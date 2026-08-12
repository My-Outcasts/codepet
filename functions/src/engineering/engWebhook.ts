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
import type Anthropic from "@anthropic-ai/sdk";
import { listCostToCredits } from "./engBudget";
import { debit } from "./engBalance";
import { getEngClient, isSafePathSegment, safeErrorDetail, type RunStatus } from "./engClient";

/**
 * True when a session event is the idle-status kind, narrowing the response
 * to one this file can safely read `.stop_reason` off. A type predicate
 * rather than a cast: `events.list`'s return type is the full ~30-member
 * session-event union regardless of the `types` query filter passed at the
 * call site (the SDK can't statically know a runtime string narrowed the
 * response), so this is what lets the compiler — not an assertion — confirm
 * the narrowing is correct.
 */
function isStatusIdleEvent(
  event: Anthropic.Beta.Sessions.BetaManagedAgentsSessionEvent
): event is Anthropic.Beta.Sessions.BetaManagedAgentsSessionStatusIdleEvent {
  return event.type === "session.status_idle";
}

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

/**
 * `statusFor`, but forced terminal when the DELIVERY ITSELF says the session
 * is gone, regardless of what the last idle event's stop reason was.
 *
 * A webhook delivery's `event.data.type` is one of `session.status_idled` or
 * `session.status_terminated` (the only two this handler acts on — see the
 * early return below) — a different vocabulary from a session EVENT's own
 * `type`, which is where `stopReason` comes from. On an `idled` delivery the
 * last idle event's stop reason is trustworthy: the agent really is idle,
 * and `requires_action` really does mean "running, waiting on the founder."
 * On a `terminated` delivery that same stop reason can be stale — the
 * session already moved on and no idle event describes why it stopped for
 * good — so `requires_action` there must never be reported as "running":
 * nothing is running any more, and an interrupt sent from `engSendTurn` (a
 * founder pressing Stop) reliably produces exactly this shape, since the
 * approval pause is typically the last idle before the interrupt lands.
 * `end_turn`/`budget_reached` are left alone even on a terminated delivery:
 * a session that finished normally and was torn down afterward really did
 * finish normally, and relabelling that `failed` would be its own
 * dishonesty.
 */
export function statusForDelivery(deliveryType: string, stopReason: string | undefined): RunStatus {
  const status = statusFor(stopReason);
  if (deliveryType === "session.status_terminated" && status === "running") {
    return "failed";
  }
  return status;
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
    // identical from here. `unwrap`'s rejection is a plain `Error` with a
    // fixed message (`standardwebhooks`'s `verify`, not an SDK `APIError` —
    // see `safeErrorDetail`'s doc comment in `engClient.ts` for what that
    // type does and does not carry) rather than something that embeds the
    // request or its headers, but the message alone is not specific enough
    // to be worth logging either, so this stays a fixed string.
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
  //
  // Both wrapped in one try/catch (Finding 3): a 429/529/timeout here is
  // routine, and before this fix it sat unguarded — the framework's own
  // handler would turn that into a 500 AND log the raw error object,
  // defeating the content-free discipline the rest of this file keeps.
  // Same retryable shape as the transaction-failure catch below: log two
  // named fields via `safeErrorDetail`, respond 503, let Anthropic retry.
  let session: Awaited<ReturnType<typeof client.beta.sessions.retrieve>>;
  let idlePage: Awaited<ReturnType<typeof client.beta.sessions.events.list>>;
  try {
    session = await client.beta.sessions.retrieve(sessionId);

    // `events.list` is paginated and, unfiltered, returns ONE page in
    // chronological order — the terminal idle event is the last event of the
    // LAST page, so a plain `list(sessionId)` call (or iterating every page
    // just to find one event) is either wrong or wasteful. Ask the API for
    // exactly the event this file needs instead: newest first, filtered to
    // the idle type, one result. `engStream.ts` has a separate, correct
    // reason to iterate every page — it relays the whole transcript — so the
    // two handlers are not meant to share this call shape.
    idlePage = await client.beta.sessions.events.list(sessionId, {
      order: "desc",
      types: ["session.status_idle"],
      limit: 1
    });
  } catch (err) {
    console.error("engWebhook: session lookup failed", safeErrorDetail(err));
    res.status(503).send("");
    return;
  }
  const lastIdle = idlePage.data.find(isStatusIdleEvent);

  // Direct addressing, not a collectionGroup(sessionId) scan: `engStartRun`
  // stamps `metadata: { runId, uid }` on the session the moment it creates
  // it, and we already have the session in hand above. A collectionGroup
  // query on `sessionId` would need a COLLECTION_GROUP index this repo does
  // not declare anywhere, so the first real delivery would throw
  // FAILED_PRECONDITION — and if that happened after a dedupe marker were
  // recorded, every retry after it would be silently swallowed. No scan
  // fallback if the metadata is malformed: that means a session was created
  // by something that stamped it wrong, which is worth surfacing, not
  // papering over with a guess.
  //
  // Finding 4: this endpoint is registered org-wide, so it also receives
  // deliveries for sessions this backend never created — leftovers from an
  // earlier spike, someone else's experiment, anything. Those carry NO
  // metadata at all (the API always returns the field; an untouched session
  // has it as `{}`), and before this fix they were indistinguishable from
  // "one of ours with a broken stamp" — both produced a 500-with-log that
  // Anthropic would retry forever. A session with metadata that EXISTS but
  // is missing/malformed runId or uid IS one of ours (only `engStartRun`
  // stamps this field), and that is the real, actionable problem.
  const metadata = session.metadata;
  if (metadata == null || Object.keys(metadata).length === 0) {
    // Not one of our sessions. Nothing to fix, nothing to retry — and
    // nothing alarming to log; this is an expected, routine shape of
    // delivery for an org-wide webhook, not a fault on our side.
    res.status(204).send("");
    return;
  }
  const runId = metadata.runId;
  const uid = metadata.uid;
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

  // Finding 1: derive status from WHICH webhook delivery this is before
  // trusting the last idle event's stop reason. A `session.status_terminated`
  // delivery — what an interrupt from `engSendTurn` produces — is terminal
  // regardless of what that idle said: the last idle before a Stop is
  // typically the approval pause (`requires_action`), which `statusFor` maps
  // to "running" — and unconditionally trusting that produced a card that
  // said "running" forever after the founder pressed Stop. Only an `idled`
  // delivery gets to rely on the idle event's own stop reason.
  const status = statusForDelivery(event.data.type, lastIdle?.stop_reason?.type);

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
    // What this run has already been charged. Deliberately NOT the run
    // document: `firestore.rules` denies clients writing `engRuns` now, but
    // rules are one careless deploy from regressing and what regresses here
    // is money — silently, because a forged baseline just makes the delta 0
    // and nobody is charged. Under `engineering/` the value is unreachable by
    // any client for read or write, so a lost carve-out cannot reopen it.
    const ledgerRef = db.doc(`companies/${uid}/engineering/debits/${runId}`);
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

      // `creditsSpent` (just computed above) is cumulative for the WHOLE
      // session, but the dedupe marker above only protects a retry of THIS
      // event id. Every distinct terminal delivery — and a session with the
      // agent's `bash: always_ask` policy pauses for approval on nearly every
      // run, producing one — reaches this line with its own fresh cumulative
      // reading. Debiting `creditsSpent` directly would re-charge the running
      // total on every delivery; debiting the DELTA against what the
      // previous delivery persisted here charges each delivery only for the
      // spend that happened since. `Math.max(0, ...)` guards the direction
      // that can never be allowed to happen silently: if a reading ever came
      // back lower than what is already on record, the honest response is
      // "charge nothing this delivery", not "credit the founder back".
      const ledgerSnap = await tx.get(ledgerRef);
      const recorded = ledgerSnap.data()?.creditsSpent;
      // `Number.isFinite`, not `typeof === "number"`: NaN is a number and
      // `creditsSpent - NaN` is NaN, which `Math.max(0, NaN)` returns as NaN,
      // and `debit` would then refuse the write — a corrupted ledger entry
      // would silently stop charging this run forever.
      const previousCreditsSpent = Number.isFinite(recorded) ? (recorded as number) : 0;
      const delta = Math.max(0, creditsSpent - previousCreditsSpent);

      tx.set(seenRef, { at: admin.firestore.FieldValue.serverTimestamp() });
      // Finding 2: `endedAt` only means what its name says. `status ===
      // "running"` is the one outcome that is not an ending — the idled
      // delivery's `requires_action` case, a run deliberately paused mid-run
      // for a founder's approval — and stamping `endedAt` there told any
      // client treating it as "this run is finished" the opposite of the
      // truth, on every run that ever paused for approval (nearly all of
      // them, given the agent's `bash: always_ask` policy). The field is
      // omitted entirely rather than set to a sentinel: Firestore's Admin
      // SDK rejects `undefined` field values outright, so leaving the key
      // out of this object (not "in, but empty") is the only correct way to
      // not write it.
      const hasEnded = status !== "running";
      tx.set(
        runRef,
        {
          status,
          creditsSpent,
          ...(hasEnded ? { endedAt: admin.firestore.FieldValue.serverTimestamp() } : {})
        },
        { merge: true }
      );
      // The ledger advances with the debit, in the same transaction: a commit
      // that charged but did not advance the baseline would charge the same
      // spend again on the next delivery.
      tx.set(ledgerRef, { creditsSpent }, { merge: true });
      debit(tx, uid, delta);
      return "processed";
    });
  } catch (err) {
    // A duplicate is detected above by reading the marker inside the
    // transaction, never by catching an error — so anything that lands here
    // is a genuine infrastructure fault on a delivery we have not yet acted
    // on (first or otherwise). Acknowledging it with 204 would tell
    // Anthropic not to retry a run whose outcome we never recorded and
    // never billed. Never log `err` itself — not because it carries the
    // request that produced it (a Firestore/SDK error does not; see
    // `safeErrorDetail`'s doc comment in `engClient.ts`), but because there
    // is nothing beyond these two named fields worth logging, and naming
    // them explicitly is what keeps a future edit from reaching for the raw
    // object instead.
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
