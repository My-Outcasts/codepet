// codepetTests/SummaryDataTests.swift
import XCTest
@testable import codepet

final class SummaryDataTests: XCTestCase {
    private func company(tasks: [RoadmapTask] = [], library: [Deliverable] = []) -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: library,
                     stage: .idea, companionId: "byte", tasks: tasks)
    }

    func testEmptyCompanyIsAllClear() {
        let d = SummaryData(company: company(), language: .en)
        XCTAssertEqual(d.totalCount, 0)
        XCTAssertEqual(d.doneCount, 0)
        XCTAssertEqual(d.byteHandled, 0)
        XCTAssertEqual(d.needsYou, 0)
        XCTAssertEqual(d.autopilotPct, 100)   // idle -> "100% on autopilot"
        XCTAssertEqual(d.departmentCount, 0)
        XCTAssertEqual(d.shippedCount, 0)
        XCTAssertTrue(d.recentWins.isEmpty)
        XCTAssertTrue(d.isAllClear)
    }

    func testAutopilotSplitAndCounts() {
        let tasks = [
            RoadmapTask(id: "1", title: "A", detail: "", phase: .build, who: .does, dept: "eng"),
            RoadmapTask(id: "2", title: "B", detail: "", phase: .build, who: .does, dept: "eng"),
            RoadmapTask(id: "3", title: "C", detail: "", phase: .build, who: .does, dept: "design"),
            RoadmapTask(id: "4", title: "D", detail: "", phase: .find, who: .you, dept: "mkt"),
            RoadmapTask(id: "5", title: "E", detail: "", phase: .find, who: .does, done: true, dept: "eng"),
        ]
        let d = SummaryData(company: company(tasks: tasks), language: .en)
        XCTAssertEqual(d.totalCount, 5)
        XCTAssertEqual(d.doneCount, 1)
        XCTAssertEqual(d.byteHandled, 3)      // 3 open .does
        XCTAssertEqual(d.needsYou, 1)         // 1 open .you
        XCTAssertEqual(d.autopilotPct, 75)    // 3 / 4
        XCTAssertEqual(d.departmentCount, 3)  // eng, design, mkt
        XCTAssertFalse(d.isAllClear)
    }

    func testRecentWinsNewestFirstCappedAndMeta() {
        let tasks = [
            RoadmapTask(id: "t-eng", title: "T", detail: "", phase: .build, who: .does, dept: "eng"),
        ]
        let lib = [
            Deliverable(id: "d1", kind: .doc,   title: "Old",    body: "b", createdAt: "2026-01-01T00:00:00Z", sourceTaskId: "t-eng"),
            Deliverable(id: "d2", kind: .post,  title: "Mid",    body: "b", createdAt: "2026-02-01T00:00:00Z", sourceTaskId: nil),
            Deliverable(id: "d3", kind: .email, title: "New",    body: "b", createdAt: "2026-03-01T00:00:00Z", sourceTaskId: "missing"),
            Deliverable(id: "d4", kind: .plan,  title: "Newest", body: "b", createdAt: "2026-04-01T00:00:00Z", sourceTaskId: "t-eng"),
        ]
        let d = SummaryData(company: company(tasks: tasks, library: lib), language: .en)
        XCTAssertEqual(d.shippedCount, 4)
        XCTAssertEqual(d.recentWins.count, 3)                                  // capped at 3
        XCTAssertEqual(d.recentWins.map(\.title), ["Newest", "New", "Mid"])   // newest-first
        XCTAssertEqual(d.recentWins[0].meta, "Engineering")                    // resolved via source task dept
        XCTAssertEqual(d.recentWins[2].meta, DeliverableKind.post.label(.en))  // fallback to kind label
    }
}
