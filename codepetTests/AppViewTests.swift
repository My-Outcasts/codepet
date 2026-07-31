import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversAllAppDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["chat", "roadmap", "secondBrain", "tasks", "library",
                        "environment", "company", "settings", "billing", "support"])
    }

    func testRailShowsDestinationsInOrder() {
        XCTAssertEqual(AppView.navTabs, [.roadmap, .secondBrain, .company, .tasks, .library, .environment])
    }

    func testRoadmapNavDestinationResolvesToRoadmapNotOverview() {
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
        XCTAssertEqual(AppView.from(navDestination: "department"), .company)
        XCTAssertNil(AppView.from(navDestination: "nope"))
    }

    func testEveryCaseHasTitleAndIcon() {
        for v in AppView.allCases {
            XCTAssertFalse(v.title(.en).isEmpty)
            XCTAssertFalse(v.title(.vi).isEmpty)
            XCTAssertFalse(v.icon.isEmpty)
        }
    }

    func testChatIsHomeAndOverviewRetired() {
        XCTAssertEqual(AppView.navTabs, [.roadmap, .secondBrain, .company, .tasks, .library, .environment])
        XCTAssertFalse(AppView.navTabs.contains(.chat))   // chat is home, not a tab
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
    }
}
