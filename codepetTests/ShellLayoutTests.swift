// codepetTests/ShellLayoutTests.swift
import XCTest
@testable import codepet

final class ShellLayoutTests: XCTestCase {
    func test_manualCollapse_always() {
        XCTAssertTrue(ShellLayout.dockCollapsed(forWidth: 1400, manual: true))
    }
    func test_narrowWindow_autoCollapses() {
        XCTAssertTrue(ShellLayout.dockCollapsed(forWidth: 800, manual: false))
    }
    func test_wideEnough_expanded() {
        XCTAssertFalse(ShellLayout.dockCollapsed(forWidth: 1200, manual: false))
    }
    func test_boundary_900_expanded() {
        XCTAssertFalse(ShellLayout.dockCollapsed(forWidth: 900, manual: false))
    }

    func test_dockWidth_isHalfTheWindow_whileHalfFitsUnderTheCap() {
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1000), 500)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1100), 550)
    }

    /// Past the cap the dock stops growing and the CONTENT pane takes the surplus —
    /// this is what stops a fullscreen window handing chat 735pt of blank column.
    func test_dockWidth_capsSoContentTakesTheSurplus() {
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1200), 560)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1470), 560)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1920), 560)
    }

    func test_goingFullscreenGivesContentABiggerShare() {
        let windowed = 918.0, fullscreen = 1470.0
        let windowedShare = (windowed - ShellLayout.dockWidth(forWidth: windowed)) / windowed
        let fullscreenShare = (fullscreen - ShellLayout.dockWidth(forWidth: fullscreen)) / fullscreen
        // Windowed stays an even split; fullscreen tilts toward the map because the dock
        // stops growing. Under the old 50/50 rule both shares were exactly 0.5.
        XCTAssertEqual(windowedShare, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(fullscreenShare, 0.6)
    }

    /// The cap is a default, not a ceiling — dragging the handle still widens the dock.
    func test_dragStillOverridesTheCap() {
        XCTAssertEqual(ShellLayout.clampDockWidth(800, windowWidth: 1470), 800)
    }
    func test_dockWidth_flooredAt360() {
        // At the 900 expand boundary, half is 450 (above the floor); a hypothetical
        // narrower expanded case never drops below the usable floor.
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 900), 450)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 600), 360)
    }
    func test_clampDockWidth_keepsBothPanesUsable() {
        // Drag wider than allowed → capped so content keeps its 420 floor.
        XCTAssertEqual(ShellLayout.clampDockWidth(2000, windowWidth: 1400), 1400 - 420)
        // Drag narrower than the dock floor → held at 360.
        XCTAssertEqual(ShellLayout.clampDockWidth(100, windowWidth: 1400), 360)
        // A sensible drag in range is returned unchanged.
        XCTAssertEqual(ShellLayout.clampDockWidth(620, windowWidth: 1400), 620)
    }

    // MARK: Where the copilot appears

    /// The copilot is an Overview surface. Founder call: it should not follow you
    /// onto the other destinations.
    func test_copilotShowsOnOverview() {
        XCTAssertTrue(ShellLayout.showsCopilot(in: .roadmap))
    }

    func test_copilotHiddenOnEveryOtherDestination() {
        for v in [AppView.company, .tasks, .library, .environment, .settings, .billing, .support] {
            XCTAssertFalse(ShellLayout.showsCopilot(in: v),
                           "copilot should not appear on \(v.rawValue)")
        }
    }

    /// `.chat` and `.secondBrain` aren't reachable destinations — both fall through
    /// to the Overview surface in `AppShellView.content`, so the copilot must stay
    /// rather than vanish on a view that is visually Overview.
    func test_copilotStaysOnTheViewsThatRenderOverview() {
        XCTAssertTrue(ShellLayout.showsCopilot(in: .chat))
        XCTAssertTrue(ShellLayout.showsCopilot(in: .secondBrain))
    }

    /// Every case is decided explicitly — a new destination added to `AppView`
    /// should have to choose, not silently inherit a default.
    func test_everyDestinationIsDecided() {
        for v in AppView.allCases {
            let shown = ShellLayout.showsCopilot(in: v)
            XCTAssertEqual(shown, [.roadmap, .chat, .secondBrain].contains(v),
                           "\(v.rawValue) is on the wrong side of the copilot rule")
        }
    }

    /// Only Overview is a top-nav tab that keeps the copilot; the other four tabs
    /// are full-width surfaces.
    func test_onlyOverviewAmongTheTopTabsKeepsTheCopilot() {
        let withCopilot = AppView.topTabs.filter { ShellLayout.showsCopilot(in: $0) }
        XCTAssertEqual(withCopilot, [.roadmap])
    }

    // MARK: Page header compaction

    func test_compactHeader_offWhenRoomy() {
        XCTAssertFalse(ShellLayout.compactPageHeader(forWidth: 900))
        XCTAssertFalse(ShellLayout.compactPageHeader(forWidth: 620))
    }
    func test_compactHeader_onWhenCramped() {
        XCTAssertTrue(ShellLayout.compactPageHeader(forWidth: 619))
        XCTAssertTrue(ShellLayout.compactPageHeader(forWidth: 460))
    }
    /// Unmeasured (first layout pass) must read roomy, so the header doesn't flash
    /// abbreviated before its real width arrives.
    func test_compactHeader_unmeasuredReadsRoomy() {
        XCTAssertFalse(ShellLayout.compactPageHeader(forWidth: 0))
    }

    /// The two rules have to agree: at the window sizes the app actually runs at, the
    /// content pane left over must NOT be narrow enough to force a compact header —
    /// except in the windowed case the screenshot came from, where it must.
    func test_fullscreenGetsTheRoomyHeader_windowedGetsCompact() {
        let fullscreenContent = 1470 - ShellLayout.dockWidth(forWidth: 1470)
        XCTAssertFalse(ShellLayout.compactPageHeader(forWidth: fullscreenContent),
                       "fullscreen should show the full 'How to read this map' label")
        let windowedContent = 918 - ShellLayout.dockWidth(forWidth: 918)
        XCTAssertTrue(ShellLayout.compactPageHeader(forWidth: windowedContent),
                      "the windowed state is what was wrapping — it must compact")
    }
}
