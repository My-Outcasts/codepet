import { validateChatPayload } from "../chat";

describe("validateChatPayload", () => {
  const valid = {
    session_id: "s1",
    language: "vi",
    pet_persona: { id: "byte", name: "Byte", personality: "glitchy", domain: "Data" },
    session_context: {
      user_brief: "building a journal",
      summary: { summary: "We worked on X.", lesson: "Stay focused." },
      turns: [
        {
          prompt: "fix the layout",
          what_you_wanted: "you wanted",
          what_happened: "you did",
          lesson: "be patient",
          duration_minutes: 10,
          events: [{ time: "09:00", tool: "Edit", path: "foo.swift" }]
        }
      ]
    },
    history: [
      { role: "user", text: "hi" },
      { role: "pet", text: "hi back" }
    ],
    user_message: "what was the messy part?"
  };

  test("returns null for a valid payload", () => {
    expect(validateChatPayload(valid)).toBeNull();
  });

  test("rejects missing session_id", () => {
    const bad = { ...valid, session_id: "" };
    expect(validateChatPayload(bad)).toMatch(/session_id/);
  });

  test("rejects missing user_message", () => {
    const bad = { ...valid, user_message: "" };
    expect(validateChatPayload(bad)).toMatch(/user_message/);
  });

  test("rejects bad language", () => {
    const bad = { ...valid, language: "fr" };
    expect(validateChatPayload(bad)).toMatch(/language/);
  });

  test("rejects non-array turns", () => {
    const bad = { ...valid, session_context: { ...valid.session_context, turns: "x" as any } };
    expect(validateChatPayload(bad)).toMatch(/turns/);
  });

  test("rejects history > 20 messages", () => {
    const bad = {
      ...valid,
      history: Array.from({ length: 21 }, (_, i) => ({ role: "user" as const, text: `m${i}` }))
    };
    expect(validateChatPayload(bad)).toMatch(/history/);
  });

  test("rejects history with bad role", () => {
    const bad = { ...valid, history: [{ role: "assistant" as any, text: "x" }] };
    expect(validateChatPayload(bad)).toMatch(/role/);
  });

  test("rejects pet_persona missing fields", () => {
    const bad = { ...valid, pet_persona: { id: "byte" } as any };
    expect(validateChatPayload(bad)).toMatch(/pet_persona/);
  });

  test("accepts payload without optional fields", () => {
    const minimal = {
      session_id: "s1",
      language: "en",
      session_context: { turns: [{ prompt: "hi", events: [] }] },
      history: [],
      user_message: "what?"
    };
    expect(validateChatPayload(minimal)).toBeNull();
  });
});

import { buildChatSystemPrompt, buildChatUserMessage, buildChatMessages, CHAT_SYSTEM_PROMPT } from "../chat";

describe("buildChatSystemPrompt", () => {
  test("substitutes language and persona", () => {
    const prompt = buildChatSystemPrompt({
      language: "vi",
      petPersona: { id: "byte", name: "Byte", personality: "glitchy", domain: "Data" },
      sessionContext: { turns: [{ prompt: "fix", events: [] }] }
    });
    expect(prompt).toContain("Tiếng Việt");
    expect(prompt).toContain("Byte");
    expect(prompt).toContain("glitchy");
    expect(prompt).not.toContain("<language>");
    expect(prompt).not.toContain("<persona_block>");
  });

  test("renders user_brief when present", () => {
    const prompt = buildChatSystemPrompt({
      language: "en",
      sessionContext: {
        user_brief: "shipping a journaling app",
        turns: [{ prompt: "x", events: [] }]
      }
    });
    expect(prompt).toContain("shipping a journaling app");
  });

  test("renders session summary when present", () => {
    const prompt = buildChatSystemPrompt({
      language: "en",
      sessionContext: {
        summary: { summary: "We refactored auth.", lesson: "Small steps." },
        turns: [{ prompt: "x", events: [] }]
      }
    });
    expect(prompt).toContain("We refactored auth.");
    expect(prompt).toContain("Small steps.");
  });

  test("renders each turn with its narrative and events", () => {
    const prompt = buildChatSystemPrompt({
      language: "en",
      sessionContext: {
        turns: [
          {
            prompt: "fix the layout",
            what_you_wanted: "you wanted clean rows",
            what_happened: "we tried twice",
            lesson: "isolate the layout first",
            duration_minutes: 12,
            events: [
              { time: "09:00", tool: "Edit", path: "ReflectionTab.swift" },
              { time: "09:05", tool: "Bash", text: "swift test" }
            ]
          }
        ]
      }
    });
    expect(prompt).toContain("fix the layout");
    expect(prompt).toContain("you wanted clean rows");
    expect(prompt).toContain("we tried twice");
    expect(prompt).toContain("isolate the layout first");
    expect(prompt).toContain("ReflectionTab.swift");
    expect(prompt).toContain("swift test");
  });

  test("forbids file/jargon rules are present", () => {
    expect(CHAT_SYSTEM_PROMPT).toMatch(/file name/i);
    expect(CHAT_SYSTEM_PROMPT).toMatch(/AI|assistant/);
    expect(CHAT_SYSTEM_PROMPT).toMatch(/second person|"you"|bạn/);
  });
});

describe("buildChatMessages", () => {
  test("maps history roles and appends user_message as final user turn", () => {
    const messages = buildChatMessages({
      history: [
        { role: "user", text: "what was tricky?" },
        { role: "pet", text: "Together we kept circling…" }
      ],
      userMessage: "tell me more"
    });
    expect(messages).toEqual([
      { role: "user", content: "what was tricky?" },
      { role: "assistant", content: "Together we kept circling…" },
      { role: "user", content: "tell me more" }
    ]);
  });

  test("handles empty history", () => {
    const messages = buildChatMessages({ history: [], userMessage: "hi" });
    expect(messages).toEqual([{ role: "user", content: "hi" }]);
  });
});

import { handleChatSession, __setStreamFactoryForTests, __resetStreamFactoryForTests } from "../chat";

// Verify-auth + rate-limit are mocked through the actual modules' env in a real
// test runner setup. For this plan we mock at module level.
jest.mock("../auth", () => ({
  verifyAuth: jest.fn(async (header: string | undefined) => {
    if (header === "Bearer good") return { uid: "user1" };
    return null;
  }),
  extractBearerToken: (h: string | undefined) => (h?.startsWith("Bearer ") ? h.slice(7) : null)
}));

jest.mock("../rateLimit", () => ({
  checkAndIncrement: jest.fn(async (uid: string) => ({
    allowed: uid !== "capped",
    resetAt: new Date("2026-05-08T00:00:00Z"),
    limit: 50
  }))
}));

function makeReq(overrides: any = {}): any {
  return {
    method: "POST",
    headers: { authorization: "Bearer good" },
    body: {
      session_id: "s1",
      language: "en",
      session_context: { turns: [{ prompt: "hi", events: [] }] },
      history: [],
      user_message: "what happened?"
    },
    ...overrides
  };
}

function makeRes() {
  const headers: Record<string, string> = {};
  let statusCode = 0;
  const writes: string[] = [];
  let ended = false;
  return {
    statusCode,
    headers,
    writes,
    ended: () => ended,
    setHeader(k: string, v: string) { headers[k] = v; },
    status(code: number) { statusCode = code; (this as any).statusCode = code; return this; },
    json(obj: any) { writes.push(JSON.stringify(obj)); ended = true; (this as any).statusCode = (this as any).statusCode || 200; },
    write(chunk: string) { writes.push(chunk); return true; },
    end() { ended = true; },
    flushHeaders() { /* noop */ }
  };
}

describe("handleChatSession", () => {
  beforeEach(() => __resetStreamFactoryForTests());

  test("rejects non-POST methods", async () => {
    const req = makeReq({ method: "GET" });
    const res = makeRes();
    await handleChatSession(req as any, res as any);
    expect((res as any).statusCode).toBe(405);
  });

  test("returns 401 for missing auth", async () => {
    const req = makeReq({ headers: { authorization: undefined } });
    const res = makeRes();
    await handleChatSession(req as any, res as any);
    expect((res as any).statusCode).toBe(401);
  });

  test("returns 400 for invalid payload", async () => {
    const req = makeReq({ body: { session_id: "" } });
    const res = makeRes();
    await handleChatSession(req as any, res as any);
    expect((res as any).statusCode).toBe(400);
  });

  test("returns 429 when rate-limited", async () => {
    // Force rate-limit to deny.
    const rl = require("../rateLimit");
    rl.checkAndIncrement.mockImplementationOnce(async () => ({
      allowed: false,
      resetAt: new Date("2026-05-08T00:00:00Z"),
      limit: 50
    }));
    const req = makeReq();
    const res = makeRes();
    await handleChatSession(req as any, res as any);
    expect((res as any).statusCode).toBe(429);
  });

  test("happy path streams deltas and a done frame", async () => {
    __setStreamFactoryForTests(async function* () {
      yield { type: "text", text: "Together " };
      yield { type: "text", text: "we kept " };
      yield { type: "text", text: "circling." };
      yield {
        type: "done",
        usage: { cache_read_input_tokens: 10, input_tokens: 5, output_tokens: 5 }
      };
    });

    const req = makeReq();
    const res = makeRes();
    await handleChatSession(req as any, res as any);

    expect((res as any).headers["Content-Type"]).toBe("text/event-stream");
    const body = (res as any).writes.join("");
    expect(body).toContain('event: delta\ndata: {"text":"Together "}');
    expect(body).toContain('event: delta\ndata: {"text":"we kept "}');
    expect(body).toContain('event: delta\ndata: {"text":"circling."}');
    expect(body).toContain('event: done');
    expect(body).toContain('"cache_hit":true');
  });

  test("mid-stream Anthropic error emits an error frame", async () => {
    __setStreamFactoryForTests(async function* () {
      yield { type: "text", text: "Together " };
      throw new Error("upstream blew up");
    });

    const req = makeReq();
    const res = makeRes();
    await handleChatSession(req as any, res as any);

    const body = (res as any).writes.join("");
    expect(body).toContain('event: delta\ndata: {"text":"Together "}');
    expect(body).toContain('event: error');
    expect((res as any).statusCode).toBe(200);  // headers already sent
  });
});
