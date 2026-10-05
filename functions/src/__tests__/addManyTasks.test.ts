import { resolveActions } from "../companyChatCore";
import { doneFrame } from "../local/chatSidecar";

/**
 * CP-060. Asked for eight roadmap tasks in one message, the model called `add_task` eight times
 * and said "All eight are queued as buttons below". `resolveActions` kept the FIRST call only
 * (`toolUses.find`), so one "Yes, add it" appeared and only the first task was added. Observed
 * 5 Oct on build 7.
 */
describe("several add_task calls in one turn (CP-060)", () => {
  const adds = (titles: string[]) =>
    titles.map((title) => ({ name: "add_task", input: { title, owner: "codepet", dept: "mkt" } }));

  it("keeps every valid add_task, in order", () => {
    const r = resolveActions(adds(["Outreach templates", "Beta checklist", "LinkedIn post"]), [], [], []);
    expect(r.addTasks.map((t) => t.title)).toEqual(["Outreach templates", "Beta checklist", "LinkedIn post"]);
  });

  it("still sets addTask to the first, so an older client behaves as before", () => {
    const r = resolveActions(adds(["Outreach templates", "Beta checklist"]), [], [], []);
    expect(r.addTask?.title).toBe("Outreach templates");
  });

  it("drops invalid calls and repeated titles", () => {
    const r = resolveActions(
      [...adds(["Beta checklist"]), { name: "add_task", input: { title: "  " } }, ...adds(["beta checklist ", "Welcome email"])],
      [], [], []);
    expect(r.addTasks.map((t) => t.title)).toEqual(["Beta checklist", "Welcome email"]);
  });

  it("caps a turn at ten", () => {
    const r = resolveActions(adds(Array.from({ length: 14 }, (_, i) => `Task ${i + 1}`)), [], [], []);
    expect(r.addTasks).toHaveLength(10);
  });

  it("is empty when complete_task or revise_work already took the turn", () => {
    const r = resolveActions(
      [{ name: "complete_task", input: { task_id: "o1" } }, ...adds(["A", "B"])],
      [], [], [{ id: "o1", title: "Call the bakery" }]);
    expect(r.addTasks).toEqual([]);
  });

  it("puts the whole list on the wire as add_tasks, next to add_task", () => {
    const done = doneFrame(resolveActions(adds(["A", "B"]), [], [], []), "m");
    expect((done.add_tasks as Array<{ title: string }>).map((t) => t.title)).toEqual(["A", "B"]);
    expect((done.add_task as { title: string }).title).toBe("A");
  });

  it("leaves add_tasks off the wire when there is nothing to add", () => {
    expect("add_tasks" in doneFrame(resolveActions([], [], [], []), "m")).toBe(false);
  });
});
