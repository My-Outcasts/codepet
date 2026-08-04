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
        // All clear — mirrors testEverythingDoneReadsAllClear.
        let done = canDo("t1", done: true)
        XCTAssertEqual(departmentPulse(eng, mine: [done], all: [done], lang: .vi),
                       "Xong hết trong Engineering.")

        // One needs-you — mirrors testOneTaskNeedsYou.
        let you = RoadmapTask(id: "t2", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [you], all: [you], lang: .vi),
                       "Một việc ở đây cần bạn.")

        // One approval — mirrors testApprovalOutranksEverythingElse.
        let draft = RoadmapTask(id: "t3", title: "Waitlist", detail: "", phase: .find,
                                who: .does, drafted: true, dept: "eng")
        let approvalOne = [draft, canDo("t4")]
        XCTAssertEqual(departmentPulse(eng, mine: approvalOne, all: approvalOne, lang: .vi),
                       "Có một bản nháp chờ bạn duyệt.")

        // Two approvals — mirrors testTwoApprovalsPluralize.
        let draftA = RoadmapTask(id: "t5", title: "A", detail: "", phase: .find, who: .does,
                                 drafted: true, dept: "eng")
        let draftB = RoadmapTask(id: "t6", title: "B", detail: "", phase: .find, who: .does,
                                 drafted: true, dept: "eng")
        let approvalTwo = [draftA, draftB]
        XCTAssertEqual(departmentPulse(eng, mine: approvalTwo, all: approvalTwo, lang: .vi),
                       "2 bản nháp chờ bạn duyệt.")

        // Two need-you — mirrors testTwoTasksNeedYou.
        let youA = RoadmapTask(id: "t7", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        let youB = RoadmapTask(id: "t8", title: "B", detail: "", phase: .find, who: .you, dept: "eng")
        let needsYouTwo = [youA, youB]
        XCTAssertEqual(departmentPulse(eng, mine: needsYouTwo, all: needsYouTwo, lang: .vi),
                       "2 việc ở đây cần bạn.")

        // One runnable — mirrors testOneRunnableTask.
        let runnableOne = canDo("t9")
        XCTAssertEqual(departmentPulse(eng, mine: [runnableOne], all: [runnableOne], lang: .vi),
                       "Không có gì chặn — tôi chạy được việc này ngay.")

        // Two runnable — mirrors testTwoRunnableTasks.
        let runnableTwo = [canDo("t10"), canDo("t11")]
        XCTAssertEqual(departmentPulse(eng, mine: runnableTwo, all: runnableTwo, lang: .vi),
                       "Không có gì chặn — tôi chạy được 2 việc ngay.")

        // Blocked by a dependency in another department — mirrors
        // testDependencyBlockedNamesTheBlockingTaskFromAnotherDepartment.
        let hosting = canDo("ops2", "Set up hosting", dept: "ops")
        let depBlocked = RoadmapTask(id: "t12", title: "Ship the page", detail: "", phase: .find,
                                    who: .does, dependsOn: ["ops2"], dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [depBlocked], all: [depBlocked, hosting], lang: .vi),
                       "Mọi việc ở đây đang chờ: Set up hosting.")

        // Blocked by a founder step holding the phase window shut — mirrors
        // testPhaseBlockedNamesTheFounderStepHoldingTheWindow.
        let gate = RoadmapTask(id: "f2", title: "Choose your launch date", detail: "",
                               phase: .find, who: .you, dept: "mkt")
        let phaseBlocked = RoadmapTask(id: "t13", title: "Build the editor", detail: "", phase: .build,
                                      who: .does, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [phaseBlocked], all: [phaseBlocked, gate], lang: .vi),
                       "Mọi việc ở đây đang chờ: Choose your launch date.")
    }
}
