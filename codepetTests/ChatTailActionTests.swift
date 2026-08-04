import XCTest
@testable import codepet

/// The four orderings of a Virtual Company handoff against a chat turn's tail.
/// `CompanyStore` cannot be unit tested under Xcode 26.2 (isolated-deinit teardown
/// crashes the XCTest host), so the decision it obeys is tested here instead.
final class ChatTailActionTests: XCTestCase {

    // MARK: - The room took the turn

    func testHandoffBeforeTheFirstDeltaDoesNotWriteTheLeadIn() {
        // Deltas are dropped on purpose once the room takes over, so `streamedText`
        // is legitimately empty even though the stream succeeded. The lead-in would
        // overwrite byte's handoff line.
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", roomTookOver: true), .none)
    }

    func testHandoffDuringTheFallbackDoesNotWriteTheOfflineLine() {
        // companyChat threw, so the tail entered `.fallback`; the handoff landed
        // during `chatSender`'s await. Re-deciding must now say "leave it alone".
        XCTAssertEqual(ChatTailAction.decide(streamThrew: true, receivedDone: false,
                                             streamedText: "", roomTookOver: false), .fallback)
        XCTAssertEqual(ChatTailAction.decide(streamThrew: true, receivedDone: false,
                                             streamedText: "", roomTookOver: true), .none)
    }

    func testHandoffAfterDoneLeavesBytesPartialAnswerAlone() {
        // The room replaced the text in `publishRunProgress`; the tail must not
        // reinstate anything on top of it.
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "Half an answer",
                                             roomTookOver: true), .none)
    }

    // MARK: - No handoff: the pre-feature behaviour, unchanged

    func testNoHandoffKeepsAGoodStreamUntouched() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "A full reply.",
                                             roomTookOver: false), .none)
    }

    func testNoHandoffFallsBackWhenTheStreamThrew() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: true, receivedDone: false,
                                             streamedText: "", roomTookOver: false), .fallback)
    }

    func testNoHandoffFallsBackWhenNoDoneFrameArrived() {
        // The pre-deploy shape: a plain-JSON body parses to zero SSE frames, so text
        // can even be present without a `done`.
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: false,
                                             streamedText: "partial", roomTookOver: false), .fallback)
    }

    func testNoHandoffWritesTheLeadInForARunTaskOnlyReply() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", roomTookOver: false), .leadIn)
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "  \n ", roomTookOver: false), .leadIn)
    }

    func testDoneWithTextNeverFallsBack() {
        // Guards the duplicate-run bug: falling back on empty text would fire a
        // second chatSender and run the same task twice.
        XCTAssertNotEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                                streamedText: "text", roomTookOver: false), .fallback)
    }
}
