// codepet/Views/Company/DepartmentDetailView.swift
import SwiftUI

/// `Department.coverAnchor` is `UnitPoint` (not `Alignment`) because `Department` conforms to
/// `Hashable` and `UnitPoint` does, while `Alignment` doesn't — but `.frame(alignment:)` takes
/// an `Alignment`, so this converts. Only `.center`/`.top`/`.bottom` are in play today (see
/// `Department.swift`'s `coverAnchor` doc), but this handles the full `UnitPoint` range.
private extension UnitPoint {
    var frameAlignment: Alignment {
        let h: HorizontalAlignment = x < 0.5 ? .leading : x > 0.5 ? .trailing : .center
        let v: VerticalAlignment = y < 0.5 ? .top : y > 0.5 ? .bottom : .center
        return Alignment(horizontal: h, vertical: v)
    }
}

struct DepartmentDetailView: View {
    let deptKey: String
    let onBack: () -> Void
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var dept: Department? { DepartmentCatalog.find(deptKey) }
    private var tasks: [RoadmapTask] { companyStore.company.tasks.filter { $0.dept == deptKey } }
    /// The reading column. The shell hands this view the whole window
    /// (`AppShellView.swift:130`), so uncapped the rationale runs ~150 characters. Follows
    /// `RoadmapView.swift:187`'s capped column, a little wider because task cards live in this one.
    private let column: CGFloat = 800

    private var doneCount: Int { tasks.filter(\.done).count }

    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        return AnyView(ScrollView {
            // Grouped spacing, not a uniform gap: identity / context / work must read as three
            // blocks. With one shared `spacing:` the section header floated midway between the
            // text above it and the list it labels.
            VStack(alignment: .leading, spacing: 0) {
                backLink.padding(.bottom, 16)
                hero(d).padding(.bottom, 18)
                Text(d.rationale)
                    .font(CodepetTheme.inter(16))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                if let pulse = departmentPulse(d, mine: tasks, all: companyStore.company.tasks,
                                               lang: lang) {
                    HStack(alignment: .center, spacing: 8) {
                        CharacterImage(companyStore.company.companionId, size: 22)
                        Text(pulse)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                }
                sectionHeader.padding(.top, 30).padding(.bottom, 10)
                if tasks.isEmpty {
                    Text(lang == .vi ? "Chưa có việc trong phòng ban này."
                                     : "No tasks in this department yet.")
                        .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    VStack(spacing: 10) {
                        ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                    }
                }
            }
            .frame(maxWidth: column, alignment: .leading)
            // 26 matches `CompanyView`'s list padding, so the back link and hero stop shifting
            // 6pt when you navigate in from a card.
            .padding(.horizontal, 26)
            .padding(.top, 22).padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private var backLink: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(lang == .vi ? "Công ty" : "Company").font(CodepetTheme.inter(13))
            }.foregroundColor(CodepetTheme.bodyText)
        }.buttonStyle(.plain)
    }

    /// The count is appended only when it carries information — "1 of 1 left" says nothing until
    /// something is done, so an untouched department just reads "WHAT NEEDS DOING".
    private var sectionHeader: some View {
        Text(headerText)
            .font(CodepetTheme.inter(12, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var headerText: String {
        let base = (lang == .vi ? "Việc cần làm" : "What needs doing").uppercased()
        guard doneCount > 0, doneCount < tasks.count else { return base }
        return base + (lang == .vi ? " · \(doneCount)/\(tasks.count) đã xong"
                                   : " · \(doneCount) of \(tasks.count) done")
    }

    /// 190pt in an 800 column is 4.2:1, so a 16:9 cover keeps roughly 76% of its height —
    /// the old 140pt strip was 6.9:1 and kept about 40%, cutting the subject out of every
    /// cover. The scrim is NEUTRAL on purpose: the accent used to flood it at 0.55, which
    /// muddied art it clashes with (Engineering's accent is blue over hot-pink art) and
    /// dimmed the title sitting on it. Identity moves to the badge instead.
    private func hero(_ d: Department) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                Image(d.coverAsset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: 190, alignment: d.coverAnchor.frameAlignment)
                    .clipped()
            }
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.40),
                .init(color: Color.black.opacity(0.72), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 9) {
                badge(d)
                Text(d.name)
                    .font(CodepetTheme.inter(30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(.white)
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The Company list card's badge treatment (`CompanyView.swift:137-142`), reused verbatim:
    /// with the scrim neutral this chip is the page's only carrier of the department's accent,
    /// and the two surfaces must agree on how a department is coloured.
    private func badge(_ d: Department) -> some View {
        Text(d.ab)
            .font(CodepetTheme.inter(11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "#0b0a12").opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(d.accent.opacity(0.34))))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1))
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
            } else {
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
            else { Task { await companyStore.runTask(task, language: lang) } }
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
