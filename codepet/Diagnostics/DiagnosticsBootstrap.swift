// codepet/Diagnostics/DiagnosticsBootstrap.swift
import AppKit
import FirebaseFirestore
import Foundation

/// Wires diagnostics into the app's launch and quit. Called once from `CodePetApp.init`,
/// and never under XCTest — which is what keeps every other test suite free of Firebase,
/// of a real `UserDefaults` write, and of an installed exception handler.
enum DiagnosticsBootstrap {
    /// `-CODEPET_DIAG_SELFTEST YES` writes one `selfTest` diagnostic and READS IT BACK,
    /// printing PASS or FAIL. It exists because "the call did not throw" is not evidence
    /// that a Firestore write landed — a rules rejection is delivered asynchronously and
    /// a dropped one is indistinguishable from success at the call site.
    ///
    /// Must be passed as a LAUNCH ARGUMENT (`--args -CODEPET_DIAG_SELFTEST YES`), not
    /// `defaults write`: a stale sandbox container makes `defaults write` on this bundle
    /// id silently no-op, and `defaults read` then confirms the lie.
    static var selfTestRequested: Bool {
        UserDefaults.standard.bool(forKey: "CODEPET_DIAG_SELFTEST")
    }

    /// The exception handler is a C function pointer and can capture nothing, so both
    /// the chained handler and the tracker it writes through have to be statics.
    private nonisolated(unsafe) static var previousExceptionHandler:
        (@convention(c) (NSException) -> Void)?
    private nonisolated(unsafe) static var terminateObserver: NSObjectProtocol?
    private nonisolated(unsafe) static var didRunSelfTest = false

    static func start(reporter: DiagnosticsReporter = .shared,
                      tracker: SessionLifecycleTracker = SessionLifecycleTracker()) {
        SessionLifecycleTracker.shared = tracker
        installUncaughtExceptionHandler()

        // Claimed as early as we can get to it. Anything that crashes before this line
        // — `FontRegistrar`, `FirebaseApp.configure()` — is invisible to this scheme,
        // and that is a real gap, not a rounding error.
        let outcome = tracker.claimLaunch(launchId: reporter.currentLaunchId)
        // Logged BEFORE the Firestore report and independently of it. Unclean-exit
        // detection is purely local, so this line survives a down network, a signed-out
        // founder and a rejected write — it is the only part of this feature that cannot
        // be defeated by the destination being wrong, and therefore the way to verify
        // crash detection without a round trip.
        DiagnosticsLog.note(DiagnosticsLog.lifecycle, DiagnosticsLog.previousSession(outcome))
        report(outcome, to: reporter)

        // `willTerminateNotification` is the graceful path: ⌘Q, the Quit menu item, and
        // a normal logout or restart all post it. A `SIGKILL`, a signal crash, or a
        // force-quit do not — which is exactly the discrimination this feature runs on.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            SessionLifecycleTracker.shared?.recordCleanExit()
        }

        reporter.install(sink: FirestoreDiagnosticsSink())
    }

    /// Turns the previous session's outcome into a diagnostic, or into nothing.
    ///
    /// Split out and internal so its decision table is testable without a process
    /// lifecycle: which outcomes are worth a document, and what each one is called.
    static func report(_ outcome: PreviousSessionOutcome, to reporter: DiagnosticsReporter) {
        guard let event = event(for: outcome) else { return }
        reporter.record(event)
    }

    static func event(for outcome: PreviousSessionOutcome) -> DiagnosticEvent? {
        switch outcome {
        case .firstLaunch, .clean:
            // Nothing to say. A clean quit is the overwhelming majority of launches and
            // a document per launch would drown the beta's real signal in noise —
            // there is no denominator question this answers that the app's own
            // analytics could not.
            return nil

        case .unclean(let cause, let record):
            var context = record.context
            context["cause"] = cause.rawValue
            if let name = record.exceptionName { context["exception"] = name }
            // A duration bucket rather than a duration: it says "died on launch" vs
            // "died after an hour" — the difference between a startup bug and a leak —
            // without becoming a usage-tracking field.
            context["sessionAge"] = ageBucket(record.startedAt)
            return DiagnosticEvent(
                kind: cause == .uncaughtException ? .uncaughtException : .uncleanExit,
                site: .sessionLifecycle,
                shape: DiagnosticErrorShape(type: cause.rawValue, domain: nil, code: nil,
                                            codingPath: nil),
                context: context
            )
        }
    }

    /// Coarse on purpose. Six buckets is enough to separate a launch crash from a
    /// long-session one, and is not a record of when the founder was working.
    static func ageBucket(_ startedAt: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(startedAt)
        if seconds < 0 { return "unknown" }
        if seconds < 10 { return "under10s" }
        if seconds < 60 { return "under1m" }
        if seconds < 600 { return "under10m" }
        if seconds < 3600 { return "under1h" }
        if seconds < 28800 { return "under8h" }
        return "over8h"
    }

    private static func installUncaughtExceptionHandler() {
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            // Name only. `NSException.reason` is a free-form message with nothing
            // stopping it from quoting a path or a value the founder typed, and this
            // process is one frame from gone — there is no room to be careful later.
            SessionLifecycleTracker.shared?
                .recordUncaughtException(name: exception.name.rawValue)
            DiagnosticsBootstrap.previousExceptionHandler?(exception)
        }
    }

    // MARK: - Self-test

    /// Called when identity first exists (see `CompanyStore.hydrate`). Writes one
    /// diagnostic and reads it back.
    static func runSelfTestIfRequested(uid: String) {
        // `AppEnvironment.isRunningTests` as well as the flag: this is reached from
        // `CompanyStore.hydrate`, which many suites drive, and `Firestore.firestore()`
        // traps with no configured app. The flag alone would be enough today — nothing
        // sets it under test — but "the reporter must never be the crash" is not a rule
        // to leave resting on one condition.
        guard !AppEnvironment.isRunningTests, selfTestRequested, !didRunSelfTest else { return }
        didRunSelfTest = true
        let nonce = UUID().uuidString
        DiagnosticsReporter.shared.record(
            kind: .selfTest, site: .sessionLifecycle, context: ["nonce": nonce])
        // `Logger` first, `print` second. The `print` costs nothing and is convenient
        // when the app happens to be attached to a debugger, but it is NOT the record —
        // a GUI app's stdout is discarded by `open` and comes back as a 0-byte file
        // under a redirect, so the `Logger` line is the only thing a human can read
        // after the fact.
        DiagnosticsLog.note(DiagnosticsLog.selfTest,
                            "self-test wrote nonce=\(nonce); reading back in 3s")
        print("[Diagnostics] self-test wrote nonce=\(nonce); reading back in 3s…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Firestore.firestore()
                .collection("companies").document(uid)
                .collection(FirestoreDiagnosticsSink.collection)
                .whereField("ctx_nonce", isEqualTo: nonce)
                .getDocuments { snapshot, error in
                    let message: String
                    let failed: Bool
                    if let error {
                        message = DiagnosticsLog.selfTestFailedOnRead(error)
                        failed = true
                    } else if (snapshot?.documents.count ?? 0) >= 1 {
                        message = DiagnosticsLog.selfTestPassed(uid: uid)
                        failed = false
                    } else {
                        message = DiagnosticsLog.selfTestFailedNoDocument(nonce: nonce)
                        failed = true
                    }
                    // A FAIL goes out at error level so it is greppable as a failure;
                    // both levels are visible to `log show` with no extra flags.
                    if failed {
                        DiagnosticsLog.failure(DiagnosticsLog.selfTest, message)
                    } else {
                        DiagnosticsLog.note(DiagnosticsLog.selfTest, message)
                    }
                    print("[Diagnostics] \(message)")
                }
        }
    }
}
