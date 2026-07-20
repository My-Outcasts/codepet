import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversTheSevenWebDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["overview", "company", "roadmap", "tasks", "library", "environment", "settings"])
    }
    func testEveryCaseHasTitleAndIcon() {
        for v in AppView.allCases {
            XCTAssertFalse(v.title(.en).isEmpty)
            XCTAssertFalse(v.title(.vi).isEmpty)
            XCTAssertFalse(v.icon.isEmpty)
        }
    }
}
