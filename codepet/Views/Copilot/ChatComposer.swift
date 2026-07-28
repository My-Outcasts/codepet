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
    var accent: Color
    var accent2: Color
    var isBusy: Bool
    @Binding var selectedDept: Department?
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

            deptChips

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
                .stroke(accent.opacity(focus.wrappedValue ? 0.9 : 0.5),
                        lineWidth: focus.wrappedValue ? 1.5 : 1.2)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
        .shadow(color: (focus.wrappedValue && !reduceTransparency) ? accent.opacity(0.28) : .clear, radius: 18)
        .opacity(isBusy ? 0.72 : 1.0)
    }

    private var deptChips: some View {
        HStack(spacing: 6) {
            ForEach(DepartmentCatalog.all.prefix(3)) { dep in
                chip(dep)
            }
            Menu {
                ForEach(DepartmentCatalog.all.dropFirst(3)) { dep in
                    Button {
                        selectedDept = (selectedDept?.key == dep.key) ? nil : dep
                    } label: {
                        Label(dep.name, systemImage: selectedDept?.key == dep.key ? "checkmark" : "")
                    }
                }
            } label: {
                Text("•••").font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 10).frame(height: 26)
                    .overlay(Capsule().stroke(CodepetTheme.hairline))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private func chip(_ dep: Department) -> some View {
        let on = selectedDept?.key == dep.key
        return Button {
            selectedDept = on ? nil : dep
        } label: {
            Text(dep.name).font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(on ? dep.accent : CodepetTheme.bodyText)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(on ? dep.accent.opacity(0.15) : Color.clear))
                .overlay(Capsule().stroke(on ? dep.accent : CodepetTheme.hairline))
        }.buttonStyle(.plain)
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
                                gradient: Gradient(colors: [accent, accent2]),
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(CodepetTheme.mutedText)
                    )
                    .shadow(color: canSend ? accent.opacity(0.55) : .clear, radius: 10)
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
    @State private var dept: Department? = nil
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
            accent: CodepetTheme.accentPurple, accent2: CodepetTheme.accentPink,
            isBusy: false, selectedDept: $dept,
            onSend: {}, onQuickAction: { _ in }
        )
        .frame(width: 640)
        .padding()
    }
}

#Preview("ChatComposer") { ChatComposerPreviewHost() }
#endif
