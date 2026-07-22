// codepet/Views/Company/DepartmentDetailView.swift
import SwiftUI

struct DepartmentDetailView: View {
    let deptKey: String
    let onBack: () -> Void
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var dept: Department? { DepartmentCatalog.find(deptKey) }
    private var tasks: [RoadmapTask] { companyStore.company.tasks.filter { $0.dept == deptKey } }
    private var left: Int { tasks.filter { !$0.done }.count }

    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        return AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(lang == .vi ? "Công ty" : "Company").font(.pixelSystem(size: 12))
                    }.foregroundColor(CodepetTheme.bodyText)
                }.buttonStyle(.plain)

                hero(d)
                Text(d.rationale).font(.pixelSystem(size: 13)).foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    CharacterImage(companyStore.company.companionId, size: 28)
                    Text(d.focus).font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(lang == .vi ? "Việc cần làm · còn \(left)/\(tasks.count)"
                                 : "What needs doing · \(left) of \(tasks.count) left")
                    .font(.pixelSystem(size: 12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                    .padding(.top, 4)
                if tasks.isEmpty {
                    Text(lang == .vi ? "Chưa có việc trong phòng ban này." : "No tasks in this department yet.")
                        .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                }
            }
            .padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private func hero(_ d: Department) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(d.coverAsset).resizable().scaledToFill().frame(height: 140).clipped()
            LinearGradient(colors: [.clear, d.accent.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 8) {
                Text(d.ab).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text(d.name).font(.pixelSystem(size: 18, weight: .bold)).foregroundColor(.white)
            }.padding(12)
        }
        .frame(height: 140).cornerRadius(14).clipped()
    }
}

/// Web-faithful department task card (mirrors DepartmentDetail.tsx TaskCard): title +
/// detail + status pill and ONE action button by state; done → a delivered row.
private struct DepartmentTaskCard: View {
    let task: RoadmapTask
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    private var status: TaskStatus { RoadmapEngine.status(for: task, in: companyStore.company.tasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.pixelSystem(size: 13, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                    if !task.detail.isEmpty {
                        Text(task.detail).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !task.done {
                    Text(status.label(lang)).font(.pixelSystem(size: 10, weight: .medium))
                        .foregroundColor(taskStatusTint(status))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(taskStatusTint(status).opacity(0.12)))
                }
            }
            if task.done {
                Text(lang == .vi ? "✓ Đã duyệt · đã giao" : "✓ Approved · delivered")
                    .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.accentTeal)
            } else {
                actionButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder private var actionButton: some View {
        let running = companyStore.runningTaskIds.contains(task.id)
        Button {
            Task { await companyStore.runTask(task, language: lang) }
        } label: {
            HStack(spacing: 5) {
                if running { ProgressView().controlSize(.mini) }
                Text(running ? (lang == .vi ? "Đang chạy…" : "Running…") : buttonLabel)
            }
            .font(.pixelSystem(size: 11, weight: .semibold))
            .foregroundColor(task.who == .you ? CodepetTheme.bodyText : .white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(task.who == .you
                ? AnyView(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                : AnyView(Capsule().fill(CodepetTheme.accentPurple)))
        }
        .buttonStyle(.plain)
        .disabled(status == .blocked || running)
    }

    private var buttonLabel: String {
        if task.drafted { return lang == .vi ? "Xem & duyệt" : "Review & approve" }
        switch task.who {
        case .you:   return lang == .vi ? "Hướng dẫn tôi" : "Walk me through it"
        case .draft: return lang == .vi ? "Codepet soạn giúp" : "Have Codepet draft it"
        case .does:  return lang == .vi ? "Codepet làm giúp" : "Have Codepet do it"
        }
    }
}
