import { validatePayload } from "../summarizeTurn";

describe("validatePayload", () => {
  const valid = {
    turn_id: "s1:2026-05-05T09:00:00Z",
    session_id: "s1",
    language: "vi" as const,
    prompt: "do thing",
    events: [],
    raw_summary: ""
  };

  test("accepts a valid payload", () => {
    expect(validatePayload(valid)).toBeNull();
  });

  test("rejects missing turn_id", () => {
    expect(validatePayload({ ...valid, turn_id: "" })).toBe("turn_id required");
  });

  test("rejects missing session_id", () => {
    expect(validatePayload({ ...valid, session_id: "" })).toBe("session_id required");
  });

  test("rejects bad language", () => {
    expect(validatePayload({ ...valid, language: "fr" as any }))
      .toBe("language must be 'vi' or 'en'");
  });

  test("rejects empty prompt", () => {
    expect(validatePayload({ ...valid, prompt: "" })).toBe("prompt required");
  });

  test("rejects non-array events", () => {
    expect(validatePayload({ ...valid, events: "x" as any }))
      .toBe("events must be an array");
  });
});
