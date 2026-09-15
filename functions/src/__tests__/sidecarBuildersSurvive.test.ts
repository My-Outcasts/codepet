import { ONE_SHOT_OPS } from "../local/oneShotOps";

/**
 * The deletion's one real risk.
 *
 * The `*Core.ts` builders live in `functions/` beside the handlers being deleted, but they are
 * not hosted code — `scripts/build-sidecar.sh` bundles them into the app, and they carry the
 * department output contract. Deleting a handler and its builder together would take the local
 * path down with the hosted one, and nothing else in this suite would notice.
 */
describe("the sidecar's builders survive the deletion", () => {
  test("every one-shot op still resolves", () => {
    // **A pinned list, not a floor.** This read `toBeGreaterThanOrEqual(12)`, which a RENAME
    // satisfies: drop `chatSession` and add `chatSessionV2` and the count is still 12 with both
    // halves still functions. The Swift call sites name these keys as strings, so a rename has
    // to fail HERE, in jest, rather than at run time on a founder's machine — which is the
    // reason this file exists at all.
    const names = Object.keys(ONE_SHOT_OPS).sort();
    expect(names).toEqual([
      "chatSession", "distillReference", "enrichBrief", "extractDecisions",
      "generateDictionary", "generateGuidance", "generatePlan", "generateRoadmap",
      "runTask", "summarizeSession", "summarizeTurn", "synthesizeBrief",
    ]);
    for (const n of names) {
      expect(typeof ONE_SHOT_OPS[n].plan).toBe("function");
      expect(typeof ONE_SHOT_OPS[n].respond).toBe("function");
    }
  });

  test("runTask still builds a department-contracted prompt", () => {
    const plan = ONE_SHOT_OPS.runTask.plan({ task_title: "Cost of inference", dept_key: "fin" });
    expect(plan.prompt).toContain("This function produces sheet, doc.");
    expect(plan.prompt).not.toContain("screens");
  });
});
