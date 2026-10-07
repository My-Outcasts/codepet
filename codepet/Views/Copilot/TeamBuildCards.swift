// codepet/Views/Copilot/TeamBuildCards.swift
import SwiftUI
import AppKit

// MARK: - Pure helpers

/// The composer's "Team build" button: when it may be pressed, and what it says. Pure so the
/// suite can pin the gate — the view only reads it.
enum TeamBuildButton {
    /// A non-blank draft, no turn in flight, and the store says a run may start
    /// (`CompanyStore.teamBuildAvailable`: grant held, demo off, no run active or planning).
    static func isEnabled(draft: String, busy: Bool, available: Bool) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy && available
    }

    static func label(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cả đội làm" : "Team build"
    }

    /// Says where the tokens come from: a Team Build spends the founder's own Claude plan, and
    /// a button that spends someone's quota should say so before it is pressed.
    static func help(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Cả đội lập kế hoạch và làm thành một project thật. Chạy trên gói Claude của bạn."
            : "The whole team plans and builds this into a real project. Runs on your Claude plan."
    }
}

/// Copy for the team card and its detail panel.
enum TeamBuildCopy {
    /// Said when a Team build's room ends with a two-way call (7 Oct): nothing is planned until the
    /// founder picks, because a plan made first had led with the option she then turned down.
    static func awaitingCall(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chọn một trong hai hướng ở trên — kế hoạch sẽ theo lựa chọn của bạn."
                    : "Pick one of the two options above — the plan follows your call."
    }

    /// The row shown while a Team Build's router picks who joins the room (CP-027). Says only what
    /// is true at that moment: nobody has started work yet, so it names the choosing, not a team.
    static func conveningTitle(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang gọi cả đội" : "Gathering the team"
    }

    /// What chat is sent when Team build is pressed, in place of the bare request (6 Oct). The
    /// chat turn runs beside the room, and with the bare request it answered as if nothing else
    /// were happening: "I can't build that from this chat" or "I've put it up as an offer", while
    /// the team went on to build it. It now knows the team has it, so the reply is a short note
    /// alongside the build, not a refusal or an `add_task` offer. Her words ride at the end, the
    /// way `ChatMode.plan` frames a turn; her bubble and the room's question keep them unframed
    /// (`sendChat`'s `founderAsk`).
    static func chatFrame(_ text: String, lang: AppLanguage) -> String {
        lang == .vi
            ? "Mình vừa bấm Cả đội làm: các phòng ban đang họp và sẽ lập kế hoạch rồi làm thành một project thật để mình duyệt. Đừng từ chối và do not offer nó thành một task trên roadmap. Trả lời ngắn (1–2 câu): xác nhận cả đội đang làm, và nêu một điều cả đội nên lưu ý nếu có. Yêu cầu: \(text)"
            : "I just pressed Team build: the departments are meeting on this now and will plan it and build it into a real project for me to approve. Don't say you can't build it, and do not offer it as a roadmap task. Reply in one or two sentences: confirm the team is on it, and name one thing they should keep in mind, if there is one. The request: \(text)"
    }

    static func conveningDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang chọn ai sẽ góp ý, thường khoảng một phút"
                    : "Choosing who should weigh in, usually about a minute"
    }

    /// A step's status pill. A running step shows its elapsed time (`m:ss`) instead of a word —
    /// the one thing a founder watching a 3-minute step wants to know is that it is still moving.
    static func status(_ s: TeamStepStatus, elapsed: TimeInterval?, lang: AppLanguage) -> String {
        let vi = lang == .vi
        switch s {
        case .waiting:     return vi ? "Chờ" : "Waiting"
        case .running:     return clock(elapsed ?? 0)
        case .done:        return vi ? "Xong" : "Done"
        case .failed:      return vi ? "Lỗi" : "Failed"
        case .blocked:     return vi ? "Bị chặn" : "Blocked"
        case .cancelled:   return vi ? "Đã dừng" : "Cancelled"
        case .interrupted: return vi ? "Bị gián đoạn" : "Interrupted"
        }
    }

    /// The muted line under a dependent step.
    static func waitsFor(_ names: [String], lang: AppLanguage) -> String {
        let list = names.joined(separator: ", ")
        return lang == .vi ? "chờ \(list)" : "waits for \(list)"
    }

    static func clock(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func deptName(_ key: String) -> String {
        DepartmentCatalog.find(key)?.name ?? key
    }

    /// The "not saved yet" line under a ready project's Approve, or nil once the founder has
    /// approved anything. Same one-time lesson as the draft card, through the same decision
    /// (`DraftCardCopy.shouldShowNotFiledNote`): this footer used to print it unconditionally,
    /// so a founder who had filed ten drafts was still told what Approve does (build 6, bug #6).
    /// `draftApproved` is false because the footer only exists before Approve (`.ready`).
    static func readyNote(hasApproved: Bool, _ lang: AppLanguage) -> String? {
        DraftCardCopy.shouldShowNotFiledNote(hasApproved: hasApproved, draftApproved: false)
            ? DraftCardCopy.notFiledNote(lang) : nil
    }

    /// Department names of `step`'s dependencies, in `dependsOn` order, each once — the build
    /// step depends on every department step, and two Marketing steps should not read
    /// "Marketing, Marketing".
    static func dependencyNames(_ step: WorkStep, in plan: WorkPlan) -> [String] {
        var seen = Set<String>()
        return step.dependsOn.compactMap { id in plan.steps.first { $0.id == id } }
            .map { deptName($0.dept) }
            .filter { seen.insert($0).inserted }
    }
}

// MARK: - Shared bits

/// A department's pet, drawn the way pixel art is always drawn here: nearest-neighbour.
struct TeamPetAvatar: View {
    let dept: String
    var size: CGFloat = 20

    var body: some View {
        if let id = DepartmentCompanions.companionId(for: dept), let pet = PetCharacter.all[id] {
            Image(pet.imageName)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Circle().fill(CodepetTheme.accentPurple.opacity(0.25)).frame(width: size, height: size)
        }
    }
}

private struct TeamStatusPill: View {
    let status: TeamStepStatus
    let text: String

    var body: some View {
        let fg: Color
        switch status {
        case .waiting, .cancelled: fg = CodepetTheme.mutedText
        case .running:             fg = CodepetTheme.accentPurple
        case .done:                fg = CodepetTheme.accentTeal
        case .failed:              fg = Color.red
        case .blocked, .interrupted: fg = CodepetTheme.accentGold
        }
        return Text(text)
            .font(CodepetTheme.inter(9, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(fg.opacity(0.15)))
            .fixedSize()
    }
}

private func elapsed(_ state: TeamStepState?, now: Date) -> TimeInterval? {
    guard let start = state?.startedAt else { return nil }
    return (state?.finishedAt ?? now).timeIntervalSince(start)
}

/// A small house button. `.primary` is the one solid accent on a card; `.secondary` is outlined;
/// `.quiet` is text only — Cancel and Stop, which must stay one click away without competing
/// with the action the card is asking for.
private struct TeamCardButton: View {
    enum Style { case primary, secondary, quiet }
    let title: String
    var style: Style = .secondary
    let action: () -> Void

    init(title: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.style = primary ? .primary : .secondary; self.action = action
    }

    init(title: String, style: Style, action: @escaping () -> Void) {
        self.title = title; self.style = style; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(12.5, weight: style == .quiet ? .medium : .semibold))
                .foregroundColor(style == .primary ? .white
                                 : style == .quiet ? CodepetTheme.mutedText : CodepetTheme.primaryText)
                .padding(.horizontal, style == .quiet ? 2 : 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(style == .primary ? CodepetTheme.accentPurple : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(style == .secondary ? CodepetTheme.hairline : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursorOnHover(.pointingHand)
        .fixedSize()
    }
}

/// The card's surface (6 Oct design pass): the plain surface with a hairline, not
/// `MessageCard`'s purple tint and purple border. The accent is kept for what is live now — the
/// running step, its clock, the one primary button — so it means something when it appears.
struct TeamQuietSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CodepetTheme.hairline, lineWidth: 1))
    }
}

// MARK: - Team card

/// The one card a Team Build lives in, from plan to filed. Which footer it shows is decided by
/// `run.phase`. The plan reads as stages — First / Then / Last (`TeamPlanStages`) — and the same
/// layout carries progress once it runs, so expanding a running card shows nothing new to learn.
struct TeamRunCard: View {
    @ObservedObject var coordinator: TeamRunCoordinator
    let onSelect: (String) -> Void

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    /// "See all N steps" on a compacted card (CP-033).
    @State private var showAllSteps = false
    /// The project's file list, behind ••• on a finished card.
    @State private var showFiles = false

    var body: some View {
        if let run = coordinator.run {
            HStack {
                TeamQuietSurface { card(run) }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card(_ run: TeamRun) -> some View {
        let compact = TeamProgress.compacts(run.phase)
        let stopped = run.phase == .cancelled
        let finished = run.phase == .ready || run.phase == .filed
        return VStack(alignment: .leading, spacing: 0) {
            header(run)
            if let sub = subline(run) {
                Text(sub)
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(showAllSteps ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            // Only the rows tick; the footer (which reads the disk on `.ready`) does not. A
            // finished card with its steps folded has nothing here, and must not keep the gap.
            if !finished || showAllSteps {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    if compact && !finished {
                        progressSummary(run, now: context.date)
                    } else if stopped {
                        // What happened, not six "Cancelled" marks (CP-034).
                        Text(TeamBuildCopy.stoppedSummary(run, lang: lang))
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !(compact || stopped) || showAllSteps {
                        stages(run, now: context.date)
                    }
                    if run.phase == .assembling, !showAllSteps {
                        buildActivity
                    }
                }
                .padding(.top, 14)
            }
            }
            if (compact && !finished) || stopped {
                disclosure(TeamBuildCopy.allSteps(run.plan.steps.count, expanded: showAllSteps, lang: lang))
                    .padding(.top, 12)
            }
            footer(run)
        }
    }

    // MARK: Head

    private func header(_ run: TeamRun) -> some View {
        let vi = lang == .vi
        let done = run.steps.filter { $0.status == .done }.count
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(run.plan.title)
                .font(CodepetTheme.inter(15, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            switch run.phase {
            case .planned:
                EmptyView()
            case .ready:
                Text(vi ? "Đã xong" : "Ready")
                    .font(CodepetTheme.inter(12.5, weight: .medium))
                    .foregroundColor(CodepetTheme.accentTeal)
            case .filed:
                Text(vi ? "Đã thêm vào Thư viện" : "Added to Library")
                    .font(CodepetTheme.inter(12.5, weight: .medium))
                    .foregroundColor(CodepetTheme.accentTeal)
            case .running, .assembling, .failed, .cancelled:
                Text(vi ? "\(done)/\(run.plan.steps.count) bước" : "\(done) of \(run.plan.steps.count)")
                    .font(CodepetTheme.inter(12.5))
                    .monospacedDigit()
                    .foregroundColor(CodepetTheme.mutedText)
                if run.phase == .running || run.phase == .assembling {
                    TeamCardButton(title: vi ? "Dừng" : "Stop", style: .quiet) { companyStore.stopTeamRun() }
                }
            }
        }
    }

    /// The line under the title: the founder's own words while they decide, and what happened
    /// once it is built. Nothing while it runs — the live line says more than a restated plan.
    /// The planner's summary is no longer shown: it is system prose ("With no room decision, …
    /// planned directly from the founder's request", build 8).
    private func subline(_ run: TeamRun) -> String? {
        switch run.phase {
        case .planned:
            let ask = run.request.trimmingCharacters(in: .whitespacesAndNewlines)
            return ask.isEmpty ? nil : ask
        case .ready, .filed:
            return TeamBuildCopy.readySummary(run, lang: lang)
        default:
            return nil
        }
    }

    // MARK: Progress

    /// The compacted card's head (CP-033): a thin bar, who is working now with its clock, and what
    /// comes next. Clicking the live line opens that step's detail.
    @ViewBuilder private func progressSummary(_ run: TeamRun, now: Date) -> some View {
        let p = TeamProgress(run)
        Capsule()
            .fill(CodepetTheme.mutedText.opacity(0.18))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(CodepetTheme.accentPurple)
                        .frame(width: max(6, g.size.width * CGFloat(p.doneCount) / CGFloat(max(1, p.total))))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(lang == .vi ? "\(p.doneCount) trên \(p.total) bước xong"
                                            : "\(p.doneCount) of \(p.total) steps done")
        if !p.current.isEmpty {
            Button { if let s = p.current.first { onSelect(s.id) } } label: {
                HStack(spacing: 10) {
                    TeamPulseDot()
                    liveText(p)
                        .font(CodepetTheme.inter(13.5))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    if p.current.count == 1, let s = p.current.first {
                        Text(TeamBuildCopy.clock(elapsed(run.state(s.id), now: now) ?? 0))
                            .font(CodepetTheme.inter(12.5))
                            .monospacedDigit()
                            .foregroundColor(CodepetTheme.accentPurple)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverAffordance(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        if let next = TeamBuildCopy.nextLine(p, lang: lang) {
            Text(next)
                .font(CodepetTheme.inter(12.5))
                .foregroundColor(CodepetTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 18)
        }
    }

    /// "**Engineering**  Booking flow and pickup-code spec" for one step; the counted form from
    /// `liveLine` when several run at once.
    private func liveText(_ p: TeamProgress) -> Text {
        if p.current.count == 1, let s = p.current.first {
            return Text(TeamBuildCopy.deptName(s.dept)).fontWeight(.semibold) + Text("  " + s.title)
        }
        return Text(TeamBuildCopy.liveLine(p, lang: lang) ?? "")
    }

    /// The build step can run for 15 minutes; its last few actions are shown on the card itself
    /// so the founder sees it moving without opening the step's detail.
    private var buildActivity: some View {
        let lines = Array(coordinator.buildLog.suffix(4))
        return VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty {
                Text(lang == .vi ? "Đang đọc tài liệu của cả đội…" : "Reading the team's docs…")
                    .font(CodepetTheme.inter(11.5)).foregroundColor(CodepetTheme.mutedText)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(i == lines.count - 1 ? CodepetTheme.bodyText : CodepetTheme.mutedText)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.leading, 18)
    }

    // MARK: Stages

    /// The plan as First / Then / Last, each stage a column of one-line steps behind a hairline.
    /// Before a run starts each step shows its pet; once it runs, its status mark.
    private func stages(_ run: TeamRun, now: Date) -> some View {
        let groups = TeamPlanStages.group(run.plan)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, steps in
                HStack(alignment: .top, spacing: 10) {
                    if let label = TeamPlanStages.label(i, of: groups.count, lang: lang) {
                        Text(label.uppercased())
                            .font(CodepetTheme.inter(10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(CodepetTheme.mutedText)
                            .frame(width: 50, alignment: .leading)
                            .padding(.top, 5)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(steps) { step in row(step, run: run, now: now) }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
                    }
                }
            }
        }
    }

    private func row(_ step: WorkStep, run: TeamRun, now: Date) -> some View {
        let state = run.state(step.id)
        let status = state?.status ?? .waiting
        let before = run.phase == .planned
        return Button { onSelect(step.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 10) {
                    if before {
                        TeamPetAvatar(dept: step.dept, size: 18)
                    } else {
                        statusMark(status).frame(width: 18, height: 18)
                    }
                    (Text(step.title)
                        .font(CodepetTheme.inter(13.5, weight: status == .running ? .medium : .regular))
                        .foregroundColor(titleColor(status, before: before))
                     + Text("  " + TeamBuildCopy.deptName(step.dept))
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    trailing(status, state: state, now: now)
                }
                if case .failed(let reason) = status {
                    Text(reason)
                        .font(CodepetTheme.inter(11.5))
                        .foregroundColor(Color.red)
                        .padding(.leading, 28)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverAffordance(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func titleColor(_ s: TeamStepStatus, before: Bool) -> Color {
        if before { return CodepetTheme.primaryText }
        switch s {
        case .running, .failed, .blocked, .interrupted: return CodepetTheme.primaryText
        case .done: return CodepetTheme.bodyText
        case .waiting, .cancelled: return CodepetTheme.mutedText
        }
    }

    @ViewBuilder private func statusMark(_ s: TeamStepStatus) -> some View {
        switch s {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(CodepetTheme.accentTeal)
        case .running:
            TeamPulseDot()
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
        case .blocked, .interrupted:
            Image(systemName: "pause.fill").font(.system(size: 8)).foregroundColor(CodepetTheme.accentGold)
        case .waiting, .cancelled:
            Circle().fill(CodepetTheme.mutedText.opacity(0.5)).frame(width: 4, height: 4)
        }
    }

    /// Time for a step that has some — accent while it runs, muted once done — and a word only
    /// where a word is news (failed, blocked, interrupted). Waiting says nothing: before this,
    /// six identical "Waiting" pills said it six times.
    @ViewBuilder private func trailing(_ s: TeamStepStatus, state: TeamStepState?, now: Date) -> some View {
        switch s {
        case .running, .done:
            if let t = elapsed(state, now: now) {
                Text(TeamBuildCopy.clock(t))
                    .font(CodepetTheme.inter(12))
                    .monospacedDigit()
                    .foregroundColor(s == .running ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }
        case .failed, .blocked, .interrupted:
            TeamStatusPill(status: s, text: TeamBuildCopy.status(s, elapsed: nil, lang: lang))
        case .waiting, .cancelled:
            EmptyView()
        }
    }

    private func disclosure(_ title: String) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { showAllSteps.toggle() } } label: {
            Text(title)
                .font(CodepetTheme.inter(12.5, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
                .underline(color: CodepetTheme.hairline)
        }
        .buttonStyle(.plain)
        .cursorOnHover(.pointingHand)
    }

    // MARK: Footer

    @ViewBuilder private func footer(_ run: TeamRun) -> some View {
        let vi = lang == .vi
        let interrupted = run.steps.contains { $0.status == .interrupted }
        switch run.phase {
        case .planned:
            footerRow {
                Text(vi ? "\(run.plan.steps.count) bước · chạy trên gói Claude của bạn"
                        : "\(run.plan.steps.count) steps · runs on your Claude plan")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                Spacer(minLength: 8)
                TeamCardButton(title: vi ? "Huỷ" : "Cancel", style: .quiet) { companyStore.cancelTeamPlan() }
                TeamCardButton(title: vi ? "Bắt đầu làm" : "Start building", primary: true) {
                    Task { await companyStore.confirmTeamPlan(language: lang) }
                }
            }
        case .running, .assembling:
            // Stop lives in the header; only an interrupted run needs a button here.
            if interrupted {
                HStack(spacing: 8) { continueButton }.padding(.top, 14)
            }
        case .failed:
            WrapLayout(spacing: 8, rowSpacing: 8) {
                ForEach(run.plan.steps.filter { step in
                    if case .failed = run.state(step.id)?.status { return true }
                    return false
                }) { step in
                    TeamCardButton(title: (vi ? "Thử lại " : "Retry ") + TeamBuildCopy.deptName(step.dept),
                                   primary: true) {
                        Task { await companyStore.retryTeamStep(step.id, language: lang) }
                    }
                }
                if interrupted { continueButton }
                TeamCardButton(title: vi ? "Dừng" : "Stop", style: .quiet) { companyStore.stopTeamRun() }
            }
            .padding(.top, 14)
        case .ready:
            if let path = run.projectPath { finishedFooter(path, approved: false) }
        case .filed:
            // The project is the deliverable, so filing it must not take away the way into it —
            // before this, the only route back was Library ▸ Engineering ▸ the entry ▸ Finder.
            if let path = run.projectPath, FileManager.default.fileExists(atPath: path) {
                finishedFooter(path, approved: true)
            }
        case .cancelled:
            HStack(spacing: 8) {
                if interrupted { continueButton }
                TeamCardButton(title: vi ? "Bỏ lượt này" : "Discard") {
                    Task { await companyStore.discardTeamRun() }
                }
            }
            .padding(.top, 14)
        }
    }

    private func footerRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
            HStack(spacing: 14) { content() }.padding(.top, 12)
        }
        .padding(.top, 16)
    }

    private var continueButton: some View {
        TeamCardButton(title: lang == .vi ? "Tiếp tục" : "Continue", primary: true) {
            Task { await companyStore.continueTeamRun(language: lang) }
        }
    }

    /// A finished run leads with seeing the page (founder decision, 6 Oct), Approve beside it until
    /// it is filed. Finder, Claude Code and the raw file list are one menu away — the build-8 card
    /// printed the whole tree, `node_modules/` and `tsconfig.json` included, above four equal
    /// buttons.
    private func finishedFooter(_ path: String, approved: Bool) -> some View {
        let vi = lang == .vi
        let url = URL(fileURLWithPath: path)
        let index = url.appendingPathComponent("index.html")
        let primary = TeamReadyAction.primary(isNodeProject: TeamProjectLauncher.isNodeProject(path),
                                              hasIndexHTML: FileManager.default.fileExists(atPath: index.path))
        return VStack(alignment: .leading, spacing: 10) {
            if showFiles { fileList(path).padding(.top, 14) }
            footerRow {
                disclosure(showAllSteps ? TeamBuildCopy.allSteps(0, expanded: true, lang: lang)
                                        : (vi ? "Xem từng phòng ban đã làm gì" : "See what each department made"))
                Spacer(minLength: 8)
                Menu {
                    Button(vi ? "Mở trong Finder" : "Open in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button(vi ? "Mở bằng Claude Code" : "Open with Claude Code") {
                        NSWorkspace.shared.open([url],
                                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                configuration: .init())
                    }
                    Divider()
                    Button(showFiles ? (vi ? "Ẩn danh sách tệp" : "Hide files") : (vi ? "Xem danh sách tệp" : "Show files")) {
                        withAnimation(.easeOut(duration: 0.15)) { showFiles.toggle() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(vi ? "Thêm" : "More")
                if !approved, primary != .approve {
                    TeamCardButton(title: vi ? "Duyệt" : "Approve") {
                        Task { await companyStore.approveTeamRun() }
                    }
                }
                switch primary {
                case .runDev:
                    TeamCardButton(title: vi ? "Mở trang" : "Open the page", primary: true) { TeamProjectLauncher.runDev(path) }
                case .openIndex:
                    TeamCardButton(title: vi ? "Mở trang" : "Open the page", primary: true) { NSWorkspace.shared.open(index) }
                case .approve:
                    if !approved {
                        TeamCardButton(title: vi ? "Duyệt" : "Approve", primary: true) {
                            Task { await companyStore.approveTeamRun() }
                        }
                    }
                }
            }
            if !approved, let note = TeamBuildCopy.readyNote(
                hasApproved: companyStore.company.firstApprovalAt != nil, lang) {
                Text(note)
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fileList(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.files(at: path), id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CodepetTheme.hairline.opacity(0.35)))
    }

    /// The department contributions (`docs/…`) first, then what Claude Code wrote at the top
    /// level. Hidden files and the `docs` folder itself are left out; folders end in `/`.
    static func files(at path: String) -> [String] {
        let fm = FileManager.default
        let docs = ((try? fm.contentsOfDirectory(atPath: path + "/docs")) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted().map { "docs/\($0)" }
        let top = ((try? fm.contentsOfDirectory(atPath: path)) ?? [])
            .filter { !$0.hasPrefix(".") && $0 != "docs" }.sorted()
            .map { name -> String in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: path + "/" + name, isDirectory: &isDir)
                return isDir.boolValue ? name + "/" : name
            }
        return docs + top
    }
}

// MARK: - Launching the project

/// "Run it" for a Node project: a Terminal window that installs if needed, starts `npm run dev`
/// and opens the page. Terminal, not a child process of the app — the dev server should outlive
/// the card, show its own errors, and stop with ^C like any dev server the founder has seen.
enum TeamProjectLauncher {
    static func isNodeProject(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/package.json")
    }

    /// The script, pure so a test can pin its quoting: the path is single-quoted with any `'`
    /// escaped, because a project folder name is derived from founder-typed text.
    ///
    /// PATH is the app's own augmented PATH (`LoginShellRunner.spawnEnvironment`): a script
    /// shell does not read `.zshrc`, which is where nvm/fnm put node.
    ///
    /// The script picks the port, not Next.js: with 3000 taken, `next dev` quietly moves to 3001,
    /// and a hard-coded `open http://localhost:3000` then showed whatever else held 3000 (build 9,
    /// 6 Oct — an old landing-page dev server). The first free port from `startPort` is passed with
    /// `-p`, and the page opens once something answers on it, rather than after a fixed 4 s.
    static func script(for path: String, pathVar: String = LoginShellRunner.spawnEnvironment()["PATH"] ?? "",
                       startPort: Int = 3000) -> String {
        """
        #!/bin/zsh
        export PATH=\(quote(pathVar)):$PATH
        cd \(quote(path)) || exit 1
        [ -d node_modules ] || npm install --no-audit --no-fund || exit 1
        PORT=\(startPort)
        while nc -z localhost $PORT 2>/dev/null; do PORT=$((PORT + 1)); done
        (for i in {1..120}; do nc -z localhost $PORT 2>/dev/null && break; sleep 1; done
         open "http://localhost:$PORT") &
        exec npm run dev -- -p $PORT
        """
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func runDev(_ path: String) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("codepet-run-\(UUID().uuidString.prefix(8)).command")
        do {
            try script(for: path).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch { return }
        NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Detail panel

/// What one step was asked, what it was handed, and what it made. The pane shows it in a side
/// column, the dock in a sheet — `CopilotChatView` decides which.
struct TeamStepDetail: View {
    let step: WorkStep
    let state: TeamStepState?
    let run: TeamRun
    let buildLog: [String]

    @Environment(\.uiLanguage) private var lang
    @State private var openDraft: Deliverable?
    @State private var showFullAsk = false

    var body: some View {
        let vi = lang == .vi
        let status = state?.status ?? .waiting
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TeamPetAvatar(dept: step.dept, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TeamBuildCopy.deptName(step.dept))
                        .font(CodepetTheme.inter(14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(step.title)
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                TeamStatusPill(status: status,
                               text: TeamBuildCopy.status(status, elapsed: elapsed(state, now: Date()), lang: lang))
            }
            if case .failed(let reason) = status {
                Text(reason)
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // RESULT FIRST (CP-035). It used to sit under a ~380-word raw instruction and the
            // upstream steps' pasted markdown, at the bottom of the panel.
            if status == .done, let draft = state?.draft {
                section(vi ? "Kết quả:" : "Result:") {
                    if DraftPayloadPreview.hasStructuredPreview(draft) {
                        DraftPayloadPreview(deliverable: draft) { openDraft = draft }
                    } else {
                        Button { openDraft = draft } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title)
                                    .font(CodepetTheme.inter(13, weight: .semibold))
                                    .foregroundColor(CodepetTheme.primaryText)
                                // `Text(String)` prints markdown literally; strip it to prose.
                                Text(DraftPreview.plain(draft.body, title: draft.title))
                                    .font(CodepetTheme.inter(12.5))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .lineLimit(10)
                                    .multilineTextAlignment(.leading)
                                Text(vi ? "Mở toàn bộ ›" : "Open in full ›")
                                    .font(CodepetTheme.inter(12, weight: .medium))
                                    .foregroundColor(CodepetTheme.accentPurple)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            section(vi ? "Yêu cầu:" : "Asked for:") {
                Text(StepAskSummary.summary(step.instruction))
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if StepAskSummary.isShortened(step.instruction) {
                    Button { withAnimation(.easeOut(duration: 0.15)) { showFullAsk.toggle() } } label: {
                        Text(showFullAsk ? (vi ? "Ẩn yêu cầu đầy đủ" : "Hide the full instruction")
                                         : (vi ? "Yêu cầu đầy đủ gửi cho \(TeamBuildCopy.deptName(step.dept)) ›"
                                               : "Full instruction sent to \(TeamBuildCopy.deptName(step.dept)) ›"))
                            .font(CodepetTheme.inter(12, weight: .medium))
                            .foregroundColor(CodepetTheme.accentPurple)
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover(.pointingHand)
                    if showFullAsk {
                        Text(step.instruction)
                            .font(CodepetTheme.inter(12))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            if !step.dependsOn.isEmpty {
                // Chips, not pasted markdown: which steps fed this one, and whether each is in.
                section(vi ? "Dùng kết quả của:" : "Uses work from:") {
                    WrapLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(step.dependsOn, id: \.self) { id in
                            if let dep = run.plan.steps.first(where: { $0.id == id }) {
                                upstreamChip(dep)
                            }
                        }
                    }
                }
            }

            if step.id == WorkPlan.buildStepId, run.phase == .assembling {
                ExecLogRow(taskTitle: run.plan.title, deptName: "Engineering",
                           steps: buildLog.map { ExecStep(label: $0, done: true) },
                           companionId: DepartmentCompanions.companionId(for: "eng"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $openDraft) { DeliverableDetailView(deliverable: $0) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CodepetTheme.inter(11, weight: .semibold))
                .foregroundColor(CodepetTheme.mutedText)
            content()
        }
    }

    /// One step this step builds on: its department and title, and whether its work is in yet.
    /// Tapping a finished one opens that work.
    private func upstreamChip(_ dep: WorkStep) -> some View {
        let draft = run.state(dep.id)?.draft
        return Button { if let draft { openDraft = draft } } label: {
            HStack(spacing: 6) {
                TeamPetAvatar(dept: dep.dept, size: 16)
                Text("\(TeamBuildCopy.deptName(dep.dept)) · \(dep.title)")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(draft == nil ? CodepetTheme.mutedText : CodepetTheme.primaryText)
                    .lineLimit(1)
                if draft == nil {
                    Text(lang == .vi ? "chưa xong" : "not ready")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(CodepetTheme.surface))
            .overlay(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(draft == nil)
    }
}

/// Resolves a selected step against the live coordinator, so the side column and the sheet
/// both update as the step runs, and calls `onClose` if the step is gone.
struct TeamStepDetailPanel: View {
    @ObservedObject var coordinator: TeamRunCoordinator
    let stepId: String
    let onClose: () -> Void

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang == .vi ? "Chi tiết bước" : "Step detail")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(CodepetIconButtonStyle(size: 24))
                    .help(lang == .vi ? "Đóng" : "Close")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().overlay(CodepetTheme.hairline)
            ScrollView {
                if let run = coordinator.run, let step = run.plan.steps.first(where: { $0.id == stepId }) {
                    TeamStepDetail(step: step, state: run.state(stepId), run: run, buildLog: coordinator.buildLog)
                        .padding(16)
                } else {
                    // The step is gone (a newer run replaced this one): close rather than
                    // leave an empty column or sheet behind.
                    Color.clear.frame(height: 1).onAppear(perform: onClose)
                }
            }
        }
        .background(CodepetTheme.pageBackground)
    }
}

/// `.sheet(item:)` needs an `Identifiable`; a step id is a `String`.
struct TeamStepSelection: Identifiable, Equatable {
    let id: String
}

// MARK: - Placement

/// Whether the store's team run is drawn at the transcript's bottom rather than inline under
/// its message. A run no thread carries (its thread deleted, or started before threads were
/// archived with `teamRunId`) has no message to sit under; without the bottom card its
/// Continue / Approve would be unreachable.
///
/// Pure so `TeamRunPlacementTests` can pin it — the decision is where the bugs were.
enum TeamRunPlacement {
    /// - `messageRunIds`: the `teamRunId`s carried by the current transcript. A run in it renders
    ///   inline, so it is never drawn here too.
    /// - `elsewhereRunIds`: the `teamRunId`s carried by the founder's OTHER threads. A run there
    ///   has a home — it renders inline when the founder opens that thread — so one waiting on
    ///   the founder (Go, Continue, Approve) is not drawn here. Before this, a finished build
    ///   awaiting Approve sat at the foot of every conversation, new ones included, for as long
    ///   as it went unapproved (5 Oct, real account).
    /// - A run still working (running, assembling) follows the founder everywhere: it lasts
    ///   minutes and its Stop has to be within reach.
    /// - Otherwise a run the founder can still act on (active, or ready for Approve) is shown.
    /// - A finished run (filed, cancelled) is shown only where it was already being drawn —
    ///   `stickyRunId` stamped in the conversation `stickyKey` — so the card does not vanish the
    ///   moment it says Cancelled or "Added to Library". Scoped to that conversation: before
    ///   the scope, a card drawn once followed the founder into every later conversation.
    /// - `transcriptKey` identifies the conversation on screen (see
    ///   `CopilotChatView.transcriptKey`); pass `stickyRunId: nil` to ask "is there something
    ///   the founder must act on", which is what the empty-state check wants.
    static func showsUnanchored(run: TeamRun?, messageRunIds: Set<String>,
                                elsewhereRunIds: Set<String> = [], stickyRunId: String?,
                                stickyKey: String?, transcriptKey: String?) -> Bool {
        guard let run, !messageRunIds.contains(run.id) else { return false }
        if run.phase == .running || run.phase == .assembling { return true }
        if run.isActive || run.phase == .ready { return !elsewhereRunIds.contains(run.id) }
        return run.id == stickyRunId && stickyKey == transcriptKey
    }
}

/// When the transcript follows a Team Build card, and to where.
///
/// The card is ONE message that grows for minutes, and the transcript only scrolled when the
/// message COUNT changed. On 1 Oct (build 6, real account) a Team Build finished and the chat did
/// not move: the Approve / Run it / Open in Finder row sat under the composer, and the founder had
/// no sign the run was waiting on them. The Virtual Company room had the same shape and is followed
/// by `vcRunCardCount`; this is the Team Build's equivalent.
enum TeamRunFollow {
    /// The scroll id `CopilotChatView` gives a run with no message in this thread.
    static let unanchoredId = "team-run"

    /// Changes exactly when the card gains something to act on or read: a new phase (the plan's
    /// Go/Cancel on `.planned`, the Approve row on `.ready`, a failure, a cancel) or one more step
    /// settling. A step merely STARTING does not count — following that would yank a founder who
    /// scrolled up to read a draft back to the bottom every few seconds.
    static func key(_ run: TeamRun?) -> String? {
        guard let run else { return nil }
        let settled = run.steps.filter {
            switch $0.status {
            case .waiting, .running: return false
            default: return true
            }
        }.count
        return "\(run.id)|\(run.phase.rawValue)|\(settled)"
    }

    /// The message carrying the run, else the unanchored card at the transcript's foot.
    static func target(runId: String, messages: [CopilotMessage]) -> String {
        messages.last(where: { $0.teamRunId == runId })?.id ?? unanchoredId
    }
}
