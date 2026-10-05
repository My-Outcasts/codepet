import XCTest
@testable import codepet

/// CP-059: what a past turn says on the wire, so the model can see the work it already did.
///
/// A finished run lands in chat as a draft card: a companion message whose `text` is "" and
/// whose `draft` carries the deliverable. History went out as `text` only, and the backend
/// drops blank turns (`buildMessages`), so the model saw its own "Running X now" followed by
/// nothing. With the runnable gate saying "do not imply anything is being produced", it then
/// "corrected" itself, every turn: "I wasn't running it". Observed 5 Oct on build 7, ~8 flips.
final class ChatHistoryWireTests: XCTestCase {

    private func draft(_ title: String, kind: DeliverableKind = .post) -> Deliverable {
        Deliverable(id: "d1", kind: kind, title: title, body: "body")
    }

    func testADraftCardIsNotBlankOnTheWire() {
        let m = CopilotMessage(role: .companion, text: "", draft: draft("LinkedIn post — private beta"))
        let wire = ChatHistoryWire.text(for: m)
        XCTAssertFalse(wire.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "a blank turn is dropped by the backend, and the run with it")
        XCTAssertTrue(wire.contains("LinkedIn post — private beta"))
        XCTAssertTrue(wire.contains("waiting for the founder's approval"))
    }

    func testAnApprovedDraftSaysItWasApproved() {
        var m = CopilotMessage(role: .companion, text: "", draft: draft("Beta checklist", kind: .checklist))
        m.draftApproved = true
        let wire = ChatHistoryWire.text(for: m)
        XCTAssertTrue(wire.contains("Beta checklist"))
        XCTAssertTrue(wire.contains("approved"))
        XCTAssertFalse(wire.contains("waiting for the founder's approval"))
    }

    func testTheKindIsNamedSoTheModelKnowsWhatItMade() {
        let m = CopilotMessage(role: .companion, text: "", draft: draft("Pricing model", kind: .sheet))
        XCTAssertTrue(ChatHistoryWire.text(for: m).contains("sheet"))
    }

    func testAMessageWithTextAndADraftKeepsItsTextFirst() {
        let m = CopilotMessage(role: .companion, text: "Here it is.", draft: draft("Welcome email", kind: .email))
        let wire = ChatHistoryWire.text(for: m)
        XCTAssertTrue(wire.hasPrefix("Here it is."))
        XCTAssertTrue(wire.contains("Welcome email"))
    }

    func testAPlainTurnIsUnchanged() {
        XCTAssertEqual(ChatHistoryWire.text(for: CopilotMessage(role: .me, text: "Run it")), "Run it")
        XCTAssertEqual(ChatHistoryWire.text(for: CopilotMessage(role: .companion, text: "")), "",
                       "a genuinely blank turn stays blank — nothing to invent")
    }
}
