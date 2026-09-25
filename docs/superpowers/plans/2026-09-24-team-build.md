# Team Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One founder request → the Virtual Company room deliberates → a validated multi-department plan → the founder taps Go once → departments run in dependency order feeding each other → Claude Code builds a real project in `~/Codepet Projects/<slug>/` with a `CLAUDE.md` → the founder approves it into the Library, with every step visible in chat.

**Architecture:** A new one-shot op `planTeamWork` (TypeScript, shared prompt builder + coercer) turns the room's brief into a `WorkPlan`. A `TeamRunCoordinator` (Swift, `@MainActor`, every dependency injected) schedules the plan's department steps through the existing task runner and then hands the build step to a `ProjectAssembler` that writes `docs/`, runs `claude -p` via `CLIRunner` with file-only tools, guarantees `CLAUDE.md`, and commits. `CompanyStore` wires it to the chat: a Team build button, a hook at the end of the room, cards for plan/progress/result, and approval through the existing `fileApproval`.

**Tech Stack:** Swift 5 / SwiftUI (macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), XCTest; TypeScript (Node 22) + jest in `functions/`; esbuild sidecars via `scripts/build-sidecar.sh`.

**Spec:** `docs/superpowers/specs/2026-09-24-team-build-design.md` — read it first. `docs/superpowers/specs/virtual-company-sse-contract.md` outranks both and is NOT changed.

## Global Constraints

- Branch `feat/team-build`. Never commit to `main`.
- Department keys at the task layer are `eng, design, mkt, sales, support, fin, ops, legal` (`generateRoadmapCore.ts:17 DEPT_KEYS`). The spec's `"engineering"` means `eng`. `product`, `chief_of_staff`, `devils_advocate` are never steps.
- Caps: ≤ **6** department steps; each step `dependsOn` ≤ **3**; ≤ **3** steps running at once; one active TeamRun per company.
- Build step id is exactly `"build"`, dept `eng`, kind `other`, depends on every other step.
- Timeouts: one-shot op **180 s**; Claude Code build **900 s** (15 min).
- Claude Code allowed tools for the build: exactly `["Read", "Write", "Edit", "Glob", "Grep"]` — no `Bash`, no web.
- Project root: `~/Codepet Projects/<slug>/`, collision suffix `-2`, `-3`, …; slug lowercase ASCII kebab, diacritics stripped, ≤ 40 chars, `"project"` if empty.
- Required `CLAUDE.md` section headings, verbatim: `## What this is`, `## What the team decided`, `## Who did what`, `## How to run`, `## Next steps`.
- Every Firestore saver is injected through `CompanyStore.init` and stubbed in tests — real savers call `Firestore.firestore()`, which TRAPS under an unconfigured `FirebaseApp` and kills the test host ("Restarting after unexpected exit").
- Run XCTest per suite only: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:codepetTests/<Suite> 2>&1 | grep -E "error:|failed \(|Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -6` (landmine 3: the full suite exits 65 on a clean checkout; do not chase it).
- Jest: `cd functions && npx jest src/__tests__/<file>.test.ts`.
- After any change under `functions/src/`: `./scripts/build-sidecar.sh` (typechecks + bundles the three sidecars; does not run jest).
- New `.swift` files need no project-file edit (synchronized folders).
- All user-facing copy in both languages: `lang == .vi ? "…" : "…"`.
- Commit messages carry the why; end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

**Deliberate deviations from the spec (decided while planning, keep them):**
1. The Claude Code **build prompt lives in Swift** (`TeamBuildPrompt.swift`), not the functions tree. The "prompts are never re-implemented" rule protects prompts that also have a cloud path; this one never has, and `CLIRunner` is Swift. It is pure and unit-tested.
2. A failed department step's reason is `"No result — the run failed or timed out"` unless the runner gives more. `taskRunner` returns `RunTaskResponse?` and drops the error; changing that seam would touch every run path. The 180 s timeout is still what bounds it.

## Review Focus

1. **Plan with only the build step** (model returned no usable department steps) — expect the build to run from the decision alone and still produce a project with `CLAUDE.md`. Pinned in Task 1 (`coerceWorkPlan` keeps a lone build step) and Task 6 (coordinator goes straight to assembly).
2. **App quit during the build step itself** — on relaunch the build step is `interrupted`, [Continue] re-runs assembly into a NEW folder (never writes over a half-built one). Pinned in Task 6 (`testInterruptedBuildReassembles`) and Task 8 (collision suffix).
3. **`~/Codepet Projects` missing or the slug is all diacritics/emoji** — folder is created, name is `project` or `project-2`. Pinned in Task 1 (slug) and Task 8 (`testCreatesRootAndFallsBackToProject`).
4. **Founder switches account mid-run** — no step result or save lands on the other account. Pinned in Task 9 (`testAccountSwitchDropsLateResults`).
5. **Claude Code writes CLAUDE.md without the required headings** — treat as missing and write the fallback (never leave a CLAUDE.md that fails the spec). Pinned in Task 8 (`testIncompleteClaudeMdIsReplaced`).

---

## File Structure

**TypeScript (`functions/src/`)**
- Create `planTeamWorkCore.ts` — `WorkPlan` types, `TEAM_PLAN_SYSTEM`, `TEAM_PLAN_TOOL`, `buildTeamPlanPrompt`, `coerceWorkPlan`, `teamSlug`. Pure; no firebase/express/anthropic imports.
- Modify `local/oneShotOps.ts` — register `planTeamWork`.
- Test `__tests__/planTeamWorkCore.test.ts`; modify `__tests__/oneShotSidecar.test.ts:570-577` and `__tests__/sidecarBuildersSurvive.test.ts:18-27`.

**Swift (`codepet/`)**
- Modify `Services/LocalOneShotRunner.swift` — timeout via extracted `runProcess`.
- Create `Models/TeamBuild.swift` — `WorkPlan`, `WorkStep`, `TeamRun`, `TeamStepState`, `TeamStepStatus`, `TeamRunPhase`, `WorkPlanValidation`, `TeamBuildRoomOutcome`.
- Modify `Models/CompanyState.swift` + `Services/CompanyData.swift` — `teamRuns` field, `saveTeamRuns`.
- Create `Services/TeamPlanClient.swift` — calls op `planTeamWork`.
- Create `Managers/TeamRunCoordinator.swift`.
- Create `Models/DeliverableMarkdown.swift`.
- Create `Services/TeamBuildPrompt.swift`, `Services/ProjectAssembler.swift`.
- Modify `Models/Deliverable.swift` — `projectPath: String?`.
- Modify `Managers/CompanyStore.swift` — injection, `startTeamBuild`, room hook, go/cancel/retry/stop/continue, approval.
- Modify `Models/CopilotMessage.swift` — `teamRunId: String?`.
- Create `Views/Copilot/TeamBuildCards.swift`; modify `Views/Copilot/ChatComposer.swift`, `Views/Copilot/CopilotChatView.swift`, `Views/Library/LibraryView.swift`.

**Tests (`codepetTests/`)** — `LocalOneShotTimeoutTests`, `WorkPlanValidationTests`, `TeamRunPersistenceTests`, `TeamPlanClientTests`, `TeamRunCoordinatorTests`, `DeliverableMarkdownTests`, `ProjectAssemblerTests`, `TeamBuildStoreTests`, `TeamBuildButtonTests`; extend `ApprovalParityTests`.

---

### Task 1: `planTeamWorkCore.ts` — prompt, schema, coercion

**Files:**
- Create: `functions/src/planTeamWorkCore.ts`
- Test: `functions/src/__tests__/planTeamWorkCore.test.ts`

**Interfaces:**
- Consumes: `DEPARTMENT_OUTPUTS`, `coerceKindForDepartment`, `DEPARTMENT_NAMES` from `./departments`; `DELIVERABLE_KINDS` from `./runTaskCore`; `DEPT_KEYS` from `./generateRoadmapCore`; `DecisionBrief` from `./company/types`.
- Produces:
  ```ts
  export const BUILD_STEP_ID = "build";
  export const MAX_DEPT_STEPS = 6;
  export const MAX_DEPS = 3;
  export interface WorkStep { id: string; dept: string; title: string; instruction: string; kind: string; dependsOn: string[] }
  export interface WorkPlan { title: string; slug: string; summary: string; projectType: string; steps: WorkStep[] }
  export interface TeamPlanInput { language: "en" | "vi"; request: string; brief: DecisionBrief | null; company: Record<string, unknown>; roster: string[] }
  export function teamSlug(s: string): string
  export function buildTeamPlanPrompt(input: TeamPlanInput): string
  export function coerceWorkPlan(raw: unknown, roster: string[]): WorkPlan | null
  export const TEAM_PLAN_SYSTEM: string
  export const TEAM_PLAN_TOOL: { name: string; description: string; input_schema: object }
  ```

- [ ] **Step 1: Write the failing tests**

```ts
// functions/src/__tests__/planTeamWorkCore.test.ts
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
```

Cycle-breaking note for the implementer: visit steps in array order, keeping a set of step ids already accepted; an edge `s → d` is kept only if `d` is already accepted (i.e. appears EARLIER). This removes every back-edge, so the result is acyclic by construction. With `[s1→s2, s2→s1]`, s1's edge to s2 is dropped (s2 not yet accepted) and s2's edge to s1 is kept — the test above asserts exactly that.

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx jest src/__tests__/planTeamWorkCore.test.ts`
Expected: FAIL — `Cannot find module '../planTeamWorkCore'`.

- [ ] **Step 3: Implement**

```ts
// functions/src/planTeamWorkCore.ts
// Pure logic for the Team Build planner — no firebase/express/anthropic imports, because the
// one-shot sidecar is esbuild-bundled and inlines this whole import graph.
import { DEPARTMENT_NAMES, DEPARTMENT_OUTPUTS, coerceKindForDepartment } from "./departments";
import { DELIVERABLE_KINDS } from "./runTaskCore";
import { DEPT_KEYS } from "./generateRoadmapCore";
import type { DecisionBrief } from "./company/types";

export const BUILD_STEP_ID = "build";
export const MAX_DEPT_STEPS = 6;
export const MAX_DEPS = 3;

export interface WorkStep { id: string; dept: string; title: string; instruction: string; kind: string; dependsOn: string[] }
export interface WorkPlan { title: string; slug: string; summary: string; projectType: string; steps: WorkStep[] }
export interface TeamPlanInput {
  language: "en" | "vi"; request: string; brief: DecisionBrief | null;
  company: Record<string, unknown>; roster: string[];
}

const str = (v: unknown, max = 600): string => (typeof v === "string" ? v.trim().slice(0, max) : "");

export function teamSlug(s: string): string {
  const ascii = s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D");
  const kebab = ascii.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  const capped = kebab.slice(0, 40).replace(/-+$/g, "");
  return capped || "project";
}

export function buildTeamPlanPrompt(input: TeamPlanInput): string {
  const roster = input.roster.filter((k) => DEPT_KEYS.has(k));
  const lines = roster.map((k) => {
    const out = DEPARTMENT_OUTPUTS[k];
    const kinds = out ? [...out.primary, ...out.allowed].join(", ") : "doc";
    return `- ${k} (${DEPARTMENT_NAMES[k] ?? k}): can produce ${kinds}`;
  });
  const b = input.brief;
  const decision = b
    ? [
        `Recommendation: ${b.recommendation}`,
        `Trade-off the founder owns: ${b.tradeoff_founder_must_own}`,
        `Kill criteria: ${b.kill_criteria.join("; ")}`,
        `What we don't know: ${b.what_we_dont_know}`,
      ].join("\n")
    : "(No room decision — plan from the request alone.)";
  return [
    `The founder asked: "${input.request}"`,
    ``,
    `What the team decided in the room:`,
    decision,
    ``,
    `Company facts (do not invent any others):`,
    JSON.stringify(input.company),
    ``,
    `Departments available on this company's roster:`,
    ...lines,
    ``,
    `Plan the work the departments must do so an engineer can then build the finished project.`,
    `Rules: at most ${MAX_DEPT_STEPS} department steps; each step depends on at most ${MAX_DEPS} earlier steps;`,
    `only use departments from the list; pick a kind that department can produce;`,
    `do NOT include the final build step — it is added for you and depends on every step.`,
    `Give the project a short title, a kebab-case slug, a one-sentence summary of what the team decided,`,
    `and a projectType naming what gets built (e.g. "static landing page", "email sequence (docs)").`,
    input.language === "vi" ? `Write every title, instruction and summary in Vietnamese.` : ``,
  ].filter((l) => l !== ``).join("\n");
}

export function coerceWorkPlan(raw: unknown, roster: string[]): WorkPlan | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const allowed = new Set(roster.filter((k) => DEPT_KEYS.has(k)));
  const rawSteps = Array.isArray(r.steps) ? r.steps : [];

  let buildInstruction = "";
  const candidates: WorkStep[] = [];
  const seen = new Set<string>();
  for (const s of rawSteps) {
    if (!s || typeof s !== "object") continue;
    const o = s as Record<string, unknown>;
    const id = str(o.id, 40);
    const dept = str(o.dept, 20);
    const kind = str(o.kind, 20);
    // A step the model marked as the build step: keep its instruction, drop the step.
    if (id === BUILD_STEP_ID || (dept === "eng" && kind === "other")) {
      buildInstruction = buildInstruction || str(o.instruction, 2000);
      continue;
    }
    if (!id || seen.has(id) || !allowed.has(dept)) continue;
    seen.add(id);
    const safeKind = DELIVERABLE_KINDS.has(kind) ? coerceKindForDepartment(dept, kind) : coerceKindForDepartment(dept, "doc");
    candidates.push({
      id, dept, kind: safeKind,
      title: str(o.title, 120) || id,
      instruction: str(o.instruction, 2000),
      dependsOn: Array.isArray(o.dependsOn) ? o.dependsOn.map((d) => str(d, 40)).filter(Boolean) : [],
    });
  }

  const kept = candidates.slice(0, MAX_DEPT_STEPS);
  const accepted = new Set<string>();
  for (const s of kept) {
    // Only edges to EARLIER accepted steps survive: removes dangling ids and every back-edge.
    s.dependsOn = [...new Set(s.dependsOn)].filter((d) => accepted.has(d)).slice(0, MAX_DEPS);
    accepted.add(s.id);
  }

  const build: WorkStep = {
    id: BUILD_STEP_ID, dept: "eng", kind: "other",
    title: "Build the project",
    instruction: buildInstruction,
    dependsOn: kept.map((s) => s.id),
  };
  const title = str(r.title, 120) || "Project";
  return {
    title,
    slug: teamSlug(str(r.slug, 120) || title),
    summary: str(r.summary, 400),
    projectType: str(r.projectType, 120) || "project",
    steps: [...kept, build],
  };
}

export const TEAM_PLAN_TOOL = {
  name: "record_team_plan",
  description: "Record the departments' work plan for a Team Build.",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string" },
      slug: { type: "string" },
      summary: { type: "string" },
      projectType: { type: "string" },
      steps: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" }, dept: { type: "string" }, title: { type: "string" },
            instruction: { type: "string" }, kind: { type: "string" },
            dependsOn: { type: "array", items: { type: "string" } },
          },
          required: ["id", "dept", "title", "instruction", "kind", "dependsOn"],
        },
      },
    },
    required: ["title", "slug", "summary", "projectType", "steps"],
  },
} as const;

export const TEAM_PLAN_SYSTEM =
  "You are the chief of staff of a small company's AI team. You turn a founder's request and the " +
  "team's decision into a short, concrete work plan for departments. You never invent company facts.";
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd functions && npx jest src/__tests__/planTeamWorkCore.test.ts`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add functions/src/planTeamWorkCore.ts functions/src/__tests__/planTeamWorkCore.test.ts
git commit -m "Add the Team Build planner's prompt and coercion (planTeamWorkCore)"
```
(Body: why coercion is the safety layer — `claude -p` cannot force a tool call; the build step is always appended by code, never trusted from the model.)

---

### Task 2: Register `planTeamWork` as a one-shot op

**Files:**
- Modify: `functions/src/local/oneShotOps.ts` (imports near :32; registry at :241)
- Modify: `functions/src/__tests__/oneShotSidecar.test.ts:570-577`, `functions/src/__tests__/sidecarBuildersSurvive.test.ts:18-27`
- Test: extend `functions/src/__tests__/planTeamWorkCore.test.ts`

**Interfaces:**
- Consumes: Task 1 exports; `OneShotOp`, `OneShotBadRequest`, `OneShotUnusableAnswer` (oneShotOps.ts:108-157).
- Produces: op key `"planTeamWork"`. Request body `{ language: "en"|"vi", request: string, brief: DecisionBrief|null, company: object, roster: string[] }`. Response body: a `WorkPlan` JSON (Task 1 shape).

- [ ] **Step 1: Update the two key-list tests to include `planTeamWork` (sorted between `generateRoadmap` and `runTask`) and add op tests**

In both files the expected array becomes:
```ts
"chatSession", "distillReference", "enrichBrief", "extractDecisions",
"generateDictionary", "generateGuidance", "generatePlan", "generateRoadmap",
"planTeamWork", "runTask", "summarizeSession", "summarizeTurn", "synthesizeBrief",
```
Append to `planTeamWorkCore.test.ts`:
```ts
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest src/__tests__/planTeamWorkCore.test.ts src/__tests__/oneShotSidecar.test.ts src/__tests__/sidecarBuildersSurvive.test.ts`
Expected: FAIL — `planTeamWork` undefined / key lists differ.

- [ ] **Step 3: Implement** — add the import and the entry:

```ts
import { TEAM_PLAN_SYSTEM, TEAM_PLAN_TOOL, buildTeamPlanPrompt, coerceWorkPlan } from "../planTeamWorkCore";
// …inside ONE_SHOT_OPS, after generateRoadmap:
  planTeamWork: {
    plan(body) {
      const request = typeof body?.request === "string" ? body.request.trim() : "";
      if (!request) throw new OneShotBadRequest("request required");
      const roster: string[] = Array.isArray(body?.roster) ? body.roster.filter((k: unknown) => typeof k === "string") : [];
      return {
        system: TEAM_PLAN_SYSTEM,
        prompt: buildTeamPlanPrompt({
          language: body?.language === "vi" ? "vi" : "en",
          request,
          brief: body?.brief && typeof body.brief === "object" ? body.brief : null,
          company: body?.company && typeof body.company === "object" ? body.company : {},
          roster,
        }),
        schema: TEAM_PLAN_TOOL.input_schema,
      };
    },
    respond(body, parsed) {
      const roster: string[] = Array.isArray(body?.roster) ? body.roster : [];
      const plan = coerceWorkPlan(parsed, roster);
      if (!plan) throw new OneShotUnusableAnswer("no work plan in the reply");
      return plan;
    },
  },
```

- [ ] **Step 4: Run tests + rebuild sidecars**

Run: `cd functions && npx jest src/__tests__/planTeamWorkCore.test.ts src/__tests__/oneShotSidecar.test.ts src/__tests__/sidecarBuildersSurvive.test.ts` → PASS.
Run: `./scripts/build-sidecar.sh` → ends with the three `▸ done:` lines.

- [ ] **Step 5: Commit** — `git add functions/src && git commit -m "Register planTeamWork as a local one-shot op"`

---

### Task 3: Timeout for `LocalOneShotRunner`

**Files:**
- Modify: `codepet/Services/LocalOneShotRunner.swift:139-229`
- Test: `codepetTests/LocalOneShotTimeoutTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension LocalOneShotRunner {
      static var defaultTimeout: TimeInterval   // 180
      static func runProcess(_ proc: Process, stdin: Data, timeout: TimeInterval, label: String) async throws -> Data
  }
  // Failure gains: case timedOut(seconds: Int)
  // run(op:body:provider:companyId:modelPreference:timeout: TimeInterval = defaultTimeout)
  ```

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/LocalOneShotTimeoutTests.swift
import XCTest
@testable import codepet

/// A hung CLI call used to be unbounded: `run` waited on the process forever. A Team Build
/// chains several of them, so one hang would freeze the whole run with no way to say why.
final class LocalOneShotTimeoutTests: XCTestCase {
    func testAHungProcessIsKilledAndReportedAsATimeout() async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["5"]
        let started = Date()
        do {
            _ = try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 0.3, label: "test")
            XCTFail("a 5s sleep must not finish inside a 0.3s timeout")
        } catch let f as LocalOneShotRunner.Failure {
            XCTAssertEqual(f, .timedOut(seconds: 0))
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the process was not killed")
    }

    func testAFastProcessReturnsItsStdout() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/echo")
        p.arguments = ["{\"ok\":true}"]
        let out = try await LocalOneShotRunner.runProcess(p, stdin: Data(), timeout: 5, label: "test")
        XCTAssertEqual(String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "{\"ok\":true}")
    }

    func testDefaultIsThreeMinutes() {
        XCTAssertEqual(LocalOneShotRunner.defaultTimeout, 180)
    }
}
```

- [ ] **Step 2: Run** `-only-testing:codepetTests/LocalOneShotTimeoutTests` → FAIL (`runProcess` / `timedOut` missing).

- [ ] **Step 3: Implement.** Add `case timedOut(seconds: Int)` to `Failure` (give it an `errorDescription` like the other cases: `"Timed out after \(seconds)s"`). Move the body of the `withCheckedThrowingContinuation` block into `runProcess`, adding a timer:

```swift
static let defaultTimeout: TimeInterval = 180

/// The process half of `run`, extracted so the timeout is testable with any executable.
static func runProcess(_ proc: Process, stdin: Data, timeout: TimeInterval, label: String) async throws -> Data {
    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    proc.standardInput = inPipe
    let timedOut = TimeoutFlag()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
        let collector = OutputCollector()
        // …the two readabilityHandlers exactly as they are today…
        proc.terminationHandler = { p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            if timedOut.isSet {
                log.error("one-shot \(label, privacy: .public) timed out after \(Int(timeout), privacy: .public)s")
                continuation.resume(throwing: Failure.timedOut(seconds: Int(timeout)))
                return
            }
            // …the existing empty-stdout / success branches, unchanged…
        }
        do {
            try proc.run()
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard proc.isRunning else { return }
                timedOut.set()
                // The login shell's children (node → claude) would outlive a plain terminate();
                // kill the whole group the shell leads.
                kill(-proc.processIdentifier, SIGTERM)
                proc.terminate()
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
```
`run` builds `proc` (executable, arguments, environment) as today, then `let out = try await runProcess(proc, stdin: payload, timeout: timeout, label: op)`, then the existing `failure(in:)` check. Add `timeout: TimeInterval = defaultTimeout` as the last parameter of `run`.

Note: `kill(-pid)` only reaches the group if the child is a group leader. Before `proc.run()` in `run` (not in the test), this is best-effort; `proc.terminate()` always ends the shell and the pipes close, which is what unblocks the caller.

- [ ] **Step 4: Run** the suite → PASS. Also run `-only-testing:codepetTests/LocalOneShotRunnerTests` if it exists (`ls codepetTests | grep -i LocalOneShot`) → PASS.

- [ ] **Step 5: Commit** — "Bound every local one-shot call at 180s" (body: the hang was unbounded; a Team Build chains N calls).

---

### Task 4: Team Build models, client-side validation, persistence

**Files:**
- Create: `codepet/Models/TeamBuild.swift`
- Modify: `codepet/Models/CompanyState.swift` (fields :17, memberwise init, `init(from:)`), `codepet/Services/CompanyData.swift` (`CompanyDoc` :9, `state(from:)` :28, add `saveTeamRuns` beside `saveDecisions` :317)
- Test: `codepetTests/WorkPlanValidationTests.swift`, `codepetTests/TeamRunPersistenceTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct WorkStep: Codable, Equatable, Identifiable { let id, dept, title, instruction, kind: String; var dependsOn: [String]
      func asRoadmapTask() -> RoadmapTask }
  struct WorkPlan: Codable, Equatable { var title, slug, summary, projectType: String; var steps: [WorkStep]
      static let buildStepId = "build"; var buildStep: WorkStep?; var departmentSteps: [WorkStep] }
  enum TeamStepStatus: Codable, Equatable { case waiting, running, done, failed(String), blocked, cancelled, interrupted }
  struct TeamStepState: Codable, Equatable { let stepId: String; var status: TeamStepStatus; var startedAt: Date?; var finishedAt: Date?; var draft: Deliverable? }
  enum TeamRunPhase: String, Codable { case planned, running, assembling, ready, filed, cancelled, failed }
  struct TeamRun: Codable, Equatable, Identifiable { let id: String; let request: String; let createdAt: Date
      var brief: VCBrief?; var plan: WorkPlan; var steps: [TeamStepState]; var projectPath: String?; var phase: TeamRunPhase
      init(id: String = UUID().uuidString, request: String, createdAt: Date, brief: VCBrief?, plan: WorkPlan)
      func state(_ stepId: String) -> TeamStepState?; var isActive: Bool }
  enum WorkPlanValidation { static let routable: Set<String>; static let maxDeptSteps = 6; static let maxDeps = 3
      static func validate(_ plan: WorkPlan, roster: Set<String>) -> WorkPlan? }
  enum TeamBuildRoomOutcome: Equatable { case brief(VCBrief), requestOnly, clarify, failed
      static func from(phase: VCRunPhase, routingDecision: String?, brief: VCBrief?) -> TeamBuildRoomOutcome }
  // CompanyState.teamRuns: [TeamRun] (default [])
  // CompanyData.saveTeamRuns(companyId: String, runs: [TeamRun]) async -> Bool
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// codepetTests/WorkPlanValidationTests.swift
import XCTest
@testable import codepet

/// The client does not trust the op's plan: the same rules `coerceWorkPlan` applies, re-applied
/// here, so a stale sidecar or a hand-edited Firestore doc cannot schedule a cycle or 20 steps.
final class WorkPlanValidationTests: XCTestCase {
    private let roster: Set<String> = ["eng", "design", "mkt", "sales"]
    private func s(_ id: String, _ dept: String, _ deps: [String] = []) -> WorkStep {
        WorkStep(id: id, dept: dept, title: id, instruction: "", kind: "doc", dependsOn: deps)
    }
    private func plan(_ steps: [WorkStep]) -> WorkPlan {
        WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: steps)
    }

    func testDropsOffRosterAndNonRoutableSteps() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt"), s("s2", "legal"), s("s3", "chief_of_staff")]), roster: roster)!
        XCTAssertEqual(p.steps.map(\.id), ["s1", "build"])
    }
    func testKeepsOnlyEdgesToEarlierSteps() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt", ["s2"]), s("s2", "design", ["s1", "ghost"])]), roster: roster)!
        XCTAssertEqual(p.steps[0].dependsOn, [])
        XCTAssertEqual(p.steps[1].dependsOn, ["s1"])
    }
    func testCapsStepsAndDeps() {
        var many = (1...9).map { s("s\($0)", "mkt") }
        many[6] = s("s7", "design", ["s1", "s2", "s3", "s4"])
        let p = WorkPlanValidation.validate(plan(many), roster: roster)!
        XCTAssertEqual(p.departmentSteps.count, 6)
        XCTAssertTrue(p.departmentSteps.allSatisfy { $0.dependsOn.count <= 3 })
    }
    func testExactlyOneFinalBuildStepDependingOnAll() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt"), s("build", "eng", ["s1"]), s("s2", "sales")]), roster: roster)!
        XCTAssertEqual(p.steps.filter { $0.id == "build" }.count, 1)
        XCTAssertEqual(p.steps.last?.id, "build")
        XCTAssertEqual(p.steps.last?.dependsOn, ["s1", "s2"])
    }
    func testRoomOutcomeMapping() {
        let brief = VCBrief(recommendation: "r", confidence: 3, confidenceReason: "", theRealDisagreement: "",
                            tradeoffFounderMustOwn: "", killCriteria: [], nextAction: VCNextAction(action: "", owner: ""),
                            whatWeDontKnow: "", unresolved: false)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .finished, routingDecision: "multi_agent", brief: brief), .brief(brief))
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .routing, routingDecision: "single_agent", brief: nil), .requestOnly)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .routing, routingDecision: "needs_clarification", brief: nil), .clarify)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .failed, routingDecision: "multi_agent", brief: nil), .failed)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .idle, routingDecision: nil, brief: nil), .failed)
    }
}
```

```swift
// codepetTests/TeamRunPersistenceTests.swift
import XCTest
@testable import codepet

final class TeamRunPersistenceTests: XCTestCase {
    func testCompanyStateWithoutTeamRunsDecodesToEmpty() throws {
        let json = #"{"brief":{},"departments":[],"library":[],"stage":"idea","companionId":"byte"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertEqual(state.teamRuns, [])
    }
    func testTeamRunRoundTripsIncludingAFailedReason() throws {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "",
                            steps: [WorkStep(id: "build", dept: "eng", title: "b", instruction: "", kind: "other", dependsOn: [])])
        var run = TeamRun(request: "pants", createdAt: Date(timeIntervalSince1970: 0), brief: nil, plan: plan)
        run.steps[0].status = .failed("Timed out")
        let back = try JSONDecoder().decode(TeamRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(back, run)
    }
    func testANewRunStartsPlannedWithEveryStepWaiting() {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "",
                            steps: [WorkStep(id: "s1", dept: "mkt", title: "a", instruction: "", kind: "doc", dependsOn: []),
                                    WorkStep(id: "build", dept: "eng", title: "b", instruction: "", kind: "other", dependsOn: ["s1"])])
        let run = TeamRun(request: "x", createdAt: Date(), brief: nil, plan: plan)
        XCTAssertEqual(run.phase, .planned)
        XCTAssertEqual(run.steps.map(\.status), [.waiting, .waiting])
        XCTAssertTrue(run.isActive)
    }
}
```

- [ ] **Step 2: Run** both suites → FAIL (types missing).

- [ ] **Step 3: Implement `Models/TeamBuild.swift`**

```swift
// codepet/Models/TeamBuild.swift
import Foundation

/// One founder request, the whole company, a real project — see
/// docs/superpowers/specs/2026-09-24-team-build-design.md.
struct WorkStep: Codable, Equatable, Identifiable {
    let id: String
    let dept: String
    let title: String
    let instruction: String
    let kind: String
    var dependsOn: [String]

    /// A synthetic roadmap task, so the existing run machinery (`runRequest`, `UpstreamWork.fromDraft`)
    /// can be reused unchanged. Never added to `company.tasks`.
    func asRoadmapTask() -> RoadmapTask {
        RoadmapTask(id: "team-\(id)", title: title, detail: instruction, phase: .build, who: .draft,
                    dependsOn: [], dept: dept)
    }
}

struct WorkPlan: Codable, Equatable {
    var title: String
    var slug: String
    var summary: String
    var projectType: String
    var steps: [WorkStep]

    static let buildStepId = "build"
    var buildStep: WorkStep? { steps.first { $0.id == Self.buildStepId } }
    var departmentSteps: [WorkStep] { steps.filter { $0.id != Self.buildStepId } }
}

enum TeamStepStatus: Codable, Equatable {
    case waiting, running, done, failed(String), blocked, cancelled, interrupted
}

struct TeamStepState: Codable, Equatable {
    let stepId: String
    var status: TeamStepStatus = .waiting
    var startedAt: Date?
    var finishedAt: Date?
    var draft: Deliverable?
}

enum TeamRunPhase: String, Codable { case planned, running, assembling, ready, filed, cancelled, failed }

struct TeamRun: Codable, Equatable, Identifiable {
    let id: String
    let request: String
    let createdAt: Date
    var brief: VCBrief?
    var plan: WorkPlan
    var steps: [TeamStepState]
    var projectPath: String?
    var phase: TeamRunPhase

    init(id: String = UUID().uuidString, request: String, createdAt: Date, brief: VCBrief?, plan: WorkPlan) {
        self.id = id; self.request = request; self.createdAt = createdAt; self.brief = brief
        self.plan = plan; self.steps = plan.steps.map { TeamStepState(stepId: $0.id) }
        self.projectPath = nil; self.phase = .planned
    }

    func state(_ stepId: String) -> TeamStepState? { steps.first { $0.stepId == stepId } }
    /// Planned, running, assembling or stalled on a failure — anything the founder can still act on
    /// before approval. Gates "one TeamRun per company".
    var isActive: Bool { [.planned, .running, .assembling, .failed].contains(phase) }
}

enum WorkPlanValidation {
    static let routable: Set<String> = ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"]
    static let maxDeptSteps = 6
    static let maxDeps = 3

    /// Swift mirror of `coerceWorkPlan` rules 1, 3, 4, 5. Nil only if the plan has no build step
    /// AND nothing valid — which cannot happen after this runs, so callers may force-unwrap in tests.
    static func validate(_ plan: WorkPlan, roster: Set<String>) -> WorkPlan? {
        let allowed = routable.intersection(roster)
        var buildInstruction = plan.buildStep?.instruction ?? ""
        var accepted: [WorkStep] = []
        var ids = Set<String>()
        for var s in plan.steps {
            if s.id == WorkPlan.buildStepId {
                if buildInstruction.isEmpty { buildInstruction = s.instruction }
                continue
            }
            guard allowed.contains(s.dept), !ids.contains(s.id), accepted.count < maxDeptSteps else { continue }
            var seen = Set<String>()
            s.dependsOn = s.dependsOn.filter { ids.contains($0) && seen.insert($0).inserted }.prefix(maxDeps).map { $0 }
            accepted.append(s); ids.insert(s.id)
        }
        let build = WorkStep(id: WorkPlan.buildStepId, dept: "eng", title: plan.buildStep?.title ?? "Build the project",
                             instruction: buildInstruction, kind: "other", dependsOn: accepted.map(\.id))
        var out = plan
        out.steps = accepted + [build]
        return out
    }
}

enum TeamBuildRoomOutcome: Equatable {
    case brief(VCBrief), requestOnly, clarify, failed

    static func from(phase: VCRunPhase, routingDecision: String?, brief: VCBrief?) -> TeamBuildRoomOutcome {
        switch routingDecision {
        case "single_agent": return .requestOnly
        case "needs_clarification": return .clarify
        default:
            if phase == .finished, let brief { return .brief(brief) }
            return .failed
        }
    }
}
```
Note: `VCBrief` must be `Codable` (it is) and `Equatable` (it is).

- [ ] **Step 4: Persistence.** In `CompanyState`: add `var teamRuns: [TeamRun]`, a defaulted memberwise parameter `teamRuns: [TeamRun] = []`, and in `init(from:)` `teamRuns = try c.decodeIfPresent([TeamRun].self, forKey: .teamRuns) ?? []` (add the key to its CodingKeys if the struct declares them). In `CompanyData`: add `var teamRuns: [TeamRun]?` to `CompanyDoc`, map it in `state(from:)` with `?? []`, and:

```swift
static func saveTeamRuns(companyId: String, runs: [TeamRun]) async -> Bool {
    guard PrototypeMode.allowsCloudWrites else { return true }
    do {
        try await Firestore.firestore().collection("companies").document(companyId)
            .setData(teamRunsPayload(runs), merge: true)
        return true
    } catch { return false }
}
static func teamRunsPayload(_ runs: [TeamRun]) -> [String: Any] {
    // Same JSONEncoder → JSONSerialization route as decisionsPayload, so Dates encode identically.
    guard let data = try? JSONEncoder().encode(runs),
          let arr = try? JSONSerialization.jsonObject(with: data) else { return [:] }
    return ["teamRuns": arr]
}
```
Match `decisionsPayload`'s encoder configuration exactly (read it first; if it sets a date strategy, use the same).

- [ ] **Step 5: Run** `WorkPlanValidationTests`, `TeamRunPersistenceTests`, and the existing `CompanyStateTests`/`CompanyDataTests` if present (`ls codepetTests | grep -i -E "CompanyState|CompanyData"`) → PASS.

- [ ] **Step 6: Commit** — "Add Team Build models, client-side plan validation and persistence".

---

### Task 5: `TeamPlanClient` — call `planTeamWork`

**Files:**
- Create: `codepet/Services/TeamPlanClient.swift`
- Test: `codepetTests/TeamPlanClientTests.swift`

**Interfaces:**
- Consumes: `LocalTransportRouter.forOneShot()`, `LocalOneShotRunner.run(op:body:provider:)`, `WorkPlan`, `VCBrief`.
- Produces:
  ```swift
  struct TeamPlanRequest: Encodable { let language: String; let request: String; let brief: VCBrief?; let company: [String: String]; let roster: [String] }
  enum TeamPlanClient {
      static func decode(_ data: Data) -> WorkPlan?
      static func plan(_ req: TeamPlanRequest) async -> WorkPlan?   // nil on blocked / failure
  }
  ```
  `VCBrief` must encode with the SNAKE_CASE keys the TS `DecisionBrief` expects (`confidence_reason`, `the_real_disagreement`, `tradeoff_founder_must_own`, `kill_criteria`, `next_action`, `what_we_dont_know`). Check `VCBrief`'s `CodingKeys` in `Models/VirtualCompanyRun.swift:159`; it decodes the room's snake_case frames, so its synthesized `Encodable` already uses those keys. The test pins it.

- [ ] **Step 1: Failing test**

```swift
// codepetTests/TeamPlanClientTests.swift
import XCTest
@testable import codepet

final class TeamPlanClientTests: XCTestCase {
    func testDecodesTheOpsResponse() {
        let json = #"{"title":"Pants","slug":"pants","summary":"s","projectType":"static landing page","steps":[{"id":"s1","dept":"mkt","title":"Msg","instruction":"i","kind":"doc","dependsOn":[]},{"id":"build","dept":"eng","title":"Build the project","instruction":"","kind":"other","dependsOn":["s1"]}]}"#
        let plan = TeamPlanClient.decode(Data(json.utf8))
        XCTAssertEqual(plan?.steps.map(\.id), ["s1", "build"])
    }
    func testGarbageDecodesToNil() {
        XCTAssertNil(TeamPlanClient.decode(Data("nope".utf8)))
    }
    func testBriefEncodesWithTheKeysTheOpReads() throws {
        let brief = VCBrief(recommendation: "r", confidence: 3, confidenceReason: "c", theRealDisagreement: "d",
                            tradeoffFounderMustOwn: "t", killCriteria: ["k"], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "w", unresolved: false)
        let req = TeamPlanRequest(language: "en", request: "x", brief: brief, company: [:], roster: ["mkt"])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as! [String: Any]
        let b = obj["brief"] as! [String: Any]
        for key in ["recommendation", "tradeoff_founder_must_own", "kill_criteria", "what_we_dont_know"] {
            XCTAssertNotNil(b[key], "the op reads \(key)")
        }
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
// codepet/Services/TeamPlanClient.swift
import Foundation
import os

private let log = Logger(subsystem: "app.murror.codepet", category: "TeamPlanClient")

struct TeamPlanRequest: Encodable {
    let language: String
    let request: String
    let brief: VCBrief?
    let company: [String: String]
    let roster: [String]
}

/// Local-only, like every AI path since the key was deleted: no Cloud Function fallback.
enum TeamPlanClient {
    static func decode(_ data: Data) -> WorkPlan? { try? JSONDecoder().decode(WorkPlan.self, from: data) }

    static func plan(_ req: TeamPlanRequest) async -> WorkPlan? {
        switch LocalTransportRouter.forOneShot() {
        case .local(let provider):
            do {
                let body = try JSONEncoder().encode(req)
                let out = try await LocalOneShotRunner.run(op: "planTeamWork", body: body, provider: provider)
                return decode(out)
            } catch {
                log.error("planTeamWork failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .blocked(let reason):
            log.error("planTeamWork blocked: \(String(describing: reason), privacy: .public)")
            return nil
        }
    }
}
```
If `testBriefEncodesWithTheKeysTheOpReads` fails because `VCBrief` encodes camelCase, give `TeamPlanRequest` a custom `encode(to:)` that writes `brief` through a private snake_case mirror struct — do NOT change `VCBrief`'s keys (the room decodes with them).

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — "Add TeamPlanClient for the planTeamWork op".

---

### Task 6: `TeamRunCoordinator` — scheduling

**Files:**
- Create: `codepet/Managers/TeamRunCoordinator.swift`
- Test: `codepetTests/TeamRunCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 4 types; `UpstreamWork.fromDraft(_:task:unapproved:)`.
- Produces:
  ```swift
  enum TeamStepResult { case success(Deliverable), failure(String) }
  enum TeamAssemblyResult { case success(path: String), failure(String) }
  @MainActor final class TeamRunCoordinator: ObservableObject {
      typealias StepRunner = (WorkStep, [UpstreamWork]) async -> TeamStepResult
      typealias Assembler = (TeamRun, @escaping (String) -> Void) async -> TeamAssemblyResult
      typealias Saver = (TeamRun) async -> Void
      static let maxConcurrent = 3
      @Published private(set) var run: TeamRun?
      @Published private(set) var buildLog: [String]
      init(runStep: @escaping StepRunner, assemble: @escaping Assembler, save: @escaping Saver, now: @escaping () -> Date = Date.init)
      func load(_ run: TeamRun)            // persisted `running` steps → `interrupted`
      func start() async                   // planned → running; returns when settled
      func retry(stepId: String) async     // failed → waiting, unblocks dependents; returns when settled
      func continueInterrupted() async     // interrupted → waiting; returns when settled
      func stop()                          // cancel in-flight; non-done → cancelled; phase cancelled
      func markFiled()                     // ready → filed
  }
  ```

- [ ] **Step 1: Failing tests**

```swift
// codepetTests/TeamRunCoordinatorTests.swift
import XCTest
@testable import codepet

@MainActor
final class TeamRunCoordinatorTests: XCTestCase {
    private actor Log {
        var started: [String] = []; var upstreamFor: [String: [String]] = [:]; var peak = 0; var live = 0
        func begin(_ id: String, _ up: [String]) { started.append(id); upstreamFor[id] = up; live += 1; peak = max(peak, live) }
        func end() { live -= 1 }
    }
    private func step(_ id: String, _ deps: [String] = []) -> WorkStep {
        WorkStep(id: id, dept: "mkt", title: id, instruction: "", kind: "doc", dependsOn: deps)
    }
    private func run(_ steps: [WorkStep]) -> TeamRun {
        let plan = WorkPlanValidation.validate(WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: steps),
                                               roster: ["mkt"])!
        return TeamRun(request: "r", createdAt: Date(), brief: nil, plan: plan)
    }
    private func draft(_ id: String) -> Deliverable { Deliverable(kind: .doc, title: "out-\(id)", body: "body \(id)") }

    private func coordinator(log: Log, fail: Set<String> = [], assemble: TeamAssemblyResult = .success(path: "/tmp/p"),
                             saves: (() -> Void)? = nil) -> TeamRunCoordinator {
        TeamRunCoordinator(
            runStep: { step, up in
                await log.begin(step.id, up.map(\.taskTitle))
                try? await Task.sleep(nanoseconds: 20_000_000)
                await log.end()
                return fail.contains(step.id) ? .failure("boom") : .success(self.draft(step.id))
            },
            assemble: { _, onLog in onLog("wrote index.html"); return assemble },
            save: { _ in saves?() })
    }

    func testChainRunsInOrderAndFeedsOnlyDirectDeps() async {
        let log = Log()
        let c = coordinator(log: log)
        c.load(run([step("a"), step("b", ["a"]), step("c", ["b"])]))
        await c.start()
        let started = await log.started
        let up = await log.upstreamFor
        XCTAssertEqual(started, ["a", "b", "c"])
        XCTAssertEqual(up["c"], ["out-b"], "C receives B's draft, not A's")
        XCTAssertEqual(c.run?.phase, .ready)
        XCTAssertEqual(c.run?.projectPath, "/tmp/p")
        XCTAssertEqual(c.buildLog, ["wrote index.html"])
    }
    func testNeverMoreThanThreeAtOnce() async {
        let log = Log()
        let c = coordinator(log: log)
        c.load(run((1...6).map { step("s\($0)") }))
        await c.start()
        let peak = await log.peak
        XCTAssertEqual(peak, 3)
    }
    func testFailureBlocksOnlyDependentsAndRetryResumes() async {
        let log = Log()
        var failing: Set<String> = ["a"]
        let c = TeamRunCoordinator(
            runStep: { step, _ in await log.begin(step.id, []); await log.end()
                return failing.contains(step.id) ? .failure("boom") : .success(self.draft(step.id)) },
            assemble: { _, _ in .success(path: "/tmp/p") }, save: { _ in })
        c.load(run([step("a"), step("b", ["a"]), step("x")]))
        await c.start()
        XCTAssertEqual(c.run?.state("a")?.status, .failed("boom"))
        XCTAssertEqual(c.run?.state("b")?.status, .blocked)
        XCTAssertEqual(c.run?.state("x")?.status, .done)
        XCTAssertEqual(c.run?.state("build")?.status, .blocked)
        XCTAssertEqual(c.run?.phase, .failed)
        failing = []
        await c.retry(stepId: "a")
        XCTAssertEqual(c.run?.state("b")?.status, .done)
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testAssemblyFailureFailsTheBuildStep() async {
        let c = coordinator(log: Log(), assemble: .failure("Timed out after 15 min"))
        c.load(run([step("a")]))
        await c.start()
        XCTAssertEqual(c.run?.state("build")?.status, .failed("Timed out after 15 min"))
        XCTAssertEqual(c.run?.phase, .failed)
    }
    func testLoneBuildStepGoesStraightToAssembly() async {
        let c = coordinator(log: Log())
        c.load(run([]))
        await c.start()
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testStopCancelsEverythingNotDone() async {
        let c = TeamRunCoordinator(
            runStep: { _, _ in try? await Task.sleep(nanoseconds: 2_000_000_000); return .failure("late") },
            assemble: { _, _ in .success(path: "/p") }, save: { _ in })
        c.load(run([step("a"), step("b", ["a"])]))
        let t = Task { await c.start() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        c.stop()
        await t.value
        XCTAssertEqual(c.run?.phase, .cancelled)
        XCTAssertEqual(c.run?.steps.map(\.status), [.cancelled, .cancelled, .cancelled])
    }
    func testLoadTurnsRunningIntoInterruptedAndContinueRerunsOnlyThose() async {
        let log = Log()
        var persisted = run([step("a"), step("b", ["a"])])
        persisted.phase = .running
        persisted.steps[0].status = .done; persisted.steps[0].draft = draft("a")
        persisted.steps[1].status = .running
        let c = coordinator(log: log)
        c.load(persisted)
        XCTAssertEqual(c.run?.state("b")?.status, .interrupted)
        await c.continueInterrupted()
        let started = await log.started
        XCTAssertEqual(started, ["b"], "done steps are never re-run")
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testInterruptedBuildReassembles() async {
        var persisted = run([step("a")])
        persisted.phase = .assembling
        persisted.steps[0].status = .done; persisted.steps[0].draft = draft("a")
        persisted.steps[1].status = .running
        var assembled = 0
        let c = TeamRunCoordinator(runStep: { _, _ in .failure("must not run") },
                                   assemble: { _, _ in assembled += 1; return .success(path: "/p-2") }, save: { _ in })
        c.load(persisted)
        await c.continueInterrupted()
        XCTAssertEqual(assembled, 1)
        XCTAssertEqual(c.run?.projectPath, "/p-2")
    }
    func testSavesOnEveryTransition() async {
        var saves = 0
        let c = coordinator(log: Log(), saves: { saves += 1 })
        c.load(run([step("a")]))
        await c.start()
        // start, a running, a done, build running, build done/ready — at least 5.
        XCTAssertGreaterThanOrEqual(saves, 5)
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
// codepet/Managers/TeamRunCoordinator.swift
import Foundation

enum TeamStepResult { case success(Deliverable), failure(String) }
enum TeamAssemblyResult { case success(path: String), failure(String) }

/// Schedules a Team Build: department steps in dependency order (≤3 at once), each fed its
/// DIRECT dependencies' drafts, then the build step through the assembler. Every dependency is
/// injected, so the whole state machine is testable without Claude, Firestore or a disk.
@MainActor
final class TeamRunCoordinator: ObservableObject {
    typealias StepRunner = (WorkStep, [UpstreamWork]) async -> TeamStepResult
    typealias Assembler = (TeamRun, @escaping (String) -> Void) async -> TeamAssemblyResult
    typealias Saver = (TeamRun) async -> Void

    static let maxConcurrent = 3

    @Published private(set) var run: TeamRun?
    @Published private(set) var buildLog: [String] = []

    private let runStep: StepRunner
    private let assemble: Assembler
    private let save: Saver
    private let now: () -> Date
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(runStep: @escaping StepRunner, assemble: @escaping Assembler, save: @escaping Saver,
         now: @escaping () -> Date = Date.init) {
        self.runStep = runStep; self.assemble = assemble; self.save = save; self.now = now
    }

    func load(_ run: TeamRun) {
        var r = run
        for i in r.steps.indices where r.steps[i].status == .running { r.steps[i].status = .interrupted }
        self.run = r
    }

    func start() async {
        guard var r = run, r.phase == .planned else { return }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func retry(stepId: String) async {
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == stepId }),
              case .failed = r.steps[i].status else { return }
        r.steps[i].status = .waiting
        for j in r.steps.indices where r.steps[j].status == .blocked { r.steps[j].status = .waiting }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func continueInterrupted() async {
        guard var r = run else { return }
        for i in r.steps.indices where r.steps[i].status == .interrupted { r.steps[i].status = .waiting }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func stop() {
        guard var r = run else { return }
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        for i in r.steps.indices where r.steps[i].status != .done { r.steps[i].status = .cancelled }
        r.phase = .cancelled
        commit(r)
        resumeWaiters()
    }

    func markFiled() {
        guard var r = run, r.phase == .ready else { return }
        r.phase = .filed
        commit(r)
    }

    // MARK: - Scheduling

    private func pumpUntilSettled() async {
        schedule()
        if isSettled { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private var isSettled: Bool {
        guard let r = run else { return true }
        return inFlight.isEmpty && !r.steps.contains { $0.status == .waiting && depsDone($0.stepId, in: r) }
    }

    private func depsDone(_ stepId: String, in r: TeamRun) -> Bool {
        guard let step = r.plan.steps.first(where: { $0.id == stepId }) else { return false }
        return step.dependsOn.allSatisfy { r.state($0)?.status == .done }
    }

    private func schedule() {
        guard var r = run, r.phase == .running || r.phase == .assembling else { resumeIfSettled(); return }
        propagateBlocks(&r)
        var slots = Self.maxConcurrent - inFlight.count
        for step in r.plan.steps where slots > 0 {
            guard r.state(step.id)?.status == .waiting, depsDone(step.id, in: r) else { continue }
            let i = r.steps.firstIndex { $0.stepId == step.id }!
            r.steps[i].status = .running
            r.steps[i].startedAt = now()
            slots -= 1
            if step.id == WorkPlan.buildStepId {
                r.phase = .assembling
                launchAssembly(r)
            } else {
                launchStep(step, upstream: upstream(for: step, in: r))
            }
        }
        settlePhase(&r)
        commit(r)
        resumeIfSettled()
    }

    private func launchStep(_ step: WorkStep, upstream: [UpstreamWork]) {
        inFlight[step.id] = Task { [weak self] in
            guard let self else { return }
            let result = await self.runStep(step, upstream)
            guard !Task.isCancelled else { return }
            self.finish(step.id, result: result)
        }
    }

    private func launchAssembly(_ snapshot: TeamRun) {
        buildLog = []
        inFlight[WorkPlan.buildStepId] = Task { [weak self] in
            guard let self else { return }
            let result = await self.assemble(snapshot) { [weak self] line in self?.buildLog.append(line) }
            guard !Task.isCancelled else { return }
            self.finishAssembly(result)
        }
    }

    private func finish(_ stepId: String, result: TeamStepResult) {
        inFlight[stepId] = nil
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == stepId }) else { return }
        r.steps[i].finishedAt = now()
        switch result {
        case .success(let d): r.steps[i].status = .done; r.steps[i].draft = d
        case .failure(let why): r.steps[i].status = .failed(why)
        }
        run = r
        schedule()
    }

    private func finishAssembly(_ result: TeamAssemblyResult) {
        inFlight[WorkPlan.buildStepId] = nil
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == WorkPlan.buildStepId }) else { return }
        r.steps[i].finishedAt = now()
        switch result {
        case .success(let path): r.steps[i].status = .done; r.projectPath = path; r.phase = .ready
        case .failure(let why): r.steps[i].status = .failed(why); r.phase = .failed
        }
        commit(r)
        resumeIfSettled()
    }

    /// Direct dependencies only: a dependency's draft already absorbed its own upstream, which is
    /// what makes the chain multi-level without re-sending the whole history.
    private func upstream(for step: WorkStep, in r: TeamRun) -> [UpstreamWork] {
        step.dependsOn.prefix(UpstreamWork.cap).compactMap { depId in
            guard let dep = r.plan.steps.first(where: { $0.id == depId }),
                  let d = r.state(depId)?.draft else { return nil }
            return UpstreamWork.fromDraft(d, task: dep.asRoadmapTask(), unapproved: true)
        }
    }

    private func propagateBlocks(_ r: inout TeamRun) {
        var changed = true
        while changed {
            changed = false
            for step in r.plan.steps {
                guard let i = r.steps.firstIndex(where: { $0.stepId == step.id }), r.steps[i].status == .waiting else { continue }
                let deadDep = step.dependsOn.contains { dep in
                    switch r.state(dep)?.status { case .failed, .blocked, .cancelled: return true; default: return false }
                }
                if deadDep { r.steps[i].status = .blocked; changed = true }
            }
        }
    }

    private func settlePhase(_ r: inout TeamRun) {
        guard inFlight.isEmpty, r.phase == .running || r.phase == .assembling else { return }
        let anyRunnable = r.steps.contains { $0.status == .waiting && depsDone($0.stepId, in: r) }
        if anyRunnable { return }
        if r.steps.contains(where: { if case .failed = $0.status { return true }; return $0.status == .blocked }) {
            r.phase = .failed
        }
    }

    private func commit(_ r: TeamRun) {
        run = r
        let snapshot = r
        Task { await save(snapshot) }
    }

    private func resumeIfSettled() { if isSettled { resumeWaiters() } }
    private func resumeWaiters() { let w = waiters; waiters = []; w.forEach { $0.resume() } }
}
```

Implementation notes (read before coding):
- `finish` sets `run = r` then calls `schedule()`, which commits (saves), so every transition is saved exactly once.
- `testSavesOnEveryTransition` counts `save` calls. `commit` saves in a detached `Task`, so the count lands asynchronously. If it flakes, have the test `await Task.yield()` a few times before asserting. Do NOT make `save` synchronous on the main path.
- In `testFailureBlocksOnlyDependentsAndRetryResumes`, `failing` is captured by the closure and mutated after the first `start()`. That works because the closure reads it at call time.

- [ ] **Step 4: Run** `-only-testing:codepetTests/TeamRunCoordinatorTests` → PASS. Repeat 3 times to check for flakes.
- [ ] **Step 5: Commit** — "Add TeamRunCoordinator: multi-level dependency scheduling for Team Build".

---

### Task 7: `DeliverableMarkdown.render`

**Files:**
- Create: `codepet/Models/DeliverableMarkdown.swift`
- Test: `codepetTests/DeliverableMarkdownTests.swift`

**Interfaces:**
- Consumes: `Deliverable`, `DeliverablePayload` (read `Models/Deliverable.swift` for the payload's cases/fields before writing: site, checklist, doc, plan, dms, calendar, sheet, screens).
- Produces: `enum DeliverableMarkdown { static func render(_ d: Deliverable, dept: String, instruction: String) -> String }`

- [ ] **Step 1: Failing tests** — one test per structured kind that the payload type actually has. For `site`:

```swift
// codepetTests/DeliverableMarkdownTests.swift
import XCTest
@testable import codepet

final class DeliverableMarkdownTests: XCTestCase {
    func testPlainBodyIsKeptUnderATitleAndHeader() {
        let d = Deliverable(kind: .doc, title: "Positioning", body: "Office workers 25-35.")
        let md = DeliverableMarkdown.render(d, dept: "Marketing", instruction: "Write positioning")
        XCTAssertTrue(md.hasPrefix("# Positioning"))
        XCTAssertTrue(md.contains("**Department:** Marketing"))
        XCTAssertTrue(md.contains("**Asked for:** Write positioning"))
        XCTAssertTrue(md.contains("Office workers 25-35."))
    }
    func testSitePayloadRendersEveryCopyField() {
        // Build a Deliverable with kind .site and a payload whose site fields are filled
        // (headline, sub, ctaPrimary, features[0].h/.p, finalCta). Use the payload's real
        // initializer from Models/Deliverable.swift.
        // Assert the rendered markdown contains each of those strings.
    }
}
```
The implementer MUST replace the comment in `testSitePayloadRendersEveryCopyField` with real construction code taken from `Models/Deliverable.swift`, and add one analogous test per remaining structured payload case. A test with no asserts does not count.

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Write a header (`# title`, `**Department:**`, `**Asked for:**`), then a `switch` over the payload's structured cases, each writing Markdown (headings for sections, `- ` bullets for lists, a table for sheets), then `## Notes` plus `d.body` when the body is not already the rendered content. If the payload is nil, just output the body.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — "Render deliverables to Markdown for a Team Build's docs/".

---

### Task 8: `ProjectAssembler` + `TeamBuildPrompt`

**Files:**
- Create: `codepet/Services/TeamBuildPrompt.swift`, `codepet/Services/ProjectAssembler.swift`
- Test: `codepetTests/ProjectAssemblerTests.swift`

**Interfaces:**
- Consumes: `TeamRun`, `WorkPlan`, `DeliverableMarkdown.render`, `CLIRunner` (`run(prompt:projectDir:allowedTools:maxTurns:)`, `@Published state`, `@Published events`, `cancel()`), `DepartmentCatalog.find(_:)?.name`.
- Produces:
  ```swift
  enum TeamBuildPrompt {
      static let requiredHeadings = ["## What this is", "## What the team decided", "## Who did what", "## How to run", "## Next steps"]
      static let allowedTools = ["Read", "Write", "Edit", "Glob", "Grep"]
      static func prompt(for run: TeamRun, docs: [String]) -> String
      static func fallbackClaudeMd(for run: TeamRun, docs: [String]) -> String
      static func isComplete(_ claudeMd: String) -> Bool
  }
  protocol ProjectCodeRunning { func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                                        timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? } // nil = ok, else failure reason
  final class CLIProjectRunner: ProjectCodeRunning
  struct ProjectAssembler {
      var root: URL                      // default ~/Codepet Projects
      var coder: ProjectCodeRunning
      var git: (_ args: [String], _ dir: URL) -> Bool
      static let buildTimeout: TimeInterval = 900
      static let maxTurns = 40
      func assemble(_ run: TeamRun, onLog: @escaping (String) -> Void) async -> TeamAssemblyResult
      func makeFolder(slug: String) throws -> URL
  }
  ```

- [ ] **Step 1: Failing tests**

```swift
// codepetTests/ProjectAssemblerTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectAssemblerTests: XCTestCase {
    private var tmp: URL!
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp); super.tearDown() }

    private final class FakeCoder: ProjectCodeRunning {
        var writeClaudeMd: String?
        var failure: String?
        private(set) var tools: [String] = []
        private(set) var prompt = ""
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            self.prompt = prompt; tools = allowedTools
            onEvent("wrote index.html")
            try? "<html></html>".write(toFile: dir + "/index.html", atomically: true, encoding: .utf8)
            if let md = writeClaudeMd { try? md.write(toFile: dir + "/CLAUDE.md", atomically: true, encoding: .utf8) }
            return failure
        }
    }

    private func teamRun(slug: String = "pants") -> TeamRun {
        let steps = [WorkStep(id: "s1", dept: "mkt", title: "Message", instruction: "Write the message", kind: "doc", dependsOn: []),
                     WorkStep(id: "build", dept: "eng", title: "Build", instruction: "static page", kind: "other", dependsOn: ["s1"])]
        var r = TeamRun(request: "pants page", createdAt: Date(), brief: nil,
                        plan: WorkPlan(title: "Pants", slug: slug, summary: "Office pants", projectType: "static landing page", steps: steps))
        r.steps[0].status = .done
        r.steps[0].draft = Deliverable(kind: .doc, title: "Message", body: "Comfy all day.")
        return r
    }
    private func assembler(_ coder: FakeCoder, gitCalls: @escaping ([String]) -> Void = { _ in }) -> ProjectAssembler {
        ProjectAssembler(root: tmp, coder: coder, git: { args, _ in gitCalls(args); return true })
    }

    func testCreatesRootAndFallsBackToProject() throws {
        let a = assembler(FakeCoder())
        let url = try a.makeFolder(slug: "")
        XCTAssertEqual(url.lastPathComponent, "project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }
    func testCollisionAppendsASuffix() throws {
        let a = assembler(FakeCoder())
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants")
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants-2")
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants-3")
    }
    func testWritesDecisionAndDepartmentDocs() async throws {
        let coder = FakeCoder(); coder.writeClaudeMd = TeamBuildPrompt.requiredHeadings.joined(separator: "\n\nx\n\n")
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail("\(result)") }
        let docs = try FileManager.default.contentsOfDirectory(atPath: path + "/docs").sorted()
        XCTAssertEqual(docs, ["00-decision.md", "01-mkt-message.md"])
        let mkt = try String(contentsOfFile: path + "/docs/01-mkt-message.md", encoding: .utf8)
        XCTAssertTrue(mkt.contains("Comfy all day."))
        XCTAssertTrue(coder.prompt.contains("docs/01-mkt-message.md"))
    }
    func testMissingClaudeMdGetsTheFallback() async throws {
        let result = await assembler(FakeCoder()).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        let md = try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8)
        XCTAssertTrue(TeamBuildPrompt.isComplete(md))
        XCTAssertTrue(md.contains("pants page"))
    }
    func testIncompleteClaudeMdIsReplaced() async throws {
        let coder = FakeCoder(); coder.writeClaudeMd = "# Pants\n\nno sections"
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        XCTAssertTrue(TeamBuildPrompt.isComplete(try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8)))
    }
    func testACompleteClaudeMdIsLeftAlone() async throws {
        let written = TeamBuildPrompt.requiredHeadings.joined(separator: "\n\nmine\n\n")
        let coder = FakeCoder(); coder.writeClaudeMd = written
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        XCTAssertEqual(try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8), written)
    }
    func testClaudeCodeGetsFileToolsOnly() async {
        let coder = FakeCoder()
        _ = await assembler(coder).assemble(teamRun()) { _ in }
        XCTAssertEqual(coder.tools, ["Read", "Write", "Edit", "Glob", "Grep"])
        XCTAssertFalse(coder.tools.contains("Bash"))
    }
    func testGitInitThenCommit() async {
        var calls: [[String]] = []
        _ = await assembler(FakeCoder(), gitCalls: { calls.append($0) }).assemble(teamRun()) { _ in }
        XCTAssertEqual(calls.first, ["init"])
        XCTAssertTrue(calls.contains(["add", "-A"]))
        XCTAssertTrue(calls.contains { $0.first == "commit" })
    }
    func testCoderFailureFailsTheAssembly() async {
        let coder = FakeCoder(); coder.failure = "Timed out after 15 min"
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .failure(let why) = result else { return XCTFail() }
        XCTAssertEqual(why, "Timed out after 15 min")
    }
    func testEventsReachTheLog() async {
        var lines: [String] = []
        _ = await assembler(FakeCoder()).assemble(teamRun()) { lines.append($0) }
        XCTAssertTrue(lines.contains("wrote index.html"))
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement `TeamBuildPrompt.swift`**

```swift
// codepet/Services/TeamBuildPrompt.swift
import Foundation

/// The build prompt lives here, not in functions/, on purpose: it has no cloud path to share
/// with, and CLIRunner is Swift. See the plan's "deliberate deviations".
enum TeamBuildPrompt {
    static let requiredHeadings = ["## What this is", "## What the team decided", "## Who did what",
                                   "## How to run", "## Next steps"]
    static let allowedTools = ["Read", "Write", "Edit", "Glob", "Grep"]

    static func isComplete(_ md: String) -> Bool { requiredHeadings.allSatisfy { md.contains($0) } }

    static func prompt(for run: TeamRun, docs: [String]) -> String {
        let build = run.plan.buildStep?.instruction ?? ""
        return """
        You are the engineer on a small company's team. The founder asked: "\(run.request)"
        Build it as: \(run.plan.projectType). \(build)

        The rest of the team has already done their part. Read every file below BEFORE writing anything:
        \(docs.map { "- \($0)" }.joined(separator: "\n"))

        Build the complete project in the current directory. Use the team's work faithfully — their copy,
        their design direction, their prices. Do not invent facts they did not give you.
        You cannot run shell commands: write every file in full, and document installation instead.
        If this is not software, produce a well-organised document project with a README.md.

        Finally write CLAUDE.md with exactly these sections, in this order:
        \(requiredHeadings.joined(separator: "\n"))
        "Who did what" must link each file in docs/. "How to run" must say nothing has been installed yet.
        """
    }

    static func fallbackClaudeMd(for run: TeamRun, docs: [String]) -> String {
        let decided = run.brief.map { "\($0.recommendation)\n\nTrade-off you own: \($0.tradeoffFounderMustOwn)" }
            ?? run.plan.summary
        let who = run.plan.departmentSteps.map { step -> String in
            let name = DepartmentCatalog.find(step.dept)?.name ?? step.dept
            let file = docs.first { $0.contains("-\(step.dept)-") } ?? ""
            return "- **\(name)** — \(step.title)" + (file.isEmpty ? "" : " ([\(file)](\(file)))")
        }.joined(separator: "\n")
        return """
        # \(run.plan.title)

        ## What this is
        \(run.plan.projectType) — built by Codepet's team from the request: "\(run.request)"

        ## What the team decided
        \(decided)

        ## Who did what
        \(who.isEmpty ? "- The engineer built this from the decision alone." : who)
        - **Engineering** — built the project

        ## How to run
        Nothing has been installed yet. Open this folder with Claude Code and ask it to set the project up.

        ## Next steps
        Review docs/, then ask Claude Code in this folder for the first change you want.
        """
    }
}
```

- [ ] **Step 4: Implement `ProjectAssembler.swift`**

```swift
// codepet/Services/ProjectAssembler.swift
import Foundation
import Combine

protocol ProjectCodeRunning {
    /// Returns nil on success, else a founder-readable failure reason.
    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String?
}

/// `CodeRunning`'s adapter hardcodes the default 8 turns and the base tools (which include Bash),
/// so a project build gets its own thin wrapper over the same `CLIRunner`.
@MainActor
final class CLIProjectRunner: ProjectCodeRunning {
    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
        let runner = CLIRunner()
        var bag = Set<AnyCancellable>()
        var seen = 0
        return await withCheckedContinuation { cont in
            var resumed = false
            func finish(_ r: String?) { guard !resumed else { return }; resumed = true; bag.removeAll(); cont.resume(returning: r) }
            runner.$events.sink { events in
                for e in events.dropFirst(seen) where e.kind == .toolUse {
                    let tool = e.toolName ?? "tool"
                    onEvent(e.filePath.map { "\(tool) \(($0 as NSString).lastPathComponent)" } ?? tool)
                }
                seen = events.count
            }.store(in: &bag)
            runner.$state.sink { state in
                switch state {
                case .finished(let code): finish(code == 0 ? nil : "Claude Code exited \(code)")
                case .failed(let reason): finish(reason)
                default: break
                }
            }.store(in: &bag)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                runner.cancel()
                finish("Timed out after \(Int(timeout / 60)) min")
            }
            runner.run(prompt: prompt, projectDir: dir, allowedTools: allowedTools, maxTurns: maxTurns)
        }
    }
}

struct ProjectAssembler {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Codepet Projects")
    var coder: ProjectCodeRunning
    var git: (_ args: [String], _ dir: URL) -> Bool = ProjectAssembler.runGit

    static let buildTimeout: TimeInterval = 900
    static let maxTurns = 40

    func makeFolder(slug: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = slug.isEmpty ? "project" : slug
        var name = base, n = 1
        while fm.fileExists(atPath: root.appendingPathComponent(name).path) { n += 1; name = "\(base)-\(n)" }
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func assemble(_ run: TeamRun, onLog: @escaping (String) -> Void) async -> TeamAssemblyResult {
        let dir: URL
        do { dir = try makeFolder(slug: run.plan.slug) } catch { return .failure("Could not create the project folder") }
        _ = git(["init"], dir)

        let docs: [String]
        do { docs = try writeDocs(run, into: dir) } catch { return .failure("Could not write the team's docs") }

        if let failure = await coder.run(prompt: TeamBuildPrompt.prompt(for: run, docs: docs), dir: dir.path,
                                         allowedTools: TeamBuildPrompt.allowedTools, maxTurns: Self.maxTurns,
                                         timeout: Self.buildTimeout, onEvent: onLog) {
            return .failure(failure)
        }

        let mdURL = dir.appendingPathComponent("CLAUDE.md")
        let existing = (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
        if !TeamBuildPrompt.isComplete(existing) {
            try? TeamBuildPrompt.fallbackClaudeMd(for: run, docs: docs).write(to: mdURL, atomically: true, encoding: .utf8)
        }
        _ = git(["add", "-A"], dir)
        _ = git(["commit", "-m", "Initial project from Codepet Team Build"], dir)   // failure is not fatal
        return .success(path: dir.path)
    }

    private func writeDocs(_ run: TeamRun, into dir: URL) throws -> [String] {
        let docsDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        var names = ["docs/00-decision.md"]
        try decisionMarkdown(run).write(to: docsDir.appendingPathComponent("00-decision.md"), atomically: true, encoding: .utf8)
        var n = 0
        for step in run.plan.departmentSteps {
            guard let draft = run.state(step.id)?.draft else { continue }
            n += 1
            let file = String(format: "%02d-%@-%@.md", n, step.dept, TeamSlug.make(step.title))
            let name = DepartmentCatalog.find(step.dept)?.name ?? step.dept
            try DeliverableMarkdown.render(draft, dept: name, instruction: step.instruction)
                .write(to: docsDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
            names.append("docs/\(file)")
        }
        return names
    }

    private func decisionMarkdown(_ run: TeamRun) -> String {
        guard let b = run.brief else {
            return "# Decision\n\n**Request:** \(run.request)\n\n\(run.plan.summary)\n"
        }
        return """
        # Decision

        **Request:** \(run.request)

        ## Recommendation
        \(b.recommendation)

        **Confidence:** \(b.confidence) — \(b.confidenceReason)

        ## The trade-off you own
        \(b.tradeoffFounderMustOwn)

        ## Kill criteria
        \(b.killCriteria.map { "- \($0)" }.joined(separator: "\n"))

        ## What we don't know
        \(b.whatWeDontKnow)
        """
    }

    static func runGit(_ args: [String], _ dir: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = LoginShellRunner.spawnEnvironment()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}

/// Same rules as the op's `teamSlug`, for file names derived from step titles.
enum TeamSlug {
    static func make(_ s: String) -> String {
        let ascii = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
        let kebab = ascii.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let capped = String(kebab.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return capped.isEmpty ? "project" : capped
    }
}
```
The test expects `01-mkt-message.md` for title "Message". That matches `TeamSlug.make("Message") == "message"`.

- [ ] **Step 5: Run** `-only-testing:codepetTests/ProjectAssemblerTests` → PASS.
- [ ] **Step 6: Commit** — "Add ProjectAssembler: docs/, Claude Code with file-only tools, guaranteed CLAUDE.md".

---

### Task 9: Wire Team Build into `CompanyStore`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
  - `init` (:343-422): add injected `teamPlanner` and `teamRunsSaver`, plus an `assemblerFactory`.
  - `startVirtualCompanyRun` (:2085-2143): add the end-of-room hook.
  - `hydrate` (:498): restore an active run.
  - `fileApproval` (:2943): no signature change.
- Modify: `codepet/Models/Deliverable.swift` (:292 — add `projectPath: String?`, `decodeIfPresent`, CodingKeys, a defaulted init parameter)
- Modify: `codepet/Models/CopilotMessage.swift` (add `var teamRunId: String? = nil` + init parameter)
- Test: `codepetTests/TeamBuildStoreTests.swift`; extend `codepetTests/ApprovalParityTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces (public on `CompanyStore`):
  ```swift
  @Published private(set) var teamRun: TeamRunCoordinator?      // the active run's coordinator
  var teamBuildAvailable: Bool                                   // grant + not prototype + no active run
  func startTeamBuild(_ ask: String, language: AppLanguage) async
  func confirmTeamPlan() async      // [Go]
  func cancelTeamPlan()             // [Cancel]
  func retryTeamStep(_ stepId: String) async
  func stopTeamRun()
  func continueTeamRun() async
  func approveTeamRun() async
  ```
  New init parameters (all defaulted):
  ```swift
  teamPlanner: @escaping (TeamPlanRequest) async -> WorkPlan? = { await TeamPlanClient.plan($0) },
  teamRunsSaver: @escaping (String, [TeamRun]) async -> Bool = CompanyData.saveTeamRuns,
  assemblerFactory: @escaping () -> ProjectAssembler = { ProjectAssembler(coder: CLIProjectRunner()) },
  ```

- [ ] **Step 1: Failing store tests.** Build the store the way `CompanyStoreVirtualCompanyTests.roomWithABrief` does, using a `vcRunner` that yields `.runStarted`, `.routing(multi_agent)`, a 60 ms gap, `.brief`, `.done` (copy its `routing(_:)` helper verbatim). Inject:
  - `claudeAuthorisation: ProviderAuthorisation(isAuthorised: { _, _ in true }, setAuthorised: { _, _, _ in })`
  - `teamPlanner` returning a fixed plan
  - `taskRunner` returning `RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# \(req.taskTitle)")`
  - `teamRunsSaver`, `librarySaver`, `tasksSaver`, `firstApprovalSaver`, `saver` all `{ _, _ in true }`
  - `decisionExtractor: { _, _ in [] }`
  - `assemblerFactory` returning a `ProjectAssembler` with a temp `root`, a fake `ProjectCodeRunning` and `git: { _, _ in true }`

```swift
// codepetTests/TeamBuildStoreTests.swift  (sketch of the required cases — write each fully)
@MainActor
final class TeamBuildStoreTests: XCTestCase {
    // helpers: routing(_:), aBrief(_:), store(vcRunner:planner:runner:grant:), waitFor(_:timeout:)
    func testTeamBuildConvenesThePlansAndShowsAPlanCard() async throws {
        // startTeamBuild("pants page") → room with brief → teamPlanner called with brief != nil
        // → store.teamRun?.run?.phase == .planned, and a chat message with teamRunId == run.id exists.
    }
    func testSingleAgentPlansFromTheRequestAlone() async throws {
        // vcRunner yields routing("single_agent") and finishes → planner called with brief == nil.
    }
    func testNeedsClarificationDoesNotPlan() async throws {
        // routing("needs_clarification") → planner never called, teamRun == nil.
    }
    func testGoRunsTheStepsAndReachesReady() async throws {
        // confirmTeamPlan() → runner called once per department step with deptKey == step.dept
        // → phase .ready, projectPath under the temp root.
    }
    func testWithoutAGrantNothingRunsAndTheReasonIsShown() async {
        // grant false → startTeamBuild appends the BlockedOffer .notGranted text; vcRunner and planner never called.
    }
    func testASecondTeamBuildIsRefusedWhileOneIsActive() async throws { }
    func testAccountSwitchDropsLateResults() async throws {
        // start a run whose runner sleeps 200ms; hydrate(companyId: "other") mid-run;
        // assert teamRunsSaver never received "other" with the first run's id, and teamRun is nil after hydrate.
    }
    func testHydrateRestoresAnActiveRunAsInterrupted() async {
        // loader returns a CompanyState whose teamRuns contains a .running run with a .running step
        // → after hydrate, teamRun?.run?.state(step)?.status == .interrupted
    }
}
```
Write every case in full, following the patterns in `CompanyStoreVirtualCompanyTests` (`awaitRoom`, expectations via `$chatMessages` or `$teamRun` sinks, 5 s timeouts). Each must fail before Step 3.

Add to `ApprovalParityTests`:
```swift
func testApprovingATeamRunFilesTheProjectAndEveryDepartmentDraft() async throws {
    // Drive a store to a .ready TeamRun with two department drafts and projectPath "/tmp/x".
    // await s.approveTeamRun()
    // library contains 3 entries: 2 drafts + 1 with projectPath == "/tmp/x"
    // firstApprovalAt != nil; teamRun?.run?.phase == .filed
}
```

- [ ] **Step 2: Run** both suites → FAIL.

- [ ] **Step 3: Implement.** Key pieces:

```swift
// Stored state
@Published private(set) var teamRun: TeamRunCoordinator?
private var teamRunBag: AnyCancellable?
private var pendingTeamBuild: (ask: String, language: AppLanguage, cid: String)?
private let teamPlanner: (TeamPlanRequest) async -> WorkPlan?
private let teamRunsSaver: (String, [TeamRun]) async -> Bool
private let assemblerFactory: () -> ProjectAssembler

var teamBuildAvailable: Bool {
    guard let companyId, !PrototypeMode.isOn else { return false }
    return claudeAuthorisation.isAuthorised(.claudeCode, companyId) && !(teamRun?.run?.isActive ?? false)
}

func startTeamBuild(_ ask: String, language: AppLanguage) async {
    let text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let cid = companyId else { return }
    guard claudeAuthorisation.isAuthorised(.claudeCode, cid) else {
        let why = BlockedOffer.resolve(reason: .notGranted, installed: installedProviders.installed, surface: .claudeOnly)
            .founderText(lang: language)
        chatMessages.append(CopilotMessage(role: .companion, text: why))
        return
    }
    guard !(teamRun?.run?.isActive ?? false) else { return }
    pendingTeamBuild = (text, language, cid)
    await sendChat(text, language: language, convenesRoom: true)
}
```

In `startVirtualCompanyRun`'s task, after the `if state.handsOffToRoom … sealed` block and before `self?.vcTasks[roomMessageId] = nil`, add:
```swift
await self?.teamBuildRoomEnded(state)
```
Then:
```swift
private func teamBuildRoomEnded(_ state: VirtualCompanyRunState) async {
    guard let pending = pendingTeamBuild, pending.cid == companyId else { return }
    pendingTeamBuild = nil
    let outcome = TeamBuildRoomOutcome.from(phase: state.phase, routingDecision: state.routing?.decision, brief: state.brief)
    let brief: VCBrief?
    switch outcome {
    case .brief(let b): brief = b
    case .requestOnly: brief = nil
    case .clarify: return                                   // the room's own question is already on screen
    case .failed:
        chatMessages.append(CopilotMessage(role: .companion, text: pending.language == .vi
            ? "Cả đội chưa họp xong được. Bấm Cả đội làm để thử lại."
            : "The team couldn't finish meeting. Tap Team build to try again."))
        return
    }
    let roster = company.departments.map(\.key)     // verify DeptRef's key property name
    let req = TeamPlanRequest(language: pending.language.rawValue, request: pending.ask, brief: brief,
                              company: ["projectName": company.brief.projectName ?? "",
                                        "oneLiner": company.brief.oneLiner ?? "",
                                        "audience": company.brief.audience ?? ""],
                              roster: roster.isEmpty ? Array(WorkPlanValidation.routable) : roster)
    guard let raw = await teamPlanner(req), companyId == pending.cid,
          let plan = WorkPlanValidation.validate(raw, roster: Set(req.roster)) else {
        if companyId == pending.cid {
            chatMessages.append(CopilotMessage(role: .companion, text: pending.language == .vi
                ? "Chưa lập được kế hoạch. Bấm Cả đội làm để thử lại."
                : "I couldn't put a plan together. Tap Team build to try again."))
        }
        return
    }
    let run = TeamRun(request: pending.ask, createdAt: Date(), brief: brief, plan: plan)
    installCoordinator(for: run, cid: pending.cid, language: pending.language)
    chatMessages.append(CopilotMessage(role: .companion, text: "", teamRunId: run.id))
}

private func installCoordinator(for run: TeamRun, cid: String, language: AppLanguage) {
    let c = TeamRunCoordinator(
        runStep: { [weak self] step, upstream in
            guard let self, self.companyId == cid else { return .failure("Account changed") }
            let task = step.asRoadmapTask()
            let req = self.runRequest(for: task, language: language, extraUpstream: upstream)
            let result = await self.taskRunner(req)
            guard self.companyId == cid else { return .failure("Account changed") }
            guard let d = self.buildDeliverable(from: result, task: task, producedBy: self.currentProvider(for: cid)) else {
                return .failure(language == .vi ? "Không có kết quả — lượt chạy lỗi hoặc hết thời gian"
                                                : "No result — the run failed or timed out")
            }
            return .success(d)
        },
        assemble: { [assemblerFactory] run, onLog in await assemblerFactory().assemble(run, onLog: onLog) },
        save: { [weak self] snapshot in
            guard let self, self.companyId == cid else { return }
            var runs = self.company.teamRuns.filter { $0.id != snapshot.id }
            runs.append(snapshot)
            self.company.teamRuns = runs
            _ = await self.teamRunsSaver(cid, runs)
        })
    c.load(run)
    teamRunBag = c.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    teamRun = c
}

func confirmTeamPlan() async { await teamRun?.start() }
func cancelTeamPlan() { teamRun?.stop() }
func retryTeamStep(_ id: String) async { await teamRun?.retry(stepId: id) }
func stopTeamRun() { teamRun?.stop() }
func continueTeamRun() async { await teamRun?.continueInterrupted() }

func approveTeamRun() async {
    guard let c = teamRun, let run = c.run, run.phase == .ready, let path = run.projectPath else { return }
    for step in run.plan.departmentSteps {
        if let d = run.state(step.id)?.draft { await fileApproval(d, taskId: nil) }
    }
    let summary = (try? String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8))
        .flatMap { md in md.components(separatedBy: "## What this is").dropFirst().first?
            .components(separatedBy: "\n## ").first?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? run.plan.summary
    let project = Deliverable(kind: .other, title: run.plan.title, body: summary, createdAt: ISOTime.utc(Date()),
                              sourceTaskId: nil, payload: nil, producedBy: nil, projectPath: path)
    await fileApproval(project, taskId: nil)
    c.markFiled()
}
```
In `hydrate`, after `company` is loaded for the new id, drop the old coordinator (`teamRun?.stop()` is wrong here because it would save a cancelled state to the NEW account; instead set `teamRun = nil; teamRunBag = nil; pendingTeamBuild = nil`). Then, if `company.teamRuns.last(where: \.isActive)` exists, `installCoordinator(for:cid:language: .en)` (the step runner re-reads language on continue; use `.en` unless AppState's language is reachable here — check how other hydrate code gets language and follow it).

Account-switch safety: `installCoordinator`'s closures capture `cid` and compare it with `self.companyId`, and `save` refuses on mismatch. That pair is what `testAccountSwitchDropsLateResults` pins.

`Deliverable.projectPath`: add `var projectPath: String? = nil`, add it to CodingKeys, decode it with `decodeIfPresent`, and add a trailing defaulted init parameter `projectPath: String? = nil`. Synthesized or explicit `encode` must write it. Run `-only-testing:codepetTests/DeliverableTests` if present.

- [ ] **Step 4: Run** `TeamBuildStoreTests`, `ApprovalParityTests`, `CompanyStoreVirtualCompanyTests`, `UpstreamCreditTests` → PASS (the last two prove the room and chain paths are unchanged).
- [ ] **Step 5: Commit** — "Wire Team Build into CompanyStore: room → plan → run → approve".

---

### Task 10: UI — composer button, cards, detail panel, Library

**Files:**
- Create: `codepet/Views/Copilot/TeamBuildCards.swift`
- Modify:
  - `codepet/Views/Copilot/ChatComposer.swift`: add `var onTeamBuild: () -> Void = {}` and `var teamBuildEnabled: Bool = false` after `onConveneRoom` (:84); add the button beside `sendButton` at :188 and :249.
  - `codepet/Views/Copilot/CopilotChatView.swift`: add a `teamBuild()` action next to `conveneRoom()` (:809); pass it at the call site (:521-554); add a render branch after the `vcRun` branch in `CopilotBubble.content` (:1526).
  - `codepet/Views/Library/LibraryView.swift`: add [Open in Finder] for a deliverable with `projectPath`.
- Test: `codepetTests/TeamBuildButtonTests.swift`

**Interfaces:**
- Consumes: `CompanyStore.teamRun`, `teamBuildAvailable`, and the Task 9 actions; `MessageCard(hue:)`, `ExecLogRow`, `DraftPayloadPreview(deliverable:onOpen:)`, `DepartmentCatalog.find`, `DepartmentCompanions.companionId(for:)`, `PetCharacter.all`.
- Produces:
  ```swift
  enum TeamBuildButton { static func isEnabled(draft: String, busy: Bool, available: Bool) -> Bool
                         static func label(_ lang: AppLanguage) -> String
                         static func help(_ lang: AppLanguage) -> String }
  enum TeamBuildCopy { static func status(_ s: TeamStepStatus, elapsed: TimeInterval?, lang: AppLanguage) -> String
                       static func waitsFor(_ names: [String], lang: AppLanguage) -> String }
  struct TeamRunCard: View      // plan / running / failed / ready / filed, by phase
  struct TeamStepDetail: View   // the detail panel content
  ```

- [ ] **Step 1: Failing test**

```swift
// codepetTests/TeamBuildButtonTests.swift
import XCTest
@testable import codepet

final class TeamBuildButtonTests: XCTestCase {
    func testEnabledOnlyWithADraftWhenIdleAndAvailable() {
        XCTAssertTrue(TeamBuildButton.isEnabled(draft: "pants page", busy: false, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "  ", busy: false, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "pants", busy: true, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "pants", busy: false, available: false))
    }
    func testHelpSaysItRunsOnTheFoundersPlan() {
        XCTAssertTrue(TeamBuildButton.help(.en).localizedCaseInsensitiveContains("Claude plan"))
        XCTAssertTrue(TeamBuildButton.help(.vi).localizedCaseInsensitiveContains("gói Claude"))
    }
    func testStatusCopyIsHonest() {
        XCTAssertEqual(TeamBuildCopy.status(.running, elapsed: 42, lang: .en), "0:42")
        XCTAssertEqual(TeamBuildCopy.status(.failed("Timed out"), elapsed: nil, lang: .en), "Failed")
        XCTAssertEqual(TeamBuildCopy.status(.blocked, elapsed: nil, lang: .vi), "Bị chặn")
        XCTAssertEqual(TeamBuildCopy.waitsFor(["Marketing", "Design"], lang: .en), "waits for Marketing, Design")
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement `TeamBuildCards.swift`.** Required content:
  - **`TeamBuildButton` / `TeamBuildCopy`:** the pure helpers above. Labels:
    - EN "Team build" / VI "Cả đội làm".
    - Help EN "The whole team plans and builds this into a real project. Runs on your Claude plan." / VI "Cả đội lập kế hoạch và làm thành một project thật. Chạy trên gói Claude của bạn."
    - Statuses EN Waiting/Done/Failed/Blocked/Cancelled/Interrupted; VI Chờ/Xong/Lỗi/Bị chặn/Đã dừng/Bị gián đoạn. Running shows `m:ss`.
  - **`TeamRunCard(coordinator:onSelect:)`:** a `MessageCard(hue: CodepetTheme.accentPurple)`. It shows:
    - a header: title + `n/N` done;
    - `run.plan.summary` in muted text;
    - one row per plan step: pet avatar (from `DepartmentCompanions.companionId(for: step.dept)` → `PetCharacter.all[id]`, drawn with `.interpolation(.none)` like other avatars), department name, step title, and a status pill; under a dependent step, a muted "waits for …" line;
    - a footer that depends on `run.phase`:
      - `.planned`: "N steps · runs on your Claude plan" + [Go] → `companyStore.confirmTeamPlan()` and [Cancel] → `cancelTeamPlan()`
      - `.running`/`.assembling`: [Stop]
      - `.failed`: [Retry <dept>] for each failed step, plus [Stop]
      - any interrupted step: [Continue]
      - `.ready`: the file list (department `docs/` names and the top-level files of `projectPath`, read with `FileManager.contentsOfDirectory`), then [Approve], [Open in Finder] (`NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])`), [Open with Claude Code] (`NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())`) and [View in browser] only if `path/index.html` exists (`NSWorkspace.shared.open(indexURL)`), plus the "Not saved yet — approving files it in your Library." note (reuse `DraftCardCopy`'s wording if it exposes it);
      - `.filed`: "Added to Library".
    - Rows are buttons calling `onSelect(step.id)`. A `TimelineView(.periodic(from: .now, by: 1))` drives the running timers.
  - **`TeamStepDetail(step:state:run:buildLog:)`:**
    - department + status;
    - "Asked for:" instruction;
    - "Receives from:" with each dependency's department name and the first 160 characters of its draft body in a quote block;
    - for a done step, `DraftPayloadPreview(deliverable: draft) {}`;
    - for the build step while assembling, `ExecLogRow(taskTitle: run.plan.title, deptName: "Engineering", steps: buildLog.map { ExecStep(label: $0, done: true) }, companionId: DepartmentCompanions.companionId(for: "eng"))`.

  **Wiring in `CopilotChatView`:**
  - `@State private var teamDetailStepId: String?`.
  - The branch in `CopilotBubble.content` right after the `vcRun` branch: `else if message.teamRunId != nil, let c = companyStore.teamRun, c.run?.id == message.teamRunId { TeamRunCard(coordinator: c, onSelect: { teamDetailStepId = $0 }) }`. `CopilotBubble` may need `companyStore` via `@EnvironmentObject` and a binding for the selection; follow how the `vcRun` branch receives its callbacks.
  - Detail presentation:
    - **pane** (`surface == .twoMode`): an `HStack` placing `TeamStepDetail` in a 320pt trailing column when `teamDetailStepId != nil`, with a close button;
    - **dock**: `.sheet(item:)` over a `String` identifiable wrapper.
  - `teamBuild()`:
    ```swift
    private func teamBuild() {
        let ask = companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TeamBuildButton.isEnabled(draft: ask, busy: isChatBusy, available: companyStore.teamBuildAvailable) else { return }
        showHistory = false
        companyStore.chatDraft = ""
        Task { await companyStore.startTeamBuild(ask, language: lang) }
    }
    ```
    Pass `onTeamBuild: teamBuild, teamBuildEnabled: TeamBuildButton.isEnabled(draft: companyStore.chatDraft, busy: isChatBusy, available: companyStore.teamBuildAvailable)`.
  - **Composer button:** `Button(action: onTeamBuild) { Label(TeamBuildButton.label(lang), systemImage: "person.3.fill") }` in the same style as the neighbouring controls, `.disabled(!teamBuildEnabled)` and `.help(TeamBuildButton.help(lang))`. Hide it (do not merely disable it) when `PrototypeMode.isOn`.
  - **LibraryView:** where a deliverable's detail is shown (`LibraryView.swift:483` area), if `deliverable.projectPath != nil` add [Open in Finder] using the same `NSWorkspace` call.

- [ ] **Step 4: Run** `TeamBuildButtonTests` → PASS. Build the app:
  `xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug -derivedDataPath build/DerivedData -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"` → `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** — "Show Team Build in chat: button, live team card, detail panel, handoff".

---

### Task 11: End-to-end on the real Claude plan + docs

**Files:**
- Modify: `CLAUDE.md` — add a short "Team Build" subsection under "The Virtual Company" with the pointers: spec path, `planTeamWork` in `ONE_SHOT_OPS`, `TeamRunCoordinator`, `ProjectAssembler`, the file-only tool list, the `~/Codepet Projects` root. Add a landmine-style note: "the build prompt is Swift on purpose".

- [ ] **Step 1:** `./scripts/build-sidecar.sh` then build Debug (command in Task 10 Step 4). Quit any running Codepet (`osascript -e 'quit app id "app.murror.codepet"'`), then `open build/DerivedData/Build/Products/Debug/codepet.app`.
- [ ] **Step 2 (by hand, signed in, plan granted, prototype mode OFF):** type "Build me a landing page selling stretch office trousers", press Team build. Check each of these:
  - [ ] the room convenes and its cards render;
  - [ ] the plan card appears with 2–6 department rows plus Engineering;
  - [ ] [Go] makes the rows move Waiting → timer → Done, with at most 3 running at once;
  - [ ] clicking a row opens the detail panel showing "Receives from" quotes;
  - [ ] the Engineering panel shows real file lines while building;
  - [ ] `ls ~/Codepet\ Projects/<slug>/` shows `CLAUDE.md`, `docs/`, `index.html`;
  - [ ] `git -C ~/Codepet\ Projects/<slug> log --oneline` shows 1 commit;
  - [ ] `grep -c '^## ' CLAUDE.md` is ≥ 5 and contains the 5 required headings;
  - [ ] [View in browser] opens the page;
  - [ ] [Approve] shows the project and the department drafts in the Library, and [Open in Finder] there works.
- [ ] **Step 3:** Record the wall-clock time and the number of CLI calls in the PR description (spec: "measure after v1 ships"). Do not invent numbers.
- [ ] **Step 4:** Run every suite this plan touched, one by one, and list the results in the PR.
- [ ] **Step 5: Commit** the CLAUDE.md change — "Document Team Build in CLAUDE.md". Push and open a PR only if the user asks.

---

## Self-review notes (done while writing)

- **Spec coverage:**
  - §0 entry → Task 9 (grant, one run) + Task 10 (button, prototype hidden)
  - §1 room outcomes → Task 4 (`TeamBuildRoomOutcome`) + Task 9 (hook)
  - §2 plan → Tasks 1, 2, 4 (client re-validation), 5
  - §3 TeamRun → Tasks 4, 6; timeouts → Task 3 (180 s) + Task 8 (900 s)
  - §4 assembly → Tasks 7, 8
  - §5 handoff/approval → Task 9 (`approveTeamRun`, `projectPath`) + Task 10 (buttons, Library)
  - §6 UI → Task 10
  - Testing → each task, plus Task 11 end-to-end
  - Out of scope → nothing added for it
- **Types used consistently:** `TeamStepResult`, `TeamAssemblyResult`, `WorkPlan.buildStepId`, `TeamRun.isActive`, `ProjectCodeRunning.run(...) -> String?`, `TeamPlanRequest`, `teamRunsSaver`.
- **Known soft spot:** Task 7's site test is specified by instruction, not code, because the `DeliverablePayload` initialiser is not quoted here. The task says the implementer must write real construction code; a reviewer should reject a test with no asserts.
