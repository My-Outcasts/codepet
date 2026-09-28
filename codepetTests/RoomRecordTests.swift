// codepetTests/RoomRecordTests.swift
import XCTest
@testable import codepet

/// CP-032: a landed room kept four disclosure bars in the chat ("What each department said",
/// "Who was in the room, and why", "How they negotiated", "What could make this wrong"), and
/// each opened several screens of text inline. They move to a side panel with three tabs,
/// opened from department chips and one "How the team decided" link on the room's answer.
final class RoomRecordTests: XCTestCase {
    private func pos(_ stance: String, _ text: String = "p") -> VCPosition {
        VCPosition(stance: stance, position: text, reasoning: "r", evidenceNeeded: [], risksIOwn: [],
                   confidence: 3, costToMyDept: "c", hardBlocker: nil)
    }

    private func landed() -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        for (id, dept, stance) in [("finance", "fin", "do_not_proceed"), ("marketing", "mkt", "proceed"),
                                   ("sales", "sales", "proceed_with_conditions")] {
            let meta = VCAgentMeta(agentId: id, departmentKey: dept)
            s.apply(.agentStart(meta))
            s.apply(.agentPosition(meta, pos(stance)))
        }
        s.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        s.apply(.agentError(VCAgentMeta(agentId: "product", departmentKey: "product"), "timed out"))
        s.apply(.negotiationRound(VCNegotiationRound(round: 1, turns: [])))
        s.apply(.negotiationRound(VCNegotiationRound(round: 2, turns: [])))
        return s
    }

    /// One chip per department in the room, in the order they joined, with how it came out.
    func testChipsFollowTheRoomsOrderAndStance() {
        let chips = RoomRecord.chips(landed())
        XCTAssertEqual(chips.map(\.agentId), ["finance", "marketing", "sales", "product"])
        XCTAssertEqual(chips.map(\.outcome), [.against, .agreed, .withConditions, .noAnswer])
    }

    func testTabsAreStancesDisagreementsAndTheFullRecord() {
        XCTAssertEqual(RoomRecordTab.allCases, [.stances, .disagreements, .record])
        XCTAssertEqual(RoomRecordTab.stances.title(landed(), lang: .en), "Stances · 4")
        XCTAssertEqual(RoomRecordTab.disagreements.title(landed(), lang: .en), "Disagreements")
        XCTAssertEqual(RoomRecordTab.record.title(landed(), lang: .en), "Full record · 2 rounds")
        XCTAssertEqual(RoomRecordTab.stances.title(landed(), lang: .vi), "Lập trường · 4")
    }

    /// A department chip opens its stance; the link opens the stances tab too, where the answer is.
    func testTheLinkCopy() {
        XCTAssertEqual(RoomRecord.linkTitle(.en), "How the team decided ›")
        XCTAssertEqual(RoomRecord.linkTitle(.vi), "Cả đội đã quyết định thế nào ›")
    }
}
