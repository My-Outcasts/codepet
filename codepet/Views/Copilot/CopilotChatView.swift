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
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !companyStore.isCompanionTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .frame(maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if companyStore.chatMessages.isEmpty { greeting }
                    ForEach(companyStore.chatMessages) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                    if companyStore.isCompanionTyping { typingRow }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: companyStore.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var greeting: some View {
        Text(lang == .vi
             ? "Chào, mình là \(companionName). Hỏi mình bất cứ điều gì về công ty của bạn."
             : "Hi, I'm \(companionName). Ask me anything about your company.")
            .font(.pixelSystem(size: 12))
            .foregroundColor(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var typingRow: some View {
        Text(lang == .vi ? "\(companionName) đang trả lời…" : "\(companionName) is typing…")
            .font(.pixelSystem(size: 11))
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(lang == .vi ? "Nhắn cho \(companionName)…" : "Message \(companionName)…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.pixelSystem(size: 12))
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

/// One chat bubble — me (accent, right) vs companion (surface, left).
struct CopilotBubble: View {
    let message: CopilotMessage
    private var isMe: Bool { message.role == .me }

    var body: some View {
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
}
