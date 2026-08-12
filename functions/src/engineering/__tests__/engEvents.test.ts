import { toExecStep } from "../engEvents";

describe("toExecStep", () => {
  it("labels a bash tool use with the command", () => {
    expect(
      toExecStep({
        type: "agent.tool_use",
        id: "sevt_1",
        name: "bash",
        input: { command: "npm test" }
      })
    ).toEqual({ id: "sevt_1", label: "ran npm test", done: false });
  });

  it("labels a file edit with the path, not the whole payload", () => {
    expect(
      toExecStep({
        type: "agent.tool_use",
        id: "sevt_2",
        name: "edit",
        input: { path: "/workspace/repo/api/billing.ts", old_str: "a", new_str: "b" }
      })
    ).toEqual({ id: "sevt_2", label: "edited api/billing.ts", done: false });
  });

  it("strips the mount prefix so the founder sees a repo-relative path", () => {
    const step = toExecStep({
      type: "agent.tool_use",
      id: "sevt_3",
      name: "read",
      input: { path: "/workspace/repo/src/deep/file.ts" }
    });
    expect(step?.label).toBe("read src/deep/file.ts");
  });

  it("marks the matching tool_result as done", () => {
    expect(
      toExecStep({ type: "agent.tool_result", id: "sevt_9", tool_use_id: "sevt_1" })
    ).toEqual({ id: "sevt_1", label: "", done: true });
  });

  it("returns null for events that are not steps", () => {
    expect(toExecStep({ type: "agent.message", id: "sevt_4", content: [] })).toBeNull();
    expect(toExecStep({ type: "session.status_running", id: "sevt_5" })).toBeNull();
  });

  it("survives a tool_use with no recognised input rather than crashing the stream", () => {
    const step = toExecStep({ type: "agent.tool_use", id: "sevt_6", name: "mystery", input: {} });
    expect(step).toEqual({ id: "sevt_6", label: "mystery", done: false });
  });

  it("truncates a long command so one step can't blow out the card", () => {
    const step = toExecStep({
      type: "agent.tool_use",
      id: "sevt_7",
      name: "bash",
      input: { command: "x".repeat(300) }
    });
    expect(step!.label.length).toBeLessThanOrEqual(88);
    expect(step!.label.endsWith("…")).toBe(true);
  });
});
