import XCTest
import SwiftUI
import AppKit
@testable import codepet

final class RoadmapPaletteTests: XCTestCase {
    private enum RenderFailure: Error { case producedNothing }
    // Web hardcodes these three (RoadmapView.tsx DOT, OverviewSection.tsx legendFor) with no
    // dark variant, so native must use the same literals in both appearances.
    func testStateHexMatchesWeb() {
        XCTAssertEqual(RoadmapPalette.doneHex, "#16a34a")
        XCTAssertEqual(RoadmapPalette.approveHex, "#d97706")
        XCTAssertEqual(RoadmapPalette.needsYouHex, "#2563eb")
    }

    // globals.css --rm-locked-op: 0.62 light / 0.9 dark.
    func testLockedOpacityMatchesWeb() {
        XCTAssertEqual(RoadmapTokens.lockedOpacity(dark: false), 0.62, accuracy: 0.0001)
        XCTAssertEqual(RoadmapTokens.lockedOpacity(dark: true), 0.9, accuracy: 0.0001)
    }

    // The board's card surface is LIGHTER than the app surface in dark mode — that's
    // deliberate so cards keep a visible edge on the near-black page.
    func testBoardSurfaceTokensMatchWeb() {
        XCTAssertEqual(RoadmapTokens.cardBGHex.light, "#ffffff")
    }

    /// Renders a colour through the same pipeline the app draws with, so two values are
    /// comparable. Raw hex and rendered pixels are NOT comparable — the render carries
    /// colour-management distortion the raw value does not — so both sides go through here.
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
            XCTFail("swatch render produced nothing")
            throw RenderFailure.producedNothing
        }
        return c
    }

    private func lum(_ c: NSColor) -> CGFloat {
        0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    /// The board's card is deliberately LIGHTER than the app's own surfaces, so a card
    /// keeps a visible edge on the near-black page. That relationship is the invariant;
    /// the specific hex is not, and asserting the hex is why this test broke on a palette
    /// change that preserved every relationship it cared about.
    ///
    /// **Reads `CodepetTheme.surface` itself rather than a hardcoded `"#1d1928"`.** An
    /// earlier draft hardcoded it — which is the same defect this plan just repaired one
    /// task earlier: `OnboardingContent.Palette` duplicated three token values as
    /// literals, the retint moved the tokens without moving the copies, and the palette
    /// was genuinely split for three commits. A literal here would go stale the same way,
    /// and the invariant would quietly stop being tested.
    ///
    /// Every value is rendered, so all four are measured through one pipeline and are
    /// comparable.
    @MainActor
    func testTheBoardCardIsLighterThanTheAppSurfaces() throws {
        let appSurface = lum(try rendered(CodepetTheme.surface, .dark))
        let card       = lum(try rendered(RoadmapTokens.cardBG, .dark))
        let chip       = lum(try rendered(RoadmapTokens.chipBG, .dark))
        let chipEdge   = lum(try rendered(RoadmapTokens.chipBorder, .dark))
        XCTAssertGreaterThan(card, appSurface,
                             "the board card must be lighter than `surface`/`cardRaised`")
        XCTAssertGreaterThan(chip, card,
                             "the status chip sits ON the card, so it must be lighter still")
        XCTAssertGreaterThan(chipEdge, chip,
                             "the chip's edge must be lighter than its fill")
    }

    // --rm-card-bg is a DIFFERENT dark surface from the list cards' (#26201a). If these ever
    // become equal, one of them drifted from globals.css.
    func testBoardCardSurfaceIsNotTheListCardSurface() {
        XCTAssertNotEqual(RoadmapTokens.cardBGHex.dark, "#26201a")
    }

    func testBoardTintCoversEveryState() {
        XCTAssertEqual(RoadmapPalette.tint(for: .done), RoadmapPalette.done)
        XCTAssertEqual(RoadmapPalette.tint(for: .codepetCanDo), RoadmapPalette.canDo)
        XCTAssertEqual(RoadmapPalette.tint(for: .needsApproval), RoadmapPalette.approve)
        XCTAssertEqual(RoadmapPalette.tint(for: .needsYou), RoadmapPalette.needsYou)
        XCTAssertEqual(RoadmapPalette.tint(for: .blocked), RoadmapPalette.blocked)
    }

    // The board palette and the department cards' palette are separate on web and must stay
    // separate here: web styles department task states from globals.css `.st-*`, where "Done"
    // is --accent-deep, NOT green. Merging them would recolor the Company page.
    func testBoardPaletteIsNotTheDepartmentPalette() {
        XCTAssertNotEqual(RoadmapPalette.tint(for: .done), taskStatusTint(.done))
    }
}
