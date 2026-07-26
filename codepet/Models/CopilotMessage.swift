// codepet/Models/CopilotMessage.swift
import Foundation

/// Who authored a Copilot chat message.
enum CopilotRole { case me, companion }

/// One Copilot chat message (session-only; not persisted this phase). Named to
/// avoid the reflection `ChatMessage`.
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    /// `var` (not `let`): a streaming companion reply is filled in place, chunk
    /// by chunk, into this same message (found by `id`) rather than replaced.
    var text: String
    var draft: Deliverable?
    var draftApproved: Bool
    /// First-run "Do it with me" action (greeting message only); nil otherwise.
    var firstRunAction: FirstRunAction?
    /// True once the action has been tapped — hides the button.
    var actionConsumed: Bool
    /// First-run enrichment interview: the gap this message asks about; nil otherwise.
    var interview: InterviewGap?
    /// True once the founder has answered or skipped — collapses the card to a plain bubble.
    var interviewAnswered: Bool

    init(id: String = UUID().uuidString, role: CopilotRole, text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false,
         firstRunAction: FirstRunAction? = nil, actionConsumed: Bool = false,
         interview: InterviewGap? = nil, interviewAnswered: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.draft = draft
        self.draftApproved = draftApproved
        self.firstRunAction = firstRunAction
        self.actionConsumed = actionConsumed
        self.interview = interview
        self.interviewAnswered = interviewAnswered
    }
}
