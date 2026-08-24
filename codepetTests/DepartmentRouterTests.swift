import XCTest
@testable import codepet

/// Tier order is the safety model. Tier 1 is today's behaviour, called unchanged and placed
/// above everything new — so every message that routes today routes the same way, and the new
/// tiers can only add answers where there were none.
final class DepartmentRouterTests: XCTestCase {

    func testAddressedWins() {
        let s = DepartmentRouter.suggest(text: "ask marketing about the launch",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.tier, .addressed)
    }

    func testNothingToGoOnYieldsNoSuggestion() {
        XCTAssertNil(DepartmentRouter.suggest(text: "hello",
                                              tasks: [], lastActed: nil, language: .en))
    }

    func testEmptyDraftIsNeverPreArmed() {
        XCTAssertNil(DepartmentRouter.suggest(text: "",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "   \n  ",
                                              tasks: [], lastActed: nil, language: .en))
    }
}
