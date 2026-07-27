// codepet/Views/SecondBrain/SecondBrainPanel.swift
import SwiftUI

/// The Second Brain info rail — a panel of real Codepet data (deliverables/
/// tasks/decisions counts, active model + companion, the next move, per-department
/// topic counts), ported from the web SecondBrainPanel and fed by the pure SecondBrainData
/// aggregation. The "Do this next" row and each "Topics" row are tappable shortcuts into
/// that department (web parity: SecondBrainPanel's click-through rows), via `onOpenDept`.
/// The web Usage section and the Milestones row are omitted: native has no tracking/
/// LedgerEvent or stage-history to back them.
struct SecondBrainPanel: View {
    let data: SecondBrainData
    let lang: AppLanguage
    /// Opens the given department key (web parity: the "Do this next" + "Topics"
    /// rows are click-through shortcuts into Company, not dead-end labels).
    let onOpenDept: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                brainSection
                nextSection
                topicsSection
            }
            .padding(16)
            .frame(maxWidth: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
        }
    }

    private var statusSection: some View {
        section(lang == .vi ? "Trạng thái" : "Status") {
            row(lang == .vi ? "Sản phẩm" : "Deliverables", "\(data.deliverables)")
            row(lang == .vi ? "Việc đã xong" : "Tasks done", "\(data.tasksDone)")
            row(lang == .vi ? "Tổng số việc" : "Total tasks", "\(data.tasksTotal)")
            row(lang == .vi ? "Quyết định" : "Decisions", "\(data.decisions)")
        }
    }

    private var brainSection: some View {
        section(lang == .vi ? "Bộ não" : "Brain") {
            row(lang == .vi ? "Mô hình" : "Model", SecondBrainData.modelLabel)
            row(lang == .vi ? "Bạn đồng hành" : "Companion", data.companionName)
        }
    }

    private var nextSection: some View {
        section(lang == .vi ? "Làm điều này tiếp" : "Do this next") {
            if let t = data.nextTask {
                let row = VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let dept = data.nextDeptName {
                        Text(dept)
                            .font(CodepetTheme.inter(11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(CodepetTheme.accentBlue.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CodepetTheme.accentBlue.opacity(0.3), lineWidth: 1))

                if let dept = t.dept {
                    Button { onOpenDept(dept) } label: { row }.buttonStyle(.plain)
                } else {
                    row
                }
            } else {
                Text(lang == .vi ? "Bạn đã theo kịp mọi thứ." : "You're all caught up.")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            }
        }
    }

    private var topicsSection: some View {
        section(lang == .vi ? "Chủ đề" : "Topics") {
            if data.topics.isEmpty {
                Text(lang == .vi ? "Chưa có gì." : "Nothing yet.")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            } else {
                ForEach(data.topics) { t in
                    Button { onOpenDept(t.department.key) } label: {
                        HStack {
                            Text(t.department.name)
                                .font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.bodyText)
                            Spacer()
                            Text("\(t.count)")
                                .font(CodepetTheme.inter(12.5, weight: .semibold))
                                .foregroundColor(CodepetTheme.accentBlue)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.surface))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(CodepetTheme.inter(10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(CodepetTheme.mutedText)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.bodyText)
            Spacer()
            Text(v).font(CodepetTheme.inter(12.5, weight: .semibold))
                .foregroundColor(CodepetTheme.accentBlue)
        }
        .padding(.vertical, 3)
    }
}
