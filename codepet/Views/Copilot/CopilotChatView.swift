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
        // The chat box measures itself so the reading column can be a SHARE of that width
        // rather than a fixed number of points (`ChatColumn`). Measured here, at the dock's
        // own bounds, and passed down explicitly: the transcript's column lives inside a
        // ScrollView and the composer's does not, so reading a container-relative width at
        // each site would be asking two different questions and getting two different
        // answers — and these two must line up exactly.
        GeometryReader { geo in
            let column = ChatColumn.textWidth(forBox: geo.size.width)
            VStack(spacing: 0) {
                header
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
    private var header: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            Button { showHistory.toggle() } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isChatBusy ? CodepetTheme.mutedText.opacity(0.5)
                                     : (showHistory ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isChatBusy)
            .help(lang == .vi ? "Lịch sử hội thoại" : "Chat history")
            Button { companyStore.dockCollapsed = true } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Thu gọn trợ lý (⌘B)" : "Collapse copilot (⌘B)")
        }
        .padding(.horizontal, 7).padding(.top, 6)
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
                                            department: selectedDept, founderAsk: text)
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
    @State private var showDetail = false
    @State private var interviewDraft = ""
    private var isMe: Bool { message.role == .me }

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }

    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }

    /// Specialist handoff attribution (Task 7): when a message carries a
    /// `companionId` (a department specialist led the turn), the header reads
    /// "Name · Dept" and the avatar/hue switch to that specialist. A nil
    /// `companionId` keeps the host companion's name, orb, and accent.
    private var headerName: String {
        guard let id = message.companionId else { return companionName }
        let name = PetCharacter.all[id]?.name ?? companionName
        if let dept = message.deptName, !dept.isEmpty { return "\(name) · \(dept)" }
        return name
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
        } else if let gap = message.interview, !message.interviewAnswered {
            interviewCard(gap)
        } else {
            textBubble
        }
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
                Text("📌 " + (lang == .vi ? "Đã ghi nhớ" : "Noted") + " · \(fact.topic) — \(fact.statement)")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.surface))
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
                Text(companionName)
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

    @ViewBuilder private var textBubble: some View {
        // A message shell can reach here with no text yet — while the companion is
        // still typing, or when the turn carried only a payload. `MessageCard` always
        // draws its fill and 1pt border, so rendering an empty one left a bare bordered
        // box that read as an error state. `ChatThinkingRow` already covers the waiting
        // beat, so render nothing rather than an empty card.
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func draftCard(_ d: Deliverable) -> some View {
        HStack {
            CodepetCard {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: d.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                            Text(d.title)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                        }
                        Text(d.body)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showDetail = true }

                    if message.draftApproved {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(lang == .vi ? "Đã thêm vào Thư viện" : "Added to Library")
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                    } else {
                        HStack(spacing: 8) {
                            Button { Task { await companyStore.approveDraft(messageId: message.id) } } label: {
                                Text(lang == .vi ? "Duyệt" : "Approve")
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(CodepetTheme.accentPurple)).hoverAffordance(Capsule())
                            }.buttonStyle(.plain)
                            Button { Task { await companyStore.redoDraft(messageId: message.id, language: lang) } } label: {
                                Text(lang == .vi ? "Làm lại" : "Redo")
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().stroke(CodepetTheme.hairline))
                                    .hoverAffordance(Capsule())
                            }.buttonStyle(.plain)
                        }
                        // Revise chips: one-tap re-runs of THIS draft with a targeted
                        // instruction (vs. Redo's blind re-run). Same visibility gate as
                        // Redo — hidden once approved.
                        HStack(spacing: 6) {
                            ForEach(ReviseKind.allCases, id: \.self) { kind in
                                Button {
                                    Task { await companyStore.redoDraft(messageId: message.id, language: lang,
                                                                         reviseNote: kind.note(lang)) }
                                } label: {
                                    Text(kind.label(lang))
                                        .font(.pixelSystem(size: 9, weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().stroke(CodepetTheme.hairline))
                                        .hoverAffordance(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
/// Points are gone on purpose. Every fixed number tried here (700 total, then 520+36, then a
/// fixed 420+36) was right at exactly one dock width and wrong either side of it, because the
/// dock ranges from `ShellLayout.dockMinWidth` (360pt) to well past `dockIdealMaxWidth`
/// (560pt). A ratio has no such width.
enum ChatColumn {
    /// Margin as a share of the chat box — the ratio, before clamping.
    ///
    /// 18% (the references' own figure) proved to be the wrong ratio for a panel this
    /// narrow: at the 381pt dock the founder had dragged to, 18% is 69pt a side and leaves
    /// 242pt of text, which reads as margin with a column of words in it. The references
    /// earn 18% because their pane is ~800pt — twice this dock — so the same percentage
    /// takes a much smaller share of the reading experience. 12% holds the proportional
    /// behaviour that was asked for while staying reasonable at the narrow end.
    /// The bracket this was narrowed to, since the number came from four rounds of looking:
    /// at a 500pt dock, 36pt (7.2%) read as too close to the edge; at a 381pt dock, 46pt
    /// (12%) read as too wide. 9% sits between them — 34pt at 381, 45pt at 500.
    static let marginFraction: CGFloat = 0.09

    /// Clamps. A pure ratio is wrong at both extremes: at the 360pt dock minimum a large
    /// fraction squeezes the text to nothing, and on a dock dragged past 900pt an unbounded
    /// one pushes the margins past any sensible gutter. Between them the ratio governs.
    static let minMargin: CGFloat = 24
    static let maxMargin: CGFloat = 112

    /// The margin on each side inside a chat box of `box` points.
    static func margin(forBox box: CGFloat) -> CGFloat {
        min(max(box * marginFraction, minMargin), maxMargin)
    }

    /// The reading column's width inside a chat box of `box` points. Rounded, because a
    /// fractional width makes the text's leading edge land off-pixel and the glyphs blur.
    static func textWidth(forBox box: CGFloat) -> CGFloat {
        max(0, (box - margin(forBox: box) * 2).rounded())
    }
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
