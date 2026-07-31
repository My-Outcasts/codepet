import XCTest
@testable import codepet

final class MessageFeedbackTests: XCTestCase {
    private func fixture(helpful: Bool) -> MessageFeedback {
        MessageFeedback(messageId: "m123", helpful: helpful, companyId: "c1",
                        userId: "u1", companionId: "byte")
    }

    func testDataHelpfulTrue() {
        let d = fixture(helpful: true).firestoreData()
        XCTAssertEqual(d["kind"] as? String, "chat_message")
        XCTAssertEqual(d["messageId"] as? String, "m123")
        XCTAssertEqual(d["helpful"] as? Bool, true)
        XCTAssertEqual(d["companyId"] as? String, "c1")
        XCTAssertEqual(d["userId"] as? String, "u1")
        XCTAssertEqual(d["companionId"] as? String, "byte")
        XCTAssertEqual(d["platform"] as? String, "macos")
    }

    func testDataHelpfulFalse() {
        XCTAssertEqual(fixture(helpful: false).firestoreData()["helpful"] as? Bool, false)
    }

    func testNoTimestampKey() {
        // The server timestamp is added by the writer, not the payload.
        XCTAssertNil(fixture(helpful: true).firestoreData()["timestamp"])
    }
}
