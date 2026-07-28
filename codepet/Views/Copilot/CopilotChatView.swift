// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI
import AppKit

/// The Copilot column: a company-grounded chat with the founder's companion.
struct CopilotChatView: View {
    /// Whether the shell's sidebar is collapsed — the header insets to clear the
    /// floating collapse toggle only then; flush-left when the sidebar is open.
    var sidebarCollapsed: Bool = false

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var mode: ChatMode = .ask
    @State private var selectedDept: Department?
    @FocusState private var inputFocused: Bool

    /// Max width of the conversation column + composer — matches Claude Code's
    /// comfortable centered reading width (both stay in sync via this one value).
    private let chatColumnWidth: CGFloat = 760
    /// Minimum side gutter kept at ALL window sizes so the column shrinks to fit a
    /// narrow window (never edge-to-edge) and the message list + composer share the
    /// exact same left/right edges — the Claude-style responsive behavior.
    private let chatGutter: CGFloat = 24

    // Thread header (name dropdown + Share).
    @State private var renamingThread = false
    @State private var threadRenameDraft = ""
    @State private var shareCopied = false

    private var activeThreadTitle: String {
        companyStore.threads.first { $0.id == companyStore.activeThreadId }?.title
            ?? (lang == .vi ? "Đoạn chat mới" : "New chat")
    }
    /// Recent threads for the header switcher, newest-first (active one excluded — it's the label).
    private var recentThreads: [ChatThread] {
        sortThreadsByRecent(companyStore.threads)
            .filter { $0.id != companyStore.activeThreadId }
            .prefix(8).map { $0 }
    }
    private var isChatBusy: Bool { companyStore.isCompanionTyping || companyStore.isStreaming }

    /// A slim top bar: the active thread's name as a dropdown switcher (New chat +
    /// recent threads + Rename), plus Share (copies the transcript). Leading inset
    /// clears the shell's sidebar-collapse toggle when the sidebar is hidden.
    private var chatHeader: some View {
        HStack(spacing: 8) {
            threadMenu
            Spacer(minLength: 8)
            shareButton
        }
        .padding(.leading, sidebarCollapsed ? 44 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .alert(lang == .vi ? "Đổi tên đoạn chat" : "Rename chat", isPresented: $renamingThread) {
            TextField(lang == .vi ? "Tên" : "Name", text: $threadRenameDraft)
            Button(lang == .vi ? "Lưu" : "Save") {
                if let id = companyStore.activeThreadId { companyStore.renameThread(id, title: threadRenameDraft) }
            }
            Button(lang == .vi ? "Hủy" : "Cancel", role: .cancel) {}
        }
    }

    private var threadMenu: some View {
        Menu {
            Button { companyStore.newChat() } label: {
                Label(lang == .vi ? "Đoạn chat mới" : "New chat", systemImage: "square.and.pencil")
            }.disabled(isChatBusy)
            if !recentThreads.isEmpty {
                Section(lang == .vi ? "Gần đây" : "Recent") {
                    ForEach(recentThreads) { t in
                        Button {
                            companyStore.switchThread(t.id)
                        } label: {
                            Text(t.title ?? (lang == .vi ? "Đoạn chat mới" : "New chat"))
                        }.disabled(isChatBusy)
                    }
                }
            }
            Divider()
            Button {
                threadRenameDraft = activeThreadTitle
                renamingThread = true
            } label: {
                Label(lang == .vi ? "Đổi tên đoạn này" : "Rename this chat", systemImage: "pencil")
            }.disabled(companyStore.activeThreadId == nil)
        } label: {
            HStack(spacing: 5) {
                Text(activeThreadTitle)
                    .font(CodepetTheme.inter(14, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
    }

    private var shareButton: some View {
        Button { copyTranscript() } label: {
            HStack(spacing: 5) {
                Image(systemName: shareCopied ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                Text(shareCopied ? (lang == .vi ? "Đã sao chép" : "Copied")
                                 : (lang == .vi ? "Chia sẻ" : "Share"))
                    .font(CodepetTheme.inter(12, weight: .medium))
            }
            .foregroundColor(shareCopied ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
        }
        .buttonStyle(.plain)
    }

    /// Copy the active thread's transcript (plain text) to the clipboard. No
    /// share-link backend yet — an honest local copy the founder can paste anywhere.
    private func copyTranscript() {
        let text = companyStore.chatMessages.compactMap { m -> String? in
            let body = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let who = m.role == .me ? (lang == .vi ? "Bạn" : "You") : companionName
            return "\(who): \(body)"
        }.joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        shareCopied = true
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); shareCopied = false }
    }

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }
    private var companionAccent2: Color {
        PetCharacter.all[companyStore.company.companionId]?.secondColor ?? CodepetTheme.accentPink
    }
    private var canSend: Bool {
        !companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !companyStore.isCompanionTyping && !companyStore.isStreaming
    }

    var body: some View {
        ZStack {
            ChatBackdrop()
            VStack(spacing: 0) {
                if companyStore.chatMessages.isEmpty {
                    ChatEmptyState(
                        state: ChatLandingState(company: companyStore.company, now: Date(), language: lang),
                        onOpenRoadmap: { companyStore.selectedDeptKey = nil; companyStore.select(.roadmap) },
                        onStarter: { companyStore.chatDraft = $0; inputFocused = true },
                        columnWidth: chatColumnWidth
                    ) {
                        composerView
                    }
                } else {
                    chatHeader
                    messageList
                    composerView
                        .frame(maxWidth: chatColumnWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, chatGutter)
                        .padding(.vertical, 10)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(companyStore.chatMessages) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                    if companyStore.isCompanionTyping { ChatThinkingRow(taskTitle: nil).id("typing") }
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: chatColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, chatGutter)
            }
            .onChange(of: companyStore.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
            .onChange(of: companyStore.isCompanionTyping) { _, typing in
                if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    /// The one composer instance, reused in the empty hero and docked in an
    /// active conversation. State (draft/mode/focus) stays here so both
    /// placements share the same value.
    private var composerView: some View {
        ChatComposer(
            draft: $companyStore.chatDraft,
            mode: $mode,
            canSend: canSend,
            focus: $inputFocused,
            placeholder: placeholder,
            quickActions: quickActions,
            accent: companionAccent,
            accent2: companionAccent2,
            isBusy: companyStore.isCompanionTyping || companyStore.isStreaming,
            selectedDept: $selectedDept,
            onSend: send,
            onQuickAction: runQuickAction
        )
    }

    private var placeholder: String {
        lang == .vi
            ? "Hỏi \(companionName) bất cứ điều gì về công ty…"
            : "Ask \(companionName) anything about your company…"
    }

    /// Capability quick-actions — the titles are complete intents, so they are
    /// sent as-is (NOT mode-shaped). Replaces the old `quickStarts`. Each also
    /// carries a short localized "why" detail shown as helper text on its card.
    private var quickActions: [QuickAction] {
        let en = ["Run a task", "Review the roadmap", "Set up a department", "Summarize where we are"]
        let vi = ["Chạy một tác vụ", "Xem lộ trình", "Thiết lập một phòng ban", "Tóm tắt tình hình công ty"]
        let detailsEn = [
            "Ship a real deliverable from your roadmap.",
            "See what's next and what's blocking launch.",
            "Bring Marketing, Legal, or Finance online.",
            "A quick read on the whole company.",
        ]
        let detailsVi = [
            "Tạo một sản phẩm thực từ lộ trình.",
            "Xem việc tiếp theo và điều đang cản trở.",
            "Kích hoạt Marketing, Pháp lý hoặc Tài chính.",
            "Tóm tắt nhanh toàn công ty.",
        ]
        let icons = ["checklist", "map", "square.grid.2x2", "doc.text"]
        let titles = lang == .vi ? vi : en
        let details = lang == .vi ? detailsVi : detailsEn
        return (0..<titles.count).map { i in
            QuickAction(title: titles[i], systemImage: icons[i], detail: details[i])
        }
    }

    /// Send a canned capability prompt through the normal chat path. Bypasses
    /// mode-shaping (the string already expresses the intent). Guarded like send.
    private func runQuickAction(_ text: String) {
        guard !companyStore.isCompanionTyping, !companyStore.isStreaming else { return }
        Task { await companyStore.sendChat(text, language: lang, department: selectedDept) }
    }

    private func send() {
        guard canSend else { return }
        // A pending enrichment question answers conversationally: the composer text
        // IS the answer (raw, no mode-shaping), routed to answerInterview.
        if let pending = companyStore.pendingInterview {
            let answer = companyStore.chatDraft
            companyStore.chatDraft = ""
            Task { await companyStore.answerInterview(messageId: pending.id, gap: pending.gap,
                                                      answer: answer, language: lang) }
            inputFocused = true
            return
        }
        let text = mode.shape(companyStore.chatDraft, language: lang)
        companyStore.chatDraft = ""
        Task { await companyStore.sendChat(text, language: lang, department: selectedDept) }
        // Re-assert focus: the composer moves between the empty-state and docked
        // `if/else` branches once `chatMessages` goes empty→non-empty, so SwiftUI
        // rebuilds the TextField and drops focus after the first send.
        inputFocused = true
    }
}

/// One chat bubble — me (accent, right) vs companion (surface, left), OR a draft
/// deliverable card (Approve/Redo) when the message carries a draft.
struct CopilotBubble: View {
    let message: CopilotMessage
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showDetail = false
    @State private var reaction: Bool?   // nil = none, true = up, false = down
    private var isMe: Bool { message.role == .me }

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }

    var body: some View {
        if message.producing {
            producingRow
        } else if let draft = message.draft {
            draftCard(draft)
        } else if let nav = message.navChip {
            navChip(nav)
        } else if let setup = message.setupSuggestion {
            setupCard(setup)
        } else if let facts = message.noted, !facts.isEmpty {
            notedChip(facts)
        } else if let action = message.firstRunAction, !message.actionConsumed {
            VStack(alignment: .leading, spacing: 8) {
                textBubble
                actionButton(action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let gap = message.interview, !message.interviewAnswered {
            interviewMessage(gap)
        } else {
            textBubble
        }
    }

    private func actionButton(_ action: FirstRunAction) -> some View {
        MessageCard(hue: MessageCardStyle.hue(for: .firstRunAction, companionAccent: companionAccent)) {
            Button {
                Task { await companyStore.runFirstRunAction(messageId: message.id, language: lang) }
            } label: {
                Text((lang == .vi ? "Làm cùng mình: " : "Do it with me: ") + action.taskTitle)
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }
            .buttonStyle(.plain)
        }
    }

    /// A tappable "go here" chip from byte's `nav` action — NOT auto-navigated
    /// (mirrors the web: the founder taps to move). Tapping resolves + applies
    /// the destination via `CompanyStore.activateNav` (sync — `select`/
    /// `selectedDeptKey` are plain mutations, no await needed).
    private func navChip(_ nav: NavAction) -> some View {
        let label = AppView.from(navDestination: nav.destination)?.title(lang) ?? nav.destination
        return HStack {
            MessageCard(hue: MessageCardStyle.hue(for: .navChip, companionAccent: companionAccent)) {
                Button { companyStore.activateNav(nav) } label: {
                    Text((lang == .vi ? "Đi tới " : "Go to ") + label)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 24)
        }
    }

    /// A tappable "turn this on" card from byte's `setup` action. Resolves the
    /// wire {category,name} to its `Toolkit` item for the display name/why-line
    /// and the category-appropriate enable verb; tapping runs the GUARDED
    /// enable in `CompanyStore.activateSetup` (never flips an already-on item off).
    private func setupCard(_ setup: SetupAction) -> some View {
        let item = Toolkit.find(category: setup.category, name: setup.name)
        let name = item?.name ?? setup.name
        let why = item?.why
        let verb = item?.category.enableVerb(lang) ?? (lang == .vi ? "Bật" : "Enable")
        return HStack {
            MessageCard(hue: MessageCardStyle.hue(for: .setupSuggestion, companionAccent: companionAccent)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(CodepetTheme.inter(14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if let why, !why.isEmpty {
                        Text(why)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { Task { await companyStore.activateSetup(setup) } } label: {
                        Text(verb)
                            .font(CodepetTheme.inter(12, weight: .semibold))
                            .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 24)
        }
    }

    /// A transient "Noted" chip per remembered fact — memory is already merged +
    /// persisted (`CompanyStore.handleRemember`) by the time this renders, so
    /// there is no tap/approval affordance here, just an acknowledgement.
    private func notedChip(_ facts: [RememberedFact]) -> some View {
        HStack {
            MessageCard(hue: MessageCardStyle.hue(for: .noted, companionAccent: companionAccent)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(facts, id: \.topic) { fact in
                        Text("📌 " + (lang == .vi ? "Đã ghi nhớ" : "Noted") + " · \(fact.topic) — \(fact.statement)")
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
            }
            Spacer(minLength: 24)
        }
    }

    /// First-run enrichment question, rendered conversationally: byte asks it as a
    /// normal companion message (orb + question + why-line), and the founder answers
    /// in the MAIN composer (send() routes to answerInterview while this is pending).
    /// A subtle Skip link advances without saving. No embedded form/box.
    private func interviewMessage(_ gap: InterviewGap) -> some View {
        let q = EnrichInterview.question(for: gap, language: lang)
        return HStack(alignment: .top, spacing: 10) {
            CompanionOrb(size: 28, glow: false)
            VStack(alignment: .leading, spacing: 6) {
                Text(q.ask)
                    .font(CodepetTheme.inter(15))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(q.why)
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await companyStore.answerInterview(messageId: message.id, gap: gap,
                                                              answer: nil, language: lang) }
                } label: {
                    Text(lang == .vi ? "Bỏ qua" : "Skip")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chat-run step-transparency indicator (web: a "producing" beat before the
    /// draft card lands). Mirrors `ChatThinkingRow`'s plain, no-bubble style — not
    /// a filled chat bubble — so it reads as ambient status, not a message.
    /// `CompanyStore.handleRunTaskId` removes this row (win or lose) before
    /// appending the real reply, so it's always transient.
    @ViewBuilder private var producingRow: some View {
        // With an execute-log, show the live step checklist (how the agent works);
        // otherwise fall back to the plain thinking row. `text` carries the task
        // title, `companionId` the acting specialist.
        if let steps = message.execSteps, !steps.isEmpty {
            ExecLogRow(taskTitle: message.text, deptName: message.deptName,
                       steps: steps, companionId: message.companionId)
        } else {
            ChatThinkingRow(taskTitle: message.text.isEmpty ? nil : message.text,
                            companionId: message.companionId)
        }
    }

    private var textBubble: some View {
        Group {
            if isMe {
                HStack {
                    Spacer(minLength: 24)
                    Text(message.text)
                        .font(CodepetTheme.inter(15))
                        .lineSpacing(4)
                        .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 14, bottomLeading: 14,
                                               bottomTrailing: 4, topTrailing: 14),
                            style: .continuous).fill(CodepetTheme.accentPurple))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    CompanionAvatar(companionId: message.companionId, size: 28)
                    VStack(alignment: .leading, spacing: 8) {
                        // A department specialist labels itself "Name · Dept" so the
                        // handoff reads as a real teammate stepping in.
                        if let dept = message.deptName,
                           let persona = message.companionId.flatMap({ PetCharacter.all[$0] }) {
                            Text("\(persona.name) · \(dept)")
                                .font(CodepetTheme.inter(12, weight: .semibold))
                                .foregroundColor(persona.color)
                        }
                        Text(message.text)
                            .font(CodepetTheme.inter(15))
                            .lineSpacing(4)
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        // Hide copy/regenerate/thumbs until the reply has text — an
                        // empty streaming placeholder shouldn't show an action bar.
                        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            companionActions
                        }
                    }
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Copy + Regenerate on a companion text bubble. Regenerate is a pure
    /// client-side resend of the last `me` message through the normal chat
    /// path — no backend "regenerate" endpoint exists.
    private var companionActions: some View {
        HStack(spacing: 14) {
            Button { copyText() } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundColor(CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            Button { regenerate() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundColor(CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            .disabled(companyStore.isCompanionTyping || companyStore.isStreaming)
            Button { react(true) } label: {
                Image(systemName: reaction == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 13))
                    .foregroundColor(reaction == true ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            Button { react(false) } label: {
                Image(systemName: reaction == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 13))
                    .foregroundColor(reaction == false ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }.buttonStyle(.plain)
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }

    private func regenerate() {
        guard !companyStore.isCompanionTyping, !companyStore.isStreaming else { return }
        guard let lastUser = companyStore.chatMessages.last(where: { $0.role == .me })?.text else { return }
        Task { await companyStore.sendChat(lastUser, language: lang) }
    }

    private func react(_ helpful: Bool) {
        reaction = helpful
        companyStore.reactToMessage(messageId: message.id, helpful: helpful)
    }

    /// A clean one-glance preview of a deliverable body for the card: drop leading
    /// markdown heading lines (the card already shows the title), then strip inline
    /// markdown markers so raw `##`/`**`/`` ` `` never leak into the preview.
    static func previewText(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        // Drop leading blank + heading lines.
        while let first = lines.first,
              first.trimmingCharacters(in: .whitespaces).isEmpty
                || first.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            lines.removeFirst()
        }
        let cleaned = lines.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "#", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func draftCard(_ d: Deliverable) -> some View {
        HStack {
            MessageCard(hue: message.draftApproved ? CodepetTheme.accentTeal : CodepetTheme.accentGold) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: d.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                            Text(d.title)
                                .font(CodepetTheme.inter(15, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                        }
                        Text(Self.previewText(d.body))
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.bodyText)
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
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                    } else {
                        HStack(spacing: 8) {
                            Button { Task { await companyStore.approveDraft(messageId: message.id) } } label: {
                                Text(lang == .vi ? "Duyệt" : "Approve")
                                    .font(CodepetTheme.inter(12, weight: .semibold))
                                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(CodepetTheme.accentPurple))
                            }.buttonStyle(.plain)
                            Button { Task { await companyStore.redoDraft(messageId: message.id, language: lang) } } label: {
                                Text(lang == .vi ? "Làm lại" : "Redo")
                                    .font(CodepetTheme.inter(12, weight: .semibold))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().stroke(CodepetTheme.hairline))
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
                                        .font(CodepetTheme.inter(11, weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().stroke(CodepetTheme.hairline))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
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
