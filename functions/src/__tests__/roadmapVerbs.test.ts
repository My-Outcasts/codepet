import {
  validateCompleteTaskToolUse,
  validateAddTaskToolUse,
  buildOpenTasksBlock,
} from "../companyChatCore";

// The chat could only RUN a task that already existed — it could not create one or
// complete one, so the roadmap was written once by the scaffold and edited only by hand.
// Founder, Aug 8: "the chat should be the central brain". Both verbs PROPOSE; nothing is
// mutated server-side, exactly like run_task.
describe("complete_task validation", () => {
  const open = [
    { id: "t1", title: "Talk to 5 potential users" },
    { id: "t2", title: "Define the riskiest assumption" },
  ];

  it("accepts an exact id from OPEN TASKS", () => {
    expect(validateCompleteTaskToolUse({ task_id: "t1" }, open)).toBe("t1");
  });

  // A hallucinated id must never complete a real task — the founder's progress would
  // become fiction, and this is the least recoverable of the roadmap mutations.
  it("rejects an id that is not open", () => {
    expect(validateCompleteTaskToolUse({ task_id: "made-up" }, open)).toBeNull();
  });

  it("falls back to a title match when the id is wrong but the title is right", () => {
    expect(
      validateCompleteTaskToolUse(
        { task_id: "wrong", task_title: "Define the riskiest assumption" },
        open
      )
    ).toBe("t2");
  });

  it("is case- and whitespace-insensitive on the title fallback", () => {
    expect(
      validateCompleteTaskToolUse({ task_id: "x", task_title: "  TALK TO 5 POTENTIAL USERS " }, open)
    ).toBe("t1");
  });

  it("rejects junk input rather than throwing", () => {
    expect(validateCompleteTaskToolUse(null, open)).toBeNull();
    expect(validateCompleteTaskToolUse({}, open)).toBeNull();
    expect(validateCompleteTaskToolUse({ task_id: 42 }, open)).toBeNull();
    expect(validateCompleteTaskToolUse({ task_id: "t1" }, [])).toBeNull();
  });
});

describe("add_task validation", () => {
  it("keeps a well-formed task", () => {
    expect(
      validateAddTaskToolUse({
        title: "Call the two bakeries who asked to pay",
        detail: "Find out what they would pay and why.",
        dept: "sales",
        owner: "founder",
      })
    ).toEqual({
      title: "Call the two bakeries who asked to pay",
      detail: "Find out what they would pay and why.",
      dept: "sales",
      owner: "founder",
    });
  });

  // Defaulting the other way would let a malformed turn queue work the founder never
  // asked Codepet to take on — and Codepet-owned tasks are the ones that spend money.
  it("defaults ownership to the founder, never to Codepet", () => {
    expect(validateAddTaskToolUse({ title: "Write the refund policy" })?.owner).toBe("founder");
    expect(validateAddTaskToolUse({ title: "x", owner: "nonsense" })?.owner).toBe("founder");
    expect(validateAddTaskToolUse({ title: "x", owner: "codepet" })?.owner).toBe("codepet");
  });

  it("drops a department it does not recognise rather than inventing one", () => {
    expect(validateAddTaskToolUse({ title: "x", dept: "bakery" })?.dept).toBeNull();
    expect(validateAddTaskToolUse({ title: "x", dept: "fin" })?.dept).toBe("fin");
  });

  it("requires a title", () => {
    expect(validateAddTaskToolUse({ title: "   " })).toBeNull();
    expect(validateAddTaskToolUse({ detail: "no title here" })).toBeNull();
    expect(validateAddTaskToolUse(null)).toBeNull();
  });

  it("caps a runaway title instead of letting it into the roadmap", () => {
    const long = "a".repeat(400);
    expect(validateAddTaskToolUse({ title: long })!.title.length).toBe(120);
  });
});

describe("OPEN TASKS grounding", () => {
  it("is empty when there is nothing open, so the prompt is unchanged", () => {
    expect(buildOpenTasksBlock([])).toBe("");
  });

  it("lists ids the model can copy verbatim", () => {
    const block = buildOpenTasksBlock([{ id: "t1", title: "Talk to 5 users" }]);
    expect(block).toContain("t1 — Talk to 5 users");
    expect(block).toContain("complete_task");
  });

  it("caps the list so a large roadmap cannot dominate the prompt", () => {
    const many = Array.from({ length: 200 }, (_, i) => ({ id: `t${i}`, title: `Task ${i}` }));
    expect(buildOpenTasksBlock(many).split("\n").filter((l) => l.startsWith("- ")).length).toBe(60);
  });
});
