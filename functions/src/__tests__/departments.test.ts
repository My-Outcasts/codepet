import { departmentBlock, departmentBrief, DEPARTMENT_FOUNDATIONS, DEPARTMENT_NAMES } from "../departments";

describe("departmentBlock", () => {
  it("includes mandate, skills, the stage focus, and antipatterns for a known key+stage", () => {
    const b = departmentBlock("eng", "Prototype");
    expect(b).toContain("Mandate:");
    expect(b).toContain("Core skills:");
    expect(b).toContain(DEPARTMENT_FOUNDATIONS.eng.stageFocus["Prototype"]);
    expect(b).toContain("Avoid:");
  });
  it("omits the focus line for an unknown stage but still returns mandate", () => {
    const b = departmentBlock("eng", "NoSuchStage");
    expect(b).toContain("Mandate:");
    expect(b).not.toContain('Focus at the "NoSuchStage"');
  });
  it("returns empty string for an unknown department key", () => {
    expect(departmentBlock("bogus", "Prototype")).toBe("");
  });
});

describe("catalog shape", () => {
  it("has all 8 departments with names", () => {
    for (const k of ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"]) {
      expect(DEPARTMENT_FOUNDATIONS[k]).toBeTruthy();
      expect(DEPARTMENT_NAMES[k]).toBeTruthy();
    }
  });
  it("departmentBrief fails open on null", () => {
    expect(departmentBrief(null)).toBe("");
    expect(departmentBrief("eng")).toContain("Mandate:");
  });
});
