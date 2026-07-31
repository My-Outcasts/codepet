import SwiftUI

/// The chat empty state: a centered, personalized hero greeting (time-of-day +
/// founder name, purple-gradient second line), the composer (injected so the
/// parent keeps ownership of draft/mode), and up to 3 LIVE roadmap cards
/// (beacon / needs-you / awaiting-approval) — or 3 prompt-starter cards that
/// fill the composer when there's no roadmap yet. Replaces the old
/// company-only greeting + static `QuickAction` pill row. The ambient purple
/// wash now lives in `ChatBackdrop` (applied by `CopilotChatView` behind both
/// the empty and active states), not here.
///
/// DOCK ADAPTATION (380pt panel, ported from the full-width feat/chat-redesign
/// original): smaller orb (56 vs 78), smaller greeting type (22 vs 31), single-
/// column card grids (vs 2-col), no fixed 760pt column cap (fills the dock
/// width instead), and tighter horizontal padding (20 vs 40).
struct ChatEmptyState<Composer: View>: View {
    let state: ChatLandingState
    let onOpenRoadmap: () -> Void
    let onStarter: (String) -> Void
    /// Dock-sized: fills the available width rather than capping at the
    /// full-width chat's 760pt column.
    var columnWidth: CGFloat = .infinity
    @ViewBuilder var composer: Composer

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(spacing: 24) {
            CompanionOrb(size: 56)

            greeting
                .padding(.horizontal, 24)

            composer
                .frame(maxWidth: columnWidth)

            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    /// Line 1: time-of-day + founder name, plain primary text. Line 2: the
    /// company question, in a purple→pink gradient. Both centered/semibold.
    private var greeting: some View {
        VStack(spacing: 4) {
            Text(state.greeting)
                .font(CodepetTheme.inter(22, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(state.question)
                .font(CodepetTheme.inter(22, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [
                        CodepetTheme.primaryText, CodepetTheme.accentPurple, CodepetTheme.accentPink]),
                    startPoint: .leading, endPoint: .trailing))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Up to 3 live roadmap cards (beacon / needs-you / awaiting-approval),
    /// omitted when zero/nil, tapping through to the Roadmap — or 3
    /// composer-filling prompt starters when there's no roadmap yet. Single
    /// column at dock width (vs 2-col in the full-width original).
    private var cards: some View {
        Group {
            if state.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                    ForEach(starters, id: \.self) { starterCard($0) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                    if let b = state.beacon {
                        landingCard(eyebrow: lang == .vi ? "TIẾP THEO" : "DO THIS NEXT",
                                    value: b.title, hue: CodepetTheme.accentPurple, onTap: onOpenRoadmap)
                    }
                    if state.needsYouCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CẦN BẠN" : "NEEDS YOU",
                                    value: "\(state.needsYouCount)", hue: CodepetTheme.accentBlue, onTap: onOpenRoadmap)
                    }
                    if state.awaitingApprovalCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CHỜ DUYỆT" : "AWAITING APPROVAL",
                                    value: "\(state.awaitingApprovalCount)", hue: CodepetTheme.accentGold, onTap: onOpenRoadmap)
                    }
                }
            }
        }
        .frame(maxWidth: columnWidth)
    }

    private var starters: [String] {
        lang == .vi
            ? ["Soạn định vị của tôi", "Lên kế hoạch tuần này", "Xem lại bản tóm tắt"]
            : ["Draft my positioning", "Plan this week", "Review my brief"]
    }

    private func landingCard(eyebrow: String, value: String, hue: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Capsule().fill(hue).frame(width: 3).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(hue).tracking(0.5)
                    Text(value).font(CodepetTheme.inter(14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
        }.buttonStyle(.plain)
    }

    private func starterCard(_ text: String) -> some View {
        Button { onStarter(text) } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(CodepetTheme.accentPurple)
                Text(text).font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
        }.buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ChatEmptyState (dock)") {
    ChatEmptyState(
        state: ChatLandingState(company: .empty, now: Date(), language: .en),
        onOpenRoadmap: {}, onStarter: { _ in }
    ) { RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 76) }
        .frame(width: 380, height: 700).background(Color.black).environmentObject(CompanyStore())
}
#endif
