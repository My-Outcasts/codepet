import { MODEL_PRICING } from "../anthropic";
import { AgentId, AgentPosition, Blackboard, FounderContext, TokenUsage } from "./types";

export function newBlackboard(args: {
  runId: string;
  uid: string;
  rawRequest: string;
  founder: FounderContext;
  now?: Date;
}): Blackboard {
  const raw = args.rawRequest.trim();
  return {
    run_id: args.runId,
    uid: args.uid,
    created_at: (args.now ?? new Date()).toISOString(),
    // real_question and type are filled in by the router in Phase 1. Until then
    // the raw request stands in, so a run that fails at intake still reads back.
    request: { raw, real_question: raw, type: "DECISION" },
    founder: args.founder,
    routing: null,
    positions: {},
    conflicts: [],
    negotiation: [],
    devils_advocate: null,
    synthesis: null,
    telemetry: { tokens_per_agent: {}, cost_estimate_usd: 0, stopped_reason: null }
  };
}

/**
 * Append-only. Throws rather than overwriting: a silent overwrite would let a
 * later phase rewrite what an agent actually said in Phase 2, which is exactly
 * the history the founder is being shown.
 */
export function recordPosition(
  bb: Blackboard,
  agent: AgentId,
  position: AgentPosition
): Blackboard {
  if (bb.positions[agent] !== undefined) {
    throw new Error(`position for ${agent} already recorded in run ${bb.run_id}`);
  }
  return { ...bb, positions: { ...bb.positions, [agent]: position } };
}

function costOf(model: string, usage: TokenUsage): number {
  const price = MODEL_PRICING[model];
  // An unrecognised model id must not take a run down over accounting.
  if (!price) return 0;
  const perToken = (perMTok: number) => perMTok / 1_000_000;
  return (
    usage.input * perToken(price.inputPerMTok) +
    usage.output * perToken(price.outputPerMTok) +
    // Cache reads bill at roughly 0.1x the input rate.
    usage.cache_read * perToken(price.inputPerMTok) * 0.1
  );
}

export function recordUsage(
  bb: Blackboard,
  agent: AgentId,
  model: string,
  usage: TokenUsage
): Blackboard {
  const prev = bb.telemetry.tokens_per_agent[agent] ?? {
    input: 0,
    output: 0,
    cache_read: 0
  };
  return {
    ...bb,
    telemetry: {
      ...bb.telemetry,
      tokens_per_agent: {
        ...bb.telemetry.tokens_per_agent,
        [agent]: {
          input: prev.input + usage.input,
          output: prev.output + usage.output,
          cache_read: prev.cache_read + usage.cache_read
        }
      },
      cost_estimate_usd: bb.telemetry.cost_estimate_usd + costOf(model, usage)
    }
  };
}
