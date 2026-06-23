import { validateSessionPayload } from "../summarizeSession";

describe("validateSessionPayload", () => {
  const valid = {
    session_id: "s1",
    language: "vi" as const,
    turns: [{ prompt: "do thing" }]
  };

  test("accepts valid payload with turns array", () => {
    expect(validateSessionPayload(valid)).toBeNull();
  });

  test("rejects empty session_id", () => {
    expect(validateSessionPayload({ ...valid, session_id: "" })).toBe("session_id required");
  });

  test("rejects bad language", () => {
    expect(validateSessionPayload({ ...valid, language: "fr" as any }))
      .toBe("language must be 'vi' or 'en'");
  });

  test("rejects empty turns array", () => {
    expect(validateSessionPayload({ ...valid, turns: [] }))
      .toBe("turns must be a non-empty array");
  });

  test("rejects turn without prompt string", () => {
    expect(validateSessionPayload({ ...valid, turns: [{ what_happened: "something" }] as any }))
      .toBe("each turn requires prompt string");
  });
});
