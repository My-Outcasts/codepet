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
