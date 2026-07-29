import SwiftUI

/// The one evolving in-chat card for a local coding-agent run (Part 2C-2). Every
/// phase of `CodingRunCoordinator.run` renders from THIS card — plan-preview →
/// live steps → diff review with per-file accept → committed / failed — so a run
/// visibly grows in place rather than spawning fresh messages. Left-aligned like a
/// companion message; Engineering-purple accent. The heavy work ran on the
/// founder's own `claude` subscription (0 Codepet credits) and never left the
/// machine — the copy says so.
struct CodeRunCardView: View {
    @ObservedObject var coordinator: CodingRunCoordinator
    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    /// Per-file accept selection — relative paths, the same domain as
    /// `run.acceptedPaths`. Seeded when diffs arrive; the founder can deselect a
    /// file before approving, and Approve commits only the still-selected subset.
    @State private var accepted: Set<String> = []

    private var hue: Color { CodepetTheme.accentPurple }
    private let maxLinesPerFile = 40

    var body: some View {
        HStack {
            MessageCard(hue: hue) {
                if let run = coordinator.run {
                    content(for: run)
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Seed / re-seed the accept selection whenever the coordinator republishes
        // the run's accepted set (i.e. when diffs land and it enters `.reviewing`).
        .onChange(of: coordinator.run?.acceptedPaths) { _, new in accepted = new ?? [] }
        .onAppear { accepted = coordinator.run?.acceptedPaths ?? [] }
    }

    // MARK: - Phase router

    @ViewBuilder private func content(for run: EditCodeRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(run)
            switch run.phase {
            case .noProject:              noProjectBody
            case .previewing:             previewBody(run)
            case .readyToRun, .running:   runningBody(run)
            case .reviewing:              reviewBody(run)
            case .committed:              committedBody(run)
            case .discarded:              discardedBody
            case .failed(let reason):     failedBody(reason)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder private func header(_ run: EditCodeRun) -> some View {
        HStack(alignment: .center, spacing: 8) {
            CompanionAvatar(size: 22, isWorking: run.phase == .running)
            VStack(alignment: .leading, spacing: 1) {
                Text(lang == .vi ? "KỸ THUẬT" : "ENGINEERING")
                    .font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
                    .foregroundColor(hue)
                Text(lang == .vi ? "Chạy trên gói Claude của bạn · 0 tín dụng"
                                 : "Ran on your Claude subscription · 0 credits")
                    .font(CodepetTheme.inter(10)).foregroundColor(CodepetTheme.mutedText)
            }
            Spacer(minLength: 8)
            phasePill(run.phase)
        }
    }

    private func phasePill(_ phase: EditCodePhase) -> some View {
        let (text, fg): (String, Color)
        switch phase {
        case .noProject:  (text, fg) = (lang == .vi ? "Chưa liên kết" : "No project", CodepetTheme.mutedText)
        case .previewing: (text, fg) = (lang == .vi ? "Kế hoạch" : "Plan", CodepetTheme.accentGold)
        case .readyToRun: (text, fg) = (lang == .vi ? "Sẵn sàng" : "Ready", hue)
        case .running:    (text, fg) = (lang == .vi ? "Đang làm" : "Working", hue)
        case .reviewing:  (text, fg) = (lang == .vi ? "Đang duyệt" : "Review", CodepetTheme.accentGold)
        case .committed:  (text, fg) = (lang == .vi ? "Đã lưu" : "Committed", CodepetTheme.accentTeal)
        case .discarded:  (text, fg) = (lang == .vi ? "Đã bỏ" : "Discarded", CodepetTheme.mutedText)
        case .failed:     (text, fg) = (lang == .vi ? "Lỗi" : "Failed", .red)
        }
        return Text(text)
            .font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(fg.opacity(0.14)))
    }

    private func askTitle(_ run: EditCodeRun) -> some View {
        Text(run.ask)
            .font(CodepetTheme.inter(14, weight: .medium))
            .foregroundColor(CodepetTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Bodies

    @ViewBuilder private var noProjectBody: some View {
        Text(lang == .vi ? "Liên kết một dự án để mình có thể sửa code thật."
                         : "Link a project so I can make real changes to your code.")
            .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.bodyText)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            // Same picker + CLAUDE.md-consent flow as Environment (shared ProjectLinker).
            // On link, re-propose THIS run's ask so the founder doesn't retype it.
            actionButton(lang == .vi ? "Liên kết dự án" : "Link a project", filled: true) {
                let ask = coordinator.run?.ask ?? ""
                if let link = ProjectLinker.pickAndLink(into: companyStore, language: lang) {
                    coordinator.propose(ask: ask, plannedFiles: 1, needsBash: false, link: link)
                }
            }
            actionButton(lang == .vi ? "Bỏ" : "Dismiss", filled: false, subtle: true) {
                coordinator.cancel()
            }
        }
    }

    @ViewBuilder private func previewBody(_ run: EditCodeRun) -> some View {
        askTitle(run)
        Text(lang == .vi
             ? "Mình sẽ chạy trên máy của bạn và có thể chạy lệnh terminal. Bạn duyệt từng thay đổi trước khi lưu."
             : "I'll work on your machine and may run terminal commands. You review every change before anything is saved.")
            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            actionButton(lang == .vi ? "Chạy" : "Run", filled: true) {
                Task { await coordinator.execute() }
            }
            actionButton(lang == .vi ? "Huỷ" : "Cancel", filled: false) {
                coordinator.cancel()
            }
        }
    }

    @ViewBuilder private func runningBody(_ run: EditCodeRun) -> some View {
        askTitle(run)
        if coordinator.steps.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(lang == .vi ? "Đang bắt đầu…" : "Getting started…")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            }
        } else {
            stepList(coordinator.steps, showSpinnerTail: run.phase == .running)
        }
    }

    @ViewBuilder private func reviewBody(_ run: EditCodeRun) -> some View {
        askTitle(run)
        // Steps collapse to a one-line summary once the diffs are the focus.
        if !coordinator.steps.isEmpty {
            Text(lang == .vi ? "\(coordinator.steps.count) bước" : "\(coordinator.steps.count) steps")
                .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
        }
        branchChip(run)
        Text(filesChangedLabel(run.diffs.count))
            .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.bodyText)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(run.diffs) { diff in diffCard(diff, run: run) }
        }
        actionButton(lang == .vi ? "Xem toàn bộ khác biệt" : "Open full diff", filled: false, subtle: true) {
            // Stub: a full-diff viewer is a follow-on. The inline diffs are the gate.
        }
        HStack(spacing: 8) {
            actionButton(approveLabel, filled: true) {
                Task { await coordinator.approve(acceptedPaths: accepted) }
            }
            actionButton(lang == .vi ? "Bỏ" : "Reject", filled: false) {
                Task { await coordinator.reject() }
            }
        }
    }

    @ViewBuilder private func committedBody(_ run: EditCodeRun) -> some View {
        switch run.backend {
        case .git(let branch):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundColor(CodepetTheme.accentTeal)
                Text(lang == .vi ? "Đã lưu vào nhánh" : "Committed to")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.bodyText)
                branchLabel(branch)
            }
            Text(lang == .vi ? "Chưa đẩy hay gộp gì — nhánh nằm ở máy bạn."
                             : "Nothing pushed or merged — the branch stays on your machine.")
                .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        case .shadow:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundColor(CodepetTheme.accentTeal)
                Text(lang == .vi ? "Đã áp dụng vào dự án" : "Applied to your project")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.bodyText)
                Spacer(minLength: 8)
                actionButton(lang == .vi ? "Hoàn tác" : "Undo", filled: false, subtle: true) {
                    // Stub: undo-from-backup is wired in a follow-on.
                }
            }
        }
    }

    private var discardedBody: some View {
        HStack(spacing: 8) {
            Text(lang == .vi ? "Đã bỏ các thay đổi — không có gì được lưu."
                             : "Discarded — nothing was saved.")
                .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actionButton(lang == .vi ? "Đóng" : "Dismiss", filled: false, subtle: true) {
                coordinator.cancel()
            }
        }
    }

    @ViewBuilder private func failedBody(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundColor(.red).padding(.top, 1)
            Text(reason)
                .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if isEnablementReason(reason) {
            Text(lang == .vi
                 ? "Để mình sửa code thật: cài Claude Code và đăng nhập một lần trong Terminal, rồi thử lại."
                 : "To let me make real code changes: install Claude Code and sign in once in your Terminal, then try again.")
                .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        actionButton(lang == .vi ? "Đóng" : "Dismiss", filled: false, subtle: true) {
            coordinator.cancel()
        }
    }

    // MARK: - Diff card

    @ViewBuilder private func diffCard(_ diff: ClaudeCodeRunner.FileDiff, run: EditCodeRun) -> some View {
        let key = relKey(for: diff, in: run)
        let isOn = accepted.contains(key)
        VStack(alignment: .leading, spacing: 0) {
            // File header: accept toggle + name + new-file tag.
            Button {
                if isOn { accepted.remove(key) } else { accepted.insert(key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundColor(isOn ? hue : CodepetTheme.mutedText.opacity(0.6))
                    Text(diff.fileName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                    if diff.isNewFile {
                        Text(lang == .vi ? "mới" : "new")
                            .font(CodepetTheme.inter(9, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentTeal)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(CodepetTheme.accentTeal.opacity(0.16)))
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Divider().overlay(CodepetTheme.hairline)
            diffLines(diff)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodepetTheme.pageBackground.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(CodepetTheme.hairline, lineWidth: 1))
        .opacity(isOn ? 1 : 0.55)   // a deselected file dims — it won't be committed
    }

    @ViewBuilder private func diffLines(_ diff: ClaudeCodeRunner.FileDiff) -> some View {
        let shown = Array(diff.lines.prefix(maxLinesPerFile))
        let overflow = diff.lines.count - shown.count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text(marker(line.kind)).frame(width: 8, alignment: .leading)
                    Text(line.text.isEmpty ? " " : line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineFg(line.kind))
                .padding(.horizontal, 8).padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(lineBg(line.kind))
            }
            if overflow > 0 {
                Text(lang == .vi ? "+\(overflow) dòng nữa" : "+\(overflow) more lines")
                    .font(CodepetTheme.inter(10)).foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Small pieces

    @ViewBuilder private func stepList(_ steps: [ExecStep], showSpinnerTail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(CodepetTheme.accentTeal)
                        .frame(width: 15, height: 15)
                    Text(step.label)
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showSpinnerTail {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 15, height: 15)
                    Text(lang == .vi ? "Đang làm…" : "Working…")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.primaryText)
                }
            }
        }
    }

    @ViewBuilder private func branchChip(_ run: EditCodeRun) -> some View {
        if case .git(let branch) = run.backend { branchLabel(branch) }
    }

    private func branchLabel(_ branch: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
            Text(branch).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundColor(hue)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(hue.opacity(0.12)))
    }

    private func actionButton(_ title: String, filled: Bool, subtle: Bool = false,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(subtle ? 11 : 12, weight: .semibold))
                .foregroundColor(filled ? CodepetTheme.onAccent(hue) : (subtle ? CodepetTheme.mutedText : hue))
                .padding(.horizontal, subtle ? 8 : 14).padding(.vertical, subtle ? 4 : 7)
                .background(
                    Capsule().fill(filled ? hue : Color.clear)
                        .overlay(Capsule().stroke(filled || subtle ? Color.clear : hue.opacity(0.5), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// The relative path (in `run.acceptedPaths`) that identifies this diff. The
    /// coordinator derived acceptedPaths 1:1 from the diffs, so each diff's absolute
    /// path ends with exactly one accepted relative path; fall back to the filename.
    private func relKey(for diff: ClaudeCodeRunner.FileDiff, in run: EditCodeRun) -> String {
        run.acceptedPaths.first { diff.path == $0 || diff.path.hasSuffix("/" + $0) } ?? diff.fileName
    }

    private func filesChangedLabel(_ n: Int) -> String {
        if lang == .vi { return "\(n) tệp thay đổi" }
        return n == 1 ? "1 file changed" : "\(n) files changed"
    }

    private var approveLabel: String {
        let n = accepted.count
        if lang == .vi { return n <= 1 ? "Duyệt" : "Duyệt \(n) tệp" }
        return n <= 1 ? "Approve" : "Approve \(n) files"
    }

    private func isEnablementReason(_ reason: String) -> Bool {
        let s = reason.lowercased()
        return s.contains("install") || s.contains("path") || s.contains("sign in") || s.contains("log in")
    }

    private func marker(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> String {
        switch kind { case .added: return "+"; case .removed: return "-"; case .context: return " " }
    }
    private func lineFg(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> Color {
        switch kind {
        case .added:   return CodepetTheme.primaryText
        case .removed: return CodepetTheme.mutedText
        case .context: return CodepetTheme.mutedText
        }
    }
    private func lineBg(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> Color {
        switch kind {
        case .added:   return Color.green.opacity(0.14)
        case .removed: return Color.red.opacity(0.12)
        case .context: return Color.clear
        }
    }
}

#if DEBUG
private func _demoDiff() -> ClaudeCodeRunner.FileDiff {
    ClaudeCodeRunner.FileDiff(path: "/proj/hello.js", isNewFile: false, lines: [
        .init(kind: .context, text: "function greet(name) {"),
        .init(kind: .removed, text: "  return \"Hi \" + name;"),
        .init(kind: .added,   text: "  return \"Hello, \" + name + \"!\";"),
        .init(kind: .context, text: "}"),
    ])
}

#Preview("phases") {
    let reviewing = EditCodeRun(
        ask: "In hello.js, make the greeting friendlier",
        backend: .git(branch: "codepet/friendlier-greeting"),
        phase: .reviewing, diffs: [_demoDiff()], acceptedPaths: ["hello.js"])
    return ScrollView {
        VStack(spacing: 20) {
            CodeRunCardView(coordinator: .preview(
                EditCodeRun(ask: "Refactor the auth flow across a few files",
                            backend: .git(branch: "codepet/auth"), phase: .previewing)))
            CodeRunCardView(coordinator: .preview(
                EditCodeRun(ask: "Make the greeting friendlier",
                            backend: .git(branch: "codepet/greet"), phase: .running),
                steps: [ExecStep(label: "Read hello.js", done: true),
                        ExecStep(label: "Edited hello.js", done: true)]))
            CodeRunCardView(coordinator: .preview(reviewing,
                steps: [ExecStep(label: "Read hello.js", done: true),
                        ExecStep(label: "Edited hello.js", done: true)]))
            CodeRunCardView(coordinator: .preview(
                EditCodeRun(ask: "Make the greeting friendlier",
                            backend: .git(branch: "codepet/greet"), phase: .committed)))
            CodeRunCardView(coordinator: .preview(
                EditCodeRun(ask: "Fix the login bug", backend: .shadow,
                            phase: .failed("Claude Code isn't installed or isn't on your PATH. Install it, then try again."))))
        }
        .padding()
    }
    .environmentObject(CompanyStore())
    .frame(width: 520, height: 900)
}
#endif
