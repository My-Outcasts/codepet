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
}
