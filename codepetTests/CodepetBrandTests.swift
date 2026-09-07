import XCTest
@testable import codepet

/// Who signs a reply. The nil case is the load-bearing one: the founder talks to the
/// product, so an ordinary turn carries no name — which is the only reason a pet's name
/// reads as different when it appears.
final class CodepetBrandTests: XCTestCase {

    func testAPetWithADepartmentSignsWithBoth() {
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: "Marketing"),
                       "Nova · Marketing")
    }

    func testAPetWithNoDepartmentSignsWithItsNameAlone() {
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: nil), "Nova")
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: ""), "Nova")
    }

    /// NOT "Codepet". The product does not announce itself on every turn.
    func testTheProductsOwnVoiceHasNoHeader() {
        XCTAssertNil(CodepetBrand.header(companionId: nil, deptName: nil))
        XCTAssertNil(CodepetBrand.header(companionId: nil, deptName: "Marketing"))
    }

    /// An id no character claims is the product speaking, not a blank pet row.
    func testAnUnknownCompanionIdHasNoHeader() {
        XCTAssertNil(CodepetBrand.header(companionId: "nobody", deptName: "Marketing"))
    }

    /// `byte` is a department character named "Byte" since 26 Aug. If a caller ever
    /// attributes a general reply to the host companion, it must NOT read "Codepet" —
    /// it reads "Byte", which is the bug this rule exists to make visible rather than hide.
    func testByteIsACharacterNotTheProduct() {
        XCTAssertEqual(CodepetBrand.header(companionId: "byte", deptName: "Engineering"),
                       "Byte · Engineering")
    }
}
