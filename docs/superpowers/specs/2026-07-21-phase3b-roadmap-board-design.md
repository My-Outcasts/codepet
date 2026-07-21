# Phase 3B — Overview Roadmap Board — Design Spec

**Date:** 2026-07-21
**Phase:** 3B of the native=web-product rebuild (Overview = the roadmap board; 3A shipped the data/engine/generation, 3B is the board UI). Anchor: `2026-07-20-native-web-product-architecture.md`. Consumes Phase 3A (`RoadmapPhase`/`TaskWho`/`RoadmapTask`/`TaskStatus`/`RoadmapEngine`/`CompanyStore.generateRoadmap`+`toggleTaskDone`).
**Goal:** Replace the placeholder Overview with a native SwiftUI board that renders the Phase-3A `RoadmapEngine` — five phase columns of status-colored task cards, a "DO THIS NEXT" beacon, and a Project Progress card — reading `CompanyStore.company.tasks`, styled in CodepetTheme, VI/EN.

---

## Context

The live Overview is a kanban-style roadmap board: five phase columns **Find → Foundation → Build → Ship → Launch**, task cards colored by derived status, a next-step beacon, and a progress readout. Phase 3A already models this (tasks in phases, `TaskStatus` legend, `RoadmapEngine` for status/nextStep/progress/grouping). This phase is the **view layer only** — all logic stays in the pure engine; the SwiftUI code just renders it and forwards a done-toggle.

## Approved decisions (brainstorming)

1. **Dependency lines: DEFERRED.** No drawn connectors this phase. Blocked cards convey the dependency via the `blocked` status ("Needs earlier steps") plus a small "after: …" hint. Lines are a later polish pass.
2. **Empty state: HONEST.** When `tasks.isEmpty`, show a friendly empty card. The view also quietly calls `generateRoadmap()` once on first appear (fail-open — today a no-op since the Cloud Function is undeployed; future-proofs auto-populate). No button, no error surfaced.
3. **Card tap: TOGGLE DONE.** A checkbox affordance on each card flips `done` via `CompanyStore.toggleTaskDone(id:)` (already built + persisted). Cards are otherwise read-only this phase (task detail/deliverables are later).
4. **Layout: HORIZONTAL COLUMNS.** Five side-by-side phase columns (headers always shown, even when empty); each column scrolls its cards vertically; the board scrolls horizontally when the window is narrow. Header (progress + beacon) sits full-width above the columns.

## Scope

**In scope:** `OverviewBoardView` (empty-state vs board), `RoadmapHeaderView` (progress + beacon), `PhaseColumnView`, `TaskCardView` (with done toggle); the one-line `AppShellView` router; small pure model helpers (`RoadmapEngine.orderedColumns`, `TaskStatus.label`, `TaskWho.label`); a status→CodepetTheme color map in the view.

**Out of scope (later):** drawn dependency lines; task-detail / deliverable open; re-plan/regenerate button (and its progress-preserving merge — see the 3A follow-up); horizontal scroll indicators/paging polish; any Copilot/Company/Tasks/Library/Environment/Settings view.

## Components

### 1. `AppShellView` router (1-line change)
The content slot (currently always `ShellPlaceholderView(view:)`) becomes:
```swift
if companyStore.view == .overview { OverviewBoardView() } else { ShellPlaceholderView(view: companyStore.view) }
```
`OverviewBoardView` reads `@EnvironmentObject var companyStore` + `@Environment(\.uiLanguage)`.

### 2. `OverviewBoardView` (`codepet/Views/Overview/OverviewBoardView.swift`)
- `tasks = companyStore.company.tasks`.
- If empty → `EmptyRoadmapView` (centered `CodepetCard`: title "Your roadmap will appear here" + one line "Once Codepet maps your next steps, they show up here." VI equivalents). `.task { if tasks.isEmpty { await companyStore.generateRoadmap() } }` — quiet, fail-open, runs once per appear.
- Else → a `VStack`: `RoadmapHeaderView(tasks:)` then a horizontal `ScrollView` of `PhaseColumnView` for each entry of `RoadmapEngine.orderedColumns(tasks)`.

### 3. `RoadmapHeaderView` (`.../RoadmapHeaderView.swift`)
- **Progress card** (`CodepetCard`): a bar (fraction = `progressPercent/100`, accentPurple fill on hairline track) + label "`{pct}% · {done} of {total} done`" (VI: "`{pct}% · {done}/{total} xong`"). `done`/`total` from `tasks`.
- **Beacon card**: if `RoadmapEngine.nextStep(tasks) != nil`, an accent-tinted `CodepetCard` — an eyebrow "★ DO THIS NEXT" (VI "★ LÀM ĐIỀU NÀY TIẾP") + the task title. Hidden when `nextStep == nil`.

### 4. `PhaseColumnView` (`.../PhaseColumnView.swift`)
Fixed-width column (~230pt): a header (`phase.label(lang)`, uppercased, with a count) over a vertical stack of `TaskCardView` for each task; an empty phase shows a muted "—" placeholder so the column reads as intentionally empty.

### 5. `TaskCardView` (`.../TaskCardView.swift`)
A `CodepetCard` per task:
- **Done toggle**: a leading checkbox (`Image(systemName: task.done ? "checkmark.square.fill" : "square")`, tint = accentPurple) in a `.plain` `Button` → `await companyStore.toggleTaskDone(id: task.id)`.
- **Title** (`.pixelSystem(size: 12, weight: .semibold)`, strikethrough when done), **detail** (muted, ≤2 lines).
- **Who chip**: `TaskWho.label(lang)` in a small muted capsule.
- **Status pill**: `TaskStatus.label(lang)` colored by `statusTint(_:)` (§6), background = tint@0.14.
- **Blocked hint**: when status == `.blocked`, a small "after: …" line naming the first not-done dependency's title (looked up in `tasks`; omitted if the dep is dangling/unknown).

### 6. Status color map (view-side `statusTint`, not stored in the model)
| `TaskStatus` | Tint |
|---|---|
| `.done` | `CodepetTheme.accentTeal` |
| `.codepetCanDo` | `CodepetTheme.accentPurple` |
| `.needsApproval` | `CodepetTheme.accentGold` |
| `.needsYou` | `CodepetTheme.accentOrange` |
| `.blocked` | `CodepetTheme.mutedText` |

## Pure helpers (the testable surface)

Added to the model layer (extend Phase-3A files), pure and unit-tested:
- `RoadmapEngine.orderedColumns(_ tasks: [RoadmapTask]) -> [(phase: RoadmapPhase, tasks: [RoadmapTask])]` — all five phases in `RoadmapPhase.allCases` order, each paired with its tasks (empty array when none). Guarantees the column set + order independent of which phases have tasks.
- `TaskStatus.label(_ lang: AppLanguage) -> String` — Done/Codepet can do/Needs approval/Needs you/Needs earlier steps (+ VI).
- `TaskWho.label(_ lang: AppLanguage) -> String` — Codepet does/Codepet drafts/You (+ VI).

`statusTint(_:)` (color) lives in `TaskCardView` — trivial `switch`, not unit-tested (verified by build).

## Data flow
`company.tasks` (@Published) → `RoadmapEngine.orderedColumns`/`nextStep`/`progressPercent` → header + columns + cards. Done toggle → `toggleTaskDone` → mutates+persists `company.tasks` → SwiftUI recomputes status/beacon/progress automatically. Empty → `generateRoadmap()` (fail-open) on appear.

## Error handling
No new failure paths. Generation is fail-open (empty result → empty state stays); persistence is fail-soft (a failed `toggleTaskDone` write leaves the in-memory flip, consistent with the 3A/onboarding pattern). The view never throws or blocks.

## Testing
- `RoadmapEngine.orderedColumns`: returns all 5 phases in Find→Launch order; groups tasks into the right phase; empty phases present with `[]`; ordering independent of input order.
- `TaskStatus.label` / `TaskWho.label`: every case returns non-empty distinct strings in both `.en` and `.vi`.
- SwiftUI views (OverviewBoardView/header/column/card) are verified by a successful `xcodebuild` build (no logic lives in them); no snapshot tests.

## Reuse / references
| Source | Native target |
|---|---|
| live Overview board (columns/status/beacon/progress) | `OverviewBoardView` + `RoadmapHeaderView` + `PhaseColumnView` + `TaskCardView` |
| Phase-3A `RoadmapEngine` (status/nextStep/progressPercent/tasksByPhase) | consumed as-is; + new `orderedColumns` |
| `CodepetCard` / `.pixelSystem` / accent tokens (CodepetTheme) | card chrome, fonts, status tints |
| `CompanyStore.generateRoadmap`/`toggleTaskDone` | empty-appear generation + card done toggle |

## Open decisions
None — resolved in brainstorming (defer lines; honest empty + quiet generate; tap toggles done; horizontal columns; status color map approved). Ready for implementation planning.
