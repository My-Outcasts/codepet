// codepetTests/SettingsSectionTests.swift
import XCTest
@testable import codepet

final class SettingsSectionTests: XCTestCase {
    func test_rawValues_roundTrip_soAChatCardCanDeepLink() {
        for s in SettingsSection.allCases {
            XCTAssertEqual(SettingsSection(rawValue: s.rawValue), s)
        }
    }

    func test_preferencesIsFirst_soTheModalOpensThere() {
        XCTAssertEqual(SettingsSection.allCases.first, .preferences)
    }

    func test_everySectionHasBothLanguages() {
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title(.en).isEmpty)
            XCTAssertFalse(s.title(.vi).isEmpty)
            XCTAssertFalse(s.subtitle(.en).isEmpty)
            XCTAssertNotEqual(s.title(.en), s.title(.vi), "\(s.rawValue) is not translated")
        }
    }

    func test_railCollapsesOnlyOnANarrowShell() {
        XCTAssertTrue(ShellLayout.settingsRailCollapsed(forWidth: 780))
        XCTAssertFalse(ShellLayout.settingsRailCollapsed(forWidth: 820))
        XCTAssertFalse(ShellLayout.settingsRailCollapsed(forWidth: 1400))
    }

    func test_panelSize_insetsFromTheWindowAndCapsOut() {
        // Wide window: capped at the ideal size, not stretched.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 1600, height: 1200),
                       CGSize(width: 920, height: 660))
        // Small window: inset 96pt from each edge.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 800, height: 600),
                       CGSize(width: 704, height: 504))
        // Tiny window: never smaller than the usable floor.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 400, height: 300),
                       CGSize(width: 480, height: 400))
    }
}
