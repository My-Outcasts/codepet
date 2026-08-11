//
// The durable half of a run.
//
// engStream only exists while the app holds a connection. This endpoint is
// what makes a run survive the founder quitting Codepet: Anthropic posts the
// session's terminal transition here, we fetch the finished session, debit
// the credits it actually spent, and write the outcome. Unauthenticated by
// necessity — Anthropic is the caller — so the HMAC signature is the only
// thing standing between this and a forged run record.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { listCostToCredits } from "./engBudget";
import { getEngClient, isSafePathSegment, type RunStatus } from "./engClient";

/**
 * A session's stop reason → the run status the card renders.
 *
 * `budget_reached` gets its own status rather than folding into `failed`.
 * The session is paused, not dead: raising the budget resumes the work in
 * place. Telling a founder their run failed when it is sitting there intact
 * would make them start over and pay twice.
 *
 * Unknown reasons map to `failed`, not `reviewing`. If Anthropic adds a stop
 * reason we have not handled, the honest read is "we do not know that this
 * finished", not a card inviting a founder to ship an unverified diff.
 */
export function statusFor(stopReason: string | undefined): RunStatus {
  switch (stopReason) {
    case "end_turn":
      return "reviewing";
    case "budget_reached":
      return "budgetReached";
    case "requires_action":
      return "running";
    default:
      return "failed";
  }
}

// `runId` and `uid` come from a remote session's caller-supplied metadata —
// not from anything this process mints — and get interpolated straight into
// a Firestore document path (`companies/{uid}/engRuns/{runId}`). Neither
// failure mode `isSafePathSegment` (in `./engClient`) guards against is
// acceptable on an HMAC-only endpoint that moves money, so both values are
// checked before they are used for anything.

export async function handleEngWebhook(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const client = getEngClient();
  let event: { id: string; data: { type: string; id: string } };
  try {
    // Verifies the HMAC and rejects a stale timestamp. `req.rawBody` — not
    // req.body — because re-serialising the JSON changes the bytes the MAC
    // was computed over.
    const raw = (req as unknown as { rawBody?: Buffer }).rawBody?.toString("utf8") ?? "";
    event = (await client.beta.webhooks.unwrap(raw, {
      headers: req.headers as Record<string, string>
    })) as typeof event;
  } catch {
    // Content-free: a rotated signing key and a forged request look
    // identical from here, but the SDK's rejection can carry the raw
    // request/headers it was given, so nothing about it is logged.
    console.error("engWebhook: signature verification failed");
    res.status(400).send("invalid signature");
    return;
  }

  if (event.data.type !== "session.status_idled" && event.data.type !== "session.status_terminated") {
    // Nothing to dedupe: an event type we never act on has no side effect to
    // protect, in either delivery.
    res.status(204).send("");
    return;
  }

  const sessionId = event.data.id;

  // These two calls hit Anthropic's API, not Firestore — they cannot live
  // inside a Firestore transaction, so they happen first, unconditionally,
  // on every delivery including retries. That is safe only because they are
  // pure reads: repeating them costs a round trip, nothing else. Everything
  // that must not repeat (the run write, the debit) happens below, inside
  // one transaction.
  const session = (await client.beta.sessions.retrieve(sessionId)) as unknown as {
    usage?: { list_cost?: { amount?: string } };
    metadata?: { runId?: unknown; uid?: unknown };
  };
  const events = await client.beta.sessions.events.list(sessionId);
  const lastIdle = [...events.data]
    .reverse()
    .find((e) => (e as unknown as { type?: string }).type === "session.status_idle") as
    | { stop_reason?: { type?: string } }
    | undefined;

  // Direct addressing, not a collectionGroup(sessionId) scan: `engStartRun`
  // stamps `metadata: { runId, uid }` on the session the moment it creates
  // it, and we already have the session in hand above. A collectionGroup
  // query on `sessionId` would need a COLLECTION_GROUP index this repo does
  // not declare anywhere, so the first real delivery would throw
  // FAILED_PRECONDITION — and if that happened after a dedupe marker were
  // recorded, every retry after it would be silently swallowed. No scan
  // fallback if the metadata is missing or malformed: that means a session
  // was created by something that did not stamp it, which is worth
  // surfacing, not papering over with a guess.
  const runId = session.metadata?.runId;
  const uid = session.metadata?.uid;
  if (
    typeof runId !== "string" ||
    typeof uid !== "string" ||
    !isSafePathSegment(runId) ||
    !isSafePathSegment(uid)
  ) {
    // Malformed or unsafe caller metadata, not a Firestore fault — nothing
    // above this point has touched Firestore, so 500 rather than the 503 the
    // transactional region below returns on a genuine infrastructure fault.
    // A 503 there means "our infrastructure faulted, a blind retry might
    // help"; a 500 here means "the data itself is bad", and retrying the
    // identical bytes cannot fix that. Anthropic retries either 5xx the same
    // way, so the split is diagnostic rather than behavioural — but
    // conflating them would send an operator to the wrong runbook.
    console.error("engWebhook: session has missing or unsafe runId/uid metadata", { sessionId });
    res.status(500).send("");
    return;
  }

  const cents = Number(session.usage?.list_cost?.amount ?? "0");
  const creditsSpent = listCostToCredits(Number.isFinite(cents) ? cents : 0);
  const status = statusFor(lastIdle?.stop_reason?.type);

  const db = admin.firestore();
  const seenRef = db.doc(`webhookEvents/${event.id}`);

  // Everything that must happen exactly once — the dedupe check, the run
  // write, and the credit debit — lives in one transaction. A delivery that
  // fails partway through (anywhere after this point) commits nothing: the
  // marker is not recorded unless the debit is too, so a retry finds the
  // work either fully done (marker present, short-circuits below) or fully
  // undone (marker absent, redoes it). At-most-once — writing the marker
  // before the work — is what let a mid-flight failure permanently skip a
  // billed run; this is the fix.
  //
  // `runRef`/`companyRef` are constructed in here too, not above: `uid` and
  // `runId` are validated by `isSafePathSegment` before this point, but
  // building the path from them is kept inside this protected region as a
  // second line of defence — if some case that validation missed still made
  // `db.doc(...)` throw, that throw lands in the `catch` below and produces
  // the same clean 503 as any other fault, instead of escaping unhandled.
  let outcome: "processed" | "duplicate" | "unmatched";
  try {
    const runRef = db.doc(`companies/${uid}/engRuns/${runId}`);
    const companyRef = db.doc(`companies/${uid}`);
    outcome = await db.runTransaction(async (tx) => {
      const seenSnap = await tx.get(seenRef);
      if (seenSnap.exists) {
        return "duplicate";
      }

      const runSnap = await tx.get(runRef);
      if (!runSnap.exists) {
        // The session pointed at a run that isn't there — deleted, or the
        // metadata refers to something that never existed. Retrying will
        // not make it exist, so this event is "handled" (marker recorded)
        // without ever touching the debit.
        tx.set(seenRef, { at: admin.firestore.FieldValue.serverTimestamp() });
        return "unmatched";
      }

      tx.set(seenRef, { at: admin.firestore.FieldValue.serverTimestamp() });
      tx.set(
        runRef,
        {
          status,
          creditsSpent,
          endedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
      );
      tx.set(companyRef, { credits: admin.firestore.FieldValue.increment(-creditsSpent) }, { merge: true });
      return "processed";
    });
  } catch (err) {
    // A duplicate is detected above by reading the marker inside the
    // transaction, never by catching an error — so anything that lands here
    // is a genuine infrastructure fault on a delivery we have not yet acted
    // on (first or otherwise). Acknowledging it with 204 would tell
    // Anthropic not to retry a run whose outcome we never recorded and
    // never billed. Never log `err` itself: it can carry the request that
    // produced it.
    console.error("engWebhook: outcome transaction failed", {
      code: (err as { code?: unknown })?.code,
      name: (err as { name?: unknown })?.name
    });
    res.status(503).send("");
    return;
  }

  if (outcome === "unmatched") {
    console.error("engWebhook: no run found at the session's metadata address", { runId, uid });
  }

  res.status(204).send("");
}
