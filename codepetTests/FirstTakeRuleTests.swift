// codepetTests/FirstTakeRuleTests.swift
import XCTest
@testable import codepet

/// CP-029: once the room lands, Codepet's first take is folded to one line and loses its own
/// offer. Before this, "Yes, make a new version" stayed purple above the room's "Lock this
/// decision in" — two primary buttons on one answer, and the founder could not tell which counted.
final class FirstTakeRuleTests: XCTestCase {
    private func reply(_ proposal: RoadmapProposal?, superseded: Bool) -> CopilotMessage {
        var m = CopilotMessage(role: .companion, text: "You've already got two in the Library…",
                               roadmapProposal: proposal)
        m.supersededByRoom = superseded
        return m
    }

    private let revise = RoadmapProposal.revise(libraryId: "lib1", title: "Landing page", note: "shorter")

    func testAFirstTakeTheRoomReplacedDrawsNoOffer() {
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(reply(revise, superseded: true)))
    }

    func testAReplyTheRoomDidNotReplaceKeepsItsOffer() {
        XCTAssertTrue(FirstTakeRule.drawsOwnOffer(reply(revise, superseded: false)))
    }

    /// Every offer-carrying branch of the message chain, not only the roadmap proposal: a first
    /// take can carry any of them, and each one drawn beside the room is a second primary action.
    func testNoOfferKindSurvivesTheRoom() {
        var m = CopilotMessage(role: .companion, text: "t", firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "Write the brief"))
        m.supersededByRoom = true
        m.chainOffer = nil
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(m), "first-run action")
        m.firstRunAction = nil
        m.blockedOffer = .grant(.claudeCode)
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(m), "grant offer")
    }

    /// The founder's own message is never a first take, whatever the flag says.
    func testTheFoundersOwnMessageIsNeverFolded() {
        var m = CopilotMessage(role: .me, text: "a landing page for this product")
        m.supersededByRoom = true
        XCTAssertFalse(FirstTakeRule.isFolded(m))
        XCTAssertTrue(FirstTakeRule.isFolded(reply(revise, superseded: true)))
    }
}
