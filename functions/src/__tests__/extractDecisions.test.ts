import { buildExtractPrompt, coerceDecisions } from "../extractDecisionsCore";

describe("buildExtractPrompt", () => {
  const deliverable = { title: "Pricing page", dept: "fin", type: "doc", out: "Plus tier is $4/mo." };
  it("lists on-record decisions and the deliverable, with the extract instruction", () => {
    const p = buildExtractPrompt(deliverable, [{ topic: "naming", statement: "App is called Codepet" }]);
    expect(p).toContain("- naming: App is called Codepet");
    expect(p).toContain("Title: Pricing page");
    expect(p).toContain("Department: fin");
    expect(p).toContain("Extract only NEW or CHANGED");
  });
  it("shows (none yet) when there are no existing decisions", () => {
    expect(buildExtractPrompt(deliverable, [])).toContain("(none yet)");
  });
  it("clips the deliverable body to 2000 chars", () => {
    const big = { ...deliverable, out: "x".repeat(5000) };
    const p = buildExtractPrompt(big, []);
    expect(p).toContain("x".repeat(2000));
    expect(p).not.toContain("x".repeat(2001));
  });
});

describe("coerceDecisions", () => {
  it("keeps valid items and trims", () => {
    const out = coerceDecisions({ decisions: [{ topic: " pricing ", statement: " $4/mo ", source: " Pricing page " }] });
    expect(out.decisions).toEqual([{ topic: "pricing", statement: "$4/mo", source: "Pricing page" }]);
  });
  it("drops items missing topic or statement, omits empty source", () => {
    const out = coerceDecisions({ decisions: [
      { topic: "", statement: "x" },
      { topic: "y" },
      { topic: "naming", statement: "Codepet", source: "" },
    ] });
    expect(out.decisions).toEqual([{ topic: "naming", statement: "Codepet" }]);
  });
  it("returns empty on junk / non-array / missing", () => {
    expect(coerceDecisions(null).decisions).toEqual([]);
    expect(coerceDecisions({}).decisions).toEqual([]);
    expect(coerceDecisions({ decisions: "nope" }).decisions).toEqual([]);
  });
});
