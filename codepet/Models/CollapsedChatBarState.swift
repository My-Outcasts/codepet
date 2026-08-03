// codepet/Models/CollapsedChatBarState.swift
import Foundation

/// Pure state for the collapsed copilot bar — the bottom strip that replaces the
/// old full-height reopen rail. Kept out of the view (like `ShellLayout` and
/// `TopbarCounts`) so the send gate and the unread rule are unit-testable.
enum CollapsedChatBarState {

    /// Sendable only with real text and no turn already in flight. Mirrors
    /// `CopilotChatView.canSend` so the bar and the dock composer can't disagree
    /// about whether a message may leave.
    static func canSend(draft: String, busy: Bool) -> Bool {
        !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What's waiting on the founder. Deliberately the SAME count the Tasks nav
    /// badge shows (`TopbarCounts.tasks` — not-done work that is either hers or a
    /// draft awaiting approval), so two surfaces can never show different numbers
    /// for the same state.
    static func needsYouCount(tasks: [RoadmapTask]) -> Int {
        TopbarCounts.tasks(tasks)
    }

    /// A reply or run landed while the dock was closed. `seen` is the message count
    /// captured while the dock was last open, so reopening always clears the dot.
    static func showsUnreadDot(messageCount: Int, seen: Int) -> Bool {
        messageCount > seen
    }
}
