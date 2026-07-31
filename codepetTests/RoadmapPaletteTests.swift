import XCTest
@testable import codepet

final class RoadmapPaletteTests: XCTestCase {
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

    // The board's card surface is LIGHTER than the app surface (#221d17) in dark mode — that's
    // deliberate on web so cards keep a visible edge on the near-black page.
    func testBoardSurfaceTokensMatchWeb() {
        XCTAssertEqual(RoadmapTokens.cardBGHex.light, "#ffffff")
        XCTAssertEqual(RoadmapTokens.cardBGHex.dark, "#2a241c")
        XCTAssertEqual(RoadmapTokens.chipBGHex.light, "#f1efe9")
        XCTAssertEqual(RoadmapTokens.chipBGHex.dark, "#342d23")
        XCTAssertEqual(RoadmapTokens.chipBorderHex.light, "#ece9e2")
        XCTAssertEqual(RoadmapTokens.chipBorderHex.dark, "#473e31")
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
