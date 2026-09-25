import SwiftUI

/// "Planning the work…" at the bottom of the transcript while a Team Build's planner runs
/// (`CompanyStore.isPlanningTeamBuild`). Planning can take up to 180 s, and before this the only
/// sign was a greyed button — a founder would reasonably think it had stopped. Styled as a
/// sibling of `AgentsWorkingRow`: the same card, a spinner, one line.
struct TeamPlanningRow: View {
    @Environment(\.uiLanguage) private var lang
    /// Set when the row first appears; the row is removed when planning ends.
    @State private var startedAt = Date()

    var body: some View {
        HStack {
            MessageCard(hue: CodepetTheme.accentPurple) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(lang == .vi ? "Đang lập kế hoạch…" : "Planning the work…")
                                .font(CodepetTheme.inter(13, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                            // A ticking clock is the proof it has not stalled.
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(TeamBuildCopy.clock(ctx.date.timeIntervalSince(startedAt)))
                                    .font(CodepetTheme.inter(11, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(CodepetTheme.accentPurple)
                            }
                        }
                        Text(lang == .vi ? "Chia việc cho từng phòng ban — có thể mất vài phút."
                                         : "Splitting the work across departments — this can take a few minutes.")
                            .font(CodepetTheme.inter(11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
