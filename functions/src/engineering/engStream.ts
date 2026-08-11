//
// Relay a session's events to the app as SSE.
//
// The reconnect contract is the point of this file. SSE has no replay, so a
// client that drops and reconnects would otherwise miss everything emitted
// in the gap. On every connect we open the live stream FIRST (it buffers
// from that moment), then read the full history, then tail — deduping by
// event id where the two overlap.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { toExecStep } from "./engEvents";
import { getEngClient, isSafePathSegment } from "./engClient";

/**
 * A no-op once the response can no longer take writes — either because we
 * already ended it, or because the client dropped and Node marked the
 * socket destroyed. Also swallows a synchronous write failure: `res.write`
 * can throw on an already-broken socket, and the catch block below calls
 * this for its own "error" frame with nothing above it to catch a throw.
 */
export function writeFrame(res: Response, event: string, payload: unknown): void {
  if (res.writableEnded || res.destroyed) return;
  try {
    res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
  } catch {
    // Socket died between the writability check and the write itself.
    // Nothing to do — the client is gone either way.
  }
}

/**
 * Content-free fields only: an error's constructor name, and an HTTP status
 * if the SDK error exposes one (Anthropic's `APIError.status`). Never the
 * error object, its `message`, or a stringification — an SDK error can carry
 * the request that produced it, including our API key header.
 */
function safeErrorDetail(err: unknown): { name?: string; status?: number } {
  const detail: { name?: string; status?: number } = {};
  if (err instanceof Error) detail.name = err.name;
  const status = (err as { status?: unknown } | null)?.status;
  if (typeof status === "number") detail.status = status;
  return detail;
}

/** True if `stream` exposes an abortable controller (the SDK's `Stream` does). Best-effort: a test double or a future SDK shape without one is a silent no-op, not a crash. */
function abortIfPossible(stream: unknown): void {
  const controller = (stream as { controller?: { abort?: () => void } } | null | undefined)?.controller;
  if (typeof controller?.abort === "function") controller.abort();
}

/** True the first time an id is seen. Id-less events always pass. */
export function dedupe(seen: Set<string>, event: { id?: unknown }): boolean {
  const id = typeof event.id === "string" ? event.id : null;
  if (!id) return true;
  if (seen.has(id)) return false;
  seen.add(id);
  return true;
}

/**
 * Whether to stop reading.
 *
 * `requires_action` is idle but NOT terminal — the agent is blocked on a tool
 * approval and will continue the moment one arrives. Breaking there is the
 * classic bug: the run looks finished and is actually waiting on a founder
 * who is no longer being shown anything to approve.
 */
export function isTerminal(event: unknown): boolean {
  if (typeof event !== "object" || event === null) return false;
  const e = event as Record<string, unknown>;
  if (e.type === "session.status_terminated") return true;
  if (e.type !== "session.status_idle") return false;
  const reason = (e.stop_reason as Record<string, unknown> | undefined)?.type;
  return reason !== "requires_action";
}

export async function handleEngStream(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  // `runId` is caller-supplied and gets interpolated straight into a
  // Firestore document path below. Unvalidated, a slash-bearing value makes
  // `db.doc(...)` throw synchronously on an odd resulting segment count —
  // and, this being the one Firestore read in this file that was never
  // wrapped, that throw escaped unhandled: the framework turned it into a
  // 500 AND logged the raw error. `engSendTurn`/`engWebhook` both gate on
  // this same `isSafePathSegment` rule from `./engClient`; match them here,
  // before anything touches Firestore.
  const runId = typeof req.query.runId === "string" ? req.query.runId : "";
  if (!runId || !isSafePathSegment(runId)) {
    res.status(400).json({ error: "invalid_payload", detail: "runId required" });
    return;
  }

  let runSnap: FirebaseFirestore.DocumentSnapshot;
  try {
    runSnap = await admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`).get();
  } catch (err) {
    // A transient Firestore fault, not a malformed request or a missing run —
    // ours to retry, so it must not collapse into 404 (already means "no such
    // run") or 400/401 (the caller's mistake to fix). Content-free log only:
    // reused from the relay's own error handling below, since a Firestore/SDK
    // error's raw form can carry request internals this file must never log.
    logger.error("engStream: run lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "lookup_failed" });
    return;
  }
  if (!runSnap.exists) {
    res.status(404).json({ error: "run_not_found" });
    return;
  }
  const sessionId = runSnap.data()?.sessionId as string | undefined;
  if (!sessionId) {
    res.status(409).json({ error: "run_has_no_session" });
    return;
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as unknown as { flushHeaders?: () => void }).flushHeaders === "function") {
    (res as unknown as { flushHeaders: () => void }).flushHeaders();
  }

  // True once the client is gone — closed the app, lost network, or the
  // socket itself errored. Checked at the top of both loops below so each
  // exits at its next iteration instead of consuming the upstream SDK stream
  // and calling res.write() for up to the full 3600s timeout.
  let clientGone = false;
  res.on("close", () => {
    clientGone = true;
  });
  res.on("error", () => {
    // Node emits this asynchronously instead of throwing when a write hits a
    // destroyed socket. `writeFrame` already checks writability before every
    // write; this listener exists only so the otherwise-unhandled "error"
    // event doesn't crash the function instance.
    clientGone = true;
  });

  const client = getEngClient();
  const seen = new Set<string>();

  const relay = (event: Record<string, unknown>): void => {
    const step = toExecStep(event);
    if (step) writeFrame(res, "step", step);
    if (event.type === "agent.message") {
      const blocks = Array.isArray(event.content) ? event.content : [];
      const text = blocks
        .filter((b): b is { type: string; text: string } =>
          typeof b === "object" && b !== null && (b as { type?: string }).type === "text")
        .map((b) => b.text)
        .join("");
      if (text) writeFrame(res, "message", { text });
    }
    if (event.type === "agent.tool_use" && (event as { evaluated_permission?: string }).evaluated_permission === "ask") {
      writeFrame(res, "approval", { toolUseId: event.id, name: event.name, input: event.input });
    }
  };

  let stream: Awaited<ReturnType<typeof client.beta.sessions.events.stream>> | undefined;
  try {
    // Order matters. Open the stream before listing history: the stream only
    // carries events emitted after it opens, so listing first leaves a gap
    // between the last history page and the first live event.
    stream = await client.beta.sessions.events.stream(sessionId);

    for await (const past of client.beta.sessions.events.list(sessionId)) {
      if (clientGone) break;
      const e = past as unknown as Record<string, unknown>;
      if (dedupe(seen, e)) relay(e);
    }

    for await (const live of stream) {
      if (clientGone) break;
      const e = live as unknown as Record<string, unknown>;
      // Dedupe gates the relay only. The terminal check must run even for an
      // event we already saw in history, or a run that finished before the
      // client connected never closes the stream.
      if (dedupe(seen, e)) relay(e);
      if (isTerminal(e)) {
        writeFrame(res, "done", { runId, stopReason: (e.stop_reason as { type?: string })?.type ?? "end_turn" });
        break;
      }
    }
  } catch (err) {
    // Never echo the upstream error. An SDK error can carry the request that
    // produced it, and that request carries our API key header. The founder
    // cannot act on the detail anyway, and writeFrame below can't produce an
    // unhandled rejection (it never throws) — but we do want SOME record of
    // the failure, so log a couple of content-free fields.
    logger.error("engStream: relay failed", safeErrorDetail(err));
    writeFrame(res, "error", { error: "stream_failed" });
  } finally {
    // Cancel the upstream SDK stream rather than leaving it iterating.
    // Breaking out of `for await (const live of stream)` above already does
    // this — the SDK's own generator aborts its request in a `finally` when
    // the consumer exits early — but that path never runs if the client was
    // already gone before we reached the live loop. Idempotent either way.
    abortIfPossible(stream);
    res.end();
  }
}
