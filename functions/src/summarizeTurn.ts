import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { getCached, putCached } from "./cache";
import { callAnthropic, streamAnthropic, MODEL, NarrativeOutput } from "./anthropic";
import { SummarizePayload, validatePayload } from "./summarizeTurnCore";

// Re-exported so `./summarizeTurn` stays the name callers and tests already import.
export * from "./summarizeTurnCore";

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

export async function handleSummarizeTurn(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validatePayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as SummarizePayload;

  // Check Accept header or query param for streaming.
  const wantsStream = req.query.stream === "true" ||
    req.headers.accept === "text/event-stream";

  // Cache check first — does NOT consume rate limit.
  // Language is part of the key so switching vi↔en produces a fresh narrative.
  const cached = await getCached(auth.uid, payload.turn_id, payload.language);
  if (cached) {
    if (wantsStream) {
      // Deliver cache hit as a single-frame SSE stream so the client
      // code path is uniform (no need to branch on cache_hit).
      res.setHeader("Content-Type", "text/event-stream");
      res.setHeader("Cache-Control", "no-cache");
      res.setHeader("Connection", "keep-alive");
      res.status(200);
      if (typeof (res as any).flushHeaders === "function") {
        (res as any).flushHeaders();
      }
      writeFrame(res, "done", {
        turn_id: payload.turn_id,
        narrative: cached,
        model: cached.model,
        cache_hit: true
      });
      res.end();
    } else {
      res.status(200).json({
        turn_id: payload.turn_id,
        narrative: cached,
        model: cached.model,
        cache_hit: true
      });
    }
    return;
  }

  // Rate limit check.
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const callArgs = {
    prompt: payload.prompt,
    events: payload.events,
    raw_summary: payload.raw_summary,
    language: payload.language as "vi" | "en",
    petPersona: payload.pet_persona,
    user_brief: payload.user_brief,
    pet_memory: payload.pet_memory
  };

  if (wantsStream) {
    // SSE streaming path.
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.status(200);
    if (typeof (res as any).flushHeaders === "function") {
      (res as any).flushHeaders();
    }

    try {
      let finalNarrative: NarrativeOutput | undefined;
      for await (const event of streamAnthropic(anthropicClient(), callArgs)) {
        if (event.type === "json_delta") {
          writeFrame(res, "delta", { json: event.text });
        } else if (event.type === "done") {
          finalNarrative = event.narrative;
          writeFrame(res, "done", {
            turn_id: payload.turn_id,
            narrative: event.narrative,
            model: event.model,
            cache_hit: event.cache_hit ?? false
          });
        } else if (event.type === "error") {
          writeFrame(res, "error", { error: "upstream_failure", detail: event.error });
        }
      }
      // Best-effort cache write.
      if (finalNarrative) {
        try {
          await putCached(auth.uid, payload.turn_id, payload.language, { ...finalNarrative, model: MODEL });
        } catch (err) {
          logger.warn("putCached failed; narrative will not be cached", {
            uid: auth.uid, turn_id: payload.turn_id, err: String(err)
          });
        }
      }
    } catch (err) {
      logger.error("anthropic stream failed", { uid: auth.uid, turn_id: payload.turn_id, err: String(err) });
      writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
    } finally {
      res.end();
    }
    return;
  }

  // Non-streaming fallback (backward compat).
  let narrative: NarrativeOutput;
  try {
    narrative = await callAnthropic(anthropicClient(), callArgs);
  } catch (err) {
    logger.error("anthropic call failed", { uid: auth.uid, turn_id: payload.turn_id, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  try {
    await putCached(auth.uid, payload.turn_id, payload.language, { ...narrative, model: MODEL });
  } catch (err) {
    logger.warn("putCached failed; narrative will not be cached", {
      uid: auth.uid,
      turn_id: payload.turn_id,
      err: String(err)
    });
  }

  res.status(200).json({
    turn_id: payload.turn_id,
    narrative,
    model: MODEL,
    cache_hit: false
  });
}
