//
// Everything the founder sends into a live session: a follow-up, a tool
// approval, or a stop. One endpoint rather than three, because they are the
// same call with a different event body and the client's state machine is
// simpler for it.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import { getEngClient, isSafePathSegment } from "./engClient";

export type TurnEvent =
  | { type: "user.message"; content: Array<{ type: "text"; text: string }> }
  | { type: "user.tool_confirmation"; tool_use_id: string; result: "allow" | "deny"; deny_message?: string }
  | { type: "user.interrupt" };

export function buildTurnEvents(body: unknown): TurnEvent[] | null {
  if (typeof body !== "object" || body === null) return null;
  const b = body as Record<string, unknown>;

  if (b.interrupt === true) return [{ type: "user.interrupt" }];

  const approve = b.approve as Record<string, unknown> | undefined;
  if (approve && typeof approve.toolUseId === "string") {
    if (approve.allow === true) {
      return [{ type: "user.tool_confirmation", tool_use_id: approve.toolUseId, result: "allow" }];
    }
    const event: TurnEvent = {
      type: "user.tool_confirmation",
      tool_use_id: approve.toolUseId,
      result: "deny"
    };
    // A denial with a reason lets the agent try another way instead of
    // stalling on a wall it cannot see the shape of.
    if (typeof approve.reason === "string" && approve.reason.trim()) {
      event.deny_message = approve.reason.trim();
    }
    return [event];
  }

  const text = typeof b.text === "string" ? b.text.trim() : "";
  if (text) return [{ type: "user.message", content: [{ type: "text", text }] }];

  return null;
}

export async function handleEngSendTurn(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const runId = typeof req.body?.runId === "string" ? req.body.runId : "";
  const events = buildTurnEvents(req.body);
  // `runId` is caller-supplied and gets interpolated straight into a
  // Firestore document path below. A value containing "/" makes
  // `db.doc(...)` throw synchronously on an odd resulting segment count (and
  // on an even count is still a same-tenant path-confusion, never a
  // cross-tenant read — this subtree is already scoped to the authenticated
  // founder's own `auth.uid`). Firestore's reserved `__…__` document-id form
  // is rejected the same way `engWebhook.ts` rejects it, via the same
  // `isSafePathSegment` rule from `./engClient`. Either shape is the
  // caller's fault, so it joins the other payload-shape checks at 400,
  // before anything touches Firestore.
  if (!runId || !events || !isSafePathSegment(runId)) {
    res.status(400).json({ error: "invalid_payload", detail: "runId and one of text/approve/interrupt required" });
    return;
  }

  let runSnap: FirebaseFirestore.DocumentSnapshot;
  try {
    runSnap = await admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`).get();
  } catch (err) {
    // A transient Firestore fault, not a malformed request — ours to retry,
    // not the caller's mistake to fix. Must not collapse into 404
    // (`run_not_found` already means "no such run" and the client renders it
    // as an offer to start a new one) or hang the caller until their own
    // timeout. Content-free log only: not because the SDK/Firestore error's
    // `err` object carries the request that produced it (it doesn't — see
    // `safeErrorDetail`'s doc comment in `engClient.ts`), but because there
    // is no diagnostic value in logging more than these two named fields,
    // and picking them explicitly is what keeps a future edit from reaching
    // for the raw object instead.
    console.error("engSendTurn: run lookup failed", {
      code: (err as { code?: unknown })?.code,
      name: (err as { name?: unknown })?.name
    });
    res.status(503).json({ error: "lookup_failed" });
    return;
  }
  const sessionId = runSnap.data()?.sessionId as string | undefined;
  if (!runSnap.exists || !sessionId) {
    res.status(404).json({ error: "run_not_found" });
    return;
  }

  try {
    await getEngClient().beta.sessions.events.send(sessionId, { events });
  } catch (err) {
    // A session paused at its budget rejects anything that starts new work.
    // Surface that as its own state rather than a generic upstream failure —
    // the client turns it into "raise the cap", not "something broke".
    // Inspecting the error server-side is fine; echoing it to the client is
    // not. Not because the SDK error carries the request we made (it
    // doesn't — see `safeErrorDetail`'s doc comment in `engClient.ts`), but
    // because its response body is not something a founder needs or should
    // see verbatim, so `detail` stays on this side of the wire regardless.
    const detail = String(err);
    if (detail.includes("budget")) {
      res.status(409).json({ error: "budget_reached" });
      return;
    }
    res.status(502).json({ error: "send_failed" });
    return;
  }

  res.status(200).json({ ok: true });
}
