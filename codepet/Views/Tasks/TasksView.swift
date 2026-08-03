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
    /// web `.kb-dot` — Up next is a FIXED violet (byte's hue), not the companion
    /// accent, so the four lanes stay four distinct colours for every companion.
    var dot: Color {
        switch self {
        case .upNext:   return CodepetTokens.violet
        case .awaiting: return CodepetTokens.gold
        case .yourMove: return CodepetTokens.blue
        case .done:     return Color(hex: "#10B981")   // web's exact Done green
        }
    }
    /// web `.kb-col--<key>` lane fill.
    var laneTint: Color {
        switch self {
        case .upNext:   return CodepetTokens.violetTint
        case .awaiting: return CodepetTokens.goldTint
        case .yourMove: return CodepetTokens.blueTint
        case .done:     return CodepetTokens.tealTint
        }
    }
    /// web `.kb-col--<key>` lane border.
    var laneLine: Color {
        switch self {
        case .upNext:   return CodepetTokens.violetLine
        case .awaiting: return CodepetTokens.goldLine
        case .yourMove: return CodepetTokens.blueLine
        case .done:     return CodepetTokens.tealLine
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme
    @State private var openDeliverable: Deliverable?
    /// The awaiting-approval task whose draft is open in the preview sheet. Set by a
    /// tap on an Awaiting card; the sheet shows the draft + Revise/Approve controls.
    @State private var previewTask: RoadmapTask?

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // web `.vhead { padding: 22px 26px 0 }` — 28px/650 title, 15px sub
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Nhiệm vụ" : "Tasks")
                    .font(CodepetTheme.inter(28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Việc \(companionName) đang làm, đang soạn, hoặc đang chờ bạn."
                                 : "What \(companionName) is doing, drafting, or waiting on you for.")
                    .font(CodepetTheme.inter(15)).foregroundColor(CodepetTheme.mutedText)
            }
            .viewHeadPadding()

            // web `.kb-board { gap: 14px; padding: 14px 26px 18px }` — lanes are equal
            // columns that fill the height; each scrolls its own list.
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskColumn.allCases, id: \.self) { col in column(col) }
            }
            .padding(.top, 14).padding(.horizontal, 26).padding(.bottom, 18)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(item: $previewTask) { TaskDraftPreview(taskId: $0.id) }
    }

    private func tasks(in col: TaskColumn) -> [RoadmapTask] {
        companyStore.company.tasks.filter { TaskColumn.column(for: $0, in: companyStore.company.tasks) == col }
    }

    /// One swimlane — web `.kb-col`: a tinted, hairlined 14pt-radius column with a
    /// fixed head (dot + uppercase label + count badge) over its own scrolling list.
    private func column(_ col: TaskColumn) -> some View {
        let items = tasks(in: col)
        return VStack(alignment: .leading, spacing: 0) {
            // web `.kb-colhead { padding: 13px 14px 11px; gap: 8px }`
            HStack(spacing: 8) {
                Circle().fill(col.dot).frame(width: 8, height: 8)
                Text(col.label(lang).uppercased())
                    .font(CodepetTheme.inter(11.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(1)
                // web `.kb-count` — white on a --t-4 pill, not plain grey text
                Text("\(items.count)")
                    .font(CodepetTheme.inter(10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 1.5)
                    .background(Capsule().fill(CodepetTokens.faint))
                    .fixedSize()
            }
            .padding(.top, 13).padding(.horizontal, 14).padding(.bottom, 11)

            // web `.kb-list { gap: 10px; padding: 2px 12px 14px; overflow-y: auto }`
            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        Text(lang == .vi ? "Trống" : "Nothing here")
                            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTokens.faint)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(items) { t in card(t) }
                    }
                }
                .padding(.top, 2).padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(col.laneTint))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(col.laneLine, lineWidth: 1))
    }

    private func card(_ t: RoadmapTask) -> some View {
        Button {
            let st = RoadmapEngine.status(for: t, in: companyStore.company.tasks)
            let action = RoadmapDispatch.action(for: st,
                                                isEngineering: t.dept == "eng",
                                                projectLinked: companyStore.activeProjectLink != nil)
            switch action {
            case .approve:         previewTask = t   // the board reviews via a preview sheet
            case .run:             Task { await companyStore.runTask(t, language: lang) }
            case .walkThrough:     Task { await companyStore.walkThroughTask(t, language: lang) }
            case .openDeliverable: openDeliverable = RoadmapEngine.deliverable(for: t, in: companyStore.company.library)
            case .editCode:
                companyStore.codingRunAnchorId = nil   // no chat ask → card at transcript bottom
                companyStore.codingRun.propose(ask: RoadmapDispatch.editCodeAsk(for: t),
                                               plannedFiles: 2, needsBash: false,
                                               link: companyStore.activeProjectLink)
                // Only the new engineering + linked-project path reveals the copilot;
                // ordinary run/walkThrough/approve/open taps keep their pre-existing
                // in-place behaviour on the Tasks board. The copilot is the docked
                // panel now (not a `.chat` destination), so expand the dock.
                companyStore.dockCollapsed = false
            case .showBlocker:     break   // Tasks board has no redirect path; unchanged from prior no-op
            case .none:            break
            }
        } label: {
            // web `.kb-card { radius 12; padding 12px 13px 13px }` — the DEPARTMENT
            // leads in full ink (.kb-dept, 700) and the task is the supporting line
            // (.kb-title, 500, --t-3); native had the two reversed.
            VStack(alignment: .leading, spacing: 3) {
                if let d = DepartmentCatalog.find(t.dept)?.name {
                    Text(d)
                        .font(CodepetTheme.inter(12.5, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                }
                Text(t.title)
                    .font(CodepetTheme.inter(12.5, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineSpacing(12.5 * 0.34)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12).padding(.horizontal, 13).padding(.bottom, 13)
            .cardChrome(radius: 12, dark: scheme == .dark)
        }
        .buttonStyle(.plain)
    }
}
