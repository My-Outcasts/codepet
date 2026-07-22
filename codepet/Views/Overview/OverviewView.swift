// codepet/Views/Overview/OverviewView.swift
import SwiftUI

/// The Overview page (web OverviewSection.tsx): title/subtitle + Roadmap/Second-Brain
/// toggle + "how to read this map" + progress/beacon chrome + KEY legend, over the
/// node-graph map. Second Brain is a stub ("coming soon").
struct OverviewView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showSecondBrain = false

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var needsYouCount: Int { tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou }.count }
    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }
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
            if showSecondBrain {
                Spacer()
                Text(lang == .vi ? "Bộ não thứ hai — sắp có" : "Second Brain — coming soon")
                    .font(CodepetTheme.inter(14)).foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                RoadmapMapView(tasks: tasks).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Tổng quan" : "Overview").font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("?").font(CodepetTheme.inter(11, weight: .bold)).foregroundColor(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(CodepetTheme.accentPurple))
                    Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                        .font(CodepetTheme.inter(13, weight: .medium)).foregroundColor(CodepetTheme.accentPurple)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.accentPurple.opacity(0.4), lineWidth: 1))
                segmentToggle
            }
        }
    }

    private var segmentToggle: some View {
        HStack(spacing: 4) {
            ForEach([false, true], id: \.self) { sb in
                let on = showSecondBrain == sb
                Button { showSecondBrain = sb } label: {
                    Text(sb ? (lang == .vi ? "Bộ não" : "Second Brain") : (lang == .vi ? "Lộ trình" : "Roadmap"))
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(on ? CodepetTheme.accentPurple : CodepetTheme.bodyText)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? CodepetTheme.accentPurple.opacity(0.28) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? CodepetTheme.accentPurple.opacity(0.5) : Color.clear, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    private var chromeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            progressCard
            if let b = beacon { beaconCard(b) }
            Spacer()
            legend   // web keeps the KEY legend always visible beside progress/beacon
        }
    }

    // The second founder task that needs input, for the beacon's "Also needs you" line.
    private var alsoNeedsYou: RoadmapTask? {
        tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != beacon?.id }.first
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
            Text("\(companionName.uppercased()) · " + (lang == .vi ? "LÀM ĐIỀU NÀY TIẾP" : "DO THIS NEXT"))
                .font(CodepetTheme.inter(10, weight: .bold)).foregroundColor(CodepetTheme.accentPurple)
            Text(b.title).font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button { Task { await companyStore.runTask(b, language: lang) } } label: {
                Text(lang == .vi ? "Bắt đầu" : "Start")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }.buttonStyle(.plain)
            if let also = alsoNeedsYou {
                Text((lang == .vi ? "Cũng cần bạn: " : "Also needs you: ") + also.title)
                    .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.accentBlue).lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.accentPurple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.accentPurple.opacity(0.3), lineWidth: 1))
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
