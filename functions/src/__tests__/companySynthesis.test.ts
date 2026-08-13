import {
  BRIEF_TOOL,
  DEFAULT_ACTION_OWNER,
  briefPatchTool,
  missingBriefFields,
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
import { BRIEF_MAX_TOKENS, PATCH_MAX_TOKENS, POSITION_MAX_TOKENS } from "../company/router";

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

  test("reads a bare kill_criteria string as one criterion", () => {
    // Measured against the real model: Opus returns a string, not a one-element
    // array, whenever it settles on a single criterion. Rejecting that discarded
    // a usable brief after paying for every earlier phase.
    const criterion = "Zero of 30 beta users purchase within 14 days at any price.";
    const brief = parseBriefToolInput(briefInput({ kill_criteria: criterion }));
    expect(brief).not.toHaveProperty("error");
    expect((brief as DecisionBrief).kill_criteria).toEqual([criterion]);
  });

  test("still rejects a blank kill_criteria string", () => {
    expect(parseBriefToolInput(briefInput({ kill_criteria: "   " }))).toEqual({
      error: expect.stringMatching(/kill_criteria/)
    });
  });

  test("fills in the owner when the model leaves it out", () => {
    // Deliberate change of intent: rejecting this cost a whole run, and the
    // founder is the only party here who can act on anything. The ACTION is
    // still required — that is content, and inventing it would put words in the
    // room's mouth.
    const brief = parseBriefToolInput(briefInput({ next_action: { action: "do it", owner: "" } }));
    expect(brief).not.toHaveProperty("error");
    expect((brief as DecisionBrief).next_action).toEqual({
      action: "do it",
      owner: DEFAULT_ACTION_OWNER
    });
  });

  test("reads a bare next_action string as the action itself", () => {
    const brief = parseBriefToolInput(briefInput({ next_action: "Gửi link thanh toán hôm nay" }));
    expect(brief).not.toHaveProperty("error");
    expect((brief as DecisionBrief).next_action).toEqual({
      action: "Gửi link thanh toán hôm nay",
      owner: DEFAULT_ACTION_OWNER
    });
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

  test("keeps the cache breakpoint whether or not the red team ran", async () => {
    // Corrected premise. The red team sends submit_red_team and this sends
    // record_decision_brief; the tool is part of the cached prefix, so neither
    // could ever read the other's entry. The reader here is this phase's own
    // retry, which is unaffected by whether the red team ran.
    for (const devilsAdvocate of [null, {
      load_bearing_assumption: "a", how_it_could_be_false: "b", cheapest_test: "c",
      failure_post_mortem: "d", who_is_not_in_the_room: "e", objections: ["o"],
      plan_is_sound: true
    }]) {
      const seen: any[] = [];
      await runSynthesis({
        ...baseArgs,
        devilsAdvocate: devilsAdvocate as any,
        call: async (args) => {
          seen.push(args);
          return { input: briefInput(), usage: zeroUsage };
        }
      });
      expect(seen[0].system[0].cache_control).toEqual({ type: "ephemeral" });
    }
  });

  test("does not lower effort — synthesis keeps the top tier default", async () => {
    // The department phases run at POSITION_EFFORT to save tokens. Synthesis is
    // one call doing the job the top tier is paid for; sending an effort here
    // would be a silent quality cut.
    const seen: any[] = [];
    await runSynthesis({
      ...baseArgs,
      call: async (args) => {
        seen.push(args);
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(seen[0].effort).toBeUndefined();
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

  test("asks again once when the brief is rejected, and keeps the retry", async () => {
    // Observed in production: the model omitted what_we_dont_know and a complete
    // brief was discarded at the last and most expensive call in the run.
    let calls = 0;
    const { brief } = await runSynthesis({
      ...baseArgs,
      call: async () => {
        calls++;
        const { what_we_dont_know, ...missingField } = briefInput();
        return {
          input: calls === 1 ? missingField : briefInput(),
          usage: { input: 200, output: 20, cache_read: 0 }
        };
      }
    });
    expect(calls).toBe(2);
    expect(brief.recommendation).not.toBe("");
  });

  test("usage covers both attempts when the first brief was rejected", async () => {
    let calls = 0;
    const { usage } = await runSynthesis({
      ...baseArgs,
      call: async () => {
        calls++;
        const { kill_criteria, ...missingField } = briefInput();
        return {
          input: calls === 1 ? missingField : briefInput(),
          usage: { input: 200, output: 20, cache_read: 5 }
        };
      }
    });
    expect(usage).toEqual({ input: 400, output: 40, cache_read: 10 });
  });

  test("does not retry when the first brief is usable", async () => {
    let calls = 0;
    await runSynthesis({
      ...baseArgs,
      call: async () => {
        calls++;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(calls).toBe(1);
  });

  test("retries a brief that buried dissent, then throws if it still does", async () => {
    // The dissent guard is the whole point of the feature, so it gets a second
    // chance rather than a silent pass — but never a pass.
    let calls = 0;
    await expect(
      runSynthesis({
        ...baseArgs,
        call: async () => {
          calls++;
          return {
            input: briefInput({ the_real_disagreement: "Everyone agreed." }),
            usage: zeroUsage
          };
        }
      })
    ).rejects.toThrow(/dissent/i);
    expect(calls).toBe(2);
  });

  test("asks for a bigger output cap than a position needs", async () => {
    // The brief is several fields of prose; a Vietnamese one measured 2000+
    // output tokens and was silently truncated at the position-sized cap.
    let seen: number | undefined;
    await runSynthesis({
      ...baseArgs,
      call: async (a) => {
        seen = a.maxTokens;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(seen).toBe(BRIEF_MAX_TOKENS);
    expect(BRIEF_MAX_TOKENS).toBeGreaterThan(POSITION_MAX_TOKENS);
  });

  test("names truncation as truncation instead of blaming the schema", async () => {
    // A cut-off brief and a schema-ignoring model both present as a missing
    // field. Reporting the wrong one sends the reader to rewrite a prompt when
    // the fix is one number.
    const { what_we_dont_know, ...cutOff } = briefInput();
    await expect(
      runSynthesis({
        ...baseArgs,
        call: async () => ({
          input: cutOff,
          usage: zeroUsage,
          stopReason: "max_tokens"
        })
      })
    ).rejects.toThrow(/cut off|truncation/i);
  });

  test("asks only for the fields that were left out, not the whole brief again", async () => {
    // Regenerating the brief reproduced the failure about as often as it fixed
    // it, because writing the same long output is what drops fields in the first
    // place. The follow-up is a small tool holding only the missing fields.
    const seen: Array<{ message: string; toolName: string; maxTokens?: number }> = [];
    let calls = 0;
    const { brief } = await runSynthesis({
      ...baseArgs,
      call: async (a) => {
        seen.push({ message: a.userMessage, toolName: a.toolName, maxTokens: a.maxTokens });
        calls++;
        if (calls === 1) {
          const { what_we_dont_know, ...gap } = briefInput();
          return { input: gap, usage: zeroUsage };
        }
        return {
          input: { what_we_dont_know: "Chưa biết ARPU thật của quảng cáo." },
          usage: zeroUsage
        };
      }
    });

    expect(seen).toHaveLength(2);
    expect(seen[1].toolName).toBe("complete_brief");
    expect(seen[1].maxTokens).toBe(PATCH_MAX_TOKENS);
    expect(seen[1].message).toMatch(/what_we_dont_know/);
    // The prose from the first attempt survives — it was never the problem.
    expect(brief.recommendation).toBe(briefInput().recommendation);
    expect(brief.what_we_dont_know).toBe("Chưa biết ARPU thật của quảng cáo.");
  });

  test("the patch tool carries only the missing fields", () => {
    const tool = briefPatchTool(["what_we_dont_know", "next_action"]);
    const props = tool.input_schema.properties as Record<string, unknown>;
    expect(Object.keys(props).sort()).toEqual(["next_action", "what_we_dont_know"]);
    expect(tool.input_schema.required).toEqual(["what_we_dont_know", "next_action"]);
  });

  test("missingBriefFields names every hole, not just the first", () => {
    const { what_we_dont_know, kill_criteria, ...gaps } = briefInput();
    expect(missingBriefFields(gaps).sort()).toEqual(["kill_criteria", "what_we_dont_know"]);
    expect(missingBriefFields(briefInput())).toEqual([]);
  });
});
