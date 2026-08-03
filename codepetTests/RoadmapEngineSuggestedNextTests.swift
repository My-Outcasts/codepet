import XCTest
@testable import codepet

final class RoadmapEngineSuggestedNextTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String?, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: dept)
    }

    func testEmptyWhenNothingIsActionable() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([], limit: 3).isEmpty)
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng", done: true)], limit: 3).isEmpty)
    }

    func testLimitZeroReturnsNothing() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng")], limit: 0).isEmpty)
    }

    /// The beacon and the suggestion list must never disagree, so nextStep is always first.
    func testBeaconIsAlwaysFirst() {
        let tasks = [t("d", .foundation, dept: "design"), t("f", .find, dept: "mkt")]
        let picked = RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id)
        XCTAssertEqual(picked.first, RoadmapEngine.nextStep(tasks)?.id)
        XCTAssertEqual(picked.first, "f")     // find(0) precedes foundation(1)
    }

    /// The gap that rules out nextMoves: a founder-owned task must be suggestible.
    func testIncludesNeedsYouAndNeedsApproval() {
        let you = t("y", .find, dept: "mkt", who: .you)
        let draft = t("dr", .find, dept: "design", drafted: true)
        let picked = RoadmapEngine.suggestedNext([you, draft], limit: 3).map(\.id)
        XCTAssertTrue(picked.contains("y"))
        XCTAssertTrue(picked.contains("dr"))
    }

    func testOneSuggestionPerDepartment() {
        let tasks = [t("e1", .find, dept: "eng"), t("e2", .find, dept: "eng"),
                     t("m1", .find, dept: "mkt")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["e1", "m1"])
    }

    func testRespectsLimit() {
        let tasks = [t("a", .find, dept: "eng"), t("b", .find, dept: "mkt"),
                     t("c", .find, dept: "design"), t("d", .find, dept: "sales")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 2).count, 2)
    }

    /// Confined to the open phase window, exactly like the beacon.
    func testConfinedToTheOpenWindow() {
        let gate = t("y", .find, dept: "mkt", who: .you)   // holds FIND shut
        let later = t("b", .build, dept: "eng")            // would otherwise be suggestible
        XCTAssertEqual(RoadmapEngine.suggestedNext([gate, later], limit: 3).map(\.id), ["y"])
    }

    /// Legacy dept-less tasks are eligible and don't collapse into one shared slot.
    func testDeptLessTasksEachTakeASlot() {
        let tasks = [t("a", .find, dept: nil), t("b", .find, dept: nil)]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["a", "b"])
    }

    func testBlockedTasksAreNeverSuggested() {
        let a = t("a", .find, dept: "eng")
        let b = t("b", .find, dept: "mkt", deps: ["a"])     // a not done → blocked
        XCTAssertEqual(RoadmapEngine.suggestedNext([a, b], limit: 3).map(\.id), ["a"])
    }
}
