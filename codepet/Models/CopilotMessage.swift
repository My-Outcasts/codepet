// codepet/Models/CopilotMessage.swift
import Foundation

/// Who authored a Copilot chat message.
enum CopilotRole { case me, companion }

/// One Copilot chat message (session-only; not persisted this phase). Named to
/// avoid the reflection `ChatMessage`.
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    /// When this turn landed. Session-only, like the transcript itself (threads are not
    /// persisted), so it measures THIS session honestly and claims nothing about earlier ones.
    var createdAt: Date = Date()
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
    /// When a specialist companion (not the host) leads this turn, its
    /// `PetCharacter` id — carried so the view can render "Name · Dept" instead
    /// of the host's attribution. Nil for an ordinary host reply.
    var companionId: String?
    /// The department name paired with `companionId` for the "Name · Dept"
    /// header. Nil whenever `companionId` is nil.
    var deptName: String?
    /// The live "how the agent is working" step checklist for a `producing`
    /// message — revealed progressively as the run proceeds. Nil/empty for an
    /// ordinary producing placeholder (renders the plain orb instead).
    var execSteps: [ExecStep]?
    /// A Virtual Company run rendered inside this message. Follows the existing
    /// fat-struct/if-chain pattern rather than an enum refactor, per
    /// docs/superpowers/specs/2026-07-31-coding-agent-in-copilot-design.md §2.
    var vcRun: VirtualCompanyRunState?

    /// `createdAt` is injectable and defaults to now.
    ///
    /// It was declared as a stored `var` but left OUT of this initializer, so no caller could
    /// set it and every message stamped itself at construction. That made the timestamp
    /// untestable — and since the synthesized `Equatable` compares it, it also made
    /// `CopilotMessage` equality depend on the clock, which quietly broke
    /// `CopilotMessageDraftTests` the day `createdAt` landed (`f0f9253`). Every existing call
    /// site keeps its behaviour: omitting the argument still means now.
    init(id: String = UUID().uuidString, role: CopilotRole, createdAt: Date = Date(),
         text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false,
         firstRunAction: FirstRunAction? = nil, actionConsumed: Bool = false,
         interview: InterviewGap? = nil, interviewAnswered: Bool = false,
         navChip: NavAction? = nil, setupSuggestion: SetupAction? = nil,
         noted: [RememberedFact]? = nil, producing: Bool = false,
         companionId: String? = nil, deptName: String? = nil,
         execSteps: [ExecStep]? = nil, vcRun: VirtualCompanyRunState? = nil) {
        self.id = id
        self.role = role
        self.createdAt = createdAt
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
        self.execSteps = execSteps
        self.vcRun = vcRun
    }
}
