// codepet/Views/Overview/OverviewIntroSheet.swift
import SwiftUI

/// The Overview briefing — Codepet introduces the map in its own voice. Auto-shows once per
/// account, and "How to read this map" reopens it any time, so the instructions are never
/// lost after the one-time dismissal. Native port of the modal in web `OverviewSection.tsx`.
struct OverviewIntroSheet: View {
    let projectName: String
    /// Codepet's one-line read of the company. Web prefers its AI `projectAnalysis.overall` and
    /// falls back through the brief; native has no analysis surface yet, so the caller passes
    /// `brief.summary ?? brief.oneLiner` and the paragraph is simply omitted when both are empty.
    let summary: String?
    let tasks: [RoadmapTask]
    let accent: Color
    let onDismiss: () -> Void

    @Environment(\.uiLanguage) private var lang

    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var currentPhase: String? { beacon?.phase.label(lang) }
    private var nextMilestone: String? {
        guard let p = beacon?.phase else { return nil }
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: p), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // The Codepet mark. This was a bare gradient square, which read as an image that
                // failed to load.
                Image("codepet-logo")
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CODEPET")
                        .font(CodepetTheme.inter(10.5, weight: .semibold)).tracking(1.26)
                        .foregroundColor(accent)
                    Text(lang == .vi ? "\(projectName), trên bản đồ" : "\(projectName), mapped")
                        .font(CodepetTheme.inter(19, weight: .bold)).tracking(-0.19)
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
            .padding(.bottom, 15)

            if let summary, !summary.isEmpty {
                Text(summary).font(CodepetTheme.inter(14.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(phaseLine).font(CodepetTheme.inter(13.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTokens.accentTint))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTokens.accentLine, lineWidth: 1))
            .padding(.bottom, 16)

            Text(lang == .vi ? "CÁCH ĐỌC BẢN ĐỒ" : "HOW TO READ THE MAP")
                .font(CodepetTheme.inter(12, weight: .semibold)).tracking(0.72)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 11) {
                Text(nextMoveIntro).font(CodepetTheme.inter(13.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(bullets, id: \.1) { color, head, body in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
                        (Text(head).font(CodepetTheme.inter(13.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                         + Text(" — \(body)").font(CodepetTheme.inter(13.5))
                            .foregroundColor(CodepetTheme.bodyText))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 22)

            Button(action: onDismiss) {
                Text(lang == .vi ? "Đã hiểu — xem ngay" : "Got it — show me")
                    .font(CodepetTheme.inter(14, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(accent))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                    .shadow(color: accent.opacity(0.7), radius: 11, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 22)
        .frame(width: 440)
        .background(CodepetTheme.surface)
    }

    private var phaseLine: String {
        let phase = currentPhase ?? (lang == .vi ? "đầu tiên" : "first")
        var s = lang == .vi ? "Bạn đang ở giai đoạn \(phase)" : "You’re in the \(phase) phase"
        if let m = nextMilestone {
            s += lang == .vi ? " — mốc tiếp theo: \(m)." : " — next milestone: \(m)."
        } else {
            s += "."
        }
        if let t = beacon?.title {
            s += lang == .vi ? " Đầu tiên: \(t)." : " First up: \(t)."
        }
        return s
    }

    /// "The glowing card is your next move — press “<its real button>” on it."
    private var nextMoveIntro: String {
        let label = beacon.map {
            RoadmapBoardCopy.panelActionLabel(for: RoadmapEngine.status(for: $0, in: tasks), lang)
        }
        let head = lang == .vi ? "Thẻ đang sáng là nước đi tiếp theo" : "The glowing card is your next move"
        return "\(head) — \(RoadmapBoardCopy.nextMoveLine(actionLabel: label, lang))"
    }

    /// The same five states, colours and names as the KEY beside the board.
    private var bullets: [(Color, String, String)] {
        RoadmapBoardCopy.keyStatuses.map {
            (RoadmapPalette.tint(for: $0),
             RoadmapBoardCopy.keyLabel(for: $0, lang),
             RoadmapBoardCopy.keyMeaning(for: $0, lang))
        }
    }
}
