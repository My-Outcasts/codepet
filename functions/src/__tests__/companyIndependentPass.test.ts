import {
  POSITION_TOOL,
  parsePositionToolInput,
  runIndependentPass
} from "../company/independentPass";
import { AgentId, FounderContext, TokenUsage } from "../company/types";
import { AGENT_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const rawRequest = "Should I add team seats or price the single-player product?";
const realQuestion = "Is the current pricing bet wrong?";
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

const tick = () => new Promise((resolve) => setImmediate(resolve));

function positionInput(overrides: Record<string, unknown> = {}) {
  return {
    stance: "proceed",
    position: "Ship the smallest version that produces a real pricing signal.",
    reasoning: "Sequencing over scope.",
    evidence_needed: ["Week-4 retention on the beta cohort"],
    risks_i_own: ["Building for an imagined buyer"],
    confidence: 3,
    cost_to_my_dept: "Displaces the onboarding rework this quarter.",
    hard_blocker: null,
    ...overrides
  };
}

describe("POSITION_TOOL", () => {
  test("is named submit_position and requires every comparable field", () => {
    expect(POSITION_TOOL.name).toBe("submit_position");
    const required = POSITION_TOOL.input_schema.required as string[];
    for (const field of [
      "stance",
      "position",
      "reasoning",
      "confidence",
      "cost_to_my_dept",
      "hard_blocker"
    ]) {
      expect(required).toContain(field);
    }
  });

  test("stance is a closed enum so phase 3 can compare it without an LLM", () => {
    const stanceEnum = (POSITION_TOOL.input_schema.properties as any).stance.enum as string[];
    expect([...stanceEnum].sort()).toEqual([
      "do_not_proceed",
      "proceed",
      "proceed_with_conditions"
    ]);
  });
});

describe("parsePositionToolInput", () => {
  test("accepts a well-formed position", () => {
    const result = parsePositionToolInput(positionInput());
    expect("error" in result).toBe(false);
    expect((result as any).stance).toBe("proceed");
  });

  test("preserves an explicit null hard_blocker", () => {
    const result = parsePositionToolInput(positionInput({ hard_blocker: null })) as any;
    expect(result.hard_blocker).toBeNull();
  });

  test("normalises a whitespace-only hard_blocker to null", () => {
    // Models sometimes emit "" instead of null. An empty string must not read as
    // a blocker — that would fabricate a BLOCKER in phase 3.
    const result = parsePositionToolInput(positionInput({ hard_blocker: "  " })) as any;
    expect(result.hard_blocker).toBeNull();
  });

  test("trims a real hard_blocker", () => {
    const result = parsePositionToolInput(
      positionInput({ hard_blocker: "  CAC exceeds LTV  " })
    ) as any;
    expect(result.hard_blocker).toBe("CAC exceeds LTV");
  });

  test("rejects an unknown stance", () => {
    expect(parsePositionToolInput(positionInput({ stance: "maybe" }))).toEqual({
      error: expect.stringMatching(/stance/)
    });
  });

  test("clamps confidence into 1..5", () => {
    expect((parsePositionToolInput(positionInput({ confidence: 9 })) as any).confidence).toBe(5);
    expect((parsePositionToolInput(positionInput({ confidence: 0 })) as any).confidence).toBe(1);
  });

  test("defaults a missing confidence rather than failing the position", () => {
    const input = positionInput();
    delete (input as any).confidence;
    expect((parsePositionToolInput(input) as any).confidence).toBe(3);
  });

  test("rejects a missing position string", () => {
    expect(parsePositionToolInput(positionInput({ position: "" }))).toEqual({
      error: expect.stringMatching(/position/)
    });
  });

  test("defaults the list fields to empty arrays", () => {
    const input = positionInput();
    delete (input as any).evidence_needed;
    delete (input as any).risks_i_own;
    const result = parsePositionToolInput(input) as any;
    expect(result.evidence_needed).toEqual([]);
    expect(result.risks_i_own).toEqual([]);
  });

  test("rejects a non-object input", () => {
    expect(parsePositionToolInput(null)).toEqual({ error: expect.any(String) });
  });
});

describe("runIndependentPass — MUTUAL BLINDNESS", () => {
  // Spec TASK 5: the most important test in the system. If it fails, the feature
  // loses its value even when every other test still passes — agents anchor on
  // whichever opinion they read first and multiple perspectives stop meaning
  // anything.
  const SENTINEL = "SENTINEL_ALPHA_9Z_PRODUCT_ONLY";

  test("no agent's prompt contains any other agent's output", async () => {
    const promptsByAgent = new Map<AgentId, string>();

    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        promptsByAgent.set(
          args.agent,
          args.system.map((b) => b.text).join("\n") + "\n" + args.userMessage
        );
        if (args.agent === "product") {
          return {
            input: positionInput({ position: SENTINEL, reasoning: SENTINEL }),
            usage: zeroUsage
          };
        }
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    // Guard against a vacuous pass: a not.toContain assertion on a prompt that
    // was never captured would succeed while proving nothing.
    expect(promptsByAgent.size).toBe(2);
    expect(promptsByAgent.get("product")).toBeDefined();
    expect(promptsByAgent.get("finance")).toBeDefined();

    expect(promptsByAgent.get("finance")!).not.toContain(SENTINEL);
    // Reverse direction too, so the test cannot pass by call ordering alone.
    expect(promptsByAgent.get("product")!).not.toContain("finance said");
  });

  test("the prompt never names the other participants", async () => {
    // Even the roster is withheld: knowing finance is in the room invites
    // product to pre-emptively concede to it.
    const prompts: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        prompts.push(args.userMessage);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    expect(prompts).toHaveLength(2);
    for (const p of prompts) {
      expect(p).not.toMatch(/finance/i);
      expect(p).not.toMatch(/product/i);
    }
  });

  test("every agent receives a byte-identical user message", async () => {
    // Timing-independent form of the blindness guarantee. The sentinel test
    // above only holds while dispatch is concurrent (nothing has been returned
    // yet when the prompts are built). This one holds regardless of scheduling:
    // if all agents get the same message, that message cannot carry any
    // individual agent's output.
    const messages: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        messages.push(args.userMessage);
        return { input: positionInput({ position: SENTINEL }), usage: zeroUsage };
      }
    });
    expect(messages).toHaveLength(2);
    expect(new Set(messages).size).toBe(1);
  });

  test("agents are dispatched concurrently, not sequentially", async () => {
    // Load-bearing alongside the sentinel test: sequential dispatch is what
    // would let a refactor thread a prior position into a later prompt. Verified
    // by mutation — a sequential loop that feeds positions forward fails both
    // this test and the sentinel test above.
    const started: AgentId[] = [];
    let releaseFirst: (() => void) | null = null;
    const firstGate = new Promise<void>((resolve) => {
      releaseFirst = resolve;
    });

    const pass = runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        started.push(args.agent);
        if (args.agent === "product") await firstGate;
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    await tick();
    // Both calls must be in flight even though the first has not resolved.
    expect(started).toHaveLength(2);

    releaseFirst!();
    await pass;
  });

  test("each agent is asked the real question", async () => {
    const messages: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        messages.push(args.userMessage);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    for (const m of messages) {
      expect(m).toContain(realQuestion);
    }
  });

  test("each agent runs on its configured model", async () => {
    const models: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        models.push(args.model);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    expect(models).toEqual([AGENT_MODEL, AGENT_MODEL]);
  });

  test("all agents share one byte-identical cache prefix", async () => {
    const prefixes: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        prefixes.push(args.system[0].text);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    expect(new Set(prefixes).size).toBe(1);
  });
});

describe("runIndependentPass — graceful degradation", () => {
  test("one agent throwing does not take down the run", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        if (args.agent === "finance") throw new Error("upstream 529");
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    const byAgent = new Map(results.map((r) => [r.agent, r]));
    expect(byAgent.get("product")!.position).toBeDefined();
    expect(byAgent.get("finance")!.position).toBeUndefined();
    expect(byAgent.get("finance")!.error).toMatch(/529/);
  });

  test("an unparseable position becomes an error entry, not a throw", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product"],
      call: async () => ({ input: { stance: "maybe" }, usage: zeroUsage })
    });
    expect(results[0].position).toBeUndefined();
    expect(results[0].error).toMatch(/stance/);
  });

  test("usage is still reported for an agent whose position failed to parse", async () => {
    // The call was billed even though the output was unusable.
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product"],
      call: async () => ({
        input: { stance: "maybe" },
        usage: { input: 900, output: 40, cache_read: 0 }
      })
    });
    expect(results[0].usage.input).toBe(900);
  });

  test("returns one result per requested agent, in request order", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async () => ({ input: positionInput(), usage: zeroUsage })
    });
    expect(results.map((r) => r.agent)).toEqual(["product", "finance"]);
  });
});
