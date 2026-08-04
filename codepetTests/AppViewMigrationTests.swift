// codepetTests/AppViewMigrationTests.swift
import XCTest
@testable import codepet

/// Settings, Billing and Support stopped being `AppView` destinations when they became
/// sections of the centered settings modal. These tests pin that migration: the three
/// raw values must not come back as routes, and removing them must not disturb the
/// copilot rule or the chat `nav` resolver.
final class AppViewMigrationTests: XCTestCase {
    func test_accountLevelSurfacesAreNoLongerDestinations() {
        let raws = AppView.allCases.map(\.rawValue)
        XCTAssertFalse(raws.contains("settings"))
        XCTAssertFalse(raws.contains("billing"))
        XCTAssertFalse(raws.contains("support"))
    }

    func test_copilotStillHidesOnEveryNonOverviewDestination() {
        for v in [AppView.company, .tasks, .library, .environment] {
            XCTAssertFalse(ShellLayout.showsCopilot(in: v), "\(v.rawValue)")
        }
        XCTAssertTrue(ShellLayout.showsCopilot(in: .roadmap))
    }

    func test_navDestinationsStillResolve() {
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
        XCTAssertEqual(AppView.from(navDestination: "department"), .company)
        XCTAssertNil(AppView.from(navDestination: "settings"))
    }

    /// Every account-level surface the three destinations carried now has a home in the
    /// modal, so nothing was dropped in the move.
    func test_theThreeSurfacesSurviveAsSettingsSections() {
        let raws = SettingsSection.allCases.map(\.rawValue)
        XCTAssertTrue(raws.contains("preferences"))
        XCTAssertTrue(raws.contains("billing"))
        XCTAssertTrue(raws.contains("usage"))
        XCTAssertTrue(raws.contains("support"))
    }
}
