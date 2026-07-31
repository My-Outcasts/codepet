// codepet/Views/Roadmap/RoadmapView.swift
import SwiftUI

/// The Overview page (web parity: `OverviewSection.tsx`) — a Roadmap ⁄ Second Brain
/// toggle over the node-graph board. Chrome (progress, beacon, states KEY) lives in
/// `OverviewChromeRow`; the first-run briefing lives in `OverviewIntroSheet`.
struct RoadmapView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showMapIntro = false
    @State private var openDeliverable: Deliverable?
    @State private var overviewTab: OverviewTab = .roadmap
    private enum OverviewTab: Hashable { case roadmap, secondBrain }

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var projectName: String? {
        let p = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }
    private var oneLiner: String? {
        let o = (companyStore.company.brief.oneLiner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return o.isEmpty ? nil : o
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
        let s = (companyStore.company.brief.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? oneLiner : s
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
                               projectName: projectName ?? (lang == .vi ? "Công ty của bạn" : "Your company"),
                               summary: briefSummary, tasks: tasks,
                               onDismiss: {
                                   showMapIntro = false
                                   Task { await companyStore.markIntroSeen() }
                               })
        }
        .onAppear { if companyStore.company.introSeenAt == nil { showMapIntro = true } }
    }

    /// The former `body` contents (roadmap map + chrome), extracted so the toggle can swap it.
    private var roadmapBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 22)
            OverviewChromeRow(tasks: tasks, companionName: companionName,
                              onStart: { dispatch($0) }, onOpenTask: { dispatch($0) })
                .padding(.horizontal, 24).padding(.top, 16)
            RoadmapBoardView(tasks: tasks, companionName: companionName,
                             founderName: companyStore.company.brief.founderName,
                             projectName: (companyStore.company.brief.projectName ?? "Codepet"),
                             tagline: companyStore.company.brief.oneLiner,
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
            Text(label)
                .font(CodepetTheme.inter(12.5, weight: .semibold))
                .foregroundColor(on ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(on ? CodepetTokens.accentTint : .clear))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Tổng quan" : "Overview")
                    .font(CodepetTheme.title()).tracking(-0.5).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(CodepetTheme.subtitle())
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 10) {
                Button { showMapIntro = true } label: {
                    HStack(spacing: 8) {
                        Text("?").font(CodepetTheme.inter(11, weight: .bold))
                            .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                            .frame(width: 15, height: 15).background(Circle().fill(CodepetTheme.accentPurple))
                        Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                            .font(CodepetTheme.inter(12.5, weight: .semibold)).foregroundColor(CodepetTheme.accentPurple)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTokens.accentTint))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CodepetTokens.accentLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                overviewToggle
            }
        }
    }

    /// Route a task tap through the pure `RoadmapDispatch` rule, then follow the two
    /// streaming actions (run, walk-through) to chat, where their output appears.
    /// Approve and open-deliverable resolve in place and do not navigate.
    private func dispatch(_ task: RoadmapTask) {
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
        case .none:             break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.dockCollapsed = false }
    }
}
