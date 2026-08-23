// codepetTests/AppThemeTests.swift
import XCTest
import SwiftUI
import AppKit
@testable import codepet

final class AppThemeTests: XCTestCase {
    private enum RenderFailure: Error { case producedNothing }

    func testColorSchemeMapping() {
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }
    func testNextCyclesSystemLightDark() {
        XCTAssertEqual(AppTheme.system.next, .light)
        XCTAssertEqual(AppTheme.light.next, .dark)
        XCTAssertEqual(AppTheme.dark.next, .system)
    }
    func testRawValueRoundTrip() {
        for t in AppTheme.allCases { XCTAssertEqual(AppTheme(rawValue: t.rawValue), t) }
    }
    func testLabels() {
        XCTAssertEqual(AppTheme.system.label(.en), "System")
        XCTAssertEqual(AppTheme.dark.label(.vi), "Tối")
    }

    /// Renders a token through the SAME `ImageRenderer` pipeline the app draws with and
    /// returns the pixel that came out. This is the only trustworthy way to read a
    /// `Color.dyn` value in a test: bridging a SwiftUI `Color` to `NSColor` can resolve
    /// eagerly, outside any appearance block, and would silently hand back the LIGHT
    /// value while the test claims to check dark.
    @MainActor
    private func rendered(_ color: Color, _ scheme: ColorScheme) throws -> NSColor {
        let swatch = Rectangle().fill(color)
            .frame(width: 20, height: 20)
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: swatch)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
                  .usingColorSpace(.sRGB) else {
            XCTFail("token swatch render produced nothing")
            throw RenderFailure.producedNothing
        }
        return c
    }

    private func lum(_ c: NSColor) -> CGFloat {
        0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    /// The dark surfaces must form a strict ladder, because the mode switch depends on it:
    /// a track darker than the rail, a card lighter than the rail. Before this retint the
    /// app inset by going LIGHTER (`well` #26211a was brighter than `surface` #221d17, and
    /// `cardRaised` #26201a sat within one hex digit of `well`), which is why the active
    /// segment needed purple body added before it read as selected.
    ///
    /// Reads the REAL TOKENS through the real pipeline. An earlier draft of this test
    /// asserted `lum("#121019") < lum("#171420")` on hex literals — which tests hex
    /// arithmetic and would pass no matter what the tokens contained.
    @MainActor
    func testDarkSurfacesFormALadder() throws {
        let track = lum(try rendered(CodepetTokens.well, .dark))
        let rail  = lum(try rendered(CodepetTokens.surface2, .dark))
        let card  = lum(try rendered(CodepetTokens.cardRaised, .dark))
        let line  = lum(try rendered(CodepetTheme.hairline, .dark))
        let line2 = lum(try rendered(CodepetTokens.cardEdge, .dark))
        XCTAssertLessThan(track, rail,  "the track must be darker than the rail")
        XCTAssertLessThan(rail,  card,  "the card must be lighter than the rail")
        XCTAssertLessThan(card,  line,  "the hairline must be lighter than the card")
        XCTAssertLessThan(line,  line2, "the strong line must be lighter than the hairline")
    }

    /// The ground is COOL now, not warm — the single assertion that catches a revert to
    /// the brown family. `#16130f` had red leading blue by 0.0275; `#121019` has blue
    /// leading red. Reads `CodepetTheme.pageBackground` itself, not a literal.
    @MainActor
    func testTheDarkGroundIsCoolNotWarm() throws {
        let g = try rendered(CodepetTheme.pageBackground, .dark)
        XCTAssertGreaterThan(g.blueComponent, g.redComponent,
                             "the dark ground went warm again — blue must lead red")
    }

    /// The onboarding palette must BE the shared tokens, not merely look like them.
    ///
    /// These three used to be re-declared in `OnboardingContent.Palette` with hex
    /// literals byte-identical to `CodepetTokens`', under a comment claiming
    /// `CodepetTheme` did not expose them. It did. A retint of one and not the other
    /// would have split the palette with nothing failing to say so.
    ///
    /// Renders both sides rather than comparing `Color` values: two `Color`s can compare
    /// unequal while rendering identically, and bridging a SwiftUI `Color` to `NSColor`
    /// can resolve eagerly outside an appearance block and return the LIGHT value while
    /// claiming to test dark. Rendering is the only comparison that reflects what is
    /// actually drawn.
    ///
    /// This catches the alias pointing at the WRONG token — the one failure a compile
    /// and the existing suites both wave through.
    ///
    /// Measured (correctly-aliased case): with the real aliases in place, distance is
    /// exactly `0.0` for all three tokens in both schemes — same underlying `Color.dyn`
    /// value through the same render pipeline.
    ///
    /// Measured (wrong-token probes, each run twice for reproducibility):
    /// - `well` pointed at `CodepetTokens.surface2` (a FAR pair) — light `0.09293878…`,
    ///   dark `0.09171904…` (not `0.917` — that's a 10x transcription error in the
    ///   `025a090` commit message, uncorrected there since amending a shared,
    ///   possibly-already-pushed commit is not worth the force-push).
    /// - `well` pointed at `CodepetTokens.page` (the closest real mistake: `well` and
    ///   `page` are `Color.dyn("#efecf7", "#121019")` vs `Color.dyn("#f5f3fa",
    ///   "#121019")` — byte-identical in dark) — light `0.04967308044433594`, dark
    ///   `0.0`. The DARK leg cannot distinguish `well` from `page` at all: a `well →
    ///   page` mis-alias renders identically in dark and is invisible to that half of
    ///   this loop. It is the LIGHT leg alone that catches it, at ~50x the `0.001`
    ///   bound — still comfortably real, just carried by one scheme instead of two.
    @MainActor
    func testOnboardingPaletteAliasesTheSharedTokens() throws {
        for scheme in [ColorScheme.light, .dark] {
            let pairs: [(String, Color, Color)] = [
                ("surface2", OnboardingContent.Palette.surface2, CodepetTokens.surface2),
                ("well",     OnboardingContent.Palette.well,     CodepetTokens.well),
                ("faint",    OnboardingContent.Palette.faint,    CodepetTokens.faint),
            ]
            for (name, alias, source) in pairs {
                let a = try rendered(alias, scheme)
                let s = try rendered(source, scheme)
                let d = abs(a.redComponent - s.redComponent)
                    + abs(a.greenComponent - s.greenComponent)
                    + abs(a.blueComponent - s.blueComponent)
                XCTAssertLessThan(d, 0.001,
                                  "OnboardingContent.Palette.\(name) does not render as "
                                  + "CodepetTokens.\(name) in \(scheme) — distance \(d). "
                                  + "Either it is still a duplicate literal, or it is "
                                  + "aliased to the wrong token.")
            }
        }
    }

    /// The collapsed phase rails must stay legible against the page.
    ///
    /// They exist as their own tokens because sharing `well`/`hairline` put them at
    /// 1.16:1 and 1.27:1 in dark, where the bodies read as absent and the rails looked
    /// like floating text. A cool retint later gave them derived values that reused the
    /// line tokens and put `railFill` back to 1.26:1 — the same defect, reintroduced,
    /// with nothing failing to say so. This is that missing assertion.
    ///
    /// WCAG relative-luminance contrast, computed from the rendered tokens rather than
    /// from ideal hexes: the render carries colour-management distortion, and this plan
    /// has twice been wrong by reasoning about declared values instead of measured ones.
    ///
    /// **The rendered numbers here do NOT match the ideal-hex arithmetic quoted above
    /// them, and that gap is itself the finding, not a mistake to paper over.**
    ///
    /// Measured pre-fix (dark `railFill` = `#2a2438`, `railBorder` = `#3a3350`, run
    /// twice on-device, identical both times): dark `railFill` contrast **1.4665:1**,
    /// `railBorder` **1.9839:1**; light `railFill` **1.3727:1**, `railBorder`
    /// **1.9417:1**. Every one of those clears this test's own 1.35 / 1.9 floors — the
    /// rendered pipeline does NOT reproduce the 1.26:1 / 1.59:1 defect that the ideal-hex
    /// WCAG arithmetic in the block above predicts for these same hexes. Raw rendered
    /// channel values ran ~0.03–0.07 brighter per channel than the literal hex implies in
    /// dark (e.g. ground `#121019` renders ~(0.090, 0.080, 0.130) instead of the ~(0.071,
    /// 0.063, 0.098) the hex means), which is enough to move a borderline ratio across
    /// this floor. Per instruction, the floors below were kept exactly as specified
    /// rather than lowered to force a red run — this comment reports the mismatch
    /// instead.
    ///
    /// Measured post-fix (dark `railFill` = `#362e48`, `railBorder` = `#50466f`, run
    /// twice, identical both times): dark `railFill` contrast **1.8066:1**, `railBorder`
    /// **2.8578:1** — both pass with more headroom than the pre-fix numbers, in the
    /// expected direction, even though the absolute values again diverge from the
    /// ideal-hex estimate (1.47 / 2.20) for the same reason as above. Light is unchanged
    /// (`well`/`hairline` untouched) and still passes at the same values as pre-fix.
    @MainActor
    func testCollapsedRailsClearContrastFloor() throws {
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func relLum(_ c: NSColor) -> CGFloat {
            0.2126 * linear(c.redComponent)
                + 0.7152 * linear(c.greenComponent)
                + 0.0722 * linear(c.blueComponent)
        }
        func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
            let la = relLum(a), lb = relLum(b)
            let lighter = max(la, lb), darker = min(la, lb)
            return (lighter + 0.05) / (darker + 0.05)
        }
        for scheme in [ColorScheme.light, .dark] {
            let ground = try rendered(CodepetTheme.pageBackground, scheme)
            let fill = try rendered(CodepetTokens.railFill, scheme)
            let border = try rendered(CodepetTokens.railBorder, scheme)
            let fillRatio = contrast(fill, ground)
            let borderRatio = contrast(border, ground)
            XCTAssertGreaterThanOrEqual(fillRatio, 1.35,
                "railFill contrast against page in \(scheme) is \(fillRatio):1, below the "
                + "1.35 floor — the rail body is reading as absent again.")
            XCTAssertGreaterThanOrEqual(borderRatio, 1.9,
                "railBorder contrast against page in \(scheme) is \(borderRatio):1, below "
                + "the 1.9 floor — the rail outline is losing its shape.")
        }
    }
}
