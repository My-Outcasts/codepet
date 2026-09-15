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
  resolveActions,
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

// ─── handleCompanyChat's harness was deleted with the handler ────────────────
// Everything between this point and `parseEnabledSkills` mocked ../auth, ../rateLimit
// and @anthropic-ai/sdk to drive the hosted companyChat endpoint down its JSON and SSE
// paths. That endpoint spent ANTHROPIC_API_KEY and is gone; the local transport streams
// through local/chatSidecar.ts (chatSidecar.test.ts) and reaches the SAME builders this
// file still exercises above and below — companyChatCore.ts is what esbuild bundles into
// the app, and it is untouched.

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

/**
 * `resolveActions` is the one place the mutual exclusion between the client actions is
 * decided, and it runs in the sidecar bundle shipped inside the app (chatSidecar.ts calls
 * it with the same lists `buildChatRequest` prompted with). The individual validators are
 * asserted above in isolation; what is asserted HERE is the chain between them —
 * run_task beats navigate beats setup, complete_task excludes add_task, and remember_fact
 * is orthogonal to all of it. Deleting a `!runTaskId` guard has to turn one of these red.
 *
 * Ported from the deleted `companyChat.test.ts` (9051460), which asserted these same
 * behaviours through the now-removed HTTP handler: cases at lines 517, 686, 710, 729, 748.
 */
describe("resolveActions — the precedence chain", () => {
  const runnable = [{ id: "t1", title: "Draft pricing page" }];
  const envSetup = [{ category: "skills" as const, name: "Code Review" }];
  const openTasks = [{ id: "o1", title: "Call the bank" }];

  // companyChat.test.ts:517 — "run_task_id stays null when the model's tool_use
  // references a task not in runnable"
  it("leaves runTaskId null when run_task names a task that is not runnable", () => {
    const r = resolveActions(
      [{ name: "run_task", input: { task_id: "made-up" } }],
      runnable,
      [],
      []
    );
    expect(r.runTaskId).toBeNull();
  });

  // companyChat.test.ts:686 — "remember_fact is orthogonal — it co-occurs with run_task
  // in the same turn"
  it("resolves remember_fact alongside run_task — it is orthogonal, not excluded", () => {
    const r = resolveActions(
      [
        { name: "run_task", input: { task_id: "t1" } },
        {
          name: "remember_fact",
          input: { facts: [{ topic: "goal", statement: "Ship the pricing page this week." }] },
        },
      ],
      runnable,
      [],
      []
    );
    expect(r.runTaskId).toBe("t1");
    expect(r.remember).toEqual([{ topic: "goal", statement: "Ship the pricing page this week." }]);
  });

  // companyChat.test.ts:710 — "mutual exclusion: run_task wins over navigate when both
  // are somehow present"
  it("run_task wins over navigate when both are present", () => {
    const r = resolveActions(
      [
        { name: "run_task", input: { task_id: "t1" } },
        { name: "navigate", input: { destination: "roadmap" } },
      ],
      runnable,
      [],
      []
    );
    expect(r.runTaskId).toBe("t1");
    expect(r.nav).toBeNull();
  });

  // companyChat.test.ts:729 — "mutual exclusion: navigate wins over setup_capability when
  // run_task didn't fire"
  it("navigate wins over setup_capability when run_task did not fire", () => {
    const r = resolveActions(
      [
        { name: "navigate", input: { destination: "library" } },
        { name: "setup_capability", input: { category: "skills", name: "Code Review" } },
      ],
      [],
      envSetup,
      []
    );
    expect(r.nav).toEqual({ destination: "library" });
    expect(r.setup).toBeNull();
  });

  // companyChat.test.ts:748 — "falls through to setup_capability when run_task fired but
  // was hallucinated (invalid)"
  it("falls through to setup_capability when run_task fired but was hallucinated", () => {
    const r = resolveActions(
      [
        { name: "run_task", input: { task_id: "made-up" } },
        { name: "setup_capability", input: { category: "skills", name: "Code Review" } },
      ],
      runnable,
      envSetup,
      []
    );
    expect(r.runTaskId).toBeNull();
    expect(r.setup).toEqual({ category: "skills", name: "Code Review" });
  });

  // Not one of the five recovered cases — the other half of the chain named in the
  // review. The two roadmap verbs are independent of run/nav/setup but exclude EACH
  // OTHER, and nothing asserted that either.
  it("complete_task excludes add_task, and both are independent of run_task", () => {
    const r = resolveActions(
      [
        { name: "run_task", input: { task_id: "t1" } },
        { name: "complete_task", input: { task_id: "o1" } },
        { name: "add_task", input: { title: "Write the launch email" } },
      ],
      runnable,
      [],
      openTasks
    );
    expect(r.runTaskId).toBe("t1");
    expect(r.completeTaskId).toBe("o1");
    expect(r.addTask).toBeNull();
  });
});
