import XCTest
@testable import codepet

final class RoadmapEngineNextMovesTests: XCTestCase {
    // Helper: a codepetCanDo-eligible task by default (who: .does, not done/drafted, no deps).
    private func task(_ id: String, dept: String?, phase: RoadmapPhase,
                      who: TaskWho = .does, done: Bool = false, drafted: Bool = false,
                      dependsOn: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: dependsOn, done: done, drafted: drafted, dept: dept)
    }

    func testPicksFirstCodepetCanDoPerDistinctDeptInRoadmapOrder() {
        let tasks = [
            task("m1", dept: "mkt", phase: .launch),
            task("e1", dept: "eng", phase: .build),
            task("e2", dept: "eng", phase: .build),   // same dept as e1 → skipped
            task("d1", dept: "design", phase: .foundation),
        ]
        let picked = RoadmapEngine.nextMoves(tasks, limit: 3).map(\.id)
        // Ordered by phase: foundation(d1) < build(e1) < launch(m1); one per dept.
        XCTAssertEqual(picked, ["d1", "e1", "m1"])
    }

    func testCapLimitsCount() {
        let tasks = [
            task("d1", dept: "design", phase: .foundation),
            task("e1", dept: "eng", phase: .build),
            task("m1", dept: "mkt", phase: .launch),
            task("f1", dept: "fin", phase: .grow),
        ]
        XCTAssertEqual(RoadmapEngine.nextMoves(tasks, limit: 2).map(\.id), ["d1", "e1"])
    }

    func testSkipsIneligibleTasks() {
        let tasks = [
            task("done1", dept: "eng", phase: .build, done: true),          // done
            task("you1", dept: "design", phase: .build, who: .you),         // needsYou
            task("draft1", dept: "mkt", phase: .build, drafted: true),      // needsApproval
            task("blocked1", dept: "fin", phase: .build, dependsOn: ["x"]), // blocked (dep x not done)
            task("x", dept: "zzz", phase: .build, done: false),             // the missing dep target (no companion mapping)
            task("nodept", dept: nil, phase: .build),                       // no dept
            task("nomap", dept: "zzz", phase: .build),                      // dept has no companion mapping
            task("ok", dept: "ops", phase: .build),                         // the only eligible one
        ]
        XCTAssertEqual(RoadmapEngine.nextMoves(tasks, limit: 3).map(\.id), ["ok"])
    }

    func testEmptyWhenNothingActionableOrLimitZero() {
        let none = [task("you1", dept: "eng", phase: .build, who: .you)]
        XCTAssertEqual(RoadmapEngine.nextMoves(none, limit: 3).count, 0)
        XCTAssertEqual(RoadmapEngine.nextMoves([], limit: 3).count, 0)
        XCTAssertEqual(RoadmapEngine.nextMoves([task("e1", dept: "eng", phase: .build)], limit: 0).count, 0)
    }
}
