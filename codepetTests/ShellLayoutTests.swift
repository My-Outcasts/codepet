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
}
