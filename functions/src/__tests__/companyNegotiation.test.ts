import {
  MAX_NEGOTIATION_ROUNDS,
  NEGOTIATION_TOOL,
  parseNegotiationToolInput,
  conflictingAgents,
  isResolved,
  runNegotiation
} from "../company/negotiation";
import {
  AgentId,
  AgentPosition,
  Conflict,
  FounderContext,
  NegotiationTurn,
  TokenUsage
} from "../company/types";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const rawRequest = "Should I scale this acquisition channel?";
const realQuestion = "Can we afford to buy information about this channel?";
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function pos(stance: AgentPosition["stance"], hardBlocker: string | null = null): AgentPosition {
  return {
    stance,
    position: `stance is ${stance}`,
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 4,
    cost_to_my_dept: "c",
    hard_blocker: hardBlocker
  };
}

const positions: Partial<Record<AgentId, AgentPosition>> = {
  product: pos("proceed"),
  finance: pos("do_not_proceed", "CAC is $19 against an LTV of $15.")
};
const blockerConflict: Conflict[] = [
  { a: "product", b: "finance", kind: "BLOCKER", reason: "finance raised a hard blocker" }
];

function turnInput(overrides: Record<string, unknown> = {}) {
  return {
    precise_disagreement: "Whether LTV is knowable before spending.",
    what_would_change_my_mind: "Month-2 retention above 35%.",
    proposal: "Cap the test at $1.6k and stop at week 8.",
    resolved: false,
    ...overrides
  };
}

describe("cap", () => {
  test("is hard-coded at 2 rounds", () => {
    expect(MAX_NEGOTIATION_ROUNDS).toBe(2);
  });
});

describe("NEGOTIATION_TOOL", () => {
  test("requires a falsification condition, not just a rebuttal", () => {
    const required = NEGOTIATION_TOOL.input_schema.required as string[];
    expect(required).toContain("what_would_change_my_mind");
    expect(required).toContain("precise_disagreement");
    expect(required).toContain("resolved");
  });
});

describe("parseNegotiationToolInput", () => {
  test("accepts a well-formed turn", () => {
    const result = parseNegotiationToolInput(turnInput());
    expect("error" in result).toBe(false);
    expect((result as any).resolved).toBe(false);
  });

  test("rejects a turn with no precise disagreement", () => {
    expect(parseNegotiationToolInput(turnInput({ precise_disagreement: " " }))).toEqual({
      error: expect.stringMatching(/precise_disagreement/)
    });
  });

  test("rejects a turn with no falsification condition", () => {
    // Without a falsifier there is no way for evidence to settle this, which
    // makes the turn noise rather than negotiation.
    expect(parseNegotiationToolInput(turnInput({ what_would_change_my_mind: "  " }))).toEqual({
      error: expect.stringMatching(/what_would_change_my_mind/)
    });
  });

  test("treats a non-boolean resolved as not resolved", () => {
    const result = parseNegotiationToolInput(turnInput({ resolved: "yes" })) as any;
    expect(result.resolved).toBe(false);
  });

  test("rejects a non-object input", () => {
    expect(parseNegotiationToolInput(null)).toEqual({ error: expect.any(String) });
  });
});

describe("conflictingAgents", () => {
  test("returns only agents in a CONFLICT or BLOCKER pair", () => {
    expect([...conflictingAgents(blockerConflict)].sort()).toEqual(["finance", "product"]);
  });

  test("excludes agents whose only relationship is TENSION or ALIGNED", () => {
    expect(
      conflictingAgents([{ a: "product", b: "finance", kind: "TENSION", reason: "" }])
    ).toEqual([]);
    expect(
      conflictingAgents([{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }])
    ).toEqual([]);
  });

  test("de-duplicates an agent appearing in several conflicts", () => {
    const many: Conflict[] = [
      { a: "product", b: "finance", kind: "CONFLICT", reason: "" },
      { a: "product", b: "finance", kind: "BLOCKER", reason: "" }
    ];
    expect([...conflictingAgents(many)].sort()).toEqual(["finance", "product"]);
  });
});

describe("isResolved", () => {
  const turn = (agent: AgentId, resolved: boolean): NegotiationTurn => ({
    agent,
    precise_disagreement: "d",
    what_would_change_my_mind: "w",
    proposal: "p",
    resolved
  });

  test("true only when every participant in the last round agrees", () => {
    expect(isResolved([{ round: 1, turns: [turn("product", true), turn("finance", true)] }])).toBe(
      true
    );
  });

  test("false when one side concedes and the other holds", () => {
    // Consensus by capitulation is a failure of this system, not a success.
    expect(isResolved([{ round: 1, turns: [turn("product", true), turn("finance", false)] }])).toBe(
      false
    );
  });

  test("false for an empty round list", () => {
    expect(isResolved([])).toBe(false);
  });

  test("false for a round with no turns", () => {
    expect(isResolved([{ round: 1, turns: [] }])).toBe(false);
  });

  test("judges only the final round", () => {
    expect(
      isResolved([
        { round: 1, turns: [turn("product", false), turn("finance", false)] },
        { round: 2, turns: [turn("product", true), turn("finance", true)] }
      ])
    ).toBe(true);
  });
});

describe("runNegotiation", () => {
  test("stops after round 1 when both sides resolve", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => {
        calls++;
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(rounds).toHaveLength(1);
    expect(unresolved).toBe(false);
    expect(calls).toBe(2); // one per conflicting agent, round 1 only
  });

  test("returns unresolved after exactly 2 rounds when nobody yields", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => {
        calls++;
        return { input: turnInput({ resolved: false }), usage: zeroUsage };
      }
    });
    expect(rounds).toHaveLength(MAX_NEGOTIATION_ROUNDS);
    expect(unresolved).toBe(true);
    expect(calls).toBe(4); // 2 agents x 2 rounds — never a third round
  });

  test("shows each agent the opposing position", async () => {
    const prompts = new Map<AgentId, string>();
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (!prompts.has(args.agent)) prompts.set(args.agent, args.userMessage);
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    // This is the one phase where cross-visibility is correct and required.
    expect(prompts.size).toBe(2);
    expect(prompts.get("product")!).toContain(positions.finance!.position);
    expect(prompts.get("finance")!).toContain(positions.product!.position);
  });

  test("does not show an agent its own position back", async () => {
    let financePrompt = "";
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions: {
        product: pos("proceed"),
        finance: { ...pos("do_not_proceed", "blocker text"), position: "FINANCE_OWN_WORDS" }
      },
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "finance") financePrompt = args.userMessage;
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(financePrompt).not.toContain("FINANCE_OWN_WORDS");
  });

  test("surfaces the opposing hard blocker verbatim", async () => {
    let productPrompt = "";
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "product") productPrompt = args.userMessage;
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(productPrompt).toContain("CAC is $19 against an LTV of $15.");
  });

  test("round 2 shows what was said in round 1", async () => {
    const prompts: string[] = [];
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        prompts.push(args.userMessage);
        return {
          input: turnInput({ resolved: false, proposal: "ROUND_ONE_PROPOSAL" }),
          usage: zeroUsage
        };
      }
    });
    // First two prompts are round 1, last two are round 2.
    expect(prompts).toHaveLength(4);
    expect(prompts[0]).not.toContain("ROUND_ONE_PROPOSAL");
    expect(prompts[2]).toContain("ROUND_ONE_PROPOSAL");
  });

  test("returns no rounds and unresolved=false when there is nothing to debate", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: [{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }],
      call: async () => {
        calls++;
        return { input: turnInput(), usage: zeroUsage };
      }
    });
    expect(rounds).toEqual([]);
    expect(unresolved).toBe(false);
    expect(calls).toBe(0);
  });

  test("a failing agent turn leaves the round unresolved rather than throwing", async () => {
    const { unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "finance") throw new Error("upstream 529");
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(unresolved).toBe(true);
  });

  test("an unparseable turn cannot count as resolution", async () => {
    const { unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "finance") return { input: { resolved: true }, usage: zeroUsage };
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(unresolved).toBe(true);
  });

  test("reports usage per agent per round for metering", async () => {
    const { usages } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => ({
        input: turnInput({ resolved: true }),
        usage: { input: 500, output: 120, cache_read: 900 }
      })
    });
    expect(usages).toHaveLength(2);
    expect(usages[0].usage.output).toBe(120);
  });
});
