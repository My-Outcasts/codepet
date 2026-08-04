// Runner note: this suite runs under jest/ts-jest (jest.config.js, `npm test`) with
// globals — same as all 28 sibling files. `vitest` is not a dependency of this package,
// so importing describe/it/expect from it fails typecheck at ts-jest transform time.
import { styleBlock } from "../companyChatCore";

describe("styleBlock", () => {
  it("is empty when the founder changed nothing", () => {
    expect(styleBlock(undefined)).toBe("");
    expect(styleBlock("")).toBe("");
    expect(styleBlock("   ")).toBe("");
  });

  it("carries the fragment under its own heading", () => {
    const out = styleBlock("Be blunt and economical.");
    expect(out).toContain("Be blunt and economical.");
    expect(out.startsWith("\n\n")).toBe(true);
  });

  it("does not duplicate a fragment it is given twice", () => {
    const once = styleBlock("Never use emoji.");
    expect(once.match(/Never use emoji\./g)?.length).toBe(1);
  });
});
