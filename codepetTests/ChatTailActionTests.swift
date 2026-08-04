import XCTest
@testable import codepet

/// What a chat turn owes its placeholder once the companion stream is over.
///
/// The three "the room took this turn" cases this suite used to carry are gone with
/// the `roomTookOver` input itself: the room is an appended message now, so it can no
/// longer overwrite byte's bubble and the tail has nothing to defend against.
final class ChatTailActionTests: XCTestCase {

    func testAGoodStreamIsLeftUntouched() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "A full reply."), .none)
    }

    func testFallsBackWhenTheStreamThrew() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: true, receivedDone: false,
                                             streamedText: ""), .fallback)
    }

    func testFallsBackWhenNoDoneFrameArrived() {
        // The pre-deploy shape: a plain-JSON body parses to zero SSE frames, so text
        // can even be present without a `done`.
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: false,
                                             streamedText: "partial"), .fallback)
    }

    func testWritesTheLeadInForARunTaskOnlyReply() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: ""), .leadIn)
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "  \n "), .leadIn)
    }

    func testDoneWithTextNeverFallsBack() {
        // Guards the duplicate-run bug: falling back on empty text would fire a
        // second chatSender and run the same task twice.
        XCTAssertNotEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                                streamedText: "text"), .fallback)
    }
}
