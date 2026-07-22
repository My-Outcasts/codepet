// codepetTests/CompanyStoreRoadmapTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRoadmapTests: XCTestCase {
    private func task(_ id: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .build, who: .does, done: done)
    }

    func testGeneratePersistsFetchedTasks() async {
        var saved: [RoadmapTask] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [self.task("t1")] },
                             tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["t1"])
        XCTAssertEqual(saved.map(\.id), ["t1"])
    }
    func testGenerateFailOpenKeepsExisting() async {
        var saveCount = 0
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("keep")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, _ in saveCount += 1; return true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["keep"])   // empty fetch → no change
        XCTAssertEqual(saveCount, 0)                          // fail-open path never persists
    }
    func testToggleTaskDoneFlipsAndPersists() async {
        var saved: [RoadmapTask] = []
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("t1")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.toggleTaskDone(id: "t1")
        XCTAssertTrue(s.company.tasks[0].done)
        XCTAssertTrue(saved.first?.done ?? false)
    }
    func testToggleAbsentIdIsNoOp() async {
        var saveCount = 0
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("t1")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, _ in saveCount += 1; return true })
        await s.hydrate(companyId: "u")
        await s.toggleTaskDone(id: "nope")
        XCTAssertFalse(s.company.tasks[0].done)   // untouched
        XCTAssertEqual(saveCount, 0)              // absent id → no persist
    }
}
