import XCTest
@testable import codepet

/// CP-050, from Dominich's build 6 report (1 Oct): after locking in "Invoice ten founders now",
/// the chip read "Noted · Do we optimize for early revenue…". The DECISION was stored right —
/// topic = the room's question, statement = the pick — but the chip renders "topic — statement"
/// in two lines, and the room's question alone fills both, so the choice was never on screen.
///
/// The chip now leads with the choice under a short "Decision" label; the question stays on the
/// stored decision, where Settings → Memory and chat grounding read it.
final class LockInNotedChipTests: XCTestCase {
    private let extracted = ExtractedDecision(
        topic: "Do we optimize for early revenue from the founders who already asked, or for a bigger beta first?",
        statement: "Invoice ten founders now: revenue this month, a smaller beta",
        source: "virtual-company/r1")

    func testTheChipLeadsWithTheChoiceNotTheQuestion() {
        let chip = VirtualCompanyDecision.chipFact(for: extracted, language: .en)
        XCTAssertEqual(chip.topic, "Decision")
        XCTAssertEqual(chip.statement, "Invoice ten founders now: revenue this month, a smaller beta")
        XCTAssertFalse(chip.topic.contains("optimize"), "the long question must not lead the chip")
    }

    func testTheChipLabelIsLocalised() {
        XCTAssertEqual(VirtualCompanyDecision.chipFact(for: extracted, language: .vi).topic, "Quyết định")
    }
}
