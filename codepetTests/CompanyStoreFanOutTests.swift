// codepetTests/CompanyStoreFanOutTests.swift
import XCTest
@testable import codepet

/// Full-flow test for the parallel department-agent fan-out: the client planner
/// picks next moves, `fanOutNextMoves` seeds `activeAgentRuns` and dispatches
/// concurrent runs, each agent's draft lands in the transcript, and the busy
/// flags clear — plus the honest empty-plan / failure paths and account-guard.
@MainActor
final class CompanyStoreFanOutTests: XCTestCase {
    private var savedStepNanos: UInt64 = 0
    private var savedBeatNanos: UInt64 = 0

    override func setUp() {
        super.setUp()
        // Collapse the client-side step-reveal + done-beat sleeps so the flow runs fast.
        savedStepNanos = CompanyStore.execStepNanos
        savedBeatNanos = CompanyStore.execDoneBeatNanos
        CompanyStore.execStepNanos = 1_000
        CompanyStore.execDoneBeatNanos = 1_000
    }
    override func tearDown() {
        CompanyStore.execStepNanos = savedStepNanos
        CompanyStore.execDoneBeatNanos = savedBeatNanos
        super.tearDown()
    }

    /// A codepetCanDo task (who: .does, not done/drafted, no deps) in `dept`.
    private func task(_ id: String, dept: String, phase: RoadmapPhase = .build) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task \(id)", detail: "d", phase: phase, who: .does, dept: dept)
    }

    /// A store seeded (via the loader) with `tasks` and the given stub `taskRunner`.
    /// Firebase-touching savers/loaders are stubbed so the test bundle never hits a
    /// live Firestore (unconfigured FirebaseApp would crash).
    private func store(tasks: [RoadmapTask],
                       runner: @escaping (RunTaskRequest) async -> RunTaskResponse?) -> CompanyStore {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: tasks)
        return CompanyStore(loader: { _ in seed },
                            tasksSaver: { _, _ in true },
                            taskRunner: runner,
                            librarySaver: { _, _ in true },
                            threadSaver: { _, _ in true },
                            threadsLoader: { _ in [] })
    }

    private func draftCount(_ s: CompanyStore) -> Int {
        s.chatMessages.filter { $0.draft != nil }.count
    }
    private func honestBubbleCount(_ s: CompanyStore) -> Int {
        s.chatMessages.filter { $0.role == .companion && $0.draft == nil && !$0.text.isEmpty }.count
    }

    // MARK: - Happy path

    func testFanOutSeedsRunsAppendsDraftPerAgentAndClears() async {
        let s = store(tasks: [task("e1", dept: "eng"), task("d1", dept: "design"), task("m1", dept: "mkt")],
                      runner: { req in RunTaskResponse(kind: "doc", title: "Out \(req.taskId)", body: "# body") })
        await s.hydrate(companyId: "u")
        await s.fanOutNextMoves(language: .en)

        XCTAssertEqual(draftCount(s), 3)                       // one draft per agent landed
        XCTAssertTrue(s.activeAgentRuns.isEmpty)               // the live row cleared when all finished
        XCTAssertFalse(s.isFanningOut)                         // busy flag cleared → composer re-enabled
        let sources = Set(s.chatMessages.compactMap { $0.draft?.sourceTaskId })
        XCTAssertEqual(sources, ["e1", "d1", "m1"])            // drafts trace back to the planned tasks
    }

    func testCapLimitsToMaxFanOutAgents() async {
        let s = store(tasks: [task("e1", dept: "eng"), task("d1", dept: "design"),
                              task("m1", dept: "mkt"), task("o1", dept: "ops")],
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# b") })
        await s.hydrate(companyId: "u")
        await s.fanOutNextMoves(language: .en)

        XCTAssertEqual(CompanyStore.maxFanOut, 3)
        XCTAssertEqual(draftCount(s), 3)                       // 4 eligible depts, capped at maxFanOut
    }

    // MARK: - Honest paths

    func testEmptyPlanShowsHonestBubbleAndNoBusyState() async {
        // Only a needsYou task → nothing codepetCanDo → empty plan.
        let s = store(tasks: [RoadmapTask(id: "y1", title: "You do it", detail: "", phase: .build,
                                          who: .you, dept: "eng")],
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# b") })
        await s.hydrate(companyId: "u")
        await s.fanOutNextMoves(language: .en)

        XCTAssertEqual(draftCount(s), 0)
        XCTAssertEqual(honestBubbleCount(s), 1)               // "you're all caught up" bubble
        XCTAssertFalse(s.isFanningOut)
        XCTAssertTrue(s.activeAgentRuns.isEmpty)
    }

    func testFailedRunShowsFailedBubbleNoDraft() async {
        let s = store(tasks: [task("e1", dept: "eng")], runner: { _ in nil })   // nil → failure
        await s.hydrate(companyId: "u")
        await s.fanOutNextMoves(language: .en)

        XCTAssertEqual(draftCount(s), 0)                      // no draft on failure
        XCTAssertEqual(honestBubbleCount(s), 1)              // honest "couldn't finish" bubble
        XCTAssertTrue(s.activeAgentRuns.isEmpty)
        XCTAssertFalse(s.isFanningOut)
    }

    // MARK: - Guards

    func testAccountSwitchDuringFanOutDiscardsDraft() async {
        var ref: CompanyStore?
        let s = store(tasks: [task("e1", dept: "eng")],
                      runner: { _ in
                          await ref?.hydrate(companyId: "B")   // switch account mid-run
                          return RunTaskResponse(kind: "doc", title: "x", body: "# b")
                      })
        ref = s
        await s.hydrate(companyId: "A")
        await s.fanOutNextMoves(language: .en)

        XCTAssertEqual(draftCount(s), 0)                      // draft discarded — never lands in another account
        XCTAssertFalse(s.isFanningOut)                        // account-switch cleared the flag
        XCTAssertTrue(s.activeAgentRuns.isEmpty)
    }

    func testResetClearsFanOutState() async {
        let s = store(tasks: [task("e1", dept: "eng")],
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# b") })
        await s.hydrate(companyId: "u")
        await s.fanOutNextMoves(language: .en)
        s.reset()

        XCTAssertTrue(s.activeAgentRuns.isEmpty)
        XCTAssertFalse(s.isFanningOut)
    }
}
