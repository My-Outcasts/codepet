import XCTest
@testable import codepet

final class VirtualCompanyDepartmentTests: XCTestCase {

    /// The backend emits department_key "product" and "fin" for its two
    /// department agents (contract line 161). Both must resolve or the column
    /// renders with no name, cover or accent.
    func testEveryDepartmentKeyTheBackendSendsResolves() {
        let keys = Set(DepartmentCatalog.all.map(\.key))
        XCTAssertTrue(keys.contains("product"), "backend sends department_key=product")
        XCTAssertTrue(keys.contains("fin"), "backend sends department_key=fin")
    }

    func testProductDepartmentIsFullyPopulated() {
        let product = DepartmentCatalog.all.first { $0.key == "product" }
        let dept = try? XCTUnwrap(product)
        XCTAssertNotNil(dept)
        guard let dept else { return }
        XCTAssertFalse(dept.name.isEmpty)
        XCTAssertEqual(dept.ab.count, 2)
        XCTAssertFalse(dept.rationale.isEmpty)
        XCTAssertFalse(dept.focus.isEmpty)
    }

    func testKeysStayUnique() {
        let keys = DepartmentCatalog.all.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    /// The catalog entry exists so `department_key: "product"` resolves; the roster is
    /// what the founder is shown. Product has no cover art of its own
    /// (`dept-product.png` is a copy of `dept-eng.png`), and a row wearing another
    /// department's illustration ships to every founder whether or not they ever convene
    /// the room. Give Product real art, then delete the filter and this test.
    func testProductResolvesButIsNotOnTheRosterYet() {
        XCTAssertNotNil(DepartmentCatalog.find("product"))
        XCTAssertFalse(DepartmentCatalog.roster.contains { $0.key == "product" })
        XCTAssertEqual(DepartmentCatalog.roster.count, DepartmentCatalog.all.count - 1)
    }

    func testProductDoesNotShareItsAccentWithAnotherDepartment() {
        let product = DepartmentCatalog.find("product")
        XCTAssertNotNil(product)
        XCTAssertNotEqual(product?.accent, DepartmentCatalog.find("ops")?.accent)
        XCTAssertNotEqual(product?.accent, DepartmentCatalog.find("eng")?.accent)
    }

    /// Chat grounding is keyed on task `dept`, not on what is displayed, so filtering the
    /// roster must not hide a product-tagged task from the department block.
    func testSummariesStillCoverEveryCatalogDepartment() {
        XCTAssertEqual(DepartmentCatalog.summaries(tasks: []).count, DepartmentCatalog.all.count)
    }
}
