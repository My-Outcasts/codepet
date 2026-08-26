/**
 * The virtual company run itself: intake, the independent pass, conflict detection,
 * negotiation, the red team, synthesis — and the exact SSE frame order the client contract
 * (`docs/superpowers/specs/virtual-company-sse-contract.md`) depends on.
 *
 * **Why this is not in the handler any more.** The same run has to be reachable from the
 * founder's own Claude Code, which has no `Response` to write to, no Firestore to persist
 * to, and no uid to authenticate. Every one of those is now injected, so there is ONE
 * orchestration and the local path cannot drift from the deployed one — which matters more
 * here than anywhere else in this feature, because the frame order IS the contract.
 *
 * What stayed in the handler: auth, payload validation, the rate limit, the kill switch, and
 * the SSE headers. All four are properties of being an HTTP endpoint, and the local path has
 * a different, honest answer for each (the founder owns the machine, so there is nobody to
 * authenticate, nothing to rate-limit, and no remote switch).
 *
 * The ceilings in `budgetState` are NOT relaxed for the local path. They exist to stop a
 * runaway loop, and a runaway loop on the founder's own plan is still a runaway loop.
 */

import { AgentCaller } from "./router";
import { runIntake } from "./router";
import { runIndependentPass } from "./independentPass";
import { detectConflicts, needsNegotiation } from "./conflicts";
import { runNegotiation } from "./negotiation";
import { runDevilsAdvocate, shouldInvokeDevilsAdvocate } from "./devilsAdvocate";
import { runSynthesis } from "./synthesis";
import { budgetState } from "./budget";
import { newBlackboard, recordPosition, recordUsage } from "./blackboard";
import { ROUTER_MODEL } from "../anthropic";
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

/** One SSE frame. The cloud path writes it to a `Response`, the local path to stdout. */
export type RunEmit = (event: string, payload: unknown) => void;

function agentMeta(agent: AgentId) {
  return { agent_id: agent, department_key: AGENT_DEPARTMENT_KEY[agent] };
}

export async function runVirtualCompany(args: {
  payload: RunPayload;
  /** Whose run this is. The local path passes the company id; there is no auth to derive it from. */
  uid: string;
  runId: string;
  call: AgentCaller;
  emit: RunEmit;
  /** Firestore on the cloud path; a no-op locally, where there is nothing to write to. */
  persist: (bb: Blackboard) => Promise<void>;
  /** Somewhere to record a failed run. `logger.error` in the CF, stderr locally. */
  logError?: (err: unknown, runId: string) => void;
}): Promise<void> {
  const { payload, runId, call, emit, persist } = args;
  const founder: FounderContext = {
    profile: payload.founder.profile,
    stage: payload.founder.stage,
    constraints: payload.founder.constraints,
    language: payload.language
  };
  let bb: Blackboard = newBlackboard({
    runId,
    uid: args.uid,
    rawRequest: payload.request,
    founder
  });

  /** Emits run_stopped and returns true when the budget is spent. */
  const stopIfOverBudget = (): boolean => {
    const state = budgetState(bb);
    if (state.withinBudget) return false;
    bb = { ...bb, telemetry: { ...bb.telemetry, stopped_reason: state.reason } };
    // Partial result with a stated reason — never a silent truncation.
    emit("run_stopped", { run_id: runId, reason: state.reason });
    return true;
  };

  const finish = async (unresolved: boolean, skipped: string | null): Promise<void> => {
    emit("telemetry", bb.telemetry);
    emit("done", { run_id: runId, unresolved, skipped });
    await persist(bb);
  };

  try {
    emit("run_started", { run_id: runId });

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
    emit("routing", {
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
      emit("agent_start", agentMeta(agent));
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
        emit("agent_position", {
          ...agentMeta(result.agent),
          position: result.position
        });
      } else {
        // Graceful degradation: this column errors, the run continues.
        emit("agent_error", {
          ...agentMeta(result.agent),
          error: result.error ?? "unknown"
        });
      }
    }

    // ── Phase 3: conflict detection — pure code, no LLM ──
    const conflicts = detectConflicts(bb.positions);
    bb = { ...bb, conflicts };
    emit("conflicts", { conflicts });

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
        emit("negotiation_round", round);
      }
    }

    // ── Phase 4b: red team ──
    const wantsRedTeam = shouldInvokeDevilsAdvocate({
      positions: bb.positions,
      conflicts,
      founderRequested: payload.stress_test === true
    });
    if (wantsRedTeam && !stopIfOverBudget()) {
      emit("agent_start", agentMeta("devils_advocate"));
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
        emit("devils_advocate", {
          ...agentMeta("devils_advocate"),
          verdict: redTeam.verdict
        });
      } catch (err) {
        // The red team is a safeguard, not a dependency — losing it must not
        // cost the founder the brief.
        emit("agent_error", {
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
    emit("brief", synthesis.brief);

    await finish(synthesis.brief.unresolved, null);
  } catch (err) {
    args.logError?.(err, runId);
    emit("error", { error: "upstream_failure", detail: String(err) });
    try {
      await persist(bb);
    } catch {
      // Persisting a failed run is best-effort; the client already has the error.
    }
  }
}
