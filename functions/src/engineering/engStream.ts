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
import { verifyAuth } from "../auth";
import { toExecStep } from "./engEvents";
import { getEngClient } from "./engClient";

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
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

  const runId = typeof req.query.runId === "string" ? req.query.runId : "";
  if (!runId) {
    res.status(400).json({ error: "invalid_payload", detail: "runId required" });
    return;
  }

  const runRef = admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`);
  const runSnap = await runRef.get();
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

  try {
    // Order matters. Open the stream before listing history: the stream only
    // carries events emitted after it opens, so listing first leaves a gap
    // between the last history page and the first live event.
    const stream = await client.beta.sessions.events.stream(sessionId);

    for await (const past of client.beta.sessions.events.list(sessionId)) {
      const e = past as unknown as Record<string, unknown>;
      if (dedupe(seen, e)) relay(e);
    }

    for await (const live of stream) {
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
    // cannot act on the detail anyway; the server-side trace is where it belongs.
    writeFrame(res, "error", { error: "stream_failed" });
  } finally {
    res.end();
  }
}
