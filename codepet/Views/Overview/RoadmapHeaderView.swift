// codepet/Views/Overview/RoadmapHeaderView.swift
import SwiftUI

/// Full-width header above the columns: a Project Progress card and the
/// DO THIS NEXT beacon (hidden when there's no next step).
struct RoadmapHeaderView: View {
    let tasks: [RoadmapTask]
    @Environment(\.uiLanguage) private var lang

    private var total: Int { tasks.count }
    private var doneCount: Int { tasks.filter(\.done).count }
    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var next: RoadmapTask? { RoadmapEngine.nextStep(tasks) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            progressCard
            if let n = next { beaconCard(n) }
        }
    }

    private var progressCard: some View {
        CodepetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(lang == .vi ? "Tiến độ dự án" : "Project progress")
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.mutedText)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CodepetTheme.hairline).frame(height: 8)
                        Capsule().fill(CodepetTheme.accentPurple)
                            .frame(width: geo.size.width * CGFloat(pct) / 100.0, height: 8)
                    }
                }
                .frame(height: 8)
                Text(progressLabel)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressLabel: String {
        lang == .vi ? "\(pct)% · \(doneCount)/\(total) xong"
                    : "\(pct)% · \(doneCount) of \(total) done"
    }

    private func beaconCard(_ n: RoadmapTask) -> some View {
        CodepetCard(fill: CodepetTheme.accentPurple.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang == .vi ? "★ LÀM ĐIỀU NÀY TIẾP" : "★ DO THIS NEXT")
                    .font(.pixelSystem(size: 10, weight: .bold))
                    .foregroundColor(CodepetTheme.accentPurple)
                Text(n.title)
                    .font(.pixelSystem(size: 13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
