import { newBlackboard, recordPosition, recordUsage } from "../company/blackboard";
import { AgentPosition, FounderContext } from "../company/types";
import { AGENT_MODEL, MODEL_PRICING } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};

function pos(overrides: Partial<AgentPosition> = {}): AgentPosition {
  return {
    stance: "proceed",
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 3,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

const fresh = () => newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });

describe("newBlackboard", () => {
  test("starts empty with the request recorded verbatim", () => {
    const bb = newBlackboard({
      runId: "r1",
      uid: "u1",
      rawRequest: "  Should I price it?  ",
      founder,
      now: new Date("2026-07-29T00:00:00Z")
    });
    expect(bb.run_id).toBe("r1");
    expect(bb.uid).toBe("u1");
    expect(bb.request.raw).toBe("Should I price it?");
    expect(bb.routing).toBeNull();
    expect(bb.positions).toEqual({});
    expect(bb.conflicts).toEqual([]);
    expect(bb.negotiation).toEqual([]);
    expect(bb.devils_advocate).toBeNull();
    expect(bb.synthesis).toBeNull();
    expect(bb.created_at).toBe("2026-07-29T00:00:00.000Z");
  });

  test("stands real_question in as the raw request until the router fills it", () => {
    // A run that fails during intake must still read back sensibly.
    const bb = newBlackboard({ runId: "r1", uid: "u1", rawRequest: "Price it?", founder });
    expect(bb.request.real_question).toBe("Price it?");
    expect(bb.request.type).toBe("DECISION");
  });

  test("telemetry starts at zero with no stop reason", () => {
    const bb = fresh();
    expect(bb.telemetry.cost_estimate_usd).toBe(0);
    expect(bb.telemetry.tokens_per_agent).toEqual({});
    expect(bb.telemetry.stopped_reason).toBeNull();
  });
});

describe("recordPosition", () => {
  test("adds a position without mutating the input blackboard", () => {
    const bb = fresh();
    const next = recordPosition(bb, "product", pos({ position: "ship the smallest test" }));
    expect(next.positions.product?.position).toBe("ship the smallest test");
    expect(bb.positions.product).toBeUndefined();
  });

  test("is append-only — a second write for the same agent throws", () => {
    // Overwriting would let a later phase quietly rewrite what an agent said in
    // Phase 2, which is exactly the history the founder is shown.
    const bb = recordPosition(fresh(), "product", pos());
    expect(() => recordPosition(bb, "product", pos({ position: "changed" }))).toThrow(
      /already recorded/i
    );
  });

  test("allows different agents to record independently", () => {
    let bb = recordPosition(fresh(), "product", pos({ position: "a" }));
    bb = recordPosition(bb, "finance", pos({ position: "b" }));
    expect(bb.positions.product?.position).toBe("a");
    expect(bb.positions.finance?.position).toBe("b");
  });
});

describe("recordUsage", () => {
  test("accumulates tokens per agent", () => {
    let bb = fresh();
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 50, cache_read: 900 });
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 10, output: 5, cache_read: 0 });
    expect(bb.telemetry.tokens_per_agent.product).toEqual({
      input: 110,
      output: 55,
      cache_read: 900
    });
  });

  test("keeps agents separate", () => {
    let bb = fresh();
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 0, cache_read: 0 });
    bb = recordUsage(bb, "finance", AGENT_MODEL, { input: 200, output: 0, cache_read: 0 });
    expect(bb.telemetry.tokens_per_agent.product?.input).toBe(100);
    expect(bb.telemetry.tokens_per_agent.finance?.input).toBe(200);
  });

  test("folds a running cost estimate using the pricing table", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: 1_000_000,
      output: 0,
      cache_read: 0
    });
    expect(bb.telemetry.cost_estimate_usd).toBeCloseTo(
      MODEL_PRICING[AGENT_MODEL].inputPerMTok,
      5
    );
  });

  test("prices cache reads at a tenth of input", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: 0,
      output: 0,
      cache_read: 1_000_000
    });
    expect(bb.telemetry.cost_estimate_usd).toBeCloseTo(
      MODEL_PRICING[AGENT_MODEL].inputPerMTok * 0.1,
      5
    );
  });

  test("an unknown model contributes no cost rather than throwing", () => {
    // A newly released model id must not take a run down over accounting.
    const bb = recordUsage(fresh(), "product", "some-future-model", {
      input: 1_000_000,
      output: 1_000_000,
      cache_read: 0
    });
    expect(bb.telemetry.cost_estimate_usd).toBe(0);
  });

  test("does not mutate the input blackboard", () => {
    const bb = fresh();
    recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 50, cache_read: 0 });
    expect(bb.telemetry.tokens_per_agent.product).toBeUndefined();
    expect(bb.telemetry.cost_estimate_usd).toBe(0);
  });
});
