import cases from "./fixtures/sheetFormulaCases.json";
import { evalFormula, formulaRefs, parseFormula } from "../sheetFormula";

describe("sheet formula language (shared cases)", () => {
  const env = cases.env as Record<string, number>;
  for (const c of cases.cases) {
    it(`${JSON.stringify(c.f)} → ${c.value}`, () => {
      const n = parseFormula(c.f);
      if (c.value === null) {
        // Rejected either at parse, or because it reads a name the sheet does not declare.
        const readsUnknown = !!n && [...formulaRefs(n)].some((r) => !(r in env));
        expect(n === null || readsUnknown).toBe(true);
      } else {
        expect(n).not.toBeNull();
        expect(evalFormula(n!, env)).toBeCloseTo(c.value, 10);
      }
    });
  }
});
