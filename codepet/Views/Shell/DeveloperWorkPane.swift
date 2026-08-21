// codepet/Views/Shell/DeveloperWorkPane.swift
import SwiftUI

/// Developer's own surface: a session bar, the run, and the gate.
///
/// **Why this exists.** Awake Developer used to render `CopilotChatView` — literally
/// the Ask conversation — on the reasoning that "the conversation is where a run is
/// described and where it streams". Watching a real run land, that does not survive:
/// a code run rendered as chat bubbles has no exec log, no changed-file summary, no
/// branch and no Review gate. The founder's screenshot next to the prototype made it
/// plain — the prototype's Developer is a session bar over a work pane, and the app
/// was showing a transcript.
///
/// **It also has to DRIVE the run, not just draw it.** The first version rendered
/// three of the eight phases and called `execute()` from nowhere — the only caller
/// in the app is `CodeRunCardView`, which the Ask transcript renders and this pane
/// replaced. So a run proposed here reached `.previewing` and stopped: the header
/// read `PREPARING` forever, no steps, no diff, and the walkthrough's whole Developer
/// chapter played over a screen that never moved. Every phase now has a body, and
/// `DevRunStage` holds the rule about which one starts itself.
struct DeveloperWorkPane: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    /// Re-published from the coordinator; a view observing only `CompanyStore` does
    /// not re-render as steps arrive, which is the bug that made the dock's run log
    /// visibly stick.
    @ObservedObject var coordinator: CodingRunCoordinator

    /// Tabs belong to the SESSION, not the app (§5) — so they live here, with the
    /// surface that owns the session, rather than in a store everything can reach.
    @State private var tabs = InspectorTabs()
    @State private var mode: ChatMode = .ask
    @State private var dept: Department?
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                work
                // A SIBLING column, never a cover. The first prototype overlaid the
                // pane to show a deliverable and destroyed the transcript and its live
                // controls with it; §5 turns that into a rule, and this is where it is
                // kept. Collapses below the same window width the dock uses — one
                // threshold for "too narrow for a side panel", not two that drift.
                if !tabs.isEmpty,
                   !TwoModeLayout.inspectorCollapsed(forWidth: geo.size.width) {
                    TwoModeInspector(tabs: $tabs,
                                     diffs: coordinator.run?.diffs ?? [],
                                     branch: branchName,
                                     projectName: companyStore.activeProjectLink
                                        .map { Project.nameFromPath($0.path) } ?? "project")
                        .frame(width: TwoModeLayout.inspectorWidth(forWidth: geo.size.width))
                }
            }
        }
        .onAppear(perform: startIfReady)
        .onChange(of: coordinator.run?.phase) { _, phase in
            startIfReady()
            // Review comes forward BY ITSELF when a run finishes (§5). Waiting for the
            // founder to go looking for the diff would put the gate behind a click they
            // have no reason to make.
            guard phase == .reviewing, let run = coordinator.run, !run.diffs.isEmpty else { return }
            openReview(run)
            commitIfTheTierSaysSo(run)
        }
    }

    /// The pane is now the thing that starts a run, because it is the surface the
    /// founder describes one from. `DevRunStage.startsItself` carries the rule —
    /// `.readyToRun` goes, `.previewing` waits for the button below — so that the
    /// difference between "the diff is the gate" and "you approve the plan first"
    /// cannot be lost to a typo in a view.
    private func startIfReady() {
        guard DevRunStage.startsItself(coordinator.run?.phase) else { return }
        Task { await coordinator.execute() }
    }

    /// Keyed on the FILE SET, not the run: §5 is "one tab per output, not one per
    /// run", so a redo over the same files reopens the same tab instead of stacking
    /// a second Review the founder has to tell apart.
    private func openReview(_ run: EditCodeRun) {
        let key = run.diffs.map(\.path).sorted().joined(separator: "|")
        tabs.open(InspectorTab(id: "review-\(key)", kind: .review,
                               title: lang == .vi ? "Duyệt" : "Review"))
    }

    /// **`Let it run` commits without showing the diff first.**
    ///
    /// Spec §8.3 records this as an AMENDMENT to a written rail — "Codepet never
    /// writes the real tree without approval" — softened only by the founder's
    /// explicit per-session choice. So it is deliberately not silent: the review tab
    /// still opens (the diff is there to read AFTER the fact, which is the whole
    /// difference between this and not showing it at all), and the landed card says
    /// the commit happened without a review.
    ///
    /// The ceiling is untouched by this and by every other tier: no merge, no deploy,
    /// no delete, no force-push, nothing outside the linked folder. That is what makes
    /// a tier this permissive safe to offer — the worst case is still a branch you
    /// delete.
    private func commitIfTheTierSaysSo(_ run: EditCodeRun) {
        guard !companyStore.sessionApprovalTier.promptsBeforeCommit else { return }
        Task { await coordinator.approve(acceptedPaths: run.acceptedPaths) }
    }

    /// The branch, when there IS one.
    ///
    /// This used to return a hardcoded `"codepet/session"` for every run, which is a
    /// fabricated fact twice over: the git backend names its own branch off the ask,
    /// and the shadow backend has no branch at all — it copies the folder and applies
    /// back over it. The walkthrough links a plain temp folder, so the breadcrumb was
    /// showing a branch name for a directory that is `not a git repo`.
    private var branchName: String? {
        guard let run = coordinator.run else { return nil }
        switch run.backend {
        case .git(let branch): return branch
        case .shadow:          return nil
        }
    }

    private var stage: DevRunStage { DevRunStage.stage(for: coordinator.run?.phase) }

    private var work: some View {
        VStack(spacing: 0) {
            sessionBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    stageBody
                    ceiling
                }
                .readingColumn(ChatColumn.paneMeasureCap)
                .padding(.top, ChatRhythm.transcriptTop(.twoMode))
                .padding(.bottom, 24)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Describing the task is still a sentence you type, so the pane keeps a
    /// composer — dropping it with the transcript would have made Developer a
    /// read-only screen you could not start anything from.
    ///
    /// It sends through `startSessionBuild`, not `sendChat`: being in Developer IS
    /// the intent, which is the whole reason the mode pill retired. No department
    /// chips either — a code run is Engineering's verb and picking a department here
    /// would imply a choice that does not exist.
    ///
    /// `startSessionBuild` and not `startCodeRun`: the view must not choose the
    /// machine. It was choosing, and choosing wrong — always local, so an awake
    /// Developer on a cloud repo with no folder linked got `.noProject` back.
    private var composer: some View {
        VStack(spacing: 8) {
            ChatComposer(
                draft: $companyStore.chatDraft,
                mode: $mode,
                canSend: !companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && coordinator.run?.phase != .running,
                focus: $focused,
                placeholder: lang == .vi ? "Mô tả một tác vụ, hoặc hỏi về mã này…"
                                         : "Describe a task, or ask about this code…",
                quickActions: [],
                accent: CodepetTheme.accentPurple,
                accent2: CodepetTheme.accentPink,
                isBusy: coordinator.run?.phase == .running,
                showsDeptChips: false,
                tier: $companyStore.sessionApprovalTier,
                selectedDept: $dept,
                onSend: send,
                onQuickAction: { _ in }
            )
            .readingColumn(ChatColumn.paneMeasureCap)
            Text(lang == .vi
                 ? "Codepet là AI và có thể mắc lỗi. Hãy kiểm tra lại nội dung quan trọng."
                 : "Codepet is AI and can make mistakes. Please double-check its work.")
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundColor(CodepetTokens.faint)
        }
        .padding(.bottom, 14)
    }

    private func send() {
        let ask = companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        companyStore.chatDraft = ""
        companyStore.startSessionBuild(ask: ask)
    }

    // MARK: - Session bar

    /// The four facts the prototype puts above every run: which backend, which
    /// folder, which branch, and what it costs. Local is stated as **0 credits**
    /// because that is the whole argument for it — it is the founder's own CLI.
    private var sessionBar: some View {
        HStack(spacing: 7) {
            chip(local ? "▣ " + (lang == .vi ? "Cục bộ · 0 tín dụng" : "Local · 0 credits")
                       : "☁ " + (lang == .vi ? "Đám mây · tín dụng" : "Cloud · credits"),
                 tint: local ? CodepetTheme.accentGreen : CodepetTheme.accentGold)
            if let link = companyStore.activeProjectLink {
                chip(Project.nameFromPath(link.path), tint: nil)
                chip(link.isGitRepo ? "⌥ " + (lang == .vi ? "nhánh phiên" : "session branch")
                                    : (lang == .vi ? "không phải git" : "not a git repo"),
                     tint: nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(CodepetTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1)
        }
    }

    private var local: Bool { companyStore.activeProjectLink != nil }

    private func chip(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(CodepetTheme.inter(CodepetType.subheadline))
            .foregroundStyle(tint ?? CodepetTheme.mutedText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(CodepetTokens.cardRaised))
            .overlay(Capsule().stroke(tint?.opacity(0.5) ?? CodepetTokens.cardEdge))
            .lineLimit(1)
    }

    // MARK: - The run

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(coordinator.run?.ask ?? (lang == .vi ? "Chưa có phiên nào chạy"
                                                      : "No session running"))
                .font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                .foregroundStyle(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            statusDot
            Spacer(minLength: 0)
        }
    }

    /// `● RUNNING · STEP 3 OF 5` — the step count is what turns a spinner into a
    /// process, and the spec's rule is never to collapse the process into a spinner
    /// plus an answer.
    @ViewBuilder private var statusDot: some View {
        let (label, tint) = status
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(CodepetTheme.inter(CodepetType.footnote)).tracking(1)
                .foregroundStyle(tint)
        }
        .fixedSize()
    }

    private var status: (String, Color) {
        guard let run = coordinator.run else {
            return (lang == .vi ? "Sẵn sàng" : "Ready", CodepetTheme.mutedText)
        }
        switch run.phase {
        case .running:
            let done = coordinator.steps.filter(\.done).count
            let total = max(coordinator.steps.count, done)
            return (total > 0
                    ? (lang == .vi ? "Đang chạy · bước \(done)/\(total)"
                                   : "Running · step \(done) of \(total)")
                    : (lang == .vi ? "Đang chạy" : "Running"),
                    CodepetTheme.accentGold)
        case .reviewing:
            return (lang == .vi ? "Chờ bạn duyệt" : "Waiting on you", CodepetTheme.accentGold)
        case .committed:
            return (lang == .vi ? "Đã commit" : "Committed", CodepetTheme.accentGreen)
        case .discarded:
            return (lang == .vi ? "Đã bỏ" : "Discarded", CodepetTheme.mutedText)
        case .failed(let why):
            return (why, CodepetTheme.accentOrange)
        case .previewing, .readyToRun:
            return (lang == .vi ? "Chuẩn bị" : "Preparing", CodepetTheme.mutedText)
        case .noProject:
            return (lang == .vi ? "Ngủ đông" : "Dormant", CodepetTheme.mutedText)
        }
    }

    // MARK: - One body per phase

    /// Every phase draws something. A phase with no body is a screen that stops
    /// responding — which is exactly what `.previewing` did.
    @ViewBuilder private var stageBody: some View {
        switch stage {
        case .idle:
            hint(lang == .vi
                 ? "Mô tả một tác vụ bên dưới. Ở trong Developer CHÍNH LÀ ý định — không có chế độ nào phải chọn."
                 : "Describe a task below. Being in Developer *is* the intent — "
                 + "there is no mode to pick.")
        case .dormant:
            hint(lang == .vi
                 ? "Chưa liên kết thư mục nào, nên không có chỗ nào để chạy."
                 : "Nothing is linked, so there is nowhere for this to run.")
        case .plan:
            planCard
        case .working:
            execLog
        case .gate:
            execLog
            if let run = coordinator.run { editedFiles(run) }
        case .landed:
            stepSummary
            if let run = coordinator.run { committedCard(run) }
        case .dropped:
            runCard(kicker: lang == .vi ? "ĐÃ BỎ" : "DISCARDED", tint: CodepetTheme.mutedText) {
                Text(lang == .vi
                     ? "Không có gì chạm vào tệp của bạn. Việc từ chối cũng là một kết quả."
                     : "Nothing reached your files. Rejecting is an outcome too.")
                    .font(CodepetTheme.inter(CodepetType.callout))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                startAnother
            }
        case .failed(let why):
            runCard(kicker: lang == .vi ? "KHÔNG CHẠY ĐƯỢC" : "DID NOT RUN",
                    tint: CodepetTheme.accentOrange) {
                Text(why)
                    .font(CodepetTheme.inter(CodepetType.body))
                    .foregroundStyle(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lang == .vi
                     ? "Không có gì được ghi. Chạy lại là miễn phí trên máy của bạn."
                     : "Nothing was written. Retrying is free on your own machine.")
                    .font(CodepetTheme.inter(CodepetType.callout))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { retry() } label: {
                        actionLabel(lang == .vi ? "Thử lại" : "Try again", filled: true)
                    }
                    .buttonStyle(.plain)
                    Button { coordinator.cancel() } label: {
                        actionLabel(lang == .vi ? "Bỏ qua" : "Dismiss", filled: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(CodepetType.body))
            .foregroundStyle(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The plan gate. A multi-file change or one that needs a shell says so and
    /// waits — this is the confirmation `needsPreview` exists to demand, and the
    /// pane had no way to give it.
    private var planCard: some View {
        runCard(kicker: lang == .vi ? "KẾ HOẠCH" : "PLAN", tint: CodepetTheme.accentGold) {
            Text(lang == .vi
                 ? "Mình sẽ làm việc trên máy của bạn và có thể chạy lệnh terminal. Bạn duyệt mọi thay đổi trước khi có gì được lưu."
                 : "I'll work on your machine and may run terminal commands. "
                 + "You review every change before anything is saved.")
                .font(CodepetTheme.inter(CodepetType.body))
                .foregroundStyle(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { Task { await coordinator.execute() } } label: {
                    actionLabel(lang == .vi ? "Chạy" : "Run", filled: true)
                }
                .buttonStyle(.plain)
                Button { coordinator.cancel() } label: {
                    actionLabel(lang == .vi ? "Huỷ" : "Cancel", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Once the diff is the thing to look at, the steps collapse to their count —
    /// the prototype's shape, and it keeps the landed card at the bottom in view.
    @ViewBuilder private var stepSummary: some View {
        if !coordinator.steps.isEmpty {
            Text(lang == .vi ? "\(coordinator.steps.count) bước" : "\(coordinator.steps.count) steps")
                .font(CodepetTheme.inter(CodepetType.callout))
                .foregroundStyle(CodepetTokens.faint)
        }
    }

    private func committedCard(_ run: EditCodeRun) -> some View {
        runCard(kicker: lang == .vi ? "ĐÃ LƯU" : "LANDED", tint: CodepetTheme.accentGreen) {
            Text(landedWhere(run))
                .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
                .foregroundStyle(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            // Says so when nobody read it. `Let it run` is the founder's own choice
            // and the diff is still one tab away — but a landed card that reads the
            // same whether or not a human saw the change would quietly erase the
            // distinction the tier exists to make.
            if !companyStore.sessionApprovalTier.promptsBeforeCommit {
                Text(lang == .vi
                     ? "Đã commit mà không qua bước duyệt — bạn đã chọn \"Cứ chạy\" cho phiên này. Diff vẫn ở tab Duyệt."
                     : "Committed without a review — you chose \"Let it run\" for this session. "
                     + "The diff is still in the Review tab.")
                    .font(CodepetTheme.inter(CodepetType.callout))
                    .foregroundStyle(CodepetTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(lang == .vi
                 ? "Mở pull request khi bạn muốn nó được review. Codepet sẽ không merge hộ bạn."
                 : "Open a pull request when you want it reviewed. Codepet will not merge it for you.")
                .font(CodepetTheme.inter(CodepetType.callout))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            startAnother
        }
    }

    /// Where it actually landed, which is not the same sentence for both backends.
    /// The card used to say "committed to the session branch" for every run — for a
    /// folder that is not a git repo there is no branch and no commit: the shadow
    /// copy is applied back over the files, with a backup taken first.
    private func landedWhere(_ run: EditCodeRun) -> String {
        let n = run.diffs.count
        let files = n == 1 ? (lang == .vi ? "1 tệp" : "1 file")
                           : (lang == .vi ? "\(n) tệp" : "\(n) files")
        switch run.backend {
        case .git(let branch):
            return lang == .vi ? "\(files) trên nhánh \(branch). Merge là việc của bạn."
                               : "\(files) on \(branch). Merging is yours."
        case .shadow:
            return lang == .vi
                ? "\(files) đã ghi vào thư mục. Đây không phải repo git, nên không có nhánh nào để merge."
                : "\(files) written into the folder. This is not a git repo, so there is no branch to merge."
        }
    }

    private var startAnother: some View {
        Button { coordinator.cancel() } label: {
            actionLabel(lang == .vi ? "Bắt đầu việc khác" : "Start another task", filled: false)
        }
        .buttonStyle(.plain)
    }

    private func retry() {
        guard let ask = coordinator.run?.ask else { return }
        coordinator.cancel()
        companyStore.startSessionBuild(ask: ask)
    }

    /// Shared chrome for the phase cards, so a new phase gets the same object rather
    /// than a new one invented at the call site.
    private func runCard<C: View>(kicker: String, tint: Color,
                                  @ViewBuilder content: () -> C) -> some View {
        let sh = CodepetTokens.shadowS(scheme == .dark)
        return VStack(alignment: .leading, spacing: 8) {
            Text(kicker)
                .font(CodepetTheme.inter(CodepetType.footnote, weight: .semibold)).tracking(0.5)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(tint.opacity(0.30)))
        .shadow(color: sh.color, radius: sh.radius, x: sh.x, y: sh.y)
    }

    /// What it did, in its own words, as it does it.
    private var execLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A run that has started but streamed nothing yet is the one moment this
            // pane can honestly show a spinner: there is no step to name.
            if coordinator.steps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                    Text(lang == .vi ? "Đang bắt đầu…" : "Getting started…")
                        .font(CodepetTheme.inter(CodepetType.callout))
                        .foregroundStyle(CodepetTheme.mutedText)
                }
            }
            ForEach(coordinator.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.done ? "✓" : "●")
                        .font(CodepetTheme.inter(CodepetType.footnote))
                        .foregroundStyle(step.done ? CodepetTheme.accentGreen
                                                   : CodepetTheme.accentGold)
                        .frame(width: 12)
                    Text(step.label)
                        .font(CodepetTheme.inter(CodepetType.callout))
                        .foregroundStyle(step.done ? CodepetTheme.mutedText
                                                   : CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            // The tail, while more is still coming. The prototype draws the whole
            // five-step plan up front with the unreached ones greyed — this cannot,
            // because the runner streams its steps and does not declare them in
            // advance. Inventing a plan to grey out would be drawing steps no runner
            // promised, so it shows only that there is more.
            if coordinator.run?.phase == .running, !coordinator.steps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12)
                    Text(lang == .vi ? "đang làm…" : "working…")
                        .font(CodepetTheme.inter(CodepetType.callout))
                        .foregroundStyle(CodepetTokens.faint)
                }
            }
        }
    }

    /// The gate. Counts come from the diff itself rather than from the prose, so the
    /// card cannot claim a change size the run did not produce.
    ///
    /// The summary stays in the pane and the DIFF goes in the inspector — the
    /// prototype's "Edited 2 files · Review" shape. `Review` is here as a button as
    /// well as auto-opening, because a founder who closed the tab needs a way back
    /// to the thing they are being asked to approve.
    private func editedFiles(_ run: EditCodeRun) -> some View {
        let added = run.diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
        let removed = run.diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
        let names = run.diffs.map(\.fileName).joined(separator: " · ")
        let n = run.diffs.count
        return runCard(kicker: lang == .vi ? "ĐÃ SỬA \(n) TỆP"
                                           : (n == 1 ? "EDITED 1 FILE" : "EDITED \(n) FILES"),
                       tint: CodepetTheme.accentGold) {
            HStack(spacing: 8) {
                Text(names)
                    .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
                    .foregroundStyle(CodepetTheme.primaryText)
                Text("+\(added)").foregroundStyle(CodepetTheme.accentGreen)
                Text("−\(removed)").foregroundStyle(CodepetTheme.accentOrange)
            }
            .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            Text(lang == .vi ? "Đọc diff trước khi nó chạm vào tệp của bạn."
                             : "Read the diff before it touches your files.")
                .font(CodepetTheme.inter(CodepetType.callout))
                .foregroundStyle(CodepetTheme.mutedText)
            HStack(spacing: 8) {
                Button { openReview(run) } label: {
                    actionLabel(lang == .vi ? "Xem diff" : "Review", filled: false)
                }
                .buttonStyle(.plain)
                Button {
                    // `run.acceptedPaths`, NOT `diffs.map(\.path)`. The coordinator
                    // stores paths RELATIVE to the commit root and `applyShadow`
                    // appends them to it — handing it absolute paths built a
                    // nonexistent `/project//private/var/…`, every copy threw, and
                    // Approve ended in "Couldn't apply all the changes." The gate's
                    // one button failed on the walkthrough's own temp folder.
                    Task { await coordinator.approve(acceptedPaths: run.acceptedPaths) }
                } label: {
                    actionLabel(lang == .vi ? "Duyệt" : "Approve", filled: true)
                }
                .buttonStyle(.plain)
                Button { Task { await coordinator.reject() } } label: {
                    actionLabel(lang == .vi ? "Bỏ" : "Discard", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(CodepetTheme.inter(CodepetType.subheadline, weight: .semibold))
            .foregroundStyle(filled ? CodepetTheme.onAccent(CodepetTheme.accentPurple)
                                    : CodepetTheme.bodyText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(filled ? CodepetTheme.accentPurple : .clear))
            .overlay(filled ? nil : Capsule().stroke(CodepetTokens.cardEdge))
            .hoverAffordance(Capsule())
    }

    /// The tier ceiling, which belongs here rather than on the dormant screen — this
    /// is where a tier can actually be chosen, so this is where the limit is worth
    /// stating.
    private var ceiling: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1)
            Text((lang == .vi ? "KHÔNG BAO GIỜ, Ở BẤT KỲ MỨC NÀO" : "NEVER, AT ANY TIER"))
                .font(CodepetTheme.inter(CodepetType.footnote)).tracking(1)
                .foregroundStyle(CodepetTokens.faint)
                .padding(.top, 4)
            Text(ApprovalTier.ceiling(lang))
                .font(CodepetTheme.inter(CodepetType.subheadline))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}
