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
    /// A tapped-to-navigate suggestion from `.done`'s `nav` action; nil for ordinary text.
    /// Rendered as a chip — tapping routes through `CompanyStore.activateNav`.
    var navChip: NavAction?
    /// A tapped-to-enable suggestion from `.done`'s `setup` action; nil for ordinary text.
    /// Rendered as an enable card — tapping routes through `CompanyStore.activateSetup`.
    var setupSuggestion: SetupAction?
    /// Transient "Noted" fact(s) from `.done`'s `remember` action. Memory is already
    /// merged + persisted by the time this renders (auto, not approval-gated).
    var noted: [RememberedFact]?
    /// True for the transient "producing…" placeholder appended by
    /// `CompanyStore.handleRunTaskId` while a chat-initiated `run_task` is in
    /// flight — removed (never persisted) once the run resolves, win or lose.
    var producing: Bool
    /// The specialist companion speaking THIS message (a department handoff);
    /// nil = the host/global companion. Drives the orb tint + sender name so a
    /// department pet can appear per message. See `deptName`.
    var companionId: String?
    /// The department this message's specialist leads (e.g. "Marketing"), shown
    /// as a "Name · Dept" sender label. nil when spoken by the host.
    var deptName: String?

    init(id: String = UUID().uuidString, role: CopilotRole, text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false,
         firstRunAction: FirstRunAction? = nil, actionConsumed: Bool = false,
         interview: InterviewGap? = nil, interviewAnswered: Bool = false,
         navChip: NavAction? = nil, setupSuggestion: SetupAction? = nil,
         noted: [RememberedFact]? = nil, producing: Bool = false,
         companionId: String? = nil, deptName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.draft = draft
        self.draftApproved = draftApproved
        self.firstRunAction = firstRunAction
        self.actionConsumed = actionConsumed
        self.interview = interview
        self.interviewAnswered = interviewAnswered
        self.navChip = navChip
        self.setupSuggestion = setupSuggestion
        self.noted = noted
        self.producing = producing
        self.companionId = companionId
        self.deptName = deptName
    }
}
