import SwiftUI

/// Collapsible "Last time on this project" reminder shown inside the pet header
/// when a previous session in the same project has a summary. Expanded by default.
struct LastTimeReminderView: View {
    let summary: SessionSummary
    let sessionDate: Date
    let sessionDurationMinutes: Int?
    @Environment(\.uiLanguage) private var uiLanguage

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle row
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ReflectionTheme.accent)
                    Text(uiLanguage == .vi ? "Lần trước ở dự án này" : "Last time on this project")
                        .font(ReflectionTheme.sans(12, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(ReflectionTheme.mutedText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(markdown: summary.summary)
                        .font(ReflectionTheme.sans(13))
                        .foregroundColor(ReflectionTheme.primaryText)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Timestamp + duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(ReflectionTheme.accent.opacity(0.55))
                        Text(timestampLabel)
                            .font(ReflectionTheme.sans(12))
                            .foregroundColor(ReflectionTheme.accent.opacity(0.55))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ReflectionTheme.reminderBackground)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ReflectionTheme.reminderBorder)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var timestampLabel: String {
        let relative = relativeLabel(for: sessionDate)
        if let mins = sessionDurationMinutes, mins > 0 {
            let minWord = uiLanguage == .vi ? "phút" : "min session"
            return "\(relative) · \(mins) \(minWord)"
        }
        return relative
    }

    private func relativeLabel(for date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        if day == today {
            return uiLanguage == .vi ? "Hôm nay" : "Today"
        }
        if day == cal.date(byAdding: .day, value: -1, to: today)! {
            return uiLanguage == .vi ? "Hôm qua" : "Yesterday"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
