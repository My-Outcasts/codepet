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

    /// **The default flipped on 23 Aug** and this test flipped with it, deliberately.
    /// Its previous form asserted the shell was OFF unless launched with a flag, and
    /// its comment said it existed to fail if someone flipped the default — so it did
    /// its job: the flip had to be made on purpose, here, rather than noticed later.
    ///
    /// What it guards now is the escape hatch. The two-mode shell is the product, but
    /// `AppShellView` is still reachable via `-CODEPET_LEGACY_SHELL YES` — delete that
    /// and every founder is one bad build away from having no way back.
    func testTheTwoModeShellIsTheDefaultAndLegacyIsStillReachable() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: TwoModeShell.legacyFlagKey),
                       "the test runner is not launched with -CODEPET_LEGACY_SHELL")
        XCTAssertTrue(TwoModeShell.enabled,
                      "the two-mode shell is the default; nothing should be needed to reach it")
        XCTAssertEqual(TwoModeShell.legacyFlagKey, "CODEPET_LEGACY_SHELL")
        // The historical argument still exists so an old launch command is not an error.
        XCTAssertEqual(TwoModeShell.flagKey, "CODEPET_TWO_MODE")
    }

    // MARK: - Labels

    func testModeTitlesAreBilingual() {
        XCTAssertEqual(WorkspaceMode.ask.title(.en), "Chat")
        XCTAssertEqual(WorkspaceMode.developer.title(.en), "Code")
        // The CASES keep their names because `rawValue` is the persisted value.
        // If this ever fails, someone renamed the case and broke mode restore for
        // every existing founder — the label is display, the rawValue is data.
        XCTAssertEqual(WorkspaceMode.ask.rawValue, "ask")
        XCTAssertEqual(WorkspaceMode.developer.rawValue, "developer")
        XCTAssertNotEqual(WorkspaceMode.ask.title(.vi), WorkspaceMode.ask.title(.en))
        XCTAssertNotEqual(WorkspaceMode.developer.title(.vi), WorkspaceMode.developer.title(.en))
        XCTAssertFalse(WorkspaceMode.hint(.vi).isEmpty)
    }
}
