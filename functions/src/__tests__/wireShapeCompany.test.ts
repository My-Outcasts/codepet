/**
 * The Virtual Company's SDK translation layer.
 *
 * Every other company test injects its own AgentCaller, so nothing exercised
 * defaultAgentCaller — the function that turns phase arguments into request
 * fields. This file is in its own suite because it mocks the SDK module, which
 * has to happen before virtualCompany.ts is imported.
 */
const captured: Record<string, any>[] = [];

jest.mock("@anthropic-ai/sdk", () => {
  return class FakeAnthropic {
    messages = {
      create: async (params: any) => {
        captured.push(params);
        return {
          content: [{ type: "tool_use", name: "submit_position", input: { ok: true } }],
          usage: { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 5 },
          stop_reason: "tool_use"
        };
      }
    };
  };
});

import { __defaultAgentCallerForTests } from "../company/virtualCompany";
import { POSITION_EFFORT, POSITION_MAX_TOKENS } from "../company/router";
import { AGENT_MODEL, ROUTER_MODEL } from "../anthropic";

const baseArgs = {
  agent: "finance" as const,
  model: AGENT_MODEL,
  system: [{ type: "text" as const, text: "prefix", cache_control: { type: "ephemeral" as const } }],
  userMessage: "position please",
  tool: { name: "submit_position" },
  toolName: "submit_position"
};

describe("defaultAgentCaller — phase args to SDK request", () => {
  beforeEach(() => {
    captured.length = 0;
    process.env.ANTHROPIC_API_KEY = "test-key";
  });

  test("translates effort into output_config", async () => {
    await __defaultAgentCallerForTests()({ ...baseArgs, effort: POSITION_EFFORT });
    expect(captured[0].output_config).toEqual({ effort: POSITION_EFFORT });
  });

  test("omits output_config entirely when no effort is given", async () => {
    // Not cosmetic. The router runs on Haiku 4.5, which errors on the field —
    // an `output_config: { effort: undefined }` key would still be sent.
    await __defaultAgentCallerForTests()({ ...baseArgs, model: ROUTER_MODEL });
    expect("output_config" in captured[0]).toBe(false);
  });

  test("passes the system blocks through untouched, cache marker included", async () => {
    await __defaultAgentCallerForTests()({ ...baseArgs, effort: POSITION_EFFORT });
    expect(captured[0].system).toEqual(baseArgs.system);
    expect(captured[0].system[0].cache_control).toEqual({ type: "ephemeral" });
  });

  test("defaults max_tokens to POSITION_MAX_TOKENS, and honours an override", async () => {
    await __defaultAgentCallerForTests()({ ...baseArgs });
    expect(captured[0].max_tokens).toBe(POSITION_MAX_TOKENS);

    captured.length = 0;
    await __defaultAgentCallerForTests()({ ...baseArgs, maxTokens: 4000 });
    expect(captured[0].max_tokens).toBe(4000);
  });

  test("reports cache_read back to the blackboard, which is how caching is observable", async () => {
    const result = await __defaultAgentCallerForTests()({ ...baseArgs });
    expect(result.usage).toEqual({ input: 10, output: 20, cache_read: 5 });
  });
});
