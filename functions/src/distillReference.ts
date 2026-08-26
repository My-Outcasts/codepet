import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { PLAN_MODEL, cacheableSystemBlock } from "./anthropic";
import {
  REFERENCE_TOOL,
  DistillPayload,
  coercePrinciples,
  distillRequest,
  validateDistillPayload,
} from "./distillReferenceCore";

// Re-exported so `./distillReference` stays the name callers and tests already import.
export * from "./distillReferenceCore";

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

export async function handleDistillReference(
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

  const validationError = validateDistillPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as DistillPayload;

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const { system, user } = distillRequest(payload);

  let principles: string[];
  try {
    const response = await anthropicClient().messages.create({
      model: PLAN_MODEL,
      // Was 800 against a model that did not think by default; on Sonnet 5 the
      // cap covers thinking too.
      max_tokens: 2000,
      // Distillation of text already supplied. `low` is sufficient and is the
      // reason this can stay on a mid tier at all.
      output_config: { effort: "low" },
      system: [cacheableSystemBlock({ model: PLAN_MODEL, text: system, tools: REFERENCE_TOOL })],
      tools: [REFERENCE_TOOL as any],
      tool_choice: { type: "tool", name: "record_reference" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: string[] | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_reference") {
        parsed = coercePrinciples(block.input) ?? undefined;
      }
    }

    if (!parsed || parsed.length === 0) {
      throw new Error("Anthropic response missing valid record_reference tool use");
    }
    principles = parsed;
  } catch (err) {
    logger.error("anthropic distill call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  res.status(200).json({
    principles,
    model: PLAN_MODEL,
    generated_at: new Date().toISOString()
  });
}
