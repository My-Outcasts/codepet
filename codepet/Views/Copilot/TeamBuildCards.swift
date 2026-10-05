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
    /// The row shown while a Team Build's router picks who joins the room (CP-027). Says only what
    /// is true at that moment: nobody has started work yet, so it names the choosing, not a team.
    static func conveningTitle(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang gọi cả đội…" : "Bringing the team together…"
    }

    static func conveningDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang chọn những phòng ban sẽ tham gia. Thường mất khoảng một phút."
                    : "Choosing which departments should weigh in. This usually takes about a minute."
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
private struct TeamPetAvatar: View {
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

/// A small house button: solid for the primary action, outlined for the rest.
private struct TeamCardButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(primary ? .white : CodepetTheme.primaryText)
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? CodepetTheme.accentPurple : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(primary ? Color.clear : CodepetTheme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Team card

/// The one card a Team Build lives in, from plan to filed. Which footer it shows is decided by
/// `run.phase`; the rows above it are the same in every phase.
struct TeamRunCard: View {
    @ObservedObject var coordinator: TeamRunCoordinator
    let onSelect: (String) -> Void

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    /// "See all N steps" on a compacted card (CP-033).
    @State private var showAllSteps = false

    var body: some View {
        if let run = coordinator.run {
            HStack {
                MessageCard(hue: CodepetTheme.accentPurple) { card(run) }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card(_ run: TeamRun) -> some View {
        let done = run.steps.filter { $0.status == .done }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(run.plan.title)
                    .font(CodepetTheme.inter(15, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text("\(done)/\(run.plan.steps.count)")
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(CodepetTheme.mutedText)
            }
            let compact = TeamProgress.compacts(run.phase)
            let stopped = run.phase == .cancelled
            if !run.plan.summary.isEmpty {
                // Two lines while compacted: the brief is context, and the whole of it is one
                // click away in the plan the founder already approved.
                Text(run.plan.summary)
                    .font(CodepetTheme.inter(12.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit((compact || stopped) && !showAllSteps ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Only the rows tick; the footer (which reads the disk on `.ready`) does not.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    if compact {
                        progressSummary(run, now: context.date)
                    } else if stopped {
                        // What happened, not six "Cancelled" pills (CP-034).
                        Text(TeamBuildCopy.stoppedSummary(run, lang: lang))
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !(compact || stopped) || showAllSteps {
                        ForEach(run.plan.steps) { step in
                            row(step, run: run, now: context.date)
                            if step.id == WorkPlan.buildStepId, run.phase == .assembling {
                                buildActivity
                            }
                        }
                    } else if run.phase == .assembling {
                        buildActivity
                    }
                }
            }
            if compact || stopped {
                Button { withAnimation(.easeOut(duration: 0.15)) { showAllSteps.toggle() } } label: {
                    Text(TeamBuildCopy.allSteps(run.plan.steps.count, expanded: showAllSteps, lang: lang)
                         + (showAllSteps ? "" : " ›"))
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
                .buttonStyle(.plain)
                .cursorOnHover(.pointingHand)
            }
            footer(run)
        }
    }

    /// The compacted card's head (CP-033): one segment per step, then who is working now with
    /// its clock, and what comes next. Clicking the live line opens that step's detail.
    @ViewBuilder private func progressSummary(_ run: TeamRun, now: Date) -> some View {
        let p = TeamProgress(run)
        HStack(spacing: 3) {
            ForEach(Array(p.segments.enumerated()), id: \.offset) { _, s in
                Capsule().fill(segmentColor(s)).frame(height: 5)
            }
        }
        .accessibilityLabel(lang == .vi ? "\(p.doneCount) trên \(p.total) bước xong"
                                        : "\(p.doneCount) of \(p.total) steps done")
        if let live = TeamBuildCopy.liveLine(p, lang: lang) {
            Button { if let s = p.current.first { onSelect(s.id) } } label: {
                HStack(spacing: 8) {
                    if p.current.count == 1, let s = p.current.first { TeamPetAvatar(dept: s.dept) }
                    Text(live)
                        .font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    if p.current.count == 1, let s = p.current.first {
                        TeamStatusPill(status: .running,
                                       text: TeamBuildCopy.status(.running, elapsed: elapsed(run.state(s.id), now: now),
                                                                  lang: lang))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverAffordance(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        if let next = TeamBuildCopy.nextLine(p, lang: lang) {
            Text(next)
                .font(CodepetTheme.inter(11.5))
                .foregroundColor(CodepetTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func segmentColor(_ s: TeamStepStatus) -> Color {
        switch s {
        case .done: return CodepetTheme.accentTeal
        case .running: return CodepetTheme.accentPurple
        case .failed: return Color.red
        case .blocked, .interrupted: return CodepetTheme.accentGold
        // Not `hairline`: on the card's purple tint a hairline-coloured segment was invisible
        // (seen on screen, 28 Sep), so the strip read as 3 segments of a 7-step run.
        case .waiting, .cancelled: return CodepetTheme.mutedText.opacity(0.35)
        }
    }

    /// The build step can run for 15 minutes; its last few actions are shown on the card itself
    /// so the founder sees it moving without opening the step's detail.
    private var buildActivity: some View {
        let lines = Array(coordinator.buildLog.suffix(4))
        return VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty {
                Text(lang == .vi ? "Đang đọc tài liệu của cả đội…" : "Reading the team's docs…")
                    .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text("› " + line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(i == lines.count - 1 ? CodepetTheme.bodyText : CodepetTheme.mutedText)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.leading, 28)
    }

    private func row(_ step: WorkStep, run: TeamRun, now: Date) -> some View {
        let state = run.state(step.id)
        let status = state?.status ?? .waiting
        let deps = TeamBuildCopy.dependencyNames(step, in: run.plan)
        return Button { onSelect(step.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    TeamPetAvatar(dept: step.dept)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TeamBuildCopy.deptName(step.dept))
                            .font(CodepetTheme.inter(11, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                        Text(step.title)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                    TeamStatusPill(status: status,
                                   text: TeamBuildCopy.status(status, elapsed: elapsed(state, now: now),
                                                              lang: lang))
                }
                if case .failed(let reason) = status {
                    Text(reason)
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(Color.red)
                        .padding(.leading, 28)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !deps.isEmpty, status == .waiting || status == .blocked {
                    Text(TeamBuildCopy.waitsFor(deps, lang: lang))
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
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

    @ViewBuilder private func footer(_ run: TeamRun) -> some View {
        let vi = lang == .vi
        let interrupted = run.steps.contains { $0.status == .interrupted }
        switch run.phase {
        case .planned:
            VStack(alignment: .leading, spacing: 8) {
                Text(vi ? "\(run.plan.steps.count) bước · chạy trên gói Claude của bạn"
                        : "\(run.plan.steps.count) steps · runs on your Claude plan")
                    .font(CodepetTheme.inter(11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                HStack(spacing: 8) {
                    TeamCardButton(title: vi ? "Bắt đầu" : "Go", primary: true) {
                        Task { await companyStore.confirmTeamPlan(language: lang) }
                    }
                    TeamCardButton(title: vi ? "Huỷ" : "Cancel") { companyStore.cancelTeamPlan() }
                }
            }
        case .running, .assembling:
            HStack(spacing: 8) {
                if interrupted { continueButton }
                TeamCardButton(title: vi ? "Dừng" : "Stop") { companyStore.stopTeamRun() }
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
                TeamCardButton(title: vi ? "Dừng" : "Stop") { companyStore.stopTeamRun() }
            }
        case .ready:
            if let path = run.projectPath { readyFooter(path) }
        case .filed:
            // The project is the deliverable, so filing it must not take away the way into it —
            // before this, the only route back was Library ▸ Engineering ▸ the entry ▸ Finder.
            VStack(alignment: .leading, spacing: 8) {
                Label(vi ? "Đã thêm vào Thư viện" : "Added to Library", systemImage: "checkmark.circle.fill")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentTeal)
                if let path = run.projectPath, FileManager.default.fileExists(atPath: path) {
                    WrapLayout(spacing: 8, rowSpacing: 8) { projectButtons(path) }
                }
            }
        case .cancelled:
            HStack(spacing: 8) {
                if interrupted { continueButton }
                TeamCardButton(title: vi ? "Bỏ lượt này" : "Discard") {
                    Task { await companyStore.discardTeamRun() }
                }
            }
        }
    }

    private var continueButton: some View {
        TeamCardButton(title: lang == .vi ? "Tiếp tục" : "Continue", primary: true) {
            Task { await companyStore.continueTeamRun(language: lang) }
        }
    }

    private func readyFooter(_ path: String) -> some View {
        let vi = lang == .vi
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.files(at: path), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.bodyText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodepetTheme.surface))
            WrapLayout(spacing: 8, rowSpacing: 8) {
                TeamCardButton(title: vi ? "Duyệt" : "Approve", primary: true) {
                    Task { await companyStore.approveTeamRun() }
                }
                projectButtons(path)
            }
            if let note = TeamBuildCopy.readyNote(
                hasApproved: companyStore.company.firstApprovalAt != nil, lang) {
                Text(note)
                    .font(CodepetTheme.inter(11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Open / run the project on disk — the same buttons before and after Approve.
    @ViewBuilder private func projectButtons(_ path: String) -> some View {
        let vi = lang == .vi
        let url = URL(fileURLWithPath: path)
        let index = url.appendingPathComponent("index.html")
        if TeamProjectLauncher.isNodeProject(path) {
            TeamCardButton(title: vi ? "Chạy thử" : "Run it") { TeamProjectLauncher.runDev(path) }
        } else if FileManager.default.fileExists(atPath: index.path) {
            TeamCardButton(title: vi ? "Xem trên trình duyệt" : "View in browser") { NSWorkspace.shared.open(index) }
        }
        TeamCardButton(title: vi ? "Mở trong Finder" : "Open in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        TeamCardButton(title: vi ? "Mở bằng Claude Code" : "Open with Claude Code") {
            NSWorkspace.shared.open([url],
                                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                    configuration: .init())
        }
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
    static func script(for path: String, pathVar: String = LoginShellRunner.spawnEnvironment()["PATH"] ?? "") -> String {
        """
        #!/bin/zsh
        export PATH=\(quote(pathVar)):$PATH
        cd \(quote(path)) || exit 1
        [ -d node_modules ] || npm install --no-audit --no-fund || exit 1
        (sleep 4; open http://localhost:3000) &
        exec npm run dev
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
