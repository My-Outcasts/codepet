// codepet/Models/MessageActionRules.swift
import Foundation

/// When a per-message action may be offered.
///
/// Extracted from the view for one reason: `CompanyStore.retryReply` walks back to the
/// preceding `.me` message and calls `removeSubrange(askIndex...)`, so retrying an OLDER
/// reply deletes the founder's question and every turn that followed it. That was harmless
/// while the action row was unreachable — the hover target was an invisible 22x20 strip —
/// and stops being harmless the moment the row is pinned to the last reply.
///
/// Confining retry to the last reply makes the deletion equal to what the button promises:
/// your last question and its answer, re-asked. It is a rule rather than an inline
/// `.disabled` condition so a test goes red when someone deletes it.
enum MessageActionRules {
    static func canRetry(isLast: Bool, isTyping: Bool, isStreaming: Bool) -> Bool {
        isLast && !isTyping && !isStreaming
    }
}
