import { validateRunPayload } from "../company/virtualCompany";

describe("validateRunPayload", () => {
  const valid = {
    request: "Should I add team seats or price the single-player product first?",
    language: "en",
    founder: {
      profile: "Solo technical founder, one prior product that plateaued.",
      stage: "Pre-revenue, 4 months runway, 30 beta users.",
      constraints: ["Cannot hire this quarter."]
    }
  };

  test("returns null for a valid payload", () => {
    expect(validateRunPayload(valid)).toBeNull();
  });

  test("rejects a missing request", () => {
    expect(validateRunPayload({ ...valid, request: "   " })).toMatch(/request/);
  });

  test("rejects a request longer than the cap", () => {
    expect(validateRunPayload({ ...valid, request: "x".repeat(4001) })).toMatch(/request/);
  });

  test("accepts a request exactly at the cap", () => {
    expect(validateRunPayload({ ...valid, request: "x".repeat(4000) })).toBeNull();
  });

  test("rejects an unsupported language", () => {
    expect(validateRunPayload({ ...valid, language: "fr" })).toMatch(/language/);
  });

  test("accepts vi", () => {
    expect(validateRunPayload({ ...valid, language: "vi" })).toBeNull();
  });

  test("rejects a missing founder block", () => {
    expect(validateRunPayload({ ...valid, founder: undefined })).toMatch(/founder/);
  });

  test("rejects a founder missing profile or stage", () => {
    expect(
      validateRunPayload({ ...valid, founder: { stage: "s", constraints: [] } })
    ).toMatch(/profile/);
    expect(
      validateRunPayload({ ...valid, founder: { profile: "p", constraints: [] } })
    ).toMatch(/stage/);
  });

  test("rejects non-string constraints", () => {
    const bad = { ...valid, founder: { ...valid.founder, constraints: [1, 2] } };
    expect(validateRunPayload(bad)).toMatch(/constraints/);
  });

  test("rejects a non-array constraints field", () => {
    const bad = { ...valid, founder: { ...valid.founder, constraints: "none" } };
    expect(validateRunPayload(bad)).toMatch(/constraints/);
  });

  test("accepts an empty constraints array", () => {
    const ok = { ...valid, founder: { ...valid.founder, constraints: [] } };
    expect(validateRunPayload(ok)).toBeNull();
  });

  test("accepts the optional stress_test flag", () => {
    expect(validateRunPayload({ ...valid, stress_test: true })).toBeNull();
    expect(validateRunPayload({ ...valid, stress_test: false })).toBeNull();
    expect(validateRunPayload({ ...valid, stress_test: "yes" })).toMatch(/stress_test/);
  });

  test("rejects a non-object body", () => {
    expect(validateRunPayload(null)).toMatch(/body/);
    expect(validateRunPayload("go")).toMatch(/body/);
    expect(validateRunPayload(undefined)).toMatch(/body/);
  });
});
