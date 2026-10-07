import XCTest
@testable import codepet

final class DepartmentCompanionsTests: XCTestCase {
    /// The composer's chip and the send that follows it read the same rule, so what the chip
    /// shows and what signs the reply cannot disagree. One unconditional resolver is what
    /// guarantees it: with no `host` parameter there is no input on which they could differ.
    ///
    /// The deleted `specialistId(for:host:)` returned nil here whenever `host == "nova"`, so the
    /// founder whose own companion was Nova got no attribution on Marketing. That is the
    /// behaviour change, and it gets no assertion of its own because it can no longer be
    /// expressed: there is no second input to vary. Nothing in Swift can assert that a deleted
    /// symbol stays deleted, so the guard against the rule returning is the doc comment on
    /// `DepartmentCompanions` and this test's name, not an assertion.
    func testCompanionIdIsUnconditional() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "mkt"), "nova")
        // Product is in the catalog to resolve a Virtual Company wire key; it has no pet.
        XCTAssertNil(DepartmentCompanions.companionId(for: "product"))
    }

    /// Byte takes Engineering — the department whose subject is the product being built,
    /// and the one whose founder-facing traffic is heaviest. This is the assertion that
    /// fails if a host rule is ever reintroduced: byte is also every founder's default
    /// companion, so a host rule would resolve this to nil for essentially everybody.
    func testCompanionIdForEng() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "eng"), "byte")
    }

    /// Crash takes Finance, which frees Sage to speak for Support alone.
    func testCompanionIdForFin() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "fin"), "crash")
    }

    /// Sage no longer doubles up. Since CP-058 no pet does (null took Legal, vega Sales).
    func testSageSpeaksForSupportAlone() {
        let sages = DepartmentCatalog.roster
            .filter { DepartmentCompanions.companionId(for: $0.key) == "sage" }
            .map(\.key)
        XCTAssertEqual(sages, ["support"])
    }

    /// CP-058 step 2 (7 Oct): Sales has its own pet, so Marketing and Sales no longer read as
    /// one character. Every roster department now maps to a DIFFERENT pet, each with art.
    func testSalesIsVegaAndEveryDepartmentHasItsOwnPet() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "sales"), "vega")
        let pets = DepartmentCatalog.roster.compactMap { DepartmentCompanions.companionId(for: $0.key) }
        XCTAssertEqual(pets.count, DepartmentCatalog.roster.count, "a roster department has no pet")
        XCTAssertEqual(Set(pets).count, pets.count, "two departments share a pet again")
        XCTAssertNotNil(PetCharacter.all["vega"], "vega is cast but has no character entry")
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
