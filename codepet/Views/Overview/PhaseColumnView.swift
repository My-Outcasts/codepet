// codepet/Views/Overview/PhaseColumnView.swift
import SwiftUI

/// One phase column: header (label + count) over its task cards. An empty phase
/// shows a muted placeholder so the column reads as intentionally empty.
struct PhaseColumnView: View {
    let phase: RoadmapPhase
    let tasks: [RoadmapTask]
    let allTasks: [RoadmapTask]
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.label(lang).uppercased())
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.bodyText)
                Spacer()
                Text("\(tasks.count)")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 4)
            if tasks.isEmpty {
                Text("—")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else {
                ForEach(tasks) { t in
                    TaskCardView(task: t, allTasks: allTasks)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 230, alignment: .top)
    }
}
