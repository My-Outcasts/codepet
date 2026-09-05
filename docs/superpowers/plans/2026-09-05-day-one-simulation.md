# Day-One Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second Murror demo state that starts from nothing and answers a solo founder's nine
questions in order, one per link, landing exactly on today's mid-flight board.

**Architecture:** One shared task list with a linear `dependsOn` chain through the nine tasks the
simulation runs. `DemoProject.murrorDayOne` is that list with those nine `done: false` and
`filed: []`; `DemoProject.murror` is unchanged. A new beat table names its nine task ids
explicitly and runs each one, then approves it. Approving files it, and `UpstreamWork.assemble`
then credits it to the next link with no new carry-forward code.

**The chain edges carry the hand-off, NOT the ordering.** An earlier draft of this plan claimed
`.runBeacon` would walk the chain because `RoadmapEngine.nextStep` follows dependencies. That is
false and was measured false: `nextStep` sorts every dependency-satisfied open task by (phase
order, array position), and Murror has other open tasks — `mur-pricing`, `mur-clinician`,
`mur-site`, `mur-screens` — that unblock mid-chain and sit EARLIER in the array. Simulated against
the real fixture, the beacon drifts at step 3 and never recovers. The script therefore names its
ids. The edges remain load-bearing for `assemble`, which is what renders each card's credit line.

**Tech Stack:** Swift 5, SwiftUI, XCTest. Xcode 26.2, macOS. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## ⚠️ Blocking decision before Task 1

**Task 1 adds a product capability that does not exist**, and the founder should approve it
before it is built.

Measured: `mur-interviews` is `who: .you`. `toggleTaskDone` marks such a task done but **files
nothing**, and `approveTask(id:)` requires `tasks[i].draft`, which nothing on a founder-only path
ever sets. So today there is **no way to complete a founder-only task and end up with an
artifact**.

Three consequences, all of which break the spec as written:
1. Day one's `filed` would end at **8**, not 9, so it would not land on mid-flight.
2. `UpstreamWork.assemble` reads filed deliverables, so **link 2 would get no credit line** from
   link 1 — the first hand-off, the one that teaches the mechanic, would be missing.
3. The spec's sentence *"the deliverable is filed from what she records"* describes a path that
   is not there.

**Task 1 builds it** — `recordFounderOutcome(taskId:body:kind:)`. It is ~25 lines and is a real
product feature, not demo scaffolding: it is how any founder ever finishes "talk to 12 people".

**If the founder would rather not expand scope**, the alternative is to start day one with
`mur-interviews` already done and filed — "from the one thing only you could do" rather than from
zero — which needs no new code but is a different story from the one approved.

Do not begin until this is answered.

## Global Constraints

- Scheme **`codepet`** (lowercase). New `.swift` files need **no** project-file edit
  (`PBXFileSystemSynchronizedRootGroup`).
- Test: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`
- **Never read pass/fail from `xcodebuild`'s exit code.** The XCTest host crashes on
  `@MainActor ObservableObject` dealloc, so a clean checkout exits 65. Read
  `Executed N tests, with M failures` from the tail. **A zero executed-count means the suite did
  not run** — it is not a pass.
- **Never run two `xcodebuild` invocations at once.** They lock `build.db` and both report 0/0.
- `CompanyStore` touching Firestore in a test **traps** (does not throw) when `FirebaseApp` is
  unconfigured. Always construct it with injected savers — `tasksSaver`, `librarySaver`,
  `decisionsSaver`, `firstApprovalSaver` — returning `true`.
- `DemoProject.murror` (mid-flight) keeps its exact `filed` list, its eight runnable tasks and its
  one `who: .you` open task. 17 suites assert on it.
- `DemoProject.codepet` is untouched.
- **No new deliverable content.** `deliverable(for:)` matches keywords against the title, so
  identical titles resolve to the nine artifacts that already exist.
- Multiline Swift strings strip indentation relative to the **closing** `"""`. Misaligning it
  injects leading spaces into every continued line.

## File Structure

| File | Responsibility |
| --- | --- |
| `codepet/Managers/CompanyStore.swift` | +`recordFounderOutcome(taskId:body:kind:)` (Task 1) |
| `codepet/Demo/DemoProjectMurror.swift` | the nine gain linear `dependsOn` edges (Task 2) |
| `codepet/Demo/DemoProjectMurrorDayOne.swift` | **new** — the day-one `DemoProject` value (Task 2) |
| `codepet/Demo/DemoProject.swift` | `all` gains the third entry (Task 2) |
| `codepet/Demo/DayOneScript.swift` | **new** — the nine-link beat table (Task 3) |
| `codepet/Demo/MockFlowScript.swift` | +`case recordFounderTask` on `Intent` (Task 3) |
| `codepet/Demo/MockFlowPlayer.swift` | plays a chosen script; handles the new case (Task 3) |
| `codepetTests/FounderOutcomeTests.swift` | **new** (Task 1) |
| `codepetTests/DayOneFixtureTests.swift` | **new** (Task 2) |
| `codepetTests/DayOneScriptTests.swift` | **new** (Task 3) |
| `codepetTests/DayOneBridgeTests.swift` | **new** (Task 4) |

---

### Task 1: Record a founder-only task's outcome

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/FounderOutcomeTests.swift`

**Interfaces:**
- Consumes: `approveTask(id:) async` and `company.tasks[i].draft` (both exist).
- Produces: `func recordFounderOutcome(taskId: String, body: String, kind: DeliverableKind) async`
  — used by Task 3's `.recordFounderTask` beat.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/FounderOutcomeTests.swift`:

```swift
// codepetTests/FounderOutcomeTests.swift
import XCTest
@testable import codepet

/// Completing a task Codepet cannot run must still leave an artifact behind.
///
/// `toggleTaskDone` marks such a task done and files NOTHING, and `approveTask` needs a draft
/// that no founder-only path ever sets. So "talk to 12 people" could be finished and the
/// dependency arrow pointing at it still read as unproduced — which is what
/// `UpstreamWork.firstUnfiled` documents as the case worth chaining.
@MainActor
final class FounderOutcomeTests: XCTestCase {

    /// Savers are injected because a `CompanyStore` reaching Firestore with no `FirebaseApp`
    /// TRAPS — it does not throw — and takes the whole test host with it.
    private func makeStore(tasks: [RoadmapTask]) -> CompanyStore {
        let store = CompanyStore(
            tasksSaver: { _, _ in true },
            librarySaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true })
        store.company.tasks = tasks
        return store
    }

    private func founderTask(id: String = "t-you", done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: "Talk to 12 people about being lonely",
                    detail: "", phase: .find, who: .you, done: done, dept: "mkt")
    }

    func testRecordingFilesADeliverableAndMarksTheTaskDone() async {
        let store = makeStore(tasks: [founderTask()])
        await store.recordFounderOutcome(taskId: "t-you", body: "Nine of twelve said the same thing.",
                                         kind: .doc)
        XCTAssertEqual(store.company.library.count, 1)
        let filed = store.company.library.first
        XCTAssertEqual(filed?.sourceTaskId, "t-you")
        XCTAssertEqual(filed?.title, "Talk to 12 people about being lonely")
        XCTAssertEqual(filed?.body, "Nine of twelve said the same thing.")
        XCTAssertTrue(store.company.tasks[0].done, "recording is what completes it")
    }

    /// The artifact must be reachable the way every other filed artifact is, or the Library
    /// and `UpstreamWork.assemble` will both miss it.
    func testTheFiledWorkResolvesThroughRoadmapEngine() async {
        let store = makeStore(tasks: [founderTask()])
        await store.recordFounderOutcome(taskId: "t-you", body: "b", kind: .doc)
        let d = RoadmapEngine.deliverable(for: store.company.tasks[0], in: store.company.library)
        XCTAssertNotNil(d, "assemble reads exactly this lookup")
    }

    /// Codepet's own tasks have a run path that already files. Routing them through here too
    /// would give one task two ways to be completed and two artifacts.
    func testItRefusesATaskCodepetCanRun() async {
        let codepetTask = RoadmapTask(id: "t-run", title: "Ship an email capture", detail: "",
                                      phase: .build, who: .draft, done: false, dept: "eng")
        let store = makeStore(tasks: [codepetTask])
        await store.recordFounderOutcome(taskId: "t-run", body: "b", kind: .doc)
        XCTAssertTrue(store.company.library.isEmpty, "only `.you` tasks are recorded this way")
        XCTAssertFalse(store.company.tasks[0].done)
    }

    /// Pressing it twice must not file the same work twice — the same double-file hazard
    /// `fileApproval` guards with its `done` check.
    func testRecordingTwiceFilesOnce() async {
        let store = makeStore(tasks: [founderTask()])
        await store.recordFounderOutcome(taskId: "t-you", body: "b", kind: .doc)
        await store.recordFounderOutcome(taskId: "t-you", body: "b again", kind: .doc)
        XCTAssertEqual(store.company.library.count, 1)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FounderOutcomeTests 2>&1 | tail -25`

Expected: compile failure — `value of type 'CompanyStore' has no member 'recordFounderOutcome'`.

- [ ] **Step 3: Implement it**

In `codepet/Managers/CompanyStore.swift`, directly ABOVE `func approveTask(id:)`:

```swift
    /// File the outcome of a task Codepet cannot run.
    ///
    /// **The gap this closes.** `who == .you` work — an interview round, a conversation, a
    /// clinician reading a crisis path — has no run path, so `approveTask` finds no draft and
    /// `toggleTaskDone` marks it done leaving nothing behind. That is precisely the state
    /// `UpstreamWork.firstUnfiled` calls out: a dependency arrow pointing at nothing readable.
    /// Every downstream run then loses the credit line it should have had.
    ///
    /// Goes through `approveTask` rather than filing directly, so a recorded outcome takes the
    /// same path an approved draft does — one place marks a task done, appends to the library
    /// and stamps the first approval.
    func recordFounderOutcome(taskId: String, body: String, kind: DeliverableKind) async {
        guard let i = company.tasks.firstIndex(where: { $0.id == taskId }),
              company.tasks[i].who == .you,
              !company.tasks[i].done else { return }
        company.tasks[i].draft = Deliverable(kind: kind, title: company.tasks[i].title,
                                             body: body, sourceTaskId: taskId)
        await approveTask(id: taskId)
    }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FounderOutcomeTests 2>&1 | tail -25`

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Prove the guard is real**

Temporarily change `company.tasks[i].who == .you` to `true`. Re-run.
Expected: `testItRefusesATaskCodepetCanRun` FAILS. Restore the line and re-run to green.

A guard nobody has watched go red is a guard nobody has tested.

- [ ] **Step 6: Sweep the neighbours this touches**

`approveTask` and `fileApproval` are shared. Run the suites that exercise them:

```bash
for s in FirstApprovalNoteTests DemoProjectFiledTests UpstreamWorkTests UpstreamCreditTests; do
  echo "== $s"
  xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
    -only-testing:codepetTests/$s 2>&1 | grep -E 'Executed [0-9]+ tests'
done
```

Expected: every line reports `0 failures` and a NON-ZERO executed count.

- [ ] **Step 7: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/FounderOutcomeTests.swift
git commit -F - <<'MSG'
feat: a founder-only task can leave an artifact behind

`who: .you` work had no way to finish with a deliverable. `toggleTaskDone`
marks it done and files nothing; `approveTask` needs a draft nothing sets.
So "talk to 12 people" could be complete and every task depending on it
still read the arrow as pointing at nothing — the exact case
`UpstreamWork.firstUnfiled` documents, and the reason the first hand-off
in the day-one simulation had no credit line.

Routed through `approveTask` so a recorded outcome and an approved draft
file by the same path.
MSG
```

---

### Task 2: The chain edges and the day-one fixture

**Files:**
- Modify: `codepet/Demo/DemoProjectMurror.swift` (the nine tasks' `dependsOn`)
- Create: `codepet/Demo/DemoProjectMurrorDayOne.swift`
- Modify: `codepet/Demo/DemoProject.swift` (`static var all`)
- Test: `codepetTests/DayOneFixtureTests.swift`

**Interfaces:**
- Consumes: `DemoProject.murror`, `murrorTasks`, `murrorDeliverables`,
  `DemoProject.murrorDepartmentReplies`, `murrorRoomFrames(ask:)` — all existing.
- Produces: `DemoProject.murrorDayOne` (id `"murror-day-one"`) and
  `DemoProject.dayOneChain: [String]` — the ordered nine task ids, consumed by Tasks 3 and 4.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DayOneFixtureTests.swift`:

```swift
// codepetTests/DayOneFixtureTests.swift
import XCTest
@testable import codepet

/// Day one is mid-flight with two fields changed. Asserting that here is what stops the two
/// drifting into different stories — the bridge claim is only true while they share a board.
final class DayOneFixtureTests: XCTestCase {

    private var dayOne: DemoProject { .murrorDayOne }
    private var midFlight: DemoProject { .murror }

    /// The ordered nine, and the shape of the run.
    func testTheChainIsNineTasksCoveringAllEightDepartments() {
        XCTAssertEqual(DemoProject.dayOneChain,
                       ["mur-interviews", "mur-landscape", "mur-notfor", "mur-brand",
                        "mur-stack", "mur-unitcost", "mur-crisis", "mur-deletion", "mur-rhythm"])
        let byId = Dictionary(uniqueKeysWithValues: midFlight.tasks.map { ($0.id, $0) })
        let depts = Set(DemoProject.dayOneChain.compactMap { byId[$0]?.dept })
        XCTAssertEqual(depts, Set(DepartmentCatalog.roster.map(\.key)),
                       "nine tasks must cover all eight departments")
    }

    /// **The bridge's precondition.** The nine the simulation runs are exactly the nine
    /// mid-flight has filed, or running them cannot land on mid-flight.
    func testTheChainIsExactlyMidFlightsFiledSet() {
        XCTAssertEqual(Set(DemoProject.dayOneChain), Set(midFlight.filed))
    }

    func testDayOneStartsFromNothing() {
        XCTAssertTrue(dayOne.filed.isEmpty, "day one has no filed work")
        XCTAssertTrue(dayOne.library().isEmpty, "and therefore an empty Library")
        for id in DemoProject.dayOneChain {
            let t = dayOne.tasks.first { $0.id == id }
            XCTAssertEqual(t?.done, false, "\(id) must be open on day one")
        }
    }

    /// One source, two states: same ids, same titles, same order, same departments.
    func testTheTwoBoardsDifferOnlyInDoneAndFiled() {
        XCTAssertEqual(dayOne.tasks.map(\.id), midFlight.tasks.map(\.id))
        XCTAssertEqual(dayOne.tasks.map(\.title), midFlight.tasks.map(\.title))
        XCTAssertEqual(dayOne.tasks.map(\.dept), midFlight.tasks.map(\.dept))
        XCTAssertEqual(dayOne.tasks.map(\.dependsOn), midFlight.tasks.map(\.dependsOn),
                       "the chain edges live in the SHARED list, not in one state")
        XCTAssertEqual(dayOne.brief.projectName, midFlight.brief.projectName)
    }

    /// The chain must actually be a line, or `nextStep` will not walk it in order.
    func testEachLinkDependsOnItsPredecessor() {
        let byId = Dictionary(uniqueKeysWithValues: dayOne.tasks.map { ($0.id, $0) })
        for (i, id) in DemoProject.dayOneChain.enumerated() where i > 0 {
            let prev = DemoProject.dayOneChain[i - 1]
            XCTAssertTrue(byId[id]?.dependsOn.contains(prev) == true,
                          "\(id) must depend on \(prev) or the beacon will skip it")
        }
    }

    /// On day one exactly ONE task is startable, and it is link 1.
    func testOnlyTheFirstLinkIsOpenOnDayOne() {
        let startable = dayOne.tasks.filter {
            let s = RoadmapEngine.status(for: $0, in: dayOne.tasks)
            return s == .codepetCanDo || s == .needsYou
        }
        XCTAssertEqual(startable.map(\.id), ["mur-interviews"])
    }

    /// **The 17 suites' premise.** New edges among tasks that are all `done` must change
    /// nothing about mid-flight: `status` returns `.done` before it consults `depsSatisfied`.
    func testMidFlightIsUnchangedByTheNewEdges() {
        let runnable = midFlight.tasks.filter {
            RoadmapEngine.status(for: $0, in: midFlight.tasks) == .codepetCanDo
        }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)), Set(DepartmentCatalog.roster.map(\.key)))
        XCTAssertEqual(RoadmapEngine.nextStep(midFlight.tasks)?.id, "mur-site",
                       "the tour's beacon must still point at the landing page")
        XCTAssertEqual(midFlight.library().count, 9)
    }

    func testDayOneIsSelectable() {
        XCTAssertTrue(DemoProject.all.contains { $0.id == "murror-day-one" })
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DayOneFixtureTests 2>&1 | tail -25`

Expected: compile failure — no `murrorDayOne`, no `dayOneChain`.

- [ ] **Step 3: Add the chain edges to the shared task list**

In `codepet/Demo/DemoProjectMurror.swift`, add each link's predecessor to its `dependsOn`,
**keeping every existing id**. The edges are additive:

| task | `dependsOn` becomes |
| --- | --- |
| `mur-interviews` | `[]` (unchanged — link 1 starts the chain) |
| `mur-landscape` | `["mur-interviews"]` |
| `mur-notfor` | `["mur-landscape"]` |
| `mur-brand` | `["mur-landscape", "mur-notfor"]` (keeps its existing edge) |
| `mur-stack` | `["mur-brand"]` |
| `mur-unitcost` | `["mur-stack"]` |
| `mur-crisis` | `["mur-unitcost"]` |
| `mur-deletion` | `["mur-crisis"]` |
| `mur-rhythm` | `["mur-deletion"]` |

Leave the other nine tasks' `dependsOn` exactly as they are. Add this comment above the block:

```swift
            // ── THE DAY-ONE CHAIN ───────────────────────────────────────────────────────────
            // These nine carry a linear `dependsOn` so `RoadmapEngine.nextStep` walks them in
            // the order the day-one script asks its nine questions. The edges are SAFE for
            // mid-flight because all nine are `done` there, and `status` returns `.done` before
            // it consults `depsSatisfied` — no status, no beacon and no runnable count moves.
            //
            // `mur-brand` KEEPS its existing `mur-landscape` edge. Replacing rather than adding
            // would quietly rewrite mid-flight's roadmap.
```

- [ ] **Step 4: Create the day-one fixture**

Create `codepet/Demo/DemoProjectMurrorDayOne.swift`:

```swift
// codepet/Demo/DemoProjectMurrorDayOne.swift
#if DEBUG
import Foundation

/// Murror on day one — the same company before any of it had been done.
///
/// **Why a second state and not a second company.** The demo's claim is that running the nine
/// questions gets you to the board the tour then walks. That is only true while both states read
/// from one task list: `tasks` here is `murrorTasks` with nine `done` flags cleared, and nothing
/// else. Brief, deliverables, department replies and room frames are shared by reference.
///
/// **No deliverable content is written here.** `deliverable(for:)` matches keywords against the
/// title, so these nine tasks resolve to the nine artifacts mid-flight already files.
extension DemoProject {

    /// The nine questions, in the order a founder actually has them.
    ///
    /// Marketing appears at both ends of the opening — "is this real?" then "has someone built
    /// it?" — which is why nine tasks cover eight departments.
    static let dayOneChain = [
        "mur-interviews",   // Marketing · Nova   — is this a real problem, or just mine?
        "mur-landscape",    // Marketing · Nova   — has someone already built this?
        "mur-notfor",       // Sales · Nova       — so who is it not for?
        "mur-brand",        // Design · Luna      — what should it feel like?
        "mur-stack",        // Engineering · Byte — what do I build it on?
        "mur-unitcost",     // Finance · Crash    — what will this cost me a month?
        "mur-crisis",       // Support · Sage     — what if someone's struggling at 2am?
        "mur-deletion",     // Legal · Glitch     — am I in trouble for holding their words?
        "mur-rhythm",       // Operations · Glitch— how do I ship without breaking it?
    ]

    static let murrorDayOne = DemoProject(
        id: "murror-day-one",
        brief: DemoProject.murror.brief,
        tasks: DemoProject.murror.tasks.map { task in
            guard dayOneChain.contains(task.id) else { return task }
            var open = task
            open.done = false
            return open
        },
        deliverables: murrorDeliverables,
        departmentReplies: DemoProject.murrorDepartmentReplies,
        // Nothing filed. The Library fills as she approves, which is the point.
        filed: [],
        roomFrames: murrorRoomFrames(ask:)
    )
}
#endif
```

- [ ] **Step 5: Make it selectable**

In `codepet/Demo/DemoProject.swift`, change:

```swift
    static var all: [DemoProject] { [.codepet, .murror] }
```

to:

```swift
    static var all: [DemoProject] { [.codepet, .murror, .murrorDayOne] }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DayOneFixtureTests 2>&1 | tail -25`

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 7: Sweep every suite that asserts on Murror**

The new edges run straight through `DemoProjectMurrorTests`' 71 assertions. This is the task
that adds the risk, so this is the task that sweeps for it — not a later one.

```bash
for s in DemoProjectMurrorTests DemoProjectEightDepartmentsTests DemoProjectParityTests \
         DemoProjectFiledTests DemoProjectTests MockFlowTests UpstreamWorkTests \
         UpstreamCreditTests PrototypeModeIsolationTests; do
  echo "== $s"
  xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
    -only-testing:codepetTests/$s 2>&1 | grep -E 'Executed [0-9]+ tests'
done
```

Expected: every line `0 failures`, every executed count NON-ZERO.

If a `DemoProjectMurrorTests` assertion pins an exact `dependsOn` array, update that assertion to
the new value — the edges are intended. Do NOT weaken it to a `contains` check; an exact
assertion on fixture shape is the thing catching drift.

- [ ] **Step 8: Commit**

```bash
git add codepet/Demo/DemoProjectMurror.swift codepet/Demo/DemoProjectMurrorDayOne.swift \
        codepet/Demo/DemoProject.swift codepetTests/DayOneFixtureTests.swift
git commit -F - <<'MSG'
feat(demo): Murror on day one, from one task list

The same nine tasks mid-flight has filed, with their `done` flags cleared
and nothing in the library. Brief, deliverables, replies and room frames
are shared by reference, so the two states cannot tell different stories.

The nine gain a linear `dependsOn` chain, which is what makes
`RoadmapEngine.nextStep` walk them in the order the questions are asked.
The edges are safe for mid-flight: all nine are `done` there, and `status`
returns `.done` before it consults `depsSatisfied`.

No deliverable content written — identical titles resolve to the nine
artifacts that already exist.
MSG
```

---

### Task 3: The nine-link script

**Files:**
- Create: `codepet/Demo/DayOneScript.swift`
- Modify: `codepet/Demo/MockFlowScript.swift` (one `Intent` case)
- Modify: `codepet/Demo/MockFlowPlayer.swift` (play a chosen script; handle the new case)
- Test: `codepetTests/DayOneScriptTests.swift`

**Interfaces:**
- Consumes: `DemoProject.dayOneChain` (Task 2),
  `CompanyStore.recordFounderOutcome(taskId:body:kind:)` (Task 1),
  `MockFlowScript.Beat` and `MockFlowScript.Intent` (existing).
- Produces: `DayOneScript.beats: [MockFlowScript.Beat]` and
  `MockFlowPlayer.script: [MockFlowScript.Beat]`.

**Duration:** the beat table below totals **65.8s**, not the spec's rough "~40 seconds" — that
estimate was made before the captions were written and counted run time only, not reading time.
65.8s is the number to hold; `testTheWholeSequenceStaysUnderNinetySeconds` is the budget.

**Why the script names its task ids.** `.runBeacon` resolves `RoadmapEngine.nextStep`, which
sorts ALL dependency-satisfied open tasks by (phase order, array position) — it does not follow
the chain. Simulated against the real fixture, a `.runBeacon`-driven script drifts to
`mur-pricing` at step 3, `mur-clinician` at step 4, and never returns to the chain. Two new
intents, `.runTask(String)` and `.recordFounderTask(taskId:body:)`, name what they act on.

This also removes a hidden coupling: a script whose order emerged from array positions in a
different file would break silently whenever a task was inserted. `testTheScriptRunsExactlyTheDayOneChain`
pins the order to `DemoProject.dayOneChain`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DayOneScriptTests.swift`:

```swift
// codepetTests/DayOneScriptTests.swift
import XCTest
@testable import codepet

/// The script's shape. Content lives in the fixture; what is guarded here is that the sequence
/// asks nine questions, runs nine links and approves all nine.
final class DayOneScriptTests: XCTestCase {

    private var beats: [MockFlowScript.Beat] { DayOneScript.beats }

    /// Link 1 is founder-only, so it is RECORDED, not run. The other eight are run and approved.
    func testItHasOneRecordEightRunsAndEightApprovals() {
        var record = 0, runs = 0, approvals = 0
        for b in beats {
            switch b.intent {
            case .recordFounderTask: record += 1
            case .runTask: runs += 1
            case .approveNewestDraft: approvals += 1
            default: break
            }
        }
        XCTAssertEqual(record, 1, "only `mur-interviews` is the founder's own work")
        XCTAssertEqual(runs, 8, "the other eight links are Codepet runs")
        XCTAssertEqual(approvals, 8, "each run is approved; the record files itself")
    }

    /// **The guard that replaces an assumption.** An earlier draft used `.runBeacon` and trusted
    /// `RoadmapEngine.nextStep` to follow the dependency chain. It does not — it sorts every
    /// dependency-satisfied open task by (phase order, array position), and simulated against
    /// the real fixture it drifted to `mur-pricing` at step 3. The script now names its ids, and
    /// this pins them to the chain so the two cannot diverge.
    func testTheScriptRunsExactlyTheDayOneChain() {
        var acted: [String] = []
        for b in beats {
            switch b.intent {
            case .recordFounderTask(let id, _): acted.append(id)
            case .runTask(let id): acted.append(id)
            default: break
            }
        }
        XCTAssertEqual(acted, DemoProject.dayOneChain,
                       "the script's order must BE the chain, not resemble it")
    }

    /// Every run beat must be followed by its approval before the next link runs — otherwise the
    /// next department reads an unfiled predecessor and its credit line comes back empty.
    func testEveryRunIsApprovedBeforeTheNextRun() {
        var awaitingApproval = false
        for b in beats {
            switch b.intent {
            case .runTask(let id):
                XCTAssertFalse(awaitingApproval, "a run started before \(id)'s predecessor was approved")
                awaitingApproval = true
            case .approveNewestDraft:
                awaitingApproval = false
            default: break
            }
        }
        XCTAssertFalse(awaitingApproval, "the last run is never approved")
    }

    /// A beat whose intent has no handler is a silent no-op — it plays as a caption over a
    /// screen where nothing happens, and nothing fails.
    func testEveryIntentUsedHasAHandler() {
        let handled: Set<String> = ["hold", "mode", "go", "newChat", "say", "runBeacon",
                                    "approveNewestDraft", "convene", "linkDemoFolder",
                                    "codeRun", "confirmCodeRun", "approveCodeRun",
                                    "walkthroughFounderTask", "recordFounderTask", "runTask"]
        for b in beats {
            let name = String(describing: b.intent).prefix(while: { $0 != "(" })
            XCTAssertTrue(handled.contains(String(name)),
                          "`\(name)` has no case in MockFlowPlayer")
        }
    }

    /// Each link needs long enough to read a question and watch a run. Measured: a run is
    /// ~6 exec steps at 420ms plus a 260ms settle.
    func testEveryRunBeatIsLongEnoughToWatch() {
        for b in beats where isRun(b.intent) {
            XCTAssertGreaterThanOrEqual(b.seconds, 2.6,
                                        "a run beat shorter than the run itself cuts it off")
        }
    }

    /// It must stay watchable. The 24-beat tour holds a 100s ceiling for the same reason.
    func testTheWholeSequenceStaysUnderNinetySeconds() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThan(total, 90, "a \(Int(total))s simulation is one nobody watches twice")
        XCTAssertGreaterThan(total, 30, "nine links cannot honestly play in under 30s")
    }

    /// The opening must be the founder's own words, not a feature tour.
    func testItOpensOnNotKnowingWhereToStart() throws {
        let first = try XCTUnwrap(beats.first)
        XCTAssertTrue(first.caption.lowercased().contains("where to start"),
                      "the opening states the problem this simulation exists for: \(first.caption)")
    }

    /// The ending hands the next move back rather than taking it.
    func testItEndsPointingAtTheLandingPage() throws {
        let last = try XCTUnwrap(beats.last)
        XCTAssertTrue(last.caption.lowercased().contains("landing page"),
                      "the bridge to the tour must be named: \(last.caption)")
    }

    private func isRun(_ i: MockFlowScript.Intent) -> Bool {
        if case .runTask = i { return true }
        return false
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DayOneScriptTests 2>&1 | tail -25`

Expected: compile failure — no `DayOneScript`, no `.recordFounderTask`.

- [ ] **Step 3: Add the intent case**

In `codepet/Demo/MockFlowScript.swift`, immediately after `case walkthroughFounderTask`:

```swift
        /// Run ONE named task.
        ///
        /// **Not `.runBeacon`.** `RoadmapEngine.nextStep` sorts every dependency-satisfied open
        /// task by (phase order, array position), so it does not follow a dependency chain.
        /// Measured against the Murror fixture, a beacon-driven day-one script drifts to
        /// `mur-pricing` at step 3 and never comes back. A scripted sequence has to say what it
        /// is running.
        case runTask(String)
        /// Record what came back from the founder's own work, which files it.
        ///
        /// `walkthroughFounderTask` ASKS about a `.you` task; this one completes it. Both are
        /// needed: the demo has to show Codepet declining to do the interviews AND has to end
        /// up with the interviews filed, because everything downstream reads them.
        case recordFounderTask(taskId: String, body: String)
```

- [ ] **Step 4: Handle it, and let the player take a script**

In `codepet/Demo/MockFlowPlayer.swift`, replace:

```swift
    var beats: [MockFlowScript.Beat] { MockFlowScript.beats }
```

with:

```swift
    /// Which sequence is playing. The 24-beat tour by default; the day-one simulation when the
    /// day-one fixture is selected. A stored property rather than a computed one so a running
    /// player cannot have the script changed under it mid-beat.
    var script: [MockFlowScript.Beat] = DemoProject.current.id == "murror-day-one"
        ? DayOneScript.beats : MockFlowScript.beats
    var beats: [MockFlowScript.Beat] { script }
```

Then add a new case to the `switch intent` block, positioned after `.walkthroughFounderTask`'s
body and before the switch's closing brace. Swift requires the switch stay exhaustive, so
omitting this is a compile error rather than a silent no-op beat:

```swift
        case .runTask(let id):
            store.view = .chat
            // The same three guards `runTask` enforces. A beat that fires on a task already
            // running or drafted would produce a second draft and double the credits.
            guard let task = store.company.tasks.first(where: { $0.id == id }),
                  !task.done, !task.drafted else { return }
            Task { await store.runTask(task, language: language) }
        case .recordFounderTask(let taskId, let body):
            store.view = .chat
            Task { await store.recordFounderOutcome(taskId: taskId, body: body, kind: .doc) }
```

- [ ] **Step 5: Write the script**

Create `codepet/Demo/DayOneScript.swift`:

```swift
// codepet/Demo/DayOneScript.swift
#if DEBUG
import Foundation

/// Day one: the nine questions a solo founder actually has, in the order she has them.
///
/// **Why this exists.** The 24-beat tour opens on a company that already has twelve interviews,
/// a competitive scan and a brand. A founder who does not know where to start has none of those,
/// and that is who this product is for. Measured on the tour: one `.runBeacon` and one
/// `.approveNewestDraft`, so one department of eight produced anything on camera.
///
/// **Why the beats name their task ids.** Each link is a question, a run and an approval. The
/// run is `.runTask(id)`, NOT `.runBeacon`: `RoadmapEngine.nextStep` sorts every
/// dependency-satisfied open task by (phase order, array position) rather than following a
/// chain, and simulated against this fixture a beacon-driven version drifts to `mur-pricing` at
/// step 3 and never returns. `DayOneScriptTests` pins this order to `DemoProject.dayOneChain`.
///
/// The chain's `dependsOn` edges are still load-bearing — they are what `UpstreamWork.assemble`
/// reads to credit each card. They carry the HAND-OFF, not the ordering.
///
/// **The ending is a hand-back, not a finale.** After link 9 the board is mid-flight and the
/// beacon lands on the landing page — where the tour's own `.runBeacon` starts. Her tenth
/// question is the one this simulation refuses to answer for her.
enum DayOneScript {

    static let beats: [MockFlowScript.Beat] = build([
        ("Day one", 4.0, .hold,
         "Mona has a feeling and nothing else — people are lonely and don't know how to reach "
         + "each other. No plan, no brand, no idea where to start. This is the board a founder "
         + "actually begins with: empty."),

        // Link 1 — Marketing · Nova. The founder's own work, and it stays that way.
        ("Is this real?", 4.2, .walkthroughFounderTask,
         "Her first question is whether the problem is real or just hers. Codepet will not "
         + "pretend to run this one — twelve conversations are hers to have — so it prepares "
         + "the guide and says so plainly."),

        ("Is this real?", 3.4, .recordFounderTask(
            taskId: "mur-interviews",
            body: "Nine of twelve described the same evening: they thought of someone, drafted "
            + "something, and never sent it. Two wanted tracking, not company. One found the "
            + "whole idea insulting."),
         "She has the conversations and records what she heard. That is what files it — and "
         + "everything after this reads it."),

        // Link 2 — Marketing · Nova.
        ("Has someone built it?", 3.0, .runTask("mur-landscape"),
         "Second question, and the first one Codepet can take: has someone already built this? "
         + "Nova reads the interviews before answering — the credit line on the card names them."),
        ("Has someone built it?", 2.8, .approveNewestDraft,
         "Approving files it. Nothing was written anywhere until that tap, and the next "
         + "department will read what she just approved."),

        // Link 3 — Sales · Nova.
        ("Who is it not for?", 3.0, .runTask("mur-notfor"),
         "The scan turns up crowded ground, which sharpens the real question: who is this NOT "
         + "for? The one person who found it insulting is worth more here than the nine who "
         + "liked it."),
        ("Who is it not for?", 2.8, .approveNewestDraft,
         "A disqualifier list is a strange thing to be pleased about, and it is the first "
         + "artifact that makes the next four decisions easy."),

        // Link 4 — Design · Luna.
        ("What should it feel like?", 3.0, .runTask("mur-brand"),
         "Now that she knows who it is for and who it is not, Luna can shape how it feels. "
         + "A different department, a different pet, reading the two artifacts before it."),
        ("What should it feel like?", 2.8, .approveNewestDraft,
         "Four questions in, and each answer has been built on the last rather than started "
         + "from the brief again."),

        // Link 5 — Engineering · Byte.
        ("What do I build it on?", 3.0, .runTask("mur-stack"),
         "The first question with a bill attached. Byte reads the direction and decides what "
         + "the app runs on — and whether anything a person writes ever leaves their device."),
        ("What do I build it on?", 2.8, .approveNewestDraft,
         "That decision sets the running cost, which is why Finance is next and not first."),

        // Link 6 — Finance · Crash.
        ("What does it cost me?", 3.0, .runTask("mur-unitcost"),
         "Crash cannot price anything without knowing what it runs on, so this question could "
         + "not have been asked earlier. Cost per active user, from the stack just chosen."),
        ("What does it cost me?", 2.8, .approveNewestDraft,
         "A number she can hold against a price — the first artifact that constrains rather "
         + "than describes."),

        // Link 7 — Support · Sage.
        ("A bad night", 3.2, .runTask("mur-crisis"),
         "The question a consumer app about loneliness cannot avoid: what happens when someone "
         + "is genuinely struggling at 2am. Sage writes what the app says, when, and what it "
         + "refuses to handle."),
        ("A bad night", 2.8, .approveNewestDraft,
         "Written down as policy, not left to a prompt. This is the artifact the board's one "
         + "founder-only task later asks a clinician to read."),

        // Link 8 — Legal · Glitch.
        ("Am I in trouble?", 3.0, .runTask("mur-deletion"),
         "She is now holding people's private words. Glitch reads the crisis policy and the "
         + "stack decision, and turns them into a promise: one tap, permanent, no email."),
        ("Am I in trouble?", 2.8, .approveNewestDraft,
         "The promise comes before the privacy policy that formalises it — which is still "
         + "sitting on her board, unwritten."),

        // Link 9 — Operations · Glitch.
        ("How do I ship it?", 3.0, .runTask("mur-rhythm"),
         "The last question of the first week: how does any of this reach anyone without "
         + "breaking. A weekly rhythm the launch checklist will later assume."),
        ("How do I ship it?", 2.8, .approveNewestDraft,
         "Nine questions, eight departments, nine artifacts — and every one of them traces "
         + "back to a task on her roadmap."),

        ("What's next is yours", 3.6, .go(.library),
         "This is what a week looks like when every answer builds on the last. She started "
         + "with a feeling and no plan."),

        ("What's next is yours", 4.0, .go(.roadmap),
         "And the beacon has already moved on to her tenth question — how do people hear about "
         + "it? Codepet does not answer that one here. It points at the landing page and waits."),
    ])

    /// Numbers the beats so `id` cannot drift from position — the same shape `MockFlowScript`
    /// uses, and for the same reason.
    private static func build(_ raw: [(String, Double, MockFlowScript.Intent, String)])
        -> [MockFlowScript.Beat] {
        raw.enumerated().map { i, r in
            MockFlowScript.Beat(id: i, chapter: r.0, seconds: r.1, intent: r.2, caption: r.3)
        }
    }
}
#endif
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DayOneScriptTests 2>&1 | tail -25`

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 7: Confirm the tour did not move**

`MockFlowPlayer` now chooses a script, so the default path must be proven unchanged.

```bash
for s in MockFlowScriptTests MockFlowTests; do
  echo "== $s"
  xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
    -only-testing:codepetTests/$s 2>&1 | grep -E 'Executed [0-9]+ tests'
done
```

Expected: `0 failures`, non-zero counts. The tour is still 24 beats and 84.1s.

- [ ] **Step 8: Commit**

```bash
git add codepet/Demo/DayOneScript.swift codepet/Demo/MockFlowScript.swift \
        codepet/Demo/MockFlowPlayer.swift codepetTests/DayOneScriptTests.swift
git commit -F - <<'MSG'
feat(demo): the day-one sequence — nine questions, eight departments

Each link is a question, a run and an approval, and the script names the
task each beat acts on.

It nearly did not. The plan said `.runBeacon` would walk the chain because
`RoadmapEngine.nextStep` follows dependencies. It does not — it sorts every
dependency-satisfied open task by (phase order, array position), and Murror
has open tasks that unblock mid-chain and sit earlier in the array.
Simulated against the real fixture before this was built, a beacon-driven
script drifted to `mur-pricing` at step 3 and never recovered.

Two new intents: `.runTask(id)` and `.recordFounderTask(taskId:body:)`.
`walkthroughFounderTask` ASKS about a `.you` task; the latter completes it,
because the demo has to show Codepet declining to run the interviews AND
end with them filed — all eight links downstream read them.

The chain edges remain load-bearing for `UpstreamWork.assemble`, which
renders each card's credit line. They carry the hand-off, not the order.

Ends by handing back the tenth question rather than answering it.
MSG
```

---

### Task 4: The bridge, asserted end to end

**Files:**
- Create: `codepetTests/DayOneBridgeTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `DemoProject.murrorDayOne`, `DemoProject.dayOneChain` (Task 2),
  `recordFounderOutcome(taskId:body:kind:)` (Task 1).
- Produces: nothing consumed by later tasks.

**Why this is its own task:** the previous three each proved a piece. This proves the claim the
whole thing was built for — that running day one lands on mid-flight — which no single piece can.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DayOneBridgeTests.swift`:

```swift
// codepetTests/DayOneBridgeTests.swift
import XCTest
@testable import codepet

/// **The claim this whole change exists to make.** Run the nine questions on day one and you
/// arrive at the board the 24-beat tour walks — same tasks done, same artifacts filed, same
/// beacon. If this drifts, the two demos are telling different stories about one company.
@MainActor
final class DayOneBridgeTests: XCTestCase {

    /// What each run was actually TOLD to build on, captured off the request.
    private var upstreamSeen: [String: [UpstreamWork]] = [:]

    /// Seeded through `loader` + `hydrate`, because `company` is `private(set)`.
    ///
    /// `decisionExtractor` is not politeness: `fileApproval` spawns a fire-and-forget
    /// `rememberFromApproval` whose default `DecisionsClient.extract` calls `Auth.auth()` and
    /// TRAPS with no `FirebaseApp`. It takes down a LATER test, so the symptom is a zero
    /// executed-count somewhere else entirely. Argument order is fixed by the declaration:
    /// `firstApprovalSaver` comes before `decisionsSaver`.
    private func dayOneStore() async -> CompanyStore {
        let project = DemoProject.murrorDayOne
        let seed = CompanyState(brief: project.brief, departments: [], library: project.library(),
                                stage: .building, companionId: "byte", onboardedAt: Date(),
                                tasks: project.tasks)
        let store = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            // The real run path, answering with the fixture's own authored artifact — so the
            // request this receives was built by `runRequest`/`assemble` for real.
            taskRunner: { req in
                self.upstreamSeen[req.taskId] = req.upstream ?? []
                let entry = project.deliverable(for: req.taskTitle)
                return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                                       body: MockChat.fill(entry.body, title: req.taskTitle))
            },
            decisionExtractor: { _, _ in [] })
        await store.hydrate(companyId: "u")
        return store
    }

    /// Walk the chain the way the script does: record link 1 (founder-only), then RUN and
    /// APPROVE each next link through the store's own API. No `.draft` poking — `company` is
    /// `private(set)`, and driving the real path is what makes this a bridge test at all.
    private func runTheNineQuestions(_ store: CompanyStore) async {
        let project = DemoProject.murrorDayOne
        for id in DemoProject.dayOneChain {
            guard let task = store.company.tasks.first(where: { $0.id == id }) else {
                XCTFail("\(id) missing from the day-one board"); return
            }
            if task.who == .you {
                let entry = project.deliverable(for: task.title)
                await store.recordFounderOutcome(
                    taskId: id, body: MockChat.fill(entry.body, title: task.title), kind: .doc)
            } else {
                await store.runTask(task, language: .en)
                await store.approveTask(id: id)
            }
        }
    }

    func testRunningTheNineLandsOnMidFlight() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)

        let doneIds = Set(store.company.tasks.filter(\.done).map(\.id))
        XCTAssertEqual(doneIds, Set(DemoProject.murror.filed),
                       "the nine done tasks must be mid-flight's nine filed tasks")

        let filedIds = Set(store.company.library.compactMap(\.sourceTaskId))
        XCTAssertEqual(filedIds, Set(DemoProject.murror.filed),
                       "and every one of them left an artifact behind")
        XCTAssertEqual(store.company.library.count, 9)
    }

    /// The hand-off to the tour. After the nine, the beacon is where the tour's `.runBeacon`
    /// starts — which is what makes the two demos one continuous story.
    func testTheBeaconThenPointsAtTheLandingPage() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        XCTAssertEqual(RoadmapEngine.nextStep(store.company.tasks)?.id, "mur-site")
    }

    /// Mid-flight's headline claim has to survive being ARRIVED at, not just declared.
    func testTheResultingBoardHasEightRunnableTasks() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        let tasks = store.company.tasks
        let runnable = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)), Set(DepartmentCatalog.roster.map(\.key)))
    }

    /// **The hand-off, at the mechanism rather than the caption.**
    ///
    /// Asserted on what each run was HANDED, not on the end state. After all nine are filed,
    /// `assemble` would find work for everything — so an after-the-fact check would pass even
    /// if every run had been given nothing at the moment it ran.
    func testEachRunWasHandedItsPredecessorsWork() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)

        // Link 1 is recorded, not run, so the eight runs are links 2-9.
        XCTAssertEqual(upstreamSeen.count, 8, "eight runs should have been made")
        for (i, id) in DemoProject.dayOneChain.enumerated() where i > 0 {
            let carried = upstreamSeen[id] ?? []
            XCTAssertFalse(carried.isEmpty,
                           "\(id) ran with no upstream — its card would credit nobody")
        }
    }

    /// Link 1 is the founder's own work, and link 2 must still be able to read it. This is the
    /// hand-off `recordFounderOutcome` exists to make possible.
    func testTheSecondLinkWasHandedTheFoundersOwnInterviews() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        let carried = upstreamSeen["mur-landscape"] ?? []
        XCTAssertTrue(carried.contains { $0.taskTitle.contains("12 people") },
                      "link 2 must credit the interviews the founder ran herself")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DayOneBridgeTests 2>&1 | tail -25`

Expected: FAIL only if Tasks 1-3 are incomplete. If Tasks 1-3 are done, these should pass on the
first run — they assert composed behaviour, not new code.

- [ ] **Step 3: If `testEachLinkCanReadItsPredecessorsWork` fails, fix the FIXTURE**

`assemble` returns nothing when the predecessor is not in `task.dependsOn`. That is a missing
edge from Task 2, not a bug in `assemble` — repair the `dependsOn` in
`codepet/Demo/DemoProjectMurror.swift` and re-run. **Do not change `UpstreamWork`**; it is out
of scope in the spec and 17 suites depend on it.

- [ ] **Step 4: Run the whole suite once, serially**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "Executed [0-9]+ tests" | tail -3
```

Expected: roughly `Executed 2250+ tests, with 0 failures`. A count near 2233 plus the ~24 tests
this plan adds. **A zero count means it did not run** — check nothing else is building.

- [ ] **Step 5: Write down what must not be broken**

Append to the demo-fixture section of `CLAUDE.md`:

```markdown
### The day-one simulation (`DemoProject.murrorDayOne`)

Day one and mid-flight are ONE task list. Four things break the bridge between them:

1. **Do not give day one its own task array.** It is `murrorTasks` with nine `done` flags
   cleared. Two arrays drift, and `DayOneBridgeTests` is what notices.
2. **Do not remove an existing `dependsOn` id when adding a chain edge.** `mur-brand` keeps its
   `mur-landscape` edge AND gains `mur-notfor`. Replacing rewrites mid-flight's roadmap.
3. **Keep `DemoProject.dayOneChain` equal to `DemoProject.murror.filed`.** The bridge claim is
   that running the nine lands on mid-flight; different sets make it false.
4. **A new `who: .you` task needs a `.recordFounderTask` beat if anything depends on it.**
   `toggleTaskDone` files nothing, so a founder-only task completed any other way leaves the
   dependency arrow pointing at nothing and every downstream credit line empty.
```

- [ ] **Step 6: Commit**

```bash
git add codepetTests/DayOneBridgeTests.swift CLAUDE.md
git commit -F - <<'MSG'
test: running day one lands on mid-flight, asserted end to end

The three previous commits each proved a piece. This proves the claim they
were built for: run the nine questions on the day-one board and you arrive
at the board the 24-beat tour walks — same tasks done, same nine artifacts
filed, beacon on the landing page.

Also asserts the hand-off at the mechanism rather than the caption: every
link after the first must have `UpstreamWork.assemble` return its
predecessor's filed work, including link 2 reading interviews the founder
ran herself.
MSG
```

---

## Verification

After all four tasks:

- [ ] `git log --oneline` shows four commits, one per task
- [ ] Full suite: `Executed 2250+ tests, with 0 failures`, non-zero count
- [ ] `DemoProjectMurrorTests` still passes — mid-flight is unmoved
- [ ] Build and launch:
  `open <app> --args -CODEPET_MOCK_AUTOPLAY YES -CODEPET_DEMO_PROJECT murror-day-one`

**The on-screen check is the founder's**, and it is the only claim no test covers:
1. the board opens with **one** startable task and an **empty** Library
2. Codepet declines to run the interviews and says why
3. each card after that names the department before it — the credit line
4. the Library fills to **9** across eight departments as the nine are approved
5. it ends on the roadmap with the beacon on *Build the Murror landing page*
