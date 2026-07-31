// codepet/Views/CodepetTokens.swift
import SwiftUI

/// The web's semantic colour scale, 1:1 with `app/globals.css` (`:root` +
/// `[data-theme='dark']`). `CodepetTheme` already carries the surfaces, text ramp
/// and base accents; this adds what the company/tasks/environment/library views
/// need and nothing else:
///
/// - each hue's **tint** (pale fill) and **line** (matching border),
/// - `well` / `surface2` / `faint`, the two neutrals + the lightest ink,
/// - `accentDeep` / `accentTint` / `accentLine`,
/// - the two elevation shadows (`--sh-s`, `--sh-m`).
///
/// Every value is a light/dark pair, so a view built from these tokens themes
/// itself the way the web does.
enum CodepetTokens {

    // MARK: Neutrals

    static let well      = Color.dyn("#f1efe9", "#26211a")   // --well
    static let surface2  = Color.dyn("#fcfbf8", "#1b1712")   // --surface-2
    static let faint     = Color.dyn("#a79e92", "#6f685c")   // --t-4
    static let page      = Color.dyn("#f8f7f3", "#16130f")   // --page

    /// Dark mode lifts every raised card above `--surface` and warms its edge,
    /// because on the near-black page a black shadow can't separate the two
    /// (`[data-theme='dark'] .deptrow, .kb-card, .lib-tile, .env-card…`).
    static let cardRaised = Color.dyn("#ffffff", "#26201a")
    static let cardEdge   = Color.dyn("#ece9e2", "#3c352b")

    // MARK: Accent (violet brand)

    static let accentDeep = Color.dyn("#5b27b0", "#7c3aed")  // --accent-deep
    static let accentTint = Color.dyn("#eee6fd", "#271f3a")  // --accent-tint
    static let accentLine = Color.dyn("#d9c9f7", "#43356b")  // --accent-line

    // MARK: Semantic hues + their tint/line pairs

    static let violet     = Color.dyn("#9333ea", "#b57bf5")
    static let violetTint = Color.dyn("#f0e4fd", "#2a2140")
    static let violetLine = Color.dyn("#dcc4f6", "#463869")

    static let gold       = Color.dyn("#fdb022", "#fdc352")
    static let goldTint   = Color.dyn("#fef0d6", "#332816")
    static let goldLine   = Color.dyn("#f6dda6", "#5c4620")

    static let blue       = Color.dyn("#2563eb", "#7fb0ff")
    static let blueTint   = Color.dyn("#dce7fc", "#182742")
    static let blueLine   = Color.dyn("#bbd0f7", "#274069")

    static let teal       = Color.dyn("#2dd4bf", "#3fe0cb")
    static let tealTint   = Color.dyn("#ddf7f3", "#123330")
    static let tealLine   = Color.dyn("#aee9e1", "#1e5a54")

    static let clay       = Color.dyn("#ff8c42", "#ff9b5e")
    static let clayTint   = Color.dyn("#ffe8d6", "#38230f")
    static let clayLine   = Color.dyn("#fbcfaf", "#5e3a1e")

    static let rose       = Color.dyn("#ff6b9d", "#ff85ac")
    static let roseTint   = Color.dyn("#ffe6ef", "#3a1a26")
    static let roseLine   = Color.dyn("#fbc4d7", "#63304a")

    /// `.dr-status.ready` / `.lt-state.live` — fixed greens, not theme hues.
    static let readyGreen = Color(hex: "#0e9f6e")
    static let liveGreen  = Color(hex: "#0f9d8f")

    // MARK: Elevation

    /// `--sh-s`: 0 1px 2px rgba(31,27,21,.05) — dark keeps a black equivalent.
    static func shadowS(_ dark: Bool) -> CodepetTheme.Shadow {
        CodepetTheme.Shadow(color: (dark ? Color.black.opacity(0.30) : Color(hex: "#1f1b15").opacity(0.05)),
                            radius: 2, x: 0, y: 1)
    }
    /// `--sh-m`: the hover/raised elevation (the wider of the web's two layers).
    static func shadowM(_ dark: Bool) -> CodepetTheme.Shadow {
        CodepetTheme.Shadow(color: (dark ? Color.black.opacity(0.50) : Color(hex: "#1f1b15").opacity(0.06)),
                            radius: 26, x: 0, y: 10)
    }
}

// MARK: - Page chrome shared by the web's `.view` sections

extension View {
    /// web `.vhead { padding: 22px 26px 0 }` — every view's masthead sits on the
    /// same optical margin, and the body blocks below carry their own 26px gutter.
    func viewHeadPadding() -> some View {
        self.padding(.top, 22).padding(.horizontal, 26)
    }

    /// A raised card: the theme's lifted fill, a visible edge, and `--sh-s`.
    func cardChrome(radius: CGFloat, dark: Bool) -> some View {
        let sh = CodepetTokens.shadowS(dark)
        return self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(CodepetTokens.cardRaised))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(CodepetTokens.cardEdge, lineWidth: 1))
            .shadow(color: sh.color, radius: sh.radius, x: sh.x, y: sh.y)
    }
}
