import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversAllAppDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["chat", "summary", "company", "roadmap", "secondBrain", "tasks", "library",
                        "environment", "settings", "billing", "support"])
    }
    func testEveryCaseHasTitleAndIcon() {
        for v in AppView.allCases {
            XCTAssertFalse(v.title(.en).isEmpty)
            XCTAssertFalse(v.title(.vi).isEmpty)
            XCTAssertFalse(v.icon.isEmpty)
        }
    }
    func testChatIsHomeAndOverviewRetired() {
        XCTAssertEqual(AppView.navTabs, [.summary, .roadmap, .secondBrain, .company, .tasks, .library, .environment])
        XCTAssertFalse(AppView.navTabs.contains(.chat))   // chat is home, not a tab
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
    }
}
