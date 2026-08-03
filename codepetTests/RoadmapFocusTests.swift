import XCTest
@testable import codepet

final class RoadmapFocusTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does,
                   done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who, done: done, dept: "eng")
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

    /// The guaranteed set must genuinely EXCEED the budget for this to prove anything — a set
    /// that happens to still fit (e.g. {find, grow}, whose trailing-gap correction shrinks
    /// `boardWidth` because grow is the LAST phase) doesn't exercise the "never dropped" rule at
    /// all. `userExpanded: [.build]` is a MIDDLE phase, so no such shrink applies: {find, build}
    /// costs `boardWidth([.find, .foundation])` (1020) against a budget of
    /// `boardWidth([.find])` (816) — genuinely over budget.
    func testUserExpandedIsHonouredEvenPastTheBudget() {
        let oneColumn: CGFloat = RoadmapGeometry.boardWidth(expanded: [.find])
        let e = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: oneColumn,
                                      userExpanded: [.build])
        XCTAssertTrue(e.contains(.build))      // never dropped, even past the budget
        XCTAssertTrue(e.contains(.find))       // the working phase still survives
        // Prove the budget really was exceeded, not merely satisfied.
        XCTAssertGreaterThan(RoadmapGeometry.boardWidth(expanded: e), oneColumn)
    }

    func testUserExpandedIgnoresEmptyPhases() {
        let e = RoadmapFocus.expanded(tasks: [t("f", .find)], availableWidth: 4000,
                                      userExpanded: [.grow])
        XCTAssertFalse(e.contains(.grow))      // nothing there to expand
    }

    func testWorkingPhaseIsTheBeaconsPhase() {
        // No founder-owned work anywhere → every phase is open, so the prefix spans BOTH
        // populated phases (find, grow) — more than one. The beacon (`RoadmapEngine.nextStep`)
        // is the EARLIEST actionable task by phase order — find — not the tail of the journey.
        let tasks = [t("f", .find), t("g", .grow)]
        XCTAssertEqual(RoadmapEngine.nextStep(tasks)?.phase, .find)
        let oneColumn = RoadmapGeometry.boardWidth(expanded: [.find])
        XCTAssertEqual(RoadmapFocus.expanded(tasks: tasks, availableWidth: oneColumn), [.find])
    }

    /// Regression for the bug this fix removes: an open prefix spanning MORE than one
    /// populated phase must still keep the BEACON's card expanded, not the last open phase's.
    /// FIND is settled (a Codepet-owned leftover, no founder step) but FOUNDATION holds a
    /// founder step, so the prefix widens to {find, foundation} — exactly the shape that let
    /// the beacon's card vanish behind a rail under the old anchor.
    func testBeaconsCardSurvivesWhenTheOpenPrefixSpansTwoPopulatedPhases() {
        let tasks = [t("f", .find), t("d", .foundation, who: .you)]
        XCTAssertEqual(RoadmapGating.openPhases(tasks), [.find, .foundation])
        XCTAssertEqual(RoadmapEngine.nextStep(tasks)?.phase, .find)
        let oneColumn = RoadmapGeometry.boardWidth(expanded: [.find])
        XCTAssertEqual(RoadmapFocus.expanded(tasks: tasks, availableWidth: oneColumn), [.find])
    }

    /// Regression for the "nearest-first measured in compressed populated-rank" bug:
    /// populated = [find, build, ship] (foundation/launch/grow empty), working = build (forced
    /// by a founder-owned task there, which also closes SHIP). True phase distance: ship is 1
    /// hop from build, find is 2 hops — ship must be offered before find. Compressed rank
    /// (find=0, build=1, ship=2) makes them a false tie, which earlier-wins resolves to find —
    /// the farther phase.
    func testNearestFirstUsesTruePhaseDistanceNotPopulatedRank() {
        // populated = [find, ship, launch, grow] (foundation, build empty). FIND's task is
        // DONE — populated still counts it (a phase with any task, done or not, is populated),
        // but the beacon (`RoadmapEngine.nextStep`) only ever points at a NOT-done task, so a
        // done find can't outrank ship for the working phase. A founder-owned task in SHIP
        // holds ship open and makes it the beacon (middle phase), with launch as the preview
        // (correctly picked regardless of the bug). That leaves find and grow as the two
        // remaining candidates: true order distance from ship (order 3) is find=3, grow=2 —
        // grow is truly nearer. But populated-rank compresses across the find→ship gap
        // (foundation, build both empty) to distance 1, while grow's distance (no empty phases
        // between ship and grow other than the populated preview) stays 2 — an inversion that
        // makes the old code prefer find over grow.
        let tasks = [t("f", .find, done: true), t("s", .ship, who: .you), t("l", .launch), t("g", .grow)]
        let threeColumns: CGFloat = RoadmapGeometry.boardWidth(expanded: [.find, .foundation, .build])
        let e = RoadmapFocus.expanded(tasks: tasks, availableWidth: threeColumns)
        XCTAssertEqual(e, [.ship, .launch, .grow])
    }

    func testDeterministicForAFixedWidth() {
        let w = RoadmapGeometry.boardWidth(expanded: [.find, .foundation, .build])
        let a = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: w)
        let b = RoadmapFocus.expanded(tasks: fullBoard(), availableWidth: w)
        XCTAssertEqual(a, b)
    }
}
