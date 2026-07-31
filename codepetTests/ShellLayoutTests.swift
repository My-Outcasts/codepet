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

    func test_dockWidth_isHalfTheWindow() {
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1400), 700)
        XCTAssertEqual(ShellLayout.dockWidth(forWidth: 1200), 600)
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
}
