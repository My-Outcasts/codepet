import {
  DEVILS_ADVOCATE_TOOL,
  parseDevilsAdvocateInput,
  shouldInvokeDevilsAdvocate,
  runDevilsAdvocate
} from "../company/devilsAdvocate";
import { AgentPosition, Conflict, FounderContext, TokenUsage } from "../company/types";
import { SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function pos(overrides: Partial<AgentPosition> = {}): AgentPosition {
  return {
    stance: "proceed",
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 5,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

const aligned: Conflict[] = [{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }];
const conflicted: Conflict[] = [{ a: "product", b: "finance", kind: "CONFLICT", reason: "" }];

function verdictInput(overrides: Record<string, unknown> = {}) {
  return {
    load_bearing_assumption: "That the beta cohort represents the paying market.",
    how_it_could_be_false: "The beta was recruited from the founder's own network.",
    cheapest_test: "Put the price in front of 20 strangers from a cold channel.",
    failure_post_mortem:
      "Twelve months on, seats sold to nobody outside the founder's network and the pricing page never converted a cold visitor.",
    who_is_not_in_the_room: "The user who churns silently without ever complaining.",
    objections: ["The sample is the founder's friends.", "No cold-channel evidence exists."],
    plan_is_sound: false,
    ...overrides
  };
}

describe("shouldInvokeDevilsAdvocate", () => {
  test("fires when the room agrees with high confidence and thin evidence", () => {
    // The whole point: agreement is when nobody is checking the premise.
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos({ confidence: 5 }), finance: pos({ confidence: 4 }) },
        conflicts: aligned
      })
    ).toBe(true);
  });

  test("does not fire when the departments already disagree", () => {
    // A live conflict already gives the founder the tension they need.
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos(), finance: pos({ stance: "do_not_proceed" }) },
        conflicts: conflicted
      })
    ).toBe(false);
  });

  test("does not fire on a BLOCKER either", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos(), finance: pos({ hard_blocker: "no" }) },
        conflicts: [{ a: "product", b: "finance", kind: "BLOCKER", reason: "" }]
      })
    ).toBe(false);
  });

  test("does not fire when the room agrees but confidence is low", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos({ confidence: 2 }), finance: pos({ confidence: 2 }) },
        conflicts: aligned
      })
    ).toBe(false);
  });

  test("does not fire when agreement rests on named evidence", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: {
          product: pos({ confidence: 5, evidence_needed: ["cold-channel conversion"] }),
          finance: pos({ confidence: 5, evidence_needed: ["month-2 retention"] })
        },
        conflicts: aligned
      })
    ).toBe(false);
  });

  test("fires when only one side named evidence", () => {
    // Thin evidence anywhere in an over-confident room is enough of a smell.
    expect(
      shouldInvokeDevilsAdvocate({
        positions: {
          product: pos({ confidence: 5, evidence_needed: ["cold-channel conversion"] }),
          finance: pos({ confidence: 5, evidence_needed: [] })
        },
        conflicts: aligned
      })
    ).toBe(true);
  });

  test("always fires when the founder explicitly asks for a stress test", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos(), finance: pos({ stance: "do_not_proceed" }) },
        conflicts: conflicted,
        founderRequested: true
      })
    ).toBe(true);
  });

  test("does not fire with fewer than two positions on record", () => {
    expect(shouldInvokeDevilsAdvocate({ positions: { product: pos() }, conflicts: [] })).toBe(
      false
    );
    expect(shouldInvokeDevilsAdvocate({ positions: {}, conflicts: [] })).toBe(false);
  });
});

describe("parseDevilsAdvocateInput", () => {
  test("accepts a well-formed verdict", () => {
    const result = parseDevilsAdvocateInput(verdictInput());
    expect("error" in result).toBe(false);
    expect((result as any).objections).toHaveLength(2);
  });

  test("requires a load-bearing assumption", () => {
    expect(parseDevilsAdvocateInput(verdictInput({ load_bearing_assumption: " " }))).toEqual({
      error: expect.stringMatching(/load_bearing_assumption/)
    });
  });

  test("requires a cheapest test — every objection must be actionable", () => {
    expect(parseDevilsAdvocateInput(verdictInput({ cheapest_test: "" }))).toEqual({
      error: expect.stringMatching(/cheapest_test/)
    });
  });

  test("requires a failure post-mortem", () => {
    expect(parseDevilsAdvocateInput(verdictInput({ failure_post_mortem: "" }))).toEqual({
      error: expect.stringMatching(/failure_post_mortem/)
    });
  });

  test("accepts a sound-plan verdict with no objections", () => {
    // Spec §3.8: a red team that always finds fatal flaws is noise.
    const result = parseDevilsAdvocateInput(
      verdictInput({ plan_is_sound: true, objections: [] })
    ) as any;
    expect(result.plan_is_sound).toBe(true);
    expect(result.objections).toEqual([]);
  });

  test("treats a non-boolean plan_is_sound as not sound", () => {
    const result = parseDevilsAdvocateInput(verdictInput({ plan_is_sound: "yes" })) as any;
    expect(result.plan_is_sound).toBe(false);
  });

  test("rejects a non-object input", () => {
    expect(parseDevilsAdvocateInput(null)).toEqual({ error: expect.any(String) });
  });
});

describe("runDevilsAdvocate", () => {
  test("runs on the top tier with the red-team role prompt", async () => {
    const seen: any[] = [];
    await runDevilsAdvocate({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      call: async (args) => {
        seen.push(args);
        return { input: verdictInput(), usage: zeroUsage };
      }
    });
    expect(seen).toHaveLength(1);
    expect(seen[0].agent).toBe("devils_advocate");
    expect(seen[0].model).toBe(SYNTHESIS_MODEL);
    expect(seen[0].toolName).toBe("submit_red_team");
  });

  test("is shown every position so it can steel-man before attacking", async () => {
    let prompt = "";
    await runDevilsAdvocate({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: {
        product: pos({ position: "PRODUCT_SAYS_THIS" }),
        finance: pos({ position: "FINANCE_SAYS_THIS" })
      },
      call: async (args) => {
        prompt = args.userMessage;
        return { input: verdictInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toContain("PRODUCT_SAYS_THIS");
    expect(prompt).toContain("FINANCE_SAYS_THIS");
  });

  test("throws with a descriptive message on an unusable verdict", async () => {
    await expect(
      runDevilsAdvocate({
        founder,
        rawRequest: "x",
        realQuestion: "q",
        positions: { product: pos() },
        call: async () => ({ input: { objections: [] }, usage: zeroUsage })
      })
    ).rejects.toThrow(/devils_advocate/i);
  });

  test("returns usage and model for metering", async () => {
    const { usage, model } = await runDevilsAdvocate({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      call: async () => ({
        input: verdictInput(),
        usage: { input: 2000, output: 400, cache_read: 1200 }
      })
    });
    expect(usage.output).toBe(400);
    expect(model).toBe(SYNTHESIS_MODEL);
  });
});
