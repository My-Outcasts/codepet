// codepetTests/WorkspaceModeTests.swift
import XCTest
@testable import codepet

/// Guards for the two-mode shell's model. These run without the app host on
/// purpose — the XCTest host on Xcode 26.2 crashes when a `@MainActor`
/// `ObservableObject` deallocates, so anything provable off a pure value type is.
final class WorkspaceModeTests: XCTestCase {

    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "two-mode-tests-\(name)")!
        d.removePersistentDomain(forName: "two-mode-tests-\(name)")
        return d
    }

    // MARK: - The five never move

    func testWorkspaceSurfacesAreTheFiveCompanyPages() {
        XCTAssertEqual(WorkspaceMode.workspaceSurfaces,
                       [.roadmap, .company, .tasks, .library, .environment])
    }

    /// Chat is the surface the five sit beside, not one of them — and Second Brain
    /// becomes a tab inside Company rather than a sixth destination.
    func testChatAndSecondBrainAreNotWorkspaceSurfaces() {
        XCTAssertFalse(WorkspaceMode.workspaceSurfaces.contains(.chat))
        XCTAssertFalse(WorkspaceMode.workspaceSurfaces.contains(.secondBrain))
    }

    /// Both modes can reach all five. Developer only COLLAPSES them — a roadmap
    /// task and the code that satisfies it must stay one click apart.
    func testBothModesKeepAllFiveReachable() {
        for mode in WorkspaceMode.allCases {
            XCTAssertEqual(WorkspaceMode.workspaceSurfaces.count, 5,
                           "\(mode) must not drop a company surface")
        }
        XCTAssertFalse(WorkspaceMode.ask.collapsesWorkspace)
        XCTAssertTrue(WorkspaceMode.developer.collapsesWorkspace)
    }

    // MARK: - Persistence

    func testModePersistsAndRestores() {
        let d = scratchDefaults()
        XCTAssertEqual(WorkspaceMode.restore(from: d), .ask, "a fresh account opens on Ask")

        WorkspaceMode.developer.persist(to: d)
        XCTAssertEqual(WorkspaceMode.restore(from: d), .developer)

        WorkspaceMode.ask.persist(to: d)
        XCTAssertEqual(WorkspaceMode.restore(from: d), .ask)
    }

    /// Ask needs no repo and no CLI, so it is the honest fallback for a value we
    /// cannot read — never Developer, which would open on a dormant workspace.
    func testUnknownStoredValueFallsBackToAsk() {
        let d = scratchDefaults()
        d.set("build", forKey: WorkspaceMode.defaultsKey)   // a retired ChatMode case
        XCTAssertEqual(WorkspaceMode.restore(from: d), .ask)
    }

    func testDefaultsKeyKeepsTheProjectPrefix() {
        XCTAssertTrue(WorkspaceMode.defaultsKey.hasPrefix("cp_"),
                      "UserDefaults keys are cp_-prefixed (CLAUDE.md)")
    }

    // MARK: - The flag

    /// `main` must keep shipping the web-parity shell while this is built, so the
    /// two-mode shell is opt-in. A test that fails if someone flips the default.
    func testTwoModeShellIsOffUnlessLaunchedWithTheFlag() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: TwoModeShell.flagKey),
                       "the test runner is not launched with -CODEPET_TWO_MODE")
        XCTAssertEqual(TwoModeShell.flagKey, "CODEPET_TWO_MODE")
    }

    // MARK: - Labels

    func testModeTitlesAreBilingual() {
        XCTAssertEqual(WorkspaceMode.ask.title(.en), "Ask")
        XCTAssertEqual(WorkspaceMode.developer.title(.en), "Developer")
        XCTAssertNotEqual(WorkspaceMode.ask.title(.vi), WorkspaceMode.ask.title(.en))
        XCTAssertNotEqual(WorkspaceMode.developer.title(.vi), WorkspaceMode.developer.title(.en))
        XCTAssertFalse(WorkspaceMode.hint(.vi).isEmpty)
    }
}
