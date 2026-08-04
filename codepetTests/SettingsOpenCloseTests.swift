// codepetTests/SettingsOpenCloseTests.swift
import XCTest
@testable import codepet

@MainActor
final class SettingsOpenCloseTests: XCTestCase {
    func test_startsClosed() {
        let store = CompanyStore()
        XCTAssertNil(store.settingsSection)
        XCTAssertFalse(store.isSettingsOpen)
    }

    func test_openDefaultsToPreferences() {
        let store = CompanyStore()
        store.openSettings()
        XCTAssertEqual(store.settingsSection, .preferences)
        XCTAssertTrue(store.isSettingsOpen)
    }

    func test_openOnASpecificSection_forDeepLinks() {
        let store = CompanyStore()
        store.openSettings(.memory)
        XCTAssertEqual(store.settingsSection, .memory)
    }

    /// Sign-out unmounts the shell, which HIDES the overlay without closing it. If the
    /// flag survived, the next account would land on the shell with settings already up.
    func test_resetClosesSettings() {
        let store = CompanyStore()
        store.openSettings(.billing)
        store.reset()
        XCTAssertNil(store.settingsSection)
        XCTAssertFalse(store.isSettingsOpen)
    }

    func test_closingLeavesTheDestinationAlone() {
        let store = CompanyStore()
        store.select(.tasks)
        store.openSettings(.billing)
        store.closeSettings()
        XCTAssertNil(store.settingsSection)
        XCTAssertEqual(store.view, .tasks, "settings must not navigate")
    }
}
