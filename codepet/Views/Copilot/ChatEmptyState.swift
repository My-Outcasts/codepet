import SwiftUI

/// The chat empty state: a centered, personalized hero greeting (time-of-day +
/// founder name, purple-gradient second line), the composer (injected so the
/// parent keeps ownership of draft/mode), and a 2-column grid of capability
/// quick-action cards. Replaces the old company-only greeting + pill row. The
/// ambient purple wash now lives in `ChatBackdrop` (applied by `CopilotChatView`
/// behind both the empty and active states), not here.
struct ChatEmptyState<Composer: View>: View {
    let line1: String
    let line2: String
    let quickActions: [QuickAction]
    let onQuickAction: (String) -> Void
    @ViewBuilder var composer: Composer

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(spacing: 28) {
            CompanionOrb(size: 78)

            greeting
                .padding(.horizontal, 24)

            composer
                .frame(maxWidth: 600)

            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    /// Line 1: time-of-day + founder name, plain primary text. Line 2: the
    /// company question, in a purple→pink gradient. Both centered/semibold.
    private var greeting: some View {
        VStack(spacing: 4) {
            Text(line1)
                .font(CodepetTheme.inter(31, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(line2)
                .font(CodepetTheme.inter(31, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [
                        CodepetTheme.primaryText, CodepetTheme.accentPurple, CodepetTheme.accentPink]),
                    startPoint: .leading, endPoint: .trailing))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Quick-action cards, 2-column grid, capped to the composer's max-width.
    private var cards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(quickActions, id: \.id) { card($0) }
        }
        .frame(maxWidth: 600)
    }

    private func card(_ qa: QuickAction) -> some View {
        Button { onQuickAction(qa.title) } label: {
            HStack(alignment: .top, spacing: 0) {
                Capsule()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [CodepetTheme.accentPurple, CodepetTheme.accentPink]),
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: qa.systemImage)
                            .font(.system(size: 13))
                            .foregroundColor(CodepetTheme.accentPurple)
                        Text(qa.title)
                            .font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                    }
                    Text(qa.detail)
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(.leading, 12)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ChatEmptyState") {
    ChatEmptyState(
        line1: "Good evening, Mona.",
        line2: "What should we build for Acme today?",
        quickActions: [
            QuickAction(title: "Run a task", systemImage: "checklist",
                        detail: "Ship a real deliverable from your roadmap."),
            QuickAction(title: "Review the roadmap", systemImage: "map",
                        detail: "See what's next and what's blocking launch."),
            QuickAction(title: "Set up a department", systemImage: "square.grid.2x2",
                        detail: "Bring Marketing, Legal, or Finance online."),
            QuickAction(title: "Summarize where we are", systemImage: "doc.text",
                        detail: "A quick read on the whole company."),
        ],
        onQuickAction: { _ in }
    ) {
        RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 96).frame(maxWidth: 720)
    }
    .frame(width: 900, height: 700)
    .background(Color.black)
    .environmentObject(CompanyStore())
}
#endif
