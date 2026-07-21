// codepet/Views/Overview/TaskCardView.swift
import SwiftUI

/// One roadmap task card: done toggle, title, detail, who chip, status pill, and
/// (when blocked) an "after: <dep>" hint. Read-only apart from the done toggle.
struct TaskCardView: View {
    let task: RoadmapTask
    let allTasks: [RoadmapTask]        // for status derivation + blocked-dep lookup
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var status: TaskStatus { RoadmapEngine.status(for: task, in: allTasks) }

    var body: some View {
        CodepetCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        Task { await companyStore.toggleTaskDone(id: task.id) }
                    } label: {
                        Image(systemName: task.done ? "checkmark.square.fill" : "square")
                            .foregroundColor(task.done ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    Text(task.title)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .strikethrough(task.done)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    tag(task.who.label(lang), color: CodepetTheme.mutedText)
                    tag(status.label(lang), color: statusTint(status))
                }
                if status == .codepetCanDo {
                    Button {
                        Task { await companyStore.runTask(task, language: lang) }
                    } label: {
                        HStack(spacing: 5) {
                            if companyStore.runningTaskIds.contains(task.id) {
                                ProgressView().controlSize(.mini)
                                Text(lang == .vi ? "Đang chạy…" : "Running…")
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 9))
                                Text(lang == .vi ? "Chạy" : "Run")
                            }
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                    }
                    .buttonStyle(.plain)
                    .disabled(companyStore.runningTaskIds.contains(task.id))
                }
                if status == .blocked, let dep = blockedAfter {
                    Text((lang == .vi ? "sau: " : "after: ") + dep)
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Title of the first not-done dependency (nil if none / dangling).
    private var blockedAfter: String? {
        for id in task.dependsOn {
            if let d = allTasks.first(where: { $0.id == id }), !d.done { return d.title }
        }
        return nil
    }

    private func statusTint(_ s: TaskStatus) -> Color {
        switch s {
        case .done:          return CodepetTheme.accentTeal
        case .codepetCanDo:  return CodepetTheme.accentPurple
        case .needsApproval: return CodepetTheme.accentGold
        case .needsYou:      return CodepetTheme.accentOrange
        case .blocked:       return CodepetTheme.mutedText
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.pixelSystem(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
