// codepet/Models/CollapsedCopilotState.swift
import Foundation

/// Pure state for the collapsed copilot button. Kept out of the view (like
/// `ShellLayout` and `TopbarCounts`) so the signal rules are unit-testable.
enum CollapsedCopilotState {

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
