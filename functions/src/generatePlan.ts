import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { PLAN_MODEL, cacheableSystemBlock } from "./anthropic";
import {
  PLAN_TOOL,
  PlanOutput,
  PlanPayload,
  applyTier,
  coercePlan,
  planRequest,
  validatePlanPayload,
} from "./generatePlanCore";

// Re-exported so `./generatePlan` stays the name callers and tests already import.
export * from "./generatePlanCore";
import { resolvePlanTier } from "./entitlements";

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

export async function handleGeneratePlan(
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
  const validationError = validatePlanPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as PlanPayload;

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

  const { system, user } = planRequest(payload);

  // Call Claude (non-streaming — a plan is a few hundred tokens)
  let plan: PlanOutput;
  try {
    const response = await anthropicClient().messages.create({
      model: PLAN_MODEL,
      // Was 1500 against a model that did not think by default. PLAN_MODEL is
      // Sonnet 5 now, where this cap covers thinking and plan together.
      max_tokens: 4000,
      output_config: { effort: "medium" },
      system: [cacheableSystemBlock({ model: PLAN_MODEL, text: system, tools: PLAN_TOOL })],
      tools: [PLAN_TOOL as any],
      tool_choice: { type: "tool", name: "record_plan" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: PlanOutput | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_plan") {
        parsed = coercePlan(block.input) ?? undefined;
      }
    }

    if (!parsed) {
      throw new Error("Anthropic response missing valid record_plan tool use");
    }
    plan = parsed;
  } catch (err) {
    logger.error("anthropic plan call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  // Resolve entitlement and gate (server-side — locked detail never leaves here)
  const tier = await resolvePlanTier(auth.uid);
  const { plan: gatedPlan, lockedStepCount } = applyTier(plan, tier);

  // Respond
  res.status(200).json({
    plan: gatedPlan,
    tier,
    locked_step_count: lockedStepCount,
    model: PLAN_MODEL,
    generated_at: new Date().toISOString()
  });
}
