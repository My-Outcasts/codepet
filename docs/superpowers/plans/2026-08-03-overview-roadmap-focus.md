# Overview Roadmap Focus Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Overview roadmap read as a journey — one open phase with a clear beacon, later phases visibly locked — and make the board actually centre in its pane instead of sliding to the bottom-left.

**Architecture:** Three new pure model files carry every decision (`RoadmapGating` = which phases are open, `RoadmapFocus` = which phases render as full columns, plus rail geometry in `RoadmapGeometry`), so all of it is unit-testable with no host app. `RoadmapEngine.status` gains a single phase-open clause, which propagates to every surface that already calls it. `RoadmapBoardView` drops its stored-measurement centring (`@State avail` → `padTop` arithmetic) in favour of a `GeometryReader` + `minWidth/minHeight` + `.center` frame.

**Tech Stack:** Swift 5 / SwiftUI, macOS 13+, XCTest, Xcode 26.4 (`xcodebuild`, scheme `codepet`).

**Spec:** `docs/superpowers/specs/2026-08-03-overview-roadmap-focus-design.md`

## Global Constraints

- Work in the worktree `/Users/monatruong/Developer/codepet-roadmap-focus` on branch `feat/overview-roadmap-focus`. Never touch `/Users/monatruong/Developer/codepet` — it holds a concurrent session's uncommitted work in `RoadmapView.swift`, `TopNavView.swift`, `ShellLayout.swift`.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`. New `.swift` files under `codepet/` and `codepetTests/` are picked up automatically — **never edit `project.pbxproj`**.
- **A running `codepet.app` holds the Firestore LevelDB lock and aborts the test host.** Before any `xcodebuild test`: `pkill -x codepet` or quit the app. `** TEST FAILED **` with zero `Failing tests:` lines means the suite never ran — close the app and re-run.
- Builds must be TEAM-signed (ad-hoc signing breaks the keychain and sign-in across rebuilds): append `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates` to every `xcodebuild` invocation.
- All user-visible copy is bilingual: every new string takes `lang: AppLanguage` and returns English and Vietnamese. Follow `RoadmapBoardCopy`'s existing shape.
- `RoadmapGeometry`'s web-parity constants (`cardW 208`, `cardH 64`, `colGap 60`, `rowPitch 96`, `top 40`, `bottomPad 16`, `rootW 172`, `rootH 118`, `rootLeft 12`, `rootGap 48`) must not change. `RoadmapLayoutTests.testGeometryMatchesWeb` pins them.
- `RoadmapLayoutEngine.layout`'s new `expanded:` parameter defaults to `nil`, meaning "every phase is a full column" — the exact current behaviour — so all existing layout tests stay green without edits.
- Never add a dependency. Every new file imports only `Foundation`/`CoreGraphics`/`SwiftUI`.

---

### Task 0: Baseline

**Files:** none (verification only)

**Interfaces:**
- Consumes: nothing
- Produces: a known-good starting point — the pass/fail state every later task is measured against

- [ ] **Step 1: Confirm the worktree and branch**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git branch --show-current    # expect: feat/overview-roadmap-focus
git status --short            # expect: clean
```

- [ ] **Step 2: Close the app so the Firestore lock is free**

```bash
pkill -x codepet; ps aux | grep -c "[c]odepet.app"
```

Expected: `0`. If non-zero, quit Codepet from the Dock before continuing.

- [ ] **Step 3: Run the full test suite and record the baseline**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. Record the executed-test count from the summary line. If the suite is already red, **stop and report** — do not start Task 1 on a red baseline.

---

### Task 1: `RoadmapGating` — the rolling window

**Files:**
- Create: `codepet/Models/RoadmapGating.swift`
- Test: `codepetTests/RoadmapGatingTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapPhase`, `TaskWho` (from `codepet/Models/RoadmapTask.swift`)
- Produces:
  - `enum PhaseState: Equatable { case complete, open, preview, later }`
  - `RoadmapGating.needsFounder(_ task: RoadmapTask) -> Bool`
  - `RoadmapGating.settled(_ phase: RoadmapPhase, in tasks: [RoadmapTask]) -> Bool`
  - `RoadmapGating.openPhases(_ tasks: [RoadmapTask]) -> Set<RoadmapPhase>`
  - `RoadmapGating.states(_ tasks: [RoadmapTask]) -> [RoadmapPhase: PhaseState]`
  - `RoadmapGating.blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask?`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/RoadmapGatingTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapGatingTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted)
    }

    // MARK: needsFounder

    func testOnlyFounderOwnedOrDraftedWorkCountsAsABlocker() {
        XCTAssertTrue(RoadmapGating.needsFounder(t("a", .find, who: .you)))
        XCTAssertTrue(RoadmapGating.needsFounder(t("b", .find, drafted: true)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("c", .find, who: .does)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("d", .find, who: .draft)))   // drafted:false → nothing to approve yet
        XCTAssertFalse(RoadmapGating.needsFounder(t("e", .find, who: .you, done: true)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("f", .find, drafted: true, done: true)))
    }

    // MARK: settled

    func testPhaseWithNoFounderWorkIsSettled() {
        let all = [t("a", .find), t("b", .find, who: .draft)]
        XCTAssertTrue(RoadmapGating.settled(.find, in: all))
    }

    func testPhaseHoldingFounderWorkIsNotSettled() {
        XCTAssertFalse(RoadmapGating.settled(.find, in: [t("a", .find, who: .you)]))
        XCTAssertFalse(RoadmapGating.settled(.find, in: [t("a", .find, drafted: true)]))
    }

    func testEmptyPhaseIsSettled() {
        XCTAssertTrue(RoadmapGating.settled(.launch, in: [t("a", .find, who: .you)]))
        XCTAssertTrue(RoadmapGating.settled(.find, in: []))
    }

    // MARK: openPhases

    func testOpenSetIsAPrefixEndingAtTheFirstUnsettledPhase() {
        // FIND settled (Codepet-owned), FOUNDATION holds a founder step → the window stops there.
        let all = [t("f", .find), t("y", .foundation, who: .you), t("b", .build)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.find))
        XCTAssertTrue(open.contains(.foundation))      // the unsettled phase is itself open
        XCTAssertFalse(open.contains(.build))
        XCTAssertFalse(open.contains(.grow))
    }

    func testCodepetLeftoversDoNotHoldTheWindowShut() {
        // A Codepet-owned FIND task nobody has run yet must not lock FOUNDATION.
        let all = [t("f", .find), t("d", .foundation)]
        XCTAssertEqual(RoadmapGating.openPhases(all), Set(RoadmapPhase.allCases))
    }

    func testFirstPhaseIsAlwaysOpen() {
        XCTAssertTrue(RoadmapGating.openPhases([t("y", .find, who: .you)]).contains(.find))
        XCTAssertTrue(RoadmapGating.openPhases([]).contains(.find))
    }

    func testEmptyPhasesAreTransparentToTheWindow() {
        // Nothing in FIND or FOUNDATION; BUILD holds founder work → SHIP is closed, BUILD open.
        let all = [t("y", .build, who: .you), t("s", .ship)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.build))
        XCTAssertFalse(open.contains(.ship))
    }

    // MARK: states

    func testStatesPrecedenceCompleteBeatsOpen() {
        let all = [t("f", .find, done: true), t("y", .foundation, who: .you), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .complete)
        XCTAssertEqual(s[.foundation], .open)
        XCTAssertEqual(s[.build], .preview)
        XCTAssertEqual(s[.ship], .later)
    }

    func testPreviewSkipsEmptyPhases() {
        // FIND holds founder work; FOUNDATION is empty → the preview is BUILD, the next
        // phase that actually has tasks.
        let all = [t("y", .find, who: .you), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .open)
        XCTAssertEqual(s[.foundation], .later)
        XCTAssertEqual(s[.build], .preview)
    }

    func testEmptyPhaseIsNeverCompleteOrPreview() {
        let s = RoadmapGating.states([t("y", .find, who: .you)])
        XCTAssertEqual(s[.grow], .later)
        XCTAssertEqual(s.count, RoadmapPhase.allCases.count)
    }

    // MARK: blocker

    func testBlockerOfAPhaseGatedTaskIsTheEarliestFounderStep() {
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: [gate, later])?.id, "y")
    }

    func testBlockerAgreesWithTheBeacon() {
        // The founder step holding the window shut is also what nextStep points at, so the
        // locked-card explanation and the beacon can never disagree.
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        let all = [gate, later]
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: all)?.id,
                       RoadmapEngine.nextStep(all)?.id)
    }

    func testBlockerOfADependencyGatedTaskIsItsUnmetDependency() {
        // Both in the open window; b waits on a, which is not done.
        let a = t("a", .find)
        let b = t("b", .find, deps: ["a"])
        XCTAssertEqual(RoadmapGating.blocker(for: b, in: [a, b])?.id, "a")
    }

    func testBlockerIsNilWhenNothingResolves() {
        let a = t("a", .find, deps: ["ghost"])     // dangling dep → fail-open, nothing blocks
        XCTAssertNil(RoadmapGating.blocker(for: a, in: [a]))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapGatingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'RoadmapGating' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/RoadmapGating.swift`:

```swift
// codepet/Models/RoadmapGating.swift
import Foundation

/// Where a phase stands in the founder's rolling window.
///
/// `open` phases are the ones the founder may act in; they form a PREFIX of the phase order,
/// not a single column, because Codepet-owned leftovers don't hold the window shut. `preview`
/// is the next planned phase — visible and locked, so the journey ahead is legible.
enum PhaseState: Equatable { case complete, open, preview, later }

/// The rolling-window rule: which phases are open, why a locked task is locked, and who has
/// to move for the window to advance. Pure — no network, no mutation, no view types.
enum RoadmapGating {
    /// Work only the FOUNDER can clear: their own step, or a draft awaiting their approval.
    ///
    /// Deliberately STRUCTURAL rather than asking `RoadmapEngine.status` — `status` consults
    /// this gating, so calling it here would recurse forever.
    static func needsFounder(_ task: RoadmapTask) -> Bool {
        !task.done && (task.drafted || task.who == .you)
    }

    /// A phase blocks nothing once no task in it still needs the founder. A `codepetCanDo`
    /// leftover does NOT keep the next phase shut — that's exactly what makes the open set a
    /// prefix, and it's what stops the founder being stuck behind work Codepet owes them.
    /// A phase with no tasks is trivially settled: an unplanned phase can't gate anything.
    static func settled(_ phase: RoadmapPhase, in tasks: [RoadmapTask]) -> Bool {
        !tasks.contains { $0.phase == phase && needsFounder($0) }
    }

    /// Every phase whose predecessors are all settled. The first phase has no predecessors, so
    /// the result is never empty — the founder always has somewhere to act.
    static func openPhases(_ tasks: [RoadmapTask]) -> Set<RoadmapPhase> {
        var out: Set<RoadmapPhase> = []
        for phase in RoadmapPhase.allCases {
            out.insert(phase)                      // this phase's predecessors are all settled
            if !settled(phase, in: tasks) { break } // …and it holds founder work, so stop here
        }
        return out
    }

    /// Per-phase state for the board's headers and rails. Precedence:
    /// `complete → open → preview → later`.
    static func states(_ tasks: [RoadmapTask]) -> [RoadmapPhase: PhaseState] {
        let open = openPhases(tasks)
        let populated = Set(tasks.map(\.phase))
        // The preview skips PAST empty phases: a gap in the plan must not swallow the one
        // look-ahead the founder gets.
        let preview = RoadmapPhase.allCases.first { !open.contains($0) && populated.contains($0) }
        var out: [RoadmapPhase: PhaseState] = [:]
        for phase in RoadmapPhase.allCases {
            let mine = tasks.filter { $0.phase == phase }
            if !mine.isEmpty && mine.allSatisfy(\.done) { out[phase] = .complete }
            else if open.contains(phase)                { out[phase] = .open }
            else if phase == preview                    { out[phase] = .preview }
            else                                        { out[phase] = .later }
        }
        return out
    }

    /// The one task standing between the founder and `task`, so a locked card can explain
    /// itself and hand the founder something to actually do.
    ///
    /// Phase-gated → the earliest founder-owned step in the earliest unsettled phase, which is
    /// the same task the beacon points at (the two surfaces can't disagree). Dependency-gated →
    /// the first unfinished dependency. nil when nothing resolves (a dangling dep, a cycle).
    static func blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        if !openPhases(tasks).contains(task.phase) {
            for phase in RoadmapPhase.allCases where !settled(phase, in: tasks) {
                if let found = tasks.first(where: { $0.phase == phase && needsFounder($0) }) {
                    return found
                }
            }
        }
        return task.dependsOn.compactMap { id in tasks.first { $0.id == id && !$0.done } }.first
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapGatingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 15 tests executed.

Note: `testBlockerAgreesWithTheBeacon` passes on the *current* `nextStep` too — Task 2 keeps it passing after gating lands.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Models/RoadmapGating.swift codepetTests/RoadmapGatingTests.swift
git commit -F - <<'EOF'
feat(roadmap): RoadmapGating — the rolling phase window

A phase opens once every earlier phase is settled, where settled means no task
in it still needs the founder. Codepet-owned leftovers deliberately do NOT hold
the window shut, so the open set is a prefix and the founder is never stuck
behind work Codepet owes them.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Wire the window into `RoadmapEngine`

**Files:**
- Modify: `codepet/Models/RoadmapEngine.swift:19-24` (`status`), `:35-44` (`nextStep`)
- Test: `codepetTests/RoadmapEngineTests.swift` (append three tests)

**Interfaces:**
- Consumes: `RoadmapGating.openPhases(_:)` from Task 1
- Produces: `RoadmapEngine.status` returns `.blocked` for tasks outside the open window; `RoadmapEngine.nextStep` never points past it. Signatures unchanged, so all ~18 existing call sites (`TasksView`, `Department.summaries`, `ChatLandingState`, `CompanyStore` fan-out, the board) inherit the behaviour with no edits.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/RoadmapEngineTests.swift`, inside the existing `final class RoadmapEngineTests` (it already defines the `t(...)` helper this code uses):

```swift
    // MARK: rolling window (RoadmapGating)

    func testStatusIsBlockedOutsideTheOpenWindow() {
        let gate = t("y", .find, who: .you)     // holds FIND shut
        let later = t("b", .build)              // .does, no deps → would otherwise be codepetCanDo
        let all = [gate, later]
        XCTAssertEqual(RoadmapEngine.status(for: later, in: all), .blocked)
        XCTAssertEqual(RoadmapEngine.status(for: gate, in: all), .needsYou)
    }

    /// A drafted task in a CLOSED phase still says "needs approval": the draft already exists,
    /// and hiding it behind a lock would strand finished work.
    func testDraftedBeatsThePhaseWindow() {
        let gate = t("y", .find, who: .you)
        let draft = t("d", .build, drafted: true)
        XCTAssertEqual(RoadmapEngine.status(for: draft, in: [gate, draft]), .needsApproval)
    }

    func testNextStepDoesNotSkipAheadOfAClosedPhase() {
        // FIND's two founder steps block each other, so FIND has no actionable task at all.
        // Without the window the beacon would jump to BUILD; with it, there is no beacon.
        let a = t("a", .find, who: .you, deps: ["b"])
        let b = t("b", .find, who: .you, deps: ["a"])
        let later = t("c", .build)
        XCTAssertNil(RoadmapEngine.nextStep([a, b, later]))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapEngineTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*(failed|passed)|TEST" | tail -20
```

Expected: `testStatusIsBlockedOutsideTheOpenWindow` and `testNextStepDoesNotSkipAheadOfAClosedPhase` FAIL (`.codepetCanDo` is not equal to `.blocked`; `"c"` is not nil). `testDraftedBeatsThePhaseWindow` already passes — precedence puts `drafted` first.

- [ ] **Step 3: Write the implementation**

In `codepet/Models/RoadmapEngine.swift`, replace `status(for:in:)` with:

```swift
    /// Legend status. Precedence: done → needsApproval → blocked → needsYou → codepetCanDo.
    ///
    /// TWO things block: the rolling phase window (`RoadmapGating`) and unmet dependencies. The
    /// window is checked first because it's the coarser truth — a task in a closed phase isn't
    /// workable no matter how its own deps look. `needsApproval` stays ahead of both: a draft
    /// that already exists must stay reviewable even in a closed phase.
    static func status(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskStatus {
        if task.done { return .done }
        if task.drafted { return .needsApproval }
        if !RoadmapGating.openPhases(tasks).contains(task.phase) { return .blocked }
        if !depsSatisfied(task, byId(tasks)) { return .blocked }
        return task.who == .you ? .needsYou : .codepetCanDo
    }
```

And replace `nextStep(_:)` with:

```swift
    /// The beacon: the first not-done, dependency-satisfied task INSIDE the open phase window,
    /// by phase order then position. The window clause matters when the open phase has no
    /// actionable task of its own — without it the beacon would skip into a locked phase and
    /// point at a card the board draws as locked.
    static func nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask? {
        let index = byId(tasks)
        let open = RoadmapGating.openPhases(tasks)
        return tasks.enumerated()
            .filter { !$0.element.done && open.contains($0.element.phase)
                      && depsSatisfied($0.element, index) }
            .min(by: { a, b in
                a.element.phase.order != b.element.phase.order
                    ? a.element.phase.order < b.element.phase.order
                    : a.offset < b.offset
            })?.element
    }
```

`nextMoves` needs no change: it already filters on `status(for:in:) == .codepetCanDo`, so it inherits the window.

- [ ] **Step 4: Run the engine and gating tests**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapEngineTests \
  -only-testing:codepetTests/RoadmapGatingTests \
  -only-testing:codepetTests/RoadmapEngineNextMovesTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|TEST" | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the FULL suite and repair the fallout**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|Failing tests|TEST" | tail -30
```

`status` semantics changed, so fixtures that place a founder-owned task in an early phase AND expect a later-phase task to be actionable now fail. The known one is `ChatLandingStateTests.fixtureTasks()` (`codepetTests/ChatLandingStateTests.swift:24-31`): `t2` is `.foundation`/`who: .you`, which now closes `.build`, so `t4` becomes `.blocked` and `needsYouCount` drops from 1 to 0.

Repair recipe — **fix the fixture, never the rule**. For each failure, make the fixture's intent explicit by moving the tasks it wants actionable into the open window:

```swift
    // ChatLandingStateTests.fixtureTasks() — t4 must stay a second `needsYou` task, so it
    // belongs in the SAME phase as the beacon rather than a later, now-locked one.
    private func fixtureTasks() -> [RoadmapTask] {
        [
            RoadmapTask(id: "t1", title: "Set up repo", detail: "", phase: .find, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you),
            RoadmapTask(id: "t3", title: "Draft brand brief", detail: "", phase: .foundation, who: .draft, drafted: true),
            RoadmapTask(id: "t4", title: "Write landing copy", detail: "", phase: .foundation, who: .you),
        ]
    }
```

If any other test fails, apply the same move: relocate the task the test wants actionable into the earliest phase that holds founder work, or mark the earlier founder-owned tasks `done: true`. Do not weaken `status`.

Re-run the full suite until it reports `** TEST SUCCEEDED **` with an executed-test count ≥ the Task 0 baseline.

- [ ] **Step 6: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Models/RoadmapEngine.swift codepetTests/
git commit -F - <<'EOF'
feat(roadmap): gate status and the beacon on the open phase window

status() returns .blocked outside the open window (on top of the existing
dependency rule) and nextStep() no longer points past it, so every surface that
already calls the engine — board, Tasks page, department summaries, chat
fan-out — tells one consistent story instead of offering eight simultaneous
"Start" buttons at 0%.

Fixtures that relied on a later-phase task being actionable behind founder-owned
work were moved into the open window; the rule was not weakened.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Locked cards hand the founder their blocker

**Files:**
- Modify: `codepet/Models/RoadmapDispatch.swift:4-11` (`RoadmapAction`), `:22-30` (`action(for:...)`)
- Modify: `codepet/Models/RoadmapBoardCopy.swift` (append two copy helpers)
- Modify: `codepet/Views/Roadmap/RoadmapView.swift:193-210` (`dispatch`)
- Test: `codepetTests/RoadmapDispatchTests.swift`, `codepetTests/RoadmapBoardCopyTests.swift`

**Interfaces:**
- Consumes: `RoadmapGating.blocker(for:in:)` (Task 1)
- Produces:
  - `RoadmapAction.showBlocker` — returned for `.blocked`
  - `RoadmapBoardCopy.waitingOn(_ blockerTitle: String, lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.notPlannedYet(_ lang: AppLanguage) -> String` (used by Task 6's rails)

- [ ] **Step 1: Write the failing tests**

Replace `testActionPerStatus` in `codepetTests/RoadmapDispatchTests.swift` and append one test:

```swift
    func testActionPerStatus() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo), .run)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsYou), .walkThrough)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsApproval), .approve)
        XCTAssertEqual(RoadmapDispatch.action(for: .done), .openDeliverable)
        XCTAssertEqual(RoadmapDispatch.action(for: .blocked), .showBlocker)
    }

    /// `.showBlocker` is a redirect, not a destination — the blocker's OWN action decides
    /// whether the founder lands in chat.
    func testShowBlockerDoesNotItselfNavigate() {
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.showBlocker))
    }
```

Append to `codepetTests/RoadmapBoardCopyTests.swift`, inside the existing class:

```swift
    func testWaitingOnNamesTheBlockerInBothLanguages() {
        XCTAssertEqual(RoadmapBoardCopy.waitingOn("Talk to 5 users", lang: .en),
                       "Waiting on: Talk to 5 users")
        XCTAssertTrue(RoadmapBoardCopy.waitingOn("Talk to 5 users", lang: .vi)
                        .contains("Talk to 5 users"))
        XCTAssertNotEqual(RoadmapBoardCopy.waitingOn("x", lang: .en),
                          RoadmapBoardCopy.waitingOn("x", lang: .vi))
    }

    func testNotPlannedYetIsNonEmptyAndDistinctPerLanguage() {
        XCTAssertFalse(RoadmapBoardCopy.notPlannedYet(.en).isEmpty)
        XCTAssertFalse(RoadmapBoardCopy.notPlannedYet(.vi).isEmpty)
        XCTAssertNotEqual(RoadmapBoardCopy.notPlannedYet(.en), RoadmapBoardCopy.notPlannedYet(.vi))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapDispatchTests -only-testing:codepetTests/RoadmapBoardCopyTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `type 'RoadmapAction' has no member 'showBlocker'`.

- [ ] **Step 3: Write the implementation**

In `codepet/Models/RoadmapDispatch.swift`, add the case to `RoadmapAction` and remap `.blocked`:

```swift
enum RoadmapAction: Equatable {
    case run              // Codepet can do it (cloud) — output streams into chat
    case walkThrough      // needs the founder — the walkthrough streams into chat
    case approve          // needs approval — resolves in place
    case openDeliverable  // done — opens the deliverable sheet in place
    case editCode         // Engineering + a linked project — the local coding agent
    case showBlocker      // locked — redirect to the step that's holding this one up
    case none             // nothing to do (no blocker resolved — a dangling dep or a cycle)
}
```

```swift
        case .blocked:       return .showBlocker
```

In `codepet/Models/RoadmapBoardCopy.swift`, append inside the enum:

```swift
    /// Why a locked card is locked, naming the step that must land first — so a locked card
    /// explains itself in the peek without the founder opening chat.
    static func waitingOn(_ blockerTitle: String, lang: AppLanguage) -> String {
        lang == .vi ? "Đang chờ: \(blockerTitle)" : "Waiting on: \(blockerTitle)"
    }

    /// A phase the plan never filled. Its rail says this instead of a bare 0/0, which reads
    /// like a bug rather than an absence.
    static func notPlannedYet(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chưa lên kế hoạch" : "Not planned yet"
    }
```

In `codepet/Views/Roadmap/RoadmapView.swift`, replace `dispatch(_:)` with:

```swift
    /// Route a task tap through the pure `RoadmapDispatch` rule, then follow the two
    /// streaming actions (run, walk-through) to chat, where their output appears.
    /// Approve and open-deliverable resolve in place and do not navigate.
    ///
    /// `depth` guards the one recursive case: tapping a LOCKED card redirects to the step
    /// holding it up (`.showBlocker`). One hop only — a dangling or cyclic graph must not
    /// bounce forever, and a blocker that is itself blocked has nothing useful to offer.
    private func dispatch(_ task: RoadmapTask, depth: Int = 0) {
        let action = RoadmapDispatch.action(for: RoadmapEngine.status(for: task, in: tasks),
                                            isEngineering: task.dept == "eng",
                                            projectLinked: companyStore.activeProjectLink != nil)
        switch action {
        case .run:              Task { await companyStore.runTask(task, language: lang) }
        case .walkThrough:      Task { await companyStore.walkThroughTask(task, language: lang) }
        case .approve:          Task { await companyStore.approveTask(id: task.id) }
        case .openDeliverable:  openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
        case .editCode:
            companyStore.codingRunAnchorId = nil   // no chat ask → card at transcript bottom
            companyStore.codingRun.propose(ask: RoadmapDispatch.editCodeAsk(for: task),
                                           plannedFiles: 2, needsBash: false,
                                           link: companyStore.activeProjectLink)
        case .showBlocker:
            guard depth == 0, let blocker = RoadmapGating.blocker(for: task, in: tasks) else { break }
            dispatch(blocker, depth: 1)
        case .none:             break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.dockCollapsed = false }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapDispatchTests -only-testing:codepetTests/RoadmapBoardCopyTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|TEST" | tail -10
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Models/RoadmapDispatch.swift codepet/Models/RoadmapBoardCopy.swift \
        codepet/Views/Roadmap/RoadmapView.swift codepetTests/
git commit -F - <<'EOF'
feat(roadmap): tapping a locked card starts the step that's blocking it

A locked card used to no-op, which is a dead end. .blocked now dispatches
.showBlocker, and the view redirects one hop to RoadmapGating.blocker — the same
task the beacon points at — so the founder always has an action.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Rail geometry + a collapsible layout engine

**Files:**
- Modify: `codepet/Models/RoadmapLayout.swift` (`RoadmapGeometry`, `RoadmapLayout`, `RoadmapLayoutEngine.layout`)
- Test: `codepetTests/RoadmapLayoutTests.swift` (append a `MARK: rails` section)

**Interfaces:**
- Consumes: `RoadmapPhase`, `RoadmapTask`
- Produces:
  - `RoadmapGeometry.railW: CGFloat = 44`, `RoadmapGeometry.railGap: CGFloat = 20`
  - `RoadmapGeometry.boardWidth(expanded: Set<RoadmapPhase>) -> CGFloat`
  - `struct PhaseRail: Identifiable { let phase: RoadmapPhase; let x: CGFloat; let done: Int; let total: Int; var id: String }`
  - `RoadmapLayout.rails: [PhaseRail]`
  - `RoadmapLayoutEngine.layout(_ tasks: [RoadmapTask], hasRoot: Bool = true, expanded: Set<RoadmapPhase>? = nil) -> RoadmapLayout` — `nil` means every phase is a full column (today's behaviour)

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/RoadmapLayoutTests.swift`, inside the existing class (it defines the `t(...)` and `node(...)` helpers):

```swift
    // MARK: rails (collapsed phases)

    func testRailGeometryConstants() {
        XCTAssertEqual(RoadmapGeometry.railW, 44)
        XCTAssertEqual(RoadmapGeometry.railGap, 20)
    }

    /// The all-expanded width must equal the pre-rails formula exactly — the last column
    /// contributes no trailing gap.
    func testBoardWidthAllExpandedMatchesTheOriginalFormula() {
        let all = Set(RoadmapPhase.allCases)
        let lastX = 232 + CGFloat(RoadmapPhase.allCases.count - 1) * 268
        XCTAssertEqual(RoadmapGeometry.boardWidth(expanded: all), lastX + 208 + 16)
    }

    func testBoardWidthShrinksWithEachCollapsedPhase() {
        let all = Set(RoadmapPhase.allCases)
        let three: Set<RoadmapPhase> = [.find, .foundation, .build]
        // 3 card columns + 3 rails, less the TRAILING gap (a rail's 20, not a column's 60),
        // plus bottomPad → 1224. Note it isn't `all - 3*268 + 3*64`: the trailing gap the
        // formula drops changes with the last slot's kind.
        XCTAssertEqual(RoadmapGeometry.boardWidth(expanded: three), 232 + 3 * 268 + 3 * 64 - 20 + 16)
        XCTAssertLessThan(RoadmapGeometry.boardWidth(expanded: three),
                          RoadmapGeometry.boardWidth(expanded: all))
    }

    func testCollapsedPhasesBecomeRailsAndDropTheirCards() {
        let tasks = [t("a", .find), t("b", .build)]
        let l = RoadmapLayoutEngine.layout(tasks, expanded: [.find])
        XCTAssertEqual(l.nodes.map(\.id), ["a"])                       // b's phase collapsed
        XCTAssertEqual(l.columns.map(\.phase), [.find])                // headers only for columns
        XCTAssertEqual(l.rails.map(\.phase), [.foundation, .build, .ship, .launch, .grow])
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.total, 1)  // the rail still counts
        XCTAssertEqual(l.rails.first { $0.phase == .foundation }?.total, 0)
    }

    func testRailXAccumulatesAfterTheExpandedColumn() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)], expanded: [.find])
        XCTAssertEqual(node(l, "a").x, 232)                            // unchanged start
        XCTAssertEqual(l.rails.first { $0.phase == .foundation }?.x, 232 + 208 + 60)  // 500
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.x, 500 + 44 + 20)        // 564
    }

    func testExpandedColumnAfterARailStartsPastIt() {
        // find expanded, foundation collapsed, build expanded
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)],
                                           expanded: [.find, .build])
        XCTAssertEqual(node(l, "b").x, 232 + 268 + 64)                 // 564
    }

    /// Height and lanes come from the EXPANDED columns only, so a collapsed phase's extra
    /// department lane can't inflate the board the founder is looking at.
    func testHeightIgnoresCollapsedPhases() {
        let tasks = [t("a", .find, dept: "eng"),
                     t("b", .build, dept: "mkt"), t("c", .build, dept: "design")]
        // BUILD collapsed → its two department lanes leave the board entirely: one row.
        let expandedOnly = RoadmapLayoutEngine.layout(tasks, expanded: [.find])
        XCTAssertEqual(expandedOnly.size.height, 40 + 64 + 16)         // 120
        // BUILD expanded → eng and design share lane 0 (their columns don't clash), mkt takes
        // lane 1, so the board grows by exactly one row pitch.
        let withBuild = RoadmapLayoutEngine.layout(tasks, expanded: [.find, .build])
        XCTAssertEqual(withBuild.size.height, 40 + 96 + 64 + 16)       // 216
    }

    func testLayoutWidthMatchesBoardWidth() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)], expanded: [.find])
        XCTAssertEqual(l.size.width, RoadmapGeometry.boardWidth(expanded: [.find]))
    }

    /// The default (nil) must be indistinguishable from the pre-rails engine.
    func testDefaultExpandedIsEveryPhase() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)])
        XCTAssertTrue(l.rails.isEmpty)
        XCTAssertEqual(l.columns.map(\.phase), RoadmapPhase.allCases)
        XCTAssertEqual(node(l, "b").x, 232 + 2 * 268)
    }

    /// A dependency into a collapsed phase draws no edge (its node doesn't exist) and must
    /// NOT resurrect the target as a root entry point.
    func testEdgeIntoACollapsedPhaseIsDroppedWithoutBecomingARootEdge() {
        let tasks = [t("a", .find), t("b", .build, deps: ["a"])]
        let l = RoadmapLayoutEngine.layout(tasks, expanded: [.build])
        XCTAssertTrue(l.edges.isEmpty)                                  // a has no node
        XCTAssertTrue(l.rootEdges.isEmpty)                              // b still depends on a
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapLayoutTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `type 'RoadmapGeometry' has no member 'railW'`.

- [ ] **Step 3: Add the rail geometry**

In `codepet/Models/RoadmapLayout.swift`, append to `enum RoadmapGeometry`:

```swift
    // ── Collapsed phases ─────────────────────────────────────────────────────────────
    /// A collapsed phase's slim rail: wide enough for a vertical label, narrow enough that
    /// three of them cost less than one card column.
    static let railW: CGFloat = 44
    static let railGap: CGFloat = 20

    /// Total board width for a given column mix — THE one width formula, shared by the layout
    /// engine (which must agree with what it draws) and `RoadmapFocus` (which must predict it
    /// before laying anything out). Columns accumulate their trailing gap; the last one's is
    /// replaced by `bottomPad`.
    static func boardWidth(expanded: Set<RoadmapPhase>) -> CGFloat {
        var cursor = rootRight + rootGap
        var lastGap: CGFloat = 0
        for phase in RoadmapPhase.allCases {
            let isColumn = expanded.contains(phase)
            cursor += isColumn ? (cardW + colGap) : (railW + railGap)
            lastGap = isColumn ? colGap : railGap
        }
        return cursor - lastGap + bottomPad
    }
```

Add the rail model above `struct RoadmapLayout`:

```swift
/// A collapsed phase — a slim clickable rail instead of a column of cards. `done`/`total` keep
/// the counts visible so a collapsed phase never hides progress.
struct PhaseRail: Identifiable {
    let phase: RoadmapPhase
    let x: CGFloat
    let done: Int
    let total: Int
    var id: String { phase.rawValue }
}
```

Add the field to `RoadmapLayout` (after `columns`):

```swift
    /// Collapsed phases, in phase order. Disjoint from `columns` — every phase is one or the other.
    let rails: [PhaseRail]
```

- [ ] **Step 4: Make the engine collapse phases**

In `RoadmapLayoutEngine`, replace `colLeft(_:hasRoot:)` with an x-table builder and update `layout`. Replace the whole `static func layout(...)` signature line and the geometry helpers as follows.

Delete:

```swift
    private static func colLeft(_ col: Int, hasRoot: Bool) -> CGFloat {
        let start = hasRoot ? RoadmapGeometry.rootRight + RoadmapGeometry.rootGap : RoadmapGeometry.rootLeft
        return start + CGFloat(col) * (RoadmapGeometry.cardW + RoadmapGeometry.colGap)
    }
```

Add in its place:

```swift
    /// Left edge of every phase's slot, accumulated left to right: a full card column for an
    /// expanded phase, a slim rail for a collapsed one. Replaces the old fixed-pitch
    /// `col * (cardW + colGap)` — with rails the pitch is no longer uniform.
    private static func slotX(expanded: Set<RoadmapPhase>, hasRoot: Bool) -> [RoadmapPhase: CGFloat] {
        var cursor = hasRoot ? RoadmapGeometry.rootRight + RoadmapGeometry.rootGap
                             : RoadmapGeometry.rootLeft
        var out: [RoadmapPhase: CGFloat] = [:]
        for phase in RoadmapPhase.allCases {
            out[phase] = cursor
            cursor += expanded.contains(phase) ? (RoadmapGeometry.cardW + RoadmapGeometry.colGap)
                                               : (RoadmapGeometry.railW + RoadmapGeometry.railGap)
        }
        return out
    }
```

Change the signature and the first lines of `layout` from:

```swift
    static func layout(_ tasks: [RoadmapTask], hasRoot: Bool = true) -> RoadmapLayout {
        let phases = RoadmapPhase.allCases
        var colOf: [RoadmapPhase: Int] = [:]
        for (i, p) in phases.enumerated() { colOf[p] = i }
```

to:

```swift
    /// `expanded` = the phases rendering as full card columns; every other phase collapses to a
    /// rail and its tasks are left out of `nodes` entirely (no cards, no lanes, no height).
    /// `nil` means every phase is a column — the pre-rails behaviour, which the existing
    /// geometry tests pin.
    static func layout(_ tasks: [RoadmapTask], hasRoot: Bool = true,
                       expanded: Set<RoadmapPhase>? = nil) -> RoadmapLayout {
        let expandedSet = expanded ?? Set(RoadmapPhase.allCases)
        let phases = RoadmapPhase.allCases
        let xOf = slotX(expanded: expandedSet, hasRoot: hasRoot)
        // Only tasks in an expanded phase get cards; the rest are represented by their rail.
        let shown = tasks.filter { expandedSet.contains($0.phase) }
        var colOf: [RoadmapPhase: Int] = [:]
        for (i, p) in phases.enumerated() { colOf[p] = i }
```

Now switch the lane/placement passes from `tasks` to `shown`, and every `colLeft(...)` to `xOf[...]`:

- In the department-lane pass, change `for t in tasks {` to `for t in shown {`.
- In the node-placement pass, change `for task in tasks {` to `for task in shown {` and the `PositionedNode` construction to:

```swift
            let n = PositionedNode(task: task, col: col, row: row,
                                   x: xOf[task.phase] ?? 0, y: rowTop(row))
```

- In the edge pass, change `for t in tasks {` to `for t in shown {`. (`nodeById` only holds shown nodes, so an edge crossing into a collapsed phase is skipped by the existing `guard let a = nodeById[dep]`.)
- `let ids = Set(tasks.map { $0.id })` stays over ALL tasks — that is what keeps a dependency on a collapsed task from fail-opening into a root edge.

Replace the size + columns block:

```swift
        let maxRows = max(1, nodes.map { $0.row + 1 }.max() ?? 1)
        let height = RoadmapGeometry.top + CGFloat(maxRows - 1) * RoadmapGeometry.rowPitch
            + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        let width = colLeft(phases.count - 1, hasRoot: hasRoot)
            + RoadmapGeometry.cardW + RoadmapGeometry.bottomPad

        let currentPhase = currentId.flatMap { nodeById[$0]?.task.phase }
        let columns: [PhaseColumn] = phases.enumerated().map { i, p in
            let list = tasks.filter { $0.phase == p }
            return PhaseColumn(phase: p, x: colLeft(i, hasRoot: hasRoot),
                               done: list.filter { $0.done }.count, total: list.count,
                               current: p == currentPhase)
        }
```

with:

```swift
        let maxRows = max(1, nodes.map { $0.row + 1 }.max() ?? 1)
        let height = RoadmapGeometry.top + CGFloat(maxRows - 1) * RoadmapGeometry.rowPitch
            + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        let width = RoadmapGeometry.boardWidth(expanded: expandedSet)

        // The current phase is read from the WHOLE task set, not just the shown ones: the
        // beacon's phase may be collapsed, and its rail should still flag as current.
        let currentPhase = currentId.flatMap { id in tasks.first { $0.id == id }?.phase }
        var columns: [PhaseColumn] = []
        var rails: [PhaseRail] = []
        for p in phases {
            let list = tasks.filter { $0.phase == p }
            let done = list.filter { $0.done }.count
            if expandedSet.contains(p) {
                columns.append(PhaseColumn(phase: p, x: xOf[p] ?? 0, done: done,
                                           total: list.count, current: p == currentPhase))
            } else {
                rails.append(PhaseRail(phase: p, x: xOf[p] ?? 0, done: done, total: list.count))
            }
        }
```

Finally include `rails` in the return:

```swift
        return RoadmapLayout(nodes: nodes, edges: edges, columns: columns, rails: rails,
                             root: root, rootEdges: rootEdges,
                             size: CGSize(width: width, height: height))
```

The root-edge pass keeps iterating `nodes` (shown only) — unchanged.

- [ ] **Step 5: Run the layout tests**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapLayoutTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|TEST" | tail -20
```

Expected: `** TEST SUCCEEDED **` — the new rail tests plus every pre-existing geometry test (`testColumnXIsRootRightPlusGapThenPitch`, `testCanvasSizeFromLastColumnAndLowestRow`, `testEmptyTasksStillGivesRootAndSixColumns`, `testColumnsAreEveryPhaseInOrderWithCounts`) still green via the `nil` default.

- [ ] **Step 6: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Models/RoadmapLayout.swift codepetTests/RoadmapLayoutTests.swift
git commit -F - <<'EOF'
feat(roadmap): collapsible phases — rails, accumulated slot x, one width formula

A phase outside the expanded set renders as a 44pt rail instead of a 268pt
column, and its tasks leave nodes/lanes/height entirely, so the board's height
is the height of what's actually shown. RoadmapGeometry.boardWidth is now the
single width formula, shared with the focus rule. expanded: nil keeps the
pre-rails behaviour the web-parity tests pin.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: `RoadmapFocus` — which phases get full columns

**Files:**
- Create: `codepet/Models/RoadmapFocus.swift`
- Test: `codepetTests/RoadmapFocusTests.swift`

**Interfaces:**
- Consumes: `RoadmapGating.openPhases(_:)`, `RoadmapGating.states(_:)` (Task 1); `RoadmapGeometry.boardWidth(expanded:)` (Task 4)
- Produces: `RoadmapFocus.expanded(tasks: [RoadmapTask], availableWidth: CGFloat, userExpanded: Set<RoadmapPhase> = []) -> Set<RoadmapPhase>`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/RoadmapFocusTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapFocusTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who, dept: "eng")
    }
    /// Tasks in all six phases, with a founder-owned step holding FIND shut so the working
    /// phase is FIND and the preview is FOUNDATION.
    private func fullBoard() -> [RoadmapTask] {
        [t("f", .find, who: .you), t("d", .foundation), t("b", .build),
         t("s", .ship), t("l", .launch), t("g", .grow)]
    }

    func testNoTasksExpandsNothing() {
        XCTAssertTrue(RoadmapFocus.expanded(tasks: [], availableWidth: 4000).isEmpty)
    }

    func testWideEnoughExpandsEveryPopulatedPhase() {
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: 4000)
        XCTAssertEqual(e, Set(RoadmapPhase.allCases))
    }

    func testEmptyPhasesAreNeverExpanded() {
        // Only FIND has tasks — the other five stay rails no matter how much room there is.
        let e = RoadmapFocus.expanded(tasks: [t("f", .find)], availableWidth: 4000)
        XCTAssertEqual(e, [.find])
    }

    /// The tightest budget still shows the phase the founder is working in — never an
    /// all-rails board with nowhere to act.
    func testWorkingPhaseSurvivesAnImpossibleBudget() {
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: 0)
        XCTAssertEqual(e, [.find])
    }

    func testGrowsFromTheWorkingPhaseThenThePreview() {
        // Budget for exactly two card columns + four rails.
        let two = RoadmapGeometry.boardWidth(expanded: [.find, .foundation])
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: two)
        XCTAssertEqual(e, [.find, .foundation])
    }

    func testResultAlwaysFitsTheBudgetWhenItCan() {
        let three = RoadmapGeometry.boardWidth(expanded: [.find, .foundation, .build])
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: three)
        XCTAssertLessThanOrEqual(RoadmapGeometry.boardWidth(expanded: e), three)
        XCTAssertEqual(e.count, 3)
    }

    func testUserExpandedIsHonouredEvenPastTheBudget() {
        let two = RoadmapGeometry.boardWidth(expanded: [.find, .foundation])
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: two, userExpanded: [.grow])
        XCTAssertTrue(e.contains(.grow))       // never dropped
        XCTAssertTrue(e.contains(.find))       // the working phase still survives
    }

    func testUserExpandedIgnoresEmptyPhases() {
        let e = RoadmapFocus.expanded(tasks: [t("f", .find)], availableWidth: 4000,
                                      userExpanded: [.grow])
        XCTAssertFalse(e.contains(.grow))      // nothing there to expand
    }

    func testWorkingPhaseIsTheLastOpenPopulatedPhase() {
        // No founder-owned work anywhere → every phase is open; the working edge is the LAST
        // populated one, so the tail of the journey is what gets the room.
        let tasks = [t("f", .find), t("g", .grow)]
        let one = RoadmapGeometry.boardWidth(expanded: [.grow])
        XCTAssertEqual(RoadmapFocus.expanded(tasks: tasks, availableWidth: one), [.grow])
    }

    func testDeterministicForAFixedWidth() {
        let w = RoadmapGeometry.boardWidth(expanded: [.find, .foundation, .build])
        let a = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: w)
        let b = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: w)
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapFocusTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'RoadmapFocus' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/RoadmapFocus.swift`:

```swift
// codepet/Models/RoadmapFocus.swift
import CoreGraphics

/// Which phases earn a full card column, given the room available. Everything else collapses to
/// a rail (`PhaseRail`). Pure and deterministic so the board's shape is testable without a view.
///
/// The rule is progressive disclosure, not truncation: whatever collapses is still visible as a
/// labelled, counted, clickable rail, so nothing is silently hidden.
enum RoadmapFocus {
    static func expanded(tasks: [RoadmapTask], availableWidth: CGFloat,
                         userExpanded: Set<RoadmapPhase> = []) -> Set<RoadmapPhase> {
        // Only phases that actually hold tasks can be columns — an empty phase has nothing to
        // show and would spend 208pt saying so.
        let populated = RoadmapPhase.allCases.filter { p in tasks.contains { $0.phase == p } }
        guard let first = populated.first else { return [] }

        let open = RoadmapGating.openPhases(tasks)
        // The working edge: the last OPEN phase with tasks — where the beacon lives.
        let working = populated.last { open.contains($0) } ?? first
        let states = RoadmapGating.states(tasks)
        let preview = populated.first { states[$0] == .preview }

        // Never dropped: the phase the founder is working in, plus anything they opened by hand.
        var keep: Set<RoadmapPhase> = [working]
        keep.formUnion(userExpanded.filter(populated.contains))

        // Then outward from the working phase — the preview first (the one look-ahead), then
        // nearest-first, earlier phases winning ties.
        let workingIndex = populated.firstIndex(of: working) ?? 0
        var order: [RoadmapPhase] = []
        if let preview, !keep.contains(preview) { order.append(preview) }
        order += populated.enumerated()
            .filter { !keep.contains($0.element) && $0.element != preview }
            .sorted { a, b in
                let da = abs(a.offset - workingIndex), db = abs(b.offset - workingIndex)
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)

        for phase in order {
            var trial = keep
            trial.insert(phase)
            if RoadmapGeometry.boardWidth(expanded: trial) <= availableWidth { keep = trial }
        }
        return keep
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapFocusTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|TEST" | tail -15
```

Expected: `** TEST SUCCEEDED **`, 10 tests executed.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Models/RoadmapFocus.swift codepetTests/RoadmapFocusTests.swift
git commit -F - <<'EOF'
feat(roadmap): RoadmapFocus — expand outward from the working phase

Picks the phases that get full card columns for a given width: the working
phase and any the founder opened by hand always survive, then the preview,
then nearest-first until the budget runs out. Everything else stays a visible,
counted rail — progressive disclosure, not silent truncation.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: The board — real centring, rails, locked headers

**Files:**
- Modify: `codepet/Views/Overview/RoadmapBoardView.swift`

**Interfaces:**
- Consumes: `RoadmapFocus.expanded(tasks:availableWidth:userExpanded:)` (Task 5), `RoadmapLayoutEngine.layout(_:hasRoot:expanded:)` + `PhaseRail` + `RoadmapGeometry.railW/railGap` (Task 4), `RoadmapGating.states(_:)` + `.blocker(for:in:)` (Task 1), `RoadmapBoardCopy.waitingOn(_:lang:)` + `.notPlannedYet(_:)` (Task 3)
- Produces: nothing consumed by later tasks

SwiftUI views aren't unit-testable here — every decision this task renders was already pinned by the pure tests in Tasks 1, 4 and 5. Verification is a build plus the visual checklist in Task 7.

- [ ] **Step 1: Delete the measured-centring machinery**

In `codepet/Views/Overview/RoadmapBoardView.swift` remove, in full:

- the `avail` state and its doc comment (lines 20-21: `/// Measured height of the scroll area, for the fit-to-height scale.` + `@State private var avail: CGFloat = 0`)
- `private var layout: RoadmapLayout { RoadmapLayoutEngine.layout(tasks) }` (line 36) — the layout now depends on the measured width, so it's computed in `body`
- `headerTrailingAllowance` and its doc comment (lines 45-49)
- `scale(for:)` and its doc comment (lines 51-59)
- `boardWidth(_:)` and its doc comment (lines 61-66)

Add next to the remaining state:

```swift
    /// Phases the founder expanded by hand from their rail. Session-only: the width rule
    /// (`RoadmapFocus`) picks the default set on every layout pass.
    @State private var userExpanded: Set<RoadmapPhase> = []

    /// Page gutters for the board. Leading is wider than the page's 24pt because the root
    /// node's aura bleeds 26pt past its own box — at 24pt the glow clips on the window edge.
    private static let insetLeading: CGFloat = 26
    private static let insetTrailing: CGFloat = 24
```

- [ ] **Step 2: Replace `body`**

```swift
    var body: some View {
        // The board's own allotment, read directly instead of stored: `@State` + `onAppear`
        // measurement is what produced the old bug — a stale viewport centred the map against
        // a container ~200pt taller than the visible one, so it sat low and ran off the bottom.
        GeometryReader { g in
            let budget = max(0, g.size.width - Self.insetLeading - Self.insetTrailing)
            let expandedPhases = RoadmapFocus.expanded(tasks: tasks, availableWidth: budget,
                                                       userExpanded: userExpanded)
            let l = RoadmapLayoutEngine.layout(tasks, expanded: expandedPhases)
            let states = RoadmapGating.states(tasks)

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.headerGap) {
                        phaseHeaders(l, states: states)
                        diagram(l)
                    }
                    .padding(.leading, Self.insetLeading)
                    .padding(.trailing, Self.insetTrailing)
                    // Centring as LAYOUT, not arithmetic: the content grows to the viewport
                    // when it's smaller (and centres inside it) and overflows into scroll when
                    // it's bigger. Nothing to measure, nothing to go stale.
                    .frame(minWidth: g.size.width, minHeight: g.size.height, alignment: .center)
                }
                .onScrollGeometryChange(for: ScrollEdgeState.self) { geo in
                    ScrollEdgeState(
                        left: geo.contentOffset.x > 0.5,
                        right: geo.contentOffset.x < geo.contentSize.width - geo.containerSize.width - 0.5)
                } action: { _, new in
                    canScrollLeft = new.left
                    canScrollRight = new.right
                }
                .overlay(alignment: .leading) { edgeFade(leading: true, visible: canScrollLeft) }
                .overlay(alignment: .trailing) { edgeFade(leading: false, visible: canScrollRight) }
                .onAppear {
                    // Open framed on the current move — the founder shouldn't hunt for it.
                    if let id = currentId { frame(proxy, id: id) }
                    prevStates = statusMap(tasks)
                    prevCurrentId = currentId
                }
                .onChange(of: currentId) { _, new in
                    // First visit: `tasks` generates asynchronously, so `currentId` is nil at
                    // `onAppear` and the board never got framed above. Catch it the moment the
                    // current move first resolves — and again on each advance, as web does.
                    guard let id = new, framedForId != id else { return }
                    frame(proxy, id: id)
                }
                .onChange(of: tasks) { _, new in detectAdvances(new) }
            }
        }
    }
```

- [ ] **Step 3: Replace `phaseHeaders` with a phase-state-aware version**

```swift
    // Left-aligned to each column's card edge (web places them at `c.x`), in their own
    // 28pt row above the diagram. A locked phase wears a lock and drops the accent, so the
    // header row alone tells the founder how far the window reaches.
    private func phaseHeaders(_ l: RoadmapLayout, states: [RoadmapPhase: PhaseState]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.columns) { c in
                let state = states[c.phase] ?? .later
                let locked = state == .preview || state == .later
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(CodepetTheme.mutedText)
                        } else if state == .complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(RoadmapPalette.done)
                        }
                        Text(c.phase.label(lang).uppercased())
                            .font(CodepetTheme.inter(10.5)).tracking(1.47)   // web .14em at 10.5px
                            .foregroundColor(c.current ? accent : CodepetTheme.mutedText)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(c.current ? CodepetTokens.accentTint : CodepetTokens.well))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(c.current ? CodepetTokens.accentLine : CodepetTheme.hairline,
                                lineWidth: 1))
                    Text("\(c.done)/\(c.total)")
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                .fixedSize()
                .offset(x: c.x, y: 0)
            }
        }
        .frame(width: l.size.width, height: Self.headerRow, alignment: .topLeading)
    }
```

- [ ] **Step 4: Render the rails in `diagram`**

Change `diagram(_:)`'s `ZStack` so rails draw under the cards, and add the rail view. Insert immediately after the `if let r = l.root { rootNode(r) }` line:

```swift
            ForEach(l.rails) { r in
                rail(r, height: l.size.height)
                    .position(x: r.x + RoadmapGeometry.railW / 2, y: l.size.height / 2)
            }
```

Add these two members below `diagram`:

```swift
    /// A collapsed phase: a slim rail carrying its name vertically plus its done/total, click
    /// to expand. An unplanned phase says so rather than showing a bare 0/0, which reads like
    /// a bug instead of an absence.
    private func rail(_ r: PhaseRail, height: CGFloat) -> some View {
        let empty = r.total == 0
        return Button { toggleExpanded(r.phase) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(CodepetTokens.well)
                RoundedRectangle(cornerRadius: 10).stroke(CodepetTheme.hairline, lineWidth: 1)
                VStack(spacing: 12) {
                    if !empty {
                        Text("\(r.done)/\(r.total)")
                            .font(CodepetTheme.inter(10)).monospacedDigit()
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    // `rotationEffect` doesn't change layout, so the label claims its
                    // horizontal size inside the 44pt frame and draws rotated — which is
                    // exactly what we want; `fixedSize` stops it wrapping first.
                    Text(r.phase.label(lang).uppercased())
                        .font(CodepetTheme.inter(10.5)).tracking(1.47)
                        .foregroundColor(CodepetTheme.mutedText.opacity(empty ? 0.6 : 1))
                        .lineLimit(1).fixedSize()
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: RoadmapGeometry.railW, height: height)
        }
        .buttonStyle(.plain)
        .help(empty ? "\(r.phase.label(lang)) · \(RoadmapBoardCopy.notPlannedYet(lang))"
                    : "\(r.phase.label(lang)) · \(r.done)/\(r.total)")
    }

    private func toggleExpanded(_ phase: RoadmapPhase) {
        if userExpanded.contains(phase) { userExpanded.remove(phase) } else { userExpanded.insert(phase) }
    }
```

- [ ] **Step 5: Connect each rail to the column before it**

In `edgeCanvas(_:)`, append inside the `Canvas` closure after the critical-path strokes:

```swift
            // A short stub into each rail, so a collapsed phase still reads as part of one
            // continuous journey rather than a detached sidebar.
            let midY = (l.size.height / 2).rounded()
            for r in l.rails {
                ctx.stroke(path([CGPoint(x: r.x - RoadmapGeometry.railGap, y: midY),
                                 CGPoint(x: r.x, y: midY)]),
                           with: .color(accent.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
```

- [ ] **Step 6: Make the peek name the blocker**

In `peekText(_:status:isCurrent:)`, insert immediately before the `switch status {` line:

```swift
        if status == .blocked, let b = RoadmapGating.blocker(for: task, in: tasks) {
            parts.append(RoadmapBoardCopy.waitingOn(b.title, lang: lang))
        }
```

- [ ] **Step 7: Build**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. If the compiler reports the `body` closure is too complex to type-check, extract `let expandedPhases`/`let l`/`let states` into a small `private struct BoardShape` computed by a helper function — do not delete the centring frame.

- [ ] **Step 8: Commit**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git add codepet/Views/Overview/RoadmapBoardView.swift
git commit -F - <<'EOF'
feat(overview): centre the board for real, collapse far phases to rails

Centring was arithmetic over a stored measurement (@State avail → padTop) that
resolved ~200pt taller than the visible viewport, so the map sat low and ran off
the bottom. It's now layout: GeometryReader + minWidth/minHeight + .center, with
nothing to go stale. Adds 26/24pt gutters so the root node's aura stops clipping,
renders collapsed phases as clickable rails, locks preview/later headers, and
lets a locked card's peek name the step it's waiting on.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: Verify end to end

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything
- Produces: a signed, running app confirmed against the original screenshot's defects

- [ ] **Step 1: Full test suite**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|Failing tests|Executed|TEST" | tail -20
```

Expected: `** TEST SUCCEEDED **`, executed count = Task 0 baseline + 41 new test methods (15 `RoadmapGatingTests`, 3 `RoadmapEngineTests`, 1 `RoadmapDispatchTests` + 1 rewritten, 2 `RoadmapBoardCopyTests`, 10 `RoadmapFocusTests`, 10 `RoadmapLayoutTests`). Recount from the summary line and report the real number rather than assuming.

- [ ] **Step 2: Launch the signed build**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
APP=$(xcodebuild -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
ps aux | grep "[c]odepet.app" || open "$APP/codepet.app"
```

If a sibling session's instance is already running, **do not kill it** — report and stop; a build-only verification is acceptable.

- [ ] **Step 3: Visual checklist on the Overview page**

Compare against the reported defects:

1. The map is vertically centred in the board area — the empty band above it matches the band below.
2. The **codepet** root node's glow is fully visible; nothing clips on the left window edge.
3. At fullscreen with the copilot collapsed, no horizontal scrolling is needed; far phases show as slim rails.
4. `LAUNCH` / `RUN & GROW` (empty on this account) are rails, not blank 268pt columns. Hovering one says "Not planned yet".
5. FIND's header is accent-tinted; FOUNDATION and later wear a lock glyph.
6. Exactly **one** card offers `Start`/`Add your input` — the beacon. Build/Ship cards are dimmed with "Needs earlier steps"; the two Foundation drafts still say `Review`.
7. Hovering a locked card shows a `Waiting on: …` line; clicking it starts that blocker instead of doing nothing.
8. Clicking a rail expands it into a full column; clicking again collapses it.
9. Open the copilot dock (⌘B): the board reflows to fewer columns and stays centred.

- [ ] **Step 4: Report**

Report the executed-test count, each checklist item's result, and anything that needed a deviation from the plan. If items 1-3 don't hold, capture a screenshot before changing anything — the framing hypothesis is the one part of this plan derived from measurement rather than from a test.

- [ ] **Step 5: Push the branch and open a PR**

```bash
cd /Users/monatruong/Developer/codepet-roadmap-focus
git push -u origin feat/overview-roadmap-focus
gh pr create --base main --title "Overview roadmap: rolling phase window, focus rails, real centring" --body "$(cat <<'EOF'
## What

The Overview map read as a flat list sliding off the bottom-left of the window. Two independent causes:

- **Framing.** The board centred itself with arithmetic over a stored measurement (`@State avail` → `padTop`) that resolved ~200pt taller than the visible viewport. Centring is now layout — `GeometryReader` + `minWidth/minHeight` + `.center` — with nothing to go stale. Adds 26/24pt gutters so the root node's aura stops clipping on the window edge.
- **Sequencing.** No card on a generated board has a resolvable dependency, so `status` returned `codepetCanDo` for eight tasks at 0% and the connectors were all root fan-out. A rolling phase window (`RoadmapGating`) now derives sequencing client-side: a phase opens once every earlier phase has no task left that needs the founder. Codepet-owned leftovers deliberately don't block, so the founder is never stuck behind work Codepet owes them.

Far phases collapse to slim clickable rails (`RoadmapFocus` picks the set by width budget), so the board fits the pane instead of forcing horizontal scroll, and empty phases stop spending 268pt each to say `0/0`.

## Notes

- No Firestore migration and no Cloud Function deploy: gating is derived, so existing boards read correctly immediately.
- `nextMoves` is confined to the open window, so the chat's parallel fan-out returns fewer tasks early on. That's the intended reading of the window.
- The `generateRoadmap` CF still under-produces chained deps and leaves Launch/Grow empty for new users — tracked as a follow-up, out of scope here.

Spec: `docs/superpowers/specs/2026-08-03-overview-roadmap-focus-design.md`
Plan: `docs/superpowers/plans/2026-08-03-overview-roadmap-focus.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for the executor

- **One rule, every surface.** Gating lives in `RoadmapEngine.status`, so `TasksView`, `Department.summaries`, `ChatLandingState` and the chat fan-out all inherit it. If a surface looks wrong after Task 2, fix the fixture or the surface — never special-case the rule.
- **No recursion.** `RoadmapGating.needsFounder` must stay structural. Calling `RoadmapEngine.status` from inside gating deadlocks the two definitions.
- **`expanded: nil` is load-bearing.** It's what keeps the web-parity layout tests green. Don't "clean it up" into a required parameter.
- `RoadmapGeometry.boardWidth` is the only width formula. If the engine and `RoadmapFocus` ever disagree, the board will oscillate between column counts on resize.
- **Deviation from the spec's file table:** `RoadmapCardView.swift` needs no change. The card already renders "Needs earlier steps" for `.blocked` via `RoadmapBoardCopy.quietLabel`; the `Waiting on: …` line belongs in the board's hover peek (Task 6, Step 6), which is where the rest of the card's explanatory copy already lives.
