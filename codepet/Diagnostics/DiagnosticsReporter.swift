// codepet/Diagnostics/DiagnosticsReporter.swift
import Foundation

/// Where a diagnostic goes. One method, and its return value is the whole contract.
nonisolated protocol DiagnosticsSink: AnyObject {
    /// Returns false when the destination is not reachable YET — no `FirebaseApp`, or
    /// nobody signed in. False is not an error; the reporter buffers and retries on the
    /// next `flush()`. A sink that returns true has taken responsibility for delivery.
    func send(_ payload: [String: Any]) -> Bool
}

/// Records handled failures that the app currently swallows into the console.
///
/// Three properties, each of them deliberate:
///
/// **Not an `ObservableObject`, not `@MainActor`.** It publishes nothing — no view reads
/// diagnostics. It is called from `Task.detached` (`VirtualCompanyClient`'s SSE loop
/// calls `VirtualCompanyEvent.decode` off the main actor) and from an uncaught-exception
/// handler on an arbitrary thread, so main-actor isolation would mean an `await` at
/// every call site, i.e. reordering a report past the failure that caused it. And a
/// `@MainActor ObservableObject` deallocating takes the XCTest host down on Xcode 26.2.
/// State is guarded by a lock instead.
///
/// **Inert until a sink is installed.** `shared` starts with `sink == nil`, and
/// `DiagnosticsBootstrap.start()` — which does not run under XCTest — is the only thing
/// that installs the Firestore sink. So the suite exercises real call sites (every
/// `CompanyStore.sendMessage` test does) with no Firebase, no network, and no need for
/// an `isRunningTests` check inside `record`.
///
/// **Buffers rather than drops.** The two most valuable reports — the previous session's
/// unclean exit, and a chat-thread file that failed to load — both happen before anyone
/// is signed in, which is before there is a Firestore path to write to. Dropping them
/// would mean the system reports nothing about exactly the failures it was built for.
nonisolated final class DiagnosticsReporter {
    static let shared = DiagnosticsReporter()

    /// Ceiling on buffered events. Reached only when nobody ever signs in, in which
    /// case there is no destination anyway.
    static let maxBuffered = 50

    private let lock = NSLock()
    private var budget = DiagnosticsBudget()
    private var buffer: [[String: Any]] = []
    private var installedSink: DiagnosticsSink?
    /// Guards the buffer-overflow log line to one per launch. Read and written only
    /// under `lock`, from `appendToBufferLocked`.
    private var didLogBufferFull = false

    private let launchId: String
    private let appVersion: String
    private let build: String
    private let osVersion: String
    private let now: () -> Date

    init(launchId: String = UUID().uuidString,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
         build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
         osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
         now: @escaping () -> Date = Date.init) {
        self.launchId = launchId
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.now = now
    }

    var currentLaunchId: String { launchId }

    func install(sink: DiagnosticsSink) {
        lock.lock()
        installedSink = sink
        lock.unlock()
        flush()
    }

    /// Test seam: how many events are waiting for a reachable destination.
    var bufferedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// The one entry point every call site uses.
    ///
    /// `nonisolated` and synchronous on purpose: a failure must be recorded at the
    /// moment and on the thread it happened, not on whenever the main actor next gets
    /// a turn.
    func record(kind: DiagnosticKind, site: DiagnosticSite, error: Error? = nil,
                code: Int? = nil, context: [String: String] = [:]) {
        let shape = DiagnosticErrorShape.of(error, code: code)
        record(DiagnosticEvent(kind: kind, site: site, shape: shape, context: context))
    }

    /// Records a pre-built event. `count` on the passed event is IGNORED — the budget
    /// owns the count, because the budget is the only thing that knows how many
    /// occurrences it has already seen.
    func record(_ event: DiagnosticEvent) {
        lock.lock()
        guard let count = budget.admit(event.budgetKey) else {
            lock.unlock()
            return
        }
        let counted = DiagnosticEvent(kind: event.kind, site: event.site, shape: event.shape,
                                      count: count, context: event.context)
        let payload = counted.payload(launchId: launchId, appVersion: appVersion,
                                      build: build, osVersion: osVersion, clientAt: now())
        let sink = installedSink
        if sink == nil {
            appendToBufferLocked(payload)
            lock.unlock()
            return
        }
        lock.unlock()

        if sink?.send(payload) != true {
            lock.lock()
            appendToBufferLocked(payload)
            lock.unlock()
        }
    }

    /// Retries everything buffered. Called when identity becomes available — see
    /// `CompanyStore.hydrate`, which is the exact moment a uid exists and a
    /// `companies/{uid}/…` write can succeed.
    func flush() {
        lock.lock()
        guard let sink = installedSink, !buffer.isEmpty else {
            lock.unlock()
            return
        }
        let queued = buffer
        buffer = []
        lock.unlock()

        var stillWaiting: [[String: Any]] = []
        for payload in queued where !sink.send(payload) {
            stillWaiting.append(payload)
        }
        DiagnosticsLog.note(DiagnosticsLog.reporter, """
            flush: \(queued.count - stillWaiting.count) of \(queued.count) handed to the \
            sink, \(stillWaiting.count) still waiting
            """)
        guard !stillWaiting.isEmpty else { return }
        lock.lock()
        // Put the unsent ones BACK IN FRONT of anything recorded while we were sending,
        // so the buffer stays in occurrence order and the cap drops the newest rather
        // than the oldest. The oldest buffered event is the launch-time one — the
        // unclean-exit report — and that is the one worth keeping.
        buffer = stillWaiting + buffer
        if buffer.count > Self.maxBuffered { buffer = Array(buffer.prefix(Self.maxBuffered)) }
        lock.unlock()
    }

    private func appendToBufferLocked(_ payload: [String: Any]) {
        guard buffer.count < Self.maxBuffered else {
            // A real, silent loss until this line existed: the cap is reached only when
            // nobody ever signs in, which is also when there is no destination to notice
            // the gap. The unified log is the only place it can be recorded, for the same
            // reason as a rejected write.
            //
            // ONCE per launch, not once per dropped event. The first version logged
            // every drop, and reading the actual `log show` output showed what that
            // means: one test produced twenty identical error lines, and a real session
            // that overflowed would bury every other diagnostics line under hundreds of
            // copies of the same sentence. The overflow is one fact, so it gets one line
            // — and the line says the rest will be silent, because a reader counting
            // lines to estimate the loss would otherwise be counting wrong.
            if !didLogBufferFull {
                didLogBufferFull = true
                DiagnosticsLog.failure(DiagnosticsLog.reporter, """
                    buffer full at \(Self.maxBuffered) — DROPPING this and every later \
                    event until someone signs in; first dropped was \
                    \(payload["kind"] as? String ?? "unknown")/\
                    \(payload["site"] as? String ?? "unknown"). Further drops are silent.
                    """)
            }
            return
        }
        buffer.append(payload)
    }
}
