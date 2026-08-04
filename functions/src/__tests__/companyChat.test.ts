import {
  companionFor,
  buildSystemPrompt,
  buildContextBlock,
  buildMessages,
  buildRunnableBlock,
  buildSetupBlock,
  validateRunTaskToolUse,
  validateNavigateToolUse,
  validateSetupToolUse,
  coerceRememberFacts,
  parseEnabledSkills,
  buildSkillsBlock,
  WEB_SEARCH_TOOL,
} from "../companyChatCore";

describe("companionFor", () => {
  it("returns the named companion for a known id", () => {
    expect(companionFor("luna").name).toBe("Luna");
    expect(companionFor("luna").voice).toMatch(/gentle|warm/i);
  });
  it("falls back to byte for an unknown id", () => {
    expect(companionFor("does-not-exist").name).toBe("Byte");
  });
  it("has all seven starters", () => {
    for (const id of ["byte", "nova", "crash", "luna", "sage", "glitch", "null"]) {
      expect(companionFor(id).name.length).toBeGreaterThan(0);
    }
  });
});

describe("buildSystemPrompt", () => {
  const base = { companionId: "luna", language: "en" };
  it("names the chosen companion", () => {
    expect(buildSystemPrompt(base)).toContain("Luna");
  });
  it("adds a Vietnamese instruction only for vi", () => {
    expect(buildSystemPrompt({ ...base, language: "vi" })).toMatch(/Vietnamese/i);
    expect(buildSystemPrompt(base)).not.toMatch(/Vietnamese/i);
  });
  it("falls back to byte for an unknown companion", () => {
    expect(buildSystemPrompt({ ...base, companionId: "zzz" })).toContain("Byte");
  });
  it("keeps the per-request context OUT of the cacheable block", () => {
    // The founder's company grounding must live in a separate (uncached) block.
    expect(buildSystemPrompt(base)).not.toMatch(/The founder's company:/);
  });
});

describe("buildContextBlock", () => {
  it("includes the provided context", () => {
    const b = buildContextBlock("Project: Acme. Next step: pricing page.");
    expect(b).toContain("Acme");
    expect(b).toContain("pricing page");
  });
  it("falls back to a general note when context is empty", () => {
    expect(buildContextBlock("")).toMatch(/brief yet/i);
  });
  it("starts with a blank-line separator (system blocks concatenate with no gap)", () => {
    expect(buildContextBlock("x").startsWith("\n\n")).toBe(true);
  });
});

describe("buildMessages", () => {
  it("maps roles and appends the new user message last", () => {
    const m = buildMessages(
      [{ role: "me", text: "hi" }, { role: "companion", text: "hey" }],
      "what next?",
    );
    expect(m).toEqual([
      { role: "user", content: "hi" },
      { role: "assistant", content: "hey" },
      { role: "user", content: "what next?" },
    ]);
  });
  it("drops a leading assistant/companion turn", () => {
    const m = buildMessages([{ role: "companion", text: "welcome" }], "hello");
    expect(m).toEqual([{ role: "user", content: "hello" }]);
  });
  it("coalesces consecutive same-role turns", () => {
    const m = buildMessages(
      [{ role: "me", text: "a" }, { role: "me", text: "b" }],
      "c",
    );
    // a+b (user) coalesced, then final user c coalesced too → one user block
    expect(m).toEqual([{ role: "user", content: "a\n\nb\n\nc" }]);
  });
  it("caps to the last 20 messages", () => {
    const hist = Array.from({ length: 40 }, (_, i) => ({
      role: i % 2 === 0 ? "me" : "companion",
      text: `t${i}`,
    }));
    const m = buildMessages(hist, "final");
    expect(m.length).toBeLessThanOrEqual(20);
    expect(m[m.length - 1]).toEqual({ role: "user", content: "final" });
  });
  it("handles empty history", () => {
    expect(buildMessages([], "only")).toEqual([{ role: "user", content: "only" }]);
  });
});

describe("buildRunnableBlock", () => {
  it("renders id + title for each runnable task", () => {
    const b = buildRunnableBlock([
      { id: "t1", title: "Draft pricing page" },
      { id: "t2", title: "Send investor update" },
    ]);
    expect(b).toContain("RUNNABLE TASKS");
    expect(b).toContain('id:"t1"');
    expect(b).toContain('title:"Draft pricing page"');
    expect(b).toContain('id:"t2"');
    expect(b).toContain('title:"Send investor update"');
  });
  it("returns '' when there are no runnable tasks", () => {
    expect(buildRunnableBlock([])).toBe("");
  });
  it("caps at 60 tasks", () => {
    const many = Array.from({ length: 90 }, (_, i) => ({ id: `t${i}`, title: `Task ${i}` }));
    const b = buildRunnableBlock(many);
    expect(b).toContain('id:"t59"');
    expect(b).not.toContain('id:"t60"');
  });
});

describe("validateRunTaskToolUse", () => {
  const runnable = [
    { id: "t1", title: "Draft pricing page" },
    { id: "t2", title: "Send investor update" },
  ];
  it("matches by task_id", () => {
    expect(validateRunTaskToolUse({ task_id: "t2" }, runnable)).toBe("t2");
  });
  it("falls back to an exact task_title match when task_id doesn't match", () => {
    expect(validateRunTaskToolUse({ task_id: "nope", task_title: "Send investor update" }, runnable)).toBe("t2");
  });
  it("matches by task_title alone", () => {
    expect(validateRunTaskToolUse({ task_title: "Draft pricing page" }, runnable)).toBe("t1");
  });
  it("returns null when nothing matches (hallucinated task)", () => {
    expect(validateRunTaskToolUse({ task_id: "made-up", task_title: "Invented task" }, runnable)).toBeNull();
  });
  it("returns null for junk/empty input", () => {
    expect(validateRunTaskToolUse(null, runnable)).toBeNull();
    expect(validateRunTaskToolUse({}, runnable)).toBeNull();
    expect(validateRunTaskToolUse({ task_id: 42 }, runnable)).toBeNull();
    expect(validateRunTaskToolUse("garbage", runnable)).toBeNull();
  });
  it("returns null when the runnable list is empty", () => {
    expect(validateRunTaskToolUse({ task_id: "t1" }, [])).toBeNull();
  });
});

describe("validateNavigateToolUse", () => {
  it("returns the action for a valid destination with no target", () => {
    expect(validateNavigateToolUse({ destination: "roadmap" })).toEqual({ destination: "roadmap" });
  });
  it("returns the action including target for destination department", () => {
    expect(validateNavigateToolUse({ destination: "department", target: "Marketing" })).toEqual({
      destination: "department",
      target: "Marketing",
    });
  });
  it("omits target when destination isn't department, even if target is present", () => {
    // target is passed through whenever present, regardless of destination —
    // the CF doesn't second-guess which destinations "use" target.
    expect(validateNavigateToolUse({ destination: "roadmap", target: "ignored" })).toEqual({
      destination: "roadmap",
      target: "ignored",
    });
  });
  it("drops (returns null) an unknown destination", () => {
    expect(validateNavigateToolUse({ destination: "not-a-real-place" })).toBeNull();
  });
  it("returns null for junk/empty input", () => {
    expect(validateNavigateToolUse(null)).toBeNull();
    expect(validateNavigateToolUse({})).toBeNull();
    expect(validateNavigateToolUse({ destination: 42 })).toBeNull();
    expect(validateNavigateToolUse("garbage")).toBeNull();
  });
});

describe("buildSetupBlock", () => {
  it("renders category + name + why for each item", () => {
    const b = buildSetupBlock([
      { category: "skills", name: "Code Review", why: "catches bugs early" },
      { category: "connectors", name: "Slack", why: "post updates" },
    ]);
    expect(b).toContain("SETUP TOOLKIT");
    expect(b).toContain('category:"skills"');
    expect(b).toContain('name:"Code Review"');
    expect(b).toContain("catches bugs early");
    expect(b).toContain('category:"connectors"');
    expect(b).toContain('name:"Slack"');
  });
  it("falls back to 'no note' when why is missing", () => {
    expect(buildSetupBlock([{ category: "agents", name: "Researcher" }])).toContain("no note");
  });
  it("returns '' when there are no setup items", () => {
    expect(buildSetupBlock([])).toBe("");
  });
  it("caps at 40 items", () => {
    const many = Array.from({ length: 60 }, (_, i) => ({
      category: "skills" as const,
      name: `Skill ${i}`,
    }));
    const b = buildSetupBlock(many);
    expect(b).toContain('name:"Skill 39"');
    expect(b).not.toContain('name:"Skill 40"');
  });
});

describe("validateSetupToolUse", () => {
  const envSetup = [
    { category: "skills" as const, name: "Code Review", why: "catches bugs" },
    { category: "connectors" as const, name: "Slack" },
  ];
  it("matches by category + name", () => {
    expect(validateSetupToolUse({ category: "skills", name: "Code Review" }, envSetup)).toEqual({
      category: "skills",
      name: "Code Review",
    });
  });
  it("matches case-insensitively on name", () => {
    expect(validateSetupToolUse({ category: "connectors", name: "slack" }, envSetup)).toEqual({
      category: "connectors",
      name: "Slack",
    });
  });
  it("drops when the category doesn't match the name's actual category", () => {
    expect(validateSetupToolUse({ category: "agents", name: "Code Review" }, envSetup)).toBeNull();
  });
  it("drops an invented/hallucinated item", () => {
    expect(validateSetupToolUse({ category: "skills", name: "Invented Skill" }, envSetup)).toBeNull();
  });
  it("returns null for junk/empty input", () => {
    expect(validateSetupToolUse(null, envSetup)).toBeNull();
    expect(validateSetupToolUse({}, envSetup)).toBeNull();
    expect(validateSetupToolUse({ category: "skills" }, envSetup)).toBeNull();
    expect(validateSetupToolUse("garbage", envSetup)).toBeNull();
  });
  it("returns null when the env_setup list is empty", () => {
    expect(validateSetupToolUse({ category: "skills", name: "Code Review" }, [])).toBeNull();
  });
});

describe("coerceRememberFacts", () => {
  it("coerces a valid facts array, lowercasing topic", () => {
    expect(
      coerceRememberFacts({ facts: [{ topic: "Traction", statement: "~300 on the waitlist" }] })
    ).toEqual([{ topic: "traction", statement: "~300 on the waitlist" }]);
  });
  it("handles multiple facts", () => {
    expect(
      coerceRememberFacts({
        facts: [
          { topic: "goal", statement: "Ship by Friday." },
          { topic: "pricing", statement: "$10/mo plan." },
        ],
      })
    ).toEqual([
      { topic: "goal", statement: "Ship by Friday." },
      { topic: "pricing", statement: "$10/mo plan." },
    ]);
  });
  it("clips topic to 40 chars and lowercases it", () => {
    const longTopic = "A".repeat(60);
    const out = coerceRememberFacts({ facts: [{ topic: longTopic, statement: "x" }] });
    expect(out[0].topic).toBe("a".repeat(40));
  });
  it("clips statement to 600 chars", () => {
    const longStatement = "b".repeat(700);
    const out = coerceRememberFacts({ facts: [{ topic: "t", statement: longStatement }] });
    expect(out[0].statement).toBe("b".repeat(600));
  });
  it("drops items missing topic or statement", () => {
    expect(coerceRememberFacts({ facts: [{ topic: "t" }] })).toEqual([]);
    expect(coerceRememberFacts({ facts: [{ statement: "s" }] })).toEqual([]);
    expect(coerceRememberFacts({ facts: [{}] })).toEqual([]);
  });
  it("returns [] when facts is absent, not an array, empty, or input is junk", () => {
    expect(coerceRememberFacts({})).toEqual([]);
    expect(coerceRememberFacts({ facts: [] })).toEqual([]);
    expect(coerceRememberFacts({ facts: "not-an-array" })).toEqual([]);
    expect(coerceRememberFacts(null)).toEqual([]);
    expect(coerceRememberFacts("garbage")).toEqual([]);
  });
});

// ─── handleCompanyChat handler ──────────────────────────────────────────────
// Mirrors chat.test.ts's harness: mocked auth/rateLimit modules, a fake Express
// `res`, and (for the streaming path) an injected fake stream factory standing
// in for the Anthropic call. The JSON path calls the real `client().messages.create`
// wiring, so the Anthropic SDK itself is mocked at module level for those cases.

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

const mockMessagesCreate = jest.fn(async (_args?: any): Promise<any> => ({
  content: [{ type: "text", text: "Hello founder." }],
  usage: { input_tokens: 10, output_tokens: 5 }
}));

jest.mock("@anthropic-ai/sdk", () => {
  return jest.fn().mockImplementation(() => ({
    messages: {
      create: mockMessagesCreate,
      // Only reached if a test forgets to inject a stream factory — fail loudly
      // rather than making a real network call.
      stream: jest.fn(() => {
        throw new Error("real Anthropic stream() called in test — inject a stream factory");
      })
    }
  }));
});

function makeReq(overrides: any = {}): any {
  return {
    method: "POST",
    headers: { authorization: "Bearer good" },
    body: {
      language: "en",
      companion_id: "byte",
      context: "Project: Acme.",
      history: [],
      user_message: "what next?"
    },
    ...overrides
  };
}

function makeRes() {
  const headers: Record<string, string> = {};
  const writes: string[] = [];
  let ended = false;
  return {
    headers,
    writes,
    ended: () => ended,
    setHeader(k: string, v: string) { headers[k] = v; },
    status(code: number) { (this as any).statusCode = code; return this; },
    json(obj: any) { writes.push(JSON.stringify(obj)); ended = true; (this as any).statusCode = (this as any).statusCode || 200; },
    write(chunk: string) { writes.push(chunk); return true; },
    end() { ended = true; },
    flushHeaders() { /* noop */ }
  };
}

describe("handleCompanyChat", () => {
  let handleCompanyChat: typeof import("../companyChat").handleCompanyChat;
  let __setStreamFactoryForTests: typeof import("../companyChat").__setStreamFactoryForTests;
  let __resetStreamFactoryForTests: typeof import("../companyChat").__resetStreamFactoryForTests;

  beforeAll(() => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    // Require after the module-level mocks above are registered.
    ({ handleCompanyChat, __setStreamFactoryForTests, __resetStreamFactoryForTests } = require("../companyChat"));
  });

  beforeEach(() => {
    __resetStreamFactoryForTests();
    mockMessagesCreate.mockClear();
  });

  test("rejects non-POST methods", async () => {
    const req = makeReq({ method: "GET" });
    const res = makeRes();
    await handleCompanyChat(req as any, res as any);
    expect((res as any).statusCode).toBe(405);
  });

  test("returns 401 for missing auth", async () => {
    const req = makeReq({ headers: { authorization: undefined } });
    const res = makeRes();
    await handleCompanyChat(req as any, res as any);
    expect((res as any).statusCode).toBe(401);
  });

  test("returns 400 for missing user_message", async () => {
    const req = makeReq({ body: { ...makeReq().body, user_message: "" } });
    const res = makeRes();
    await handleCompanyChat(req as any, res as any);
    expect((res as any).statusCode).toBe(400);
  });

  // ── Non-streaming JSON path (no Accept header) — unchanged ────────────────

  describe("JSON path (no Accept: text/event-stream)", () => {
    test("returns {reply, run_task_id} on success", async () => {
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      expect((res as any).statusCode).toBe(200);
      expect(mockMessagesCreate).toHaveBeenCalledTimes(1);
      const body = JSON.parse((res as any).writes[0]);
      expect(body).toEqual({ reply: "Hello founder.", run_task_id: null });
    });

    // ── founder style (Settings → AI) placement in the system blocks ─────────
    // The behavioural point of the tone controls: the fragment has to land AFTER
    // the persona sentence it may override ("No hype, no filler, no emoji") and
    // BEFORE the company grounding, and it must stay out of the cached static
    // block so a per-founder string doesn't shatter cache sharing.

    test("style_fragment lands at the head of the volatile block, after the persona, before the company", async () => {
      const req = makeReq({
        body: { ...makeReq().body, style_fragment: "Never use emoji." }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const call = mockMessagesCreate.mock.calls[0][0] as any;
      const [staticBlock, volatileBlock] = call.system as Array<{ text: string }>;
      // Static (cached) block keeps the persona sentence and gains nothing.
      expect(staticBlock.text).toContain("no emoji");
      expect(staticBlock.text).not.toContain("Never use emoji.");
      // Volatile block: style first, company grounding after it.
      expect(volatileBlock.text.startsWith("\n\nHow the founder wants you to write:\nNever use emoji.")).toBe(true);
      expect(volatileBlock.text.indexOf("How the founder wants you to write:"))
        .toBeLessThan(volatileBlock.text.indexOf("The founder's company:"));
    });

    test("omitting style_fragment leaves the system prompt byte-for-byte unchanged", async () => {
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const call = mockMessagesCreate.mock.calls[0][0] as any;
      const volatileBlock = (call.system as Array<{ text: string }>)[1];
      expect(volatileBlock.text).not.toContain("How the founder wants you to write");
      expect(volatileBlock.text.startsWith("\n\nThe founder's company:")).toBe(true);
    });

    test("returns 429 when rate-limited (before any Anthropic call)", async () => {
      const rl = require("../rateLimit");
      rl.checkAndIncrement.mockImplementationOnce(async () => ({
        allowed: false,
        resetAt: new Date("2026-05-08T00:00:00Z"),
        limit: 50
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);
      expect((res as any).statusCode).toBe(429);
      expect(mockMessagesCreate).not.toHaveBeenCalled();
    });

    test("returns 502 when the Anthropic call fails", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => {
        throw new Error("upstream down");
      });
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);
      expect((res as any).statusCode).toBe(502);
    });

    // ── run_task tool (non-stream) ──────────────────────────────────────────

    test("run_task_id is the matched task id when the model calls run_task with a valid task_id", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "text", text: "On it — running that now." },
          { type: "tool_use", id: "toolu_1", name: "run_task", input: { task_id: "t1", task_title: "Draft pricing page" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: {
          ...makeReq().body,
          runnable: [{ id: "t1", title: "Draft pricing page" }, { id: "t2", title: "Send investor update" }]
        }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      expect((res as any).statusCode).toBe(200);
      const body = JSON.parse((res as any).writes[0]);
      expect(body.reply).toBe("On it — running that now.");
      expect(body.run_task_id).toBe("t1");

      // tools were actually offered to the model this turn — run_task because
      // runnable was non-empty, plus the always-on navigate + remember_fact.
      const call = mockMessagesCreate.mock.calls[0][0] as any;
      expect((call.tools as any[]).map((t) => t.name)).toEqual([
        "run_task",
        "navigate",
        "remember_fact",
      ]);
    });

    test("run_task_id stays null when the model's tool_use references a task not in runnable", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "run_task", input: { task_id: "made-up" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: { ...makeReq().body, runnable: [{ id: "t1", title: "Draft pricing page" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.run_task_id).toBeNull();
    });

    test("only the always-on navigate + remember_fact tools are offered, and run_task_id is null, when runnable/env_setup are omitted (backward compat)", async () => {
      const req = makeReq(); // no `runnable`, no `env_setup` on the body at all
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      // Exact shape match — old clients that only look for {reply, run_task_id}
      // must see nothing new when nav/setup/remember never fired.
      expect(body).toEqual({ reply: "Hello founder.", run_task_id: null });
      const call = mockMessagesCreate.mock.calls[0][0] as any;
      expect((call.tools as any[]).map((t) => t.name)).toEqual(["navigate", "remember_fact"]);
    });

    // ── navigate tool (non-stream) ──────────────────────────────────────────

    test("response nav is set when the model calls navigate with a valid destination", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "text", text: "Here's your roadmap." },
          { type: "tool_use", id: "toolu_1", name: "navigate", input: { destination: "roadmap" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.nav).toEqual({ destination: "roadmap" });
    });

    test("response nav includes target for destination department", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "navigate", input: { destination: "department", target: "Marketing" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.nav).toEqual({ destination: "department", target: "Marketing" });
    });

    test("nav is dropped (absent) when navigate is called with an invalid destination", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "navigate", input: { destination: "not-a-real-place" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.nav).toBeUndefined();
    });

    // ── setup_capability tool (non-stream) ──────────────────────────────────

    test("response setup is set when setup_capability matches an env_setup item", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "text", text: "Want me to turn that on?" },
          { type: "tool_use", id: "toolu_1", name: "setup_capability", input: { category: "skills", name: "Code Review" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: {
          ...makeReq().body,
          env_setup: [{ category: "skills", name: "Code Review", why: "catches bugs early" }]
        }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.setup).toEqual({ category: "skills", name: "Code Review" });

      // the setup tool was actually offered because env_setup was non-empty.
      const call = mockMessagesCreate.mock.calls[0][0] as any;
      expect((call.tools as any[]).map((t) => t.name)).toContain("setup_capability");
    });

    test("setup is dropped (absent) when setup_capability doesn't match any env_setup item", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "setup_capability", input: { category: "skills", name: "Invented Skill" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: { ...makeReq().body, env_setup: [{ category: "skills", name: "Code Review" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.setup).toBeUndefined();
    });

    test("setup_capability tool is not offered when env_setup is empty", async () => {
      const req = makeReq(); // no env_setup at all
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const call = mockMessagesCreate.mock.calls[0][0] as any;
      expect((call.tools as any[]).map((t) => t.name)).not.toContain("setup_capability");
    });

    // ── remember_fact tool (non-stream) ─────────────────────────────────────

    test("response remember is set with coerced facts when the model calls remember_fact", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "text", text: "Got it." },
          {
            type: "tool_use",
            id: "toolu_1",
            name: "remember_fact",
            input: { facts: [{ topic: "Traction", statement: "~300 people on the waitlist" }] }
          }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.remember).toEqual([{ topic: "traction", statement: "~300 people on the waitlist" }]);
    });

    test("remember is absent when remember_fact fires with an empty facts array", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "remember_fact", input: { facts: [] } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.remember).toBeUndefined();
    });

    test("remember_fact is orthogonal — it co-occurs with run_task in the same turn", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "run_task", input: { task_id: "t1" } },
          {
            type: "tool_use",
            id: "toolu_2",
            name: "remember_fact",
            input: { facts: [{ topic: "goal", statement: "Ship the pricing page this week." }] }
          }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: { ...makeReq().body, runnable: [{ id: "t1", title: "Draft pricing page" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.run_task_id).toBe("t1");
      expect(body.remember).toEqual([{ topic: "goal", statement: "Ship the pricing page this week." }]);
    });

    test("mutual exclusion: run_task wins over navigate when both are somehow present", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "run_task", input: { task_id: "t1" } },
          { type: "tool_use", id: "toolu_2", name: "navigate", input: { destination: "roadmap" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: { ...makeReq().body, runnable: [{ id: "t1", title: "Draft pricing page" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.run_task_id).toBe("t1");
      expect(body.nav).toBeUndefined();
    });

    test("mutual exclusion: navigate wins over setup_capability when run_task didn't fire", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "navigate", input: { destination: "library" } },
          { type: "tool_use", id: "toolu_2", name: "setup_capability", input: { category: "skills", name: "Code Review" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: { ...makeReq().body, env_setup: [{ category: "skills", name: "Code Review" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.nav).toEqual({ destination: "library" });
      expect(body.setup).toBeUndefined();
    });

    test("falls through to setup_capability when run_task fired but was hallucinated (invalid)", async () => {
      mockMessagesCreate.mockImplementationOnce(async () => ({
        content: [
          { type: "tool_use", id: "toolu_1", name: "run_task", input: { task_id: "made-up" } },
          { type: "tool_use", id: "toolu_2", name: "setup_capability", input: { category: "skills", name: "Code Review" } }
        ],
        usage: { input_tokens: 10, output_tokens: 5 }
      }));
      const req = makeReq({
        body: {
          ...makeReq().body,
          runnable: [{ id: "t1", title: "Draft pricing page" }],
          env_setup: [{ category: "skills", name: "Code Review" }]
        }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = JSON.parse((res as any).writes[0]);
      expect(body.run_task_id).toBeNull();
      expect(body.setup).toEqual({ category: "skills", name: "Code Review" });
    });
  });

  // ── Streaming path (Accept: text/event-stream) — new, opt-in ──────────────

  describe("SSE path (Accept: text/event-stream)", () => {
    function makeStreamingReq(overrides: any = {}): any {
      return makeReq({
        headers: { authorization: "Bearer good", accept: "text/event-stream" },
        ...overrides
      });
    }

    test("streams delta frames and a final done frame, matching chat.ts's format", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "Here's " };
        yield { type: "text", text: "the plan." };
        yield {
          type: "done",
          usage: { cache_read_input_tokens: 10, input_tokens: 5, output_tokens: 5 }
        };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      expect((res as any).headers["Content-Type"]).toBe("text/event-stream");
      expect(mockMessagesCreate).not.toHaveBeenCalled(); // streaming path never touches the JSON call

      const body = (res as any).writes.join("");
      expect(body).toContain('event: delta\ndata: {"text":"Here\'s "}');
      expect(body).toContain('event: delta\ndata: {"text":"the plan."}');
      expect(body).toContain('event: done');
      expect(body).toContain('"cache_hit":true');
      expect(body).toContain('"model":"claude-sonnet-5"');
      expect((res as any).ended()).toBe(true);
    });

    test("a server-side tool block never becomes a phantom client action", async () => {
      // Anthropic runs web_search itself, so its block arrives as
      // `server_tool_use` — which the raw-event mapper does NOT open an
      // accumulator for. Its input still streams and its block still closes, so
      // the handler sees a tool_use_delta + tool_use_stop for an index that was
      // never started. That must be inert: an unguarded accumulator would
      // fabricate a tool call out of a search the founder never asked for.
      __setStreamFactoryForTests(async function* () {
        yield { type: "tool_use_delta", index: 0, partial_json: '{"query":"claude pricing"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "text", text: "Sonnet 5 is $3/MTok in." };
        yield { type: "done", usage: { input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('event: delta\ndata: {"text":"Sonnet 5 is $3/MTok in."}');
      expect(body).toContain("event: done");
      // No action of any kind was invented from the server-side search.
      expect(body).not.toContain('"run_task_id":"');
      expect(body).not.toContain('"nav":');
      expect(body).not.toContain('"setup":');
      expect((res as any).ended()).toBe(true);
    });

    test("mid-stream failure emits an error frame (headers already sent)", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "Here's " };
        throw new Error("upstream blew up");
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('event: delta\ndata: {"text":"Here\'s "}');
      expect(body).toContain('event: error');
      expect((res as any).statusCode).toBe(200); // headers already sent — SSE convention from chat.ts
    });

    test("pre-stream auth failure returns a plain 401 JSON error, not an SSE frame", async () => {
      const req = makeStreamingReq({ headers: { authorization: undefined, accept: "text/event-stream" } });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      expect((res as any).statusCode).toBe(401);
      expect((res as any).headers["Content-Type"]).toBeUndefined();
      const body = JSON.parse((res as any).writes[0]);
      expect(body).toEqual({ error: "invalid_token" });
    });

    test("pre-stream rate-limit failure returns a plain 429 JSON error, not an SSE frame", async () => {
      const rl = require("../rateLimit");
      rl.checkAndIncrement.mockImplementationOnce(async () => ({
        allowed: false,
        resetAt: new Date("2026-05-08T00:00:00Z"),
        limit: 50
      }));
      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      expect((res as any).statusCode).toBe(429);
      expect((res as any).headers["Content-Type"]).toBeUndefined();
      const body = JSON.parse((res as any).writes[0]);
      expect(body.error).toBe("daily_limit_reached");
    });

    // ── run_task tool (streaming) ───────────────────────────────────────────

    test("accumulates a streamed run_task tool_use block and carries the validated id on the done frame", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "On it — " };
        yield { type: "text", text: "running that now." };
        // A run_task tool_use block streamed in fragments, mirroring how Anthropic
        // streams tool input: content_block_start (name), input_json_delta
        // fragments, then content_block_stop.
        yield { type: "tool_use_start", index: 1, name: "run_task" };
        yield { type: "tool_use_delta", index: 1, partial_json: '{"task_id":"t1",' };
        yield { type: "tool_use_delta", index: 1, partial_json: '"task_title":"Draft pricing page"}' };
        yield { type: "tool_use_stop", index: 1 };
        yield {
          type: "done",
          usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 }
        };
      });

      const req = makeStreamingReq({
        body: {
          ...makeReq().body,
          runnable: [{ id: "t1", title: "Draft pricing page" }, { id: "t2", title: "Send investor update" }]
        }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('event: delta\ndata: {"text":"On it — "}');
      expect(body).toContain('event: delta\ndata: {"text":"running that now."}');
      expect(body).toContain('event: done');
      expect(body).toContain('"run_task_id":"t1"');
      expect((res as any).ended()).toBe(true);
    });

    test("streamed run_task tool_use with a hallucinated task_id yields run_task_id: null on the done frame", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "tool_use_start", index: 0, name: "run_task" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"task_id":"made-up"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq({
        body: { ...makeReq().body, runnable: [{ id: "t1", title: "Draft pricing page" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('"run_task_id":null');
    });

    test("no run_task tool_use in the stream still yields run_task_id: null on the done frame (backward compat)", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "Just a plain reply." };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('"run_task_id":null');
      // navigate/setup/remember fields are absent — old clients unaffected.
      expect(body).not.toContain('"nav"');
      expect(body).not.toContain('"setup"');
      expect(body).not.toContain('"remember"');
    });

    // ── navigate tool (streaming) ────────────────────────────────────────────

    test("a stream emitting text + a navigate tool_use → done frame carries nav", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "Here's your library." };
        yield { type: "tool_use_start", index: 0, name: "navigate" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"destination":"library"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('event: done');
      expect(body).toContain('"nav":{"destination":"library"}');
    });

    test("a streamed navigate tool_use with an invalid destination yields no nav field on the done frame", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "tool_use_start", index: 0, name: "navigate" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"destination":"not-a-real-place"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).not.toContain('"nav"');
    });

    // ── setup_capability tool (streaming) ───────────────────────────────────

    test("a streamed setup_capability tool_use matching an env_setup item → done frame carries setup", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "tool_use_start", index: 0, name: "setup_capability" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"category":"skills",' };
        yield { type: "tool_use_delta", index: 0, partial_json: '"name":"Code Review"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq({
        body: { ...makeReq().body, env_setup: [{ category: "skills", name: "Code Review" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('"setup":{"category":"skills","name":"Code Review"}');
    });

    // ── remember_fact tool (streaming) — orthogonal ─────────────────────────

    test("a stream with remember_fact + run_task together → both remember and run_task_id on the done frame", async () => {
      __setStreamFactoryForTests(async function* () {
        yield { type: "text", text: "On it — " };
        yield { type: "tool_use_start", index: 0, name: "run_task" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"task_id":"t1"}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "tool_use_start", index: 1, name: "remember_fact" };
        yield {
          type: "tool_use_delta",
          index: 1,
          partial_json: '{"facts":[{"topic":"Goal","statement":"Ship the pricing page this week."}]}'
        };
        yield { type: "tool_use_stop", index: 1 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq({
        body: { ...makeReq().body, runnable: [{ id: "t1", title: "Draft pricing page" }] }
      });
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('"run_task_id":"t1"');
      expect(body).toContain('"remember":[{"topic":"goal","statement":"Ship the pricing page this week."}]');
    });

    test("interleaved tool_use blocks by index are accumulated independently", async () => {
      // Two tool_use blocks streamed with interleaved deltas (out-of-order
      // fragment delivery relative to each other) — the accumulator keys by
      // index, so this must not cross-contaminate the two JSON buffers.
      __setStreamFactoryForTests(async function* () {
        yield { type: "tool_use_start", index: 0, name: "navigate" };
        yield { type: "tool_use_start", index: 1, name: "remember_fact" };
        yield { type: "tool_use_delta", index: 0, partial_json: '{"destination"' };
        yield { type: "tool_use_delta", index: 1, partial_json: '{"facts":[{"topic":"pricing",' };
        yield { type: "tool_use_delta", index: 0, partial_json: ':"tasks"}' };
        yield { type: "tool_use_delta", index: 1, partial_json: '"statement":"$10/mo plan decided."}]}' };
        yield { type: "tool_use_stop", index: 0 };
        yield { type: "tool_use_stop", index: 1 };
        yield { type: "done", usage: { cache_read_input_tokens: 0, input_tokens: 5, output_tokens: 5 } };
      });

      const req = makeStreamingReq();
      const res = makeRes();
      await handleCompanyChat(req as any, res as any);

      const body = (res as any).writes.join("");
      expect(body).toContain('"nav":{"destination":"tasks"}');
      expect(body).toContain('"remember":[{"topic":"pricing","statement":"$10/mo plan decided."}]');
    });
  });
});

describe("parseEnabledSkills", () => {
  it("keeps only ids the backend actually implements", () => {
    const s = parseEnabledSkills(["web-research", "prd-writer"]);
    expect(s.has("web-research")).toBe(true);
    expect(s.has("prd-writer")).toBe(true);
    expect(s.size).toBe(2);
  });
  it("drops catalog items that exist in the app but have no implementation", () => {
    // The founder can toggle these on today; nothing is built behind them, so
    // the CF must ignore them rather than pretend.
    const s = parseEnabledSkills(["code-review", "changelog", "explorer", "migrator"]);
    expect(s.size).toBe(0);
  });
  it("normalizes case and whitespace", () => {
    expect(parseEnabledSkills(["  Web-Research "]).has("web-research")).toBe(true);
  });
  it("ignores non-arrays and non-strings", () => {
    expect(parseEnabledSkills(undefined).size).toBe(0);
    expect(parseEnabledSkills("web-research").size).toBe(0);
    expect(parseEnabledSkills([1, null, {}, ["web-research"]]).size).toBe(0);
  });
  it("dedupes", () => {
    expect(parseEnabledSkills(["web-research", "web-research"]).size).toBe(1);
  });
});

describe("buildSkillsBlock", () => {
  it("is empty when no skills are on, leaving the prompt untouched", () => {
    expect(buildSkillsBlock(new Set())).toBe("");
  });
  it("describes only the skills that are on", () => {
    const b = buildSkillsBlock(new Set(["prd-writer"]));
    expect(b).toContain("SKILLS THE FOUNDER HAS TURNED ON");
    expect(b).toContain("PRD writer");
    expect(b).not.toContain("Web research");
  });
  it("tells web research not to search what the context already answers", () => {
    // The cost guard: an unconditional searcher would bill on every turn.
    expect(buildSkillsBlock(new Set(["web-research"]))).toMatch(/already answered by the/i);
  });
  it("can carry both at once", () => {
    const b = buildSkillsBlock(new Set(["web-research", "prd-writer"]));
    expect(b).toContain("Web research");
    expect(b).toContain("PRD writer");
  });
});

describe("WEB_SEARCH_TOOL", () => {
  it("is the dated server-side tool type the chat model supports", () => {
    expect(WEB_SEARCH_TOOL.type).toBe("web_search_20260209");
    expect(WEB_SEARCH_TOOL.name).toBe("web_search");
  });
  it("caps searches per request so one turn cannot outspend a day of chat", () => {
    expect(WEB_SEARCH_TOOL.max_uses).toBeGreaterThan(0);
    expect(WEB_SEARCH_TOOL.max_uses).toBeLessThanOrEqual(5);
  });
});
