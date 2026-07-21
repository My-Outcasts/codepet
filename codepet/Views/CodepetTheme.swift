import SwiftUI

// MARK: - CodepetTheme
//
// Tokens + view modifiers that align in-app chrome with the marketing site
// (code-pet.com). The aesthetic is soft and modern: cream background,
// generously rounded corners, blurred drop shadows, system sans-serif type,
// and bright accent colors. Pet sprites themselves stay pixel art via
// `.interpolation(.none)` — only the chrome around them matches the site.

enum CodepetTheme {

    // MARK: Typography rule
    //
    // Titles (display() and any pixelSystem(size:) ≥ 18pt) render in Minecraft
    // bitmap. Everything else — body copy, labels, captions, tab pills — renders
    // in Inter. Inter weight files (Regular/Medium/SemiBold/Bold) must be
    // present in codepet/Resources/Fonts/ and listed in FontRegistrar.swift.
    static let titlePixelSizeThreshold: CGFloat = 18

    // MARK: Surfaces

    /// Page background — warm cream that the marketing site uses across hero,
    /// product, and footer sections.
    static let pageBackground = Color(red: 0xF8 / 255.0, green: 0xF7 / 255.0, blue: 0xF3 / 255.0)

    /// Card / panel surface. Solid white sits cleanly on top of the cream
    /// background.
    static let surface = Color.white

    /// Subtle hairline used inside cards for dividers when a stronger
    /// boundary is needed than whitespace alone.
    static let hairline = Color(red: 0xEC / 255.0, green: 0xE9 / 255.0, blue: 0xE2 / 255.0)

    // MARK: Text

    /// Headline / primary text — near-black with a touch of warmth.
    static let primaryText = Color(red: 0x1F / 255.0, green: 0x1B / 255.0, blue: 0x15 / 255.0)

    /// Body copy — slightly softer than headlines.
    static let bodyText = Color(red: 0x33 / 255.0, green: 0x2E / 255.0, blue: 0x27 / 255.0)

    /// Muted text — labels, captions, helper copy.
    static let mutedText = Color(red: 0x77 / 255.0, green: 0x70 / 255.0, blue: 0x65 / 255.0)

    // MARK: Brand accents (mirrors the marketing site)

    static let accentPurple = Color(red: 0x7C / 255.0, green: 0x3A / 255.0, blue: 0xED / 255.0)
    static let accentPink   = Color(red: 0xFF / 255.0, green: 0x6B / 255.0, blue: 0x9D / 255.0)
    static let accentGold   = Color(red: 0xFD / 255.0, green: 0xB0 / 255.0, blue: 0x22 / 255.0)
    static let accentTeal   = Color(red: 0x2D / 255.0, green: 0xD4 / 255.0, blue: 0xBF / 255.0)
    static let accentOrange = Color(red: 0xFF / 255.0, green: 0x8C / 255.0, blue: 0x42 / 255.0)
    static let accentBlue   = Color(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0)

    // MARK: Geometry

    /// Default card corner radius — gentle ~14pt curve on stat cards and
    /// testimonial blocks.
    static let cardRadius: CGFloat = 14

    /// Pill-style buttons.
    static let pillRadius: CGFloat = 24

    /// Tighter radius for inline pills (input chrome, small chips).
    static let inputRadius: CGFloat = 12

    // MARK: Shadow tokens

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// Soft elevation used on cards.
    static let cardShadow = Shadow(
        color: Color.black.opacity(0.08),
        radius: 12, x: 0, y: 4
    )

    /// Slightly stronger lift used on a floating panel (chat, modals).
    static let floatingShadow = Shadow(
        color: Color.black.opacity(0.12),
        radius: 24, x: 0, y: 12
    )

    // MARK: Typography

    /// Title / headline. Always Minecraft pixel font.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        _ = weight // Minecraft is a single-weight bitmap font
        return pixel(size)
    }

    /// Body / content. Always Inter.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return inter(size, weight: weight)
    }

    /// Bundled bitmap pixel font ("Minecraft.ttf"). Used by `display(_:)` and
    /// available directly when an explicit pixel accent is needed.
    static func pixel(_ size: CGFloat) -> Font {
        _ = FontRegistrar.autoRegister
        return Font.custom("Minecraft", size: size, relativeTo: .body)
    }

    /// The app's sans — Google Sans Flex, matching the web. Maps SwiftUI weight
    /// to the matching bundled static weight registered by `FontRegistrar`
    /// (Inter remains bundled as the fallback family). Unsupplied weights
    /// (light/thin/black) fall back to Regular. `inter(_:weight:)` is kept as an
    /// alias so existing call sites are unchanged.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = FontRegistrar.autoRegister
        let name: String
        switch weight {
        case .black, .heavy, .bold:
            name = "GoogleSansFlex-Bold"
        case .semibold:
            name = "GoogleSansFlex-SemiBold"
        case .medium:
            name = "GoogleSansFlex-Medium"
        default:
            name = "GoogleSansFlex-Regular"
        }
        return Font.custom(name, size: size, relativeTo: .body)
    }
}

// MARK: - Drop-in `.font(.pixelSystem(size:))` replacement

extension Font {
    /// Drop-in for `Font.system(size:weight:design:)` that follows the
    /// project-wide rule: titles (≥ 18pt) render in Minecraft, everything
    /// smaller renders in Inter. The `design` hint is ignored — pick weight
    /// instead.
    static func pixelSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        _ = design
        if size >= CodepetTheme.titlePixelSizeThreshold {
            return CodepetTheme.pixel(size)
        }
        return CodepetTheme.inter(size, weight: weight)
    }
}

// MARK: - Soft drop-shadow modifier

extension View {
    /// Apply a `CodepetTheme.Shadow` token.
    func codepetShadow(_ shadow: CodepetTheme.Shadow = CodepetTheme.cardShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Card container

/// Rounded white surface with a soft drop shadow.
struct CodepetCard<Content: View>: View {
    var fill: Color = CodepetTheme.surface
    var radius: CGFloat = CodepetTheme.cardRadius
    var shadow: CodepetTheme.Shadow = CodepetTheme.cardShadow
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .codepetShadow(shadow)
    }
}

// MARK: - Pill button style

/// Solid pill. Brand accent fill + white text by default. Matches the
/// site's primary CTA.
struct CodepetPillButtonStyle: ButtonStyle {
    var fill: Color = CodepetTheme.accentPurple
    var foreground: Color = .white
    var paddingH: CGFloat = 18
    var paddingV: CGFloat = 10
    var font: Font = CodepetTheme.body(13, weight: .semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundColor(foreground)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.pillRadius, style: .continuous)
                    .fill(fill)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Compact icon button (close X, etc.)

struct CodepetIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var fill: Color = .clear
    var foreground: Color = CodepetTheme.mutedText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed
                          ? Color.black.opacity(0.06)
                          : fill)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Soft input chrome

struct CodepetInputBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                    .fill(Color(white: 0.97))
            )
    }
}

extension View {
    /// Wrap a TextField in soft input chrome.
    func codepetInput() -> some View {
        modifier(CodepetInputBackground())
    }
}

// MARK: - Markdown Text rendering

extension Text {
    /// Render a plain `String` containing inline Markdown into a colored `Text`.
    /// Each inline style maps to a distinct accent color, so emphasis pops the
    /// way it would in a code editor:
    ///
    /// - `` `code` ``        → accent **purple** + monospaced (handled by SwiftUI)
    /// - `**bold**`          → accent **pink**
    /// - `*italic*`          → accent **blue**
    /// - `~~strike~~`        → accent **orange** (kept struck through)
    /// - `[tag](anything)`   → accent **gold** (link target is ignored — purely a
    ///                          visual marker so writers can highlight phrases
    ///                          without inventing custom syntax)
    ///
    /// Preserves whitespace and line breaks. Falls back to the plain string
    /// if parsing fails.
    init(markdown raw: String) {
        self.init(CodepetMarkdown.attributedString(from: raw))
    }

    /// Markdown render that also highlights + links dictionary terms. Used by
    /// the Reflection narrative; pair with an `OpenURLAction` that handles the
    /// `codepetterm://<id>` scheme.
    init(markdown raw: String, linkTerms: Bool) {
        self.init(CodepetMarkdown.attributedString(from: raw, linkTerms: linkTerms))
    }
}

/// Shared markdown → AttributedString tinting used by both `Text(markdown:)`
/// and `MarkdownTypewriterText`. Lifted out so the typewriter can reveal a
/// fully-tinted attributed prefix character-by-character without re-parsing.
enum CodepetMarkdown {
    /// - Parameter linkTerms: when true, words that have a Dictionary entry are
    ///   dot-underlined in their topic color and carry a `codepetterm://<id>`
    ///   link (handled by an `OpenURLAction` in the narrative view). Off by
    ///   default so the rest of the app's markdown is untouched.
    // Parsing markdown + scanning the glossary is expensive and runs on every
    // body refresh (scroll, typewriter ticks, state changes), yet the raw text
    // for a given narrative field almost never changes. Cache the finished
    // AttributedString keyed on (linkTerms, raw). Bounded + lock-guarded so a
    // long session's many turns can't grow it without limit or race.
    private static var cache: [String: AttributedString] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 256
    private static let cacheLock = NSLock()

    static func attributedString(from raw: String, linkTerms: Bool = false) -> AttributedString {
        let key = (linkTerms ? "1\u{01}" : "0\u{01}") + raw
        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let value = buildAttributedString(from: raw, linkTerms: linkTerms)

        cacheLock.lock()
        if cache[key] == nil {
            cache[key] = value
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                let evict = cacheOrder.removeFirst()
                cache.removeValue(forKey: evict)
            }
        }
        cacheLock.unlock()
        return value
    }

    private static func buildAttributedString(from raw: String, linkTerms: Bool) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attr = try? AttributedString(markdown: raw, options: opts) else {
            var fallback = AttributedString(raw)
            if linkTerms { applyGlossary(&fallback) }
            return fallback
        }

        // Collect ranges first to avoid mutating the AttributedString while
        // iterating its runs.
        var codeRanges: [Range<AttributedString.Index>] = []
        var boldRanges: [Range<AttributedString.Index>] = []
        var italicRanges: [Range<AttributedString.Index>] = []
        var strikeRanges: [Range<AttributedString.Index>] = []
        var linkRanges: [Range<AttributedString.Index>] = []

        for run in attr.runs {
            if run.link != nil {
                linkRanges.append(run.range)
                continue
            }
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                codeRanges.append(run.range)
            } else if intent.contains(.strikethrough) {
                strikeRanges.append(run.range)
            } else if intent.contains(.stronglyEmphasized) {
                boldRanges.append(run.range)
            } else if intent.contains(.emphasized) {
                italicRanges.append(run.range)
            }
        }

        for r in codeRanges {
            attr[r].foregroundColor = CodepetTheme.accentPurple
        }
        for r in boldRanges {
            attr[r].foregroundColor = CodepetTheme.accentPink
        }
        for r in italicRanges {
            attr[r].foregroundColor = CodepetTheme.accentBlue
        }
        for r in strikeRanges {
            attr[r].foregroundColor = CodepetTheme.accentOrange
        }
        for r in linkRanges {
            attr[r].foregroundColor = CodepetTheme.accentGold
            attr[r].link = nil       // strip the URL so taps don't navigate
            attr[r].underlineStyle = nil
        }

        if linkTerms { applyGlossary(&attr) }
        return attr
    }

    /// Dot-underline + topic-color + link every dictionary term found in the
    /// already-tinted string. Operates on the rendered characters (markdown
    /// markers already removed), mapping String offsets to AttributedString
    /// indices so the spans line up exactly.
    static func applyGlossary(_ attr: inout AttributedString) {
        let plain = String(attr.characters)
        let hits = DictionaryGlossary.scan(plain)
        guard !hits.isEmpty else { return }
        for hit in hits {
            let startOffset = plain.distance(from: plain.startIndex, to: hit.range.lowerBound)
            let length = plain.distance(from: hit.range.lowerBound, to: hit.range.upperBound)
            let lo = attr.index(attr.startIndex, offsetByCharacters: startOffset)
            let hi = attr.index(lo, offsetByCharacters: length)
            let topicId = DictionaryContent.terms.first { $0.id == hit.termId }?.topicId ?? ""
            let color = DictionaryContent.accent(forTopicId: topicId).color
            attr[lo..<hi].foregroundColor = color
            attr[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot, color: color)
            attr[lo..<hi].link = URL(string: "codepetterm://\(hit.termId)")
        }
    }
}
