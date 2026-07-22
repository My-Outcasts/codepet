import XCTest
@testable import codepet

final class TaskColumnTests: XCTestCase {
    private func t(_ id: String, who: TaskWho, done: Bool = false, drafted: Bool = false, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, dependsOn: deps, done: done, drafted: drafted)
    }
    func testColumnMapping() {
        let all = [
            t("blocker", who: .you),                              // undone → dep unsatisfied for dependents
            t("does", who: .does),                                // codepetCanDo → upNext
            t("draftpending", who: .draft),                       // codepetCanDo (draft, not yet) → upNext
            t("drafted", who: .does, drafted: true),              // needsApproval → awaiting
            t("you", who: .you),                                  // needsYou → yourMove
            t("done", who: .does, done: true),                    // done
            t("blocked", who: .does, deps: ["blocker"]),          // blocked → upNext (queued)
        ]
        func col(_ id: String) -> TaskColumn { TaskColumn.column(for: all.first { $0.id == id }!, in: all) }
        XCTAssertEqual(col("does"), .upNext)
        XCTAssertEqual(col("draftpending"), .upNext)
        XCTAssertEqual(col("blocked"), .upNext)
        XCTAssertEqual(col("drafted"), .awaiting)
        XCTAssertEqual(col("you"), .yourMove)
        XCTAssertEqual(col("done"), .done)
    }
}
