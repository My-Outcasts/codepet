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

    /// The dock does not track the window. This is the assertion the 50%-of-window rule
    /// fails, and the reason it exists: while the dock moved with the window, resizing
    /// re-wrapped every line of the transcript, because `ChatColumn` sizes the reading
    /// column from the dock's width. Founder call, Aug 5 — resizing must not touch the chat.
    func test_dockWidth_doesNotTrackTheWindow() {
        for window in [CGFloat(900), 1000, 1100, 1200, 1470, 1920, 2560] {
            XCTAssertEqual(ShellLayout.dockWidth(forWidth: window), ShellLayout.dockDefaultWidth,
                           "window \(window) moved the dock to \(ShellLayout.dockWidth(forWidth: window))pt")
        }
    }

    /// Every point a bigger window brings goes to the content pane, so the map's share of
    /// the shell rises with the window instead of staying pinned at half.
    func test_aBiggerWindowGivesEveryNewPointToTheMap() {
        let small = 918.0, large = 1470.0
        let smallMap = small - ShellLayout.dockWidth(forWidth: small)
        let largeMap = large - ShellLayout.dockWidth(forWidth: large)
        XCTAssertEqual(largeMap - smallMap, large - small, accuracy: 0.5)
        XCTAssertGreaterThan(largeMap / large, smallMap / small)
    }

    /// The default is a default, not a ceiling — dragging the handle still widens the dock.
    func test_dragStillOverridesTheCap() {
        XCTAssertEqual(ShellLayout.clampDockWidth(800, windowWidth: 1470), 800)
    }
    /// On a window too small for the default, the content pane's floor wins and the dock
    /// gives way — down to its own floor and no further.
    func test_dockWidth_yieldsToTheContentFloorOnASmallWindow() {
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 900), ShellLayout.dockDefaultWidth)  // 900-420 = 480, room to spare
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 760), 340 < ShellLayout.dockMinWidth
                                                             ? ShellLayout.dockMinWidth : 340)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 600), ShellLayout.dockMinWidth)
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
        for v in [AppView.company, .tasks, .library, .environment] {
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

    /// Every top-nav tab is a full-width surface; the copilot belongs to home.
    ///
    /// This used to filter `topTabs` and assert it equalled `[.roadmap]`, which stopped saying
    /// anything the moment Overview left the bar (Aug 6) — an empty list would have satisfied a
    /// `.filter` that found nothing. Asserting the tabs are copilot-FREE, and that home is not,
    /// survives the tab list changing again.
    func test_noTopTabKeepsTheCopilot_andHomeDoes() {
        for v in AppView.topTabs {
            XCTAssertFalse(ShellLayout.showsCopilot(in: v),
                           "\(v.rawValue) is a full-width surface")
        }
        XCTAssertTrue(ShellLayout.showsCopilot(in: AppView.home))
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
