import XCTest
@testable import codepet

final class ChatThinkingLabelTests: XCTestCase {
    func testNoTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en), "Working on it…")
    }
    func testNoTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .vi), "Đang xử lý…")
    }
    func testNamedTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .en),
                       "Drafting positioning brief…")
    }
    func testNamedTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .vi),
                       "Đang soạn positioning brief…")
    }
    func testBlankTitleTreatedAsNone() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "   ", language: .en), "Working on it…")
    }
}
