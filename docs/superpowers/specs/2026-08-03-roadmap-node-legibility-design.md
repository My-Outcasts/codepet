# Roadmap node legibility — adapting Cofounder's tech-tree model

**Date:** 2026-08-03
**Branch:** `feat/roadmap-node-legibility`, branched off `feat/overview-roadmap-focus` (PR #52) —
it touches the same four files, so it must not land before that merges.
**Reference studied:** Cofounder's "How to Build a Company" tech tree
(`app.cofounder.co/org/<org>/canvas?open_tech_tree=1`), inspected live on 2026-08-03.
**Predecessor spec:** `2026-08-03-overview-roadmap-focus-design.md` (the rolling phase window,
focus rails and layout centring this builds on).

## What Cofounder does that we don't

Their nodes are **states, not chores**. Opening a completed node shows:

> **BUILD** · **App is started** — `Build app` · Completed
> **WHAT BECOMES TRUE** — The core app exists so onboarding, launch, and GTM work can connect.
> **HOW TO MOVE THIS FORWARD** — Build the usable product app in Cofounder.
> **TO COMPLETE** — ☑ App is started
> **REQUIRED FIRST** — ✓ Initial idea

Every node answers four questions: what becomes true, how do I move it, what counts as done, and
what's required first — with each dependency shown next to its *live status*. Some nodes are pure
milestones ("Marketing website is launched", "Support agent is installed"). That framing is why it
reads as a tech tree instead of a to-do list.

Codepet's cards carry a title and a verb chip. The dependency graph exists and is correct, but it
is only visible as drawn edges and a hover tooltip, and nothing anywhere says why a task matters.

Also observed and adopted: a lock glyph plus a named reason on blocked cards, an **In progress**
state, a **Mark complete** action for work done outside the app, and **three** ranked suggestions
instead of one beacon.

Also observed and **rejected**: Cofounder does not gate by stage at all (Identity had three
"Available" cards while Initial sat at 2/3, and "Launch app" was complete while GTM was 0/4).
Codepet keeps its rolling phase window — the product is a companion telling one founder what to do
next, not a canvas of agents to direct. Decision confirmed by the founder.

## Decisions taken before design

1. **Keep the phase window.** Borrow Cofounder's legibility, not its gating.
2. **Derive, don't author.** Panel content comes from data every existing board already has, so
   this works on the current board with no Cloud Function deploy and no migration. We are NOT
   adding `becomesTrue`/`stateName`/`completionCriteria` fields, which means node titles stay task
   names rather than state assertions ("Design your brand look", not "Brand exists").
3. All four secondary mechanisms are in scope: mark-complete, lock-plus-reason, in-progress,
   suggested-next×3.

## 1. `RoadmapNodeDetail` + the node panel

**New pure file** `codepet/Models/RoadmapNodeDetail.swift` derives everything; **new view**
`codepet/Views/Overview/TaskNodePanel.swift` renders it. Same split as `RoadmapGating` /
`RoadmapFocus`: all decisions in a testable pure struct, a thin sheet over it.

```swift
struct RoadmapNodeDetail {
    let phaseLabel: String          // "FOUNDATION"
    let deptName: String?           // "Design", nil for legacy dept-less tasks
    let title: String
    let status: TaskStatus
    let becomesTrue: String         // per-PHASE sentence (see below)
    let howToMoveForward: String    // task.detail, or a status-derived fallback
    let toComplete: String          // derived from task.who
    let requiredFirst: [Requirement]
    let unlocks: [String]           // titles of tasks depending on this one, capped at 4
    static func build(for task: RoadmapTask, in tasks: [RoadmapTask], lang: AppLanguage) -> Self
}

struct Requirement {               // a dependency, or the phase window itself
    enum Kind { case task(RoadmapTask), phaseWindow(RoadmapPhase) }
    let kind: Kind
    let label: String
    let satisfied: Bool
    let statusNote: String?        // "needs you", "Codepet can run this", …
}
```

**`becomesTrue` is per-phase, not per-task, and says so.** Six sentences in `RoadmapBoardCopy`,
bilingual, phrased as "Finishing this moves <Phase> forward: <sentence>". We cannot honestly claim
to know what each individual task makes true without authored fields (decision 2), and inventing a
per-task claim would be worse than a truthful per-phase one.

| Phase | Sentence (EN) |
|---|---|
| find | you know who wants this and why |
| foundation | the pieces Build depends on exist |
| build | the product exists and runs |
| ship | it's deployable, documented and defensible |
| launch | it's public and reachable |
| grow | it keeps growing without you steering every step |

**`toComplete`** derives from `task.who`: `.does` → "Codepet runs it; you approve the result."
`.draft` → "Codepet drafts it; you finalise." `.you` → "You do this one — Codepet will walk you
through it."

**`requiredFirst`** is the part Cofounder does best, plus one thing it can't have: unmet
dependencies each with their live status, AND — when the task is phase-gated — an explicit
`.phaseWindow` requirement naming the phase and the founder step holding it shut
(`RoadmapGating.founderStep`). Satisfied requirements still render, checked, so the panel shows
progress rather than only obstacles.

Exact wording per requirement kind:

- `.task(dep)` → `label` is the dependency's title; `statusNote` is its status label ("needs you",
  "Codepet can do", "Needs approval"); `satisfied` is `dep.done`.
- `.phaseWindow(phase)` → `label` is "<PHASE> must be settled first"; `statusNote` names the
  blocking step ("waiting on: Talk to 5 potential users"), or is nil when `founderStep` returns
  nothing; `satisfied` is false whenever this requirement is emitted at all.

**Panel actions:** the primary action from `RoadmapDispatch.action(for:)`, plus mark-complete (§2).

### Behaviour change: tap opens the panel

Today tapping a card dispatches immediately — a mis-click starts an agent run, and there is
nowhere to read about a task first. Tapping now opens the panel, and the action lives inside it.
The chrome row's `DO THIS NEXT` keeps its direct `Start`, so the one-click path for the current
move is unchanged.

Rejected alternative: keep tap-to-run and add a separate ⓘ target. Two hit targets on a 208×64
card fights the project's minimalist rule, and it leaves the accidental-run problem in place.

## 2. Mark complete

`CompanyStore.toggleTaskDone(id:)` already exists and persists, so this is an affordance plus a
guard. Labelled "I already did this".

- **Offered** for `.codepetCanDo`, `.needsYou` and `.blocked`.
- **Hidden** when `task.drafted` — a draft exists, "Approve" is the correct action, and
  mark-complete would silently discard generated work.
- **Hidden** when already `.done`.

This closes a dead end shipped in the predecessor spec: a `needsYou` task the founder handles in
real life currently holds the phase window shut forever, because nothing in the app can record it.

## 3. Lock glyph and a named blocker on the card face

`RoadmapCardView` renders, for `.blocked`, a lock glyph plus `RoadmapBoardCopy.waitingOn(<title>)`
in place of the generic "Needs earlier steps". One line, tail-truncated; the full name stays in the
hover peek and the panel.

**This forces a correctness fix.** `RoadmapGating.blocker(for:in:)` currently serves two masters:
explanation and escape-hatch redirect. Its `actionable(...)` walk means that on a cyclic or
dangling graph it can return a task with no dependency relationship to the tapped card — harmless
as a redirect target, but a lie on the card face. Split it:

- `blocker(for:in:)` — **strict**: the first unmet dependency, or the founder step holding the
  phase window shut. No walk, no fallback. Used for all display.
- `escapeHatch(for:in:)` — today's walked-forward behaviour. Used only by `RoadmapView.dispatch`.

The final review of PR #52 logged this as a Minor with exactly this fix.

## 4. In progress

`TaskStatus` stays pure. "Running" is ephemeral UI state, not a persisted fact, and threading it
through `status(for:in:)` would change a signature ~18 call sites depend on.

- `CompanyStore` gains `@Published var runningTaskIds: Set<String>`, inserted before the `runTask`
  / `walkThroughTask` await and removed in a `defer`.
- `RoadmapCardView` gains `isRunning: Bool`; a running card shows a spinner and "In progress"
  instead of its verb chip.
- `RoadmapView.dispatch` no-ops for a running task, so an agent can't be double-fired.

## 5. Suggested Next ×3

**`RoadmapEngine.nextMoves` cannot back this** — verified by reading it: it filters to
`status == .codepetCanDo` AND departments that map to a specialist companion, so it excludes every
`needsYou` task. The current beacon ("Talk to 5 potential users") is a `needsYou`, so reusing
`nextMoves` would drop the founder's own next step from their suggestions.

**New pure function:**

```swift
static func suggestedNext(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask]
```

Actionable tasks (`codepetCanDo`, `needsYou`, `needsApproval`) inside the open phase window, in
roadmap order, deduplicated by department, with `nextStep`'s result guaranteed first so the beacon
and the suggestion list can never disagree. Dept-less legacy tasks are eligible and each counts as
its own slot.

`OverviewChromeRow` renders the first as today's filled beacon and up to two more as compact rows,
**replacing** the existing single `alsoNeedsYou` line rather than sitting alongside it.

**Reasons are derived, not authored:** `"<Dept> · unlocks <n> later steps"`, or
`"<Dept> · nothing else waits on it yet"` when the unlock count is zero. Cofounder's reasons are
LLM prose; ours cannot be without authored fields, but unlock-count is a structurally true
leverage signal rather than a persuasive one.

**Layout note:** the chrome row grows vertically. This is safe *because* of the predecessor spec —
centring is now layout-based, so a taller chrome row shrinks the board area and the map re-centres
inside it. Under the old arithmetic this would have shifted the map off-centre.

## Files

| File | Change |
|---|---|
| `codepet/Models/RoadmapNodeDetail.swift` | new — `RoadmapNodeDetail`, `Requirement`, `build(for:in:lang:)` |
| `codepet/Views/Overview/TaskNodePanel.swift` | new — the sheet |
| `codepet/Models/RoadmapGating.swift` | split `blocker` (strict) from `escapeHatch` (walked) |
| `codepet/Models/RoadmapEngine.swift` | add `suggestedNext(_:limit:)`; `nextMoves` untouched |
| `codepet/Models/RoadmapBoardCopy.swift` | phase `becomesTrue` sentences, `toComplete` lines, mark-complete label, in-progress label, suggestion reasons — all EN + VI |
| `codepet/Views/Overview/RoadmapCardView.swift` | lock glyph + named blocker; `isRunning` spinner |
| `codepet/Views/Overview/RoadmapBoardView.swift` | tap opens the panel; passes blocker title and `isRunning` |
| `codepet/Views/Overview/OverviewChromeRow.swift` | Suggested Next ×3 replacing `alsoNeedsYou` |
| `codepet/Managers/CompanyStore.swift` | `runningTaskIds`; mark-complete reuses `toggleTaskDone` |
| `codepet/Views/Roadmap/RoadmapView.swift` | panel presentation; dispatch uses `escapeHatch`; no-op while running |

## Tests

**New** — `RoadmapNodeDetailTests`: per-phase `becomesTrue` selection; `howToMoveForward` falls
back when `detail` is empty; `toComplete` per `who`; `requiredFirst` lists unmet deps with correct
satisfied flags; a phase-gated task gets a `.phaseWindow` requirement naming the founder step; an
in-window dependency-gated task does NOT; `unlocks` reads reverse edges and caps at 4; both
languages non-empty and distinct.

**New** — `RoadmapEngineSuggestedNextTests`: `nextStep` is always first; dedup by department;
confined to the open window; includes `needsYou` and `needsApproval` (the gap that rules out
`nextMoves`); respects `limit`; dept-less tasks each take a slot; empty when nothing is actionable.

**Updated** — `RoadmapGatingTests`: the actionable-walk tests move to `escapeHatch`; new tests pin
that strict `blocker` returns nil rather than an unrelated task on a cyclic graph.
`RoadmapDispatchTests`: unchanged mapping, but dispatch now consumes `escapeHatch`.
`RoadmapBoardCopyTests`: the new strings.

Views have no unit tests, as before. Verification is the full suite plus a visual pass — which
requires the founder's eyes, since this environment cannot screenshot the app.

## Risks

- **Tap semantics.** Muscle memory says tap runs the task. Mitigated by keeping the chrome row's
  direct `Start`, but it is a real change and the visual pass should confirm it feels right.
- **Mark complete is unguarded progress.** A founder can mark anything done and open the next
  phase. That is the point — it's the escape hatch — but it means the roadmap's progress figure can
  reflect claims rather than generated work. Accepted; the alternative is the dead end.
- **Panel content is derived, so it is generic.** "Finishing this moves Foundation forward" is true
  of every Foundation task. If it reads as filler rather than insight, the answer is authored
  fields and a CF deploy, not better derivation.

## Out of scope

Per-task pictorial icons (conflicts with the project's no-decorative-icons rule); the Identity and
GTM stages Cofounder has and Codepet folds into Foundation and Ship/Launch (generator work plus a
migration for every existing board); per-department roadmap slices deep-linking into the board;
authored per-node fields and the `generateRoadmap` prompt changes they need.
