import SwiftUI

/// The chat empty state: a centered, personalized hero greeting, the composer
/// (injected so the parent keeps ownership of draft/mode), and a row of
/// capability quick-action pills. Replaces the old left-aligned welcome text.
struct ChatEmptyState<Composer: View>: View {
    let companyName: String
    let quickActions: [QuickAction]
    let onQuickAction: (String) -> Void
    @ViewBuilder var composer: Composer

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(spacing: 28) {
            CompanionOrb(size: 78)

            greeting
                .font(CodepetTheme.inter(34, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            composer
                .frame(maxWidth: 680)

            pills
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    /// "How can I help you build {company} today?" with the company in accent.
    private var greeting: Text {
        let accent = Text(companyName).foregroundColor(CodepetTheme.accentPurple)
        switch lang {
        case .vi: return Text("Mình giúp gì cho ") + accent + Text(" hôm nay?")
        case .en: return Text("How can I help you build ") + accent + Text(" today?")
        }
    }

    /// Quick-action pills. One row when it fits, two rows otherwise, so a narrow
    /// column never clips them.
    private var pills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { ForEach(quickActions, id: \.id) { pill($0) } }
            VStack(spacing: 10) {
                HStack(spacing: 10) { ForEach(firstHalf, id: \.id) { pill($0) } }
                HStack(spacing: 10) { ForEach(secondHalf, id: \.id) { pill($0) } }
            }
        }
    }

    private var firstHalf: [QuickAction] { Array(quickActions.prefix((quickActions.count + 1) / 2)) }
    private var secondHalf: [QuickAction] { Array(quickActions.suffix(quickActions.count / 2)) }

    private func pill(_ qa: QuickAction) -> some View {
        Button { onQuickAction(qa.title) } label: {
            HStack(spacing: 8) {
                Image(systemName: qa.systemImage)
                    .font(.system(size: 13))
                    .foregroundColor(CodepetTheme.accentPurple)
                Text(qa.title)
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(CodepetTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ChatEmptyState") {
    ChatEmptyState(
        companyName: "Acme",
        quickActions: [
            QuickAction(title: "Run a task", systemImage: "checklist"),
            QuickAction(title: "Review the roadmap", systemImage: "map"),
            QuickAction(title: "Set up a department", systemImage: "square.grid.2x2"),
            QuickAction(title: "Summarize where we are", systemImage: "doc.text"),
        ],
        onQuickAction: { _ in }
    ) {
        RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 96).frame(maxWidth: 680)
    }
    .frame(width: 900, height: 620)
}
#endif
