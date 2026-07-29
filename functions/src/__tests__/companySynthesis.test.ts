import {
  BRIEF_TOOL,
  parseBriefToolInput,
  briefOmitsDissent,
  runSynthesis
} from "../company/synthesis";
import {
  AgentPosition,
  Conflict,
  DecisionBrief,
  FounderContext,
  TokenUsage
} from "../company/types";
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
    confidence: 4,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

const conflicted: Conflict[] = [
  { a: "product", b: "finance", kind: "BLOCKER", reason: "finance raised a hard blocker" }
];
const alignedOnly: Conflict[] = [
  { a: "product", b: "finance", kind: "ALIGNED", reason: "" }
];

function briefInput(overrides: Record<string, unknown> = {}) {
  return {
    recommendation: "Run a capped 8-week test at $1.6k before committing further.",
    confidence: 3,
    confidence_reason: "The channel has never run a full cycle, so LTV is a guess.",
    the_real_disagreement:
      "Finance: CAC is $19 against a $15 LTV, so scaling loses money faster. Product: we have not run a full cycle, so blocking now means never learning which channels work.",
    tradeoff_founder_must_own:
      "Spend $1.6k to buy information, or preserve three months of runway and accept not knowing.",
    kill_criteria: ["Month-2 retention below 35%", "CAC still above $19 at week 8"],
    next_action: {
      action: "Cap the channel test at $1.6k and instrument week-8 LTV",
      owner: "founder"
    },
    what_we_dont_know: "Real LTV for this channel — no cohort has completed a full cycle.",
    unresolved: true,
    ...overrides
  };
}

const baseArgs = {
  founder,
  rawRequest: "x",
  realQuestion: "q",
  positions: { product: pos(), finance: pos() },
  conflicts: conflicted,
  negotiation: [],
  devilsAdvocate: null,
  unresolved: true
};

describe("BRIEF_TOOL", () => {
  test("requires all six components from spec §2.2 Phase 5", () => {
    const required = BRIEF_TOOL.input_schema.required as string[];
    for (const field of [
      "recommendation",
      "the_real_disagreement",
      "tradeoff_founder_must_own",
      "kill_criteria",
      "next_action",
      "what_we_dont_know"
    ]) {
      expect(required).toContain(field);
    }
  });
});

describe("parseBriefToolInput", () => {
  test("accepts a well-formed brief", () => {
    const result = parseBriefToolInput(briefInput());
    expect("error" in result).toBe(false);
    expect((result as any).unresolved).toBe(true);
  });

  test("rejects a brief missing the trade-off the founder must own", () => {
    // Spec forbids ending on "it depends on your priorities".
    expect(parseBriefToolInput(briefInput({ tradeoff_founder_must_own: "  " }))).toEqual({
      error: expect.stringMatching(/tradeoff_founder_must_own/)
    });
  });

  test("rejects a brief with no kill criteria", () => {
    expect(parseBriefToolInput(briefInput({ kill_criteria: [] }))).toEqual({
      error: expect.stringMatching(/kill_criteria/)
    });
  });

  test("drops blank kill criteria and rejects if none survive", () => {
    expect(parseBriefToolInput(briefInput({ kill_criteria: ["  ", ""] }))).toEqual({
      error: expect.stringMatching(/kill_criteria/)
    });
  });

  test("rejects a next_action with no owner", () => {
    expect(
      parseBriefToolInput(briefInput({ next_action: { action: "do it", owner: "" } }))
    ).toEqual({ error: expect.stringMatching(/owner/) });
  });

  test("rejects a next_action with no action", () => {
    expect(
      parseBriefToolInput(briefInput({ next_action: { action: " ", owner: "founder" } }))
    ).toEqual({ error: expect.stringMatching(/action/) });
  });

  test("rejects a missing recommendation", () => {
    expect(parseBriefToolInput(briefInput({ recommendation: "" }))).toEqual({
      error: expect.stringMatching(/recommendation/)
    });
  });

  test("clamps confidence into 1..5", () => {
    expect((parseBriefToolInput(briefInput({ confidence: 99 })) as any).confidence).toBe(5);
  });

  test("rejects a non-object input", () => {
    expect(parseBriefToolInput(null)).toEqual({ error: expect.any(String) });
  });
});

describe("briefOmitsDissent", () => {
  const brief = (overrides: Partial<DecisionBrief> = {}): DecisionBrief => ({
    ...(parseBriefToolInput(briefInput()) as DecisionBrief),
    ...overrides
  });

  test("true when a conflict existed but the brief records no disagreement", () => {
    // The exact failure the feature exists to prevent.
    expect(briefOmitsDissent(brief({ the_real_disagreement: "" }), conflicted)).toBe(true);
  });

  test("true when the brief hand-waves the disagreement away", () => {
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "Everyone agreed." }), conflicted)
    ).toBe(true);
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "There was no disagreement." }), conflicted)
    ).toBe(true);
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "The room was unanimous." }), conflicted)
    ).toBe(true);
  });

  test("is case-insensitive about the consensus tells", () => {
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "EVERYONE AGREED" }), conflicted)
    ).toBe(true);
  });

  test("false when the brief names both sides", () => {
    expect(briefOmitsDissent(brief(), conflicted)).toBe(false);
  });

  test("false when there was no conflict to report", () => {
    expect(briefOmitsDissent(brief({ the_real_disagreement: "" }), alignedOnly)).toBe(false);
  });
});

describe("runSynthesis", () => {
  test("runs chief_of_staff on the top tier", async () => {
    const seen: any[] = [];
    await runSynthesis({
      ...baseArgs,
      call: async (args) => {
        seen.push(args);
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(seen).toHaveLength(1);
    expect(seen[0].agent).toBe("chief_of_staff");
    expect(seen[0].model).toBe(SYNTHESIS_MODEL);
  });

  test("passes both positions verbatim so dissent can be quoted", async () => {
    let prompt = "";
    await runSynthesis({
      ...baseArgs,
      positions: {
        product: pos({ position: "PRODUCT_VERBATIM" }),
        finance: pos({ position: "FINANCE_VERBATIM", hard_blocker: "BLOCKER_VERBATIM" })
      },
      call: async (args) => {
        prompt = args.userMessage;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toContain("PRODUCT_VERBATIM");
    expect(prompt).toContain("FINANCE_VERBATIM");
    expect(prompt).toContain("BLOCKER_VERBATIM");
  });

  test("tells the synthesiser when the negotiation did not resolve", async () => {
    let prompt = "";
    await runSynthesis({
      ...baseArgs,
      negotiation: [
        {
          round: 1,
          turns: [
            {
              agent: "product",
              precise_disagreement: "d",
              what_would_change_my_mind: "w",
              proposal: "p",
              resolved: false
            }
          ]
        }
      ],
      call: async (args) => {
        prompt = args.userMessage;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toMatch(/unresolved/i);
  });

  test("includes the red team verdict when one exists", async () => {
    let prompt = "";
    await runSynthesis({
      ...baseArgs,
      devilsAdvocate: {
        load_bearing_assumption: "RED_TEAM_ASSUMPTION",
        how_it_could_be_false: "f",
        cheapest_test: "t",
        failure_post_mortem: "pm",
        who_is_not_in_the_room: "silent churner",
        objections: ["o"],
        plan_is_sound: false
      },
      call: async (args) => {
        prompt = args.userMessage;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toContain("RED_TEAM_ASSUMPTION");
  });

  test("forces unresolved=true on the brief when negotiation did not resolve", async () => {
    // The model must not be able to paper over an unresolved trade-off.
    const { brief } = await runSynthesis({
      ...baseArgs,
      unresolved: true,
      call: async () => ({ input: briefInput({ unresolved: false }), usage: zeroUsage })
    });
    expect(brief.unresolved).toBe(true);
  });

  test("lets the brief declare unresolved even when negotiation resolved", async () => {
    const { brief } = await runSynthesis({
      ...baseArgs,
      unresolved: false,
      call: async () => ({ input: briefInput({ unresolved: true }), usage: zeroUsage })
    });
    expect(brief.unresolved).toBe(true);
  });

  test("throws when the brief buries dissent that actually existed", async () => {
    await expect(
      runSynthesis({
        ...baseArgs,
        call: async () => ({
          input: briefInput({ the_real_disagreement: "Everyone agreed." }),
          usage: zeroUsage
        })
      })
    ).rejects.toThrow(/dissent/i);
  });

  test("throws with a descriptive message on an unusable brief", async () => {
    await expect(
      runSynthesis({
        ...baseArgs,
        call: async () => ({ input: { recommendation: "" }, usage: zeroUsage })
      })
    ).rejects.toThrow(/chief_of_staff/i);
  });
});
