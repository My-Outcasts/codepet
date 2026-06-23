import SwiftUI

struct SessionChatPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatStore: SessionChatStore
    @EnvironmentObject var controller: SessionChatController

    let session: Session
    let onClose: () -> Void
    var onSend: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    @State private var atBottom = true

    private var pet: PetCharacter? { PetCharacter.all[appState.activeChar] }
    private var petName: String { pet?.name ?? "Pet" }
    private var petColor: Color { pet?.color ?? CodepetTheme.accentPurple }

    private var messages: [ChatMessage] { chatStore.messages(for: session.id) }
    private var isStreaming: Bool { controller.inFlightSessionId == session.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            inputRow
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(petColor.opacity(0.05))
        .onAppear {
            inputFocused = true
            // Consume pending chat prompt from Tips tab deep-link
            if let prompt = appState.pendingChatPrompt {
                draft = prompt
                appState.pendingChatPrompt = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let pet = pet {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(pet.color.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(pet.color.opacity(0.35), lineWidth: 1.5)
                        )
                        .overlay(
                            Image(pet.imageName)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(petName)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                    Text("Session chat")
                        .font(.pixelSystem(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PixelButtonStyle(
                    fill: Color(hex: "#F0F0EC"),
                    foreground: Color(hex: "#2D2B26"),
                    paddingH: 8,
                    paddingV: 6,
                    blockSize: 2,
                    steps: 2,
                    borderWidth: 2,
                    shadowOffset: 2,
                    font: .pixelSystem(size: 12, weight: .semibold)
                ))
                .help("Close chat")
            }

            // Status row
            HStack(spacing: 4) {
                Circle()
                    .fill(petColor)
                    .frame(width: 6, height: 6)
                Text(isStreaming ? "\(petName) is typing..." : "Ask about this session.")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(petColor.opacity(0.08))
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty && !isStreaming {
                        emptyGreetingBubble
                    }
                    ForEach(messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if isStreaming {
                        streamingBubble
                            .id("streaming")
                    }
                    if let error = controller.error {
                        errorRow(error)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottomSentinel")
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: BottomVisibilityKey.self,
                                    value: geo.frame(in: .named("chatScroll")).maxY
                                            <= geo.frame(in: .named("chatScroll")).size.height + 40
                                )
                            }
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .coordinateSpace(name: "chatScroll")
            .onPreferenceChange(BottomVisibilityKey.self) { atBottom = $0 }
            .onChange(of: messages.count) { _ in
                if atBottom, let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: controller.streamingText) { _ in
                if atBottom {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyGreetingBubble: some View {
        bubble(role: .pet, text: greeting, isStreaming: false)
    }

    private var greeting: String {
        "Ask me about this session."
    }

    private var streamingBubble: some View {
        bubble(role: .pet, text: controller.streamingText, isStreaming: true)
    }

    private func bubble(for message: ChatMessage) -> some View {
        bubble(role: message.role, text: message.text, isStreaming: false)
    }

    @ViewBuilder
    private func bubble(role: ChatMessage.Role, text: String, isStreaming: Bool) -> some View {
        let isUser = role == .user
        if isUser {
            HStack {
                Spacer()
                Text(text)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(petColor.opacity(0.85))
                    )
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                if let pet = pet {
                    Image(pet.imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(text)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#2D2B26"))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isStreaming {
                        Text("▎")
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(petColor)
                            .opacity(0.7)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(petColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(petColor.opacity(0.25), lineWidth: 1)
                        )
                )
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Error row

    private func errorRow(_ error: SessionChatController.ChatError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.accentOrange)
            Text(errorText(error))
                .font(CodepetTheme.body(11))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                .fill(CodepetTheme.accentOrange.opacity(0.10))
        )
    }

    private func errorText(_ error: SessionChatController.ChatError) -> String {
        switch error {
        case .notSignedIn: return "Sign in to chat with your pet."
        case .rateLimited(let resetAt, _):
            if let r = resetAt {
                let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
                return "Daily limit reached. Comes back at \(f.string(from: r))."
            }
            return "You've reached today's limit."
        case .networkOrServer:
            return "Could not reach your pet — try again."
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask \(petName)...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($inputFocused)
                .font(.pixelSystem(size: 12))
                .foregroundColor(Color(hex: "#2D2B26"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(petColor.opacity(0.08))
                )
                .onSubmit { submit() }

            Button(action: submit) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(PixelButtonStyle(
                fill: canSubmit ? petColor : Color(hex: "#D0D0CC"),
                foreground: .white,
                paddingH: 10,
                paddingV: 8,
                blockSize: 2,
                steps: 2,
                borderWidth: 2,
                shadowOffset: 3,
                font: .pixelSystem(size: 14, weight: .bold)
            ))
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(12)
        .background(petColor.opacity(0.08))
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    private func submit() {
        guard canSubmit else { return }
        let text = draft
        draft = ""
        onSend(text)
    }
}

// MARK: - Preference key for bottom-proximity auto-scroll guard

private struct BottomVisibilityKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}
