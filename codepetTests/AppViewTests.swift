import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversAllAppDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["chat", "roadmap", "secondBrain", "tasks", "library",
                        "environment", "company", "settings", "billing", "support"])
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
}
