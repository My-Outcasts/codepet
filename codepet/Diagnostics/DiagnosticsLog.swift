// codepet/Diagnostics/DiagnosticsLog.swift
import Foundation
import os

/// **The local half of diagnostics: what the founder's machine can be asked, after the
/// fact, about the reporter itself.**
///
/// Read it with — note the absolute path, because zsh in this repo has its own `log`
/// that eats the arguments:
///
/// ```
/// /usr/bin/log show --last 5m --predicate 'subsystem == "app.murror.codepet.diagnostics"' --style compact
/// ```
///
/// **This module shipped with `print` and that made its own self-test worthless.** The
/// self-test writes a document and reads it back, which is the only thing that converts
/// "the Firestore path is authorised" from an inference into a fact — and it announced
/// its PASS/FAIL to stdout. A GUI app's stdout goes nowhere: `open` discards it, and
/// running `Contents/MacOS/codepet` directly with stdout redirected produces a 0-byte
/// file (measured, not assumed). So the one verification step in the whole feature was
/// unreadable, which is the same shape as the failure it exists to prevent: something
/// that looks instrumented and tells you nothing. `VoiceLog` had already learned this
/// and written it down; this module did not read it.
///
/// **Its own subsystem, not `app.murror.codepet` + a category.** One predicate should
/// read the whole thing, without the reader having to get a category filter right while
/// chasing a bug. Same reasoning as `app.murror.codepet.voice`.
///
/// **Every level is default (`log`) or `error`, and nothing is `.debug` — or `.info`.**
/// `log show` without `--info --debug` shows only default level and above, so a `.debug`
/// line is another invisible success. `.info` is hidden by exactly the same rule, and
/// the read command documented above passes neither flag, so `.info` is banned here too.
///
/// **Interpolation privacy is centralised into `note` and `failure`, and there is
/// nowhere else in this module that interpolates into a `Logger`.** `Logger`'s default
/// interpolation privacy is `.private`, which renders every value as `<private>` when
/// read from another process — a trace of `<private>` is not a trace. Rather than
/// repeating `privacy: .public` at twenty call sites and relying on nobody forgetting
/// once, callers pass a plain `String` and the two functions below are the only places
/// the rule has to hold.
///
/// **Every member is `nonisolated`, and that is load-bearing.** Under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` even a `static let` on an enum is
/// *inferred* main-actor, and this module is read from `VirtualCompanyEvent.decode`
/// inside `Task.detached` and from an uncaught-exception handler on whatever thread
/// threw. Same reasoning, and the same fix, as `VoiceLog`.
///
/// **What is logged here is deliberately more than what is uploaded.** The Firestore
/// payload records shape only — no paths, no error descriptions (see
/// `DiagnosticRedaction`). This log never leaves the founder's machine unless she
/// chooses to send it, so it may carry an error's `localizedDescription`, which is
/// often the only readable part of a Firestore permission failure. It still carries no
/// message text, no prompt and no deliverable body: the same line `VoiceLog` draws when
/// it logs a transcript's *length* and never its words.
nonisolated enum DiagnosticsLog {

    nonisolated static let subsystem = "app.murror.codepet.diagnostics"

    /// `-CODEPET_DIAG_SELFTEST YES`: the write, and whether reading it back found it.
    nonisolated static let selfTest = Logger(subsystem: subsystem, category: "selfTest")
    /// The Firestore write itself — in particular, its rejections.
    nonisolated static let sink = Logger(subsystem: subsystem, category: "sink")
    /// What the reporter accepted, buffered, and flushed.
    nonisolated static let reporter = Logger(subsystem: subsystem, category: "reporter")
    /// Launch and quit: what the previous session's outcome was judged to be.
    nonisolated static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

    // MARK: - The only two interpolation sites in this module

    /// Default level: persisted, and visible to `log show` with no extra flags.
    nonisolated static func note(_ logger: Logger, _ message: String) {
        logger.log("\(message, privacy: .public)")
    }

    /// Error level. Also visible with no extra flags, and greppable as a failure.
    nonisolated static func failure(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    // MARK: - Messages worth building carefully

    /// **Domain and code, not `localizedDescription` alone.** A Firestore rules
    /// rejection and a network failure both render as an unhelpful sentence, and
    /// `FIRFirestoreErrorDomain/7` (`permissionDenied`) is the one that means "the rule
    /// is missing" — the single most important thing this log can tell anyone. The
    /// description is kept as well, last, because it is occasionally the readable part.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)/\(ns.code) — \(ns.localizedDescription)"
    }

    /// The line a human reads to decide whether the destination works.
    ///
    /// Built as a pure function so its content is testable without a log store: the
    /// wording is the deliverable here, not an implementation detail. It has to name the
    /// path, because "PASS" without a path does not tell you *what* passed.
    nonisolated static func selfTestPassed(uid: String) -> String {
        "SELF-TEST PASS — the write landed and was read back at companies/\(uid)/diagnostics"
    }

    /// Names the likely cause, because a bare FAIL sends the reader to the wrong place.
    /// A rejected write is a rules problem; a missing document after a clean write is
    /// replication lag.
    nonisolated static func selfTestFailedNoDocument(nonce: String) -> String {
        """
        SELF-TEST FAIL — no document with nonce=\(nonce). The write was rejected \
        (check firestore.rules for the companies/{uid}/{sub} write allow) or has not \
        replicated yet.
        """
    }

    nonisolated static func selfTestFailedOnRead(_ error: Error) -> String {
        "SELF-TEST FAIL — reading back errored: \(describe(error))"
    }

    /// How the previous session ended, as one readable line.
    ///
    /// **This is the highest-value line in the module, and it owes nothing to Firestore.**
    /// Unclean-termination detection is entirely local — a `UserDefaults` flag and a
    /// `kern.boottime` comparison — so this line is readable on a founder's machine even
    /// if the network is down, nobody is signed in, or the rules reject every write. It
    /// is the one part of this feature that cannot be defeated by the destination being
    /// wrong, which also makes it the way to test crash detection without a round trip.
    nonisolated static func previousSession(_ outcome: PreviousSessionOutcome) -> String {
        switch outcome {
        case .firstLaunch:
            return "previous session: none (first launch, or a fresh container)"
        case .clean:
            return "previous session: ended cleanly"
        case .unclean(let cause, let record):
            // The cause is spelled out rather than left as "unclean", because the whole
            // point of classifying it is that a reader must not read `concurrentInstance`
            // or `systemRestart` as a crash.
            let exception = record.exceptionName.map { ", exception=\($0)" } ?? ""
            return """
                previous session: DID NOT END CLEANLY — cause=\(cause.rawValue)\(exception), \
                launchId=\(record.launchId), pid=\(record.pid)
                """
        }
    }

    /// The sink's rejection line.
    ///
    /// This is the one failure diagnostics cannot report through itself: the channel
    /// that would carry the report is the channel that just failed, and re-reporting it
    /// would recurse. So this log line is the *only* place a rejected diagnostics write
    /// is ever recorded, which is precisely why it must not be a `print`.
    nonisolated static func writeRejected(_ error: Error) -> String {
        "write REJECTED — \(describe(error)) — no diagnostic can report this; this line is the only record"
    }
}
