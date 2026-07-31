import XCTest
@testable import codepet

final class EditCodeRoutingTests: XCTestCase {
    private var eng: Department? { DepartmentCatalog.find("eng") }
    private var mkt: Department? { DepartmentCatalog.find("mkt") }

    func test_engineeringPill_withLink_routes() {
        XCTAssertTrue(EditCodeRouting.shouldRoute(department: eng, projectLinked: true))
    }
    func test_engineeringPill_noLink_doesNotRoute() {
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: eng, projectLinked: false))
    }
    func test_otherDept_orNil_doesNotRoute() {
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: mkt, projectLinked: true))
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: nil, projectLinked: true))
    }
}
