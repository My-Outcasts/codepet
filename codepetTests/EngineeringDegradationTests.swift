// codepetTests/EngineeringDegradationTests.swift
import XCTest
@testable import codepet

/// Every backend refusal a founder can actually hit, and the wording it earns.
///
/// The statuses are fixed by Plan 1; this suite pins the mapping and the words.
/// Two of these tests exist because writing them found live bugs — a paused run
/// told the founder to connect a repo, and the message that said so never
/// reached them at all.
final class EngineeringDegradationMappingTests: XCTestCase {

    // MARK: - status → error

    func test_402IsOutOfCredits() {
        XCTAssertEqual(EngineeringError.from(status: 402, code: "no_credits"), .noCredits)
    }

    func test_409WithoutACodeIsTheMissingRepo() {
        XCTAssertEqual(EngineeringError.from(status: 409, code: nil), .noRepoLinked)
    }

    func test_409GitHubNotConnectedIsItsOwnFix() {
        // Connecting GitHub and linking a repo are different actions. Folding
        // them together sends the founder to the wrong screen.
        XCTAssertEqual(EngineeringError.from(status: 409, code: "github_not_connected"),
                       .gitHubNotConnected)
    }

    func test_aPausedRunIsNotAMissingRepo() {
        // THE BUG THIS SUITE FOUND. `engSendTurn.ts:118` answers a turn on a
        // budget-paused run with 409 `budget_reached`. The fallback below it
        // folds every unrecognised 409 into `.noRepoLinked`, so a founder whose
        // run paused at its limit was told to connect a repo they linked days
        // ago — an instruction they can follow, that cannot help, on a run that
        // is sitting there intact.
        XCTAssertEqual(EngineeringError.from(status: 409, code: "budget_reached"),
                       .budgetReached)
    }

    func test_500IsOurs() {
        XCTAssertEqual(EngineeringError.from(status: 500, code: "misconfigured"), .misconfigured)
    }

    func test_503IsRetryable() {
        XCTAssertEqual(EngineeringError.from(status: 503, code: nil), .unavailable)
    }

    func test_anUnmappedStatusKeepsItsNumberRatherThanPosingAsAKnownOne() {
        XCTAssertEqual(EngineeringError.from(status: 418, code: nil), .unknown(418))
    }

    // MARK: - which failures earn a retry control

    func test_onlyTheTransientFailureOffersARetry() {
        // A retry button that re-runs the same refusal teaches the founder the
        // button is decoration — after which they stop believing the one place
        // it works.
        XCTAssertTrue(EngineeringError.unavailable.isRetryable)
        for error: EngineeringError in [.noRepoLinked, .gitHubNotConnected, .noCredits,
                                        .budgetReached, .misconfigured, .unknown(500)] {
            XCTAssertFalse(error.isRetryable, "\(error) offers a retry that cannot succeed")
        }
    }

    // MARK: - the words

    func test_everyRefusalHasCopyInBothLanguages() {
        let all: [EngineeringError] = [.noRepoLinked, .gitHubNotConnected, .noCredits,
                                       .budgetReached, .misconfigured, .unavailable, .unknown(0)]
        for error in all {
            let en = EngineeringResultBar.message(for: error, lang: .en)
            let vi = EngineeringResultBar.message(for: error, lang: .vi)
            XCTAssertFalse(en.isEmpty, "\(error) has no English copy")
            XCTAssertFalse(vi.isEmpty, "\(error) has no Vietnamese copy")
            XCTAssertNotEqual(en, vi, "\(error) shows English to a Vietnamese founder")
        }
    }

    func test_ourOwnBreakageIsNeverTheFoundersFault() {
        // `misconfigured` is a deploy problem. Any phrasing that puts it on the
        // founder sends them hunting for a setting that does not exist.
        let en = EngineeringResultBar.message(for: .misconfigured, lang: .en).lowercased()
        XCTAssertTrue(en.contains("our side") || en.contains("we"),
                      "misconfigured must own the fault: \(en)")
        for blame in ["you ", "your "] {
            XCTAssertFalse(en.contains(blame), "misconfigured blames the founder: \(en)")
        }
    }

    func test_theCreditRefusalNamesWhatARunNeeds() {
        // The balance is definitionally 0 at this refusal, so printing it says
        // nothing. The number the founder can act on is what to top up TO.
        let en = EngineeringResultBar.message(for: .noCredits, lang: .en)
        XCTAssertTrue(en.contains("\(EngineeringRun.creditsPerRun)"),
                      "the credit refusal names no number: \(en)")
    }

    func test_aPausedRunIsNeverWordedAsAFailure() {
        // Telling a founder their work failed when it is intact makes them
        // start over and pay twice.
        for lang: AppLanguage in [.en, .vi] {
            let text = EngineeringResultBar.message(for: .budgetReached, lang: lang).lowercased()
            for word in ["failed", "error", "lỗi", "thất bại"] {
                XCTAssertFalse(text.contains(word),
                               "budgetReached reads as a failure in \(lang): \(text)")
            }
        }
        // And it must say the work survived, or "stopped" is just bad news.
        let en = EngineeringResultBar.message(for: .budgetReached, lang: .en).lowercased()
        XCTAssertTrue(en.contains("intact") || en.contains("branch"),
                      "budgetReached never says the work is safe: \(en)")
    }

    func test_theTwoPausedStatesAgreeThatNothingFailed() {
        // The phase chip and the message are two surfaces for one moment; if
        // one says "paused" and the other says "didn't finish", the founder
        // believes the worse of the two.
        let (chip, _) = EngineeringResultBar.phaseLabel(.budgetReached, lang: .en)
        XCTAssertFalse(chip.lowercased().contains("didn't"), "phase chip contradicts the message")
        XCTAssertTrue(chip.lowercased().contains("paused"), "phase chip: \(chip)")
    }
}

/// The store half: a refusal has to reach the founder, and the retry has to
/// repeat the thing that actually failed.
@MainActor
final class EngineeringRetryTests: XCTestCase {

    /// Fails a chosen operation a chosen number of times, then succeeds.
    private final class FlakyRunner: EngineeringRunning {
        enum Op { case start, send, diff }
        let failing: Op
        let error: EngineeringError
        var remainingFailures: Int
        private(set) var startCount = 0
        private(set) var sendCount = 0
        private(set) var diffCount = 0

        init(failing: Op, error: EngineeringError = .unavailable, times: Int = 1) {
            self.failing = failing
            self.error = error
            self.remainingFailures = times
        }

        private func maybeThrow(_ op: Op) throws {
            guard op == failing, remainingFailures > 0 else { return }
            remainingFailures -= 1
            throw error
        }

        func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
            startCount += 1
            try maybeThrow(.start)
            return "run_1"
        }
        func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {}
        func send(runId: String, turn: EngineeringTurn) async throws {
            sendCount += 1
            try maybeThrow(.send)
        }
        func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary {
            diffCount += 1
            try maybeThrow(.diff)
            return .empty
        }
    }

    func test_aTurnThatCannotLandIsNotSwallowed() async {
        // THE OTHER BUG THIS SUITE FOUND. `answer` used `try?`, so when a
        // budget-paused run answered 409, the card vanished, the run sat
        // paused, and nothing on screen said why — a founder watching a
        // spinner that was never going to move.
        let runner = FlakyRunner(failing: .send, error: .budgetReached, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i stripe")))

        await store.answer(toolUseId: "tu_1", allow: true)

        XCTAssertEqual(store.failure, .budgetReached, "the refusal never reached the founder")
        XCTAssertEqual(store.phase, .budgetReached, "a paused run must not read as running")
    }

    func test_aPausedRunOffersNoRetryBecauseRetryingCannotHelp() async {
        let runner = FlakyRunner(failing: .send, error: .budgetReached, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i stripe")))
        await store.answer(toolUseId: "tu_1", allow: true)

        XCTAssertFalse(store.canRetry)
    }

    func test_retryingADiffRefetchesTheDiffRatherThanRerunningTheAsk() async {
        // The expensive confusion this guards: one shared "try again" that
        // always re-runs the ask would spend a founder's credits again to fix
        // a diff that merely failed to load, on work that already succeeded.
        let runner = FlakyRunner(failing: .diff, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")
        await store.loadDiff(scope: .branch)

        XCTAssertEqual(store.failure, .unavailable)
        XCTAssertTrue(store.canRetry)

        await store.retry()

        XCTAssertEqual(runner.startCount, 1, "the retry re-ran the ask and re-spent credits")
        XCTAssertEqual(runner.diffCount, 2, "the retry did not refetch the diff")
        XCTAssertNil(store.failure, "a successful retry left the failure on screen")
    }

    func test_retryingAFailedStartStartsTheRunAgain() async {
        let runner = FlakyRunner(failing: .start, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")

        XCTAssertEqual(store.failure, .unavailable)
        XCTAssertTrue(store.canRetry)

        await store.retry()

        XCTAssertEqual(runner.startCount, 2)
        XCTAssertNil(store.failure)
        XCTAssertEqual(store.runId, "run_1")
    }

    func test_theRetryIsSpentOnceSoATwitchyDoubleTapIsNotTwoRuns() async {
        // Two retries of one start are two runs and two bills.
        let runner = FlakyRunner(failing: .start, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")

        await store.retry()
        await store.retry()

        XCTAssertEqual(runner.startCount, 2, "the second tap started a second run")
    }

    func test_aDiffThatLoadsClearsAnEarlierRefusal() async {
        // A stale failure sitting under a diff that loaded reads as a diff you
        // cannot trust.
        let runner = FlakyRunner(failing: .diff, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")
        await store.loadDiff(scope: .branch)
        XCTAssertNotNil(store.failure)

        await store.loadDiff(scope: .branch)
        XCTAssertNil(store.failure)
        XCTAssertFalse(store.canRetry)
    }

    func test_aFailedDiffDoesNotMarkTheRunFailed() async {
        // The work happened and the branch exists. Saying otherwise sends a
        // founder off to re-run something that already succeeded.
        let runner = FlakyRunner(failing: .diff, times: 1)
        let store = EngineeringRunStore(runner: runner)
        await store.start(ask: "add stripe checkout")
        let before = store.phase
        await store.loadDiff(scope: .branch)

        XCTAssertEqual(store.phase, before, "a diff fetch failure changed the run's phase")
    }
}
