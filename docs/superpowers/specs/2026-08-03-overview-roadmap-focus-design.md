# Overview roadmap — focus board, honest gating, real centring

**Date:** 2026-08-03
**Scope:** native `codepet` repo only. No Cloud Function deploy, no Firestore migration.
**Branch:** `feat/overview-roadmap-focus` (isolated worktree — `RoadmapView.swift`, `TopNavView.swift`,
`ShellLayout.swift` carry uncommitted header-compaction work in the primary checkout).

## Problem

Two independent defects, one visual and one structural.

**The map is not centred.** `RoadmapBoardView` computes `padTop = (avail - scaledH) / 2`, where `avail`
is a `@State` written from a `GeometryReader` in the ScrollView's `.background`
(`RoadmapBoardView.swift:86`). Measured against a 1481×963pt window, `avail` resolves to ≈900pt while
the visible scroll viewport is ≈690pt: the board is centred inside a viewport ~200pt taller than the
one on screen, so it lands low and the bottom of the "centred" band falls past the window edge.
Stored, measurement-derived geometry is the fragile part — it can be stale, and `padTop` feeds back
into the content height that produced it.

Horizontally there is no centring at all and no gutter. The root node sits at `x = 12` while the page
uses a 24pt gutter, so the company node's aura is clipped by the window edge. The board also reserves
a full 268pt column for every phase including empty ones (`launch 0/0`, `grow 0/0`), producing a
~1810pt content width against a ~1480pt pane — the cause of the horizontal scroll and the `›` chevron.

**Every task is startable at once.** The connectors between Foundation → Build → Ship are not
dependency edges; they are root fan-out edges (`RoadmapLayoutEngine` emits one per node whose
`dependsOn` resolves to nothing). No card on the board has a resolvable dependency, so
`RoadmapEngine.status` returns `.codepetCanDo` for eight tasks at 0% progress. The dependency
machinery — critical path, `.blocked`, elbow routing, "Needs earlier steps" — is correct and entirely
unexercised, because the data has no chain.

The generator is the origin (`generateRoadmapCore.ts` gained "CHAIN THE PHASES" plus a phase-gating
backstop only on an undeployed branch), but native regenerates only when `tasks.isEmpty`, so existing
boards would stay flat even after a CF fix. This spec therefore derives sequencing on the client and
leaves the CF as a tracked follow-up.

## Design

### 1. `RoadmapGating` — phase states (new pure file)

```swift
enum PhaseState { case complete, open, preview, later }
```

- **complete** — every task in the phase is done.
- **open** — every earlier phase is *settled*. Open phases form a **prefix**, not a single column.
- **preview** — the first phase after the earliest unsettled phase. Visible, locked.
- **later** — everything beyond.

A phase is **settled** when no task in it still needs the founder:

```
settled(p) = tasks(p).allSatisfy { $0.done || (status($0) != .needsYou && status($0) != .needsApproval) }
```

Codepet-owned leftovers do not block. A `codepetCanDo` task left behind in FIND stays runnable after
FOUNDATION opens — which is precisely why the open set is a prefix.

State precedence is `complete → open → preview → later`: a finished phase reads `complete` even though
its predecessors are settled.

A phase with zero tasks is settled (it cannot block) and is never `open` or `preview` — `preview` skips
past empty phases to the next one that has tasks. An empty phase renders as a rail (§3).

### 2. `RoadmapEngine.status` — one added clause

`.blocked` when the task's phase is not open, **in addition to** the existing `dependsOn` rule, so a
real dependency chain still gates within a phase. Precedence is unchanged:

```
done → needsApproval → blocked → needsYou → codepetCanDo
```

`needsApproval` before `blocked` is load-bearing: the two drafted Foundation tasks on the current board
keep reading "Review" rather than disappearing behind a lock, because that work already exists.

Consequences, with no data change:

| Phase      | Before                      | After                                            |
|------------|-----------------------------|--------------------------------------------------|
| find       | 1 × Add your input (beacon) | open — one beacon, unchanged                      |
| foundation | 2 × Review, 1 × Start       | preview — locked; the 2 drafts still say "Review" |
| build      | 3 × Start                   | later — locked                                    |
| ship       | 2 × Start                   | later — locked                                    |

This table depends on FIND's one task being **founder-owned** (`who == .you` — it renders "Add your
input", not "Start"), which is what keeps FIND unsettled and FOUNDATION merely a preview. Read the
rule, not the table: were that task Codepet-owned instead, FIND would be *settled* and FOUNDATION
would be **open** alongside it, because the open set is a prefix and Codepet-owned leftovers do not
block. That case is not hypothetical — it is what the founder's board looks like the moment they
finish their FIND step, and any consumer that assumes a single open phase will break there.

`nextStep` needs no change: phase-gating flows through `status`. `nextMoves` is confined to the open
prefix, so the chat's parallel-agent fan-out returns fewer tasks early on — one, on the current board.
That is the accepted cost of the rolling window; it recovers as soon as a multi-department phase opens.

**Dead-end escape hatch.** Tapping a locked card must not no-op. `RoadmapDispatch` gains a
`.showBlocker(RoadmapTask)` action for `.blocked` status: the board names the blocking task
("Waiting on: Talk to 5 potential users") and starts *that* task instead. The blocker is the earliest
founder-owned task in the earliest unsettled phase, walked forward to something actually actionable if
that task is itself blocked. It coincides with the beacon when the open prefix holds exactly one
populated phase; with a wider prefix the beacon may sit in an earlier phase than the blocker, and both
are legitimate actions. No per-task skip: that is a separate product decision.

### 3. `RoadmapFocus` + rails — the board fits the window

New pure function:

```swift
RoadmapFocus.expanded(tasks:availableWidth:userExpanded:) -> Set<RoadmapPhase>
```

Grows greedily outward from the open phase (open first, then `preview`, then neighbours) while the
accumulated width fits `availableWidth`. Phases the founder clicked open (`userExpanded`) are honoured
first and never dropped. A phase with no tasks is never expanded.

`RoadmapLayoutEngine.layout` takes `expanded:` and `colLeft` becomes a running accumulator rather than
`col * (cardW + colGap)`:

- **expanded phase** → today's 208pt column, `colGap` 60
- **collapsed phase** → a 44pt rail, full board height, rotated phase label + `done/total`, `railGap` 20
- **empty phase** → always a rail; tooltip "Not planned yet"

Lane assignment and `maxRows` are computed over **expanded columns only**, so the board's height is the
height of what is actually shown. This is what makes §4's centring read correctly instead of centring a
mostly-empty six-column canvas.

`RoadmapGeometry`'s web-parity constants are untouched. `headerTrailingAllowance = 240` — the fixed
fudge for the last header's label — is removed: the trailing column is a rail whose label is vertical.

One faint accent stub connects the last expanded column to the first following rail, so the journey
still reads as continuous. Rails carry no cards and no dependency edges.

The root node keeps its position and is vertically centred on the expanded content.

### 4. Framing — delete the measured centring

`@State avail`, the `.background(GeometryReader)`, `scale(for:)` and `padTop` all come out:

```swift
GeometryReader { g in
    ScrollView([.horizontal, .vertical], showsIndicators: false) {
        content.frame(minWidth:  g.size.width  - insets.horizontal,
                      minHeight: g.size.height,
                      alignment: .center)
    }
}
```

Centring becomes layout rather than arithmetic: no stored measurement, so no stale viewport and no
`padTop` feedback loop. §3 makes the board fit at scale 1.0, so web's "never downscale" rule is
preserved by construction instead of by clamping.

Insets: 26pt leading for the root's aura plus the page's 24pt gutter, applied at the view level so
`RoadmapGeometry` and `RoadmapLayoutTests` stay untouched. The company node stops being clipped.

The current-move framing (`ScrollViewReader` + `frame(proxy:id:)`) and the scroll-edge fades stay as
they are; with the board fitting the pane they simply fire less often.

### 5. Phase headers

Header chips take phase state: `open` = accent tint (as today), `preview` = hairline border + lock
glyph, `complete` = green check + count, rails muted. The existing KEY legend already carries "Needs
earlier steps", so no legend change.

## Files

| File | Change |
|------|--------|
| `codepet/Models/RoadmapGating.swift` | new — `PhaseState`, `settled`, `states(for:)`, `blocker(in:)` |
| `codepet/Models/RoadmapFocus.swift` | new — `expanded(tasks:availableWidth:userExpanded:)` |
| `codepet/Models/RoadmapEngine.swift` | `status` gains the phase-open clause |
| `codepet/Models/RoadmapDispatch.swift` | `.showBlocker` action for `.blocked` |
| `codepet/Models/RoadmapLayout.swift` | `expanded:` param, rail geometry, accumulator `colLeft`, expanded-only lanes/height |
| `codepet/Views/Overview/RoadmapBoardView.swift` | GeometryReader framing, rails, phase-state headers, remove `avail`/`scale`/`padTop`/`headerTrailingAllowance` |
| `codepet/Views/Overview/RoadmapCardView.swift` | locked-card tap affordance copy |
| `codepet/Models/RoadmapBoardCopy.swift` | blocker + "not planned yet" strings, EN + VI |

## Tests

**New**

- `RoadmapGatingTests` — open set is a prefix; Codepet leftovers do not block; a drafted task counts as
  a founder blocker; `needsApproval` beats `blocked`; empty phases are settled and never open; the
  blocker resolves to an actionable task, and coincides with the beacon when the open prefix holds
  one populated phase.
- `RoadmapFocusTests` — width budget expands greedily from the open phase; `userExpanded` is honoured
  and never dropped; empty phases are never expanded; deterministic for a fixed width.

**Updated**

- `RoadmapEngineTests`, `RoadmapEngineNextMovesTests` — status, beacon and fan-out semantics change by
  design; expectations move with them.
- `RoadmapLayoutTests` — rail-accumulator x positions, expanded-only height, root centring.
- `RoadmapDispatchTests` — `.blocked` maps to `.showBlocker`.

Every new decision lands in a pure model file, so all of it is unit-testable without a host app. Per
the repo's Firestore lock note, the running `codepet.app` must be closed before `xcodebuild test`.

## Risks

- **Fan-out narrows early.** `nextMoves` returns one task on a board whose only open phase holds one
  task. Accepted; it is the honest reading of the rolling window.
- **Test churn.** Changing `status` semantics touches existing engine expectations. Intentional and
  enumerated above.
- **New users still get flat, under-populated boards.** The `generateRoadmap` CF fix is out of scope by
  decision; gating repairs the *reading* of such a board but cannot invent Launch/Grow tasks. Tracked
  as a follow-up.

## Out of scope

CF prompt/deploy, Firestore migration, a re-plan action, per-task skip, Second Brain tab.
