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
            if !run.plan.summary.isEmpty {
                Text(run.plan.summary)
                    .font(CodepetTheme.inter(12.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Only the rows tick; the footer (which reads the disk on `.ready`) does not.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(run.plan.steps) { step in
                        row(step, run: run, now: context.date)
                    }
                }
            }
            footer(run)
        }
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
            Label(vi ? "Đã thêm vào Thư viện" : "Added to Library", systemImage: "checkmark.circle.fill")
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentTeal)
        case .cancelled:
            if interrupted { continueButton }
        }
    }

    private var continueButton: some View {
        TeamCardButton(title: lang == .vi ? "Tiếp tục" : "Continue", primary: true) {
            Task { await companyStore.continueTeamRun(language: lang) }
        }
    }

    private func readyFooter(_ path: String) -> some View {
        let vi = lang == .vi
        let url = URL(fileURLWithPath: path)
        let index = url.appendingPathComponent("index.html")
        let hasIndex = FileManager.default.fileExists(atPath: index.path)
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
                TeamCardButton(title: vi ? "Mở trong Finder" : "Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                TeamCardButton(title: vi ? "Mở bằng Claude Code" : "Open with Claude Code") {
                    NSWorkspace.shared.open([url],
                                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                            configuration: .init())
                }
                if hasIndex {
                    TeamCardButton(title: vi ? "Xem trên trình duyệt" : "View in browser") {
                        NSWorkspace.shared.open(index)
                    }
                }
            }
            Text(DraftCardCopy.notFiledNote(lang))
                .font(CodepetTheme.inter(11.5))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
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

            section(vi ? "Yêu cầu:" : "Asked for:") {
                Text(step.instruction)
                    .font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !step.dependsOn.isEmpty {
                section(vi ? "Nhận từ:" : "Receives from:") {
                    ForEach(step.dependsOn, id: \.self) { id in
                        if let dep = run.plan.steps.first(where: { $0.id == id }) {
                            upstream(dep)
                        }
                    }
                }
            }

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
                                Text(draft.body)
                                    .font(CodepetTheme.inter(12.5))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .lineLimit(10)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    private func upstream(_ dep: WorkStep) -> some View {
        let body = run.state(dep.id)?.draft?.body
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TeamPetAvatar(dept: dep.dept, size: 16)
                Text(TeamBuildCopy.deptName(dep.dept))
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            HStack(spacing: 8) {
                Rectangle().fill(CodepetTheme.accentPurple.opacity(0.5)).frame(width: 2)
                Text(body.map { String($0.prefix(160)) + ($0.count > 160 ? "…" : "") }
                     ?? (lang == .vi ? "Chưa có" : "Not ready yet"))
                    .font(CodepetTheme.inter(12))
                    .italic(body != nil)
                    .foregroundColor(body == nil ? CodepetTheme.mutedText : CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Resolves a selected step against the live coordinator, so the side column and the sheet
/// both update as the step runs, and closes itself if the step is gone (a new run replaced it).
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
