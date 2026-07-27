// codepet/Views/Roadmap/RoadmapView.swift
import SwiftUI

/// The Roadmap page — was the left half of the retired Overview toggle, and now
/// owns the chrome that page carried: progress, the beacon, the KEY legend and the
/// "how to read this map" briefing, over the node-graph map.
struct RoadmapView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showMapIntro = false
    @State private var beaconPinging = false
    @State private var openDeliverable: Deliverable?

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var needsYouCount: Int {
        tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou }.count
    }
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var subtitle: String {
        let p = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let o = (companyStore.company.brief.oneLiner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty && o.isEmpty { return lang == .vi ? "Lộ trình xây dựng công ty của bạn" : "Your company-building roadmap" }
        return [p, o].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 22)
            chromeRow.padding(.horizontal, 24).padding(.top, 14)
            RoadmapMapView(tasks: tasks).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Lộ trình" : "Roadmap")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(CodepetTheme.subtitle())
                    .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
            Spacer()
            Button { showMapIntro = true } label: {
                HStack(spacing: 8) {
                    Text("?").font(CodepetTheme.inter(11, weight: .bold)).foregroundColor(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(CodepetTheme.accentPurple))
                    Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                        .font(CodepetTheme.inter(13, weight: .medium)).foregroundColor(CodepetTheme.accentPurple)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.accentPurple.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMapIntro) { mapIntroBriefing }
        }
    }

    private var chromeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            progressCard
            if let b = beacon { beaconCard(b) }
            Spacer()
            legend
        }
    }

    private var alsoNeedsYou: RoadmapTask? {
        tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != beacon?.id }.first
    }

    /// Routes a task tap through the pure rule, then follows streaming actions to chat.
    private func dispatch(_ task: RoadmapTask) {
        let action = RoadmapDispatch.action(for: RoadmapEngine.status(for: task, in: tasks))
        switch action {
        case .run:              Task { await companyStore.runTask(task, language: lang) }
        case .walkThrough:      Task { await companyStore.walkThroughTask(task, language: lang) }
        case .approve:          Task { await companyStore.approveTask(id: task.id) }
        case .openDeliverable:  openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
        case .none:             break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.select(.chat) }
    }

    private var currentPhase: RoadmapPhase { beacon?.phase ?? .find }
    private var nextPhaseLabel: String? {
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: currentPhase), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(lang == .vi ? "Tiến độ" : "Project Progress")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                Text(currentPhase.label(lang)).font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(pct)").font(CodepetTheme.inter(30, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Text("%").font(CodepetTheme.inter(14, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
                if needsYouCount > 0 {
                    Text(lang == .vi ? "cần bạn \(needsYouCount)" : "needs you \(needsYouCount)")
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.accentBlue)
                }
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(pct), total: 100).tint(CodepetTheme.accentPurple).frame(width: 120)
                if let next = nextPhaseLabel {
                    Text((lang == .vi ? "Tiếp: " : "Next: ") + next)
                        .font(CodepetTheme.inter(10, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    private func beaconCard(_ b: RoadmapTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                beaconPingDot
                Text("\(companionName.uppercased()) · " + (lang == .vi ? "LÀM ĐIỀU NÀY TIẾP" : "DO THIS NEXT"))
                    .font(CodepetTheme.inter(10, weight: .bold)).foregroundColor(CodepetTheme.accentPurple)
            }
            Text(b.title).font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button { dispatch(b) } label: {
                Text(lang == .vi ? "Bắt đầu" : "Start")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }.buttonStyle(.plain)
            if let also = alsoNeedsYou {
                Button { dispatch(also) } label: {
                    Text((lang == .vi ? "Cũng cần bạn: " : "Also needs you: ") + also.title)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.accentBlue).lineLimit(1)
                        .underline()
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.accentPurple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.accentPurple.opacity(0.3), lineWidth: 1))
    }

    private var beaconPingDot: some View {
        ZStack {
            Circle().fill(CodepetTheme.accentPurple)
                .frame(width: 13, height: 13)
                .scaleEffect(beaconPinging ? 2.9 : 1)
                .opacity(beaconPinging ? 0 : 0.5)
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                beaconPinging = true
            }
        }
    }

    private var mapIntroBriefing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                .font(CodepetTheme.inter(13, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text((lang == .vi ? "Giai đoạn hiện tại: " : "Current phase: ") + currentPhase.label(lang))
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.accentPurple)
                if let next = nextPhaseLabel {
                    Text((lang == .vi ? "Tiếp theo: " : "Next: ") + next)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                if let title = beacon?.title {
                    Text((lang == .vi ? "Bước tiếp theo: " : "Up next: ") + title)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            legend
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private var legend: some View {
        let items: [(String, Color)] = [
            (lang == .vi ? "Xong" : "Done", taskStatusTint(.done)),
            (lang == .vi ? "\(companionName) làm được" : "\(companionName) can do this", taskStatusTint(.codepetCanDo)),
            (lang == .vi ? "Cần bạn nhập" : "Needs your input", taskStatusTint(.needsYou)),
            (lang == .vi ? "Cần duyệt" : "Needs approval", taskStatusTint(.needsApproval)),
            (lang == .vi ? "Cần bước trước" : "Needs earlier steps", taskStatusTint(.blocked)),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text(lang == .vi ? "CHÚ THÍCH" : "KEY")
                .font(CodepetTheme.inter(10, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
            ForEach(items, id: \.0) { it in
                HStack(spacing: 6) {
                    Circle().fill(it.1).frame(width: 7, height: 7)
                    Text(it.0).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }
}
