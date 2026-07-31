import XCTest
@testable import codepet

final class ChatModeTests: XCTestCase {
    func testAskReturnsTextUnchanged() {
        XCTAssertEqual(ChatMode.ask.shape("what's next?", language: .en), "what's next?")
        XCTAssertEqual(ChatMode.ask.shape("việc gì tiếp?", language: .vi), "việc gì tiếp?")
    }

    func testPlanWrapsAndPreservesText() {
        let out = ChatMode.plan.shape("pricing page", language: .en)
        XCTAssertTrue(out.contains("pricing page"))
        XCTAssertNotEqual(out, "pricing page")
        XCTAssertTrue(out.lowercased().contains("plan"))
    }

    func testBuildWrapsAndPreservesText() {
        let out = ChatMode.build.shape("landing page", language: .en)
        XCTAssertTrue(out.contains("landing page"))
        XCTAssertNotEqual(out, "landing page")
    }

    func testPlanIsLocalized() {
        XCTAssertNotEqual(ChatMode.plan.shape("x", language: .en),
                          ChatMode.plan.shape("x", language: .vi))
    }

    func testAllCasesHaveNonEmptyLabels() {
        for m in ChatMode.allCases {
            XCTAssertFalse(m.label(.en).isEmpty)
            XCTAssertFalse(m.label(.vi).isEmpty)
        }
    }
}
