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

    /// Updated for the run→approve rework: a run now stashes the deliverable as the
    /// task's `draft` (+ `drafted=true`) and persists via `tasksSaver` — it no longer
    /// writes `company.library` directly (that only happens on `approveTask`).
    func testRunProducesDeliverableAndPersists() async {
        var savedTasks: [RoadmapTask] = []
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, tasks in savedTasks = tasks; return true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "WTP Survey", body: "# Q1") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertTrue(s.company.library.isEmpty)         // NOT written to library on run
        let d = s.company.tasks[0].draft
        XCTAssertEqual(d?.kind, .doc)
        XCTAssertEqual(d?.title, "WTP Survey")
        XCTAssertEqual(d?.sourceTaskId, "t1")
        XCTAssertFalse(d?.id.isEmpty ?? true)                    // unique id
        XCTAssertTrue(d?.createdAt?.hasSuffix("Z") ?? false)  // canonical UTC
        XCTAssertEqual(savedTasks.count, 1)              // tasks persisted
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
        XCTAssertTrue(s.company.tasks[0].drafted)        // → Awaiting approval
        XCTAssertFalse(s.company.tasks[0].done)          // not done until approved
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
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "  ", body: "# body") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(s.company.tasks[0].draft?.title, "Survey users")
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
    /// An account switch via hydrate(differentId) must clear stale run state so account
    /// A's error/spinner doesn't bleed into account B (mirrors the chat-state clearing).
    func testAccountSwitchViaHydrateClearsRunState() async {
        let s = store({ _ in nil })   // nil → sets runError on account A
        await s.hydrate(companyId: "A")
        await s.runTask(task(), language: .en)
        XCTAssertNotNil(s.runError)
        await s.hydrate(companyId: "B")
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }

    func testRunTaskStashesDraftAndMarksDraftedWithoutTouchingLibrary() async {
        var tasksSaved = false, librarySaved = false
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(),
                                tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
        let s = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in tasksSaved = true; return true },
            taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Out", body: "the body") },
            librarySaver: { _, _ in librarySaved = true; return true })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertNotNil(s.company.tasks[0].draft)        // draft stashed on task
        XCTAssertTrue(s.company.tasks[0].drafted)        // → Awaiting approval
        XCTAssertFalse(s.company.tasks[0].done)
        XCTAssertTrue(s.company.library.isEmpty)         // NOT added to library on run
        XCTAssertTrue(tasksSaved)                        // tasks persisted
        XCTAssertFalse(librarySaved)                     // library not persisted on run
    }

    func testRunTaskDedupesWhenAlreadyDrafted() async {
        var runs = 0
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             taskRunner: { _ in runs += 1; return RunTaskResponse(kind: "doc", title: "X", body: "y") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(runs, 0)                           // already drafted → not re-run
        XCTAssertEqual(s.company.library.count, 0)
    }

    func testApproveTaskMovesDraftToLibraryOnceAndMarksDone() async {
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        // Stub both savers — approveTask's persistence path would otherwise hit real
        // CompanyData.saveLibrary/saveTasks (Firestore) with an unconfigured FirebaseApp
        // in the test bundle and crash (SIGABRT), not the Xcode 26.2 teardown bug.
        // decisionExtractor is stubbed too: approveTask now fires a fire-and-forget
        // rememberFromApproval, and its default hits DecisionsClient.extract (live
        // Firebase Auth) — same unconfigured-FirebaseApp crash risk.
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertEqual(s.company.library.count, 1)        // moved to library once
        XCTAssertEqual(s.company.library[0].title, "D")
        XCTAssertTrue(s.company.tasks[0].done)
        XCTAssertFalse(s.company.tasks[0].drafted)
        XCTAssertNil(s.company.tasks[0].draft)            // consumed
        await s.approveTask(id: "t1")                     // idempotent
        XCTAssertEqual(s.company.library.count, 1)        // no duplicate
    }

    func testApproveTaskNoOpWithoutDraft() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(),
                                tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
        let s = CompanyStore(loader: { _ in seed })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertFalse(s.company.tasks[0].done)
    }

    func testApproveExtractsMergesAndPersistsDecisions() async {
        var savedDecisions: [DecisionEntry]?
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "Pricing", body: "Plus $4/mo", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             decisionsSaver: { _, d in savedDecisions = d; return true },
                             decisionExtractor: { _, _ in [ExtractedDecision(topic: "pricing", statement: "Plus $4/mo", source: "Pricing")] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        // fire-and-forget Task — allow it to run
        await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(s.company.decisions.first?.topic, "pricing")
        XCTAssertEqual(savedDecisions?.first?.statement, "Plus $4/mo")
    }
    func testApproveFailOpenWhenExtractorReturnsEmpty() async {
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "X", body: "y", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(s.company.decisions.isEmpty)   // nothing extracted → unchanged
        XCTAssertTrue(s.company.tasks[0].done)        // approval still completed
    }
}
