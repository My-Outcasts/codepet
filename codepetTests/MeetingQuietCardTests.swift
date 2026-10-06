// codepetTests/MeetingQuietCardTests.swift
import XCTest
@testable import codepet

/// The quieter department meeting (6 Oct design pass, mock approved): one card that grows, a
/// five-step strip for the process, the departments side by side, and each side's "changes its
/// mind if" from its latest negotiation turn. The views only read these.
final class MeetingQuietCardTests: XCTestCase {

    private func meta(_ id: String, _ dept: String?) -> VCAgentMeta { VCAgentMeta(agentId: id, departmentKey: dept) }

    private func position(_ stance: String = "proceed_with_conditions", _ text: String = "Fine.") -> VCPosition {
        VCPosition(stance: stance, position: text, reasoning: "r", evidenceNeeded: [], risksIOwn: [],
                   confidence: 3, costToMyDept: "c", hardBlocker: nil)
    }

    private func turn(_ agent: String, _ mind: String) -> VCNegotiationTurn {
        VCNegotiationTurn(agent: agent, preciseDisagreement: "d", whatWouldChangeMyMind: mind,
                          proposal: "p", resolved: false)
    }

    // MARK: step strip

    /// Five fixed steps, so the strip never reflows while the meeting moves. The current one is
    /// read off the same stage the old progress row used, so the two cannot disagree.
    func testTheStripMapsEachProgressStageToOneStep() {
        XCTAssertEqual(MeetingSteps.current(.routing), 0)
        XCTAssertEqual(MeetingSteps.current(.answering(done: 0, total: 2)), 1)
        XCTAssertEqual(MeetingSteps.current(.comparing), 2)
        XCTAssertEqual(MeetingSteps.current(.negotiating(round: 1)), 3)
        XCTAssertEqual(MeetingSteps.current(.finishing), 4)
        XCTAssertEqual(MeetingSteps.titles(.en), ["Asked", "Answering", "Comparing", "Negotiating", "Call"])
        XCTAssertEqual(MeetingSteps.titles(.vi).count, 5)
    }

    // MARK: words for the wire values

    /// The stance in plain words under the department, replacing a purple "with conditions" chip.
    func testStanceReadsAsPlainWords() {
        XCTAssertEqual(MeetingWords.stance("proceed", lang: .en), "Yes")
        XCTAssertEqual(MeetingWords.stance("proceed_with_conditions", lang: .en), "Yes, with conditions")
        XCTAssertEqual(MeetingWords.stance("do_not_proceed", lang: .en), "No")
        XCTAssertEqual(MeetingWords.stance("proceed_with_conditions", lang: .vi), "Làm, có điều kiện")
    }

    /// Confidence stays as dots (rule 7); the word sits beside them, never a number.
    func testConfidenceGetsAWordNotANumber() {
        XCTAssertEqual(MeetingWords.confidence(1, lang: .en), "Not very sure")
        XCTAssertEqual(MeetingWords.confidence(2, lang: .en), "Not very sure")
        XCTAssertEqual(MeetingWords.confidence(3, lang: .en), "Fairly sure")
        XCTAssertEqual(MeetingWords.confidence(4, lang: .en), "Sure")
        XCTAssertEqual(MeetingWords.confidence(5, lang: .en), "Very sure")
        for n in 1...5 {
            XCTAssertFalse(MeetingWords.confidence(n, lang: .en).contains(where: \.isNumber), "rule 7: no number")
        }
    }

    // MARK: changes its mind if

    /// Rule 4. The falsifier lives on negotiation TURNS, not on positions, so it is the latest
    /// round's line for that department — and nothing before negotiating starts.
    func testChangesItsMindIfComesFromTheLatestRound() {
        let r1 = VCNegotiationRound(round: 1, turns: [turn("design", "old line"), turn("sales", "sales line")])
        let r2 = VCNegotiationRound(round: 2, turns: [turn("design", "newer line"), turn("sales", "  ")])
        XCTAssertEqual(MeetingWords.changesMind("design", rounds: [r1, r2]), "newer line")
        XCTAssertEqual(MeetingWords.changesMind("sales", rounds: [r1, r2]), "sales line",
                       "a blank later turn does not erase an earlier real one")
        XCTAssertNil(MeetingWords.changesMind("legal", rounds: [r1, r2]))
        XCTAssertNil(MeetingWords.changesMind("design", rounds: []))
    }

    // MARK: the answer in a column

    /// A column shows the first full sentence, never a cut-off mid-sentence; the rest is one
    /// click away. Same text, clamped at a sentence — not rewritten (rule 2).
    func testAnAnswerLeadsWithItsFirstSentence() {
        let full = "A one-page form can work. But only if it pre-qualifies commitment, not just a name."
        XCTAssertEqual(MeetingWords.lead(full), "A one-page form can work.")
        XCTAssertTrue(MeetingWords.hasMore(full))
        XCTAssertEqual(MeetingWords.lead("One sentence only."), "One sentence only.")
        XCTAssertFalse(MeetingWords.hasMore("One sentence only."))
    }

    // MARK: columns

    /// Side by side when it fits: every department in one row up to three, a 2x2 grid for four,
    /// and a single stacked column as the last resort (the dock is 380pt wide).
    func testSeatLayoutsTryWideThenNarrow() {
        XCTAssertEqual(MeetingSeats.columnChoices(count: 1), [1])
        XCTAssertEqual(MeetingSeats.columnChoices(count: 2), [2, 1])
        XCTAssertEqual(MeetingSeats.columnChoices(count: 3), [3, 1])
        XCTAssertEqual(MeetingSeats.columnChoices(count: 4), [2, 1])
    }

    /// The seats are the room's departments in seat order. Chief of staff and the challenger
    /// have no department key and take no seat.
    func testSeatsAreTheDepartmentsOnly() {
        let seats = MeetingSeats.departments([meta("cos", nil), meta("design", "design"), meta("da", nil), meta("sales", "sales")])
        XCTAssertEqual(seats.map(\.agentId), ["design", "sales"])
    }

    /// "Design and Sales are in the room" — the one line that replaces the IN THE ROOM / SAT OUT
    /// cells and the "0 of 2 answered" count.
    func testWhoIsInTheRoomReadsAsOneLine() {
        XCTAssertEqual(MeetingWords.inTheRoom(["Design"], lang: .en), "Design is in the room")
        XCTAssertEqual(MeetingWords.inTheRoom(["Design", "Sales"], lang: .en), "Design and Sales are in the room")
        XCTAssertEqual(MeetingWords.inTheRoom(["Design", "Sales", "Legal"], lang: .en), "Design, Sales and Legal are in the room")
        XCTAssertEqual(MeetingWords.inTheRoom(["Design", "Sales"], lang: .vi), "Design và Sales đang họp")
    }
}
