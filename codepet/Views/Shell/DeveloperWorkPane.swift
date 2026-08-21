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
/// **What it deliberately is not (yet).** The prototype also carries an INSPECTOR —
/// a tabbed diff beside the conversation, `Result ⇄ Source`. That is the next slice
/// and a larger one; this pane stops at the Review gate and hands off to the diff
/// surface that already exists. Better a pane that ends honestly than one that
/// implies a panel which is not there.
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
        // Review comes forward BY ITSELF when a run finishes (§5). Waiting for the
        // founder to go looking for the diff would put the gate behind a click they
        // have no reason to make.
        .onChange(of: coordinator.run?.phase) { _, phase in
            guard phase == .reviewing, let run = coordinator.run, !run.diffs.isEmpty else { return }
            // Keyed on the FILE SET, not the run: §5 is "one tab per output, not one
            // per run", so a redo over the same files reopens the same tab instead of
            // stacking a second Review the founder has to tell apart.
            let key = run.diffs.map(\.path).sorted().joined(separator: "|")
            tabs.open(InspectorTab(id: "review-\(key)", kind: .review,
                                   title: lang == .vi ? "Duyệt" : "Review"))
        }
    }

    private var branchName: String? {
        guard let run = coordinator.run else { return nil }
        switch run.phase {
        case .committed, .reviewing: return "codepet/session"
        default: return nil
        }
    }

    private var work: some View {
        VStack(spacing: 0) {
            sessionBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !coordinator.steps.isEmpty { execLog }
                    if let run = coordinator.run, !run.diffs.isEmpty { editedFiles(run) }
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
    /// It sends through `startCodeRun`, not `sendChat`: being in Developer IS the
    /// intent, which is the whole reason the mode pill retired. No department chips
    /// either — a code run is Engineering's verb and picking a department here would
    /// imply a choice that does not exist.
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
        companyStore.startCodeRun(ask: ask)
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

    /// What it did, in its own words, as it does it.
    private var execLog: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
    }

    /// The gate. Counts come from the diff itself rather than from the prose, so the
    /// card cannot claim a change size the run did not produce.
    private func editedFiles(_ run: EditCodeRun) -> some View {
        let added = run.diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
        let removed = run.diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
        let names = run.diffs.map(\.fileName).joined(separator: " · ")
        let reviewing = run.phase == .reviewing
        let sh = CodepetTokens.shadowS(scheme == .dark)
        return VStack(alignment: .leading, spacing: 8) {
            Text((lang == .vi ? "ĐÃ SỬA \(run.diffs.count) TỆP" : "EDITED \(run.diffs.count) FILES"))
                .font(CodepetTheme.inter(CodepetType.footnote, weight: .semibold)).tracking(0.5)
                .foregroundStyle(CodepetTheme.accentGold)
            HStack(spacing: 8) {
                Text(names)
                    .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
                    .foregroundStyle(CodepetTheme.primaryText)
                Text("+\(added)").foregroundStyle(CodepetTheme.accentGreen)
                Text("−\(removed)").foregroundStyle(CodepetTheme.accentOrange)
            }
            .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)

            if reviewing {
                HStack(spacing: 8) {
                    Button {
                        Task { await coordinator.approve(acceptedPaths: Set(run.diffs.map(\.path))) }
                    } label: {
                        actionLabel(lang == .vi ? "Duyệt" : "Review and approve", filled: true)
                    }
                    .buttonStyle(.plain)
                    Button { Task { await coordinator.reject() } } label: {
                        actionLabel(lang == .vi ? "Bỏ" : "Discard", filled: false)
                    }
                    .buttonStyle(.plain)
                }
            } else if run.phase == .committed {
                Text(lang == .vi
                     ? "Đã commit lên nhánh của phiên. Merge là việc của bạn."
                     : "Committed to the session branch. Merging is yours.")
                    .font(CodepetTheme.inter(CodepetType.callout))
                    .foregroundStyle(CodepetTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(CodepetTokens.goldTint))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CodepetTokens.goldLine))
        .shadow(color: sh.color, radius: sh.radius, x: sh.x, y: sh.y)
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
            Text(lang == .vi
                 ? "merge · deploy · xoá · force-push · chạm vào tệp ngoài thư mục"
                 : "merge · deploy · delete · force-push · touch a file outside the folder")
                .font(CodepetTheme.inter(CodepetType.subheadline))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}
