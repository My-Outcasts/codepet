import SwiftUI

/// The streaming/producing state: a breathing companion orb + a label that names
/// the work (via ChatThinkingLabel), with a subtle light sweep through the text.
/// Replaces the old static typingRow/producingRow. Reduce Motion → orb static +
/// no sweep. Dock-sized: orb ≤ 22pt, label truncates to one line at the 380pt
/// dock width instead of wrapping.
struct ChatThinkingRow: View {
    /// A real in-flight title, or nil for a plain chat turn (→ "Working on it…").
    var taskTitle: String? = nil
    /// The specialist working (a department handoff); nil → the global companion.
    var companionId: String? = nil

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String { ChatThinkingLabel.text(taskTitle: taskTitle, language: lang) }

    var body: some View {
        HStack(spacing: 10) {
            CompanionAvatar(companionId: companionId, size: 22, isWorking: true)
            shimmerLabel
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder private var shimmerLabel: some View {
        let base = Text(label)
            .font(CodepetTheme.inter(13))
            .foregroundColor(CodepetTheme.mutedText)
            .lineLimit(1)
            .truncationMode(.tail)
        if reduceMotion {
            base
        } else {
            TimelineView(.animation) { tl in
                let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.1) / 2.1
                base.overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, CodepetTheme.primaryText.opacity(0.7), .clear]),
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .offset(x: CGFloat(phase * 260 - 60))
                    .mask(base)
                    .allowsHitTesting(false)
                )
            }
        }
    }
}

#if DEBUG
#Preview("ChatThinkingRow") {
    VStack(alignment: .leading, spacing: 16) {
        ChatThinkingRow(taskTitle: nil)
        ChatThinkingRow(taskTitle: "positioning brief")
    }
    .padding(40)
    .frame(width: 380)
    .environmentObject(CompanyStore())
}
#endif
