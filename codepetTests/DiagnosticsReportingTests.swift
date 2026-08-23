import XCTest
@testable import codepet

/// A sink that records what it was handed, and can refuse delivery on command.
private final class FakeSink: DiagnosticsSink {
    var accepted: [[String: Any]] = []
    var refuseCount = 0

    func send(_ payload: [String: Any]) -> Bool {
        if refuseCount > 0 {
            refuseCount -= 1
            return false
        }
        accepted.append(payload)
        return true
    }
}

/// The budget, the buffer, and the chat-turn decision — the three places where this
/// system decides NOT to report something. Each one is a place a real signal could be
/// lost, so each is pinned.
@MainActor
final class DiagnosticsReportingTests: XCTestCase {

    private func reporter() -> DiagnosticsReporter {
        DiagnosticsReporter(launchId: "test-launch", appVersion: "1.0", build: "1",
                            osVersion: "macOS 26.2")
    }

    // MARK: - Budget

    func testAThousandIdenticalFailuresProduceEightDocumentsAndStillReportOneThousand() {
        var budget = DiagnosticsBudget()
        var written: [Int] = []
        for _ in 1...1000 {
            if let count = budget.admit("quota") { written.append(count) }
        }
        // The ladder, then every 500th. Without it this is 1000 Firestore documents an
        // hour for one founder over their Anthropic quota.
        XCTAssertEqual(written, [1, 2, 5, 10, 25, 50, 100, 500, 1000])
        // And the number that would change a decision is still exact, not sampled.
        XCTAssertEqual(written.last, 1000)
    }

    func testTheSecondOccurrenceIsReportedSoAOneOffIsDistinguishableFromAPattern() {
        var budget = DiagnosticsBudget()
        XCTAssertEqual(budget.admit("k"), 1)
        XCTAssertEqual(budget.admit("k"), 2)
        XCTAssertNil(budget.admit("k"), "the 3rd is counted, not written")
        XCTAssertNil(budget.admit("k"))
        XCTAssertEqual(budget.admit("k"), 5)
    }

    func testANewFailureKindPastTheDistinctKeyCeilingIsDroppedButTrackedKeysKeepReporting() {
        var budget = DiagnosticsBudget()
        for i in 0..<DiagnosticsBudget.maxDistinctKeys {
            XCTAssertEqual(budget.admit("key-\(i)"), 1)
        }
        XCTAssertEqual(budget.trackedKeyCount, DiagnosticsBudget.maxDistinctKeys)
        // An error whose code is a timestamp would otherwise mint documents forever.
        XCTAssertNil(budget.admit("key-overflow"))
        XCTAssertEqual(budget.droppedKeyCount, 1)
        // The ceiling must not silence the failures we were already watching.
        XCTAssertEqual(budget.admit("key-0"), 2)
    }

    func testTheReporterAppliesTheBudgetSoARepeatedFailureIsOneDocumentNotThree() {
        let sink = FakeSink()
        let reporter = self.reporter()
        reporter.install(sink: sink)
        for _ in 0..<3 {
            reporter.record(kind: .handledError, site: .narrativeEnrich,
                            error: URLError(.timedOut), context: ["reason": "network"])
        }
        XCTAssertEqual(sink.accepted.count, 2, "occurrences 1 and 2 write; the 3rd only counts")
        XCTAssertEqual(sink.accepted.last?["count"] as? Int, 2)
    }

    // MARK: - Buffering

    func testAFailureRecordedBeforeAnyoneIsSignedInIsHeldAndDeliveredWhenIdentityArrives() {
        // This is the case the feature exists for: the previous session's unclean exit
        // and a chat-thread file that would not decode both happen at launch, before
        // there is a `companies/{uid}` path to write to. Dropping them would mean
        // reporting nothing about exactly the failures this was built for.
        let reporter = self.reporter()
        reporter.record(kind: .uncleanExit, site: .sessionLifecycle)
        reporter.record(kind: .handledError, site: .chatThreadLoad)
        XCTAssertEqual(reporter.bufferedCount, 2)

        let sink = FakeSink()
        reporter.install(sink: sink)
        XCTAssertEqual(sink.accepted.count, 2)
        XCTAssertEqual(reporter.bufferedCount, 0)
        XCTAssertEqual(sink.accepted.first?["kind"] as? String, DiagnosticKind.uncleanExit.rawValue)
    }

    func testASinkThatRefusesDeliveryGetsTheEventBackOnTheNextFlushRatherThanLosingIt() {
        // `send` returns false for "not reachable yet" — no FirebaseApp, nobody signed
        // in. Treating that as delivered is how a report vanishes while every call
        // returns without throwing, which is the exact failure shape this feature is
        // supposed to end.
        let sink = FakeSink()
        sink.refuseCount = 1
        let reporter = self.reporter()
        reporter.install(sink: sink)

        reporter.record(kind: .handledError, site: .chatTurn)
        XCTAssertEqual(sink.accepted.count, 0)
        XCTAssertEqual(reporter.bufferedCount, 1, "a refused send must be re-buffered")

        reporter.flush()
        XCTAssertEqual(sink.accepted.count, 1)
        XCTAssertEqual(reporter.bufferedCount, 0)
    }

    func testTheBufferIsCappedAndDropsTheNewestSoTheLaunchTimeReportSurvives() {
        let reporter = self.reporter()
        reporter.record(DiagnosticEvent(kind: .uncleanExit, site: .sessionLifecycle))
        // The buffer cap (50) is HIGHER than the budget's distinct-key ceiling (40), so
        // distinct keys alone cannot fill it — the first draft of this test asserted 50
        // and got 40, because the key ceiling bit first. Repeat occurrences up each
        // key's ladder instead, which is how a real failing beta session would fill it.
        for key in 0..<20 {
            for _ in 0..<11 {
                reporter.record(DiagnosticEvent(
                    kind: .handledError, site: .chatTurn,
                    shape: DiagnosticErrorShape(type: "E", domain: nil, code: key,
                                                 codingPath: nil)))
            }
        }
        XCTAssertEqual(reporter.bufferedCount, DiagnosticsReporter.maxBuffered)

        let sink = FakeSink()
        reporter.install(sink: sink)
        // The oldest buffered event is the unclean-exit report. It is the reason the
        // buffer exists, so it must be the one thing the cap never evicts.
        XCTAssertEqual(sink.accepted.first?["kind"] as? String,
                       DiagnosticKind.uncleanExit.rawValue)
    }

    // MARK: - Chat turn

    func testAStreamThatFailedButWasRecoveredByTheFallbackIsNotReported() {
        // `sendMessage` retries non-streaming. A blip the founder never saw would
        // otherwise be a Firestore document per transient network error in the beta.
        XCTAssertNil(ChatTurnDiagnostic.event(streamError: URLError(.timedOut),
                                              fallbackReplyWasNil: false))
    }

    func testATurnTheFounderGotNoAnswerToIsReportedWithTheHTTPStatusThatCausedIt() {
        let error = CompanyChatStreamError.http(status: 429, body: nil)
        let event = ChatTurnDiagnostic.event(streamError: error, fallbackReplyWasNil: true)
        let unwrapped = try? XCTUnwrap(event)
        XCTAssertEqual(unwrapped?.site, .chatTurn)
        XCTAssertEqual(unwrapped?.context["cause"], "http")
        // 429 rather than the NSError bridge's case ordinal, which is what a generic
        // classifier would have recorded and is not a status at all.
        XCTAssertEqual(unwrapped?.shape.code, 429)
    }

    func testAnEmptyReplyWithNoThrowIsReportedAsADifferentCauseFromANetworkFailure() {
        // "The request completed and the answer was empty" is ours and worse than "the
        // founder is offline". They must not collapse into one bucket.
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: nil), "emptyReply")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: URLError(.notConnectedToInternet)), "offline")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.notSignedIn),
                       "notSignedIn")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.malformedResponse),
                       "malformedResponse")
    }

    // MARK: - Previous-session reporting

    func testACleanQuitAndAFirstLaunchProduceNoDocumentAtAll() {
        XCTAssertNil(DiagnosticsBootstrap.event(for: .clean))
        XCTAssertNil(DiagnosticsBootstrap.event(for: .firstLaunch))
    }

    func testOnlyAnUncaughtExceptionIsReportedAsACrashAndTheRestAsAnUncleanExit() {
        // The honesty guard. A set-on-launch flag cannot tell a crash from a force-quit,
        // so only the cause we can PROVE gets the crash kind. Collapsing these would
        // turn an unknown into a wrong number someone acts on.
        let base = SessionRecord(launchId: "L", pid: 42, bootTime: 100,
                                 startedAt: Date(), context: [:], exceptionName: nil, endedCleanly: false)
        var withException = base
        withException.exceptionName = "NSInvalidArgumentException"

        let crash = DiagnosticsBootstrap.event(
            for: .unclean(cause: .uncaughtException, record: withException))
        XCTAssertEqual(crash?.kind, .uncaughtException)
        XCTAssertEqual(crash?.context["exception"], "NSInvalidArgumentException")

        for cause in [UncleanCause.unknown, .systemRestart, .concurrentInstance] {
            let event = DiagnosticsBootstrap.event(for: .unclean(cause: cause, record: base))
            XCTAssertEqual(event?.kind, .uncleanExit, "\(cause) is not provably a crash")
            XCTAssertEqual(event?.context["cause"], cause.rawValue,
                           "the cause must ride along so it can be filtered out")
        }
    }
}
