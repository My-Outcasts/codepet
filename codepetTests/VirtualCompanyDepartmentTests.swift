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
}
