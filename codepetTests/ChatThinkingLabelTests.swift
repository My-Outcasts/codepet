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

// MARK: - Naming the pet (7 Sep — the row lost its orb, so the words carry the identity)

extension ChatThinkingLabelTests {
    func testPetAndTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Luna", taskTitle: "the brand direction",
                                              language: .en),
                       "Luna is drafting the brand direction…")
    }
    func testPetAndTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Luna", taskTitle: "the brand direction",
                                              language: .vi),
                       "Luna đang soạn the brand direction…")
    }
    func testPetWithNoTask() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Crash", taskTitle: nil, language: .en),
                       "Crash is on it…")
        XCTAssertEqual(ChatThinkingLabel.text(petName: "Crash", taskTitle: nil, language: .vi),
                       "Crash đang làm…")
    }

    /// **The fallbacks are the point.** An unknown companion id resolves to nil, and the row
    /// must then read exactly as it did before rather than asserting a specialist that is not
    /// working. These are the two cases that would let the label lie.
    func testBlankPetFallsBackToTheUnnamedCopy() {
        XCTAssertEqual(ChatThinkingLabel.text(petName: "   ", taskTitle: nil, language: .en),
                       "Working on it…")
        XCTAssertEqual(ChatThinkingLabel.text(petName: nil, taskTitle: "positioning brief",
                                              language: .en),
                       "Drafting positioning brief…")
    }
}
