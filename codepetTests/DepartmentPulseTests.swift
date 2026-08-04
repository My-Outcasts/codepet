import XCTest
@testable import codepet

final class DepartmentPulseTests: XCTestCase {
    private let eng = DepartmentCatalog.find("eng")!

    /// A task in `.find` owned by Codepet: never gates the phase window, never blocked.
    private func canDo(_ id: String, _ title: String = "Do a thing", dept: String? = "eng",
                       done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .find, who: .does,
                    done: done, dept: dept)
    }

    func testNoTasksRendersNoLine() {
        XCTAssertNil(departmentPulse(eng, mine: [], all: [], lang: .en))
    }

    func testEverythingDoneReadsAllClear() {
        let t = canDo("t1", done: true)
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "All clear in Engineering.")
    }

    func testApprovalOutranksEverythingElse() {
        let draft = RoadmapTask(id: "t1", title: "Waitlist", detail: "", phase: .find,
                                who: .does, drafted: true, dept: "eng")
        let other = canDo("t2")
        let all = [draft, other]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "One thing's ready for you to approve.")
    }

    func testTwoApprovalsPluralize() {
        let a = RoadmapTask(id: "t1", title: "A", detail: "", phase: .find, who: .does,
                            drafted: true, dept: "eng")
        let b = RoadmapTask(id: "t2", title: "B", detail: "", phase: .find, who: .does,
                            drafted: true, dept: "eng")
        let all = [a, b]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "2 ready for you to approve.")
    }

    func testOneTaskNeedsYou() {
        let t = RoadmapTask(id: "t1", title: "Pick a name", detail: "", phase: .find,
                            who: .you, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "One here needs you.")
    }

    func testTwoTasksNeedYou() {
        let a = RoadmapTask(id: "t1", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        let b = RoadmapTask(id: "t2", title: "B", detail: "", phase: .find, who: .you, dept: "eng")
        let all = [a, b]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "2 here need you.")
    }

    func testOneRunnableTask() {
        let t = canDo("t1")
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "Nothing blocked — I can run this one now.")
    }

    func testTwoRunnableTasks() {
        let all = [canDo("t1"), canDo("t2")]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "Nothing blocked — I can run 2 of these now.")
    }

    /// Dependency-gated: the blocker lives in ANOTHER department, proving resolution runs
    /// against the whole board and not the department-filtered list.
    func testDependencyBlockedNamesTheBlockingTaskFromAnotherDepartment() {
        let hosting = canDo("ops1", "Set up hosting", dept: "ops")
        let mine = RoadmapTask(id: "t1", title: "Ship the page", detail: "", phase: .find,
                               who: .does, dependsOn: ["ops1"], dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [mine], all: [mine, hosting], lang: .en),
                       "Everything here is waiting on Set up hosting.")
    }

    /// Phase-gated: nothing in Engineering has an unmet dependency, but its phase is shut
    /// behind a founder-owned step in an earlier phase. `RoadmapGating.blocker` returns that
    /// founder step, which is the useful thing to name.
    func testPhaseBlockedNamesTheFounderStepHoldingTheWindow() {
        let gate = RoadmapTask(id: "f1", title: "Choose your launch date", detail: "",
                               phase: .find, who: .you, dept: "mkt")
        let mine = RoadmapTask(id: "t1", title: "Build the editor", detail: "", phase: .build,
                               who: .does, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [mine], all: [mine, gate], lang: .en),
                       "Everything here is waiting on Choose your launch date.")
    }

    func testDoneTasksAreIgnoredWhenOpenWorkRemains() {
        let finished = canDo("t1", done: true)
        let open = canDo("t2")
        let all = [finished, open]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "Nothing blocked — I can run this one now.")
    }

    func testVietnamese() {
        let done = canDo("t1", done: true)
        XCTAssertEqual(departmentPulse(eng, mine: [done], all: [done], lang: .vi),
                       "Xong hết trong Engineering.")
        let you = RoadmapTask(id: "t2", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [you], all: [you], lang: .vi),
                       "Một việc ở đây cần bạn.")
    }
}
