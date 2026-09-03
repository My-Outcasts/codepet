import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL, cacheableSystemBlock } from "./anthropic";
import {
  OVERVIEW_TOOL,
  OverviewOutput,
  SynthesizeBriefPayload,
  buildSynthesizeUserMessage,
  synthesizeSystemPrompt,
  validateSynthesizeBriefPayload,
} from "./synthesizeBriefCore";

// Re-exported so `./synthesizeBrief` stays the name callers already import.
export * from "./synthesizeBriefCore";

// MARK: - Synthesize a complete project brief from session history.
//
// The per-session summarizer writes a one-session-grounded `project_overview`
// (thin — it only sees one session). This endpoint instead takes the WHOLE
// arc of a project (every past session summary) and synthesizes one complete
// description of what the project IS. Used by the client's one-time backfill
// so an existing project's brief box starts full, not "A macOS app".

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

export async function handleSynthesizeBrief(
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

  const validationError = validateSynthesizeBriefPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as SynthesizeBriefPayload;

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const system = synthesizeSystemPrompt(payload.language);
  const user = buildSynthesizeUserMessage(payload);

  let overview: string;
  try {
    const response = await anthropicClient().messages.create({
      model: MODEL,
      max_tokens: 600,
      system: [cacheableSystemBlock({ model: MODEL, text: system, tools: OVERVIEW_TOOL })],
      tools: [OVERVIEW_TOOL as any],
      tool_choice: { type: "tool", name: "record_overview" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: string | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_overview") {
        const input = block.input as OverviewOutput;
        if (typeof input.overview === "string" && input.overview.trim().length > 0) {
          parsed = input.overview.trim();
        }
      }
    }
    if (!parsed) throw new Error("Anthropic response missing valid record_overview tool use");
    overview = parsed;
  } catch (err) {
    logger.error("anthropic synthesizeBrief call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  res.status(200).json({
    overview,
    model: MODEL,
    generated_at: new Date().toISOString()
  });
}
