import { buildChatRequest, resolveActions } from "../companyChatCore";
import { doneFrame } from "../local/chatSidecar";

/**
 * CP-025, found 24 Sep 2026 on prod build 3: revising an approved landing page offered a NEW
 * roadmap task every time ("Redesign…", "Rework… editorial type scale", "Rework… joinswsh.com"),
 * because the chat model was shown only OPEN and RUNNABLE tasks. It could not see that the work
 * had already been delivered, so `add_task`'s own rule — never for work already on the roadmap —
 * was impossible to follow.
 *
 * The fix gives the model the founder's DELIVERED WORK and a `revise_work` verb for it. These pin
 * the request side (what the model is shown and offered) and the resolve side (what reaches the
 * app). Spec: docs/superpowers/specs/2026-09-24-revision-versioning-design.md.
 */
describe("revise_work", () => {
  const base = { user_message: "make it more editorial", companion_id: "byte", language: "en" };
  const landing = { id: "L1", kind: "site", title: "Codepet landing page", task_id: "t1" };

  const names = (tools: unknown[]) =>
    tools.map((t) => (t as { name?: string }).name).filter(Boolean);

  describe("the request", () => {
    it("is byte-for-byte unchanged for a client that sends no delivered work", () => {
      // An older app never sends `delivered`. It must get exactly today's prompt and tools —
      // otherwise this change ships a behaviour change to every build already installed.
      const today = buildChatRequest(base);
      const empty = buildChatRequest({ ...base, delivered: [] });
      expect(empty.systemBlocks).toEqual(today.systemBlocks);
      expect(names(empty.tools)).toEqual(names(today.tools));
      expect(today.systemBlocks[1].text).not.toContain("DELIVERED WORK");
      expect(names(today.tools)).not.toContain("revise_work");
    });

    it("shows the model what has been delivered, and offers revise_work for it", () => {
      const built = buildChatRequest({ ...base, delivered: [landing] });
      const context = built.systemBlocks[1].text;
      expect(context).toContain("DELIVERED WORK");
      expect(context).toContain("- L1 · site · Codepet landing page");
      expect(names(built.tools)).toContain("revise_work");
    });

    it("tells the model a revision is revise_work, not a new task", () => {
      const context = buildChatRequest({ ...base, delivered: [landing] }).systemBlocks[1].text;
      const block = context.slice(context.indexOf("DELIVERED WORK"));
      expect(block).toMatch(/revise_work/);
      expect(block).toMatch(/not add_task/i);
    });

    it("keeps the delivered work out of the cached prefix", () => {
      const built = buildChatRequest({ ...base, delivered: [landing] });
      expect(built.systemBlocks[0].text).not.toContain("DELIVERED WORK");
    });

    it("lists at most 15 items, the first 15 the client sent (newest first)", () => {
      const many = Array.from({ length: 20 }, (_, i) => ({ id: `L${i}`, kind: "doc", title: `Item ${i}` }));
      const context = buildChatRequest({ ...base, delivered: many }).systemBlocks[1].text;
      expect(context).toContain("- L14 · doc · Item 14");
      expect(context).not.toContain("- L15 ·");
    });

    it("drops entries with no id rather than listing something revise_work cannot name", () => {
      const built = buildChatRequest({
        ...base,
        delivered: [{ title: "No id" }, { id: "  L2  ", kind: "doc", title: " Pricing " }, null],
      });
      expect(built.delivered).toEqual([{ id: "L2", kind: "doc", title: "Pricing" }]);
    });
  });

  describe("resolving the tool call", () => {
    const delivered = [landing];

    it("resolves a revise_work that names delivered work", () => {
      const r = resolveActions(
        [{ name: "revise_work", input: { library_id: "L1", note: "make it more editorial" } }],
        [], [], [], delivered);
      expect(r.reviseWork).toEqual({ libraryId: "L1", note: "make it more editorial" });
    });

    it("refuses an id the founder was never shown, so a guess cannot overwrite the wrong item", () => {
      const r = resolveActions(
        [{ name: "revise_work", input: { library_id: "L9", note: "x" } }], [], [], [], delivered);
      expect(r.reviseWork).toBeNull();
    });

    it("refuses an empty note — a revise pass needs to know what to change", () => {
      const r = resolveActions(
        [{ name: "revise_work", input: { library_id: "L1", note: "   " } }], [], [], [], delivered);
      expect(r.reviseWork).toBeNull();
    });

    it("wins over add_task in the same turn — that pairing IS the bug", () => {
      const r = resolveActions(
        [
          { name: "add_task", input: { title: "Rework landing page", owner: "codepet" } },
          { name: "revise_work", input: { library_id: "L1", note: "editorial type" } },
        ],
        [], [], [], delivered);
      expect(r.reviseWork).not.toBeNull();
      expect(r.addTask).toBeNull();
    });

    it("leaves add_task alone when revise_work did not resolve", () => {
      const r = resolveActions(
        [
          { name: "add_task", input: { title: "Write a pricing page", owner: "codepet" } },
          { name: "revise_work", input: { library_id: "nope", note: "x" } },
        ],
        [], [], [], delivered);
      expect(r.addTask?.title).toBe("Write a pricing page");
    });
  });

  describe("the done frame", () => {
    it("carries revise_work in the snake_case shape the app decodes", () => {
      const r = resolveActions(
        [{ name: "revise_work", input: { library_id: "L1", note: "editorial type" } }],
        [], [], [], [landing]);
      expect(doneFrame(r, "m").revise_work).toEqual({ library_id: "L1", note: "editorial type" });
    });

    it("omits revise_work when there is none, like every other optional verb", () => {
      const r = resolveActions([], [], [], [], [landing]);
      expect("revise_work" in doneFrame(r, "m")).toBe(false);
    });
  });
});
