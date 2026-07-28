// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI
import AppKit

/// The Copilot column: a company-grounded chat with the founder's companion.
struct CopilotChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var draft = ""
    @State private var mode: ChatMode = .ask
    @FocusState private var inputFocused: Bool

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
    /// "Good morning/afternoon/evening, {founder}." — first line of the empty-state
    /// greeting, in the plain primary text color (line 2 carries the purple gradient).
    private var greetingLine1: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part: String
        switch h {
        case ..<12:  part = lang == .vi ? "Chào buổi sáng" : "Good morning"
        case 12..<18: part = lang == .vi ? "Chào buổi chiều" : "Good afternoon"
        default:      part = lang == .vi ? "Chào buổi tối" : "Good evening"
        }
        return "\(part), \(founderName)."
    }
    private var greetingLine2: String {
        lang == .vi ? "Hôm nay mình xây gì cho \(companyName)?" : "What should we build for \(companyName) today?"
    }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !companyStore.isCompanionTyping && !companyStore.isStreaming
    }

    var body: some View {
        ZStack {
            ChatBackdrop()
            VStack(spacing: 0) {
                if companyStore.chatMessages.isEmpty {
                    ChatEmptyState(line1: greetingLine1,
                                   line2: greetingLine2,
                                   quickActions: quickActions,
                                   onQuickAction: runQuickAction) {
                        composerView
                    }
                } else {
                    messageList
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        composerView.frame(maxWidth: 600)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(companyStore.chatMessages) { m in
                            CopilotBubble(message: m).id(m.id)
                        }
                        if companyStore.isCompanionTyping { ChatThinkingRow(taskTitle: nil).id("typing") }
                    }
                    .padding(12)
                    .frame(maxWidth: 600, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .center)
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
            draft: $draft,
            mode: $mode,
            canSend: canSend,
            focus: $inputFocused,
            placeholder: placeholder,
            quickActions: quickActions,
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
        Task { await companyStore.sendChat(text, language: lang) }
    }

    private func send() {
        guard canSend else { return }
        let text = mode.shape(draft, language: lang)
        draft = ""
        Task { await companyStore.sendChat(text, language: lang) }
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
    @State private var interviewDraft = ""
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
            interviewCard(gap)
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
                    .foregroundColor(.white)
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
                        .foregroundColor(.white)
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
                            .foregroundColor(.white)
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

    /// First-run enrichment interview: question + why-line + free-text answer,
    /// Send (saves raw text to the brief) or Skip (advances without saving).
    private func interviewCard(_ gap: InterviewGap) -> some View {
        let q = EnrichInterview.question(for: gap, language: lang)
        let canSend = !interviewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack {
            MessageCard(hue: MessageCardStyle.hue(for: .interview, companionAccent: companionAccent)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.ask)
                        .font(CodepetTheme.inter(15, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(q.why)
                        .font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(lang == .vi ? "Nhập câu trả lời…" : "Type your answer…",
                              text: $interviewDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(CodepetTheme.inter(14))
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
                                .font(CodepetTheme.inter(12, weight: .semibold))
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
                                .font(CodepetTheme.inter(12, weight: .semibold))
                                .foregroundColor(CodepetTheme.mutedText)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().stroke(CodepetTheme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 24)
        }
    }

    /// The chat-run step-transparency indicator (web: a "producing" beat before the
    /// draft card lands). Mirrors `ChatThinkingRow`'s plain, no-bubble style — not
    /// a filled chat bubble — so it reads as ambient status, not a message.
    /// `CompanyStore.handleRunTaskId` removes this row (win or lose) before
    /// appending the real reply, so it's always transient.
    private var producingRow: some View {
        // Pass a real title if the producing message carries one; else nil → "Working on it…".
        ChatThinkingRow(taskTitle: nil)
    }

    private var textBubble: some View {
        Group {
            if isMe {
                HStack {
                    Spacer(minLength: 24)
                    Text(message.text)
                        .font(CodepetTheme.inter(15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 14, bottomLeading: 14,
                                               bottomTrailing: 4, topTrailing: 14),
                            style: .continuous).fill(CodepetTheme.accentPurple))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    CompanionOrb(size: 28, glow: false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.text)
                            .font(CodepetTheme.inter(15))
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        companionActions
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
                        Text(d.body)
                            .font(CodepetTheme.inter(13))
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
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                    } else {
                        HStack(spacing: 8) {
                            Button { Task { await companyStore.approveDraft(messageId: message.id) } } label: {
                                Text(lang == .vi ? "Duyệt" : "Approve")
                                    .font(CodepetTheme.inter(12, weight: .semibold))
                                    .foregroundColor(.white)
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
