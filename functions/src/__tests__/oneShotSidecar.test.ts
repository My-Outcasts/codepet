import {
  ONE_SHOT_OPS,
  OneShotBadRequest,
  OneShotUnusableAnswer,
  extractJson,
  pickModel,
  schemaInstruction,
} from "../local/oneShotOps";
import { claudeArgs, renderPrompt } from "../local/oneShotSidecar";
import { ENRICH_TOOL, buildEnrichPrompt } from "../enrichBrief";
import { OVERVIEW_TOOL, synthesizeSystemPrompt } from "../synthesizeBrief";
import { ROADMAP_TOOL, buildRoadmapPrompt } from "../generateRoadmapCore";

/**
 * The local one-shot path: the non-streaming Cloud Functions running on the founder's own
 * Claude Code instead of an API key. Only the pure parts are tested here; the process
 * wiring is proven by actually running the sidecar against a real `claude`.
 */

describe("claudeArgs", () => {
  /**
   * THE guard in this file. These ops read a founder's notes and answer; a run that could
   * also edit files or execute a shell is a different, much larger permission than the
   * feature needs. Delete `--tools ""` and this goes red.
   */
  it("grants no tools at all", () => {
    const args = claudeArgs({ systemPrompt: "s" });
    const at = args.indexOf("--tools");
    expect(at).toBeGreaterThan(-1);
    expect(args[at + 1]).toBe("");
    expect(args.join(" ")).not.toMatch(/Bash|Edit|Write|allowedTools/);
  });

  /**
   * Strict WITHOUT a config file is what excludes every MCP server. Chat has to pass both
   * flags because it ships a server; here the exclusion is the entire point, so a stray
   * `--mcp-config` would be a regression rather than a tidy-up.
   */
  it("excludes every MCP server, and names no config to re-admit one", () => {
    const args = claudeArgs({ systemPrompt: "s" });
    expect(args).toContain("--strict-mcp-config");
    expect(args).not.toContain("--mcp-config");
  });

  /** The founder's own settings, and therefore their hooks, stay out of Codepet's turn. */
  it("reads no setting sources", () => {
    const args = claudeArgs({ systemPrompt: "s" });
    const at = args.indexOf("--setting-sources");
    expect(at).toBeGreaterThan(-1);
    expect(args[at + 1]).toBe("");
  });

  it("asks for the json envelope, not a stream", () => {
    const args = claudeArgs({ systemPrompt: "s" });
    expect(args[args.indexOf("--output-format") + 1]).toBe("json");
  });

  /**
   * Absent means "whatever the founder's Claude Code already uses". Passing an empty
   * `--model` would instead be an argument the CLI has to interpret.
   */
  it("passes model and effort only when the founder chose one", () => {
    expect(claudeArgs({ systemPrompt: "s" })).not.toContain("--model");
    expect(claudeArgs({ systemPrompt: "s" })).not.toContain("--effort");
    const chosen = claudeArgs({ systemPrompt: "s", model: "haiku", effort: "medium" });
    expect(chosen[chosen.indexOf("--model") + 1]).toBe("haiku");
    expect(chosen[chosen.indexOf("--effort") + 1]).toBe("medium");
  });
});

describe("schemaInstruction", () => {
  /**
   * The schema travels as the schema. A paraphrase would be a second source of truth, and
   * the first field added to the tool would only reach one of the two transports.
   */
  it("carries the tool's own input_schema, field names and all", () => {
    const text = schemaInstruction(ENRICH_TOOL.input_schema);
    expect(text).toContain('"summary"');
    expect(text).toContain('"audience"');
    expect(text).toContain('"categories"');
  });

  /**
   * `buildSynthesizeUserMessage` ends with "Now call record_overview with ..." — correct for
   * the API's forced tool, impossible under `claude -p`. Contradicting it beats forking the
   * builder, so the instruction has to actually say so.
   */
  it("cancels the tool call the shared prompts ask for", () => {
    expect(schemaInstruction({}).toLowerCase()).toContain("no tools available");
  });

  it("asks for the object alone, with no fence and no prose", () => {
    const text = schemaInstruction({}).toLowerCase();
    expect(text).toContain("only that json object");
    expect(text).toContain("no code fence");
  });
});

describe("renderPrompt", () => {
  it("keeps the shared builder's text first, verbatim", () => {
    const built = buildEnrichPrompt({ projectName: "Codepet", oneLiner: "an app" });
    expect(renderPrompt(built, ENRICH_TOOL.input_schema).startsWith(built)).toBe(true);
  });
});

describe("extractJson", () => {
  it("reads a bare object", () => {
    expect(extractJson('{"a":1}')).toEqual({ a: 1 });
  });

  it("reads one wrapped in a fence, which is still an answer", () => {
    expect(extractJson('```json\n{"a":1}\n```')).toEqual({ a: 1 });
  });

  it("reads one after a sentence of preamble", () => {
    expect(extractJson('Sure, here it is:\n{"a":1}\nHope that helps.')).toEqual({ a: 1 });
  });

  /**
   * Not a regex, and this is why: a founder's summary is ordinary text that may contain a
   * brace or an escaped quote, and a greedy or lazy pattern mangles one of those two cases.
   */
  it("survives braces and escaped quotes inside strings", () => {
    expect(extractJson('{"summary":"uses {curly} and a \\" quote"}')).toEqual({
      summary: 'uses {curly} and a " quote',
    });
  });

  it("refuses a reply with no object rather than inventing one", () => {
    expect(() => extractJson("I cannot help with that.")).toThrow(OneShotUnusableAnswer);
  });

  it("refuses a truncated object", () => {
    expect(() => extractJson('{"a": 1')).toThrow(OneShotUnusableAnswer);
  });

  it("refuses an object that is not valid JSON", () => {
    expect(() => extractJson("{a: 1}")).toThrow(OneShotUnusableAnswer);
  });
});

describe("pickModel", () => {
  /**
   * A run bills small side calls as well as the answer — measured: a Haiku entry alongside
   * the answering model. The one that wrote the answer is the one with the output tokens.
   */
  it("reports the model that actually produced the answer", () => {
    expect(pickModel({
      modelUsage: {
        "claude-haiku-4-5": { outputTokens: 14 },
        "claude-opus-5": { outputTokens: 83 },
      },
    })).toBe("claude-opus-5");
  });

  it("falls back to an honest placeholder rather than guessing", () => {
    expect(pickModel({})).toBe("claude-code-local");
    expect(pickModel({ modelUsage: {} })).toBe("claude-code-local");
  });
});

describe("enrichBrief op", () => {
  const op = ONE_SHOT_OPS.enrichBrief;

  /**
   * Both short circuits the handler has, for the same reason: the cloud path answers these
   * without spending a token, so the local path must not spend a turn of the founder's plan.
   */
  it("answers an already-summarised brief without a model call", () => {
    const brief = { projectName: "Codepet", oneLiner: "an app", summary: "already done" };
    expect(op.plan({ brief })).toEqual({ answer: { brief } });
  });

  it("answers a brief with nothing to read without a model call", () => {
    const brief = { projectName: "Codepet" };
    expect(op.plan({ brief })).toEqual({ answer: { brief } });
  });

  /**
   * Driven from the builder rather than a fixture: a prompt edited for the cloud path must
   * reach the local path in the same keystroke, and this is what says so.
   */
  it("asks with the Cloud Function's own prompt and schema", () => {
    const brief = { projectName: "Codepet", oneLiner: "an app for founders" };
    const plan = op.plan({ brief });
    expect(plan.prompt).toBe(buildEnrichPrompt(brief));
    expect(plan.schema).toBe(ENRICH_TOOL.input_schema);
    expect(plan.answer).toBeUndefined();
  });

  it("refuses a payload with no brief", () => {
    expect(() => op.plan({})).toThrow(OneShotBadRequest);
    expect(() => op.plan({ brief: "not an object" })).toThrow(OneShotBadRequest);
  });

  /**
   * The local answer goes through the SAME merge as the API's, which is what keeps a sloppy
   * one safe: what the founder typed wins, and the response shape stays `{brief}`.
   */
  it("merges without overwriting what the founder typed", () => {
    const brief = { projectName: "Codepet", oneLiner: "an app", audience: "founders" };
    const out = op.respond(
      { brief },
      { summary: "It is an app.", audience: "everyone", categories: ["dev tools"] },
      { model: "m", nowISO: "2026-08-26T00:00:00.000Z" }
    ) as any;
    expect(out.brief.audience).toBe("founders");
    expect(out.brief.summary).toBe("It is an app.");
    expect(out.brief.categories).toEqual(["dev tools"]);
  });

  it("refuses an answer that is not an object", () => {
    expect(() => op.respond({ brief: {} }, "prose", { model: "m", nowISO: "t" }))
      .toThrow(OneShotUnusableAnswer);
  });
});

describe("synthesizeBrief op", () => {
  const op = ONE_SHOT_OPS.synthesizeBrief;
  const payload = {
    language: "vi" as const,
    project: { name: "Codepet" },
    sessions: [{ summary: "Built the roadmap screen" }],
  };

  it("validates with the handler's own validator", () => {
    expect(() => op.plan({ ...payload, language: "fr" })).toThrow(OneShotBadRequest);
    expect(() => op.plan({ ...payload, sessions: [] })).toThrow(OneShotBadRequest);
  });

  /** A Vietnamese founder must not get an English overview on one transport only. */
  it("carries the founder's output language into the system prompt", () => {
    expect(op.plan(payload).system).toBe(synthesizeSystemPrompt("vi"));
    expect(op.plan({ ...payload, language: "en" }).system).toBe(synthesizeSystemPrompt("en"));
    expect(op.plan(payload).schema).toBe(OVERVIEW_TOOL.input_schema);
  });

  it("answers the response body the client already decodes", () => {
    const out = op.respond(payload, { overview: "  You are building Codepet.  " }, {
      model: "claude-opus-5",
      nowISO: "2026-08-26T00:00:00.000Z",
    }) as any;
    expect(out).toEqual({
      overview: "You are building Codepet.",
      model: "claude-opus-5",
      generated_at: "2026-08-26T00:00:00.000Z",
    });
  });

  /** The handler answers 502 rather than writing a blank description into the brief box. */
  it("refuses an empty overview", () => {
    const meta = { model: "m", nowISO: "t" };
    expect(() => op.respond(payload, { overview: "   " }, meta)).toThrow(OneShotUnusableAnswer);
    expect(() => op.respond(payload, {}, meta)).toThrow(OneShotUnusableAnswer);
  });
});

describe("generateRoadmap op", () => {
  const op = ONE_SHOT_OPS.generateRoadmap;
  const brief = { projectName: "Codepet", oneLiner: "an app for founders" };

  it("asks with the Cloud Function's own prompt and schema", () => {
    const plan = op.plan({ language: "vi", brief });
    expect(plan.prompt).toBe(buildRoadmapPrompt({ language: "vi", brief }));
    expect(plan.schema).toBe(ROADMAP_TOOL.input_schema);
  });

  /** An unknown language must not reach the prompt builder as itself. */
  it("narrows the language the way the handler does", () => {
    expect(op.plan({ language: "fr", brief }).prompt)
      .toBe(buildRoadmapPrompt({ language: "en", brief }));
  });

  it("refuses a payload with no brief", () => {
    expect(() => op.plan({ language: "en" })).toThrow(OneShotBadRequest);
    expect(() => op.plan({ language: "en", brief: [] })).toThrow(OneShotBadRequest);
  });

  /**
   * `coerceRoadmap` is the whole safety story on this transport: the API forces a schema,
   * `claude -p` cannot, so a loose answer has to be filtered rather than trusted. If this
   * stops running, a made-up phase reaches the founder's board.
   */
  it("coerces the answer instead of trusting it", () => {
    const out = op.respond({ language: "en", brief }, {
      tasks: [
        { phase: "build", title: "Ship the roadmap screen", detail: "d", who: "you", dept: "eng", deps: [] },
        { phase: "not-a-phase", title: "Nonsense", detail: "d", who: "you", dept: "eng", deps: [] },
      ],
    }, { model: "m", nowISO: "t" }) as any;
    expect(out.tasks.map((t: any) => t.title)).toEqual(["Ship the roadmap screen"]);
  });

  /** The client reads `[]` as "no change", so a junk answer must degrade to that. */
  it("answers an empty task list rather than throwing", () => {
    expect(op.respond({ language: "en", brief }, { tasks: "nope" }, { model: "m", nowISO: "t" }))
      .toEqual({ tasks: [] });
  });
});
