// codepet/Views/Overview/OverviewBoardView.swift
import SwiftUI

/// The Overview = the roadmap board. Renders CompanyStore.company.tasks through
/// the pure RoadmapEngine: a progress + beacon header over five phase columns.
/// Empty → an honest empty card plus a quiet, fail-open generate on appear.
struct OverviewBoardView: View {
    @EnvironmentObject var companyStore: CompanyStore

    private var tasks: [RoadmapTask] { companyStore.company.tasks }

    var body: some View {
        Group {
            if tasks.isEmpty {
                EmptyRoadmapView()
            } else {
                board
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if companyStore.company.tasks.isEmpty { await companyStore.generateRoadmap() }
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoadmapHeaderView(tasks: tasks)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(RoadmapEngine.orderedColumns(tasks), id: \.phase) { col in
                        PhaseColumnView(phase: col.phase, tasks: col.tasks, allTasks: tasks)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Honest empty state — the roadmap hasn't been generated yet.
struct EmptyRoadmapView: View {
    @Environment(\.uiLanguage) private var lang
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 30))
                .foregroundColor(CodepetTheme.mutedText)
            Text(lang == .vi ? "Lộ trình của bạn sẽ xuất hiện ở đây" : "Your roadmap will appear here")
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Khi Codepet vạch ra các bước tiếp theo, chúng sẽ hiện ở đây."
                             : "Once Codepet maps your next steps, they show up here.")
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}
