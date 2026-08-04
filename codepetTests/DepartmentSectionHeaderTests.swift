import XCTest
@testable import codepet

final class DepartmentSectionHeaderTests: XCTestCase {
    private func task(_ id: String, done: Bool) -> RoadmapTask {
        RoadmapTask(id: id, title: "T\(id)", detail: "", phase: .find, who: .does,
                    done: done, dept: "eng")
    }

    /// Nothing delivered yet — the count would only restate the list below it.
    func testUntouchedDepartmentReadsBare() {
        let tasks = [task("a", done: false), task("b", done: false)]
        XCTAssertEqual(departmentSectionHeader(tasks: tasks, lang: .en), "WHAT NEEDS DOING")
    }

    func testPartlyDoneAppendsTheCount() {
        let tasks = [task("a", done: true), task("b", done: false), task("c", done: false)]
        XCTAssertEqual(departmentSectionHeader(tasks: tasks, lang: .en),
                       "WHAT NEEDS DOING · 1 of 3 done")
    }

    /// The case that drove the change: without the count this header read "WHAT NEEDS DOING"
    /// directly above eight delivered rows and an "All clear" pulse line.
    func testFullyDoneStillShowsTheCount() {
        let tasks = (1...8).map { task("\($0)", done: true) }
        XCTAssertEqual(departmentSectionHeader(tasks: tasks, lang: .en),
                       "WHAT NEEDS DOING · 8 of 8 done")
    }

    /// A dormant department renders this header with the empty-state line beneath it.
    func testNoTasksReadsBare() {
        XCTAssertEqual(departmentSectionHeader(tasks: [], lang: .en), "WHAT NEEDS DOING")
    }

    func testVietnamese() {
        let untouched = [task("a", done: false)]
        XCTAssertEqual(departmentSectionHeader(tasks: untouched, lang: .vi), "VIỆC CẦN LÀM")

        let partly = [task("a", done: true), task("b", done: false)]
        XCTAssertEqual(departmentSectionHeader(tasks: partly, lang: .vi),
                       "VIỆC CẦN LÀM · 1/2 đã xong")
    }
}
