import XCTest
@testable import codepet

final class DepartmentCatalogTests: XCTestCase {
    func testEightDepartmentsInOrder() {
        XCTAssertEqual(DepartmentCatalog.all.map(\.key),
                       ["eng","design","mkt","sales","support","fin","ops","legal"])
        XCTAssertEqual(DepartmentCatalog.find("eng")?.name, "Engineering")
        XCTAssertEqual(DepartmentCatalog.find("eng")?.ab, "En")
        XCTAssertNil(DepartmentCatalog.find(nil))
        XCTAssertFalse(DepartmentCatalog.find("eng")!.rationale.isEmpty)
    }
    private func task(_ id: String, dept: String?, who: TaskWho, done: Bool = false, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, dependsOn: deps, done: done, dept: dept)
    }
    func testSummaryStatusAndCounts() {
        let tasks = [
            task("a", dept: "eng", who: .you),                 // needsYou → attention
            task("b", dept: "eng", who: .does),                // codepetCanDo
            task("c", dept: "mkt", who: .does),                // codepetCanDo → ready
            task("d", dept: "fin", who: .does, done: true),    // done → idle (no open)
        ]
        let s = DepartmentCatalog.summaries(tasks: tasks)
        let eng = s.first { $0.department.key == "eng" }!
        XCTAssertEqual(eng.status, .attention)         // has a needsYou task
        XCTAssertEqual(eng.pending, 2)
        XCTAssertEqual(eng.currentTaskTitle, "a")
        XCTAssertEqual(s.first { $0.department.key == "mkt" }!.status, .ready)
        XCTAssertEqual(s.first { $0.department.key == "fin" }!.status, .idle)   // only a done task
        XCTAssertEqual(s.first { $0.department.key == "legal" }!.status, .later) // zero tasks
        XCTAssertEqual(DepartmentCatalog.needToday(s), 1)   // only eng is attention
    }
}
