// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI

/// The Copilot column: a company-grounded chat with the founder's companion.
struct CopilotChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    /// Toggles the "History" thread switcher over the message list. Session-only
    /// UI state — the History stub (see the header) now activates this.
    @State private var showHistory = false

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var companyName: String {
        let n = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Codepet" : n
    }
    private var founderName: String {
        let n = (companyStore.company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (lang == .vi ? "bạn" : "there") : n
    }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !companyStore.isCompanionTyping && !companyStore.isStreaming
    }
    /// True while a chat turn is in flight — gates the History toggle here and
    /// (via `ThreadListView`'s own copy of this) the "New chat"/switch/delete
    /// row controls, so the UI can't trigger a mid-stream thread repoint even
    /// though `CompanyStore` also guards it at the source. Mirrors `canSend`'s
    /// existing streaming gate.
    private var isChatBusy: Bool {
        companyStore.isCompanionTyping || companyStore.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showHistory {
                ThreadListView(showHistory: $showHistory)
            } else {
                messageList
                letsBuild
            }
            Divider()
            inputBar
        }
        .frame(maxHeight: .infinity)
    }

    // Web Copilot header: "Your team" + "guiding · {company}" + History toggle
    // (was an inert stub — now opens/closes the thread switcher below).
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(lang == .vi ? "Đội của bạn" : "Your team")
                    .font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                Text((lang == .vi ? "đang hỗ trợ · " : "guiding · ") + companyName)
                    .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
            Spacer()
            Button { showHistory.toggle() } label: {
                Text(lang == .vi ? "Lịch sử" : "History")
                    .font(CodepetTheme.inter(11, weight: .medium))
                    .foregroundColor(isChatBusy ? CodepetTheme.mutedText.opacity(0.5)
                                     : (showHistory ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
            }
            .buttonStyle(.plain)
            .disabled(isChatBusy)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // "Let's build" CTA — stub (the live build session is a later effort).
    private var letsBuild: some View {
        Button { } label: {
            Text("🔨 " + (lang == .vi ? "Cùng xây" : "Let's build"))
                .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.accentPurple)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(CodepetTheme.accentPurple.opacity(0.08))
        }.buttonStyle(.plain)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if companyStore.chatMessages.isEmpty { greeting }
                    ForEach(companyStore.chatMessages) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                    if companyStore.isCompanionTyping { typingRow.id("typing") }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: companyStore.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
            .onChange(of: companyStore.isCompanionTyping) { _, typing in
                if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == .vi
                 ? "Chào \(founderName). Hỏi mình bất cứ điều gì về \(companyName) — nên tập trung vào đâu, điều gì đang cản trở, hay xây gì tiếp theo."
                 : "Welcome, \(founderName). Ask me anything about \(companyName) — where to focus, what's blocking you, or what to build next.")
                .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickStarts, id: \.self) { chip in
                    Button { Task { await companyStore.sendChat(chip, language: lang) } } label: {
                        Text(chip).font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var quickStarts: [String] {
        lang == .vi
            ? ["Nên tập trung vào đâu trước?", "Tóm tắt tình hình công ty", "Điều gì đang cản trở ra mắt?"]
            : ["What should I focus on first?", "Summarize where my company is", "What\u{2019}s blocking my launch?"]
    }

    private var typingRow: some View {
        Text(lang == .vi ? "\(companionName) đang trả lời…" : "\(companionName) is typing…")
            .font(.pixelSystem(size: 11))
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(lang == .vi ? "Hỏi \(companionName) bất cứ điều gì về công ty…" : "Ask \(companionName) anything about your company…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(12))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(10)
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        showHistory = false   // sending always returns to the live conversation
        Task { await companyStore.sendChat(text, language: lang) }
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
                .background(Capsule().fill(CodepetTheme.accentPurple))
        }
        .buttonStyle(.plain)
    }

    /// A tappable "go here" chip from byte's `nav` action — NOT auto-navigated
    /// (mirrors the web: the founder taps to move). Tapping resolves + applies
    /// the destination via `CompanyStore.activateNav` (sync — `select`/
    /// `selectedDeptKey` are plain mutations, no await needed).
    private func navChip(_ nav: NavAction) -> some View {
        let label = AppView.from(navDestination: nav.destination)?.title(lang) ?? nav.destination
        return HStack {
            Button { companyStore.activateNav(nav) } label: {
                Text((lang == .vi ? "Đi tới " : "Go to ") + label)
                    .font(.pixelSystem(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }
            .buttonStyle(.plain)
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
            CodepetCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if let why, !why.isEmpty {
                        Text(why)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { Task { await companyStore.activateSetup(setup) } } label: {
                        Text(verb)
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                    }.buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 24)
        }
    }

    /// A transient "Noted" chip per remembered fact — memory is already merged +
    /// persisted (`CompanyStore.handleRemember`) by the time this renders, so
    /// there is no tap/approval affordance here, just an acknowledgement.
    private func notedChip(_ facts: [RememberedFact]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(facts, id: \.topic) { fact in
                    Text("📌 " + (lang == .vi ? "Đã ghi nhớ" : "Noted") + " · \(fact.topic) — \(fact.statement)")
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(CodepetTheme.surface))
                }
            }
            Spacer(minLength: 24)
        }
    }

    /// First-run enrichment interview: question + why-line + free-text answer,
    /// Send (saves raw text to the brief) or Skip (advances without saving).
    private func interviewCard(_ gap: InterviewGap) -> some View {
        let q = EnrichInterview.question(for: gap, language: lang)
        let canSend = !interviewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(q.ask)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(q.why)
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(lang == .vi ? "Nhập câu trả lời…" : "Type your answer…",
                          text: $interviewDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.pixelSystem(size: 12))
                    .lineLimit(1...4)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodepetTheme.surface))
                HStack(spacing: 8) {
                    Button {
                        let answer = interviewDraft
                        interviewDraft = ""
                        Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: answer, language: lang) }
                    } label: {
                        Text(lang == .vi ? "Gửi" : "Send")
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                    }
                    .buttonStyle(.plain).disabled(!canSend)
                    Button {
                        interviewDraft = ""
                        Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: nil, language: lang) }
                    } label: {
                        Text(lang == .vi ? "Bỏ qua" : "Skip")
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().stroke(CodepetTheme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CodepetTheme.surface))
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 24)
        }
    }

    /// The chat-run step-transparency indicator (web: a "producing" beat before the
    /// draft card lands). Mirrors `CopilotChatView.typingRow`'s plain, no-bubble
    /// style — not a filled chat bubble — so it reads as ambient status, not a
    /// message. `CompanyStore.handleRunTaskId` removes this row (win or lose)
    /// before appending the real reply, so it's always transient.
    private var producingRow: some View {
        HStack {
            Text(lang == .vi ? "\(companionName) đang tổng hợp…" : "\(companionName) is putting that together…")
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 24)
        }
    }

    private var textBubble: some View {
        HStack {
            if isMe { Spacer(minLength: 24) }
            Text(message.text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(isMe ? .white : CodepetTheme.primaryText)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isMe ? CodepetTheme.accentPurple : CodepetTheme.surface))
                .fixedSize(horizontal: false, vertical: true)
            if !isMe { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
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
                                    .background(Capsule().fill(CodepetTheme.accentPurple))
                            }.buttonStyle(.plain)
                            Button { Task { await companyStore.redoDraft(messageId: message.id, language: lang) } } label: {
                                Text(lang == .vi ? "Làm lại" : "Redo")
                                    .font(.pixelSystem(size: 10, weight: .semibold))
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
                                        .font(.pixelSystem(size: 9, weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().stroke(CodepetTheme.hairline))
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
/// RunTaskRequest so the CF revises in place.
private enum ReviseKind: CaseIterable {
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
