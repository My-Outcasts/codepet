import { toMcpTools, allowedToolNames, handleRpc } from "../local/mcpToolServer";
import { claudeArgs, ingestLine, renderForPrompt, type TurnResult } from "../local/chatSidecar";
import { buildChatRequest } from "../companyChatCore";

/**
 * The local chat path: `companyChat` running on the founder's own Claude Code instead of
 * an API key. Only the pure parts are tested here; the process wiring is proven by
 * actually running the sidecar against a real `claude`.
 */

describe("toMcpTools", () => {
  it("renames input_schema to inputSchema, which is the whole reason it exists", () => {
    const [t] = toMcpTools([
      { name: "navigate", description: "go", input_schema: { type: "object" } },
    ]);
    expect(t).toEqual({ name: "navigate", description: "go", inputSchema: { type: "object" } });
  });

  /**
   * web_search is an Anthropic SERVER tool: `{type, name}` with no schema, run by
   * Anthropic. Serving it over MCP would advertise a tool nothing can execute, so the
   * local path reaches web search through Claude Code's own built-in instead.
   */
  it("drops the server-side web_search tool", () => {
    expect(toMcpTools([{ type: "web_search_20260209", name: "web_search" }])).toEqual([]);
  });

  it("drops connector toolsets, which name servers this process cannot load", () => {
    expect(toMcpTools([{ type: "mcp_toolset", mcp_server_name: "notion" }])).toEqual([]);
  });

  it("keeps every real tool a live turn offers", () => {
    // Drive it from the actual builder rather than a fixture, so adding a tool to chat
    // cannot leave the local path silently serving a stale set.
    const built = buildChatRequest({
      user_message: "hi",
      runnable: [{ id: "t1", title: "Ship" }],
      open_tasks: [{ id: "o1", title: "Call" }],
      env_setup: [{ category: "skills", name: "web-research" }],
    } as any);
    expect(toMcpTools(built.tools).map((t) => t.name).sort()).toEqual(
      ["add_task", "complete_task", "draft_message", "navigate", "remember_fact", "run_task", "setup_capability"].sort()
    );
  });
});

describe("allowedToolNames", () => {
  /**
   * Without these on `--allowedTools` the model emits the tool_use and the call is
   * DENIED, so the founder gets an apology instead of an answer. The namespacing is
   * Claude Code's, not ours.
   */
  it("namespaces every tool the way Claude Code does", () => {
    expect(allowedToolNames([{ name: "navigate", description: "", inputSchema: {} }]))
      .toEqual(["mcp__codepet__navigate"]);
  });
});

describe("handleRpc", () => {
  const tools = [{ name: "navigate", description: "go", inputSchema: { type: "object" } }];
  let out: string[];

  beforeEach(() => {
    out = [];
    jest.spyOn(process.stdout, "write").mockImplementation((c: any) => { out.push(String(c)); return true; });
  });
  afterEach(() => jest.restoreAllMocks());

  const replies = () => out.map((l) => JSON.parse(l));

  it("echoes the client's protocol version rather than pinning a guess", () => {
    handleRpc({ jsonrpc: "2.0", id: 0, method: "initialize", params: { protocolVersion: "2099-01-01" } }, tools);
    expect(replies()[0].result.protocolVersion).toBe("2099-01-01");
  });

  it("lists the tools it was given", () => {
    handleRpc({ jsonrpc: "2.0", id: 1, method: "tools/list" }, tools);
    expect(replies()[0].result.tools).toEqual(tools);
  });

  /**
   * The call is acknowledged, never performed — these tools are signals to the app, and
   * the app reads them from stream-json. But an acknowledgement must come back: without a
   * result the model stalls or apologises, and that lands in the founder's transcript.
   */
  it("acknowledges a call without performing anything", () => {
    handleRpc({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "navigate", arguments: { destination: "roadmap" } } }, tools);
    expect(replies()[0].result.content[0].type).toBe("text");
  });

  it("stays silent on a notification, because answering one is a protocol error", () => {
    handleRpc({ jsonrpc: "2.0", method: "notifications/initialized" }, tools);
    expect(out).toEqual([]);
  });

  it("reports an unknown method instead of hanging the client", () => {
    handleRpc({ jsonrpc: "2.0", id: 3, method: "resources/list" }, tools);
    expect(replies()[0].error.code).toBe(-32601);
  });
});

describe("claudeArgs", () => {
  const base = { mcpConfigPath: "/tmp/mcp.json", allowed: ["mcp__codepet__navigate"], webSearch: false, systemPrompt: "You are byte." };

  /**
   * Measured on 2.1.241: `--strict-mcp-config` ALONE excludes every server, this one
   * included, because it means "only what --mcp-config names". They ship together or the
   * turn has no tools at all.
   */
  it("never passes strict-mcp-config without an mcp-config to scope it to", () => {
    const a = claudeArgs(base);
    expect(a).toContain("--strict-mcp-config");
    expect(a[a.indexOf("--mcp-config") + 1]).toBe("/tmp/mcp.json");
  });

  /** Without this the founder's own hooks fire into Codepet's turn — observed, not feared. */
  it("blanks the setting sources, which is what keeps their hooks out", () => {
    const a = claudeArgs(base);
    expect(a[a.indexOf("--setting-sources") + 1]).toBe("");
  });

  /**
   * --safe-mode would isolate more and disable MCP with it, so the run could not reach
   * the tools. This is the flag that must NEVER appear here.
   */
  it("never passes safe-mode, which would disable the MCP server it depends on", () => {
    expect(claudeArgs(base)).not.toContain("--safe-mode");
  });

  /** A safety property, not tidiness: chat has no business holding Bash, Edit or Write. */
  it("restricts built-in tools to nothing, or to WebSearch when the skill is on", () => {
    expect(claudeArgs(base)[claudeArgs(base).indexOf("--tools") + 1]).toBe("");
    const withSearch = claudeArgs({ ...base, webSearch: true });
    expect(withSearch[withSearch.indexOf("--tools") + 1]).toBe("WebSearch");
  });

  /** Variadic, so anything after it is swallowed — including a positional prompt. */
  it("puts the variadic allowedTools last", () => {
    const a = claudeArgs(base);
    expect(a.indexOf("--allowedTools")).toBe(a.length - 2);
  });

  it("omits allowedTools entirely when there are no tools to allow", () => {
    expect(claudeArgs({ ...base, allowed: [] })).not.toContain("--allowedTools");
  });
});

describe("ingestLine", () => {
  const fresh = (): TurnResult => ({ text: "", toolUses: [], model: null });

  it("streams partial text so the reply arrives as it is written", () => {
    const acc = fresh();
    const seen: string[] = [];
    ingestLine(JSON.stringify({ type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text: "Hi" } } }), acc, (t) => seen.push(t));
    expect(seen).toEqual(["Hi"]);
    expect(acc.text).toBe("Hi");
  });

  /**
   * MCP tool names arrive namespaced but the validators in companyChatCore expect the
   * bare name. Strip it here and nowhere else — everything downstream is shared with the
   * HTTP path, which never sees a prefix.
   */
  it("strips the mcp__codepet__ prefix so the shared validators recognise the tool", () => {
    const acc = fresh();
    ingestLine(JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", name: "mcp__codepet__navigate", input: { destination: "roadmap" } }] } }), acc, () => {});
    expect(acc.toolUses).toEqual([{ name: "navigate", input: { destination: "roadmap" } }]);
  });

  it("leaves a non-MCP tool name alone", () => {
    const acc = fresh();
    ingestLine(JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", name: "WebSearch", input: {} }] } }), acc, () => {});
    expect(acc.toolUses[0].name).toBe("WebSearch");
  });

  it("reports which model actually answered", () => {
    const acc = fresh();
    ingestLine(JSON.stringify({ type: "system", subtype: "init", model: "claude-opus-5" }), acc, () => {});
    expect(acc.model).toBe("claude-opus-5");
  });

  /** `result` repeats the final text, so trusting it unconditionally doubles the reply. */
  it("falls back to result only when streaming produced nothing", () => {
    const withText = fresh();
    withText.text = "already streamed";
    ingestLine(JSON.stringify({ type: "result", result: "already streamed" }), withText, () => { throw new Error("must not re-emit"); });
    expect(withText.text).toBe("already streamed");

    const empty = fresh();
    const seen: string[] = [];
    ingestLine(JSON.stringify({ type: "result", result: "only here" }), empty, (t) => seen.push(t));
    expect(seen).toEqual(["only here"]);
  });

  it("ignores a line that is not JSON instead of failing the turn", () => {
    const acc = fresh();
    expect(() => ingestLine("Warning: something", acc, () => {})).not.toThrow();
    expect(acc.text).toBe("");
  });
});

describe("renderForPrompt", () => {
  it("sends a single turn as itself, with no transcript scaffolding", () => {
    expect(renderForPrompt([{ role: "user", content: "What is next?" }])).toBe("What is next?");
  });

  /**
   * The documented compromise: `claude -p` takes one prompt, not a messages array, so
   * history is flattened into a labelled transcript. The words are what
   * `buildChatRequest` produced; the role structure is not.
   */
  it("labels prior turns and puts the current one last", () => {
    const out = renderForPrompt([
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there" },
      { role: "user", content: "What is next?" },
    ]);
    expect(out).toContain("Founder: Hello");
    expect(out).toContain("You: Hi there");
    expect(out.trimEnd().endsWith("What is next?")).toBe(true);
  });

  /**
   * A founder who attached a screenshot must be able to tell it was not read. Dropping it
   * silently makes the model look like it ignored them.
   */
  it("names an attachment it cannot carry rather than dropping it silently", () => {
    const out = renderForPrompt([
      { role: "user", content: [{ type: "text", text: "look" }, { type: "image" } as any] },
    ]);
    expect(out).toContain("look");
    expect(out).toContain("attachment omitted");
  });

  it("returns empty for no messages instead of throwing", () => {
    expect(renderForPrompt([])).toBe("");
  });
});
