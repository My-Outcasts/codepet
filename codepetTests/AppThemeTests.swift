// codepetTests/AppThemeTests.swift
import XCTest
import SwiftUI
@testable import codepet

final class AppThemeTests: XCTestCase {
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

    /// The ramp is a constructor, not a constant, because its two consumers need
    /// different hues: the composer's stops are the active companion's colour
    /// (`CopilotChatView.companionColor`), and only the hero mark is brand purple.
    /// A fixed `brandGradient` would have had to be overridden at the very sites
    /// that share it. This asserts the pair and its order, which the hero's radial
    /// depends on: purple reads first, pink second.
    func testBrandRampIsPurpleThenPink() {
        XCTAssertEqual(CodepetTheme.brandRamp.count, 2)
        XCTAssertEqual(CodepetTheme.brandRamp[0], CodepetTheme.accentPurple)
        XCTAssertEqual(CodepetTheme.brandRamp[1], CodepetTheme.accentPink)
    }
}
