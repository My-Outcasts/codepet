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

    /// Sentence case on purpose — `SectionEyebrow` uppercases at render time.
    static func tasksLabel(left: Int, total: Int, lang: AppLanguage) -> String {
        lang == .vi ? "Việc cần làm · còn \(left)/\(total)"
                    : "What needs doing · \(left) of \(total) left"
    }

    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        // The skeleton is CompanyView's, deliberately: fixed header with
        // viewHeadPadding(), then a ScrollView whose content carries the shared
        // page rhythm and pageColumn(). Before this the page used padding(20) on
        // all four sides and never called pageColumn(), so its hero ran the full
        // width of the window while the roster that links to it capped at 1280.
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            DepartmentHeader(name: d.name, rationale: d.rationale, onBack: onBack)
                .viewHeadPadding()
            ScrollView {
                // spacing: 0 — every vertical gap comes from CodepetTokens.Space,
                // so this page cannot drift off the house rhythm again.
                VStack(alignment: .leading, spacing: 0) {
                    hero(d)
                    SectionEyebrow(Self.tasksLabel(left: left, total: tasks.count, lang: lang))
                    if tasks.isEmpty {
                        Text(lang == .vi ? "Chưa có việc trong phòng ban này." : "No tasks in this department yet.")
                            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                    } else {
                        VStack(spacing: CodepetTokens.Space.itemGap) {
                            ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                        }
                    }
                }
                .padding(.top, CodepetTokens.Space.headToBody)
                .padding(.horizontal, 26)
                .padding(.bottom, CodepetTokens.Space.pageBottom)
                .pageColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }

    /// A plain image band. The name, the two-letter badge and the accent
    /// gradient all came out when the masthead took over: the gradient existed
    /// only to make white text legible over the art, and with no text on the art
    /// it was tinting the image for nothing. The badge earns its place on the
    /// roster cover, where it marks otherwise unlabelled art — beside a
    /// spelled-out "Engineering" it is decoration.
    ///
    /// 104 rather than 140 because the band no longer holds a text block, and
    /// the shorter one keeps the first task card above the fold on a 900pt
    /// window. `.interpolation(.high)` matches the roster cover (CompanyView:133).
    private func hero(_ d: Department) -> some View {
        Image(d.coverAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(14)
    }
}

/// The masthead. Plain values rather than the store, so it carries no Firebase
/// dependency and can be rendered on its own.
///
/// The title/subtitle pair is CompanyView:51-59 exactly — 28pt semibold at
/// -0.5 tracking over 15pt muted, four points apart. The back link sits ten
/// points above it: it is a control, not decoration, so it survives the
/// no-decorative-icons rule, and pinning it outside the ScrollView keeps the
/// way out reachable on a six-task department.
private struct DepartmentHeader: View {
    let name: String
    let rationale: String
    let onBack: () -> Void
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(lang == .vi ? "Công ty" : "Company").font(CodepetTheme.inter(13))
                }
                .foregroundColor(CodepetTheme.bodyText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(CodepetTheme.inter(28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(rationale)
                    .font(CodepetTheme.inter(15))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Web-faithful department task card (mirrors DepartmentDetail.tsx TaskCard): title +
/// detail + status pill and ONE action button by state; done → a delivered row.
private struct DepartmentTaskCard: View {
    let task: RoadmapTask
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var openDeliverable: Deliverable?
    /// Set when tapping "Review & approve" — opens the draft-preview sheet (shared with
    /// the Tasks board) instead of approving blindly.
    @State private var previewTask: RoadmapTask?
    private var status: TaskStatus { RoadmapEngine.status(for: task, in: companyStore.company.tasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(CodepetTheme.cardTitle()).foregroundColor(CodepetTheme.primaryText)
                    if !task.detail.isEmpty {
                        Text(task.detail).font(CodepetTheme.cardDetail()).foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !task.done {
                    Text(status.label(lang)).font(CodepetTheme.inter(11, weight: .medium))
                        .foregroundColor(taskStatusTint(status))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(taskStatusTint(status).opacity(0.12)))
                }
            }
            if task.done {
                Button {
                    openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
                } label: {
                    Text(lang == .vi ? "✓ Đã duyệt · đã giao" : "✓ Approved · delivered")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.accentTeal)
                }
                .buttonStyle(.plain)
            } else if status != .blocked {
                // No action button on a blocked task — it had one, dimmed and unpressable
                // (`.disabled(status == .blocked)`), which is a dead affordance: it reads
                // as "there is something to do here, but not for you". There is nothing to
                // do until an earlier task lands, and the status pill above already says
                // so. Founder call, Aug 5, alongside the same clean-up on the Tasks board.
                actionButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(item: $previewTask) { TaskDraftPreview(taskId: $0.id) }
    }

    @ViewBuilder private var actionButton: some View {
        let running = companyStore.runningTaskIds.contains(task.id)
        Button {
            if status == .needsApproval { previewTask = task }
            else if task.who == .you { Task { await companyStore.walkThroughTask(task, language: lang) } }
            else { companyStore.proposeRun(task, language: lang) }
        } label: {
            HStack(spacing: 5) {
                if running { ProgressView().controlSize(.mini) }
                Text(running ? (lang == .vi ? "Đang chạy…" : "Running…") : buttonLabel)
            }
            .font(CodepetTheme.inter(12, weight: .semibold))
            .foregroundColor(task.who == .you ? CodepetTheme.bodyText : .white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(task.who == .you
                ? AnyView(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                : AnyView(Capsule().fill(CodepetTheme.accentPurple)))
        }
        .buttonStyle(.plain)
        // Only the TRANSIENT disable remains. A running task's dimmed pill plus its
        // spinner correctly reads as "working on it"; a blocked task simply has no
        // button now, so `.blocked` no longer belongs in this condition.
        .disabled(running)
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
