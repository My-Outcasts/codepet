// codepetTests/CompanyStoreRunTaskTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRunTaskTests: XCTestCase {
    private func task(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "Survey users", detail: "wtp", phase: .find, who: .does)
    }
    private func store(_ runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     taskRunner: runner, librarySaver: saver)
    }

    func testRunProducesDeliverableAndPersists() async {
        var saved: [Deliverable] = []
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "WTP Survey", body: "# Q1") },
                      saver: { _, lib in saved = lib; return true })
        await s.hydrate(companyId: "u")
        let t = task()
        await s.runTask(t, language: .en)
        XCTAssertEqual(s.company.library.count, 1)
        let d = s.company.library[0]
        XCTAssertEqual(d.kind, .doc)
        XCTAssertEqual(d.title, "WTP Survey")
        XCTAssertEqual(d.sourceTaskId, "t1")
        XCTAssertFalse(d.id.isEmpty)                    // unique id
        XCTAssertTrue(d.createdAt?.hasSuffix("Z") ?? false)  // canonical UTC
        XCTAssertEqual(saved.count, 1)                  // persisted
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
        XCTAssertFalse(s.company.tasks.contains { $0.id == "t1" && $0.done })  // task unchanged
    }
    func testEmptyBodyFailsOpenNoDeliverable() async {
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "x", body: "   ") })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testNilResultFailsOpen() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
    }
    func testTitleFallsBackToTaskTitle() async {
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "  ", body: "# body") })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertEqual(s.company.library.first?.title, "Survey users")
    }
    func testAccountSwitchMidRunDiscards() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             taskRunner: { _ in await ref?.hydrate(companyId: "B"); return RunTaskResponse(kind: "doc", title: "x", body: "# y") },
                             librarySaver: { _, _ in true })
        ref = s
        await s.hydrate(companyId: "A")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)   // discarded on switch
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testResetClearsRunState() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        s.reset()
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
}
