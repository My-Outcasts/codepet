// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI

/// The Copilot column: a company-grounded chat with the founder's companion.
struct CopilotChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var draft = ""
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
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !companyStore.isCompanionTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            letsBuild
            Divider()
            inputBar
        }
        .frame(maxHeight: .infinity)
    }

    // Web Copilot header: "Your team" + "guiding · {company}" + History (stub).
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(lang == .vi ? "Đội của bạn" : "Your team")
                    .font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                Text((lang == .vi ? "đang hỗ trợ · " : "guiding · ") + companyName)
                    .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
            Spacer()
            Text(lang == .vi ? "Lịch sử" : "History")
                .font(CodepetTheme.inter(11, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
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
            : ["What should I focus on first?", "Summarize where my company is", "What's blocking my launch?"]
    }

    private var typingRow: some View {
        Text(lang == .vi ? "\(companionName) đang trả lời…" : "\(companionName) is typing…")
            .font(.pixelSystem(size: 11))
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(lang == .vi ? "Hỏi Codepet bất cứ điều gì về công ty…" : "Ask Codepet anything about your company…",
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
        Task { await companyStore.sendChat(text, language: lang) }
    }
}

/// One chat bubble — me (accent, right) vs companion (surface, left), OR a draft
/// deliverable card (Approve/Redo) when the message carries a draft.
struct CopilotBubble: View {
    let message: CopilotMessage
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showDetail = false
    private var isMe: Bool { message.role == .me }

    var body: some View {
        if let draft = message.draft {
            draftCard(draft)
        } else {
            textBubble
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
