import { ADD_TASK_TOOL, COMPLETE_TASK_TOOL, REVISE_WORK_TOOL } from "../companyChatCore";

/**
 * CP-024 family, measured 25 Sep 2026 by replaying turns through the local sidecar: every
 * OFFER verb was narrated as already done — "I added it to your roadmap" (add_task, 2/2),
 * "Done. I've marked … as complete" (complete_task, 2/2), "I've queued a warmer version"
 * (revise_work, 3/3). None of those had happened: each tool only puts a button in front of
 * the founder, and nothing changes until they press it. The descriptions said "Offer to…"
 * but never said what an offer IS, so the model reported the tool call as the outcome.
 *
 * These pin that every offer verb tells the model the truth about what calling it does.
 */
describe("offer verbs say that nothing has happened yet", () => {
  const offers = { add_task: ADD_TASK_TOOL, complete_task: COMPLETE_TASK_TOOL, revise_work: REVISE_WORK_TOOL };

  for (const [name, tool] of Object.entries(offers)) {
    it(`${name} says the call only shows a button and nothing happens until the founder presses it`, () => {
      expect(tool.description).toMatch(/only shows the founder a button/i);
      expect(tool.description).toMatch(/nothing (has )?happen(s|ed)? until they press it/i);
    });

    it(`${name} tells the model to word the reply as an offer, not as done`, () => {
      expect(tool.description).toMatch(/word your reply as an offer/i);
    });
  }
});

/**
 * CP-061. Since CP-060 several add_task calls in one turn arrive as ONE card with ONE
 * "Add all N" button. The description never said so, and on 5 Oct the model's text still
 * read "Three buttons are up — press each one" over that card: 4/4 replays of a three-task
 * request through the shipped sidecar described buttons that do not exist.
 */
describe("add_task says several tasks share one Add all button (CP-061)", () => {
  it("tells the model the tasks arrive as one list with one Add all button", () => {
    expect(ADD_TASK_TOOL.description).toMatch(/one list/i);
    expect(ADD_TASK_TOOL.description).toMatch(/single "Add all" button/i);
  });

  it("names the wording it must not use", () => {
    expect(ADD_TASK_TOOL.description).toMatch(/never "buttons"/i);
    expect(ADD_TASK_TOOL.description).toMatch(/press each/i);
  });
});
