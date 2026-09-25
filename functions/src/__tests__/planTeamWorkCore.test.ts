import {
  BUILD_STEP_ID, MAX_DEPT_STEPS, buildTeamPlanPrompt, coerceWorkPlan, teamSlug,
} from "../planTeamWorkCore";

const ROSTER = ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"];
const step = (id: string, dept: string, dependsOn: string[] = [], kind = "doc") =>
  ({ id, dept, title: `T ${id}`, instruction: `do ${id}`, kind, dependsOn });
const plan = (steps: any[]) =>
  ({ title: "Pants landing", slug: "pants", summary: "s", projectType: "static landing page", steps });

describe("teamSlug", () => {
  it("strips Vietnamese diacritics and kebab-cases", () => {
    expect(teamSlug("Bán quần văn phòng!")).toBe("ban-quan-van-phong");
  });
  it("falls back to project when nothing survives", () => {
    expect(teamSlug("🚀🚀")).toBe("project");
  });
  it("caps at 40 chars without a trailing dash", () => {
    const s = teamSlug("a ".repeat(60));
    expect(s.length).toBeLessThanOrEqual(40);
    expect(s.endsWith("-")).toBe(false);
  });
});

describe("coerceWorkPlan", () => {
  it("drops unknown and non-routable departments", () => {
    const p = coerceWorkPlan(plan([step("s1", "mkt"), step("s2", "product"), step("s3", "chief_of_staff")]), ROSTER)!;
    expect(p.steps.map((s) => s.dept)).toEqual(["mkt", "eng"]);
  });
  it("drops departments missing from this company's roster", () => {
    const p = coerceWorkPlan(plan([step("s1", "legal")]), ["mkt", "eng"])!;
    expect(p.steps.map((s) => s.id)).toEqual([BUILD_STEP_ID]);
  });
  it("coerces an out-of-contract kind to doc", () => {
    const p = coerceWorkPlan(plan([step("s1", "fin", [], "site")]), ROSTER)!;
    expect(p.steps[0].kind).toBe("doc");
  });
  it("drops dangling dependencies", () => {
    const p = coerceWorkPlan(plan([step("s1", "mkt", ["nope"])]), ROSTER)!;
    expect(p.steps[0].dependsOn).toEqual([]);
  });
  it("breaks a cycle by removing the closing edge", () => {
    const p = coerceWorkPlan(plan([step("s1", "mkt", ["s2"]), step("s2", "design", ["s1"])]), ROSTER)!;
    const s1 = p.steps.find((s) => s.id === "s1")!;
    const s2 = p.steps.find((s) => s.id === "s2")!;
    expect(s1.dependsOn).toEqual([]);   // s2 is not yet accepted when s1 is visited
    expect(s2.dependsOn).toEqual(["s1"]);
  });
  it("caps department steps and per-step dependencies", () => {
    const many = Array.from({ length: 9 }, (_, i) => step(`s${i + 1}`, "mkt"));
    many[7] = step("s8", "design", ["s1", "s2", "s3", "s4", "s5"]);
    const p = coerceWorkPlan(plan(many), ROSTER)!;
    expect(p.steps.filter((s) => s.id !== BUILD_STEP_ID)).toHaveLength(MAX_DEPT_STEPS);
    for (const s of p.steps.filter((s) => s.id !== BUILD_STEP_ID)) expect(s.dependsOn.length).toBeLessThanOrEqual(3);
  });
  it("always ends with exactly one build step depending on every other step", () => {
    const p = coerceWorkPlan(plan([step("s1", "mkt"), step("s2", "design", ["s1"])]), ROSTER)!;
    const last = p.steps[p.steps.length - 1];
    expect(last).toMatchObject({ id: BUILD_STEP_ID, dept: "eng", kind: "other" });
    expect(last.dependsOn).toEqual(["s1", "s2"]);
    expect(p.steps.filter((s) => s.id === BUILD_STEP_ID)).toHaveLength(1);
  });
  it("folds a model-marked build step into the final one, keeping its instruction", () => {
    const raw = plan([step("s1", "mkt"), { ...step("build", "eng", ["s1"], "other"), instruction: "Astro site" }]);
    const p = coerceWorkPlan(raw, ROSTER)!;
    expect(p.steps.filter((s) => s.id === BUILD_STEP_ID)).toHaveLength(1);
    expect(p.steps[p.steps.length - 1].instruction).toBe("Astro site");
  });
  it("keeps a plan with no department steps as a lone build step", () => {
    const p = coerceWorkPlan(plan([]), ROSTER)!;
    expect(p.steps).toHaveLength(1);
    expect(p.steps[0].id).toBe(BUILD_STEP_ID);
    expect(p.steps[0].dependsOn).toEqual([]);
  });
  it("normalises the slug and returns null for non-objects", () => {
    expect(coerceWorkPlan({ ...plan([]), slug: "Quần Âu" }, ROSTER)!.slug).toBe("quan-au");
    expect(coerceWorkPlan("nope", ROSTER)).toBeNull();
    expect(coerceWorkPlan(null, ROSTER)).toBeNull();
  });
});

describe("buildTeamPlanPrompt", () => {
  const input = { language: "en" as const, request: "build a landing page selling pants",
    brief: null, company: { projectName: "Pantsy" }, roster: ROSTER };
  it("carries the request, the roster and the caps", () => {
    const p = buildTeamPlanPrompt(input);
    expect(p).toContain("build a landing page selling pants");
    expect(p).toContain("Marketing");
    expect(p).toMatch(/at most 6/i);
  });
  it("includes the room's recommendation when there is a brief", () => {
    const brief: any = { recommendation: "Target office workers 25-35", confidence: 4, confidence_reason: "",
      the_real_disagreement: "", tradeoff_founder_must_own: "", kill_criteria: [], next_action: { action: "", owner: "" },
      what_we_dont_know: "", unresolved: false };
    expect(buildTeamPlanPrompt({ ...input, brief })).toContain("Target office workers 25-35");
  });
  it("asks for Vietnamese only when language is vi", () => {
    expect(buildTeamPlanPrompt({ ...input, language: "vi" })).toMatch(/Vietnamese/);
    expect(buildTeamPlanPrompt(input)).not.toMatch(/Vietnamese/);
  });
});

import { ONE_SHOT_OPS, OneShotBadRequest, OneShotUnusableAnswer } from "../local/oneShotOps";

describe("planTeamWork op", () => {
  const op = ONE_SHOT_OPS.planTeamWork;
  const body = { language: "en", request: "pants page", brief: null, company: {}, roster: ["mkt", "eng"] };
  it("plans with the shared prompt and schema", () => {
    const p = op.plan(body);
    expect(p.prompt).toContain("pants page");
    expect(p.schema).toBeDefined();
  });
  it("refuses a body with no request", () => {
    expect(() => op.plan({ ...body, request: "  " })).toThrow(OneShotBadRequest);
  });
  it("coerces the reply against the body's roster", () => {
    const out: any = op.respond(body, { title: "x", slug: "x", summary: "", projectType: "",
      steps: [{ id: "s1", dept: "legal", title: "t", instruction: "i", kind: "doc", dependsOn: [] }] },
      { model: "m", nowISO: "" });
    expect(out.steps.map((s: any) => s.id)).toEqual(["build"]);
  });
  it("throws unusable for a non-object reply", () => {
    expect(() => op.respond(body, "nope", { model: "m", nowISO: "" })).toThrow(OneShotUnusableAnswer);
  });
});
