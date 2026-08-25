// codepet/Diagnostics/ChatTurnDiagnostic.swift
import Foundation

/// Decides whether a chat turn is worth reporting, and as what.
///
/// A value type rather than inline code in `CompanyStore.sendMessage`, for the same
/// reason `ChatTailAction` is one: the decision is the interesting part and the send
/// path is 250 lines long. This one is testable with no store, no network and no
/// Firebase.
///
/// The rule: report ONLY a turn the founder got no answer to. `sendMessage` has a
/// non-streaming fallback, so a stream that throws and is then recovered produced a real
/// reply — worth a log line, not a document, and reporting it would mean a document for
/// every transient network blip in a beta. The turn that matters is the one that ends
/// with "I cannot reach your departments right now", because that is a founder typing a
/// question and getting nothing.
nonisolated enum ChatTurnDiagnostic {
    /// `streamError` is what the SSE stream threw, if it threw. `fallbackReplyWasNil`
    /// is true when the non-streaming retry also came back with nothing.
    static func event(streamError: Error?, fallbackReplyWasNil: Bool) -> DiagnosticEvent? {
        guard fallbackReplyWasNil else { return nil }
        return DiagnosticEvent(
            kind: .handledError,
            site: .chatTurn,
            shape: DiagnosticErrorShape.of(streamError, code: httpStatus(of: streamError)),
            context: ["cause": cause(of: streamError)]
        )
    }

    /// A token naming WHICH failure, because the generic classifier can only see
    /// `CompanyChatStreamError` — the case lives in an associated value it cannot reach.
    /// Distinguishing these is the difference between "the founder is offline" (not our
    /// bug), "the function is 500ing" (ours, urgent) and "nobody is signed in" (an auth
    /// bug we would otherwise never hear about).
    static func cause(of error: Error?) -> String {
        switch error {
        case nil:
            // No throw, and the fallback still produced nothing: the request completed
            // and the answer was empty. A distinct and worse failure than a network one.
            return "emptyReply"
        case let streamError as CompanyChatStreamError:
            switch streamError {
            case .notSignedIn: return "notSignedIn"
            case .http: return "http"
            case .malformedResponse: return "malformedResponse"
            // Distinct in diagnostics too: a beta week full of these means the local
            // runner is not reaching founders, which is a packaging problem, not a
            // network one — and the two would be indistinguishable folded together.
            case .localUnavailable: return "localUnavailable"
            }
        case let urlError as URLError:
            return urlError.code == .notConnectedToInternet ? "offline" : "network"
        default:
            return "other"
        }
    }

    /// The HTTP status, when the error carries one. Overrides the `NSError` bridge's
    /// code, which for a Swift error enum is just the case's ordinal.
    static func httpStatus(of error: Error?) -> Int? {
        guard case .http(let status, _) = error as? CompanyChatStreamError else { return nil }
        return status
    }
}
