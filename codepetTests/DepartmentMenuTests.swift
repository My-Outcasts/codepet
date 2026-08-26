import XCTest
@testable import codepet

/// `DepartmentMenu`'s doc comment says a SwiftUI `Menu`'s rows cannot be asserted on, which
/// is why the type exists at all — and then nothing asserted on the type either. These are
/// the rules it claims to hold.
final class DepartmentMenuTests: XCTestCase {

    private func dept(_ key: String) throws -> Department {
        try XCTUnwrap(DepartmentCatalog.find(key), "no department '\(key)' in the catalog")
    }

    /// The row shows the pet that signs the reply. Both sides now read the same
    /// unconditional resolver, so this cannot drift.
    func testRowTitleNamesThePetThatSignsTheReply() throws {
        let mkt = try dept("mkt")
        let pet = try XCTUnwrap(DepartmentMenu.pet(for: mkt))
        XCTAssertEqual(pet, DepartmentCompanions.companionId(for: "mkt"))
        let name = try XCTUnwrap(PetCharacter.all[pet]?.name)
        XCTAssertEqual(DepartmentMenu.rowTitle(mkt), "\(name) · Marketing")
    }

    /// Picking a row and reading the button back must not look like two choices.
    func testArmedLabelMatchesTheRow() throws {
        for dep in DepartmentMenu.rosterOrder {
            XCTAssertEqual(DepartmentMenu.armedLabel(dep), DepartmentMenu.rowTitle(dep),
                           "\(dep.name)'s button and row disagree")
        }
    }

    /// A department with no pet shows the department alone — the row never promises a pet
    /// that will not appear. Product is that department today.
    func testUnmappedDepartmentShowsItsNameAlone() throws {
        let product = try dept("product")
        XCTAssertNil(DepartmentMenu.pet(for: product))
        XCTAssertEqual(DepartmentMenu.rowTitle(product), "Product")
    }

    /// Product is filtered out of the menu: `dept-product.png` is a byte-identical copy of
    /// `dept-eng.png`, so a row for it would wear Engineering's identity.
    func testRosterOrderExcludesProduct() {
        XCTAssertFalse(DepartmentMenu.rosterOrder.contains { $0.key == "product" })
    }
}
