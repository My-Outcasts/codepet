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
    /// The signed-in account's display name — the greeting's second source for who
    /// the founder is when the brief carries no name. See `FounderName`.
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var lang
    /// Which shell is hosting this — the dock, or the two-mode pane. Decides the
    /// header row, where the composer sits, and whether the mode pill exists.
    @Environment(\.chatSurface) private var surface
    @FocusState private var inputFocused: Bool
    /// Toggles the "History" thread switcher over the message list. Session-only
    /// UI state — the History stub (see the header) now activates this.
    @State private var showHistory = false
    /// Bumped from the coordinator's publishers so a nested-object change reliably
    /// re-renders the run card live (see the onReceive bridges below).
    @State private var codingRunTick = 0
    /// Bumped by every autoscroll trigger in `messageList` — new messages, the fan-out row,
    /// a growing Virtual Company room, the typing indicator, and the coding run's own start
    /// and step stream — so `CopilotBubble` can reset a stranded `hovering` regardless of
    /// which of the six caused the scroll. Not wired to the individual signals
    /// (`chatMessages.count`, `activeAgentRuns.count`, `vcRunCardCount`, `isCompanionTyping`,
    /// `CodingRunCoordinator.$run`/`.$steps`) because those six share nothing except "this
    /// scrolled the list" — `activeAgentRuns`, the VC room, and the coding run all move the
    /// scroll position without touching `chatMessages.count` (the fan-out's own append —
    /// `CompanyStore.swift:1855`; the room mutates `vcRun` by id; the coding run renders
    /// inline next to its anchor message and its step stream fires on every step), which is
    /// exactly the gap that let a hovered older reply get scrolled out from under the pointer
    /// with its action row stuck lit (`.onHover(false)` never firing —
    /// `CodepetTokens.swift:211-214`).
    @State private var scrollGeneration = 0
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
            let column = ChatColumn.textWidth(forBox: geo.size.width, surface: surface)
            VStack(spacing: 0) {
                // Two-mode has no dock to collapse and no history icon: the rail's
                // Recent list IS the thread switcher, so the row would be two
                // controls that duplicate or lie about what the shell can do.
                if surface.showsDockChrome {
                    header(column: column)
                }
                if showHistory {
                    ThreadListView(showHistory: $showHistory)
                } else if companyStore.chatMessages.isEmpty && companyStore.activeAgentRuns.isEmpty {
                    ChatEmptyState(
                        state: ChatLandingState(company: companyStore.company, now: Date(),
                                                language: lang, accountName: appState.displayName),
                        onOpenRoadmap: { companyStore.select(.roadmap) },
                        onStarter: { starter in
                            companyStore.chatDraft = starter
                            mode = .ask
                            send()
                        },
                        beaconTasks: companyStore.company.tasks,
                        onBeacon: runBeacon,
                        selectedDept: $selectedDept,
                        onDepartment: armDepartment
                    ) { if surface == .dock { composer } }
                    // Two-mode docks the composer at the bottom of the pane instead
                    // of stacking it inside the hero — that is what keeps the beacon's
                    // buttons on screen when the greeting or the card grows.
                    if surface == .twoMode {
                        // No chips here: `DepartmentRoster` is directly above and
                        // offers the same control for the same departments, with
                        // all eight and their pets rather than three names.
                        composerDock(column: column, showsDeptChips: false)
                    }
                } else {
                    messageList(column: column)
                    // No rule above the composer — it carries its own bordered container,
                    // so the seam was redundant chrome. Matches the header's no-divider
                    // direction. It shares the transcript's reading column, so the composer
                    // and the words above it start and end on the same two vertical lines.
                    if surface == .twoMode {
                        composerDock(column: column)
                    } else {
                        composer.readingColumn(column).padding(.bottom, 12)
                    }
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
    private var composer: some View { composer(showsDeptChips: true) }

    private func composer(showsDeptChips: Bool) -> some View {
        ChatComposer(
            draft: $companyStore.chatDraft,
            mode: $mode,
            canSend: canSend,
            focus: $inputFocused,
            // "Codepet", not the pet's name: the founder is talking to the product, and
            // the pet's own name belongs to the moment it answers (`headerName`).
            // Two-mode says "your company" instead: the rail already says Codepet, and
            // Ask is defined as the door that talks to the company.
            placeholder: placeholderText,
            quickActions: quickActions,
            accent: companionColor,
            accent2: CodepetTheme.accentPink,
            isBusy: isChatBusy,
            showsDeptChips: showsDeptChips,
            selectedDept: $selectedDept,
            onSend: send,
            onQuickAction: handleQuickAction
        )
    }

    /// The pane's composer and the line under it.
    ///
    /// The composer was sitting ~6pt off the window's bottom edge, which is most of why
    /// it read as cramped — Claude leaves ~22pt and then a line of text below that, and
    /// Codex leaves ~10. The disclaimer is not filler: this product hands the founder
    /// drafts they file and act on, and Claude carries the same sentence under the same
    /// control. It doubles as the air the composer was missing.
    private func composerDock(column: CGFloat, showsDeptChips: Bool = true) -> some View {
        VStack(spacing: 8) {
            composer(showsDeptChips: showsDeptChips).readingColumn(column)
            Text(lang == .vi
                 ? "Codepet là AI và có thể mắc lỗi. Hãy kiểm tra lại nội dung quan trọng."
                 : "Codepet is AI and can make mistakes. Please double-check its work.")
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundColor(CodepetTokens.faint)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 14)
    }

    private var placeholderText: String {
        switch surface {
        case .dock:
            return lang == .vi ? "Hỏi Codepet bất cứ điều gì về công ty…"
                               : "Ask Codepet anything about your company…"
        case .twoMode:
            return lang == .vi ? "Hỏi công ty của bạn bất cứ điều gì…"
                               : "Ask your company anything…"
        }
    }

    /// A roster tap arms the department and puts the caret in the composer. It does
    /// NOT send: the founder came to ask their own question, and a tap that spends a
    /// chat turn on "where would you start?" bills them for a question they did not
    /// write. Toggles, so tapping the armed pet disarms it — same as its chip.
    private func armDepartment(_ dep: Department) {
        selectedDept = (selectedDept?.key == dep.key) ? nil : dep
        inputFocused = true
    }

    /// The hero card's buttons. Each is wired to something that already exists —
    /// no button here promises a surface the app does not have.
    ///
    /// `walkthrough` sends the ask rather than opening a dedicated flow: the
    /// native app has no walkthrough surface (the web app's `#125` never ported),
    /// and a chat turn that explains the step and captures what was learned is the
    /// honest version of it. `review` navigates to the roadmap, where the draft
    /// actually is; generating a second draft would spend credits to show the
    /// founder something they already have.
    private func runBeacon(_ primary: BeaconOffer.Primary, _ task: RoadmapTask) {
        showHistory = false
        switch primary {
        case .run:
            Task { await companyStore.runTask(task, language: lang) }
        case .walkthrough:
            companyStore.chatDraft = lang == .vi
                ? "Hướng dẫn tôi làm: \(task.title)"
                : "Walk me through: \(task.title)"
            mode = .ask
            send()
        case .review:
            companyStore.select(.roadmap)
        }
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
                        CopilotBubble(message: m,
                                      isLast: idx == companyStore.chatMessages.count - 1,
                                      scrollGeneration: scrollGeneration)
                            .padding(.top, ChatRhythm.extraGap(after: previousRole, before: m.role))
                            .id(m.id)
                        if companyStore.codingRun.run != nil,
                           companyStore.codingRunAnchorId == m.id {
                            CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")
                        }
                        // The cloud twin, anchored the same way. `m.text` is the
                        // ask: it belongs to this chat turn, not to the store,
                        // which holds one run's live state and is replaced by
                        // the next run.
                        if let eng = companyStore.engineeringRunStore,
                           companyStore.engineeringRunAnchorId == m.id {
                            // Permission asks render INSIDE the bar — see
                            // `EngineeringResultBar.approvalRows`. They were
                            // siblings here until Aug 13 and the two cards did
                            // not line up.
                            EngineeringResultBar(
                                store: eng,
                                onReview: { companyStore.openEngineeringReview() },
                                onConnectRepo: { companyStore.promptForEngineeringRepo() },
                                onRunLocally: companyStore.localBuildAvailable
                                    ? { companyStore.switchBuildToLocal(ask: m.text) }
                                    : nil
                            )
                            .id("engineering-run")
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
                scrollGeneration &+= 1
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
            .onChange(of: companyStore.isCompanionTyping) { _, typing in
                scrollGeneration &+= 1
                if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
            .onChange(of: companyStore.activeAgentRuns.count) { _, count in
                scrollGeneration &+= 1
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
                scrollGeneration &+= 1
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
                        scrollGeneration &+= 1
                        withAnimation { proxy.scrollTo("coding-run", anchor: .bottom) }
                    }
                }
            }
            .onReceive(companyStore.codingRun.$steps) { _ in
                DispatchQueue.main.async {
                    codingRunTick &+= 1
                    if companyStore.codingRun.run != nil {
                        // `$steps` fires on every step of a coding run, and `CodeRunCardView`
                        // renders inline right after its anchor message, so the transcript
                        // really does reflow here — this bridge used to scroll without
                        // bumping `scrollGeneration`, which left a hovered older reply's
                        // action row stuck lit for the rest of the session (finding 3, the
                        // 2026-08-11 whole-branch review).
                        scrollGeneration &+= 1
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
        // One message, one handoff. The chip used to survive the send — and `newChat()` and a
        // thread switch too, since it lives here rather than in the store — so a founder who
        // asked Marketing one question had Nova answering every later question in the session,
        // including the ones about pricing. Nothing on screen said why: the chip sits under the
        // composer, out of the eyeline of someone reading replies. A selection consumed by the
        // message it was made for can't go stale, so the sticky-focus problem stops existing
        // rather than needing to be signposted. Cleared for `.build` too — that send doesn't read
        // the department, and leaving one armed chip behind is the exact state this removes.
        let dept = selectedDept
        selectedDept = nil
        switch mode {
        case .ask, .plan:
            // `founderAsk` is the unshaped text: byte should see the mode's framing
            // ("Help me plan this — …"), the Virtual Company's router should not, since
            // it decides `request_type` and rewrites the question into `real_question`.
            Task {
                await companyStore.sendChat(mode.shape(text, language: lang), language: lang,
                                            department: dept, founderAsk: text,
                                            convenesRoom: mode.convenesRoom)
            }
        case .build:
            // One code mode. WHERE it runs is the run's business, not the
            // founder's — `startBuild` decides and says so on the card.
            companyStore.startBuild(ask: text)
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
    /// True for the newest message in the transcript. Pins the action row (so the reply
    /// being read always shows its affordances) and gates retry, whose store method deletes
    /// every turn after the ask.
    let isLast: Bool
    /// Bumped by `messageList` on every one of its six autoscroll triggers. Watched only to
    /// reset a stranded `hovering` — see the comment on `body`'s `.onChange` below.
    let scrollGeneration: Int
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    /// The draft card's chrome is scheme-dependent (`cardChrome`), so the bubble needs it.
    @Environment(\.colorScheme) private var scheme
    /// Decides how loud the founder's own turn is — see `textBubble`.
    @Environment(\.chatSurface) private var surface
    /// For the identity fields on a thumb — the same ones `FeatureFeedbackManager` sends.
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var appState: AppState
    @State private var showDetail = false
    /// Expansion of the finished run's "What <Name> did" log on a draft card.
    @State private var showSteps = false
    /// Expansion of the fast answer once a room has superseded it — see `firstTakeRow`.
    @State private var showFirstTake = false
    /// Hover state for the per-message action row, and the transient "Copied" acknowledgement.
    @State private var hovering = false
    /// Two separate flags (rather than one "which copy" enum) because `copy(_:setting:)`
    /// clears both before setting either — see that helper's comment for why they must be
    /// mutually exclusive rather than independent, which is how this pair started.
    @State private var copied = false
    @State private var copiedMarkdown = false
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

    /// The action row belongs to the MESSAGE, not to one branch of this chain. It used to be
    /// called from inside `textBubble`, so a draft, exec log, room or proposal reply — the
    /// replies most worth copying and rating — had no actions at all. Wrapping `content` is
    /// what makes the row universal without touching a single payload branch.
    ///
    /// `.onHover` sits here rather than on the row (where it used to, at `messageActions`),
    /// because the row is held at `opacity(0)`: the target was a blank 22x20 strip below the
    /// prose, which is why the founder read the actions as missing entirely.
    var body: some View {
        if showsActions {
            VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
                content
                messageActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering = $0 }
            // `.onHover(false)` does not fire when a view disappears from under the pointer
            // (`CodepetTokens.swift:211-214`), and `messageList` autoscrolls on SIX separate
            // triggers, only one of which (`chatMessages.count` itself) is a change to the
            // message array — the other five (the typing indicator, the fan-out row via
            // `activeAgentRuns.count`, a growing Virtual Company room via `vcRunCardCount`,
            // and the coding run's own start and step stream) move the scroll position while
            // leaving `chatMessages` untouched. So: the founder reads an older reply with the
            // pointer resting on it, any of the six fires, the transcript scrolls that reply
            // out from under the cursor with `hovering` stuck true — its row stays lit next to
            // the newly pinned one until the pointer happens to re-enter and leave it.
            // `scrollGeneration` is bumped by all six in `messageList`, with no signal in
            // common besides "this scrolled the list" — watching it here (rather than each of
            // the six individually) clears `hovering` before it can be seen, no matter which
            // one fired. The coding run's step bridge used to scroll WITHOUT bumping this,
            // even though `CodeRunCardView` renders inline right after its anchor message and
            // every step really does reflow the transcript (finding 3, 2026-08-11 review).
            .onChange(of: scrollGeneration) { _, _ in hovering = false }
        } else {
            content
        }
    }

    /// Whether this message gets an action row at all: not the founder's own words (nothing
    /// to copy/retry/thumb on those), not still being produced (a reply mid-stream has
    /// nothing to act on yet), and not empty once rendered. `hasActionableContent` also
    /// catches the streaming shell: a message with no text yet renders `EmptyView()` from
    /// `textBubble` (see its own comment below), and without this guard the pinned row on
    /// the newest message would draw floating with nothing above it.
    private var showsActions: Bool {
        !isMe && !message.producing && hasActionableContent
    }

    /// A message shell can reach `textBubble` with no text yet — while the companion is
    /// still typing (see its own comment there). `MessageTranscript.plain` is the emptiness
    /// oracle: if there is nothing to copy, there is nothing to rate or retry either, and a
    /// standalone chip (`navChip` / `setupSuggestion` / `noted`) has nothing worth acting on
    /// regardless — this also suppresses the row on those.
    private var hasActionableContent: Bool {
        !MessageTranscript.plain(message, lang: lang).isEmpty
    }

    @ViewBuilder private var content: some View {
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

    /// Per-message actions, revealed on hover and pinned on the newest reply — the row both
    /// references put under an answer. Copy, copy as Markdown, try again, a thumb either way,
    /// and the age of the turn.
    ///
    /// Hover-reveal because an answer is for reading; the affordances belong to the moment you
    /// reach for them. Pinned on the last reply because hover alone taught nobody the row was
    /// there — the target was this row itself, held at `opacity(0)`.
    @ViewBuilder private var messageActions: some View {
        let retryEnabled = MessageActionRules.canRetry(isLast: isLast,
                                                       isTyping: companyStore.isCompanionTyping,
                                                       isStreaming: companyStore.isStreaming,
                                                       isFanningOut: companyStore.isFanningOut,
                                                       founderAsk: message.founderAsk)
        // For the disabled tooltip only — which of `canRetry`'s conditions is the reason.
        // A blank/nil `founderAsk` is the COMMONEST disabled case now that retry pins to the
        // newest message: the first-run greeting, a run proposal, a room card, a draft card
        // are all `isLast` with no ask before them, so "only applies to the newest reply" is
        // something the founder can see is false on the very message she's looking at.
        let hasFounderAsk = !(message.founderAsk ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 2) {
            // The icon ITSELF becomes the acknowledgement — see `actionIcon`'s `tint`.
            actionIcon(copied ? "checkmark" : "doc.on.doc",
                       help: lang == .vi ? "Sao chép" : "Copy",
                       tint: copied ? CodepetTheme.accentTeal : nil) {
                copy(MessageTranscript.plain(message, lang: lang), setting: $copied)
            }
            // Distinct from Copy: the founder's paste target for a draft or a room is
            // Notion or a PR, and plain text loses the headings and the per-seat structure.
            actionIcon(copiedMarkdown ? "checkmark" : "square.and.arrow.up",
                       help: lang == .vi ? "Sao chép dạng Markdown" : "Copy as Markdown",
                       tint: copiedMarkdown ? CodepetTheme.accentTeal : nil) {
                copy(MessageTranscript.markdown(message, speaker: headerName, lang: lang), setting: $copiedMarkdown)
            }
            actionIcon("arrow.clockwise",
                       help: retryEnabled
                           ? (lang == .vi ? "Hỏi lại" : "Try again")
                           : !hasFounderAsk
                               // No founder ask precedes this reply at all — true regardless of
                               // `isLast`, and the common case (see the `let` above).
                               ? (lang == .vi ? "Chỉ áp dụng cho câu trả lời cho điều bạn đã hỏi"
                                              : "Try again only applies to a reply to something you asked")
                               : !isLast
                                   // Has an ask, just isn't the newest reply — an older one
                                   // looked equally live (finding 4) with no way to tell it was
                                   // inert until tapped.
                                   ? (lang == .vi ? "Chỉ hỏi lại được câu trả lời mới nhất"
                                                  : "Try again only applies to the newest reply")
                                   // Newest, has an ask, just still busy (typing/streaming/
                                   // fanning out) — neither of the above is true, so neither
                                   // wording is.
                                   : (lang == .vi ? "Đợi xong rồi hỏi lại"
                                                  : "Wait for this to finish before trying again"),
                       isEnabled: retryEnabled) {
                Task { await companyStore.retryReply(messageId: message.id, language: lang) }
            }
            .disabled(!retryEnabled)
            thumb(.up, icon: "hand.thumbsup", help: lang == .vi ? "Hữu ích" : "Good reply")
            thumb(.down, icon: "hand.thumbsdown", help: lang == .vi ? "Chưa tốt" : "Bad reply")
            Text(Self.age(of: message.createdAt, lang: lang))
                .font(.pixelSystem(size: 9))
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.leading, 4)
        }
        // Pinned on the newest reply so the affordance is discoverable at all — hover alone
        // taught nobody it existed. Still `opacity` rather than a conditional, so the row's
        // height never changes under the cursor.
        .opacity(hovering || isLast ? 1 : 0)
        // `.opacity(0)` does NOT stop hit-testing — the row stays clickable while invisible.
        // `scrollGeneration`'s `.onChange` (above) forces `hovering` false WHILE the pointer is
        // still resting on the row (any of the six scroll bumps, including a coding run's
        // per-step bridge, can fire mid-read), so without this the founder can click exactly
        // where she believes there is nothing. Copy/Copy as Markdown landing on the wrong
        // reply is a shrug; a thumb is not — it is a PERMANENT `feedback` write, and
        // `firestore.rules:42` denies both read and update, so a vote recorded against the
        // wrong reply this way can never be corrected.
        .allowsHitTesting(hovering || isLast)
        // Two `.animation` modifiers, not one value: `isLast` flips (1 → 0) the instant a new
        // reply lands and becomes the pinned one, on a row `hovering` never touched, so without
        // observing `isLast` too that un-pin snapped in a single frame while everything else on
        // screen eased.
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.12), value: isLast)
    }

    /// `isEnabled` is separate from the caller's `.disabled(...)`: `.disabled` only changes
    /// behaviour (SwiftUI dims a `Button`'s default styling, but this icon paints its own
    /// `foregroundColor`, which overrides that and always looked the same either way). Without
    /// this parameter a disabled Try again on an older reply looked exactly as live as an
    /// enabled one — the founder tapped it and nothing happened, with no visual reason why.
    ///
    /// `tint` overrides the resting ink, which is how a copy acknowledges itself: the icon
    /// swaps to a teal `checkmark` for 1.4s instead of floating a "Copied" label beside it.
    /// The label was an `.overlay(alignment: .leading)` offset by exactly the icon's own 22pt
    /// width, so it began at the icon's right edge and ran straight over the NEXT control —
    /// on a five-icon row that meant it covered Copy as Markdown, and it was clipped to
    /// "Cop.." besides, because an overlay does not expand its parent's bounds. Founder-
    /// verified on screen, Aug 11. Swapping the icon is also the pattern this repo already
    /// uses for a copy confirm (`MessageDraftCard.swift:144`).
    private func actionIcon(_ system: String, help: String, isEnabled: Bool = true,
                            tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tint ?? CodepetTheme.mutedText.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Puts `string` on the pasteboard and shows `flag`'s acknowledgement for 1.4s.
    ///
    /// Clears BOTH flags before setting the one requested, so only one checkmark is ever lit:
    /// `copied` and `copiedMarkdown` were fully independent, each on its own timer, and Copy
    /// then Copy as Markdown inside 1.4s showed two acknowledgements at once.
    private func copy(_ string: String, setting flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copied = false
        copiedMarkdown = false
        flag.wrappedValue = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            flag.wrappedValue = false
        }
    }


    /// A thumb fills once given, and the other stays live so a misclick is correctable.
    ///
    /// The correction writes a SECOND `feedback` document — `firestore.rules:42` denies
    /// `update` — which the reader resolves by latest `timestamp`. Voting the same way twice
    /// is a no-op rather than a duplicate write.
    ///
    /// Gated on `isCompanionTyping`/`isStreaming` — the same busy state as retry, minus
    /// `isFanningOut` — AND on `isLast`, because those two flags are global store state: without
    /// `isLast` a thumb on a complete reply from five turns ago went dead the moment any new
    /// turn started streaming, disabling the whole transcript's history over one in-flight
    /// reply. The only half-written reply is the pinned/newest one, so only it needs to gate —
    /// same scoping as `canRetry` above. A fan-out does not make the reply already on screen
    /// incomplete, so voting on it stays valid even while `isLast` — that is a different
    /// question from what `retryReply` will accept, which is why `canRetry` still checks
    /// `isFanningOut` too and this does not.
    ///
    /// Also gated on `ownRoomStillRunning`, independently of the two global flags above:
    /// a Virtual Company room runs inside `startVirtualCompanyRun`'s own `Task {}`, which
    /// INHERITS that call's `@MainActor` isolation (`CompanyStore.swift:1016-1021`) rather than
    /// running detached — only `vcRunner`'s own I/O is `Task.detached`. Both `isCompanionTyping`
    /// and `isStreaming` still clear while the room keeps filling for 30–60s (the composer is
    /// deliberately free during that window). The
    /// room lands as its OWN message (inserted under its question, not appended), carrying
    /// a non-blank handoff line, so its row is pinned and votable from the very first
    /// routing card — before the verdict a thumbs-down there rates a room that hasn't
    /// spoken yet. Read straight off `message.vcRun.phase`, so a room convening elsewhere
    /// in the transcript never blocks voting on an unrelated reply.
    @ViewBuilder private func thumb(_ vote: MessageVote, icon: String, help: String) -> some View {
        let chosen = message.vote == vote
        // Computed ONCE and reused for the dim, the tooltip, AND `.disabled` below, rather than
        // repeating the expression three times. Same drift `actionIcon`'s own note warns about
        // (`.disabled` alone does not dim a `foregroundColor`-painted icon), but on this row
        // specifically: `ownRoomStillRunning` opens the app's LONGEST disabled window (a whole
        // room convening, 30–60s), long enough that a founder who sees no dimming and no
        // explanation clicks it more than once believing nothing happened.
        let disabled = (isLast && (companyStore.isCompanionTyping || companyStore.isStreaming)) || ownRoomStillRunning
        Button {
            guard !chosen else { return }
            companyStore.recordVote(messageId: message.id, vote: vote)
            MessageFeedbackService.submit(vote: vote, message: message,
                                          threadId: companyStore.activeThreadId ?? "",
                                          authManager: authManager, appState: appState)
        } label: {
            Image(systemName: chosen ? "\(icon).fill" : icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(chosen ? CodepetTheme.accentTeal
                                         : CodepetTheme.mutedText.opacity(disabled ? 0.35 : 1))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(disabled ? waitHelp(forRoom: ownRoomStillRunning) : help)
        .disabled(disabled)
    }

    /// The tooltip a disabled thumb shows instead of "Good reply"/"Bad reply" — that wording
    /// promised an action that a click, right then, does nothing. `forRoom` distinguishes the
    /// 30–60s room window (`ownRoomStillRunning`) from the few-second one (this reply itself
    /// still typing/streaming), because "the room" is only true of the former.
    private func waitHelp(forRoom: Bool) -> String {
        if forRoom {
            return lang == .vi ? "Đợi phòng họp này hoàn tất trước khi đánh giá"
                               : "Wait for the room to finish before rating"
        }
        return lang == .vi ? "Đợi câu trả lời này hoàn tất trước khi đánh giá"
                           : "Wait for this reply to finish before rating"
    }

    /// True while THIS message's own Virtual Company room is still convening — see
    /// `thumb`'s doc for why the two global chat flags don't cover this window. `vcRun` is
    /// only non-nil on the room's own message (`publishRunProgress` inserts it separately
    /// from byte's fast answer), so this never reads another message's run.
    private var ownRoomStillRunning: Bool {
        guard let phase = message.vcRun?.phase else { return false }
        return phase != .finished && phase != .failed
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
        if !message.drafts.isEmpty { draftedMessages }
        if let nav = message.navChip { navChipButton(nav) }
        if let setup = message.setupSuggestion {
            HStack {
                CodepetCard { setupInline(setup).padding(12) }
                Spacer(minLength: 24)
            }
        }
        if let facts = message.noted, !facts.isEmpty { notedInline(facts) }
    }

    /// The messages the companion wrote, each in the same card the Library uses for an
    /// `.email`/`.dms` deliverable.
    ///
    /// The founder's Aug 10 report was that a message written in chat was indistinguishable
    /// from ordinary prose. Sharing `MessageDraftViewer` with the deliverable viewers is the
    /// point: wherever a message appears, it looks like a message. A `to` on an email — whose
    /// heading is already its subject — is carried as its own small line so nothing is lost.
    @ViewBuilder private var draftedMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(message.drafts.enumerated()), id: \.offset) { _, draft in
                VStack(alignment: .leading, spacing: 6) {
                    MessageDraftViewer(eyebrow: draft.eyebrow(lang),
                                       heading: draft.heading,
                                       text: draft.body)
                    if draft.channel == "email",
                       let to = draft.to?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !to.isEmpty {
                        Text((lang == .vi ? "Gửi tới: " : "To: ") + to)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(CodepetTheme.inter(ChatRhythm.prose(surface)))
                    .lineSpacing(ChatRhythm.proseLeading(surface))
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
            // The founder's own words, quietly.
            //
            // In the dock this is a solid accent bubble, and at 380pt that earns its
            // volume: the column is too narrow for an attribution row on every turn, so
            // colour is what separates the two speakers.
            //
            // The pane does not have that problem — the reply carries an avatar and a
            // name row — and there the accent bubble makes the loudest object on screen
            // the one sentence the founder already knows, on every single turn. Claude
            // gives the question a quiet grey and spends no accent in the transcript at
            // all. `well` is this app's own version of that: the neutral it already uses
            // for a recessed track.
            let quiet = surface == .twoMode
            let pad: CGFloat = 14
            HStack {
                Spacer(minLength: 24)
                Text(message.text)
                    .font(CodepetTheme.inter(ChatRhythm.prose(surface)))
                    .lineSpacing(ChatRhythm.proseLeading(surface))
                    .foregroundColor(quiet ? CodepetTheme.bodyText : .white)
                    .padding(.horizontal, pad).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(quiet ? CodepetTokens.well : CodepetTheme.accentPurple))
                    .fixedSize(horizontal: false, vertical: true)
                    // The bubble's TEXT lands on the column's right edge, not its
                    // border — so the founder's words and the reply's words end on
                    // the same vertical line, and only the bubble's padding
                    // overhangs it. This is what Claude does, and without it the
                    // question sits ~7pt inside the answer for no reason a reader
                    // could name.
                    .padding(.trailing, quiet ? -pad : 0)
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
                    prose(message.text)
                    inlineActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The reply's prose, one block per paragraph.
    ///
    /// Split on blank lines rather than handed to a single `Text`. A `Text` renders
    /// `\n\n` as a real empty line — measured at 1.94× the line height against a
    /// convention of 0.5–0.75× — which is why the transcript read airier and longer
    /// than its word count deserved. Spacing the blocks lands the gap near 0.6×.
    ///
    /// Blanks are still tinted per paragraph: when the companion writes
    /// conversationally rather than producing a deliverable, this prose IS the draft,
    /// and a `[name]` buried mid-sentence is the one thing in it the founder has to
    /// act on before sending (Aug 10). Tinting after the split keeps that, because
    /// a placeholder never spans a paragraph break.
    @ViewBuilder private func prose(_ text: String) -> some View {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: ChatRhythm.paragraphGap) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(MessagePlaceholders.tinted(paragraph,
                                                tint: MessageDraftStyle.blankTint,
                                                ink: MessageDraftStyle.blankInk))
                    .font(CodepetTheme.inter(ChatRhythm.prose(surface)))
                    .lineSpacing(ChatRhythm.proseLeading(surface))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The cap for the two-mode PANE, which is a different problem from the dock.
    ///
    /// 640 was chosen when a dragged-wide dock was the only way the box got large; in
    /// the pane the box starts large, so the cap is what decides the column at every
    /// size above ~700pt rather than an edge case. At a ~995pt window it barely binds
    /// (the pane is ~787 and the margins land near 73), which is why this reads fine
    /// today — but maximised on an external display the same constant leaves the app's
    /// widest surface carrying its narrowest column.
    ///
    /// `DeliverableStyle.measure` — the app's own reading measure, 620.
    ///
    /// This was 760, chosen while the prose was still 13.5pt, with a comment
    /// admitting 760 was "already ~110 characters". Measured on screen it was ~115,
    /// against a convention of 45–75 and a ceiling near 90. Widening the column was
    /// treating the symptom: the type was a dock size in a pane-sized column, and
    /// the fix is the pair, not either half. See `ChatRhythm.prose`.
    static var paneMeasureCap: CGFloat { DeliverableStyle.measure }

    /// The reading column's width inside a chat box of `box` points. Rounded, because a
    /// fractional width makes the text's leading edge land off-pixel and the glyphs blur.
    static func textWidth(forBox box: CGFloat, surface: ChatSurface = .dock) -> CGFloat {
        let cap = surface == .dock ? measureCap : paneMeasureCap
        return max(0, min(box - inset * 2, cap).rounded())
    }

    /// The margin each side — whatever the column leaves, split in two. Derived rather than
    /// stated so it can never disagree with the column.
    static func margin(forBox box: CGFloat, surface: ChatSurface = .dock) -> CGFloat {
        max(0, (box - textWidth(forBox: box, surface: surface)) / 2)
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

    /// The transcript's reading standard, per surface.
    ///
    /// The dock keeps 13.5/6 — correct at 380pt, where the column is too narrow for
    /// anything larger. The pane adopts **`DeliverableStyle`**, which is this app's
    /// own answer to "how should a document be set": body 14 at a 620pt measure,
    /// with 7 of extra leading.
    ///
    /// Measured, which is why it changed: at 13.5pt across the pane's 739pt column
    /// the transcript ran ~115 characters a line. The convention is 45–75 and the
    /// hard ceiling ~90; Claude's chat sits at ~88. `DeliverableStyle`'s pair —
    /// 620 ÷ (14 × 0.5) — is 88 exactly. The app had already solved this for its
    /// deliverables and the transcript was the one surface not using it, which is
    /// how the *card* ended up set LARGER (14) in a NARROWER measure (620) than the
    /// prose introducing it (13.5 at 739). Adopting the standard closes that
    /// backwards gap instead of inventing a third scale.
    static func prose(_ surface: ChatSurface) -> CGFloat {
        surface == .dock ? 13.5 : DeliverableStyle.body
    }

    static func proseLeading(_ surface: ChatSurface) -> CGFloat {
        surface == .dock ? lineSpacing : DeliverableStyle.leading
    }

    /// Paragraph separation inside one reply.
    ///
    /// The replies arrive with `\n\n` between paragraphs, and a single `Text`
    /// renders that as a genuinely EMPTY LINE — measured at 1.94× the line height,
    /// where the typographic convention is 0.5–0.75× and Claude sits at ~1.48×
    /// including its own leading. So the paragraphs are split and spaced instead:
    /// the gap becomes this plus the natural leading, which lands near 0.6×.
    static let paragraphGap: CGFloat = 8
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
