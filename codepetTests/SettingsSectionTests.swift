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

    /// Sections whose TITLE is a proper noun, so it reads the same in both languages.
    /// Deliberately narrow: the exemption covers the title only, and the subtitle
    /// assertions below still apply — so a half-translated section is still caught.
    /// Adding a section here is a claim that its name is a brand, not a shortcut past
    /// the translation this test exists to demand.
    private static let untranslatableTitles: Set<SettingsSection> = [.claudeCode]

    func test_everySectionHasBothLanguages() {
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title(.en).isEmpty)
            XCTAssertFalse(s.title(.vi).isEmpty)
            XCTAssertFalse(s.subtitle(.en).isEmpty)
            XCTAssertFalse(s.subtitle(.vi).isEmpty)
            XCTAssertNotEqual(s.subtitle(.en), s.subtitle(.vi),
                              "\(s.rawValue)'s subtitle is not translated")
            guard !Self.untranslatableTitles.contains(s) else { continue }
            XCTAssertNotEqual(s.title(.en), s.title(.vi), "\(s.rawValue) is not translated")
        }
    }

    /// The exemption above must stay a statement about brand names, not a growing
    /// allowlist. If a section is exempt, its title really must be identical — an
    /// exemption that no longer applies is an exemption that should be deleted.
    func test_exemptTitlesReallyAreIdenticalInBothLanguages() {
        for s in Self.untranslatableTitles {
            XCTAssertEqual(s.title(.en), s.title(.vi),
                           "\(s.rawValue) is exempt but its title differs — drop the exemption")
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
