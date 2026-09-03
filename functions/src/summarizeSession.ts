import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import {
  callAnthropicSession,
  streamAnthropicSession,
  MODEL,
  SessionSummaryOutput
} from "./anthropic";
import { SummarizeSessionPayload, validateSessionPayload } from "./summarizeSessionCore";

// Re-exported so `./summarizeSession` stays the name callers and tests already import.
export * from "./summarizeSessionCore";

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

export async function handleSummarizeSession(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateSessionPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as SummarizeSessionPayload;

  // Note: sessions don't use idempotency cache (the same session may legitimately
  // be re-summarized as more turns are added). Skip cache, but still consume rate limit.
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const wantsStream = req.query.stream === "true" ||
    req.headers.accept === "text/event-stream";

  const callArgs = {
    turns: payload.turns,
    language: payload.language as "vi" | "en",
    petPersona: payload.pet_persona,
    userBrief: payload.user_brief,
    petMemory: payload.pet_memory
  };

  if (wantsStream) {
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.status(200);
    if (typeof (res as any).flushHeaders === "function") {
      (res as any).flushHeaders();
    }

    try {
      for await (const event of streamAnthropicSession(anthropicClient(), callArgs)) {
        if (event.type === "json_delta") {
          writeFrame(res, "delta", { json: event.text });
        } else if (event.type === "done") {
          writeFrame(res, "done", {
            session_id: payload.session_id,
            summary: event.summary,
            model: event.model
          });
        } else if (event.type === "error") {
          writeFrame(res, "error", { error: "upstream_failure", detail: event.error });
        }
      }
    } catch (err) {
      logger.error("anthropic session stream failed", {
        uid: auth.uid, session_id: payload.session_id, err: String(err)
      });
      writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
    } finally {
      res.end();
    }
    return;
  }

  // Non-streaming fallback.
  let summary: SessionSummaryOutput;
  try {
    summary = await callAnthropicSession(anthropicClient(), callArgs);
  } catch (err) {
    logger.error("anthropic session call failed", {
      uid: auth.uid,
      session_id: payload.session_id,
      err: String(err)
    });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  res.status(200).json({
    session_id: payload.session_id,
    summary: summary,
    model: MODEL
  });
}

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}
