// codepetTests/EngineeringRunStoreTests.swift
import XCTest
@testable import codepet

/// Driven through an injected `EngineeringRunning`, so no test here touches
/// the network — and so the store can be exercised at all, given the XCTest
/// host on Xcode 26.2 crashes when a @MainActor ObservableObject deallocates.
@MainActor
final class EngineeringRunStoreTests: XCTestCase {

    /// A runner that does nothing on its own. The store is fed frames directly
    /// via `handle`, so each test controls the exact sequence rather than
    /// racing a script.
    private final class SilentRunner: EngineeringRunning {
        var sent: [EngineeringTurn] = []
        var diffToReturn: EngDiffSummary = .empty
        var diffError: EngineeringError?
        var startError: EngineeringError?

        func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
            if let startError { throw startError }
            return "run_1"
        }
        func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {}
        func send(runId: String, turn: EngineeringTurn) async throws { sent.append(turn) }
        func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary {
            if let diffError { throw diffError }
            return diffToReturn
        }
    }

    private func makeStore(_ runner: SilentRunner = SilentRunner()) -> (EngineeringRunStore, SilentRunner) {
        (EngineeringRunStore(runner: runner), runner)
    }

    // MARK: - steps

    func testACompletionMarkerCompletesTheEarlierStepRatherThanAddingARow() {
        // engEvents sends { id, label: "", done: true } to finish a step it
        // announced earlier. Appending it would leave the original spinning
        // forever AND add a blank row under it.
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "s1", label: "ran npm test", done: false, kind: .mono)))
        store.handle(.step(ExecStep(id: "s1", label: "", done: true, kind: .mono)))

        XCTAssertEqual(store.steps.count, 1)
        XCTAssertTrue(store.steps[0].done)
        XCTAssertEqual(store.steps[0].label, "ran npm test", "the announcement's label must survive")
    }

    func testALaterLabelWinsWhenTheMarkerCarriesOne() {
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "s1", label: "running", done: false, kind: .mono)))
        store.handle(.step(ExecStep(id: "s1", label: "ran 14 tests", done: true, kind: .mono)))
        XCTAssertEqual(store.steps[0].label, "ran 14 tests")
    }

    func testTwoDistinctStepsAreTwoRows() {
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "s1", label: "a", done: false, kind: .mono)))
        store.handle(.step(ExecStep(id: "s2", label: "b", done: false, kind: .mono)))
        XCTAssertEqual(store.steps.count, 2)
    }

    // MARK: - approvals

    func testAnApprovalPausesTheRun() {
        let (store, _) = makeStore()
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i")))
        XCTAssertEqual(store.approvals.count, 1)
        XCTAssertEqual(store.phase, .awaitingApproval)
    }

    func testAnsweringRemovesTheCardAndResumes() async {
        let (store, runner) = makeStore()
        _ = await store.start(ask: "x")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i")))

        await store.answer(toolUseId: "tu_1", allow: true)

        XCTAssertTrue(store.approvals.isEmpty)
        XCTAssertEqual(store.phase, .running)
        XCTAssertEqual(runner.sent, [.approve(toolUseId: "tu_1")])
    }

    func testADuplicateApprovalIdDoesNotStackTwoCards() {
        // The relay replays history on reconnect; the same ask arrives twice.
        let (store, _) = makeStore()
        let ask = EngApproval(id: "tu_1", name: "bash", input: "npm i")
        store.handle(.approval(ask))
        store.handle(.approval(ask))
        XCTAssertEqual(store.approvals.count, 1)
    }

    func testAnAlreadyAnsweredApprovalDoesNotComeBackOnReplay() async {
        // The sharpest version of the same problem: answered, then replayed on
        // reconnect. A card that reappears reads as the agent asking twice.
        let (store, _) = makeStore()
        _ = await store.start(ask: "x")
        let ask = EngApproval(id: "tu_1", name: "bash", input: "npm i")
        store.handle(.approval(ask))
        await store.answer(toolUseId: "tu_1", allow: true)

        store.handle(.approval(ask))

        XCTAssertTrue(store.approvals.isEmpty)
    }

    func testTwoOutstandingAsksAreBothShownAndAnsweredIndependently() async {
        // The agent can batch tool calls in one turn.
        let (store, _) = makeStore()
        _ = await store.start(ask: "x")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "a")))
        store.handle(.approval(EngApproval(id: "tu_2", name: "bash", input: "b")))
        XCTAssertEqual(store.approvals.count, 2)

        await store.answer(toolUseId: "tu_1", allow: true)

        XCTAssertEqual(store.approvals.map(\.id), ["tu_2"])
        XCTAssertEqual(store.phase, .awaitingApproval, "one answered ask does not resume the run")
    }

    func testDenyingCarriesTheReason() async {
        let (store, runner) = makeStore()
        _ = await store.start(ask: "x")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i")))

        await store.answer(toolUseId: "tu_1", allow: false, reason: "use pnpm")

        XCTAssertEqual(runner.sent, [.deny(toolUseId: "tu_1", reason: "use pnpm")])
    }

    // MARK: - terminal states

    func testEndTurnMovesToReviewing() {
        let (store, _) = makeStore()
        store.handle(.done(stopReason: "end_turn"))
        XCTAssertEqual(store.phase, .reviewing)
    }

    // MARK: - a command asked for is not a command run

    func testAStepWaitingOnPermissionIsNotListedAsSomethingThatHappened() {
        // THE BUG THE FIRST LIVE RUN SHOWED. A step is built from
        // `agent.tool_use` — the agent ASKING for a tool — so under
        // `bash: always_ask` the same command appeared twice in one card: an
        // un-ticked step row, and directly below it the card asking whether it
        // may run at all. Two rows apart, disagreeing.
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "t1", label: "ls -la", done: true, kind: .mono)))
        store.handle(.step(ExecStep(id: "t2", label: "rm -rf build", done: false, kind: .mono)))
        store.handle(.approval(EngApproval(id: "t2", name: "bash", input: "rm -rf build")))

        XCTAssertEqual(store.steps.count, 2, "the log must keep everything")
        XCTAssertEqual(store.visibleSteps.map(\.id), ["t1"],
                       "a command still awaiting permission is shown as a step")
    }

    func testTheStepAppearsOnceTheAskIsAnswered() async {
        // Answered or denied, the approval leaves and the row takes its place
        // in the log — in order, as what the agent actually did.
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "t2", label: "rm -rf build", done: false, kind: .mono)))
        store.handle(.approval(EngApproval(id: "t2", name: "bash", input: "rm -rf build")))
        XCTAssertTrue(store.visibleSteps.isEmpty)

        await store.answer(toolUseId: "t2", allow: true)

        XCTAssertEqual(store.visibleSteps.map(\.id), ["t2"])
    }

    func testWithNothingPendingEveryStepShows() {
        let (store, _) = makeStore()
        store.handle(.step(ExecStep(id: "a", label: "one", done: true, kind: .mono)))
        store.handle(.step(ExecStep(id: "b", label: "two", done: true, kind: .mono)))
        XCTAssertEqual(store.visibleSteps.count, 2)
    }

    func testABudgetPauseIsNotAFailure() {
        // Resumable. Calling it failed makes a founder start over and pay twice.
        let (store, _) = makeStore()
        store.handle(.done(stopReason: "budget_reached"))
        XCTAssertEqual(store.phase, .budgetReached)
        // No refusal came over the wire — the stream just ended — and this is
        // the exact state that left the bar silent: it drew its explanation
        // off `failure` alone, so the commonest budget pause said nothing.
        XCTAssertNil(store.failure)
        XCTAssertNotNil(EngineeringResultBar.note(phase: store.phase,
                                                  failure: store.failure, lang: .en),
                        "a run stopped at its cap explains nothing to the founder")
    }

    func testAStreamErrorIsRetryableRatherThanUnknown() {
        let (store, _) = makeStore()
        store.handle(.failure("stream_failed"))
        XCTAssertEqual(store.failure, .unavailable)
    }

    // MARK: - refusals

    func testStartSurfacesTheRefusalTheFounderMustActon() async {
        let runner = SilentRunner()
        runner.startError = .noRepoLinked
        let (store, _) = makeStore(runner)

        await store.start(ask: "x")

        XCTAssertEqual(store.failure, .noRepoLinked)
        XCTAssertNil(store.runId)
    }

    func testAFailedDiffDoesNotMarkTheRunFailed() async {
        // The work happened and the branch exists. Calling the RUN failed would
        // send a founder to re-run something that already succeeded.
        let runner = SilentRunner()
        runner.diffError = .unavailable
        let (store, _) = makeStore(runner)
        _ = await store.start(ask: "x")
        store.handle(.done(stopReason: "end_turn"))

        await store.loadDiff(scope: .branch)

        XCTAssertEqual(store.failure, .unavailable)
        XCTAssertEqual(store.phase, .reviewing, "a diff fetch must not change the run's phase")
    }

    func testLoadingADiffStoresIt() async {
        let runner = SilentRunner()
        runner.diffToReturn = EngDiffSummary(
            files: [], additions: 3, deletions: 1,
            truncated: true, scope: .branch, scopeFellBack: true
        )
        let (store, _) = makeStore(runner)
        _ = await store.start(ask: "x")

        await store.loadDiff(scope: .turn)

        XCTAssertEqual(store.diff?.additions, 3)
        XCTAssertEqual(store.diff?.truncated, true)
        XCTAssertEqual(store.diff?.scopeFellBack, true)
    }

    func testMessagesAccumulateInOrder() {
        let (store, _) = makeStore()
        store.handle(.message("first"))
        store.handle(.message("second"))
        XCTAssertEqual(store.messages, ["first", "second"])
    }
}
