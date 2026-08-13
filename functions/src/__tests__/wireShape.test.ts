/**
 * Captures the actual request bodies this codebase puts on the wire.
 *
 * Every other test here asserts on the seam ABOVE the SDK — the injected
 * AgentCaller, the injected stream factory — which is exactly the layer that
 * would hide a params bug. These assert the object handed to the SDK itself.
 */
import { callAnthropic, MODEL, NARRATIVE_TOOL, PLAN_MODEL } from "../anthropic";

type Captured = Record<string, any>;

function fakeClient(captured: Captured[], reply: any) {
  return {
    messages: {
      create: async (params: any) => {
        captured.push(params);
        return reply;
      },
      stream: (params: any) => {
        captured.push(params);
        return reply;
      }
    }
  } as any;
}

const narrativeReply = {
  content: [
    {
      type: "tool_use",
      name: "record_narrative",
      input: {
        title: "t",
        what_you_wanted: "w",
        what_happened: "h",
        lesson: "l",
        next_steps: "n",
        mood: "idle",
        detected_skills: []
      }
    }
  ],
  usage: { input_tokens: 1, output_tokens: 1 }
};

describe("summarizeTurn wire shape", () => {
  const callArgs = {
    prompt: "fix the bug",
    events: [{ time: "09:00", tool: "Edit", path: "a.ts" }],
    raw_summary: "Edit a.ts",
    language: "en" as const
  };

  test("sends NO cache_control — the Haiku prefix cannot reach the 4096 floor", async () => {
    const captured: Captured[] = [];
    await callAnthropic(fakeClient(captured, narrativeReply), callArgs);

    expect(captured).toHaveLength(1);
    expect(captured[0].model).toBe(MODEL);
    expect(captured[0].system).toHaveLength(1);
    expect(captured[0].system[0].cache_control).toBeUndefined();
    expect(captured[0].system[0].type).toBe("text");
  });

  test("still sends the system text and the forced tool — the guard drops only the marker", async () => {
    const captured: Captured[] = [];
    await callAnthropic(fakeClient(captured, narrativeReply), callArgs);

    expect(captured[0].system[0].text).toContain("coding companion");
    expect(captured[0].tools).toEqual([NARRATIVE_TOOL]);
    expect(captured[0].tool_choice).toEqual({ type: "tool", name: "record_narrative" });
  });

  test("sends no `thinking` key — Haiku 4.5 has no adaptive thinking to configure", async () => {
    const captured: Captured[] = [];
    await callAnthropic(fakeClient(captured, narrativeReply), callArgs);
    expect("thinking" in captured[0]).toBe(false);
    // And no effort: Haiku 4.5 errors on the field.
    expect("output_config" in captured[0]).toBe(false);
  });
});

describe("model constants actually point where the cost analysis assumed", () => {
  test("PLAN_MODEL is Sonnet 5, whose cache floor is 1024 not 4096", () => {
    expect(PLAN_MODEL).toBe("claude-sonnet-5");
  });

  test("MODEL is still the cheapest tier for the highest-volume path", () => {
    expect(MODEL.startsWith("claude-haiku-4-5")).toBe(true);
  });
});

// ── runTask: the real handler, real SDK call site, fake transport ────────────
jest.mock("../auth", () => ({ verifyAuth: async () => ({ uid: "u1" }) }));
jest.mock("../rateLimit", () => ({
  checkAndIncrement: async () => ({ allowed: true, limit: 100, resetAt: new Date(0) })
}));

const runTaskCaptured: Captured[] = [];
jest.mock("@anthropic-ai/sdk", () => {
  return class FakeAnthropic {
    messages = {
      create: async (params: any) => {
        runTaskCaptured.push(params);
        return {
          content: [
            {
              type: "tool_use",
              name: "record_deliverable",
              input: { kind: "doc", title: "t", body: "b" }
            }
          ],
          usage: { input_tokens: 1, output_tokens: 1 }
        };
      }
    };
  };
});

describe("runTask wire shape", () => {
  beforeEach(() => {
    runTaskCaptured.length = 0;
    process.env.ANTHROPIC_API_KEY = "test-key";
  });

  async function invoke() {
    const { handleRunTask } = require("../runTask");
    const res: any = {
      status(code: number) { this.code = code; return this; },
      json(payload: unknown) { this.payload = payload; return this; }
    };
    await handleRunTask(
      { method: "POST", headers: { authorization: "Bearer x" },
        body: { task_title: "Draft the supplier email", context: "bakeries" } } as any,
      res
    );
    return res;
  }

  test("carries output_config.effort — the change is not just a constant nobody reads", async () => {
    await invoke();
    expect(runTaskCaptured).toHaveLength(1);
    expect(runTaskCaptured[0].output_config).toEqual({ effort: "medium" });
  });

  test("carries the raised cap, which is what keeps thinking from truncating the JSON", async () => {
    await invoke();
    expect(runTaskCaptured[0].max_tokens).toBe(8000);
    expect(runTaskCaptured[0].model).toBe("claude-sonnet-5");
  });

  test("omits `thinking`, so Sonnet 5 runs adaptive — the reason the cap had to rise", async () => {
    await invoke();
    expect("thinking" in runTaskCaptured[0]).toBe(false);
  });

  test("the deliverable prompt carries the length bound", async () => {
    await invoke();
    expect(runTaskCaptured[0].messages[0].content).toContain("LENGTH:");
  });
});
