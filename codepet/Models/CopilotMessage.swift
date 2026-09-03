// codepet/Models/CopilotMessage.swift
import Foundation

/// Who authored a Copilot chat message.
enum CopilotRole { case me, companion }

/// The founder's verdict on one reply. Written straight to Firestore; the copy held
/// here only keeps the chosen thumb filled while the transcript is on screen.
enum MessageVote { case up, down }

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
    /// What this deliverable was built on — the upstream departments' work that travelled with
    /// the run, exactly as the request carried it. Nil for a run with no dependencies, which
    /// is most of them, and for every message that is not a finished draft.
    ///
    /// Read off the `RunTaskRequest` that was actually sent rather than re-derived for the
    /// view. Deriving it twice is how a card ends up crediting work the model never received —
    /// the library can change between the run and the render, and the chained case is not in
    /// the library at all.
    var upstream: [UpstreamWork]?
    /// A run offered as a choice because its dependency has produced nothing — see `ChainOffer`.
    /// `actionConsumed` retires the buttons once the founder picks, like `runProposal`.
    var chainOffer: ChainOffer?
    /// Which way the founder went on `chainOffer`, so the retired row says so. Nil until they pick.
    var chainOfferChained: Bool?
    /// A Virtual Company run rendered inside this message. Follows the existing
    /// fat-struct/if-chain pattern rather than an enum refactor, per
    /// docs/superpowers/specs/2026-07-31-coding-agent-in-copilot-design.md §2.
    var vcRun: VirtualCompanyRunState?
    /// True once a Virtual Company room landed for THIS turn, superseding this reply.
    ///
    /// Both calls go out in parallel so ordinary chat keeps its latency, which means the fast
    /// answer is written before the router has decided anything. When a room then lands, the
    /// founder has read a confident several-hundred-word answer immediately followed by "Actually
    /// — this one needs the whole room", which reads as Codepet contradicting itself (founder,
    /// Aug 7). It is not wrong, it is EARLY — and the room's call is the better answer, because
    /// four departments arguing produced a cohort split the fast reply never considered.
    var supersededByRoom: Bool = false
    /// A run started from a surface and offered here before it happens — see `RunProposal`.
    /// `actionConsumed` hides the button once pressed, the same way it does for `firstRunAction`.
    var runProposal: RunProposal?
    /// A roadmap change offered for confirmation — see `RoadmapProposal`.
    var roadmapProposal: RoadmapProposal?
    /// Messages the companion wrote for the founder to send — see `MessageDraftDTO`.
    ///
    /// Unlike every other payload here there is nothing to confirm and nothing to consume: a
    /// draft is content, and the founder acts on it by copying it. It attaches to the reply
    /// rather than arriving as its own bubble, for the same reason `roadmapProposal` does —
    /// two avatars for one thought reads as Codepet talking to itself (founder, Aug 10).
    var drafts: [MessageDraftDTO] = []

    /// The founder's thumb on this reply, or nil until they give one.
    ///
    /// On the message rather than in `CopilotBubble`'s `@State` because SwiftUI drops view
    /// state as rows recycle during scrolling, which would make the filled thumb vanish
    /// mid-scroll. Session-only like the rest of the transcript — the vote itself is durable
    /// in Firestore, this is only what the row draws.
    var vote: MessageVote?

    /// The files the founder attached to THIS turn, when she attached any.
    ///
    /// Session-only, like the rest of the transcript — threads are not persisted, and
    /// this is base64 in memory, which is exactly what must not be written into a
    /// Firestore document. It exists so `CompanyStore.sendMessage` can rebuild
    /// `history[].attachments` on the next turn: the model's memory of an image is the
    /// replay, and the replay is built from the transcript.
    ///
    /// `ChatAttachment` rather than the wire `AttachmentDTO`: what the pill row and a
    /// future re-send would want is the whole attachment (`byteCount` for the pill,
    /// `id` for de-dupe), and the wire shape is derived at the wire.
    var attachments: [ChatAttachment] = []

    /// The founder's own typed ask this reply answers, when it was produced by one — nil for
    /// every store-initiated append (a run proposal, a finished draft, a fan-out row, an
    /// interview question, the first-run greeting, ...).
    ///
    /// NOT inferable from array position: `CompanyStore.retryReply` assumes the newest message
    /// is the answer to the founder's LAST question, walks back to the preceding `.me`, and
    /// deletes everything from there forward. Many companion messages land with no founder ask
    /// immediately before them — a Roadmap "Run" proposal, a finished run's draft, a fan-out
    /// summary — and each becomes the newest message in turn. Gating retry on `isLast` alone
    /// offered it there too: tapping it deleted whatever question and answer preceded it (often
    /// several turns back), not the proposal on screen. This field is the one faithful signal —
    /// set only on the reply `sendChat` produces for a typed ask, left nil everywhere else — so
    /// `MessageActionRules.canRetry` can refuse retry on a reply that isn't answering anything.
    var founderAsk: String?

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
         execSteps: [ExecStep]? = nil, upstream: [UpstreamWork]? = nil,
         chainOffer: ChainOffer? = nil, chainOfferChained: Bool? = nil,
         vcRun: VirtualCompanyRunState? = nil,
         runProposal: RunProposal? = nil, roadmapProposal: RoadmapProposal? = nil,
         drafts: [MessageDraftDTO] = [], vote: MessageVote? = nil,
         founderAsk: String? = nil, attachments: [ChatAttachment] = []) {
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
        self.upstream = upstream
        self.chainOffer = chainOffer
        self.chainOfferChained = chainOfferChained
        self.vcRun = vcRun
        self.runProposal = runProposal
        self.roadmapProposal = roadmapProposal
        self.drafts = drafts
        self.vote = vote
        self.founderAsk = founderAsk
        self.attachments = attachments
    }
}
