import XCTest
@testable import codepet

final class TopbarCountsTests: XCTestCase {
    private func t(_ id: String, who: TaskWho, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, done: done)
    }
    func testTaskCount_openYouOrDraft() {
        let tasks = [t("a", who: .you), t("b", who: .draft), t("c", who: .does), t("d", who: .you, done: true)]
        XCTAssertEqual(TopbarCounts.tasks(tasks), 2)   // you + draft, not done; .does excluded
    }
    func testEnvPending() {
        let enabled = Set(Toolkit.catalog.prefix(3).map { $0.id })
        XCTAssertEqual(TopbarCounts.envPending(enabled: enabled), max(0, Toolkit.catalog.count - 3))
    }
}
