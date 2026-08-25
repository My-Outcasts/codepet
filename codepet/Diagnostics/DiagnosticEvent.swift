// codepet/Diagnostics/DiagnosticEvent.swift
import Foundation

/// What kind of thing is being reported. Deliberately a small, closed vocabulary:
/// an admin reading `companies/*/diagnostics` sorts by this before anything else.
nonisolated enum DiagnosticKind: String, Equatable, CaseIterable {
    /// A failure the app caught and recovered from. The founder may or may not have
    /// seen it; either way the app kept running.
    case handledError

    /// The PREVIOUS launch left its session flag set — it did not reach
    /// `NSApplication.willTerminateNotification`. Read `cause` before calling this a
    /// crash; see `UncleanCause`.
    case uncleanExit

    /// An Obj-C exception reached the top of the stack via
    /// `NSSetUncaughtExceptionHandler`. This one IS a crash.
    case uncaughtException

    /// Written by `-CODEPET_DIAG_SELFTEST YES` only, to prove a write lands.
    case selfTest
}

/// The call site a diagnostic came from. A closed enum rather than `#function`, because
/// `#function` would let a refactor silently rename a series that someone is watching,
/// and because a free-form string is a place for a path or a prompt to leak in.
nonisolated enum DiagnosticSite: String, Equatable, CaseIterable {
    case narrativeEnrich = "NarrativeEnricher.recordFailure"
    case chatThreadLoad = "SessionChatStore.loadFromDisk"
    case chatTurn = "CompanyStore.sendMessage"
    case roomEventDecode = "VirtualCompanyEvent.decode"
    case sessionLifecycle = "DiagnosticsBootstrap.start"
}

/// The SHAPE of an error: what type it was and which numbered failure, never what it
/// said. `String(describing: someError)` is banned from this struct on purpose —
/// `DecodingError.dataCorrupted`'s `debugDescription` quotes the offending bytes, and
/// `URLError.userInfo` carries `NSURLErrorFailingURLStringErrorKey`, i.e. a URL with
/// whatever query string was on it. Both are content.
nonisolated struct DiagnosticErrorShape: Equatable {
    /// A type name, and for the error types we own, the case: `"URLError"`,
    /// `"DecodingError.dataCorrupted"`, `"CompanyChatStreamError.http"`.
    let type: String
    /// `NSError.domain` when there is one. A constant like `NSURLErrorDomain`.
    let domain: String?
    /// `NSError.code`, or an HTTP status for the errors that carry one.
    let code: Int?
    /// For a `DecodingError` only: the coding path as KEY NAMES, dot-joined
    /// (`"threads.messages.role"`). That is the schema of our own file format, not the
    /// founder's data — and it is the single most useful field for a decode bug,
    /// because it names the field that broke. Array indices are dropped: an index is
    /// closer to "how much data was there" than to schema, and is not actionable.
    let codingPath: String?

    static let none = DiagnosticErrorShape(type: "none", domain: nil, code: nil, codingPath: nil)

    /// Classifies an error into shape-only fields.
    ///
    /// `code` overrides whatever the error carries, for the error types whose useful
    /// number is in an associated value the classifier cannot reach generically.
    static func of(_ error: Error?, code overrideCode: Int? = nil) -> DiagnosticErrorShape {
        guard let error else {
            return overrideCode == nil
                ? .none
                : DiagnosticErrorShape(type: "none", domain: nil, code: overrideCode,
                                       codingPath: nil)
        }

        if let decoding = error as? DecodingError {
            let (caseName, context) = Self.split(decoding)
            let keys = context?.codingPath.compactMap { $0.intValue == nil ? $0.stringValue : nil }
            let path = (keys?.isEmpty ?? true) ? nil : keys?.joined(separator: ".")
            return DiagnosticErrorShape(
                type: "DecodingError.\(caseName)",
                domain: nil,
                code: overrideCode,
                codingPath: path
            )
        }

        let ns = error as NSError
        return DiagnosticErrorShape(
            type: String(describing: Swift.type(of: error)),
            domain: ns.domain,
            code: overrideCode ?? ns.code,
            codingPath: nil
        )
    }

    private static func split(_ error: DecodingError) -> (String, DecodingError.Context?) {
        switch error {
        case .typeMismatch(_, let c): return ("typeMismatch", c)
        case .valueNotFound(_, let c): return ("valueNotFound", c)
        case .keyNotFound(_, let c): return ("keyNotFound", c)
        case .dataCorrupted(let c): return ("dataCorrupted", c)
        @unknown default: return ("unknown", nil)
        }
    }
}

/// One thing worth telling us about, as pure data. Built at the call site, turned into
/// a Firestore document by `payload(...)`, written by `DiagnosticsReporter`.
nonisolated struct DiagnosticEvent: Equatable {
    let kind: DiagnosticKind
    let site: DiagnosticSite
    let shape: DiagnosticErrorShape
    /// How many times this (kind, site, shape) has happened this launch, including
    /// this one. `DiagnosticsBudget` only lets a fraction of occurrences through, so
    /// this is the number that matters — not the document count.
    let count: Int
    /// Shape-only extras: an enum's `rawValue`, a bucket, a boolean as a string.
    /// Every value is passed through `DiagnosticRedaction.sanitize` before it lands in
    /// the payload, so a caller cannot leak a path through here even by accident.
    let context: [String: String]

    init(kind: DiagnosticKind, site: DiagnosticSite, shape: DiagnosticErrorShape = .none,
         count: Int = 1, context: [String: String] = [:]) {
        self.kind = kind
        self.site = site
        self.shape = shape
        self.count = count
        self.context = context
    }

    /// The coalescing key. Two occurrences share a key when they are the same failure:
    /// same kind, same site, same error shape. `count` and `context` are deliberately
    /// NOT part of it — a counter in the key would defeat the budget, and context that
    /// varies per occurrence would too.
    var budgetKey: String {
        [kind.rawValue, site.rawValue, shape.type, shape.domain ?? "",
         shape.code.map(String.init) ?? "", shape.codingPath ?? ""].joined(separator: "|")
    }

    /// The Firestore document body, minus the server timestamp (added by the sink).
    ///
    /// There is no `userId` field: the document's own path is
    /// `companies/{uid}/diagnostics/{id}`, so the account is already identified by
    /// where the document lives. Adding it again would be a second thing to keep
    /// correct for no new information.
    func payload(launchId: String, appVersion: String, build: String,
                 osVersion: String, clientAt: Date) -> [String: Any] {
        var data: [String: Any] = [
            "kind": kind.rawValue,
            "site": site.rawValue,
            "errorType": shape.type,
            "count": count,
            // Correlates the events of ONE app launch without identifying anything: a
            // UUID minted at launch and never persisted beyond the session record.
            "launchId": launchId,
            "appVersion": appVersion,
            "build": build,
            "os": osVersion,
            "platform": "macos",
            "schemaVersion": 1,
            // A client clock, so events stay orderable even if the server timestamp is
            // missing (a buffered event written minutes after it happened would
            // otherwise sort by its flush, not its occurrence).
            "clientAt": ISO8601DateFormatter().string(from: clientAt)
        ]
        if let domain = shape.domain { data["errorDomain"] = DiagnosticRedaction.sanitize(domain) }
        if let code = shape.code { data["errorCode"] = code }
        if let path = shape.codingPath { data["codingPath"] = DiagnosticRedaction.sanitize(path) }
        for (key, value) in context {
            // Namespaced so a context key can never shadow a top-level field — a
            // caller passing `context: ["count": "..."]` must not be able to rewrite
            // the budget's count.
            data["ctx_\(DiagnosticRedaction.sanitize(key))"] = DiagnosticRedaction.sanitize(value)
        }
        return data
    }
}

/// The last gate before a string becomes a Firestore field.
///
/// This exists because the leak this app has already had is a path: `ChatAttachment.id`
/// is an absolute path under the founder's home directory, and any `String(describing:)`
/// of an error that touched a file carries one. Rather than trusting every call site to
/// remember, every string in a diagnostics payload goes through here.
nonisolated enum DiagnosticRedaction {
    static let redacted = "<redacted>"
    static let maxLength = 120

    /// Returns the string, or `<redacted>` if it looks like it could carry content.
    ///
    /// Refuses anything with a path separator, a `~`, an `@`, or a whitespace run. That
    /// is aggressive — it would reject a legitimate sentence — and that is the point:
    /// nothing in this payload is supposed to be a sentence. Every field is an
    /// identifier, an enum `rawValue`, or a bucket label.
    static func sanitize(_ value: String) -> String {
        if value.isEmpty { return redacted }
        if value.count > maxLength { return redacted }
        if value.contains("/") || value.contains("\\") { return redacted }
        if value.contains("~") || value.contains("@") { return redacted }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return redacted }
        return value
    }
}
