import XCTest
@testable import codepet

final class DepartmentCompanionsTests: XCTestCase {
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
    /// `actingSpecialist` give up instead of trying the next match — so this question
    /// silently lost luna · Design.
    func testAnUnmappedDepartmentDoesNotShadowAMappedOneMentionedLater() {
        XCTAssertNil(DepartmentCompanions.companionId(for: "product"),
                     "product has no companion — that is the premise of this test")
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "What should the design of my product page be?"),
                       "design")
    }

    func testAMentionOfOnlyAnUnmappedDepartmentResolvesToNothing() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "how do I price my product?"))
    }
}
