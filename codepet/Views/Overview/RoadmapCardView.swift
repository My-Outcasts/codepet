// codepet/Views/Overview/RoadmapCardView.swift
import SwiftUI

/// One roadmap board card — a native port of `Node` in the web `RoadmapView.tsx`.
///
/// Layout is HORIZONTAL and fixed at 208×64: a 26pt status-icon box, then the title with
/// its chip (or quiet status text) stacked beside it. The "is here" marker floats ABOVE
/// the card (web `top:-32`), which is why the layout engine reserves `TOP = 40`.
struct RoadmapCardView: View {
    let task: RoadmapTask
    let status: TaskStatus
    /// The single current move (the beacon) — the only card with a filled chip + marker.
    let isCurrent: Bool
    let herePhrase: String
    let pulsing: Bool
    let onTap: () -> Void

    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { RoadmapPalette.tint(for: status) }
    private var isDone: Bool { status == .done }
    private var isLocked: Bool { status == .blocked }

    var body: some View {
        HStack(spacing: 10) {
            statusBox
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(2)
                    .lineSpacing(0)   // cancel SwiftUI's extra leading; web sets line-height 1.2
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150, alignment: .leading)
                if let verb = RoadmapBoardCopy.verb(for: status, lang) {
                    chip(verb)
                } else if let quiet = RoadmapBoardCopy.quietLabel(for: status, lang: lang) {
                    Text(quiet)
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: RoadmapGeometry.cardW, height: RoadmapGeometry.cardH, alignment: .leading)
        // The locked fade lives on the CONTENT, never the card — a faded card would let the
        // connectors behind it show through. Web puts the tray marker INSIDE this same
        // content layer (its `inset:0` div carries both the marker and `opacity: LOCKED_OP`),
        // so the marker fades with the rest of a locked card rather than sitting on top of it
        // at full strength — keep the marker in this overlay, not a later one.
        .overlay(alignment: .topTrailing) {
            if RoadmapBoardCopy.showsTrayMarker(status) { trayMarker }
        }
        .opacity(isLocked ? RoadmapTokens.lockedOpacity(dark: scheme == .dark) : 1)
        .background(cardFill)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(cardBorder, lineWidth: 1))
        .shadow(color: isCurrent ? CodepetTheme.accentPurple.opacity(0.6) : .clear,
                radius: 15, x: 0, y: 10)
        .overlay(alignment: .topLeading) {
            if isCurrent { hereMarker.offset(x: -1, y: -32) }
        }
        .scaleEffect(pulsing ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.5), value: pulsing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // Web: a 26×26 rounded box holding a 10×10 dot — a CIRCLE when done, a 3px rounded
    // square otherwise. Done also tints the box green.
    private var statusBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(isDone ? RoadmapPalette.done.opacity(0.14) : RoadmapTokens.chipBG)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(isDone ? RoadmapPalette.done.opacity(0.3) : RoadmapTokens.chipBorder,
                            lineWidth: 1))
                .frame(width: 26, height: 26)
            Group {
                if isDone { Circle().fill(tint) }
                else { RoundedRectangle(cornerRadius: 3).fill(tint) }
            }
            .frame(width: 10, height: 10)
        }
    }

    // Only the current move is a FILLED chip; every other actionable card is an outline, so
    // the board has exactly one unmistakable hero.
    @ViewBuilder private func chip(_ label: String) -> some View {
        let filled = isCurrent && status == .codepetCanDo
        // Web's `chipStyle` gives the merely-`available` outline (codepetCanDo, not current)
        // the `--accent-tint` / `--accent-line` tokens specifically — `approve`/`needsYou`
        // keep their own literal-hex rgba blends, so only this one state switches source.
        let isAvailable = !filled && status == .codepetCanDo
        Text(label)
            .font(CodepetTheme.inter(10, weight: .bold))
            .foregroundColor(filled ? CodepetTheme.onAccent(tint) : tint)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(Capsule().fill(filled ? tint : isAvailable ? CodepetTokens.accentTint : tint.opacity(0.10)))
            .overlay(Capsule().stroke(filled ? tint : isAvailable ? CodepetTokens.accentLine : tint.opacity(0.35), lineWidth: 1))
    }

    // The card is always OPAQUE — the state tint is layered over the base surface rather than
    // replacing it, so a dependency line running behind a card can never bleed through.
    private var cardFill: some View {
        let tintOverlay: Color? = isCurrent
            ? CodepetTheme.accentPurple.opacity(0.10)
            : isDone ? RoadmapPalette.done.opacity(0.06) : nil
        return RoundedRectangle(cornerRadius: 11).fill(RoadmapTokens.cardBG)
            .overlay {
                if let tintOverlay {
                    RoundedRectangle(cornerRadius: 11).fill(tintOverlay)
                }
            }
    }

    private var cardBorder: Color {
        if isCurrent { return CodepetTheme.accentPurple.opacity(0.6) }
        if isDone { return RoadmapPalette.done.opacity(0.22) }
        return CodepetTokens.cardEdge
    }

    // Web: a 10×10 square with a thick bottom border — an out-tray glyph marking a step
    // that still owes a deliverable.
    private var trayMarker: some View {
        VStack(spacing: 0) {
            Rectangle().stroke(CodepetTheme.mutedText, lineWidth: 1.5).frame(height: 6)
            Rectangle().fill(CodepetTheme.mutedText).frame(height: 4.5)
        }
        .frame(width: 10, height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .opacity(0.9)
        .padding(.top, 9).padding(.trailing, 10)
    }

    // Web: a surface-filled pill with an accent border, a 17pt gradient square, and
    // ACCENT-colored text (not white on purple).
    private var hereMarker: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [CodepetTokens.accentDeep, CodepetTheme.accentPurple],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 17, height: 17)
            Text(herePhrase.uppercased())
                .font(CodepetTheme.inter(9.5)).tracking(0.57)   // web .06em at 9.5px
                .foregroundColor(CodepetTheme.accentPurple)
                .fixedSize()
        }
        .padding(.leading, 4).padding(.trailing, 9).padding(.vertical, 3)
        .background(Capsule().fill(CodepetTheme.surface))
        .overlay(Capsule().stroke(CodepetTheme.accentPurple.opacity(0.5), lineWidth: 1))
        .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 10, x: 0, y: 6)
    }
}
