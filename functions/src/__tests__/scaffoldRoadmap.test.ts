import { buildScaffoldPrompt, coerceScaffold } from "../scaffoldRoadmap";

const DEPTS = [
  { key: "engineering", name: "Engineering", expertise: "ship the product" },
  { key: "marketing", name: "Marketing", expertise: "reach users" },
];

describe("buildScaffoldPrompt", () => {
  it("includes the founder product, stage, and each department", () => {
    const p = buildScaffoldPrompt({ projectName: "Codepet", oneLiner: "a recap tool" }, "building", DEPTS);
    expect(p).toContain("Codepet");
    expect(p).toContain("building");
    expect(p).toContain("Engineering");
    expect(p).toContain("Marketing");
    expect(p).toContain("do not invent");
  });
});

describe("coerceScaffold", () => {
  it("keeps only known departments and clamps task fields", () => {
    const out = coerceScaffold(
      { departments: [
        { key: "engineering", tasks: [{ title: "  Ship auth ", detail: "d", who: "draft", kind: "build" }] },
        { key: "unknown", tasks: [{ title: "x", detail: "y", who: "does", kind: "build" }] },
      ] },
      DEPTS,
    );
    expect(out.departments.map((d) => d.key)).toEqual(["engineering"]);
    expect(out.departments[0].tasks[0].title).toBe("Ship auth");
  });

  it("returns empty departments for malformed input (fail-open shape)", () => {
    expect(coerceScaffold(null, DEPTS).departments).toEqual([]);
    expect(coerceScaffold({ departments: "nope" }, DEPTS).departments).toEqual([]);
  });
});
