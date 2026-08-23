import XCTest
@testable import codepet

/// Unclean-termination detection: set a flag on launch, clear it on graceful
/// termination, and if it is still set next launch the previous session died.
///
/// The tests that matter here are the ones about what this scheme gets WRONG. It cannot
/// distinguish a crash from a force-quit, so the value of the whole feature rests on
/// classifying the cases it CAN rule out — a reboot, a second instance — and never
/// calling the remainder a crash.
@MainActor
final class SessionLifecycleTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "cp.diag.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func tracker(pid: Int32 = 1000, bootTime: Int64 = 5_000,
                         alive: @escaping (Int32) -> Bool = { _ in false },
                         now: Date = Date(timeIntervalSince1970: 1_000_000))
    -> SessionLifecycleTracker {
        SessionLifecycleTracker(defaults: defaults, key: "cp_diag_session_v1",
                                currentPid: pid, bootTime: bootTime,
                                isProcessAlive: alive, now: { now })
    }

    // MARK: - The happy path both ways

    func testTheFirstEverLaunchIsNotReportedAsADeath() {
        XCTAssertEqual(tracker().claimLaunch(launchId: "L1"), .firstLaunch)
    }

    func testALaunchThatQuitGracefullyIsReportedAsCleanAndNotAsAFirstLaunch() {
        // `.clean` has to be REACHABLE. The first version of `recordCleanExit` deleted
        // the record, so the next launch saw nothing and answered `.firstLaunch` —
        // "quit normally yesterday" and "never run before" were indistinguishable.
        // Neither produces a document, so nothing was mis-reported, but the outcome the
        // API returned was false and the next reader of it would have inherited that.
        let first = tracker(pid: 1000)
        _ = first.claimLaunch(launchId: "L1")
        first.recordCleanExit()

        let second = tracker(pid: 1001)
        XCTAssertEqual(second.claimLaunch(launchId: "L2"), .clean)
    }

    func testANonOwningInstanceCannotSignOffOnTheSessionThatActuallyOwnsTheFlag() {
        // Two instances share one flag. Without an owner check, the first to quit
        // cleanly marks the record ended — and the instance that is still running and
        // then crashes gets reported as a clean quit.
        let owner = tracker(pid: 1000, bootTime: 5_000)
        _ = owner.claimLaunch(launchId: "L1")
        let stranger = tracker(pid: 2222, bootTime: 5_000)
        stranger.recordCleanExit()

        let next = tracker(pid: 3333, bootTime: 5_000, alive: { _ in false })
        guard case .unclean(let cause, _) = next.claimLaunch(launchId: "L3") else {
            return XCTFail("the owner's session never ended cleanly and must be reported")
        }
        XCTAssertEqual(cause, .unknown)
    }

    func testALaunchThatNeverReachedWillTerminateIsReportedAsUncleanWithNoProvableCause() {
        // No clean exit, same boot, the old pid gone: a native crash, a force-quit, an
        // OS memory kill or a hang the founder ended from the Dock. We cannot tell those
        // apart without a crash SDK, and `.unknown` is the honest name for that.
        let first = tracker(pid: 1000, bootTime: 5_000)
        _ = first.claimLaunch(launchId: "L1")

        let second = tracker(pid: 1001, bootTime: 5_000, alive: { _ in false })
        guard case .unclean(let cause, let record) = second.claimLaunch(launchId: "L2") else {
            return XCTFail("a session that never cleared its flag must be reported")
        }
        XCTAssertEqual(cause, .unknown)
        XCTAssertEqual(record.pid, 1000)
        XCTAssertEqual(record.launchId, "L1")
    }

    // MARK: - The false positives this scheme would otherwise produce

    func testARebootIsNotReportedAsACrashOfTheAppThatWasOpenAcrossIt() {
        // The founder shuts down with the app open, or the machine loses power. The flag
        // survives; the session did die; it was not our bug. Counted as a crash it would
        // inflate every beta number.
        let first = tracker(pid: 1000, bootTime: 5_000)
        _ = first.claimLaunch(launchId: "L1")

        let second = tracker(pid: 1001, bootTime: 9_999, alive: { _ in false })
        guard case .unclean(let cause, _) = second.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(cause, .systemRestart)
    }

    func testASecondInstanceLaunchingBesideALiveFirstOneIsNotReportedAsADeathAtAll() {
        // Routine in this project: `open -n`, or an Xcode run next to a released copy.
        // Nothing died — the flag's owner is still running — and reporting it as a crash
        // would manufacture failures out of the team's own workflow.
        let first = tracker(pid: 1000, bootTime: 5_000)
        _ = first.claimLaunch(launchId: "L1")

        let second = tracker(pid: 1001, bootTime: 5_000, alive: { $0 == 1000 })
        guard case .unclean(let cause, _) = second.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(cause, .concurrentInstance)
    }

    func testARecycledPidAfterARebootIsClassifiedAsTheRebootAndNotAsASecondInstance() {
        // Order-of-checks guard, and it protects against a false NEGATIVE — the
        // expensive direction. Pids are handed out from low numbers after a boot, so a
        // stale pid is very likely alive again as something unrelated. Checking
        // "is that pid alive" BEFORE "did the machine reboot" would file a real death
        // as a harmless second instance and we would never hear about it.
        let outcome = SessionLifecycleTracker.classify(
            SessionRecord(launchId: "L1", pid: 1000, bootTime: 5_000, startedAt: Date(),
                          context: [:], exceptionName: nil, endedCleanly: false),
            currentBootTime: 9_999, currentPid: 1001, isProcessAlive: { _ in true })
        guard case .unclean(let cause, _) = outcome else { return XCTFail("expected unclean") }
        XCTAssertEqual(cause, .systemRestart)
    }

    // MARK: - Uncaught exceptions

    func testAnUncaughtExceptionRecordedAsTheProcessDiedIsReportedOnTheNextLaunch() {
        // Firestore is unreachable from an exception handler — an async write cannot
        // outlive the process — so the record goes to UserDefaults and surfaces one
        // launch late. That delay is the design, not a bug.
        let first = tracker(pid: 1000, bootTime: 5_000)
        _ = first.claimLaunch(launchId: "L1")
        first.recordUncaughtException(name: "NSInvalidArgumentException")

        let second = tracker(pid: 1001, bootTime: 5_000)
        guard case .unclean(let cause, let record) = second.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(cause, .uncaughtException)
        XCTAssertEqual(record.exceptionName, "NSInvalidArgumentException")
    }

    func testAnExceptionOutranksARebootBecauseItIsTheOneCauseWeCanProve() {
        let first = tracker(pid: 1000, bootTime: 5_000)
        _ = first.claimLaunch(launchId: "L1")
        first.recordUncaughtException(name: "NSRangeException")

        let second = tracker(pid: 1001, bootTime: 9_999, alive: { _ in true })
        guard case .unclean(let cause, _) = second.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(cause, .uncaughtException)
    }

    func testAnExceptionNameThatLooksLikeAMessageIsRedactedRatherThanStored() {
        // `NSException.name` is normally a constant, but nothing guarantees it. The
        // adjacent `reason` — which IS a free-form message and can quote a path or a
        // value the founder typed — is never read at all.
        let tracker = self.tracker(pid: 1000)
        _ = tracker.claimLaunch(launchId: "L1")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        tracker.recordUncaughtException(name: "failed opening \(home)/deck.pdf")

        let next = self.tracker(pid: 1001)
        guard case .unclean(_, let record) = next.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(record.exceptionName, DiagnosticRedaction.redacted)
    }

    // MARK: - Context

    func testBreadcrumbsAreSanitisedOnTheWayIntoTheSessionRecordNotOnTheWayOut() {
        // The record is written by an exception handler with the process one frame from
        // gone. There is no "later" in which to be careful, so the redaction has to
        // already have happened.
        let tracker = self.tracker(pid: 1000)
        _ = tracker.claimLaunch(launchId: "L1")
        tracker.updateContext(["tab": "chat",
                               "file": "/Users/someone/.codepet/session_chats.json"])

        let next = self.tracker(pid: 1001)
        guard case .unclean(_, let record) = next.claimLaunch(launchId: "L2") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(record.context["tab"], "chat")
        XCTAssertEqual(record.context["file"], DiagnosticRedaction.redacted)
    }

    func testAnotherInstancesContextUpdateCannotOverwriteThisSessionsRecord() {
        // Two instances share one flag. The one that does not own it must not rewrite
        // the other's breadcrumbs, or an unclean exit would be reported with the wrong
        // session's context.
        let owner = tracker(pid: 1000)
        _ = owner.claimLaunch(launchId: "L1")
        owner.updateContext(["tab": "chat"])

        let stranger = tracker(pid: 2222)
        stranger.updateContext(["tab": "roadmap"])

        let next = tracker(pid: 3333)
        guard case .unclean(_, let record) = next.claimLaunch(launchId: "L3") else {
            return XCTFail("expected an unclean outcome")
        }
        XCTAssertEqual(record.context["tab"], "chat")
    }
}
