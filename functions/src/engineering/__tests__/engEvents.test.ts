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
    ).toEqual({ id: "sevt_1", label: "npm test", done: false });


  });

  it("labels a file edit with the path, not the whole payload", () => {
    expect(
      toExecStep({
        type: "agent.tool_use",
        id: "sevt_2",
        name: "edit",
        input: { path: "/workspace/repo/api/billing.ts", old_str: "a", new_str: "b" }
      })
    ).toEqual({ id: "sevt_2", label: "edit api/billing.ts", done: false });
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

  it("never claims a tool has run, because tool_use is an announcement", () => {
    // `agent.tool_use` fires when the agent ASKS for a tool. Under
    // `bash: always_ask` it may then sit unanswered in front of the founder,
    // or be denied. Past tense was a claim the event cannot support — and on
    // 14 Aug a live run rendered "ran cd … && grep …" directly above a card
    // saying "Wants to run:" the same command.
    const pending = [
      { type: "agent.tool_use", id: "t1", name: "bash", input: { command: "rm -rf build" } },
      { type: "agent.tool_use", id: "t2", name: "write", input: { path: "/workspace/repo/a.ts" } },
      { type: "agent.tool_use", id: "t3", name: "edit", input: { path: "/workspace/repo/b.ts" } },
      { type: "agent.tool_use", id: "t4", name: "grep", input: { pattern: "plant" } }
    ];
    for (const e of pending) {
      const step = toExecStep(e)!;
      expect(step.done).toBe(false);
      for (const pastTense of ["ran ", "created ", "edited ", "searched ", "read the"]) {
        expect(step.label.startsWith(pastTense)).toBe(false);
      }
    }
  });
});
