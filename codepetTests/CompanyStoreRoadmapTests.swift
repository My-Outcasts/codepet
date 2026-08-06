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

    /// Every run — from any surface — plays the full execute-log in the copilot.
    ///
    /// Aug 6, against the live web: clicking a card must produce the same theater a chat run has
    /// always produced (`ExecLogRow`), not the one-line strip `runTask` used to publish onto the
    /// pressed card. Asserted from INSIDE `taskRunner`, the only moment the run is in flight: the
    /// transcript must hold a `producing` message carrying the step checklist and the
    /// DEPARTMENT's pet.
    func testASurfaceRunPlaysTheExecuteLogInChat() async {
        var producing: CopilotMessage?
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "glitch", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "t1", title: "Write your landing page copy",
                                             detail: "", phase: .find, who: .draft, dept: "mkt")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in
               producing = ref?.chatMessages.first { $0.producing }
               return RunTaskResponse(kind: "doc", title: "Landing copy", body: "# hi")
           },
           decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)

        XCTAssertNotNil(producing, "a surface run showed no execute-log at all")
        XCTAssertFalse(producing?.execSteps?.isEmpty ?? true, "the log needs its checklist")
        XCTAssertEqual(producing?.deptName, "Marketing")
        XCTAssertEqual(producing?.companionId, "nova", "the run must carry the DEPARTMENT's pet")
        // Collapsed into the deliverable, with the finished log kept on it.
        XCTAssertFalse(s.chatMessages.contains { $0.producing }, "the placeholder must not survive")
        XCTAssertNotNil(s.chatMessages.last?.draft)
        XCTAssertFalse(s.chatMessages.last?.execSteps?.isEmpty ?? true)
        XCTAssertTrue(s.company.tasks[0].drafted)
    }

    /// The department's character shows even when it happens to BE the founder's companion.
    /// `taskSpecialist` used to return nil in that case, so with Glitch chosen every ops and
    /// legal run lost its character — Glitch is this map's ops/legal specialist.
    func testTheDepartmentsPetShowsEvenWhenItIsAlsoTheHostCompanion() async {
        var producing: CopilotMessage?
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "glitch", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "ops1", title: "Set up a deploy checklist",
                                             detail: "", phase: .find, who: .draft, dept: "ops")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in
               producing = ref?.chatMessages.first { $0.producing }
               return RunTaskResponse(kind: "doc", title: "Checklist", body: "# hi")
           },
           decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)
        XCTAssertEqual(producing?.companionId, "glitch")
        XCTAssertEqual(producing?.deptName, "Operations")
    }

    /// A failed run leaves no placeholder claiming an agent is still working, and says so.
    func testAFailedSurfaceRunLeavesNoAgentBehind() async {
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "byte", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "t1", title: "Draft a support FAQ", detail: "",
                                             phase: .find, who: .draft, dept: "support")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in nil },
           decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.producing })
        XCTAssertNotNil(s.runError)
        XCTAssertFalse(s.company.tasks[0].drafted, "a failed run must not leave a phantom draft")
    }

    // MARK: - Propose, then confirm

    /// A tap on a card must not spend anything. Web parity, verified live Aug 6: clicking `Start`
    /// opens the copilot and OFFERS the run; only the offer's own button runs it.
    func testASurfaceTapProposesAndRunsNothing() async {
        var ran = 0
        let s = proposalStore(runs: { ran += 1 })
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        s.dockCollapsed = true
        s.proposeRun(task, language: .en)

        XCTAssertEqual(ran, 0, "proposing must not run the task")
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertEqual(s.chatMessages.last?.runProposal?.taskId, "t1")
        XCTAssertEqual(s.chatMessages.last?.runProposal?.deptName, "Marketing")
        XCTAssertTrue(s.chatMessages.last?.text.contains("Write your landing page copy") ?? false)
        XCTAssertFalse(s.dockCollapsed, "the copilot must open so the offer is visible")
        XCTAssertFalse(s.company.tasks[0].drafted)
    }

    /// Confirming is what spends. It also consumes the button, so the offer cannot be taken twice.
    func testConfirmingTheProposalRunsItExactlyOnce() async {
        var ran = 0
        let s = proposalStore(runs: { ran += 1 })
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        s.proposeRun(task, language: .en)
        guard let id = s.chatMessages.last?.id else { return XCTFail("no proposal") }

        await s.confirmRun(messageId: id, language: .en)
        XCTAssertEqual(ran, 1)
        XCTAssertTrue(s.company.tasks[0].drafted)
        XCTAssertTrue(s.chatMessages.contains { $0.id == id && $0.actionConsumed })

        // A second press of the same button must be inert — the task is drafted now, and
        // re-running would produce a duplicate draft for work already awaiting approval.
        await s.confirmRun(messageId: id, language: .en)
        XCTAssertEqual(ran, 1, "a consumed proposal must not run again")
    }

    /// Two taps on the same card must not stack two offers — the founder would confirm one and be
    /// left with an orphan offering work that is already drafted.
    func testASecondTapDoesNotStackASecondProposal() async {
        let s = proposalStore(runs: {})
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        s.proposeRun(task, language: .en)
        s.proposeRun(task, language: .en)
        XCTAssertEqual(s.chatMessages.filter { $0.runProposal != nil }.count, 1)
    }

    /// An already-drafted task has nothing to offer — it needs approving, not running.
    func testADraftedTaskIsNotProposed() async {
        let s = proposalStore(runs: {}, drafted: true)
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        s.proposeRun(task, language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    private func proposalStore(runs: @escaping () -> Void, drafted: Bool = false) -> CompanyStore {
        CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "byte", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "t1", title: "Write your landing page copy",
                                             detail: "", phase: .find, who: .draft,
                                             drafted: drafted, dept: "mkt")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in
               runs()
               return RunTaskResponse(kind: "doc", title: "Landing copy", body: "# hi")
           },
           decisionExtractor: { _, _ in [] })
    }

}
