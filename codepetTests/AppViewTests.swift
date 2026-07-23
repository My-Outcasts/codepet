import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversAllAppDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["overview", "company", "roadmap", "tasks", "library",
                        "environment", "settings", "billing", "support"])
    }
    func testEveryCaseHasTitleAndIcon() {
        for v in AppView.allCases {
            XCTAssertFalse(v.title(.en).isEmpty)
            XCTAssertFalse(v.title(.vi).isEmpty)
            XCTAssertFalse(v.icon.isEmpty)
        }
    }
}
