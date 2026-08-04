// codepet/Views/Roadmap/RoadmapView.swift
import SwiftUI

/// The Overview page (web parity: `OverviewSection.tsx`) — a Roadmap ⁄ Second Brain
/// toggle over the node-graph board. Chrome (progress, beacon, states KEY) lives in
/// `OverviewChromeRow`; the first-run briefing lives in `OverviewIntroSheet`.
struct RoadmapView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var lang
    @State private var showMapIntro = false
    @State private var introShown = false
    @State private var openDeliverable: Deliverable?
    @State private var overviewTab: OverviewTab = .roadmap
    /// Measured width of the header row — drives the compact/roomy control switch.
    @State private var headerWidth: CGFloat = 0
    private enum OverviewTab: Hashable { case roadmap, secondBrain }

    /// Matches the surrounding chrome (`AppShellView.accent`) — web threads one
    /// `--accent` through both. Founder call (Aug 3): that accent is Codepet purple,
    /// NOT the companion's colour. Previously read from `appState.activeChar`, which
    /// made the whole board, its connectors and the root node's glow red under Crash.
    private var accent: Color { CodepetTheme.accentPurple }

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    /// Placeholder-junk filtered, mirroring web's `cleanCompanyName` — onboarding lets people
    /// type anything, so a company name that's really "12" or an email must not reach the UI.
    private var projectName: String? {
        MeaningfulText.clean(companyStore.company.brief.projectName)
    }
    /// Placeholder-junk filtered, mirroring web's `meaningfulText` — a one-liner of "12" must
    /// not reach the briefing subtitle or the root node's tagline.
    private var oneLiner: String? {
        MeaningfulText.clean(companyStore.company.brief.oneLiner)
    }
    /// The ONE display name for the company, used by the briefing headline AND the board's root
    /// node. Web derives both from a single `cleanCompanyName(brief.projectName) ?? 'Your company'`
    /// (`OverviewSection.tsx:103`); passing the raw optional to one surface and the trimmed one to
    /// another gave a blank root-node title for a whitespace-only name, and two different
    /// fallbacks ("Codepet" vs "Your company") for the same account in the same session.
    private var displayProjectName: String {
        projectName ?? (lang == .vi ? "Công ty của bạn" : "Your company")
    }
    /// Web parity: once we know the company, say whose it is and what it is; otherwise the generic framing.
    private var subtitle: String {
        if let p = projectName, let o = oneLiner { return "\(p) — \(o)" }
        return lang == .vi
            ? "Toàn bộ công ty của bạn dưới dạng lộ trình — bạn đang ở đâu, \(companionName) làm gì tiếp theo, và bạn đã đi được bao xa."
            : "Your whole company as a roadmap — where you are, what \(companionName) does next, and how far you've come."
    }
    /// Codepet's read of the company for the briefing — web's fallback chain minus the AI
    /// `projectAnalysis` layer, which native doesn't have yet.
    private var briefSummary: String? {
        MeaningfulText.clean(companyStore.company.brief.summary) ?? oneLiner
    }
    /// Placeholder-junk filtered, mirroring web's `meaningfulText` — the founder's name feeds
    /// the "MONA IS HERE"-style marker, so a junk value there must fall back the same way.
    private var founderName: String? {
        MeaningfulText.clean(companyStore.company.brief.founderName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if overviewTab == .roadmap {
                roadmapBody
            } else {
                overviewToggle.padding(.horizontal, 24).padding(.top, 16)
                SecondBrainView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(isPresented: $showMapIntro) {
            OverviewIntroSheet(companionName: companionName,
                               projectName: displayProjectName,
                               summary: briefSummary, tasks: tasks,
                               accent: accent,
                               onDismiss: {
                                   showMapIntro = false
                                   Task { await companyStore.markIntroSeen() }
                               })
        }
        .onChange(of: tasks.isEmpty, initial: true) { _, isEmpty in
            // First-run briefing: wait until the roadmap has resolved so the sheet can name the
            // founder's first move. On a fresh account `generateRoadmap` is still in flight when
            // this view appears, and a briefing without "First up: …" loses the one line it exists
            // to deliver. `introSeenAt` keeps it once-per-account; `introShown` keeps it once per
            // appearance so dismissing it mid-session can't immediately re-trigger it.
            guard !isEmpty, !introShown, companyStore.company.introSeenAt == nil else { return }
            introShown = true
            showMapIntro = true
        }
    }

    /// The former `body` contents (roadmap map + chrome), extracted so the toggle can swap it.
    private var roadmapBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 22)
            OverviewChromeRow(tasks: tasks, companionName: companionName, accent: accent,
                              onStart: { dispatch($0) }, onOpenTask: { dispatch($0) })
                .padding(.horizontal, 24).padding(.top, 16)
            RoadmapBoardView(tasks: tasks, companionName: companionName,
                             founderName: founderName,
                             projectName: displayProjectName,
                             tagline: oneLiner,
                             accent: accent,
                             onTaskTap: { dispatch($0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var overviewToggle: some View {
        HStack(spacing: 3) {
            segment(.roadmap, lang == .vi ? "Lộ trình" : "Roadmap")
            segment(.secondBrain, lang == .vi ? "Bộ não" : "Second Brain")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    private func segment(_ t: OverviewTab, _ label: String) -> some View {
        let on = overviewTab == t
        return Button { overviewTab = t } label: {
            // `fixedSize` is load-bearing: without it a squeezed row wraps this label
            // one character per line ("Roa / dm / ap") instead of pushing back.
            Text(label)
                .font(CodepetTheme.inter(12.5, weight: .semibold))
                .foregroundColor(on ? accent : CodepetTheme.mutedText)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(on ? CodepetTokens.accentTint : .clear))
        }
        .buttonStyle(.plain)
    }

    private var howToReadLabel: String {
        lang == .vi ? "Cách đọc bản đồ" : "How to read this map"
    }

    /// Windowed vs fullscreen: the content pane is half the shell, so leaving fullscreen
    /// can halve this header's width. The controls must never be the thing that gives —
    /// squeezed, their labels wrapped one character per line — so they hold their
    /// intrinsic size (`layoutPriority`) and the title block yields instead. Past
    /// `compactHeaderMaxWidth` even that isn't enough, and the How-to button sheds its
    /// label to keep everything on one row.
    private var header: some View {
        let compact = ShellLayout.compactPageHeader(forWidth: headerWidth)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Tổng quan" : "Overview")
                    .font(CodepetTheme.title()).tracking(-0.5).foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1)
                Text(subtitle).font(CodepetTheme.subtitle())
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .layoutPriority(0)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Button { showMapIntro = true } label: {
                    HStack(spacing: 8) {
                        Text("?").font(CodepetTheme.inter(11, weight: .bold))
                            .foregroundColor(CodepetTheme.onAccent(accent))
                            .frame(width: 15, height: 15).background(Circle().fill(accent))
                        if !compact {
                            Text(howToReadLabel)
                                .font(CodepetTheme.inter(12.5, weight: .semibold)).foregroundColor(accent)
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.horizontal, compact ? 8 : 13).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTokens.accentTint))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CodepetTokens.accentLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(howToReadLabel)
                .accessibilityLabel(howToReadLabel)
                overviewToggle
            }
            .layoutPriority(1)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
    }

    /// Route a task tap through the pure `RoadmapDispatch` rule, then follow the two
    /// streaming actions (run, walk-through) to chat, where their output appears.
    /// Approve and open-deliverable resolve in place and do not navigate.
    ///
    /// `depth` guards the one recursive case: tapping a LOCKED card redirects to the step
    /// holding it up (`.showBlocker`). One hop only — a dangling or cyclic graph must not
    /// bounce forever, and a blocker that is itself blocked has nothing useful to offer.
    private func dispatch(_ task: RoadmapTask, depth: Int = 0) {
        let action = RoadmapDispatch.action(for: RoadmapEngine.status(for: task, in: tasks),
                                            isEngineering: task.dept == "eng",
                                            projectLinked: companyStore.activeProjectLink != nil)
        switch action {
        case .run:              Task { await companyStore.runTask(task, language: lang) }
        case .walkThrough:      Task { await companyStore.walkThroughTask(task, language: lang) }
        case .approve:          Task { await companyStore.approveTask(id: task.id) }
        case .openDeliverable:  openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
        case .editCode:
            companyStore.codingRunAnchorId = nil   // no chat ask → card at transcript bottom
            companyStore.codingRun.propose(ask: RoadmapDispatch.editCodeAsk(for: task),
                                           plannedFiles: 2, needsBash: false,
                                           link: companyStore.activeProjectLink)
        case .showBlocker:
            guard depth == 0, let blocker = RoadmapGating.blocker(for: task, in: tasks) else { break }
            dispatch(blocker, depth: 1)
        case .none:             break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.dockCollapsed = false }
    }
}
