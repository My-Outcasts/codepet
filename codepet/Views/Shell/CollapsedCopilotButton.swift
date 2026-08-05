// codepet/Views/Shell/CollapsedCopilotButton.swift
import SwiftUI

/// The collapsed copilot: a circular floating button in the content area's
/// bottom-right corner, carrying the pixel Codepet mark — web parity with the
/// v1.2 app's collapsed-copilot affordance.
///
/// It replaces the old 44pt-wide, full-height reopen rail, which spent ~880pt of
/// height on a single glyph and — filled with `CodepetTheme.surface` (`#221d17`)
/// over `pageBackground` (`#16130f`), two near-identical values in dark mode —
/// barely read as a control at all. That is the same defect the wake pill had.
///
/// Three things here are deliberate, all corrections from founder review:
///
/// 1. **A light disc under the mark.** `codepet-logo` is RGBA with a fully
///    TRANSPARENT background, so it carries no disc of its own — drawn straight
///    onto `pageBackground` the button had no body and got lost against black.
/// 2. **The mark is inset, not filled.** Its opaque glyph measures 646×826 in a
///    1024 canvas — taller than wide, with only 9.7% vertical margin — so
///    `scaledToFill` (or even `scaledToFit`) across the full diameter renders the
///    "C" at ~81% of the button and it reads as overflowing. It gets an explicit
///    `markBox` so the glyph lands near half the disc, matching the web button.
/// 3. **Brand purple, NOT the companion accent.** Codepet's primary colour is
///    purple; tinting this with the active companion made it red under Crash. This
///    is the brand mark, so it stays brand-coloured while the rest of the chrome
///    re-tints. Do not "fix" this back to `accent`.
///
/// The mark is rendered the way the roadmap's root node renders it
/// (`RoadmapBoardView`): `.interpolation(.none)`, per the project rule that pixel
/// art never gets smoothed.
struct CollapsedCopilotButton: View {
    /// Work waiting on the founder, from `CollapsedCopilotState.needsYouCount`.
    let needsYou: Int
    /// A reply or run landed while the dock was closed.
    let unread: Bool
    let onExpand: () -> Void

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered = false

    private var diameter: CGFloat { 48 }
    /// The mark's box inside the disc. The glyph is 80.7% of its canvas HEIGHT, so
    /// a fitted square at 0.58× lands the "C" at roughly half the disc — the web
    /// button's proportion. Raising this is what made the letter look too big.
    private var markBox: CGFloat { diameter * 0.58 }
    /// Codepet's primary colour. Deliberately NOT the companion accent — see the
    /// type comment.
    private var brand: Color { CodepetTheme.accentPurple }
    private var openLabel: String {
        lang == .vi ? "Mở Codepet (⌘B)" : "Open Codepet (⌘B)"
    }

    var body: some View {
        Button(action: onExpand) {
            ZStack {
                // The disc the transparent mark needs to sit on. White in both
                // themes: it's the brand mark's own ground, and on the near-black
                // page background it's what stops the button disappearing.
                Circle().fill(Color.white)
                Image("codepet-logo")
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(width: markBox, height: markBox)
            }
            .frame(width: diameter, height: diameter)
            // A hairline so the disc keeps an edge in LIGHT mode too, where a white
            // circle on cream would otherwise have no boundary.
            .overlay(Circle().stroke(brand.opacity(hovered ? 0.55 : 0.28), lineWidth: 1))
            .shadow(color: reduceTransparency ? .clear : brand.opacity(hovered ? 0.6 : 0.4),
                    radius: hovered ? 18 : 12)
            .scaleEffect(hovered ? 1.04 : 1.0)
            .overlay(alignment: .topTrailing) { indicator }
        }
        .buttonStyle(.plain)
        .help(openLabel)
        .accessibilityLabel(openLabel)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .padding(20)
    }

    /// A count when work is waiting, else a quiet dot when something merely
    /// arrived. Never both: a number is strictly more informative than a dot.
    @ViewBuilder private var indicator: some View {
        if needsYou > 0 {
            Text("\(needsYou)")
                .font(CodepetTheme.inter(10, weight: .semibold))
                .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentGold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(CodepetTheme.accentGold))
                .overlay(Capsule().stroke(CodepetTheme.pageBackground, lineWidth: 1.5))
                .offset(x: 4, y: -3)
                .help(lang == .vi ? "\(needsYou) việc đang chờ bạn" : "\(needsYou) waiting on you")
        } else if unread {
            Circle().fill(brand)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(CodepetTheme.pageBackground, lineWidth: 1.5))
                .offset(x: 2, y: -1)
                .help(lang == .vi ? "Có tin mới trong trợ lý" : "New in the copilot")
        }
    }
}

#if DEBUG
#Preview("CollapsedCopilotButton") {
    VStack {
        Spacer()
        HStack {
            Spacer()
            CollapsedCopilotButton(needsYou: 5, unread: false, onExpand: {})
        }
    }
    .frame(width: 420, height: 240)
    .background(CodepetTheme.pageBackground)
}
#endif
