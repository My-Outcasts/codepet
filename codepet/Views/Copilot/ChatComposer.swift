import SwiftUI

/// The chat composer — one reusable input surface used in BOTH the empty hero
/// and the docked active conversation. Owns no state: draft/mode live in the
/// parent (`CopilotChatView`) so the same value drives both placements.
///
/// Honesty notes: the `+` button is a quick-actions menu (NOT a file picker —
/// the app has no attachments), and the mode control shapes the outgoing message
/// via `ChatMode` (no backend mode exists).
struct ChatComposer: View {
    @Binding var draft: String
    @Binding var mode: ChatMode
    var canSend: Bool
    var focus: FocusState<Bool>.Binding
    var placeholder: String
    var quickActions: [QuickAction]
    var onSend: () -> Void
    var onQuickAction: (String) -> Void

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(15))
                .lineLimit(1...6)
                .focused(focus)
                .onSubmit(onSend)

            HStack(spacing: 8) {
                quickActionsMenu
                modeMenu
                Spacer()
                sendButton
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LinearGradient(
                    gradient: Gradient(colors: [
                        CodepetTheme.accentPurple, Color.dyn("#7c3aed", "#7c3aed"), CodepetTheme.accentPink]),
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
        .shadow(color: reduceTransparency ? .clear : CodepetTheme.accentPurple.opacity(0.22), radius: 22)
    }

    private var quickActionsMenu: some View {
        Menu {
            ForEach(quickActions) { qa in
                Button {
                    onQuickAction(qa.title)
                } label: {
                    Label(qa.title, systemImage: qa.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(CodepetTheme.hairline)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var modeMenu: some View {
        Menu {
            ForEach(ChatMode.allCases) { m in
                Button(m.label(lang)) { mode = m }
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode.label(lang)).font(CodepetTheme.inter(13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodepetTheme.hairline)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        canSend
                            ? AnyShapeStyle(LinearGradient(
                                gradient: Gradient(colors: [CodepetTheme.accentPurple, CodepetTheme.accentPink]),
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(CodepetTheme.mutedText)
                    )
                    .shadow(color: canSend ? CodepetTheme.accentPurple.opacity(0.55) : .clear, radius: 10)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }
}

#if DEBUG
private struct ChatComposerPreviewHost: View {
    @State private var draft = ""
    @State private var mode: ChatMode = .ask
    @FocusState private var focused: Bool
    var body: some View {
        ChatComposer(
            draft: $draft, mode: $mode, canSend: !draft.isEmpty,
            focus: $focused,
            placeholder: "Ask anything about your company…",
            quickActions: [
                QuickAction(title: "Run a task", systemImage: "checklist",
                            detail: "Ship a real deliverable from your roadmap."),
                QuickAction(title: "Review the roadmap", systemImage: "map",
                            detail: "See what's next and what's blocking launch."),
            ],
            onSend: {}, onQuickAction: { _ in }
        )
        .frame(width: 640)
        .padding()
    }
}

#Preview("ChatComposer") { ChatComposerPreviewHost() }
#endif
