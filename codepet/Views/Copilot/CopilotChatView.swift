// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI

/// The Copilot column: a company-grounded chat with the founder's companion —
/// the PR#39 redesign composed into `main`'s 380pt dock. Empty state renders the
/// landing hero (`ChatEmptyState`); a shared `ChatComposer` (Ask/Plan/Build mode)
/// drives both the empty hero and the active conversation; the coding-agent
/// wiring (anchored `CodeRunCardView` + the `codingRun` scroll bridges) and the
/// `ThreadListView` history switcher are preserved from `main`.
struct CopilotChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @FocusState private var inputFocused: Bool
    /// Toggles the "History" thread switcher over the message list. Session-only
    /// UI state — the History stub (see the header) now activates this.
    @State private var showHistory = false
    /// Bumped from the coordinator's publishers so a nested-object change reliably
    /// re-renders the run card live (see the onReceive bridges below).
    @State private var codingRunTick = 0
    /// Composer mode (Ask/Plan/Build) — pure client-side message shaping; `.build`
    /// is the streamlined replacement for the old full-width "Let's build" button.
    @State private var mode: ChatMode = .ask
    /// The department chip selected in the composer (nil = no focus). Threads into
    /// `sendChat(department:)` for the specialist handoff.
    @State private var selectedDept: Department?

    /// The active companion's accent hue — the composer's primary gradient stop
    /// (accent) and the empty hero orb tint. `accent2` pairs it with pink.
    private var companionColor: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }
    private var canSend: Bool {
        !companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !companyStore.isCompanionTyping && !companyStore.isStreaming && !companyStore.isFanningOut
    }
    /// True while a chat turn OR a parallel fan-out is in flight — gates the
    /// History toggle here and (via `ThreadListView`'s own copy of this) the
    /// "New chat"/switch/delete row controls, so the UI can't trigger a
    /// mid-stream thread repoint even though `CompanyStore` also guards it at
    /// the source. Also dims/disables the composer during a fan-out.
    private var isChatBusy: Bool {
        companyStore.isCompanionTyping || companyStore.isStreaming || companyStore.isFanningOut
    }

    var body: some View {
        // The chat box measures itself so the reading column can be derived from its width
        // (`ChatColumn`: a fixed inset, capped). Measured here, at the dock's
        // own bounds, and passed down explicitly: the transcript's column lives inside a
        // ScrollView and the composer's does not, so reading a container-relative width at
        // each site would be asking two different questions and getting two different
        // answers — and these two must line up exactly.
        GeometryReader { geo in
            let column = ChatColumn.textWidth(forBox: geo.size.width)
            VStack(spacing: 0) {
                header(column: column)
                if showHistory {
                    ThreadListView(showHistory: $showHistory)
                } else if companyStore.chatMessages.isEmpty && companyStore.activeAgentRuns.isEmpty {
                    ChatEmptyState(
                        state: ChatLandingState(company: companyStore.company, now: Date(), language: lang),
                        onOpenRoadmap: { companyStore.select(.roadmap) },
                        onStarter: { starter in
                            companyStore.chatDraft = starter
                            mode = .ask
                            send()
                        }
                    ) { composer }
                } else {
                    messageList(column: column)
                    // No rule above the composer — it carries its own bordered container,
                    // so the seam was redundant chrome. Matches the header's no-divider
                    // direction. It shares the transcript's reading column, so the composer
                    // and the words above it start and end on the same two vertical lines.
                    composer.readingColumn(column).padding(.bottom, 12)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ChatBackdrop())
    }

    /// The dock's only chrome: a trailing pair of icon buttons — history (thread
    /// switcher) and collapse (⌘B). No title row and no divider; the chat starts
    /// at the top of the dock and these two controls sit quietly above it.
    ///
    /// History is icon-only, so both buttons carry `.help` tooltips — hover is the
    /// only thing naming them now.
    /// Leading, not trailing — and the panel toggle first, which is where ChatGPT puts its
    /// sidebar control. Founder call, Aug 5, with their icon as the reference: a panel glyph
    /// rather than a bare chevron, because a chevron says "go" and this hides a panel.
    ///
    /// Sized to the reading column so the two controls sit on the same left edge as the words
    /// below them, at any dock width — the alternative is a fixed inset that lines up at
    /// exactly one width, which is the mistake this file has already made five times.
    private func header(column: CGFloat) -> some View {
        HStack(spacing: 2) {
            Button { companyStore.dockCollapsed = true } label: {
                // Mirrors the dock it collapses: the filled half sits on the side the panel is
                // on. `leadinghalf` is the glyph ChatGPT uses, but their sidebar is on the left
                // and this dock is on the right, so the mirrored variant is the same icon
                // pointing at the right panel.
                Image(systemName: "rectangle.trailinghalf.filled")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Thu gọn trợ lý (⌘B)" : "Collapse copilot (⌘B)")
            Button { showHistory.toggle() } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isChatBusy ? CodepetTheme.mutedText.opacity(0.5)
                                     : (showHistory ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isChatBusy)
            .help(lang == .vi ? "Lịch sử hội thoại" : "Chat history")
            Spacer(minLength: 0)
        }
        .frame(width: column, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 6)
    }

    /// The shared composer — one `ChatComposer` instance used in BOTH the empty
    /// hero (injected via `ChatEmptyState`'s trailing closure) and the active
    /// conversation (at the bottom). Owns no state: draft/mode/selectedDept live
    /// here so the same values drive both placements.
    private var composer: some View {
        ChatComposer(
            draft: $companyStore.chatDraft,
            mode: $mode,
            canSend: canSend,
            focus: $inputFocused,
            // "Codepet", not the pet's name: the founder is talking to the product, and
            // the pet's own name belongs to the moment it answers (`headerName`).
            placeholder: lang == .vi ? "Hỏi Codepet bất cứ điều gì về công ty…"
                                     : "Ask Codepet anything about your company…",
            quickActions: quickActions,
            accent: companionColor,
            accent2: CodepetTheme.accentPink,
            isBusy: isChatBusy,
            selectedDept: $selectedDept,
            onSend: send,
            onQuickAction: handleQuickAction
        )
    }

    /// The `+` menu quick-actions. "Run my next moves" fans out parallel
    /// department agents (→ `AgentsWorkingRow`); the rest fill the composer with
    /// a starter question and send it (mirrors `main`'s prior quick-start pills).
    private var runMovesTitle: String { lang == .vi ? "Chạy các bước tiếp theo" : "Run my next moves" }
    private var quickActions: [QuickAction] {
        lang == .vi
            ? [QuickAction(title: runMovesTitle, systemImage: "bolt.fill",
                           detail: "Cho đội chạy song song các việc tiếp theo."),
               QuickAction(title: "Nên tập trung vào đâu trước?", systemImage: "target",
                           detail: "Ưu tiên tiếp theo là gì."),
               QuickAction(title: "Tóm tắt tình hình công ty", systemImage: "doc.text",
                           detail: "Bức tranh tổng thể hiện tại.")]
            : [QuickAction(title: runMovesTitle, systemImage: "bolt.fill",
                           detail: "Let the team run your next moves in parallel."),
               QuickAction(title: "What should I focus on first?", systemImage: "target",
                           detail: "The next priority to pursue."),
               QuickAction(title: "Summarize where my company is", systemImage: "doc.text",
                           detail: "The big-picture status right now.")]
    }

    private func handleQuickAction(_ title: String) {
        showHistory = false
        if title == runMovesTitle {
            Task { await companyStore.fanOutNextMoves(language: lang) }
        } else {
            companyStore.chatDraft = title
            mode = .ask
            send()
        }
    }

    /// The newest Virtual Company run's message — the room sits under its OWN question,
    /// which is not necessarily the end of the transcript, so this is what the scroll
    /// follows rather than `chatMessages.last`.
    private var vcRunMessage: CopilotMessage? {
        companyStore.chatMessages.last { $0.vcRun != nil }
    }

    /// How many cards that run has put on screen. Every frame adds one, so this rises
    /// monotonically through a run and is what the transcript scrolls on — the run lives
    /// in a single message, so the message count cannot.
    private var vcRunCardCount: Int {
        guard let run = vcRunMessage?.vcRun else { return 0 }
        return (run.routing != nil ? 1 : 0) + run.agents.count + run.positions.count
            + run.agentErrors.count + run.conflicts.count + run.negotiationRounds.count
            + (run.verdict != nil ? 1 : 0) + (run.brief != nil ? 1 : 0)
            + (run.telemetry != nil ? 1 : 0) + (run.stoppedReason != nil ? 1 : 0)
            + (run.terminalError != nil ? 1 : 0)
    }

    private func messageList(column: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ChatRhythm.messageGap) {
                    // Enumerated for ONE reason: the gap above a message depends on who spoke
                    // before it. A flat spacing gives a question and its answer the same
                    // distance as two paragraphs from the same speaker, which is what made
                    // the transcript read as one undivided block.
                    ForEach(Array(companyStore.chatMessages.enumerated()), id: \.element.id) { idx, m in
                        let previousRole = idx > 0 ? companyStore.chatMessages[idx - 1].role : nil
                        CopilotBubble(message: m)
                            .padding(.top, ChatRhythm.extraGap(after: previousRole, before: m.role))
                            .id(m.id)
                        if companyStore.codingRun.run != nil,
                           companyStore.codingRunAnchorId == m.id {
                            CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")
                        }
                    }
                    // A run with no chat anchor (triggered from tasks/roadmap) falls to the bottom.
                    // Anchored runs render ONLY inline (above, next to their anchor message) —
                    // if the anchor isn't in this thread's buffer (a switch/leak), nothing
                    // renders here for it.
                    if companyStore.codingRun.run != nil,
                       companyStore.codingRunAnchorId == nil {
                        CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")
                    }
                    // Parallel department agents (a "Run my next moves" fan-out).
                    if !companyStore.activeAgentRuns.isEmpty {
                        AgentsWorkingRow(runs: companyStore.activeAgentRuns).id("agents")
                    }
                    // The streaming/typing affordance (Task 11) — replaces main's
                    // static typingRow. Generic label (no single-run step source here).
                    if companyStore.isCompanionTyping { ChatThinkingRow().id("typing") }
                }
                .readingColumn(column)
                .padding(.top, ChatRhythm.transcriptTop)
                .padding(.bottom, ChatRhythm.transcriptBottom)
            }
            .onChange(of: companyStore.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
            .onChange(of: companyStore.isCompanionTyping) { _, typing in
                if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
            .onChange(of: companyStore.activeAgentRuns.count) { _, count in
                if count > 0 { withAnimation { proxy.scrollTo("agents", anchor: .bottom) } }
            }
            // A Virtual Company run is ONE message that then grows for 30–60s, so
            // `chatMessages.count` above scrolls to it once (and only if it landed last)
            // and then stops while the cards pile up out of view. Follow the run itself
            // — the same thing this file already does for the coding run and the fan-out
            // row, neither of which changes the message count either. Scrolling to the
            // ROOM's id, not to the transcript bottom: the room is inserted under its own
            // question, so the bottom may be an unrelated later turn.
            .onChange(of: vcRunCardCount) { _, count in
                guard count > 0, let id = vcRunMessage?.id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
            // Nested-ObservableObject publishers emit in willSet (before the new value
            // is assigned), so defer one runloop turn to re-render on the committed value —
            // otherwise the card sticks on "running" until a tab switch.
            .onReceive(companyStore.codingRun.$run) { _ in
                DispatchQueue.main.async {
                    codingRunTick &+= 1
                    if companyStore.codingRun.run != nil {
                        withAnimation { proxy.scrollTo("coding-run", anchor: .bottom) }
                    }
                }
            }
            .onReceive(companyStore.codingRun.$steps) { _ in
                DispatchQueue.main.async {
                    codingRunTick &+= 1
                    if companyStore.codingRun.run != nil {
                        withAnimation { proxy.scrollTo("coding-run", anchor: .bottom) }
                    }
                }
            }
        }
    }

    /// The `onSend` routing — the core "streamline Let's build in" change.
    /// `.ask`/`.plan` shape the text and stream a grounded chat reply (with any
    /// selected department focus); `.build` stages a local coding run instead of
    /// a chat turn. Callable directly by `onStarter`/quick-actions too, so it
    /// guards empty input itself rather than relying on the composer's `canSend`.
    private func send() {
        let text = companyStore.chatDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        companyStore.chatDraft = ""
        showHistory = false   // sending always returns to the live conversation
        switch mode {
        case .ask, .plan:
            // `founderAsk` is the unshaped text: byte should see the mode's framing
            // ("Help me plan this — …"), the Virtual Company's router should not, since
            // it decides `request_type` and rewrites the question into `real_question`.
            Task {
                await companyStore.sendChat(mode.shape(text, language: lang), language: lang,
                                            department: selectedDept, founderAsk: text,
                                            convenesRoom: mode.convenesRoom)
            }
        case .build:
            companyStore.startCodeRun(ask: text)   // shows .noProject card if nothing linked
        }
    }
}

/// The "History" panel: session-only multi-thread switcher — "+ New chat", one
/// row per thread (title/relative time, active row highlighted), rename + delete
/// per row. Tapping a row switches threads and closes the panel. Level 1: pure
/// `CompanyStore` state, no persistence. Native port of the web `ThreadList()`.
struct ThreadListView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Binding var showHistory: Bool
    @State private var renamingId: String?
    @State private var renameDraft = ""
    // Stamped once at appear (not read live in the body) so relative times don't
    // recompute on every re-render — the panel remounts each time History opens,
    // which is when the times should refresh. Mirrors the web's lazy `useState`.
    @State private var now = Date()

    private var rows: [ChatThread] { sortThreadsByRecent(companyStore.threads) }
    /// Gates "New chat" + per-row switch/delete while a turn is in flight —
    /// mirrors `CopilotChatView.isChatBusy` (also gates the History toggle
    /// that opens this panel). Rename is left enabled: it only edits a title
    /// in `threads`, it never repoints `chatMessages`, so it can't corrupt an
    /// in-flight stream. `CompanyStore.newChat()`/`switchThread(_:)`/
    /// `deleteThread(_:)` guard the same condition independently — this is UI
    /// affordance on top of that store-level guard, not a substitute for it.
    private var isChatBusy: Bool {
        companyStore.isCompanionTyping || companyStore.isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                companyStore.newChat()
                showHistory = false
            } label: {
                Text("+ " + (lang == .vi ? "Đoạn chat mới" : "New chat"))
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isChatBusy ? CodepetTheme.accentPurple.opacity(0.5) : CodepetTheme.accentPurple))
            }
            .buttonStyle(.plain)
            .disabled(isChatBusy)
            .padding(12)

            if rows.isEmpty {
                Text(lang == .vi ? "Chưa có đoạn chat nào." : "No chats yet.")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rows) { thread in
                            threadRow(thread)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { now = Date() }
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        let isActive = thread.id == companyStore.activeThreadId
        return Group {
            if renamingId == thread.id {
                HStack(spacing: 6) {
                    TextField(lang == .vi ? "Đổi tên đoạn chat" : "Rename chat", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(CodepetTheme.inter(12))
                        .onSubmit { commitRename(thread.id) }
                    Button(lang == .vi ? "Lưu" : "Save") { commitRename(thread.id) }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
                .padding(10)
            } else {
                HStack(spacing: 6) {
                    Button {
                        companyStore.switchThread(thread.id)
                        showHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.title ?? (lang == .vi ? "Đoạn chat mới" : "New chat"))
                                .font(CodepetTheme.inter(12, weight: isActive ? .semibold : .regular))
                                .foregroundColor(CodepetTheme.primaryText)
                                .lineLimit(1)
                            Text(relativeTime(thread.updatedAt, now: now))
                                .font(CodepetTheme.inter(10))
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isChatBusy)

                    Menu {
                        Button {
                            renameDraft = thread.title ?? ""
                            renamingId = thread.id
                        } label: {
                            Label(lang == .vi ? "Đổi tên" : "Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            companyStore.deleteThread(thread.id)
                        } label: {
                            Label(lang == .vi ? "Xóa" : "Delete", systemImage: "trash")
                        }
                        .disabled(isChatBusy)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)
                }
                .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? CodepetTheme.accentPurple.opacity(0.08) : CodepetTheme.surface))
    }

    private func commitRename(_ id: String) {
        companyStore.renameThread(id, title: renameDraft)
        renamingId = nil
    }
}

/// One chat bubble — me (accent, right) vs companion (surface, left), OR a draft
/// deliverable card (Approve/Redo) when the message carries a draft.
struct CopilotBubble: View {
    let message: CopilotMessage
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    /// The draft card's chrome is scheme-dependent (`cardChrome`), so the bubble needs it.
    @Environment(\.colorScheme) private var scheme
    @State private var showDetail = false
    /// Expansion of the finished run's "What <Name> did" log on a draft card.
    @State private var showSteps = false
    /// Expansion of the fast answer once a room has superseded it — see `firstTakeRow`.
    @State private var showFirstTake = false
    /// Hover state for the per-message action row, and the transient "Copied" acknowledgement.
    @State private var hovering = false
    @State private var copied = false
    @State private var interviewDraft = ""
    private var isMe: Bool { message.role == .me }

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }

    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }

    /// Who is speaking. "Codepet" for the product's own voice; a pet's name ONLY when that pet
    /// is the one doing the work — a department specialist, carried on `companionId`.
    ///
    /// The founder's model, stated Aug 5: she chats with Codepet. Glitch, Nova, Luna and the
    /// rest are department characters, not the assistant — so signing a general answer "Glitch"
    /// named the wrong thing. (This reverses the reading I shipped earlier the same day, where
    /// the header carried the CHOSEN companion's name. "The name appears when it responds" meant
    /// when a PET responds, i.e. on a department's task, not on every reply.)
    private var headerName: String {
        guard let id = message.companionId, let pet = PetCharacter.all[id] else {
            return CodepetBrand.name
        }
        if let dept = message.deptName, !dept.isEmpty { return "\(pet.name) · \(dept)" }
        return pet.name
    }
    private var headerAccent: Color {
        guard let id = message.companionId else { return companionAccent }
        return PetCharacter.all[id]?.color ?? companionAccent
    }

    var body: some View {
        if message.producing {
            if let steps = message.execSteps, !steps.isEmpty {
                ExecLogRow(taskTitle: message.text, deptName: message.deptName, steps: steps,
                           companionId: message.companionId)
            } else {
                producingRow
            }
        } else if let run = message.vcRun {
            // The room has its own appended message and nothing else is ever written
            // into it, so this branch's position in the chain is not load-bearing — but
            // it stays first, ahead of the payloads that CAN coexist on one message.
            // The text bubble above the cards is byte's handoff line: byte speaking,
            // then the room.
            VStack(alignment: .leading, spacing: 8) {
                textBubble
                VCRunCards(state: run, lockedIn: message.actionConsumed) {
                    Task {
                        await companyStore.lockInVirtualCompanyDecision(run, messageId: message.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let draft = message.draft {
            draftCard(draft)
        // An action now rides on the reply it belongs to and is drawn inside that
        // reply's card (see `inlineActions`). These three branches remain only for
        // the fallback the store still writes: an action with no reply to attach to,
        // which has nothing to sit inside and so keeps its standalone row.
        } else if let nav = message.navChip, textIsBlank {
            navChip(nav)
        } else if let setup = message.setupSuggestion, textIsBlank {
            setupCard(setup)
        } else if let facts = message.noted, !facts.isEmpty, textIsBlank {
            notedChip(facts)
        } else if let action = message.firstRunAction, !message.actionConsumed {
            VStack(alignment: .leading, spacing: 8) {
                textBubble
                actionButton(action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let proposal = message.runProposal {
            runProposalCard(proposal)
        } else if let proposal = message.roadmapProposal {
            roadmapProposalCard(proposal)
        } else if let gap = message.interview, !message.interviewAnswered {
            interviewCard(gap)
        } else {
            textBubble
        }
    }

    /// A run the founder started from a surface, offered before it happens.
    ///
    /// The sentence stays a plain reply — the proposal is Codepet talking, not a widget — and the
    /// only chrome is the confirm button under it. Once pressed, `actionConsumed` retires the
    /// button and the sentence remains as the record of what was asked for, so the transcript
    /// reads "we agreed to do this" and then shows the run.
    @ViewBuilder private func runProposalCard(_ proposal: RunProposal) -> some View {
        VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
            textBubble
            if message.actionConsumed {
                // Retired, not removed: a vanished button loses the fact a run was confirmed.
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(lang == .vi ? "Đã bắt đầu" : "Started")
                }
                .font(.pixelSystem(size: DraftCardMetrics.chip, weight: .semibold))
                .foregroundColor(CodepetTheme.accentTeal)
            } else {
                Button {
                    Task { await companyStore.confirmRun(messageId: message.id, language: lang) }
                } label: {
                    Text(proposal.buttonLabel(lang))
                        .font(.pixelSystem(size: DraftCardMetrics.action, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                        .hoverAffordance(Capsule())
                }
                .buttonStyle(.plain)
                .cursorOnHover(.pointingHand)
                // A run is the one action here that spends credits, so it must not be
                // pressable while another run or a chat turn is already in flight.
                .disabled(companyStore.isStreaming || companyStore.isCompanionTyping
                          || companyStore.runningTaskIds.contains(proposal.taskId))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A roadmap change Codepet is offering to make.
    ///
    /// Same shape as `runProposalCard`, and for the same reason: the sentence stays a plain reply,
    /// the only chrome is the confirm button, and once pressed the button retires to a record of
    /// what happened rather than vanishing. The founder should be able to scroll back and see that
    /// her roadmap changed, and on whose say-so.
    @ViewBuilder private func roadmapProposalCard(_ proposal: RoadmapProposal) -> some View {
        VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
            textBubble
            if message.actionConsumed {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(proposal.doneLabel(lang))
                }
                .font(.pixelSystem(size: DraftCardMetrics.chip, weight: .semibold))
                .foregroundColor(CodepetTheme.accentTeal)
            } else {
                Button {
                    Task { await companyStore.confirmRoadmapProposal(messageId: message.id, language: lang) }
                } label: {
                    Text(proposal.buttonLabel(lang))
                        .font(.pixelSystem(size: DraftCardMetrics.action, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                        .hoverAffordance(Capsule())
                }
                .buttonStyle(.plain)
                .cursorOnHover(.pointingHand)
                .disabled(companyStore.isStreaming || companyStore.isCompanionTyping)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per-message actions, revealed on hover — the row both references put under an answer
    /// (copy · retry · a timestamp). Deliberately only two buttons: thumbs would need a
    /// `feedback` collection and a Firestore rule that do not exist natively yet, and a control
    /// that silently drops the founder's opinion is worse than no control. Speak and share are
    /// the same judgement — offered when they do something.
    ///
    /// Hover-only because an answer is for reading; the affordances belong to the moment you
    /// reach for them, not to the reading. `opacity` rather than a conditional so the row's
    /// height never changes under the cursor.
    @ViewBuilder private var messageActions: some View {
        HStack(spacing: 2) {
            actionIcon("doc.on.doc", help: lang == .vi ? "Sao chép" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    copied = false
                }
            }
            .overlay(alignment: .leading) {
                if copied {
                    Text(lang == .vi ? "Đã sao chép" : "Copied")
                        .font(.pixelSystem(size: 9, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                        .offset(x: 22)
                        .transition(.opacity)
                }
            }
            actionIcon("arrow.clockwise", help: lang == .vi ? "Hỏi lại" : "Try again") {
                Task { await companyStore.retryReply(messageId: message.id, language: lang) }
            }
            .disabled(companyStore.isCompanionTyping || companyStore.isStreaming)
            Text(Self.age(of: message.createdAt, lang: lang))
                .font(.pixelSystem(size: 9))
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.leading, 4)
        }
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    private func actionIcon(_ system: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// "just now" until a minute has passed, then minutes, then hours — the reference's
    /// "3 hours ago" without pretending to know about sessions that are already over.
    static func age(of date: Date, lang: AppLanguage) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return lang == .vi ? "vừa xong" : "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return lang == .vi ? "\(minutes) phút trước" : "\(minutes)m ago" }
        let hours = minutes / 60
        return lang == .vi ? "\(hours) giờ trước" : "\(hours)h ago"
    }

    private func actionButton(_ action: FirstRunAction) -> some View {
        Button {
            Task { await companyStore.runFirstRunAction(messageId: message.id, language: lang) }
        } label: {
            Text((lang == .vi ? "Làm cùng mình: " : "Do it with me: ") + action.taskTitle)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.accentPurple)).hoverAffordance(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A tappable "go here" chip from byte's `nav` action — NOT auto-navigated
    /// (mirrors the web: the founder taps to move). Tapping resolves + applies
    /// the destination via `CompanyStore.activateNav` (sync — `select`/
    /// `selectedDeptKey` are plain mutations, no await needed).
    private var textIsBlank: Bool {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The actions belonging to THIS reply, drawn directly under its text.
    ///
    /// The nav chip and the noted rows carry their own capsule, so they stand on the
    /// backdrop unaided. The setup suggestion does not — it is a name, a why-line and an
    /// Enable button that used to be bounded by the reply's `MessageCard`, and with the
    /// prose un-carded it would spill onto the backdrop as loose text. So it keeps a
    /// container of its own, which is the same rule the standalone `setupCard` follows:
    /// an offer is an object, the sentence introducing it is not.
    @ViewBuilder private var inlineActions: some View {
        if let nav = message.navChip { navChipButton(nav) }
        if let setup = message.setupSuggestion {
            HStack {
                CodepetCard { setupInline(setup).padding(12) }
                Spacer(minLength: 24)
            }
        }
        if let facts = message.noted, !facts.isEmpty { notedInline(facts) }
    }

    private func navChipButton(_ nav: NavAction) -> some View {
        let label = AppView.from(navDestination: nav.destination)?.title(lang) ?? nav.destination
        return Button { companyStore.activateNav(nav) } label: {
            Text((lang == .vi ? "Đi tới " : "Go to ") + label)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.accentPurple)).hoverAffordance(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func navChip(_ nav: NavAction) -> some View {
        HStack {
            navChipButton(nav)
            Spacer(minLength: 24)
        }
    }

    /// A tappable "turn this on" card from byte's `setup` action. Resolves the
    /// wire {category,name} to its `Toolkit` item for the display name/why-line
    /// and the category-appropriate enable verb; tapping runs the GUARDED
    /// enable in `CompanyStore.activateSetup` (never flips an already-on item off).
    @ViewBuilder private func setupInline(_ setup: SetupAction) -> some View {
        let item = Toolkit.find(category: setup.category, name: setup.name)
        let why = item?.why
        VStack(alignment: .leading, spacing: 8) {
            Text(item?.name ?? setup.name)
                .font(.pixelSystem(size: 12, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            if let why, !why.isEmpty {
                Text(why)
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await companyStore.activateSetup(setup) } } label: {
                Text(item?.category.enableVerb(lang) ?? (lang == .vi ? "Bật" : "Enable"))
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.accentPurple)).hoverAffordance(Capsule())
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupCard(_ setup: SetupAction) -> some View {
        HStack {
            CodepetCard { setupInline(setup).padding(12) }
            Spacer(minLength: 24)
        }
    }

    /// A transient "Noted" chip per remembered fact — memory is already merged +
    /// persisted (`CompanyStore.handleRemember`) by the time this renders, so
    /// there is no tap/approval affordance here, just an acknowledgement.
    private func notedInline(_ facts: [RememberedFact]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(facts, id: \.topic) { fact in
                // CLAMPED, and a capsule no longer: `statement` is whatever the model chose to
                // remember, and when the Virtual Company files its brief that is several hundred
                // words. Unclamped inside a Capsule it rendered as a wall of grey text taller
                // than the answer it summarised (seen in the app, Aug 5). An acknowledgement is
                // one line; the fact itself lives in Settings → Memory.
                Text("📌 " + (lang == .vi ? "Đã ghi nhớ" : "Noted") + " · \(fact.topic) — \(fact.statement)")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CodepetTheme.surface))
            }
        }
    }

    private func notedChip(_ facts: [RememberedFact]) -> some View {
        HStack {
            notedInline(facts)
            Spacer(minLength: 24)
        }
    }

    /// First-run enrichment interview: question + why-line + free-text answer,
    /// Send (saves raw text to the brief) or Skip (advances without saving).
    private func interviewCard(_ gap: InterviewGap) -> some View {
        let q = EnrichInterview.question(for: gap, language: lang)
        let canSend = !interviewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Rendered as a teammate card (orb + name + surface) so the first-run
        // question reads like a companion message in the web chat language.
        return HStack(alignment: .top, spacing: 8) {
            CompanionOrb(size: 22, glow: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(CodepetBrand.name)
                    .font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                MessageCard(hue: companionAccent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(q.ask)
                            .font(CodepetTheme.inter(14.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(q.why)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField(lang == .vi ? "Nhập câu trả lời…" : "Type your answer…",
                                  text: $interviewDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(CodepetTheme.inter(13.5))
                            .lineLimit(1...4)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(CodepetTheme.pageBackground))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(CodepetTheme.hairline, lineWidth: 1))
                        HStack(spacing: 8) {
                            Button {
                                let answer = interviewDraft
                                interviewDraft = ""
                                Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: answer, language: lang) }
                            } label: {
                                Text(lang == .vi ? "Gửi" : "Send")
                                    .font(CodepetTheme.inter(13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Capsule().fill(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                            }
                            .buttonStyle(.plain).disabled(!canSend)
                            Button {
                                interviewDraft = ""
                                Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: nil, language: lang) }
                            } label: {
                                Text(lang == .vi ? "Bỏ qua" : "Skip")
                                    .font(CodepetTheme.inter(13, weight: .medium))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .overlay(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                                    .hoverAffordance(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chat-run step-transparency indicator (web: a "producing" beat before the
    /// draft card lands). Matches `CopilotChatView.typingRow`'s orb + Inter style —
    /// not a filled chat bubble — so it reads as ambient status, not a message.
    /// `CompanyStore.handleRunTaskId` removes this row (win or lose) before
    /// appending the real reply, so it's always transient.
    private var producingRow: some View {
        HStack(spacing: 8) {
            CompanionOrb(size: 20, glow: false, isWorking: true)
            // Ambient status, not the pet speaking — so "Codepet", like the composer.
            Text(lang == .vi ? "Codepet đang tổng hợp…" : "Codepet is putting that together…")
                .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 8)
        }
    }

    /// The fast answer, demoted once the room has landed.
    ///
    /// Both calls go out in parallel so ordinary chat keeps its latency, so this reply was written
    /// before the router had decided anything. When a room lands, the founder has just read a
    /// confident several-hundred-word answer immediately followed by "Actually — this one needs the
    /// whole room": it reads as Codepet contradicting itself (founder, Aug 7).
    ///
    /// It is not wrong, it is EARLY, and the room's call is the better answer — on the founder's own
    /// test the room proposed a cohort split the fast reply never considered. So it collapses to a
    /// line that names it as the first take and keeps it one click away, rather than being deleted:
    /// throwing away an answer she has already partly read would be its own kind of lie about what
    /// happened.
    @ViewBuilder private var firstTakeRow: some View {
        VStack(alignment: .leading, spacing: ChatRhythm.nameToProse) {
            Button { withAnimation(.easeInOut(duration: 0.16)) { showFirstTake.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: showFirstTake ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(lang == .vi ? "Ý đầu tiên của Codepet" : "Codepet's first take")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                    Text(BriefDocument.headline(message.text))
                        .font(CodepetTheme.inter(12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodepetTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CodepetTheme.hairline, lineWidth: 1))
                .hoverAffordance(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .cursorOnHover(.pointingHand)
            if showFirstTake {
                Text(message.text)
                    .font(CodepetTheme.inter(13.5))
                    .lineSpacing(ChatRhythm.lineSpacing)
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var textBubble: some View {
        // A message shell can reach here with no text yet — while the companion is
        // still typing, or when the turn carried only a payload. `MessageCard` always
        // draws its fill and 1pt border, so rendering an empty one left a bare bordered
        // box that read as an error state. `ChatThinkingRow` already covers the waiting
        // beat, so render nothing rather than an empty card.
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else if message.supersededByRoom && !isMe {
            firstTakeRow
        } else if isMe {
            HStack {
                Spacer(minLength: 24)
                Text(message.text)
                    .font(CodepetTheme.inter(13.5))
                    .lineSpacing(ChatRhythm.lineSpacing)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CodepetTheme.accentPurple))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            // Attribution row, then the answer at the FULL width of the dock.
            //
            // The reply used to sit in a tinted, bordered `MessageCard` inside an avatar
            // gutter, which cost it the gutter's 30pt plus the card's 24pt of padding on
            // every line — in a dock this narrow that is a word or two per line, and the
            // long answers are exactly the ones worth reading. A container earns its
            // edges when it bounds an OBJECT (a draft, a room, an exec log); prose is not
            // an object, and the name row above it already says where it came from.
            // Founder call, Aug 5.
            //
            // `CompanionAvatar` shows the specialist's sprite for a handoff, the host orb
            // otherwise, and `headerName` carries the "Name · Dept" attribution — so the
            // one place the pet's own name appears is the moment it answers.
            VStack(alignment: .leading, spacing: ChatRhythm.nameToProse) {
                HStack(spacing: 8) {
                    CompanionAvatar(companionId: message.companionId, size: 22)
                    Text(headerName)
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                }
                VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
                    Text(message.text)
                        .font(CodepetTheme.inter(13.5))
                        .lineSpacing(ChatRhythm.lineSpacing)
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    inlineActions
                    messageActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The finished run's steps, collapsed behind a disclosure on the deliverable card.
    /// Deliberately quiet: it is a receipt, not the headline — the deliverable is. Named after
    /// the specialist who did the work (`headerName` carries "Nova · Marketing", so just the
    /// name here), matching the web's "What Nova did".
    private func whatItDid(_ steps: [ExecStep]) -> some View {
        let who = PetCharacter.all[message.companionId ?? companyStore.company.companionId]?.name ?? "Codepet"
        return VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showSteps.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: showSteps ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(lang == .vi ? "\(who) đã làm gì · \(steps.count) bước"
                                     : "What \(who) did · \(steps.count) steps")
                        .font(.pixelSystem(size: DraftCardMetrics.chip, weight: .semibold))
                }
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .overlay(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                .hoverAffordance(Capsule())
            }
            .buttonStyle(.plain)
            if showSteps {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(steps) { step in
                        let isCheckpoint = step.kind == .checkpoint
                        HStack(alignment: .top, spacing: 6) {
                            if step.kind == .mono {
                                Text("›").font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .frame(width: 10, height: 12)
                            } else {
                                Image(systemName: isCheckpoint ? "circle.fill" : "checkmark")
                                    .font(.system(size: isCheckpoint ? 6 : 8, weight: .bold))
                                    .foregroundColor(isCheckpoint ? CodepetTheme.accentGold : CodepetTheme.accentPurple)
                                    .frame(width: 10, height: 12)
                            }
                            Text(step.label)
                                .font(step.kind == .mono
                                      ? .system(size: DraftCardMetrics.chip, design: .monospaced)
                                      : .pixelSystem(size: DraftCardMetrics.chip))
                                .foregroundColor(isCheckpoint ? CodepetTheme.accentGold : CodepetTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 2)
            }
        }
    }

    private func draftCard(_ d: Deliverable) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DraftCardMetrics.blockGap) {
                    // Opening the deliverable is the card's largest target, and it was the ONLY
                    // one with no pointer response: every small pill carried `hoverAffordance`
                    // while the title and body — the thing you actually click to read the work —
                    // had a bare `contentShape` and no cursor. The affordance was inverted
                    // (founder, Aug 6), so the block now gets the same hover fill the pills get,
                    // plus the pointing hand.
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: d.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                            Text(d.title)
                                .font(.pixelSystem(size: DraftCardMetrics.title, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                        }
                        // Markdown syntax used to reach the founder verbatim — see `DraftPreview`.
                        Text(DraftPreview.plain(d.body, title: d.title))
                            .font(.pixelSystem(size: DraftCardMetrics.body))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineSpacing(ChatRhythm.lineSpacing)
                            .lineLimit(DraftCardMetrics.previewLines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .padding(.horizontal, 2)
                    .hoverAffordance(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .cursorOnHover(.pointingHand)
                    .onTapGesture { showDetail = true }
                    // Cancels the 6/2 inset above so the block's text stays optically flush with
                    // the buttons below it while its hover fill still reads as a target.
                    .padding(-6).padding(.horizontal, -2)

                    // "▸ What Nova did · 6 steps" — the run's own log, kept. Web parity
                    // (inline-run transparency): the live execute-log collapses onto the
                    // finished deliverable instead of vanishing with it, so "how did it get
                    // this?" is answerable after the fact and not only during the four seconds
                    // the run was on screen. Absent → nothing renders, so a draft from the
                    // board (no chat run, no steps) is unchanged.
                    if let steps = message.execSteps, !steps.isEmpty {
                        whatItDid(steps)
                    }

                    if message.draftApproved {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(lang == .vi ? "Đã thêm vào Thư viện" : "Added to Library")
                        }
                        .font(.pixelSystem(size: DraftCardMetrics.chip, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                    } else {
                        // DECIDE, then adjust. Approve/Redo settle the draft; the revise chips
                        // only nudge it. They used to sit 8pt apart at 10pt and 9pt, so five
                        // pills read as one undifferentiated cluster with no answer to "which of
                        // these is the point?" (founder, Aug 6). The gap and the rule below carry
                        // that hierarchy; Approve carries it in weight.
                        HStack(spacing: 9) {
                            Button { Task { await companyStore.approveDraft(messageId: message.id) } } label: {
                                Text(lang == .vi ? "Duyệt" : "Approve")
                                    .font(.pixelSystem(size: DraftCardMetrics.action, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().fill(CodepetTheme.accentPurple)).hoverAffordance(Capsule())
                            }.buttonStyle(.plain)
                            Button { Task { await companyStore.redoDraft(messageId: message.id, language: lang) } } label: {
                                Text(lang == .vi ? "Làm lại" : "Redo")
                                    .font(.pixelSystem(size: DraftCardMetrics.action, weight: .semibold))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().stroke(CodepetTheme.hairline))
                                    .hoverAffordance(Capsule())
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, DraftCardMetrics.decideGap - DraftCardMetrics.blockGap)

                        // Revise chips: one-tap re-runs of THIS draft with a targeted
                        // instruction (vs. Redo's blind re-run). Same visibility gate as
                        // Redo — hidden once approved.
                        VStack(alignment: .leading, spacing: 9) {
                            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                            HStack(spacing: 7) {
                                ForEach(ReviseKind.allCases, id: \.self) { kind in
                                    Button {
                                        Task { await companyStore.redoDraft(messageId: message.id, language: lang,
                                                                             reviseNote: kind.note(lang)) }
                                    } label: {
                                        Text(kind.label(lang))
                                            .font(.pixelSystem(size: DraftCardMetrics.chip, weight: .semibold))
                                            .foregroundColor(CodepetTheme.mutedText)
                                            .padding(.horizontal, 11).padding(.vertical, 5)
                                            .background(Capsule().stroke(CodepetTheme.hairline))
                                            .hoverAffordance(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
            }
            .padding(DraftCardMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The house card chrome — a lifted fill AND a 1pt edge. `CodepetCard` draws fill +
            // shadow only, and at `surface` (#221d17) on a near-black dock that is a ~3%
            // lightness step with an invisible shadow: the card had no edge to hold its contents
            // and everything inside read as loose floating text (founder, Aug 6, "the card is
            // black"). Every Tasks-board card already uses this; the chat's draft card was the
            // one card in the app without an edge.
            .cardChrome(radius: 12, dark: scheme == .dark)
            Spacer(minLength: 24)
        }
        .sheet(isPresented: $showDetail) { DeliverableDetailView(deliverable: d) }
    }
}

/// The 3 one-tap revise chips on a draft card: a targeted re-run (vs. Redo's blind
/// re-run) that threads a short instruction + the draft's current body into the
/// RunTaskRequest so the CF revises in place. Internal (not private) so the Tasks
/// draft-preview sheet reuses the exact same labels/notes.
enum ReviseKind: CaseIterable {
    case shorter, moreDetail, punchier

    /// Chip label (short, matches Approve/Redo's terse pill style).
    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.shorter, .vi): return "Ngắn gọn hơn"
        case (.shorter, _): return "Shorter"
        case (.moreDetail, .vi): return "Chi tiết hơn"
        case (.moreDetail, _): return "More detail"
        case (.punchier, .vi): return "Ấn tượng hơn"
        case (.punchier, _): return "Punchier"
        }
    }

    /// The `reviseNote` sent to the CF — a full instruction, not the terse chip label.
    func note(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.shorter, .vi): return "Làm ngắn gọn hơn"
        case (.shorter, _): return "Make it shorter"
        case (.moreDetail, .vi): return "Thêm chi tiết hơn"
        case (.moreDetail, _): return "Add more detail"
        case (.punchier, .vi): return "Làm ấn tượng hơn"
        case (.punchier, _): return "Make it punchier"
        }
    }
}

// MARK: - The chat's reading column

/// The transcript and the composer share one measured column, the way ChatGPT's and
/// Claude's do: inset from the dock's edges, capped at a comfortable line length, and
/// centred in whatever width is left.
///
/// Why a cap and not just padding: the dock is user-resizable, so padding alone means the
/// line length grows with the window and a wide dock produces 140-character lines that the
/// eye loses its place in. Capping the measure turns extra dock width into margin instead.
/// This landed right after the reply lost its bubble — un-carding the prose removed the
/// last thing bounding it, and it ran the full width of the panel. Both numbers are a
/// taste call and this is the only place they live.
///
/// Founder call, Aug 5, referencing ChatGPT and Claude.
/// Both numbers are calibrated against the references rather than guessed. Measured off
/// the founder's own screenshots at 2×: in an ~800pt pane, Claude runs a ~490pt text
/// measure with ~159pt gutters, ChatGPT ~518pt with ~150pt. So the target is a measure
/// near 520pt with generous air — and the first attempt at this (700pt total, 24pt inset)
/// missed for a reason worth writing down: the dock is ~478pt, NARROWER than the
/// references' measure, so a 700pt cap never bound and the 24pt inset was the whole margin.
/// At a dock this size the air has to come out of the inset.
/// A SHARE of the chat box, not a number of points: 18% margin on each side, 64% for the
/// words, recomputed at every width the dock is dragged to.
///
/// The fraction is measured, not chosen. Read off the founder's own reference screenshots
/// at 2×: Claude runs ~159pt gutters in an ~805pt pane (19.8% a side) and ChatGPT ~150pt in
/// ~822pt (18.2%) — so a shade over 18% a side is what those layouts actually do, and it is
/// what makes them read as deliberate at any window size.
///
/// This deliberately reintroduces reflow, which an earlier fixed-measure column had removed:
/// a width defined as a share of the box necessarily changes when the box does, so dragging
/// the divider re-wraps the lines and moves the scroll offset. Founder call, Aug 5, asked
/// with that cost stated — proportional margins won.
///
/// The dock no longer moves with the window (`ShellLayout.dockDefaultWidth`), so at the
/// default this column is stable by construction: the only thing that changes it is the
/// founder dragging the divider, which is a deliberate act rather than a side effect of
/// resizing a window.
enum ChatColumn {
    /// A percentage was the wrong MODEL, not just the wrong number, and three rounds of
    /// "still too wide" is what it took to see it. The references do not scale their margins
    /// with the pane at all: ChatGPT's reading surfaces are `max-width: 800px` with `40px
    /// 16px` padding — a fixed 16px gutter, with air appearing only once the viewport
    /// outgrows the cap. That is why they look tight on a narrow window and generous on a
    /// wide one, and it is already the house rule here: `CodepetTokens.pageColumnWidth` plus
    /// a fixed 26pt page padding, measured from the same place in f05eff2.
    ///
    /// So: a fixed inset that holds at every dock width the founder actually uses, and a cap
    /// that turns a dragged-wide dock into gutter. At the 381pt dock that is 18pt a side
    /// instead of the 34 a 9% ratio produced.
    ///
    /// 18 rather than ChatGPT's 16 because the dock carries a border and a scroll track that
    /// a full-bleed web page does not.
    static let inset: CGFloat = 18

    /// The widest the words go, for the case this cannot control: a founder who drags the
    /// divider out. At the default 380pt dock it never binds — the inset decides the column —
    /// which is why pinning it to 344 was the wrong fix for "don't scale the content out".
    /// That made a dragged-wide dock 278pt of gutter a side; the actual ask was that RESIZING
    /// THE WINDOW leave the chat alone, and that belongs in `ShellLayout`, where the dock's
    /// width is now a constant rather than half the window.
    static let measureCap: CGFloat = 640

    /// The reading column's width inside a chat box of `box` points. Rounded, because a
    /// fractional width makes the text's leading edge land off-pixel and the glyphs blur.
    static func textWidth(forBox box: CGFloat) -> CGFloat {
        max(0, min(box - inset * 2, measureCap).rounded())
    }

    /// The margin each side — whatever the column leaves, split in two. Derived rather than
    /// stated so it can never disagree with the column.
    static func margin(forBox box: CGFloat) -> CGFloat {
        max(0, (box - textWidth(forBox: box)) / 2)
    }
}

/// The draft card's scale and spacing, in one place so the card cannot drift from the prose it
/// sits under again.
///
/// It had drifted badly. The message above the card is `inter(13.5)`; inside it the title was
/// 12, the body 11, Approve/Redo 10 and the revise chips 9 — a card 11–33% smaller than the
/// sentence introducing it, in which **the primary action was set smaller than the body text it
/// approved**, with a ~22pt tap target under the 28pt macOS comfortable minimum. That is the
/// measurable half of "the button and text appear a bit small" (founder, Aug 6).
///
/// The scale below is anchored to the 13.5pt prose rather than chosen: the title matches it, and
/// each tier steps down by one point. Nothing here is smaller than 11.
enum DraftCardMetrics {
    /// Matches the transcript's body size — the card's headline is not a footnote to it.
    static let title: CGFloat = 13.5
    static let body: CGFloat = 12.5
    /// Approve / Redo. At 12 with 16×7 padding the target clears 28pt.
    static let action: CGFloat = 12
    /// Revise chips and the run-log disclosure — the quietest tier, and still legible.
    static let chip: CGFloat = 11
    /// Inside the card. 12 was the same padding a Tasks-board lane card uses at roughly a third
    /// of this card's width, so proportionally this card was the tighter of the two.
    static let padding: CGFloat = 16
    /// Between the card's stacked blocks.
    static let blockGap: CGFloat = 10
    /// Preview → the decision. Deliberately larger than `blockGap`: the buttons are a change of
    /// register, not the next paragraph.
    static let decideGap: CGFloat = 16
    /// The body preview. 3 lines was set when markdown syntax ate two of them; with the syntax
    /// gone, the dock's width supports a fourth line of actual prose.
    static let previewLines: Int = 4
}

/// The chat's vertical rhythm. Measured off the founder's reference screenshots as RATIOS,
/// which survive not knowing the screenshots' scale: in both Claude and ChatGPT the body's
/// line height is ~1.6× the font size, and the gap between one speaker's turn and the next
/// is ~2.2–2.7 line heights. Ours was 1.42× and a flat 10pt between every message — which is
/// the whole of the "too cramped, no breathing room" complaint, and the flat gap is the worse
/// half: a question and its answer sat as close together as two paragraphs from one speaker,
/// so the transcript read as one undivided block of text.
///
/// Values are for the 13.5pt body. Font size is deliberately unchanged: at this dock width a
/// bigger face would cost characters per line, and the ask was for whitespace.
enum ChatRhythm {
    /// Extra leading between lines. SwiftUI's `lineSpacing` adds to the font's natural ~1.2em,
    /// so 6 on 13.5pt lands at ~1.64em — the references' ratio.
    static let lineSpacing: CGFloat = 6
    /// Between consecutive messages from the SAME speaker.
    static let messageGap: CGFloat = 12
    /// Added on top of `messageGap` when the speaker changes, so a turn boundary reads as
    /// one: 12 + 26 = 38pt, ~1.8 line heights.
    static let speakerChangeGap: CGFloat = 26
    /// The attribution row to the words it introduces.
    static let nameToProse: CGFloat = 8
    /// The words to the chip or card that belongs to them.
    static let proseToAction: CGFloat = 12
    /// Head of the transcript, so the first message doesn't touch the dock's chrome.
    static let transcriptTop: CGFloat = 20
    /// Tail of the transcript — larger than the head so the last message clears the composer.
    static let transcriptBottom: CGFloat = 24

    /// The extra gap above a message, given who spoke before it. Pure so the rule is
    /// testable: nil `previous` is the first message in the transcript (no gap to add — the
    /// transcript's own top padding does that job), and a repeated role is a continuation.
    static func extraGap(after previous: CopilotRole?, before current: CopilotRole) -> CGFloat {
        guard let previous, previous != current else { return 0 }
        return speakerChangeGap
    }
}

private extension View {
    /// Sized to the column and centred in whatever is left. Two frames, in this order: the
    /// first sets the content to the column width and left-aligns inside it — so a companion
    /// reply and a right-hand founder pill anchor to the same two edges — and the second
    /// expands to the available width and centres that column in it.
    func readingColumn(_ column: CGFloat) -> some View {
        self
            .frame(width: column, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
