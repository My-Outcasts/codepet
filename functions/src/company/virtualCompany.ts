import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { checkAndIncrement } from "../rateLimit";
import { ROUTER_MODEL } from "../anthropic";
import { AgentCaller, POSITION_MAX_TOKENS, runIntake } from "./router";
import { runIndependentPass } from "./independentPass";
import { detectConflicts, needsNegotiation } from "./conflicts";
import { runNegotiation } from "./negotiation";
import { runDevilsAdvocate, shouldInvokeDevilsAdvocate } from "./devilsAdvocate";
import { runSynthesis } from "./synthesis";
import { budgetState, isFeatureEnabled } from "./budget";
import { newBlackboard, recordPosition, recordUsage, saveBlackboard } from "./blackboard";
import { AGENT_DEPARTMENT_KEY, AgentId, Blackboard, FounderContext } from "./types";

const MAX_REQUEST_CHARS = 4000;

export interface RunPayload {
  request: string;
  language: "vi" | "en";
  founder: { profile: string; stage: string; constraints: string[] };
  stress_test?: boolean;
}

export function validateRunPayload(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return "body required";
  const b = body as Record<string, unknown>;

  if (typeof b.request !== "string" || b.request.trim().length === 0) {
    return "request required";
  }
  if (b.request.length > MAX_REQUEST_CHARS) {
    return `request exceeds ${MAX_REQUEST_CHARS} characters`;
  }
  if (b.language !== "vi" && b.language !== "en") {
    return "language must be 'vi' or 'en'";
  }

  const founder = b.founder;
  if (typeof founder !== "object" || founder === null) return "founder required";
  const f = founder as Record<string, unknown>;
  if (typeof f.profile !== "string") return "founder.profile must be a string";
  if (typeof f.stage !== "string") return "founder.stage must be a string";
  if (!Array.isArray(f.constraints)) return "founder.constraints must be an array";
  if (!f.constraints.every((c) => typeof c === "string")) {
    return "founder.constraints must contain only strings";
  }

  if (b.stress_test !== undefined && typeof b.stress_test !== "boolean") {
    return "stress_test must be a boolean";
  }
  return null;
}

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

function agentMeta(agent: AgentId) {
  return { agent_id: agent, department_key: AGENT_DEPARTMENT_KEY[agent] };
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

  const founder: FounderContext = {
    profile: payload.founder.profile,
    stage: payload.founder.stage,
    constraints: payload.founder.constraints,
    language: payload.language
  };
  const runId = `run_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  let bb: Blackboard = newBlackboard({
    runId,
    uid: auth.uid,
    rawRequest: payload.request,
    founder
  });
  const call: AgentCaller = _agentCaller ?? defaultAgentCaller;

  /** Emits run_stopped and returns true when the budget is spent. */
  const stopIfOverBudget = (): boolean => {
    const state = budgetState(bb);
    if (state.withinBudget) return false;
    bb = { ...bb, telemetry: { ...bb.telemetry, stopped_reason: state.reason } };
    // Partial result with a stated reason — never a silent truncation.
    writeFrame(res, "run_stopped", { run_id: runId, reason: state.reason });
    return true;
  };

  const finish = async (unresolved: boolean, skipped: string | null): Promise<void> => {
    writeFrame(res, "telemetry", bb.telemetry);
    writeFrame(res, "done", { run_id: runId, unresolved, skipped });
    await saveBlackboard(bb);
  };

  try {
    writeFrame(res, "run_started", { run_id: runId });

    // ── Phase 1: intake ──
    const intake = await runIntake({ founder, rawRequest: payload.request, call });
    bb = recordUsage(bb, "chief_of_staff", ROUTER_MODEL, intake.usage);
    bb = {
      ...bb,
      routing: intake.routing,
      request: {
        raw: bb.request.raw,
        real_question: intake.routing.real_question,
        type: intake.routing.request_type
      }
    };
    writeFrame(res, "routing", {
      ...intake.routing,
      agent_meta: intake.routing.agents.map(agentMeta)
    });

    // ── Escape hatch: skip phases 2-5 entirely (spec §2.2 Phase 1) ──
    if (intake.routing.decision !== "multi_agent") {
      await finish(false, intake.routing.decision);
      return;
    }

    if (stopIfOverBudget()) {
      await finish(false, null);
      return;
    }

    // ── Phase 2: independent pass, mutually blind ──
    const departmentAgents = intake.routing.agents.filter((a) => a !== "devils_advocate");
    // Emitted before any position arrives, so the client can open every column
    // at once — that simultaneity is what reads as a room thinking.
    for (const agent of departmentAgents) {
      writeFrame(res, "agent_start", agentMeta(agent));
    }

    const pass = await runIndependentPass({
      founder,
      rawRequest: payload.request,
      realQuestion: intake.routing.real_question,
      agents: departmentAgents,
      call
    });

    for (const result of pass.results) {
      bb = recordUsage(bb, result.agent, result.model, result.usage);
      if (result.position) {
        bb = recordPosition(bb, result.agent, result.position);
        writeFrame(res, "agent_position", {
          ...agentMeta(result.agent),
          position: result.position
        });
      } else {
        // Graceful degradation: this column errors, the run continues.
        writeFrame(res, "agent_error", {
          ...agentMeta(result.agent),
          error: result.error ?? "unknown"
        });
      }
    }

    // ── Phase 3: conflict detection — pure code, no LLM ──
    const conflicts = detectConflicts(bb.positions);
    bb = { ...bb, conflicts };
    writeFrame(res, "conflicts", { conflicts });

    // ── Phase 4: negotiation, only when there is something to debate ──
    let unresolved = false;
    if (needsNegotiation(conflicts) && !stopIfOverBudget()) {
      const negotiation = await runNegotiation({
        founder,
        rawRequest: payload.request,
        realQuestion: intake.routing.real_question,
        positions: bb.positions,
        conflicts,
        call
      });
      for (const u of negotiation.usages) {
        bb = recordUsage(bb, u.agent, u.model, u.usage);
      }
      bb = { ...bb, negotiation: negotiation.rounds };
      unresolved = negotiation.unresolved;
      for (const round of negotiation.rounds) {
        writeFrame(res, "negotiation_round", round);
      }
    }

    // ── Phase 4b: red team ──
    const wantsRedTeam = shouldInvokeDevilsAdvocate({
      positions: bb.positions,
      conflicts,
      founderRequested: payload.stress_test === true
    });
    if (wantsRedTeam && !stopIfOverBudget()) {
      writeFrame(res, "agent_start", agentMeta("devils_advocate"));
      try {
        const redTeam = await runDevilsAdvocate({
          founder,
          rawRequest: payload.request,
          realQuestion: intake.routing.real_question,
          positions: bb.positions,
          call
        });
        bb = recordUsage(bb, "devils_advocate", redTeam.model, redTeam.usage);
        bb = { ...bb, devils_advocate: redTeam.verdict };
        writeFrame(res, "devils_advocate", {
          ...agentMeta("devils_advocate"),
          verdict: redTeam.verdict
        });
      } catch (err) {
        // The red team is a safeguard, not a dependency — losing it must not
        // cost the founder the brief.
        writeFrame(res, "agent_error", {
          ...agentMeta("devils_advocate"),
          error: String(err)
        });
      }
    }

    // ── Phase 5: synthesis ──
    if (stopIfOverBudget()) {
      await finish(unresolved, null);
      return;
    }

    const synthesis = await runSynthesis({
      founder,
      rawRequest: payload.request,
      realQuestion: intake.routing.real_question,
      positions: bb.positions,
      conflicts,
      negotiation: bb.negotiation,
      devilsAdvocate: bb.devils_advocate,
      unresolved,
      call
    });
    bb = recordUsage(bb, "chief_of_staff", synthesis.model, synthesis.usage);
    bb = { ...bb, synthesis: synthesis.brief };
    writeFrame(res, "brief", synthesis.brief);

    await finish(synthesis.brief.unresolved, null);
  } catch (err) {
    logger.error("virtualCompanyRun failed", {
      uid: auth.uid,
      run_id: runId,
      err: String(err)
    });
    writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
    try {
      await saveBlackboard(bb);
    } catch {
      // Persisting a failed run is best-effort; the client already has the error.
    }
  } finally {
    res.end();
  }
}
