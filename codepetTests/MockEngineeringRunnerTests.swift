// codepetTests/MockEngineeringRunnerTests.swift
import XCTest
@testable import codepet

/// The mock is what every later task is built and reviewed against — with the
/// Anthropic account out of credits it is the only way to see Engineering mode
/// at all. So it gets tested like production code: if its script is wrong, the
/// views built on it are built against a run that never happens.
@MainActor
final class MockEngineeringRunnerTests: XCTestCase {

    /// Collects frames as they arrive. The mock plays its script on a detached
    /// Task, so a test waits on the frame it expects rather than a fixed sleep.
    private final class Collector {
        private(set) var frames: [EngineeringFrame] = []
        func append(_ frame: EngineeringFrame) { frames.append(frame) }

        func names() -> [String] {
            frames.map {
                switch $0 {
                case .step: return "step"
                case .message: return "message"
                case .approval: return "approval"
                case .done: return "done"
                case .failure: return "error"
                }
            }
        }

        var approvalIds: [String] {
            frames.compactMap { if case .approval(let a) = $0 { return a.id } else { return nil } }
        }

        var isDone: Bool {
            frames.contains { if case .done = $0 { return true } else { return false } }
        }
    }

    private func waitUntil(
        _ label: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for \(label)"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testARunPausesForPermissionRatherThanRunningToCompletion() async throws {
        // The pause is the whole point. Under `bash: always_ask` every real run
        // stops here, so a mock that ran straight through would let a UI ship
        // that never handles the state a founder spends most of their time in.
        let runner = MockEngineeringRunner()
        let collector = Collector()
        _ = try await runner.start(ask: "add stripe checkout") { collector.append($0) }

        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }

        XCTAssertFalse(collector.isDone, "the run must be waiting on the founder, not finished")
        XCTAssertEqual(collector.approvalIds, ["tu_1"])
    }

    func testApprovingResumesTheRunAndFinishesIt() async throws {
        let runner = MockEngineeringRunner()
        let collector = Collector()
        _ = try await runner.start(ask: "add stripe checkout") { collector.append($0) }
        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }

        try await runner.send(runId: "run_mock_1", turn: .approve(toolUseId: "tu_1"))

        try await waitUntil("the run to finish") { collector.isDone }
        XCTAssertEqual(runner.sent, [.approve(toolUseId: "tu_1")])
    }

    func testDenyingEndsTheRunWithoutRunningTheTool() async throws {
        let runner = MockEngineeringRunner()
        let collector = Collector()
        _ = try await runner.start(ask: "add stripe checkout") { collector.append($0) }
        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }

        try await runner.send(runId: "run_mock_1", turn: .deny(toolUseId: "tu_1", reason: "not that one"))

        try await waitUntil("the run to finish") { collector.isDone }
        // The tool step must never appear — a denial that still runs the
        // command is the worst possible outcome of an approval gate.
        XCTAssertFalse(collector.names().contains { $0 == "step" && collector.frames.contains {
            if case .step(let s) = $0 { return s.label == "npm install stripe" } else { return false }
        } })
    }

    func testAnswerlessTurnsForAToolThatIsNotPendingChangeNothing() async throws {
        // A real backend accepts a confirmation for an id it is not waiting on
        // and nothing happens. Inventing a response here would let the store
        // be written against behaviour the backend does not have.
        let runner = MockEngineeringRunner()
        let collector = Collector()
        _ = try await runner.start(ask: "x") { collector.append($0) }
        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }
        let before = collector.frames.count

        try await runner.send(runId: "run_mock_1", turn: .approve(toolUseId: "tu_does_not_exist"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(collector.frames.count, before)
    }

    func testAStepIsCompletedByIdRatherThanDuplicated() async throws {
        // The script emits { id: "s1", label: "..." } then { id: "s1",
        // label: "", done: true } — the real completion-marker shape. A mock
        // that emitted two labelled steps would hide a store bug.
        let runner = MockEngineeringRunner()
        let collector = Collector()
        _ = try await runner.start(ask: "x") { collector.append($0) }
        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }

        let s1 = collector.frames.compactMap { frame -> ExecStep? in
            if case .step(let s) = frame, s.id == "s1" { return s } else { return nil }
        }
        XCTAssertEqual(s1.count, 2)
        XCTAssertTrue(s1[1].done)
        XCTAssertTrue(s1[1].label.isEmpty, "the completion marker carries no label")
    }

    func testTheBudgetEndingIsResumableNotAFailure() async throws {
        let runner = MockEngineeringRunner(ending: .failsAtBudget)
        let collector = Collector()
        _ = try await runner.start(ask: "x") { collector.append($0) }
        try await waitUntil("the permission ask") { !collector.approvalIds.isEmpty }

        try await runner.send(runId: "run_mock_1", turn: .approve(toolUseId: "tu_1"))
        try await waitUntil("the run to stop") { collector.isDone }

        guard case .done(let reason)? = collector.frames.last else {
            return XCTFail("expected a done frame")
        }
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: reason), .budgetReached)
    }

    // MARK: - picking the ending from the dev flag

    /// A scratch domain, so a test can never leave the real app parked on a
    /// non-default ending — a stray `CODEPET_MOCK_ENG_ENDING` would make every
    /// later demo stop at its spend cap with nothing saying why.
    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "codepet.tests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func testTheEndingDefaultsToTheOrdinaryRunWhenTheFlagIsUnset() {
        XCTAssertEqual(MockEngineeringRunner.endingFromDefaults(scratchDefaults()), .finishes)
    }

    func testTheFlagSelectsTheBudgetEnding() {
        // The reason this flag exists: the budget-paused state was reachable
        // only from the preview canvas, and copy is judged in the app.
        let d = scratchDefaults()
        d.set("budget", forKey: MockEngineeringRunner.endingKey)
        XCTAssertEqual(MockEngineeringRunner.endingFromDefaults(d), .failsAtBudget)
    }

    func testTheFlagIsForgivingAboutCaseAndStraySpace() {
        // It gets typed by hand into `defaults write`, and a value that is
        // right-but-shouty failing silently back to the default would look
        // exactly like the flag not working at all.
        let d = scratchDefaults()
        d.set("  BUDGET ", forKey: MockEngineeringRunner.endingKey)
        XCTAssertEqual(MockEngineeringRunner.endingFromDefaults(d), .failsAtBudget)
    }

    func testTheFlagSelectsTheSecondPause() {
        let d = scratchDefaults()
        d.set("pauses", forKey: MockEngineeringRunner.endingKey)
        XCTAssertEqual(MockEngineeringRunner.endingFromDefaults(d), .pausesAgain)
    }

    func testATypoFallsBackToTheOrdinaryRunRatherThanSomeOtherOne() {
        // Failing back to `.finishes` is the only safe direction: a misspelled
        // flag that silently produced a DIFFERENT ending would have someone
        // review the wrong state and believe they had seen the right one.
        let d = scratchDefaults()
        d.set("budgett", forKey: MockEngineeringRunner.endingKey)
        XCTAssertEqual(MockEngineeringRunner.endingFromDefaults(d), .finishes)
    }

    func testAttachReplaysHistorySoTheStoreMustTolerateRepeats() async throws {
        // A real reattach replays what already happened. Any consumer that
        // cannot dedupe will show two of everything.
        let runner = MockEngineeringRunner()
        let collector = Collector()
        try await runner.attach(runId: "run_mock_1") { collector.append($0) }

        try await waitUntil("the replayed ask") { !collector.approvalIds.isEmpty }
        XCTAssertTrue(collector.names().contains("step"))
    }

    // MARK: - diff

    func testTheDiffCarriesABinaryFileSoThePaneMustRenderOne() async throws {
        let runner = MockEngineeringRunner()
        let diff = try await runner.diff(runId: "run_mock_1", scope: .branch)
        XCTAssertTrue(diff.files.contains { $0.isBinary },
                      "a binary row is a state the pane must handle, not an edge case to skip")
    }

    func testAskingForOneTurnReturnsTheBranchAndSaysSo() async throws {
        // Exactly what engDiff does until lastTurnBaseSha is written. A mock
        // that returned a clean turn diff would let the pane ship with no
        // handling for the flag it will actually receive.
        let runner = MockEngineeringRunner()
        let diff = try await runner.diff(runId: "run_mock_1", scope: .turn)
        XCTAssertTrue(diff.scopeFellBack)
        XCTAssertEqual(diff.scope, .branch)
    }

    func testTheDiffTotalsMatchItsFiles() async throws {
        let runner = MockEngineeringRunner()
        let diff = try await runner.diff(runId: "run_mock_1", scope: .branch)
        XCTAssertEqual(diff.additions, diff.files.reduce(0) { $0 + $1.additions })
        XCTAssertEqual(diff.deletions, diff.files.reduce(0) { $0 + $1.deletions })
    }
}

/// The wire bodies `engSendTurn.buildTurnEvents` parses. Wrong here means a
/// 400 the founder cannot act on, or — worse — a silently ignored answer that
/// leaves the run paused forever.
final class EngineeringTurnBodyTests: XCTestCase {

    func testTextSendsTheTextField() {
        XCTAssertEqual(EngineeringTurn.text("carry on").body["text"] as? String, "carry on")
    }

    func testApproveSendsAllowTrueAgainstTheToolUseId() {
        let approve = EngineeringTurn.approve(toolUseId: "tu_1").body["approve"] as? [String: Any]
        XCTAssertEqual(approve?["toolUseId"] as? String, "tu_1")
        XCTAssertEqual(approve?["allow"] as? Bool, true)
    }

    func testDenySendsAllowFalse() {
        let approve = EngineeringTurn.deny(toolUseId: "tu_1", reason: nil).body["approve"] as? [String: Any]
        XCTAssertEqual(approve?["allow"] as? Bool, false)
        XCTAssertNil(approve?["reason"], "an absent reason must not be sent as an empty string")
    }

    func testDenyCarriesAReasonWhenThereIsOne() {
        // A denial with a reason lets the agent try another way instead of
        // stalling against a wall it cannot see the shape of.
        let approve = EngineeringTurn.deny(toolUseId: "tu_1", reason: "use pnpm").body["approve"] as? [String: Any]
        XCTAssertEqual(approve?["reason"] as? String, "use pnpm")
    }

    func testAWhitespaceOnlyReasonIsOmittedRatherThanSent() {
        // engSendTurn trims and drops it anyway; sending it invites the two
        // sides to disagree about what counts as a reason.
        let approve = EngineeringTurn.deny(toolUseId: "tu_1", reason: "   ").body["approve"] as? [String: Any]
        XCTAssertNil(approve?["reason"])
    }

    func testInterruptSendsTheInterruptFlag() {
        XCTAssertEqual(EngineeringTurn.interrupt.body["interrupt"] as? Bool, true)
    }
}

/// One case per status the handlers return, so a refusal is mapped once and
/// every surface says the same words.
final class EngineeringErrorTests: XCTestCase {

    func testTheTwoNineOhNinesAreDifferentProblems() {
        // "Connect a repo" and "connect GitHub" need different fixes; folding
        // them together sends a founder to the wrong screen.
        XCTAssertEqual(EngineeringError.from(status: 409, code: "no_repo_linked"), .noRepoLinked)
        XCTAssertEqual(EngineeringError.from(status: 409, code: "github_not_connected"), .gitHubNotConnected)
    }

    func testMapsTheRest() {
        XCTAssertEqual(EngineeringError.from(status: 402, code: "no_credits"), .noCredits)
        XCTAssertEqual(EngineeringError.from(status: 500, code: "misconfigured"), .misconfigured)
        XCTAssertEqual(EngineeringError.from(status: 503, code: "lookup_failed"), .unavailable)
    }

    func testAnUnmappedStatusIsNotSilentlyTreatedAsOneThatIs() {
        XCTAssertEqual(EngineeringError.from(status: 418, code: nil), .unknown(418))
    }
}
