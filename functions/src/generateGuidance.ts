import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL, cacheableSystemBlock } from "./anthropic";
import {
  GUIDANCE_TOOL,
  GuidanceOutput,
  GuidancePayload,
  coerceGuidance,
  guidanceRequest,
  validateGuidancePayload,
} from "./generateGuidanceCore";

// Re-exported so `./generateGuidance` stays the name callers and tests already import.
export * from "./generateGuidanceCore";

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

// MARK: - Handler

export async function handleGenerateGuidance(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  // Auth
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  // Validate
  const validationError = validateGuidancePayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as GuidancePayload;

  // Rate limit
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const { system, user } = guidanceRequest(payload);

  // Call Claude (non-streaming — guidance is short)
  let guidance: GuidanceOutput;
  try {
    const response = await anthropicClient().messages.create({
      model: MODEL,
      max_tokens: 800,
      system: [cacheableSystemBlock({ model: MODEL, text: system, tools: GUIDANCE_TOOL })],
      tools: [GUIDANCE_TOOL as any],
      tool_choice: { type: "tool", name: "record_guidance" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: GuidanceOutput | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_guidance") {
        parsed = coerceGuidance(block.input) ?? undefined;
      }
    }

    if (!parsed) {
      throw new Error("Anthropic response missing valid record_guidance tool use");
    }
    guidance = parsed;
  } catch (err) {
    logger.error("anthropic guidance call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  // Respond
  res.status(200).json({
    guidance,
    model: MODEL,
    generated_at: new Date().toISOString()
  });
}
