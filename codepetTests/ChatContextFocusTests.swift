import XCTest
@testable import codepet

final class ChatContextFocusTests: XCTestCase {
    private let brief = CompanyBrief()
    private let dep = DepartmentCatalog.all.first!   // e.g. product/engineering

    func testFocusDirectivePresentWhenSet() {
        let out = ChatContext.compose(brief: brief, tasks: [], focusDepartment: dep)
        XCTAssertTrue(out.contains("focused on the \(dep.name) department"),
                      "focus directive should name the department")
        XCTAssertTrue(out.contains(dep.focus), "focus directive should include the dept focus line")
    }

    func testNoDirectiveWhenNil() {
        let out = ChatContext.compose(brief: brief, tasks: [], focusDepartment: nil)
        XCTAssertFalse(out.contains("focused on the"))
    }

    func testNilBranchEqualsDefaultCompose() {
        // Parity: passing focusDepartment nil must equal omitting it (no drift).
        let a = ChatContext.compose(brief: brief, tasks: [], focusDepartment: nil)
        let b = ChatContext.compose(brief: brief, tasks: [])
        XCTAssertEqual(a, b)
    }
}
