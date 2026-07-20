# Phase 3A — Roadmap Data + Engine + Generation — Design Spec

**Date:** 2026-07-20
**Phase:** 3A of the native=web-product rebuild (Overview = the roadmap board; 3A = data/engine/generation, 3B = the board view). Anchor: `2026-07-20-native-web-product-architecture.md`. Phases 1–2 shipped the shell + `CompanyStore`/`CompanyData` + onboarding.
**Goal:** Give the app a native roadmap **data model, a pure engine (status / next-step / progress), and fail-open generation**, per company — the data the Overview board (3B) renders.

---

## Context

Inspecting the live app confirmed the **Overview *is* the roadmap board**: stage/phase columns **Find → Foundation → Build → Ship → Launch**, task cards color-coded by a derived status (Done / Codepet-can-do / Needs-your-input / Needs-approval / Needs-earlier-steps), connected by dependency lines, with a **next-step beacon** and a **progress** card. (The `OverviewView.tsx` 3D constellation in the source is a dead/old variant.) The web models tasks with `who: 'does' | 'draft' | 'you'` and derives status from `who` + `done` + `drafted` + dependency-readiness.

This phase ports a **simplified-but-faithful** native model: a self-contained phase/dependency task graph with derived status — producing the same board — rather than cloning the web's authored node-graph + join-key machinery (approved; can be deepened later). No UI this phase.

## Scope

**In scope:** `RoadmapPhase`, `TaskWho`, `RoadmapTask`, `TaskStatus`; a pure `RoadmapEngine` (status / next-step / progress / group-by-phase); `CompanyState.tasks` + persistence; fail-open generation on `CompanyStore` (injectable fetcher).

**Out of scope (later):** the board UI (3B); the `scaffoldRoadmap` function's output alignment + node-22 deploy (generation fail-opens until then); task approval/deliverable flows (later phases); the "Second Brain" toggle.

## Components

### 1. `RoadmapPhase` (enum, new)
`enum RoadmapPhase: String, Codable, CaseIterable, Identifiable { case find, foundation, build, ship, launch }` with `var order: Int` (find 0 … launch 4) and `func label(_ lang: AppLanguage) -> String` (VI/EN). The board's columns, in order.

### 2. `TaskWho` (enum, new)
`enum TaskWho: String, Codable, Hashable { case does, draft, you }` — mirrors the web `Who` (companion does it / companion drafts it / the founder must).

### 3. `RoadmapTask` (model, new)
`struct RoadmapTask: Codable, Hashable, Identifiable` — `id: String`, `title: String`, `detail: String`, `phase: RoadmapPhase`, `who: TaskWho`, `dependsOn: [String]` (task ids), `done: Bool`, `drafted: Bool` (companion produced a draft awaiting approval). Memberwise init defaulting `dependsOn: []`, `done: false`, `drafted: false`.

### 4. `TaskStatus` (derived, new)
`enum TaskStatus { case done, needsApproval, blocked, needsYou, codepetCanDo }` — the legend. Derived by the engine (not stored).

### 5. `RoadmapEngine` (pure, new)
- `static func status(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskStatus` — precedence: `done` → `needsApproval` (`drafted && !done`) → `blocked` (any `dependsOn` id maps to a not-done task) → `needsYou` (`who == .you`) → `codepetCanDo` (`who == .does || .draft`).
- `static func nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask?` — the beacon: the first not-done task whose dependencies are all done, in `RoadmapPhase.order` then array order; `nil` when none.
- `static func progressPercent(_ tasks: [RoadmapTask]) -> Int` — `round(done / total * 100)`, `0` when empty.
- `static func tasksByPhase(_ tasks: [RoadmapTask]) -> [RoadmapPhase: [RoadmapTask]]` — grouped for the columns.

### 6. `CompanyState.tasks` + persistence
- Add `var tasks: [RoadmapTask]` to `CompanyState` (`.empty` → `[]`) and `var tasks: [RoadmapTask]?` to `CompanyDoc` (`RoadmapTask` is `Codable` with only JSON-safe fields — strings/bools/arrays — so it decodes via the existing `JSONSerialization` load path). `CompanyData.state(from:)` maps `doc.tasks ?? []`.
- `CompanyData.saveTasks(companyId:tasks:) async -> Bool` — writes `companies/{uid}` `{ tasks: <array of dicts> }`, merge, fail-soft (mirrors `saveBrief`'s encode approach via `JSONEncoder → JSONSerialization`).

### 7. Generation (`CompanyStore`)
- Injectable `roadmapFetcher: (CompanyBrief) async -> [RoadmapTask]` (init default: a real fetcher that calls the `scaffoldRoadmap` Cloud Function and fail-opens to `[]`; the function's phase/dependency output alignment + node-22 deploy are the follow-through).
- `func generateRoadmap() async` — `tasks = await roadmapFetcher(company.brief)`; if non-empty, persist via `saveTasks(companyId:)` and set `company.tasks`. Fail-open (empty result → no change). Guarded by the generation token like `finishOnboarding` (an account switch mid-fetch discards).
- `func setTaskDone(id:done:)` / `toggleTaskDone(id:)` — local mutate + persist (for the board's done toggles in 3B); fail-soft.

## Data flow
`generateRoadmap` → `roadmapFetcher(brief)` (fail-open) → `[RoadmapTask]` → persist + `company.tasks`. `RoadmapEngine` derives per-task `status`, the `nextStep` beacon, `progressPercent`, and `tasksByPhase` — all pure, consumed by the 3B board.

## Error handling
Generation **fail-open** (empty on failure/undeployed — the board just shows no tasks). Persistence **fail-soft**. Generation/toggle respect the `hydrationToken` guard so an account switch mid-write can't cross-contaminate.

## Testing
- `RoadmapEngine`: status precedence matrix (done > needsApproval > blocked > needsYou > codepetCanDo); `nextStep` picks the first dep-satisfied not-done task by phase order and returns nil when none/all-blocked; `progressPercent`; `tasksByPhase` grouping.
- `RoadmapTask`/`CompanyState.tasks`: Codable round-trip; `state(from:)` maps `tasks`.
- `CompanyData.saveTasks`: payload shape (array of task dicts).
- `CompanyStore.generateRoadmap`: stub fetcher → tasks persisted + set; empty fetcher → no change (fail-open); token-guard discards a superseded fetch. `toggleTaskDone` flips + persists.

## Reuse / references
| Web source | Native target |
|---|---|
| live Overview board (phases/status/beacon/progress) | `RoadmapPhase` + `TaskStatus` + `RoadmapEngine` |
| `lib/data.ts` `Task`/`Who` (`does`/`draft`/`you`) | `RoadmapTask` / `TaskWho` |
| deployed-later `scaffoldRoadmap` fn | `roadmapFetcher` (fail-open) |
| `CompanyData`/`CompanyStore` (P1/P2) | extended with tasks + generation |

## Open decisions
None — resolved in brainstorming (simplified faithful model; fail-open generation; data before board). Ready for implementation planning.
