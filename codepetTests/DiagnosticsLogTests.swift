import OSLog
import XCTest
@testable import codepet

/// **Whether anyone can actually read what diagnostics says.**
///
/// This suite exists because the module shipped with `print`, and `print` from this app
/// goes nowhere: `open` discards stdout, and running the binary directly with stdout
/// redirected produces a 0-byte file. The self-test — the only thing that turns "the
/// Firestore path is authorised" into a fact — announced its PASS/FAIL there. So the
/// feature's one verification step was unreadable, which is the same failure shape the
/// feature exists to prevent.
///
/// Two of these tests read the unified log BACK, in-process, and would have failed on
/// the original `print` implementation.
@MainActor
final class DiagnosticsLogTests: XCTestCase {

    // MARK: - Readable at all, and at a visible level

    /// Reads entries this process wrote under the diagnostics subsystem.
    ///
    /// `.currentProcessIdentifier` scope needs no entitlement and sees only our own
    /// lines, so this cannot pick up a stray entry from another test run.
    private func readBack(since start: Date) throws -> [OSLogEntryLog] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: start)
        let entries = try store.getEntries(
            at: position,
            matching: NSPredicate(format: "subsystem == %@", DiagnosticsLog.subsystem))
        return entries.compactMap { $0 as? OSLogEntryLog }
    }

    func testALoggedLineIsReadableFromTheUnifiedLogRatherThanOnlyOnStdout() throws {
        let start = Date().addingTimeInterval(-1)
        let marker = "readability-probe-\(UUID().uuidString)"
        DiagnosticsLog.note(DiagnosticsLog.selfTest, marker)

        // The store is written asynchronously; poll briefly rather than sleeping blind.
        var found: [OSLogEntryLog] = []
        for _ in 0..<40 {
            found = try readBack(since: start).filter { $0.composedMessage.contains(marker) }
            if !found.isEmpty { break }
            usleep(50_000)
        }
        XCTAssertFalse(found.isEmpty, """
            nothing under subsystem \(DiagnosticsLog.subsystem) carried the marker — a \
            `print` would land here, which is exactly the bug this replaced
            """)
    }

    func testTheLoggedLineIsAtALevelThatLogShowDisplaysWithoutExtraFlags() throws {
        // `log show` without `--info --debug` shows only default level and above, so a
        // `.debug` or `.info` line is another invisible success. The documented read
        // command passes neither flag.
        let start = Date().addingTimeInterval(-1)
        let noteMarker = "level-probe-note-\(UUID().uuidString)"
        let failMarker = "level-probe-fail-\(UUID().uuidString)"
        DiagnosticsLog.note(DiagnosticsLog.sink, noteMarker)
        DiagnosticsLog.failure(DiagnosticsLog.sink, failMarker)

        var note: OSLogEntryLog?
        var fail: OSLogEntryLog?
        for _ in 0..<40 {
            let entries = try readBack(since: start)
            note = entries.first { $0.composedMessage.contains(noteMarker) }
            fail = entries.first { $0.composedMessage.contains(failMarker) }
            if note != nil, fail != nil { break }
            usleep(50_000)
        }

        let noteLevel = try XCTUnwrap(note?.level, "the default-level line was not readable")
        let failLevel = try XCTUnwrap(fail?.level, "the error-level line was not readable")
        for (label, level) in [("note", noteLevel), ("failure", failLevel)] {
            XCTAssertNotEqual(level, .debug, "\(label) at .debug is invisible to `log show`")
            XCTAssertNotEqual(level, .info, "\(label) at .info is invisible to `log show`")
        }
        XCTAssertEqual(failLevel, .error, "a failure must be greppable as one")
    }

    func testTheInterpolatedValueSurvivesInsteadOfRenderingAsPrivate() throws {
        // `Logger`'s default interpolation privacy is `.private`. In-process reads are
        // not redacted, so this cannot prove the cross-process case on its own — what it
        // pins is that the value reaches the message at all, and that `note`/`failure`
        // remain the only interpolation sites (a caller who logged directly with the
        // default privacy would produce `<private>` when read with `log show`).
        let start = Date().addingTimeInterval(-1)
        let value = "quota-\(UUID().uuidString)"
        DiagnosticsLog.note(DiagnosticsLog.reporter, "probe value=\(value)")

        var message: String?
        for _ in 0..<40 {
            message = try readBack(since: start)
                .first { $0.composedMessage.contains("probe value=") }?.composedMessage
            if message != nil { break }
            usleep(50_000)
        }
        let composed = try XCTUnwrap(message)
        XCTAssertTrue(composed.contains(value))
        XCTAssertFalse(composed.contains("<private>"))
    }

    /// The rule that makes the two above generalise: nothing else in the module
    /// interpolates into a `Logger`, so `privacy: .public` has exactly one place to hold.
    ///
    /// **The compiler already enforces most of this, and finding that out is what makes
    /// this test worth keeping in its narrow form.** `DiagnosticsLog.swift` is the only
    /// file in the folder that imports `os`, and this project builds with
    /// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — so a `Logger` call in any
    /// other file fails to BUILD ("instance method 'log' is not available due to missing
    /// import of defining module 'os'"), which is a better guard than any test. Verified
    /// by mutation.
    ///
    /// What the compiler does not catch is someone adding `import os` to that file first,
    /// which is exactly what a person chasing a bug would do. That is the case this test
    /// covers, and it was confirmed red by adding the import and the direct call together.
    func testNoteAndFailureAreTheOnlyInterpolationSitesInTheModule() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // codepetTests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("codepet/Diagnostics")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "the Diagnostics folder moved; this guard is stale")

        // Any `logger.<level>("…")` call outside DiagnosticsLog.swift would be a second
        // place the privacy default could bite.
        let offenders = try files.filter { name in
            guard name != "DiagnosticsLog.swift" else { return false }
            let source = try String(contentsOf: dir.appendingPathComponent(name),
                                    encoding: .utf8)
            return source.contains(".log(\"") || source.contains(".error(\"")
                || source.contains(".notice(\"") || source.contains(".debug(\"")
                || source.contains(".info(\"") || source.contains(".fault(\"")
        }
        XCTAssertEqual(offenders, [], """
            these files log directly instead of going through DiagnosticsLog.note/failure, \
            so they carry their own interpolation privacy
            """)
    }

    // MARK: - Volume

    func testAnOverflowingBufferLogsOneLineForTheWholeOverflowNotOnePerDroppedEvent() throws {
        // Found by reading the real `log show` output rather than by reasoning: the
        // first version logged every drop, so one test emitted twenty identical error
        // lines and a real overflowing session would bury every other diagnostics line
        // under hundreds of copies of the same sentence.
        let start = Date().addingTimeInterval(-1)
        let reporter = DiagnosticsReporter(launchId: "overflow-probe", appVersion: "1.0",
                                           build: "1", osVersion: "macOS 26.2")
        // No sink, so everything buffers; well past the cap, up each key's ladder.
        for key in 0..<20 {
            for _ in 0..<11 {
                reporter.record(DiagnosticEvent(
                    kind: .handledError, site: .chatTurn,
                    shape: DiagnosticErrorShape(type: "Overflow", domain: nil, code: key,
                                                 codingPath: nil)))
            }
        }
        XCTAssertEqual(reporter.bufferedCount, DiagnosticsReporter.maxBuffered)

        var lines: [OSLogEntryLog] = []
        for _ in 0..<40 {
            lines = try readBack(since: start).filter { $0.composedMessage.contains("buffer full") }
            if !lines.isEmpty { break }
            usleep(50_000)
        }
        XCTAssertEqual(lines.count, 1, "the overflow is one fact and gets one line")
        // And it must say the rest are silent, or a reader counting lines to estimate
        // how much was lost would count wrong.
        XCTAssertTrue(lines.first?.composedMessage.contains("Further drops are silent") ?? false)
    }

    // MARK: - Message content

    func testTheSelfTestPassLineNamesThePathSoItSaysWhatPassed() {
        let message = DiagnosticsLog.selfTestPassed(uid: "abc123")
        XCTAssertTrue(message.contains("PASS"))
        // "PASS" alone does not tell a reader which destination was proven.
        XCTAssertTrue(message.contains("companies/abc123/diagnostics"))
    }

    func testTheSelfTestFailLineSendsTheReaderToTheRulesRatherThanNowhere() {
        let message = DiagnosticsLog.selfTestFailedNoDocument(nonce: "n-1")
        XCTAssertTrue(message.contains("FAIL"))
        XCTAssertTrue(message.contains("n-1"))
        // A bare FAIL sends the reader to the wrong place; a rejected write is a rules
        // problem and the line has to say so.
        XCTAssertTrue(message.contains("firestore.rules"))
    }

    func testARejectedWriteLineSaysThatNothingElseWillEverRecordIt() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."])
        let message = DiagnosticsLog.writeRejected(error)
        // Domain and code, because `permissionDenied` is what "the rule is missing"
        // looks like and the sentence alone does not say it.
        XCTAssertTrue(message.contains("FIRFirestoreErrorDomain/7"))
        XCTAssertTrue(message.contains("REJECTED"))
        // The reader has to know this log line is the whole record — diagnostics cannot
        // report its own delivery failure.
        XCTAssertTrue(message.contains("only record"))
    }

    func testThePreviousSessionLineSpellsOutTheCauseRatherThanJustSayingUnclean() {
        // The entire point of classifying the cause is that a reader must not read
        // `concurrentInstance` or `systemRestart` as a crash. A line that said only
        // "did not end cleanly" would undo that.
        let record = SessionRecord(launchId: "L1", pid: 4242, bootTime: 5_000,
                                   startedAt: Date(), context: [:], exceptionName: nil,
                                   endedCleanly: false)
        let concurrent = DiagnosticsLog.previousSession(
            .unclean(cause: .concurrentInstance, record: record))
        XCTAssertTrue(concurrent.contains("concurrentInstance"))
        XCTAssertTrue(concurrent.contains("4242"))

        var crashed = record
        crashed.exceptionName = "NSInvalidArgumentException"
        let crash = DiagnosticsLog.previousSession(
            .unclean(cause: .uncaughtException, record: crashed))
        XCTAssertTrue(crash.contains("NSInvalidArgumentException"))

        // And the two quiet outcomes still say something, so "diagnostics ran and found
        // nothing" is distinguishable from "diagnostics did not run".
        XCTAssertTrue(DiagnosticsLog.previousSession(.clean).contains("cleanly"))
        XCTAssertTrue(DiagnosticsLog.previousSession(.firstLaunch).contains("first launch"))
    }

    func testTheSubsystemIsItsOwnSoOnePredicateReadsTheWholeModule() {
        XCTAssertEqual(DiagnosticsLog.subsystem, "app.murror.codepet.diagnostics")
        // Not the bundle id plus a category: the read command must not need a category
        // filter the reader has to get right while chasing a bug.
        XCTAssertNotEqual(DiagnosticsLog.subsystem, "app.murror.codepet")
        // And distinct from the voice stack, which is deliberately local and verbose.
        XCTAssertNotEqual(DiagnosticsLog.subsystem, VoiceLog.subsystem)
    }
}
