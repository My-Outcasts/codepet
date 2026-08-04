// codepet/Models/ChatTailAction.swift
import Foundation

/// What a chat turn owes its placeholder message once the companion stream is over.
///
/// A value type, in its own file, deliberately: three stream outcomes (threw, ended
/// with no `done`, ended clean) cross two text outcomes (empty, non-empty) and the
/// wrong answer either fires a second `chatSender` — running the same task twice —
/// or leaves the founder staring at an empty bubble.
///
/// The Virtual Company fan-out is deliberately NOT an input here. It used to be: the
/// room rewrote byte's own message, so every write in the tail had to re-ask "did the
/// room take this turn". The room now owns a separate appended message, so byte's
/// tail is exactly what it was before the feature existed.
enum ChatTailAction: Equatable {
    /// companyChat never delivered a well-formed reply (it threw, or it answered
    /// with no `done` frame — the shape a pre-deploy plain-JSON response collapses
    /// to). Call the non-streaming sender and fill the placeholder from it.
    case fallback
    /// A `done` arrived but byte sent zero chat text — a run-task-only reply. Write
    /// the lead-in so the bubble is not left blank.
    case leadIn
    /// Leave the placeholder exactly as it stands.
    case none

    static func decide(streamThrew: Bool,
                       receivedDone: Bool,
                       streamedText: String) -> ChatTailAction {
        if streamThrew || !receivedDone { return .fallback }
        // Gated on "no `done`", NOT on empty text: byte can legitimately reply with
        // only a run-task decision, and falling back there would fire a second
        // chatSender call and run the same task twice.
        if streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .leadIn }
        return .none
    }
}
