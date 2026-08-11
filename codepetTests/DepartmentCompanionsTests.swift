import XCTest
@testable import codepet

final class DepartmentCompanionsTests: XCTestCase {
    /// The composer's chip and the send that follows it read the same rule, so what the chip
    /// shows and what signs the reply cannot disagree.
    func testSpecialistIdDeclinesTheHostAndTheUnmapped() {
        // Cast to someone other than the founder's companion — the visible handoff.
        XCTAssertEqual(DepartmentCompanions.specialistId(for: "mkt", host: "byte"), "nova")
        // The founder whose OWN companion is Nova gets no handoff on Marketing: announcing a
        // handoff to yourself says nothing, and a chip showing Nova would promise one.
        XCTAssertNil(DepartmentCompanions.specialistId(for: "mkt", host: "nova"))
        // Product is in the catalog to resolve a Virtual Company wire key; it has no pet.
        XCTAssertNil(DepartmentCompanions.specialistId(for: "product", host: "byte"))
    }

    func testCompanionIdForEng() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "eng"), "crash")
    }

    func testCompanionIdForByte() {
        XCTAssertNil(DepartmentCompanions.companionId(for: "byte"))
    }

    func testMentionedDeptKeyForMarketing() {
        let result = DepartmentCompanions.mentionedDeptKey(in: "help me with marketing")
        XCTAssertEqual(result, "mkt")
    }

    func testMentionedDeptKeyForHello() {
        let result = DepartmentCompanions.mentionedDeptKey(in: "hello")
        XCTAssertNil(result)
    }

    /// Regression: adding `product` to the catalog (for the Virtual Company's
    /// `department_key`) put an unmapped entry at index 1, and returning it made
    /// `actingSpecialist` give up instead of trying the next match — so a question naming both
    /// silently lost luna · Design.
    ///
    /// The phrasing changed on Aug 10, because the one it shipped with had been RED on `main`
    /// since the Aug 7 addressing fix. "What should the design of my product page be?" mentions
    /// design without addressing it, so the addressing rule — added after this test — declines it
    /// on its own, before the shadowing this test is about can even come up. The assertion was
    /// therefore checking a promise the code had stopped making, in the file whose doc comment
    /// still cites it. An addressed phrasing puts the original regression back under test: if the
    /// `map[dept.key] != nil` skip in `mentionedDeptKey` is deleted, `product` matches at index 1,
    /// resolves to no companion, and this goes red again — which is the whole point of it.
    func testAnUnmappedDepartmentDoesNotShadowAMappedOneMentionedLater() {
        XCTAssertNil(DepartmentCompanions.companionId(for: "product"),
                     "product has no companion — that is the premise of this test")
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "ask design about my product page"),
                       "design")
    }

    /// The other half of the phrasing change above, pinned so it can't drift back silently:
    /// merely naming a department while asking the host a question stays with the host.
    func testMentioningTwoDepartmentsWithoutAddressingEitherStaysWithTheHost() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "What should the design of my product page be?"))
    }

    func testAMentionOfOnlyAnUnmappedDepartmentResolvesToNothing() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "how do I price my product?"))
    }
}
