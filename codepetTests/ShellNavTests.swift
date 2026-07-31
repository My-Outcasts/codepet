// codepetTests/ShellNavTests.swift
import XCTest
@testable import codepet

@MainActor
final class ShellNavTests: XCTestCase {
    func test_defaultLandingIsOverview() {
        XCTAssertEqual(CompanyStore().view, .roadmap)
    }
    func test_topTabs_areTheFiveWebTabs() {
        XCTAssertEqual(AppView.topTabs, [.roadmap, .company, .tasks, .library, .environment])
    }
    func test_overviewLabel() {
        XCTAssertEqual(AppView.roadmap.navLabel(.en), "Overview")
        XCTAssertEqual(AppView.company.navLabel(.en), AppView.company.title(.en))
    }
}
