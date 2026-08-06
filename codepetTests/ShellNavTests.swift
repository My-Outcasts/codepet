// codepetTests/ShellNavTests.swift
import XCTest
@testable import codepet

@MainActor
final class ShellNavTests: XCTestCase {
    func test_defaultLandingIsOverview() {
        XCTAssertEqual(CompanyStore().view, .roadmap)
    }
    /// Four tabs, not five. Overview left the bar on Aug 6 because it is the default
    /// destination — the app opened with a tab already selected that restated where you were.
    func test_topTabs_areTheFourNonDefaultTabs() {
        XCTAssertEqual(AppView.topTabs, [.company, .tasks, .library, .environment])
    }

    /// The one that matters: Overview must stay REACHABLE after losing its tab. `home` is what
    /// the wordmark selects, and it has to be the same destination the app lands on, or clicking
    /// the logo would take you somewhere that isn't home.
    func test_homeIsTheDefaultLandingAndIsNotATab() {
        XCTAssertEqual(AppView.home, .roadmap)
        XCTAssertEqual(CompanyStore().view, AppView.home)
        XCTAssertFalse(AppView.topTabs.contains(AppView.home),
                       "home is reached by the wordmark; a tab for it would be the duplicate we removed")
    }

    /// The label outlived the tab — it is what the wordmark's hover tooltip reads.
    func test_overviewLabel() {
        XCTAssertEqual(AppView.roadmap.navLabel(.en), "Overview")
        XCTAssertEqual(AppView.roadmap.navLabel(.vi), "Tổng quan")
        XCTAssertEqual(AppView.company.navLabel(.en), AppView.company.title(.en))
    }

    /// The chip has to name the binding `TopNavView` actually installs (⇧⌘H). If someone
    /// rebinds the wordmark, this is the reminder that the tooltip is now lying.
    func test_homeShortcutLabelIsTheOneBoundInTheTopBar() {
        XCTAssertEqual(AppView.homeShortcutLabel, "⇧⌘H")
    }
}
