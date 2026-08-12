// codepetTests/MessageVoteTests.swift
import XCTest
@testable import codepet

/// The vote lives on the message, not in `@State`, because SwiftUI drops view state as
/// rows recycle during scrolling — the founder would watch their thumb disappear.
@MainActor
final class MessageVoteTests: XCTestCase {

    func testVoteDefaultsToNil() {
        XCTAssertNil(CopilotMessage(role: .companion, text: "hi").vote)
    }

    func testVoteIsCarriedByTheInitializer() {
        XCTAssertEqual(CopilotMessage(role: .companion, text: "hi", vote: .up).vote, .up)
    }

    func testRecordVoteSetsTheVoteOnTheNamedMessage() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([
            CopilotMessage(id: "a", role: .me, text: "ask"),
            CopilotMessage(id: "b", role: .companion, text: "answer")
        ])
        store.recordVote(messageId: "b", vote: .down)
        XCTAssertEqual(store.chatMessages[1].vote, .down)
        XCTAssertNil(store.chatMessages[0].vote, "the other message must be untouched")
    }

    /// The rule denies `update`, so a correction writes a second doc rather than editing
    /// the first — but the UI must still show the corrected thumb.
    func testRecordVoteReplacesAnEarlierVote() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([CopilotMessage(id: "b", role: .companion, text: "answer")])
        store.recordVote(messageId: "b", vote: .up)
        store.recordVote(messageId: "b", vote: .down)
        XCTAssertEqual(store.chatMessages[0].vote, .down)
    }

    func testRecordVoteOnAnUnknownIdIsANoOp() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([CopilotMessage(id: "b", role: .companion, text: "answer")])
        store.recordVote(messageId: "nope", vote: .up)
        XCTAssertNil(store.chatMessages[0].vote)
    }
}
