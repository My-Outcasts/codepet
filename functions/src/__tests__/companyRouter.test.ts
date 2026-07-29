import { ROUTING_TOOL, parseRoutingToolInput, runIntake } from "../company/router";
import { FounderContext, TokenUsage } from "../company/types";
import { ROUTER_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function validInput(overrides: Record<string, unknown> = {}) {
  return {
    decision: "multi_agent",
    agents: ["product", "finance"],
    real_question: "Is the current pricing bet wrong?",
    request_type: "DECISION",
    reason_per_agent: {
      product: "This displaces the only bet worth testing this quarter.",
      finance: "This changes the revenue structure."
    },
    excluded: {},
    missing_info: [],
    ...overrides
  };
}

describe("ROUTING_TOOL", () => {
  test("is named record_routing and requires the load-bearing fields", () => {
    expect(ROUTING_TOOL.name).toBe("record_routing");
    const required = ROUTING_TOOL.input_schema.required as string[];
    for (const field of ["decision", "agents", "real_question", "request_type"]) {
      expect(required).toContain(field);
    }
  });

  test("offers only agents that exist in this deployment", () => {
    const agentEnum = (ROUTING_TOOL.input_schema.properties as any).agents.items.enum as string[];
    expect([...agentEnum].sort()).toEqual(["devils_advocate", "finance", "product"]);
    expect(agentEnum).not.toContain("gtm");
    expect(agentEnum).not.toContain("engineering");
  });
});

describe("parseRoutingToolInput", () => {
  test("accepts a well-formed routing decision", () => {
    const result = parseRoutingToolInput(validInput());
    expect("error" in result).toBe(false);
    expect((result as any).agents).toEqual(["product", "finance"]);
  });

  test("rejects an agent that does not exist in this deployment", () => {
    // A hallucinated department must not be convened — it has no role prompt,
    // so it would fail much later with a far less obvious error.
    const result = parseRoutingToolInput(validInput({ agents: ["product", "gtm"] }));
    expect(result).toEqual({ error: expect.stringMatching(/gtm/) });
  });

  test("rejects chief_of_staff as a convened participant", () => {
    // It is the router and synthesiser, not a department that holds a position.
    const result = parseRoutingToolInput(
      validInput({ agents: ["product", "chief_of_staff"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/chief_of_staff/) });
  });

  test("rejects an unknown decision value", () => {
    expect(parseRoutingToolInput(validInput({ decision: "convene_everyone" }))).toEqual({
      error: expect.stringMatching(/decision/)
    });
  });

  test("rejects single_agent that names more than one agent", () => {
    const result = parseRoutingToolInput(
      validInput({ decision: "single_agent", agents: ["product", "finance"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/single_agent/) });
  });

  test("rejects multi_agent with fewer than two agents", () => {
    // Convening "the company" with one voice defeats the point of the feature.
    const result = parseRoutingToolInput(
      validInput({ decision: "multi_agent", agents: ["product"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/multi_agent/) });
  });

  test("de-duplicates a repeated agent before checking the count", () => {
    const result = parseRoutingToolInput(
      validInput({ decision: "multi_agent", agents: ["product", "product"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/multi_agent/) });
  });

  test("allows needs_clarification with no agents", () => {
    const result = parseRoutingToolInput(
      validInput({ decision: "needs_clarification", agents: [], missing_info: ["current MRR"] })
    );
    expect("error" in result).toBe(false);
    expect((result as any).missing_info).toEqual(["current MRR"]);
  });

  test("rejects an empty real_question", () => {
    expect(parseRoutingToolInput(validInput({ real_question: "   " }))).toEqual({
      error: expect.stringMatching(/real_question/)
    });
  });

  test("rejects an unknown request_type", () => {
    expect(parseRoutingToolInput(validInput({ request_type: "VIBES" }))).toEqual({
      error: expect.stringMatching(/request_type/)
    });
  });

  test("defaults optional maps and arrays instead of leaving them undefined", () => {
    const input = validInput();
    delete (input as any).reason_per_agent;
    delete (input as any).excluded;
    delete (input as any).missing_info;
    const result = parseRoutingToolInput(input) as any;
    expect(result.reason_per_agent).toEqual({});
    expect(result.excluded).toEqual({});
    expect(result.missing_info).toEqual([]);
  });

  test("rejects a non-object input", () => {
    expect(parseRoutingToolInput(null)).toEqual({ error: expect.any(String) });
    expect(parseRoutingToolInput("multi_agent")).toEqual({ error: expect.any(String) });
  });
});

describe("runIntake", () => {
  test("calls the router on the cheapest tier with the chief_of_staff prompt", async () => {
    const seen: any[] = [];
    const { routing } = await runIntake({
      founder,
      rawRequest: "Should I add team seats?",
      call: async (args) => {
        seen.push(args);
        return { input: validInput(), usage: zeroUsage };
      }
    });
    expect(seen).toHaveLength(1);
    expect(seen[0].agent).toBe("chief_of_staff");
    expect(seen[0].model).toBe(ROUTER_MODEL);
    expect(seen[0].toolName).toBe("record_routing");
    expect(routing.decision).toBe("multi_agent");
  });

  test("passes the founder's verbatim request to the router", async () => {
    let userMessage = "";
    await runIntake({
      founder,
      rawRequest: "Should I add team seats?",
      call: async (args) => {
        userMessage = args.userMessage;
        return { input: validInput(), usage: zeroUsage };
      }
    });
    expect(userMessage).toContain("Should I add team seats?");
  });

  test("instructs the router to bias toward single_agent", async () => {
    let userMessage = "";
    await runIntake({
      founder,
      rawRequest: "x",
      call: async (args) => {
        userMessage = args.userMessage;
        return { input: validInput(), usage: zeroUsage };
      }
    });
    expect(userMessage).toMatch(/single_agent/);
  });

  test("throws a descriptive error when the model returns an unusable routing", async () => {
    await expect(
      runIntake({
        founder,
        rawRequest: "x",
        call: async () => ({ input: validInput({ agents: ["gtm"] }), usage: zeroUsage })
      })
    ).rejects.toThrow(/routing/i);
  });

  test("returns usage so the caller can meter the router call", async () => {
    const { usage } = await runIntake({
      founder,
      rawRequest: "x",
      call: async () => ({
        input: validInput(),
        usage: { input: 1200, output: 80, cache_read: 0 }
      })
    });
    expect(usage).toEqual({ input: 1200, output: 80, cache_read: 0 });
  });
});
