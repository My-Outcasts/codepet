// codepet/Diagnostics/SessionLifecycle.swift
import Foundation
import Darwin

/// What we can say about a session that did not end cleanly.
///
/// This enum is the honest part of this feature. A set-on-launch / clear-on-quit flag
/// cannot tell a crash from a force-quit from a `SIGKILL` during logout, and a beta
/// report that says "3 crashes" when it means "3 sessions that did not reach
/// `applicationWillTerminate`" is worse than no report — it converts an unknown into a
/// wrong number that someone will act on. So the cause is always recorded alongside the
/// fact, and only `.uncaughtException` is a crash we can prove.
nonisolated enum UncleanCause: String, Equatable, CaseIterable {
    /// `NSSetUncaughtExceptionHandler` fired and got its record written before the
    /// process died. This IS a crash, and we know its exception name.
    case uncaughtException

    /// The machine's `kern.boottime` changed between that session and this one: the
    /// host rebooted, slept-and-lost-power, or was force-restarted. The session did
    /// die, but almost certainly not because of us. Low signal; recorded so it can be
    /// filtered out rather than inflating a crash count.
    case systemRestart

    /// The flag's owning process is STILL RUNNING. This is not a death at all — it is a
    /// second instance of the app launching alongside the first (`open -n`, or an Xcode
    /// run next to a released copy, both routine in this project). Reported so the
    /// pattern is visible, but it must never be counted as a crash.
    case concurrentInstance

    /// The flag was set, the machine did not reboot, the owning process is gone, and no
    /// exception was recorded. A native crash (signal, mach exception), a force-quit, an
    /// OS memory kill, or a hang the founder ended with the Dock. We cannot tell these
    /// apart without a crash SDK — see the report.
    case unknown
}

/// The record one launch leaves behind, so the NEXT launch can say what happened.
nonisolated struct SessionRecord: Codable, Equatable {
    var launchId: String
    var pid: Int32
    /// `kern.boottime` in seconds. Distinguishes a reboot from a process death.
    var bootTime: Int64
    var startedAt: Date
    /// Shape-only breadcrumbs the last session had reached — a tab name, a chat mode.
    /// Never message text; see `DiagnosticRedaction`.
    var context: [String: String]
    /// Set by the uncaught-exception handler, synchronously, as the process dies.
    var exceptionName: String?

    /// True once this session reached `NSApplication.willTerminateNotification`.
    ///
    /// A marker rather than deleting the record, which is what this originally did.
    /// Deleting made `.clean` UNREACHABLE — the next launch saw no record and reported
    /// `.firstLaunch`, so "quit normally yesterday" and "never run before" were the
    /// same answer. Both produce no document, so nothing was mis-reported, but the
    /// outcome enum was lying and any future use of it would have inherited the lie.
    /// Optional so a record written before this field existed still decodes; nil reads
    /// as "did not end cleanly", which is the safe direction.
    var endedCleanly: Bool?
}

nonisolated enum PreviousSessionOutcome: Equatable {
    /// No record at all — a first launch, or a fresh container.
    case firstLaunch
    /// The last session reached `willTerminate` and cleared its flag.
    case clean
    case unclean(cause: UncleanCause, record: SessionRecord)
}

/// Set a flag on launch, clear it on graceful termination; if it is still set at the
/// next launch the previous session died. That is the whole idea, and it needs no signal
/// handlers and no mach exception ports.
///
/// Everything injectable, and deliberately NOT an `ObservableObject` and NOT
/// `@MainActor`: it publishes nothing to any view, it is written to from an
/// exception handler on an arbitrary thread, and a `@MainActor ObservableObject`
/// deallocating takes the XCTest host down on Xcode 26.2. `VirtualCompanyClient`
/// documents the same reasoning.
nonisolated final class SessionLifecycleTracker {
    static let defaultsKey = "cp_diag_session_v1"

    /// Installed by `DiagnosticsBootstrap`. A static, because the uncaught-exception
    /// handler is a C function pointer and can capture nothing.
    nonisolated(unsafe) static var shared: SessionLifecycleTracker?

    private let defaults: UserDefaults
    private let key: String
    private let currentPid: Int32
    private let bootTime: Int64
    private let isProcessAlive: (Int32) -> Bool
    private let now: () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard,
         key: String = SessionLifecycleTracker.defaultsKey,
         currentPid: Int32 = ProcessInfo.processInfo.processIdentifier,
         bootTime: Int64 = SessionLifecycleTracker.systemBootTime(),
         isProcessAlive: @escaping (Int32) -> Bool = SessionLifecycleTracker.processIsAlive,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.currentPid = currentPid
        self.bootTime = bootTime
        self.isProcessAlive = isProcessAlive
        self.now = now
    }

    /// Reads whatever the last session left, classifies it, and claims the flag for
    /// this session. Call once, as early in launch as possible: a crash before this
    /// runs is a crash we cannot see.
    func claimLaunch(launchId: String) -> PreviousSessionOutcome {
        lock.lock()
        defer { lock.unlock() }

        let previous = readRecord()
        let outcome = Self.classify(previous, currentBootTime: bootTime,
                                    currentPid: currentPid, isProcessAlive: isProcessAlive)

        // Claim unconditionally, INCLUDING in the `.concurrentInstance` case. The two
        // instances then fight over one flag and the second to quit cleanly clears it,
        // so a genuine crash of the first instance is missed. That is the right trade:
        // the alternative — not claiming — means this instance's own crash is invisible,
        // and a missed report is better than a fabricated one.
        write(SessionRecord(launchId: launchId, pid: currentPid, bootTime: bootTime,
                            startedAt: now(), context: [:], exceptionName: nil,
                            endedCleanly: false))
        return outcome
    }

    /// The graceful path. Marks the record ended, so the next launch sees `.clean`.
    func recordCleanExit() {
        lock.lock()
        defer { lock.unlock() }
        // Only the record's OWNER may mark it ended. Two instances share one flag, and
        // without this the first one to quit cleanly would sign off on the other's
        // session — so a second instance that then crashed would be reported as a clean
        // quit. The reverse order still has a hole (the owner quits cleanly, the
        // non-owner crashes, and the crash is missed) and one flag cannot close it; this
        // guard closes the half that can be closed.
        guard var record = readRecord(), record.pid == currentPid else { return }
        record.endedCleanly = true
        write(record)
        // `cfprefsd` holds the value out of process, so it survives our exit without
        // this — but `synchronize()` costs nothing on a quit path and removes the
        // question entirely. Getting this wrong shows up as phantom crash reports.
        defaults.synchronize()
    }

    /// Merges shape-only breadcrumbs into the live record, so an unclean exit can be
    /// reported with what the session had last reached.
    func updateContext(_ additions: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = readRecord(), record.pid == currentPid else { return }
        for (k, v) in additions {
            record.context[DiagnosticRedaction.sanitize(k)] = DiagnosticRedaction.sanitize(v)
        }
        write(record)
    }

    /// Called from the uncaught-exception handler, on whatever thread threw, with the
    /// process about to die.
    ///
    /// Writes ONLY `NSException.name` — never `reason`, which is a free-form message and
    /// has no rule stopping it from quoting a path or a value. Firestore is unreachable
    /// from here (an async write cannot outlive the process), so the record is left in
    /// `UserDefaults` for the next launch to report. That is why an exception shows up
    /// one launch late, and it is not a bug.
    func recordUncaughtException(name: String) {
        lock.lock()
        defer { lock.unlock() }
        var record = readRecord() ?? SessionRecord(
            launchId: UUID().uuidString, pid: currentPid, bootTime: bootTime,
            startedAt: now(), context: [:], exceptionName: nil)
        record.exceptionName = DiagnosticRedaction.sanitize(name)
        write(record)
        defaults.synchronize()
    }

    // MARK: - Classification

    /// Pure, so the whole decision table is testable without a process to kill.
    ///
    /// Order is load-bearing. `systemRestart` is checked BEFORE `concurrentInstance`
    /// because pids are recycled from low numbers after a reboot: a stale pid from the
    /// previous boot is very likely alive again as something else, and that would
    /// misread a real crash as a harmless second instance — a false NEGATIVE, the
    /// expensive direction.
    static func classify(_ previous: SessionRecord?, currentBootTime: Int64,
                         currentPid: Int32,
                         isProcessAlive: (Int32) -> Bool) -> PreviousSessionOutcome {
        guard let previous else { return .firstLaunch }
        // A recorded exception outranks a clean-exit marker. The two can coexist —
        // `NSSetUncaughtExceptionHandler` runs, a chained handler lets AppKit unwind,
        // and `willTerminate` still posts — and "it threw NSRangeException" is strictly
        // more informative than "it shut down afterwards".
        if let name = previous.exceptionName, !name.isEmpty {
            return .unclean(cause: .uncaughtException, record: previous)
        }
        // `endedCleanly` nil (a record from before the field existed) reads as "did
        // not", which over-reports rather than under-reports. That is the right
        // direction for the one launch it can affect.
        if previous.endedCleanly == true { return .clean }
        if previous.bootTime != currentBootTime {
            return .unclean(cause: .systemRestart, record: previous)
        }
        if previous.pid != currentPid, isProcessAlive(previous.pid) {
            return .unclean(cause: .concurrentInstance, record: previous)
        }
        return .unclean(cause: .unknown, record: previous)
    }

    // MARK: - Storage

    private func readRecord() -> SessionRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    private func write(_ record: SessionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - System facts

    /// Seconds-since-epoch of the last boot, from `kern.boottime`.
    static func systemBootTime() -> Int64 {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Int64(tv.tv_sec)
    }

    /// `kill(pid, 0)` probes for existence without delivering anything. `EPERM` means
    /// the process exists but belongs to someone else, which still answers "alive".
    static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
