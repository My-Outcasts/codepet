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
        // "To approve", not "Awaiting your approval": the long form wrapped the lane header
        // (6 Oct design pass).
        case .awaiting: return lang == .vi ? "Chờ duyệt" : "To approve"
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

/// The board's words and limits (6 Oct design pass, mock approved). Pure so the rules are pinned.
enum TaskBoard {
    /// Cards a lane shows before "N more".
    static let cap = 6

    static func visible(count: Int, expanded: Bool) -> Int { expanded ? count : min(count, cap) }

    static func moreLabel(hidden: Int, lang: AppLanguage) -> String {
        lang == .vi ? "Thêm \(hidden)" : "\(hidden) more"
    }

    /// What a waiting card is waiting for, in words: its first unfinished dependency by title, in
    /// `dependsOn` order, plus how many more. Replaces the "Needs earlier steps" pill, which said
    /// THAT a card was blocked on every one of 16 cards and never by WHAT. A dependency id that is
    /// not on the board is not something to wait for, so it is skipped rather than counted.
    static func waitingLine(_ task: RoadmapTask, in tasks: [RoadmapTask], lang: AppLanguage) -> String? {
        let open = task.dependsOn.compactMap { id in tasks.first { $0.id == id } }.filter { !$0.done }
        guard let first = open.first else { return nil }
        let name = "\u{201C}\(first.title)\u{201D}"
        let rest = open.count - 1
        if rest == 0 { return lang == .vi ? "Sau \(name)" : "After \(name)" }
        return lang == .vi ? "Sau \(name) và \(rest) bước khác" : "After \(name) and \(rest) more"
    }

    /// An empty lane says what goes there, not "Nothing here".
    static func emptyText(_ col: TaskColumn, lang: AppLanguage) -> String {
        let vi = lang == .vi
        switch col {
        case .upNext:   return vi ? "Chưa có việc nào" : "Nothing queued"
        case .awaiting: return vi ? "Bản nháp sẽ nằm ở đây chờ bạn duyệt" : "Drafts land here for your OK"
        case .yourMove: return vi ? "Không có gì cần bạn lúc này" : "Nothing needs you right now"
        case .done:     return vi ? "Chưa có gì xong" : "Nothing finished yet"
        }
    }

    /// The action a card leads to, shown on the card so it reads as something to press. Nil for a
    /// waiting card, which has nothing to press.
    static func actionLabel(_ status: TaskStatus, lang: AppLanguage) -> String? {
        let vi = lang == .vi
        switch status {
        case .needsYou:      return vi ? "Hướng dẫn mình" : "Walk me through it"
        case .codepetCanDo:  return vi ? "Chạy" : "Run it"
        case .needsApproval: return vi ? "Xem bản nháp" : "Review the draft"
        case .blocked, .done: return nil
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
    /// Lanes the founder opened past `TaskBoard.cap`.
    @State private var expanded: Set<String> = []


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // web `.vhead { padding: 22px 26px 0 }` — 28px/650 title, 15px sub
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Nhiệm vụ" : "Tasks")
                    .font(CodepetTheme.inter(28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Việc Codepet đang làm, đang soạn, hoặc đang chờ bạn."
                                 : "What Codepet is doing, drafting, or waiting on you for.")
                    .font(CodepetTheme.inter(15)).foregroundColor(CodepetTheme.mutedText)
            }
            .viewHeadPadding()

            // web `.kb-board { gap: 14px; padding: 14px 26px 18px }` — lanes are equal
            // columns that fill the height; each scrolls its own list.
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskColumn.allCases, id: \.self) { col in column(col) }
            }
            .padding(.top, CodepetTokens.Space.headToBody).padding(.horizontal, 26).padding(.bottom, CodepetTokens.Space.pageBottom)
            .pageColumn()
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(item: $previewTask) { TaskDraftPreview(taskId: $0.id) }
    }

    private func tasks(in col: TaskColumn) -> [RoadmapTask] {
        companyStore.company.tasks.filter { TaskColumn.column(for: $0, in: companyStore.company.tasks) == col }
    }

    /// One lane. Since the 6 Oct design pass the lane keeps its colour but softly: a faint wash and
    /// a thin edge of its hue instead of the full tint and line, a full-colour dot by its name, and
    /// the count as plain text on the right instead of a filled badge.
    private func column(_ col: TaskColumn) -> some View {
        let items = tasks(in: col)
        let key = col.label(.en)
        let shown = TaskBoard.visible(count: items.count, expanded: expanded.contains(key))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(col.dot).frame(width: 7, height: 7)
                Text(col.label(lang).uppercased())
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(items.count)")
                    .font(CodepetTheme.inter(11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.top, 14).padding(.horizontal, 15).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text(TaskBoard.emptyText(col, lang: lang))
                            .font(CodepetTheme.inter(12))
                            .foregroundColor(col.dot.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18).padding(.horizontal, 10)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(col.dot.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    } else {
                        ForEach(items.prefix(shown)) { t in card(t) }
                        if shown < items.count || expanded.contains(key) && items.count > TaskBoard.cap {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                                }
                            } label: {
                                Text(expanded.contains(key) ? (lang == .vi ? "Thu gọn" : "Show fewer")
                                                            : TaskBoard.moreLabel(hidden: items.count - shown, lang: lang))
                                    .font(CodepetTheme.inter(12, weight: .medium))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .cursorOnHover(.pointingHand)
                        }
                    }
                }
                .padding(.top, 0).padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(col.dot.opacity(scheme == .dark ? 0.06 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(col.dot.opacity(scheme == .dark ? 0.16 : 0.2), lineWidth: 1))
    }

    private func card(_ t: RoadmapTask) -> some View {
        let status = RoadmapEngine.status(for: t, in: companyStore.company.tasks)
        // A blocked card is NOT a disabled control — it is a card with nothing to tap.
        //
        // It used to be a `Button` with `.disabled(status == .blocked)`, and SwiftUI dims
        // a disabled button's whole label: the department name, the task line AND the
        // status pill all lost contrast at once, stacked on an already-dark card, until
        // the entire "Up next" lane read as switched off (founder, Aug 5). Same defect
        // class as the collapsed phase rails.
        //
        // Rendering it as a plain view keeps full contrast and still cannot be tapped —
        // and it is the honest structure, since `.showBlocker` is a no-op on this board.
        // "Locked" is carried by the "Needs earlier steps" pill and the absence of any
        // hover affordance, not by draining the card of ink.
        if status == .blocked { return AnyView(cardBody(t, status: status)) }
        return AnyView(Button {
            let action = RoadmapDispatch.action(for: status,
                                                isEngineering: t.dept == "eng",
                                                projectLinked: companyStore.activeProjectLink != nil)
            switch action {
            case .approve:         previewTask = t   // the board reviews via a preview sheet
            // Proposes rather than runs: the run plays in the copilot as the full execute-log,
            // after the founder confirms it there. Web parity, Aug 6.
            case .run:             companyStore.proposeRun(t, language: lang)
            case .walkThrough:     Task { await companyStore.walkThroughTask(t, language: lang) }
            case .openDeliverable: openDeliverable = RoadmapEngine.deliverable(for: t, in: companyStore.company.library)
            case .editCode:
                companyStore.codingRunAnchorId = nil   // no chat ask → card at transcript bottom
                companyStore.codingRun.propose(ask: RoadmapDispatch.editCodeAsk(for: t),
                                               plannedFiles: 2, needsBash: false,
                                               link: companyStore.activeProjectLink)
                // Reveal the conversation the coding run is proposed in. `revealConversation`
                // opens the dock in the legacy shell and moves to `.chat` in the two-mode
                // shell, which has no dock. (`.run` reveals inside `proposeRun`.)
                companyStore.revealConversation()
            case .showBlocker:     break   // Tasks board has no redirect path; unchanged from prior no-op
            case .none:            break
            }
        } label: {
            cardBody(t, status: status)
        }
        .buttonStyle(.plain))
    }

    /// The card (6 Oct design pass): the department's pet and name small and grey, then the task in
    /// full ink, then either what it waits for or what pressing it does. The bold department
    /// heading and the status pill are gone — the pill said "Needs earlier steps" on 16 cards in a
    /// row and never what they needed.
    private func cardBody(_ t: RoadmapTask, status: TaskStatus) -> some View {
        let waiting = status == .blocked
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if let dept = t.dept { TeamPetAvatar(dept: dept, size: 15) }
                Text(DepartmentCatalog.find(t.dept)?.name ?? "")
                    .font(CodepetTheme.inter(11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(1)
            }
            Text(t.title)
                .font(CodepetTheme.inter(13))
                .foregroundColor(waiting ? CodepetTheme.mutedText : CodepetTheme.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if waiting, let line = TaskBoard.waitingLine(t, in: companyStore.company.tasks, lang: lang) {
                Text(line)
                    .font(CodepetTheme.inter(11.5))
                    .foregroundColor(CodepetTokens.faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else if !t.done, let action = TaskBoard.actionLabel(status, lang: lang) {
                Text(action)
                    .font(CodepetTheme.inter(11.5, weight: .semibold))
                    .foregroundColor(taskStatusTint(status))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 11).padding(.horizontal, 12).padding(.bottom, 12)
        .cardChrome(radius: 12, dark: scheme == .dark)
    }
}
