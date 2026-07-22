// codepet/Views/Tasks/TasksView.swift
import SwiftUI

/// Kanban buckets by the task's derived state. Up next folds "Codepet can do" +
/// "queued/blocked does-or-draft" (web's does + draft-not-yet); a produced draft
/// sits in Awaiting; needsYou in Your move; done in Done.
enum TaskColumn: CaseIterable {
    case upNext, awaiting, yourMove, done
    static func column(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskColumn {
        if task.done { return .done }
        switch RoadmapEngine.status(for: task, in: tasks) {
        case .done:          return .done
        case .needsApproval: return .awaiting
        case .needsYou:      return .yourMove
        case .codepetCanDo, .blocked: return .upNext
        }
    }
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .upNext:   return lang == .vi ? "Tiếp theo" : "Up next"
        case .awaiting: return lang == .vi ? "Chờ bạn duyệt" : "Awaiting your approval"
        case .yourMove: return lang == .vi ? "Lượt của bạn" : "Your move"
        case .done:     return lang == .vi ? "Xong" : "Done"
        }
    }
    var dot: Color {
        switch self {
        case .upNext:   return CodepetTheme.accentPurple
        case .awaiting: return CodepetTheme.accentGold
        case .yourMove: return CodepetTheme.accentBlue
        case .done:     return Color(hex: "#10B981")   // web's exact Done green
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Nhiệm vụ" : "Tasks").font(CodepetTheme.title())
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Việc \(companionName) đang làm, đang soạn, hoặc đang chờ bạn."
                                 : "What \(companionName) is doing, drafting, or waiting on you for.")
                    .font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskColumn.allCases, id: \.self) { col in column(col) }
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tasks(in col: TaskColumn) -> [RoadmapTask] {
        companyStore.company.tasks.filter { TaskColumn.column(for: $0, in: companyStore.company.tasks) == col }
    }

    private func column(_ col: TaskColumn) -> some View {
        let items = tasks(in: col)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(col.dot).frame(width: 7, height: 7)
                Text(col.label(lang)).font(CodepetTheme.inter(12.5, weight: .semibold)).foregroundColor(CodepetTheme.bodyText)
                Text("\(items.count)").font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
            }
            if items.isEmpty {
                Text(lang == .vi ? "Trống" : "Nothing here")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 20)
            } else {
                ForEach(items) { t in card(t) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(col.dot.opacity(0.06)))
    }

    private func card(_ t: RoadmapTask) -> some View {
        Button {
            if !t.done { Task { await companyStore.runTask(t, language: lang) } }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if let d = DepartmentCatalog.find(t.dept)?.name {
                    Text(d).font(CodepetTheme.inter(12.5, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
                }
                Text(t.title).font(CodepetTheme.inter(12.5, weight: .medium)).foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.surface))
        }
        .buttonStyle(.plain)
    }
}
