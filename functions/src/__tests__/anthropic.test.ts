import { buildUserMessage, NARRATIVE_TOOL, SYSTEM_PROMPT } from "../anthropic";

describe("anthropic prompt builders", () => {
  test("buildUserMessage includes prompt and events", () => {
    const msg = buildUserMessage({
      prompt: "fix the bug",
      events: [
        { time: "09:00", tool: "Edit", path: "foo.swift" },
        { time: "09:01", tool: "Bash", text: "git commit" }
      ],
      raw_summary: "Edit foo.swift · Bash: git commit"
    });
    expect(msg).toContain("fix the bug");
    expect(msg).toContain("09:00");
    expect(msg).toContain("Edit");
    expect(msg).toContain("git commit");
    expect(msg).toContain("Edit foo.swift · Bash: git commit");
  });

  test("buildUserMessage truncates prompt over 8000 chars", () => {
    const huge = "x".repeat(10000);
    const msg = buildUserMessage({ prompt: huge, events: [], raw_summary: "" });
    expect(msg.length).toBeLessThan(9500);
  });

  test("buildUserMessage truncates events over 50", () => {
    const events = Array.from({ length: 100 }, (_, i) => ({
      time: "09:00",
      tool: "Edit",
      path: `f${i}.swift`
    }));
    const msg = buildUserMessage({ prompt: "p", events, raw_summary: "" });
    // Only first 50 should appear
    expect(msg).toContain("f49.swift");
    expect(msg).not.toContain("f50.swift");
  });

  test("NARRATIVE_TOOL has required fields", () => {
    expect(NARRATIVE_TOOL.name).toBe("record_narrative");
    const props = (NARRATIVE_TOOL.input_schema as any).properties;
    expect(props.title).toBeDefined();
    expect(props.what_you_wanted).toBeDefined();
    expect(props.what_happened).toBeDefined();
    expect(props.lesson).toBeDefined();
    expect(props.next_steps).toBeDefined();
    expect(props.mood).toBeDefined();
    expect((NARRATIVE_TOOL.input_schema as any).required)
      .toEqual(["title", "what_you_wanted", "what_happened", "lesson", "next_steps", "mood", "detected_skills"]);
  });

  test("SYSTEM_PROMPT contains language placeholder", () => {
    expect(SYSTEM_PROMPT).toContain("<language>");
  });
});
