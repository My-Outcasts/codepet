import { DRAFT_MESSAGE_TOOL, RUN_TASK_TOOL } from "../companyChatCore";

/**
 * CP-024, measured 1 Oct 2026 by replaying turns through the local sidecar. Asked for "three
 * versions" of an outreach message, the model wrote three draft_message cards 15/15 times —
 * UNLESS a matching task sat in RUNNABLE TASKS. Then it called run_task 5/6 times, because
 * draft_message's own description said "prefer run_task", and said "I'm drafting three
 * versions" over a run that files ONE email. The founder asked for three and got one.
 *
 * Both descriptions now carry the same rule: several versions are drafts, a run files one.
 */
describe("several versions go to draft_message, not run_task", () => {
  it("draft_message no longer sends a multi-version ask to run_task", () => {
    expect(DRAFT_MESSAGE_TOOL.description).toMatch(/a run files ONE deliverable/);
    expect(DRAFT_MESSAGE_TOOL.description).toMatch(/several versions/i);
    // The unconditional preference is what produced the bug.
    expect(DRAFT_MESSAGE_TOOL.description).not.toMatch(/asking for a message that is already a task on their roadmap/);
  });

  it("run_task says a run files one deliverable and points several versions at draft_message", () => {
    expect(RUN_TASK_TOOL.description).toMatch(/a run files ONE deliverable/);
    expect(RUN_TASK_TOOL.description).toMatch(/several versions[^.]*draft_message/i);
  });
});
