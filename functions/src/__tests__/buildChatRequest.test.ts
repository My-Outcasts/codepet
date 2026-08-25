import { buildChatRequest } from "../companyChatCore";

/**
 * `buildChatRequest` is the single place a chat turn's prompt is assembled, and from
 * 2026-08-25 it has TWO consumers: the HTTP handler, and the local sidecar that routes a
 * turn through the founder's own Claude Code. Drift between them is impossible by
 * construction — there is one builder — but the SHAPE it produces is now a contract the
 * sidecar reads, so the parts a reorder would silently change are pinned here.
 */
describe("buildChatRequest", () => {
  const base = { user_message: "hello", companion_id: "byte", language: "en" };

  const names = (tools: unknown[]) =>
    tools.map((t) => (t as { name?: string }).name).filter(Boolean);

  it("puts the cached static prompt first and the volatile context second", () => {
    const { systemBlocks } = buildChatRequest({ ...base, context: "ACME sells widgets." });
    expect(systemBlocks).toHaveLength(2);
    // The breakpoint rides the static block ONLY. Moving it, or letting per-request
    // context into the cached prefix, silently destroys the cache-hit rate that the
    // cheap-chat lever depends on.
    expect(systemBlocks[0].cache_control).toEqual({ type: "ephemeral" });
    expect(systemBlocks[1].cache_control).toBeUndefined();
    expect(systemBlocks[1].text).toContain("ACME sells widgets.");
  });

  it("offers the four unconditional tools on a bare turn", () => {
    // No runnable, no open tasks, no env_setup, no skills — so the conditional four
    // must be absent and exactly these four present.
    expect(names(buildChatRequest(base).tools).sort()).toEqual(
      ["add_task", "draft_message", "navigate", "remember_fact"].sort()
    );
  });

  it("offers run_task only when there is something runnable", () => {
    expect(names(buildChatRequest(base).tools)).not.toContain("run_task");
    const withTask = buildChatRequest({ ...base, runnable: [{ id: "t1", title: "Ship it" }] });
    expect(names(withTask.tools)).toContain("run_task");
  });

  it("offers complete_task only when the founder has an open step", () => {
    expect(names(buildChatRequest(base).tools)).not.toContain("complete_task");
    const withOpen = buildChatRequest({ ...base, open_tasks: [{ id: "o1", title: "Call the bank" }] });
    expect(names(withOpen.tools)).toContain("complete_task");
  });

  it("offers setup_capability only when something is off", () => {
    expect(names(buildChatRequest(base).tools)).not.toContain("setup_capability");
    const withSetup = buildChatRequest({
      ...base,
      env_setup: [{ category: "skills", name: "web-research" }],
    });
    expect(names(withSetup.tools)).toContain("setup_capability");
  });

  it("offers web_search only to a founder who turned the skill on", () => {
    expect(buildChatRequest(base).tools.some((t) => (t as any).type?.startsWith?.("web_search"))).toBe(false);
    const on = buildChatRequest({ ...base, enabled_skills: ["web-research"] });
    expect(on.tools.some((t) => (t as any).type?.startsWith?.("web_search"))).toBe(true);
  });

  /**
   * Nothing is forced. `companyChat.ts` records the reason: byte stays free to reply in
   * plain text, or ask a clarifying question, instead of calling any tool. This is also
   * exactly why the local path needs MCP rather than `--json-schema`, which can only
   * force one structured output — so if a `tool_choice` ever appears here, the local
   * path's whole design premise has changed and should fail loudly.
   */
  it("never forces a tool", () => {
    const built = buildChatRequest({ ...base, runnable: [{ id: "t1", title: "Ship it" }] });
    expect(built).not.toHaveProperty("tool_choice");
    expect(JSON.stringify(built.tools)).not.toContain("tool_choice");
  });

  it("appends connector toolsets last, after the built-ins", () => {
    const toolset = { type: "mcp_toolset", mcp_server_name: "notion" };
    const { tools } = buildChatRequest(base, [toolset]);
    expect(tools[tools.length - 1]).toBe(toolset);
  });

  it("carries the parsed lists back out, so a caller resolves actions against the same set", () => {
    // resolveActions validates a tool call against these exact lists. If the builder
    // returned a different set than it prompted with, a legitimate call would be
    // rejected as a hallucination.
    const built = buildChatRequest({
      ...base,
      runnable: [{ id: "t1", title: "Ship it" }, { id: "", title: "dropped" }],
      open_tasks: [{ id: "o1", title: "Call the bank" }],
      env_setup: [{ category: "skills", name: "web-research" }],
    });
    expect(built.runnable).toEqual([{ id: "t1", title: "Ship it" }]);
    expect(built.openTasks).toEqual([{ id: "o1", title: "Call the bank" }]);
    expect(built.envSetup).toEqual([{ category: "skills", name: "web-research" }]);
  });

  it("survives a body with nothing in it", () => {
    // Every field is client-supplied and the body is applied with an `as` cast, so the
    // builder must not throw on an empty object — the handler 400s on a missing
    // user_message before this point, and the sidecar must not crash instead.
    const built = buildChatRequest({} as any);
    expect(built.systemBlocks).toHaveLength(2);
    expect(built.messages.length).toBeGreaterThan(0);
  });
});
