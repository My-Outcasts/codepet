// codepet/Views/Overview/OverviewChromeRow.swift
import SwiftUI

/// Project Progress + Do This Next side by side, with the states KEY pushed right — one
/// compact top strip so the roadmap below gets the space. Native port of the strip in the
/// web `OverviewSection.tsx`.
struct OverviewChromeRow: View {
    let tasks: [RoadmapTask]
    let companionName: String
    let onStart: (RoadmapTask) -> Void
    let onOpenTask: (RoadmapTask) -> Void

    @Environment(\.uiLanguage) private var lang
    @State private var pinging = false

    /// The two cards sit side by side, each ~HUD-sized. The row is capped so they stay small.
    private let panelW: CGFloat = 430

    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var currentPhase: RoadmapPhase? { beacon?.phase }
    private var nextMilestone: String? {
        guard let p = currentPhase else { return nil }
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: p), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }
    /// The one actionable nudge kept on the compact card: tasks that need the founder.
    private var needsYou: Int {
        tasks.filter { !$0.done && !$0.drafted && $0.who == .you }.count
    }
    /// The founder often ALSO has a step waiting on them — surface the top one as a distinct
    /// secondary line under Start, never the same task as the move.
    private var alsoNeedsYou: RoadmapTask? {
        tasks.first { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou
                      && $0.id != beacon?.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            HStack(alignment: .top, spacing: 14) {
                progressCard
                if let b = beacon { beaconCard(b) }
            }
            .frame(maxWidth: panelW, alignment: .leading)
            Spacer(minLength: 0)
            key
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(lang == .vi ? "Tiến độ dự án" : "Project Progress")
                    .font(CodepetTheme.inter(12.5, weight: .semibold)).tracking(-0.125)
                    .foregroundColor(CodepetTheme.primaryText)
                if let p = currentPhase {
                    Text(p.label(lang))
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(CodepetTokens.accentTint))
                        .overlay(Capsule().stroke(CodepetTokens.accentLine, lineWidth: 1))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(pct)").font(CodepetTheme.inter(22, weight: .bold)).tracking(-0.66)
                        .foregroundColor(CodepetTheme.primaryText)
                        .monospacedDigit()
                    Text("%").font(CodepetTheme.inter(13, weight: .bold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                if needsYou > 0 {
                    Text(lang == .vi ? "cần bạn \(needsYou)" : "needs you \(needsYou)")
                        .font(CodepetTheme.inter(12)).foregroundColor(RoadmapPalette.needsYou)
                }
            }
            .padding(.top, 3).padding(.bottom, 6)
            progressBar
        }
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    // A 14pt well with a glowing gradient fill, and the next-milestone chip riding INSIDE
    // the bar at its right end (web: `position:absolute; right:5`).
    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(CodepetTokens.well)
                Capsule()
                    .fill(LinearGradient(colors: [CodepetTokens.accentDeep, CodepetTheme.accentPurple],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(pct > 0 ? 14 : 0, g.size.width * CGFloat(pct) / 100))
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.5), radius: 5.5)
                if let next = nextMilestone {
                    HStack {
                        Spacer()
                        Text((lang == .vi ? "Tiếp: " : "Next: ") + next)
                            .font(CodepetTheme.inter(10.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(CodepetTokens.accentTint))
                            .padding(.trailing, 5)
                    }
                }
            }
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8), value: pct)
        }
        .frame(height: 14)
    }

    private func beaconCard(_ b: RoadmapTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                pingDot
                Text("\(companionName) · " + (lang == .vi ? "LÀM ĐIỀU NÀY TIẾP" : "DO THIS NEXT"))
                    .font(CodepetTheme.inter(10)).tracking(1.3)      // web .13em at 10px
                    .foregroundColor(CodepetTheme.accentPurple)
                    .textCase(.uppercase)
            }
            Text(b.title).font(CodepetTheme.inter(13, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button { onStart(b) } label: {
                Text(lang == .vi ? "Bắt đầu" : "Start")
                    .font(CodepetTheme.inter(12.5, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(CodepetTheme.accentPurple))
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 7, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            if let also = alsoNeedsYou {
                Button { onOpenTask(also) } label: {
                    HStack(spacing: 5) {
                        Text(lang == .vi ? "Cũng cần bạn:" : "Also needs you:")
                            .foregroundColor(RoadmapPalette.needsYou.opacity(0.75))
                        Text(also.title).underline().lineLimit(1)
                            .foregroundColor(RoadmapPalette.needsYou)
                    }
                    .font(CodepetTheme.inter(11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help((lang == .vi ? "Cũng cần bạn: " : "Also needs you: ") + also.title)
            }
        }
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTokens.accentTint))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTokens.accentLine, lineWidth: 1))
    }

    // Web `@keyframes beaconPing`: a ring scaling 1→2.9 while fading .5→0, looping.
    private var pingDot: some View {
        ZStack {
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
                .scaleEffect(pinging ? 2.9 : 1).opacity(pinging ? 0 : 0.5)
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
                .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 6)
        }
        .frame(width: 13, height: 13)
        .onAppear {
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pinging = true
            }
        }
    }

    // Teaches a first-time user what the card colors mean. Order matches the web legend.
    private var key: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(lang == .vi ? "CHÚ THÍCH" : "KEY")
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1.2)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.bottom, 1)
            ForEach(keyItems, id: \.0) { item in
                HStack(spacing: 8) {
                    Circle().fill(item.1).frame(width: 7, height: 7)
                    Text(item.0).font(CodepetTheme.inter(11.5))
                        .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    private var keyItems: [(String, Color)] {
        [
            (lang == .vi ? "Xong" : "Done", RoadmapPalette.done),
            (lang == .vi ? "\(companionName) làm được" : "\(companionName) can do this", RoadmapPalette.canDo),
            (lang == .vi ? "Cần bạn nhập" : "Needs your input", RoadmapPalette.needsYou),
            (lang == .vi ? "Cần duyệt" : "Needs approval", RoadmapPalette.approve),
            (lang == .vi ? "Cần bước trước" : "Needs earlier steps", RoadmapPalette.blocked),
        ]
    }
}
