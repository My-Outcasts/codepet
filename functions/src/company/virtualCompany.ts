import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { checkAndIncrement } from "../rateLimit";
import { AgentCaller, POSITION_MAX_TOKENS } from "./router";
import { isFeatureEnabled } from "./killSwitch";
import { saveBlackboard } from "./blackboardStore";
import { RunPayload, runVirtualCompany, validateRunPayload } from "./orchestrate";

// Re-exported so `./virtualCompany` stays the name callers and tests already import.
export { RunPayload, validateRunPayload } from "./orchestrate";


// ─── Anthropic call seam ──────────────────────────────────────────────────────

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

/**
 * The only place in the feature that talks to the Anthropic SDK. Every agent
 * call is forced through a tool so the output is schema-validated rather than
 * parsed out of free text (spec §5.4 — text parsing breaks in production).
 */
const defaultAgentCaller: AgentCaller = async (args) => {
  const response = await anthropicClient().messages.create({
    model: args.model,
    max_tokens: args.maxTokens ?? POSITION_MAX_TOKENS,
    // Spread rather than always-present: an `effort` of undefined is still a
    // key on the wire, and ROUTER_MODEL (Haiku 4.5) errors on the field at all.
    ...(args.effort ? { output_config: { effort: args.effort } } : {}),
    system: args.system as any,
    tools: [args.tool as any],
    tool_choice: { type: "tool", name: args.toolName },
    messages: [{ role: "user", content: args.userMessage }]
  });

  const usage = {
    input: response.usage?.input_tokens ?? 0,
    output: response.usage?.output_tokens ?? 0,
    cache_read: (response.usage as any)?.cache_read_input_tokens ?? 0
  };

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === args.toolName) {
      // stop_reason travels with the result so the parse site can tell a
      // truncated object from a model that ignored the schema.
      return { input: block.input, usage, stopReason: response.stop_reason };
    }
  }
  throw new Error(`${args.agent} did not call ${args.toolName}`);
};

/**
 * Exposed for the wire-shape test only. Every other test in this feature
 * injects its own AgentCaller, which means the translation done HERE — phase
 * arguments into SDK request fields — is the one link in the chain that nothing
 * exercised. A dropped `effort` would have made the whole tiering silently dead.
 */
export const __defaultAgentCallerForTests = (): AgentCaller => defaultAgentCaller;

let _agentCaller: AgentCaller | null = null;
export function __setAgentCallerForTests(caller: AgentCaller): void {
  _agentCaller = caller;
}
export function __resetAgentCallerForTests(): void {
  _agentCaller = null;
}

// ─── SSE plumbing ─────────────────────────────────────────────────────────────

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

// ─── Handler ──────────────────────────────────────────────────────────────────

export async function handleVirtualCompanyRun(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateRunPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as RunPayload;

  if (!(await isFeatureEnabled())) {
    res.status(503).json({ error: "feature_disabled" });
    return;
  }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  try {
    await runVirtualCompany({
      payload,
      uid: auth.uid,
      runId: `run_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`,
      call: _agentCaller ?? defaultAgentCaller,
      emit: (event, data) => writeFrame(res, event, data),
      persist: saveBlackboard,
      logError: (err, runId) =>
        logger.error("virtualCompanyRun failed", { uid: auth.uid, run_id: runId, err: String(err) })
    });
  } finally {
    res.end();
  }
}
