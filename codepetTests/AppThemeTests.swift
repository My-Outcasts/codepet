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
}
