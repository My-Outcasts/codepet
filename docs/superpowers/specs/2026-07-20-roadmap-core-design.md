# Roadmap (core) — Design Spec

**Date:** 2026-07-20
**Sub-project:** 3 of 8 in the web→native port (order: brief ✅ → companion ✅(already native) → **roadmap** → chat → deliverables → toolkit → memory → billing).
**Goal:** Give the native macOS Codepet app an AI-generated, stage-appropriate **build roadmap** — bespoke tasks per department plus a single **next-step** — layered onto the app's existing Project Health (departments × stage) model.

---

## Context

- **Web app** has a generative **roadmap**: `scaffold` produces departments + tailored tasks for the founder's product/stage; a **next-step/beacon** names the one task to do next; per-task **deliverables** come from `run-task`. Forward-looking: *"what should you build next?"*
- **Native app** has **Project Health**: a *fixed, hand-authored rubric* (`ProjectHealthEngine.allRules`) of best-practice checks, auto-detected from the project's files/brief, gated by **stage** (`ProjectStage`: idea/building/launch/growth) and grouped by **department** (`ProjectDepartment`: engineering/business/marketing/growth), with AI **action plans** per check (`generatePlan`). Assessment-oriented: *"is your project healthy?"*

Native already has the departments, the stages, and per-item AI plans — it lacks the web's *generative, bespoke, forward* task list + next-step. This sub-project adds exactly that, **reusing native's department/stage model** rather than inventing a parallel one.

### Approved decisions (from brainstorming)
1. **Extend Project Health** — reuse native's `ProjectDepartment` + `ProjectStage`; add AI-generated bespoke **tasks** and a **next-step** on top of the existing rubric. Health checks and roadmap tasks **coexist** under the same departments as two labeled groups.
2. **Core first** — generate tasks + next-step + minimal surfacing. The overview **map/breadcrumb** visualizations are a later follow-on.
3. **Generation ports to a new Firebase Function** (`scaffoldRoadmap`) on `devpet-8f4b1`, per the locked backend decision.
4. Next-step is a **pure engine** (order/stage pick), not an LLM call — matching the web's post-audit pure `computeNextStep`.

## Scope

**In scope:**
- `RoadmapTask` + `RoadmapNextStep` Swift models, persisted per project.
- `scaffoldRoadmap` Cloud Function — generates bespoke tasks per department from the brief + stage.
- `RoadmapEngine.nextStep` — pure Swift next-step picker.
- `ReflectionAPIClient.scaffoldRoadmap(...)` client method (+ default-throw protocol entry).
- Minimal surfacing in the existing project folder/health view: a **Next step** beacon, a **"To build"** task group per department (done toggles), and a **Generate / Re-plan** action.

**Out of scope (later sub-projects / follow-on):**
- Producing a *deliverable* per task (that's `run-task` → sub-project 5).
- Chat reading the next-step (sub-project 4).
- Overview **map / breadcrumb / constellation** visualizations (roadmap follow-on).
- Locked "produces" copy, task pending/run states, paywall gating.

**Explicit non-goals:** do not modify the existing health rubric or `generatePlan`; do not merge failing checks into the task list (checks and tasks stay as two labeled groups); do not touch `CLAUDE.md`.

## Repositories
- Swift app: worktree `~/Documents/codepet-roadmap-wt` (`My-Outcasts/codepet`), branch `feat/roadmap` off `origin/main`.
- Function: `Murror/CodePet-Clean` functions on `feat/project-health-reflection-sync` (the authoritative functions branch, deploys to `devpet-8f4b1`) — same home as `enrichBrief`.

---

## Architecture

```
[project folder/health view]
   │  "Generate / Re-plan for my stage"
   ▼
ReflectionAPIClient.scaffoldRoadmap(brief, stage, departments)
   ▼
[scaffoldRoadmap Cloud Function]  → tasks per department (bespoke, stage-appropriate)
   ▼  (fail-open: on error, no tasks; health rubric untouched)
ProjectStore.setRoadmapTasks(projectPath, [RoadmapTask])   → persist (UserDefaults + cloud, like briefs)
   ▼
RoadmapEngine.nextStep(tasks, stage) → RoadmapNextStep?     (pure, no network)
   ▼
view renders: Next-step beacon + per-department "To build" list (done toggles) alongside "Checks"
```

## Components

### 1. Models (Swift, new)
- `RoadmapTask`: `id: String` (stable), `deptKey: ProjectDepartment`, `title: String`, `detail: String`, `who: TaskWho` (`draft` | `does` | `needsYou` — mirrors the web `Who`: the AI drafts it, the AI does it, or the founder must), `kind: String`, `done: Bool`. `Codable, Hashable`.
- `RoadmapNextStep`: `deptKey: ProjectDepartment`, `taskTitle: String`, `why: String`. (Mirrors web `NextStep {deptK, taskTitle, why}`.)

### 2. Persistence (extend `ProjectStore`)
- Store `roadmapTasks: [String: [RoadmapTask]]` keyed by `projectPath` (mirrors the brief-markers pattern; `cp_roadmap_tasks` UserDefaults key). `setRoadmapTasks(projectId:tasks:)`, `roadmapTasks(for:) -> [RoadmapTask]`, `toggleRoadmapTask(projectId:taskId:)`. Persist + cloud-sync like other project data.

### 3. `scaffoldRoadmap` Cloud Function (new, functions repo)
Port of the web `scaffold` generation, adapted to native's fixed departments. Input `{ brief: CompanyBrief, stage: string, departments: [{ key, name, expertise }] }` → output `{ departments: [{ key, tasks: [{ title, detail, who, kind }] }] }`. Generates **tasks, not departments** (native supplies the 4). Uses per-department **expertise/foundations** in the prompt (port the web `DEPARTMENT_FOUNDATIONS`, or author native equivalents for engineering/business/marketing/growth — mandate/skills/stageFocus/antipatterns). Tool-based structured output (matches `enrichBrief`/`summarizeTurn` pattern), Bearer auth, rate-limited. **Fail-open**: HTTP 200 with empty task list on model error.

### 4. `ReflectionAPIClient.scaffoldRoadmap(...)` (client, new)
`func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask]`. New endpoint constant, DTOs, and a **default-throw** protocol entry so existing mocks compile (same pattern as `enrichBrief`).

### 5. `RoadmapEngine.nextStep` (pure Swift, new)
`static func nextStep(_ tasks: [RoadmapTask], stage: ProjectStage) -> RoadmapNextStep?` — pick the highest-priority **not-done** task by department order (`ProjectDepartment.order`) then task order, biased to the current stage; return `nil` when nothing is open. `why` is a short templated reason (department + stage). No network, no LLM. Mirrors the web's pure `computeNextStep`/`openTaskCatalog`.

### 6. Surfacing (core, minimal)
In the existing project folder/health view (where health checks render today), add:
- A **Next step** beacon at the top (the `RoadmapNextStep`, or hidden when nil).
- A **"To build"** task group per department under the existing "Checks" group — each task a row with a **done** toggle.
- A **"Generate roadmap / Re-plan for my stage"** button that calls `scaffoldRoadmap` and stores the result.
No new map/visualization in core.

## Data flow
1. User taps **Generate / Re-plan** → `scaffoldRoadmap(brief, stage, departments)`.
2. Function returns tasks per department (or empty on failure — fail-open).
3. `ProjectStore.setRoadmapTasks` persists them.
4. View renders the per-department "To build" lists + the `RoadmapEngine.nextStep` beacon.
5. Toggling a task done updates the store; the beacon recomputes purely.

## Error handling
- `scaffoldRoadmap` failure is **fail-open**: no tasks added, existing health rubric + any prior tasks untouched, quiet retry — never a dead end.
- `nextStep` returns `nil` when there are no open tasks (beacon hides).
- Persistence resilient (mirrors existing `ProjectStore` behavior).

## Testing
- `RoadmapEngineTests` (pure): correct next-step pick by department/task order + stage; `nil` when all done / empty; skips done tasks.
- `ProjectStoreRoadmapTests`: set/read/toggle tasks persist; toggling done flips `nextStep`.
- `ReflectionAPIClientScaffoldTests`: mocked URLProtocol returns tasks; error path throws; empty-on-fail-open.
- Cloud Function `scaffoldRoadmap` jest: output shape, per-department tailoring present, fail-open on model error, auth required.

## Verbatim-port references (web → native)
| Web source | Native/Function target |
|---|---|
| `lib/ai/nextStep.ts` (`NextStep`, `openTaskCatalog`, pure pick) | `RoadmapNextStep` + `RoadmapEngine.nextStep` |
| `lib/data.ts` `Task {t,d,who,kind}` / `Dept {k,need,tasks}` | `RoadmapTask` model |
| `lib/ai/scaffold.ts` + scaffold route | `scaffoldRoadmap` Cloud Function |
| `lib/ai/departments.ts` `DEPARTMENT_FOUNDATIONS` | per-dept expertise in the scaffold prompt |

## Open decisions
None — resolved in brainstorming. Ready for implementation planning.
