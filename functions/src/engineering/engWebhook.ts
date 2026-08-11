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
import { getEngClient, type RunStatus } from "./engClient";

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
    res.status(400).send("invalid signature");
    return;
  }

  const db = admin.firestore();

  // Deliveries retry, and the same event id arrives more than once. A
  // create-if-absent write is the dedupe: the second delivery loses the race
  // and returns early rather than debiting the founder twice.
  const seenRef = db.doc(`webhookEvents/${event.id}`);
  try {
    await seenRef.create({ at: admin.firestore.FieldValue.serverTimestamp() });
  } catch {
    res.status(204).send("");
    return;
  }

  if (event.data.type !== "session.status_idled" && event.data.type !== "session.status_terminated") {
    res.status(204).send("");
    return;
  }

  const sessionId = event.data.id;
  const matches = await db.collectionGroup("engRuns").where("sessionId", "==", sessionId).limit(1).get();
  if (matches.empty) {
    // Not ours, or the run record was deleted. Acknowledge — retrying will
    // not make it exist.
    res.status(204).send("");
    return;
  }
  const runRef = matches.docs[0].ref;

  const session = (await client.beta.sessions.retrieve(sessionId)) as unknown as {
    usage?: { list_cost?: { amount?: string } };
  };
  const events = await client.beta.sessions.events.list(sessionId);
  const lastIdle = [...events.data]
    .reverse()
    .find((e) => (e as unknown as { type?: string }).type === "session.status_idle") as
    | { stop_reason?: { type?: string } }
    | undefined;

  const cents = Number(session.usage?.list_cost?.amount ?? "0");
  const creditsSpent = listCostToCredits(Number.isFinite(cents) ? cents : 0);

  await runRef.set(
    {
      status: statusFor(lastIdle?.stop_reason?.type),
      creditsSpent,
      endedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  await runRef.parent.parent!.set(
    { credits: admin.firestore.FieldValue.increment(-creditsSpent) },
    { merge: true }
  );

  res.status(204).send("");
}
