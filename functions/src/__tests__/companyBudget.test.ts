import {
  MAX_RUN_TOKENS,
  MAX_RUN_COST_USD,
  totalTokens,
  budgetState
} from "../company/budget";
import { newBlackboard, recordUsage } from "../company/blackboard";
import { FounderContext } from "../company/types";
import { AGENT_MODEL, MODEL_PRICING, SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue.",
  constraints: [],
  language: "en"
};
const fresh = () => newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });

describe("totalTokens", () => {
  test("is zero for a fresh run", () => {
    expect(totalTokens(fresh())).toBe(0);
  });

  test("sums input and output across agents but excludes cache reads", () => {
    // Cache reads bill at a tenth and are the behaviour we want to encourage —
    // counting them against the ceiling would penalise a well-cached run.
    let bb = fresh();
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 50, cache_read: 5000 });
    bb = recordUsage(bb, "finance", AGENT_MODEL, { input: 200, output: 25, cache_read: 5000 });
    expect(totalTokens(bb)).toBe(375);
  });
});

describe("budgetState", () => {
  test("a fresh run is within budget", () => {
    expect(budgetState(fresh())).toEqual({ withinBudget: true, reason: null });
  });

  test("breaches on the token ceiling with a stated reason", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: MAX_RUN_TOKENS,
      output: 1,
      cache_read: 0
    });
    const state = budgetState(bb);
    expect(state.withinBudget).toBe(false);
    expect(state.reason).toMatch(/token/i);
  });

  test("breaches on the cost ceiling with a stated reason", () => {
    // Isolate the cost ceiling from the token ceiling: 60k output tokens on the
    // top tier ($25/MTok) is exactly $1.50, while 60k is well under the 200k
    // token ceiling — so only the cost check can fire here.
    const outputTokens = Math.ceil(
      (MAX_RUN_COST_USD * 1_000_000) / MODEL_PRICING[SYNTHESIS_MODEL].outputPerMTok
    );
    expect(outputTokens).toBeLessThan(MAX_RUN_TOKENS);

    const bb = recordUsage(fresh(), "chief_of_staff", SYNTHESIS_MODEL, {
      input: 0,
      output: outputTokens,
      cache_read: 0
    });
    const state = budgetState(bb);
    expect(state.withinBudget).toBe(false);
    expect(state.reason).toMatch(/cost/i);
  });

  test("the reason names the actual numbers so the founder can see why", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: MAX_RUN_TOKENS + 1,
      output: 0,
      cache_read: 0
    });
    const reason = budgetState(bb).reason!;
    expect(reason.length).toBeGreaterThan(10);
    expect(reason).toContain(String(MAX_RUN_TOKENS));
  });

  test("a run just under the ceiling is still allowed", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: MAX_RUN_TOKENS - 1,
      output: 0,
      cache_read: 0
    });
    expect(budgetState(bb).withinBudget).toBe(true);
  });

  test("ceilings are set to plausible per-run values", () => {
    expect(MAX_RUN_TOKENS).toBeGreaterThan(50_000);
    expect(MAX_RUN_COST_USD).toBeGreaterThan(0);
    expect(MAX_RUN_COST_USD).toBeLessThan(10);
  });
});
