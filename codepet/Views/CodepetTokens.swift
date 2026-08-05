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

    // MARK: Layout

    /// Widest the reading column grows before it stops following the window.
    ///
    /// **One number for every page in every tab** (founder call, Aug 5) — a founder
    /// tabbing between surfaces should never see the measure jump.
    ///
    /// Measured ChatGPT rather than guessing: `/library`, `/projects` and `/codex` all
    /// use `max-width: 800px` with `40px 16px` padding — a 736-768px measure, identical
    /// on all three, with a 28px title like ours. The lesson that holds is where the air
    /// goes: their list rows sit back-to-back (61pt, hairline), and the calm comes from
    /// short lines plus big SECTION gaps, not from spacing siblings out.
    ///
    /// The 800 itself does NOT transfer, and 880 was tried and read as tight (founder,
    /// Aug 5). A ChatGPT library row is a filename, a date and a size; a Codepet row is
    /// a 40%-wide cover image beside a name, a status pill, a task line and a count —
    /// far more to seat across the measure. Walked up with the founder watching on a
    /// 1470pt window: 880 read tight, 1040 snug, 1160 closer, 1280 settled — wide enough
    /// for a cover-plus-columns row, still ~95pt of margin each side so the page reads as
    /// a column rather than the full-bleed wall it started as (~1900). This is about the
    /// ceiling on a 1470pt window: past it the margins stop looking deliberate. The
    /// Environment grid holds three cards per row from 1040 up.
    static let pageColumnWidth: CGFloat = 1280

    /// The page rhythm — one scale for every page in every tab (founder call, Aug 5).
    ///
    /// Before this, each surface carried its own numbers: header-to-content was 14 on
    /// Tasks, 18 on Company and Environment, 22 on Second Brain, and item gaps were
    /// 10, 14 and 18. Nothing was wrong individually; together they read as four
    /// pages built by four people.
    ///
    /// Measured from ChatGPT (`/library`, `/projects`, `/codex`): the air goes at
    /// SECTION seams, not between siblings — their list rows sit back-to-back while
    /// the column takes 40px of padding and the title-to-content run is ~190px.
    enum Space {
        /// Masthead to the first block of content.
        static let headToBody: CGFloat = 34
        /// Above a section label (eyebrow, group header).
        static let sectionAbove: CGFloat = 36
        /// Below a section label — deliberately much smaller than `sectionAbove` so the
        /// label sits WITH the group it names. At 20/14 the Library's group header read
        /// as belonging to the group above it.
        static let sectionBelow: CGFloat = 10
        /// Between sibling cards. Carded items need to read as separate objects, which
        /// is why this is not ChatGPT's zero — their rows have no chrome. 14 is what
        /// the Environment grid already used, so it is the house value.
        static let itemGap: CGFloat = 14
        /// Tail of a scrolling page, so the last row never sits on the window edge.
        static let pageBottom: CGFloat = 56
    }

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

    // MARK: Collapsed phase rails
    //
    // Rails used `well` + `hairline`, which measured 1.16:1 and 1.27:1 against the
    // page in dark mode — the same near-identical-values defect as the wake pill
    // (1.11:1). The bodies read as absent and only the labels registered, so the
    // rails looked like floating text. Their own tokens rather than a change to
    // `well`, which three other surfaces share.
    //
    // Measured against `page` — dark `#16130f`, light `#f8f7f3`:
    //   railFill    light 1.29:1  dark 1.47:1   (was 1.07 / 1.16)
    //   railBorder  light 1.90:1  dark 2.21:1   (was ~1.05 / 1.27)
    // The border does the real work of drawing the shape; the fill stays quiet
    // because a collapsed phase is meant to be de-emphasised, not loud.
    static let railFill   = Color.dyn("#e0dbcf", "#3a3228")
    static let railBorder = Color.dyn("#bdb5a2", "#574c3f")
    /// Hover lift for an EXPANDABLE rail — the affordance the rails never had.
    static let railFillHover   = Color.dyn("#d3ccbc", "#483f33")
    static let railBorderHover = Color.dyn("#a89e88", "#6d604f")

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
    ///
    /// Also carries the centered column, because a masthead that ran edge to edge
    /// while the body below it was capped would stop lining up with its own content.
    func viewHeadPadding() -> some View {
        self.padding(.top, 32).padding(.horizontal, 26).pageColumn()
    }

    /// The reading column: capped, content left-aligned inside it, column centred in
    /// the window.
    ///
    /// Claude's "Apps and extensions" and ChatGPT's "Plugins" both cap the column and
    /// centre it rather than running the full width of the window — at ~1900pt the
    /// Environment grid was fitting five cards per row and the eye had nowhere to
    /// land. Founder call, Aug 5.
    ///
    /// **Header and body must both use this** (`viewHeadPadding()` already does), or
    /// the title stops lining up with the cards under it.
    func pageColumn() -> some View {
        self.frame(maxWidth: CodepetTokens.pageColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
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

    /// The one hover + hit-area treatment for controls that opted out of AppKit's
    /// chrome with `.buttonStyle(.plain)`.
    ///
    /// Two defects it repairs together. A shape drawn with `.stroke` hit-tests along
    /// its 1pt path only, so an outlined pill responds on its outline and its glyphs
    /// but not across the padding between them — `contentShape` gives the control the
    /// hit area its outline always implied. And `.plain` strips the pointer response
    /// AppKit would have drawn, which leaves a working control reading as a disabled
    /// one; a faint same-shape fill on hover restores it.
    ///
    /// Nothing changes at rest: the fill is fully transparent until the pointer is
    /// inside, so every surface keeps the design it has today.
    func hoverAffordance<S: InsettableShape>(
        _ shape: S,
        accent: Color = CodepetTheme.accentPurple
    ) -> some View {
        modifier(HoverAffordance(shape: shape, accent: accent))
    }

    /// Show `cursor` while the pointer is inside, and guarantee the matching pop.
    ///
    /// `NSCursor.push()` and `.pop()` operate on a stack that must balance, and
    /// `onHover(false)` does **not** fire when a view disappears from under the
    /// pointer. A bare `if inside { push() } else { pop() }` therefore leaks: clicking
    /// the dock divider to collapse it removed the handle mid-hover, leaving the
    /// resize cursor set for the rest of the session. This pops on disappear, and
    /// refuses to pop a push it never made — which also absorbs the repeated
    /// `onHover(true)` callbacks that would otherwise push twice.
    ///
    /// `onChange` carries the hover state through for callers that also drive their
    /// own highlight from it.
    func cursorOnHover(_ cursor: NSCursor, onChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(CursorOnHover(cursor: cursor, onChange: onChange))
    }
}

/// Backing modifier for `cursorOnHover(_:onChange:)` — needs `@State` to remember
/// whether this view owns a push, so it cannot live in the `View` extension.
struct CursorOnHover: ViewModifier {
    let cursor: NSCursor
    let onChange: ((Bool) -> Void)?
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                onChange?(inside)
                guard inside != pushed else { return }
                pushed = inside
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                guard pushed else { return }
                pushed = false
                NSCursor.pop()
            }
    }
}

/// Backing modifier for `hoverAffordance(_:accent:)` — needs `@State`, so it cannot
/// live in the `View` extension itself.
struct HoverAffordance<S: InsettableShape>: ViewModifier {
    let shape: S
    let accent: Color
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(shape)
            .background(shape.fill(accent.opacity(hovering ? 0.14 : 0)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Overview roadmap board

/// The roadmap-local custom properties from `app/globals.css` that no other surface uses.
/// `--rm-card-border` is deliberately absent: it is byte-for-byte `CodepetTokens.cardEdge`.
/// Each token is exposed twice — as a `(light, dark)` hex pair, so parity is unit-testable
/// without resolving an NSAppearance, and as the `Color` the views consume.
enum RoadmapTokens {
    typealias HexPair = (light: String, dark: String)

    static let cardBGHex: HexPair      = ("#ffffff", "#2a241c")   // --rm-card-bg
    static let chipBGHex: HexPair      = ("#f1efe9", "#342d23")   // --rm-chip-bg
    static let chipBorderHex: HexPair  = ("#ece9e2", "#473e31")   // --rm-chip-border

    /// Board card fill. In dark this is LIGHTER than both `--surface` (#221d17) and the list
    /// cards' `cardRaised` (#26201a) — web gives the board its own slightly-raised surface so
    /// cards keep a visible edge on the near-black page.
    static let cardBG = Color.dyn(cardBGHex.light, cardBGHex.dark)
    /// The status-icon box inside a card.
    static let chipBG = Color.dyn(chipBGHex.light, chipBGHex.dark)
    /// That box's edge.
    static let chipBorder = Color.dyn(chipBorderHex.light, chipBorderHex.dark)

    /// `--rm-locked-op` — how far a locked card's CONTENT fades. Never applied to the card
    /// itself: a translucent card would let the connectors behind it show through.
    static func lockedOpacity(dark: Bool) -> Double { dark ? 0.9 : 0.62 }
}

/// The board's five states. `done`/`approve`/`needsYou` are literal hex on web with no dark
/// variant (`RoadmapView.tsx` DOT, `OverviewSection.tsx` legendFor), so they are literal here
/// too — do NOT wrap them in `Color.dyn`. `canDo` and `blocked` follow the app's accent and
/// muted-text tokens, exactly as web follows `--accent` and `--t-3`.
enum RoadmapPalette {
    static let doneHex = "#16a34a"
    static let approveHex = "#d97706"
    static let needsYouHex = "#2563eb"

    static let done = Color(hex: doneHex)
    static let approve = Color(hex: approveHex)
    static let needsYou = Color(hex: needsYouHex)
    static var canDo: Color { CodepetTheme.accentPurple }
    static var blocked: Color { CodepetTheme.mutedText }

    /// State → dot/chip color for the roadmap board only, mirroring `RoadmapView.tsx`'s `DOT`
    /// map. Deliberately NOT `taskStatusTint`: that one serves the department cards, which web
    /// styles from a different scale (`globals.css` `.st-*`), so the two must not be merged.
    static func tint(for status: TaskStatus) -> Color {
        switch status {
        case .done:          return done
        case .codepetCanDo:  return canDo
        case .needsApproval: return approve
        case .needsYou:      return needsYou
        case .blocked:       return blocked
        }
    }
}
