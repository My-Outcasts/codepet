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

    // MARK: - Message cards (`draft_message`), 7 Oct

    /// Chat's email / DM cards never reached history: the model's own "both versions are in the
    /// cards" came back with no cards, so "make the email shorter" had nothing to work from.
    func testMessageCardsAreOnTheWireWithTheirWords() {
        let email = MessageDraftDTO(channel: "email", to: "Building manager",
                                    subject: "15 minutes about parcels?", body: "Chào anh/chị, em là Quan.")
        let m = CopilotMessage(role: .companion, text: "I wrote two versions.", drafts: [email])
        let wire = ChatHistoryWire.text(for: m)
        XCTAssertTrue(wire.hasPrefix("I wrote two versions."), "the reply's own words come first")
        XCTAssertTrue(wire.contains("email"))
        XCTAssertTrue(wire.contains("Building manager"))
        XCTAssertTrue(wire.contains("15 minutes about parcels?"))
        XCTAssertTrue(wire.contains("Chào anh/chị, em là Quan."), "a revision needs the body itself")
    }

    func testOnlyCardsIsNotBlankOnTheWire() {
        let dm = MessageDraftDTO(channel: "dm", to: nil, subject: nil, body: "See you at 3?")
        let wire = ChatHistoryWire.text(for: CopilotMessage(role: .companion, text: "", drafts: [dm]))
        XCTAssertTrue(wire.contains("See you at 3?"))
    }

    /// One long email must not ride along in full on every later turn.
    func testALongCardBodyIsCapped() {
        let long = String(repeating: "a", count: 5_000)
        let card = MessageDraftDTO(channel: "email", to: nil, subject: nil, body: long)
        let wire = ChatHistoryWire.text(for: CopilotMessage(role: .companion, text: "x", drafts: [card]))
        XCTAssertLessThan(wire.count, 2_000)
        XCTAssertTrue(wire.contains("…"))
    }
}
