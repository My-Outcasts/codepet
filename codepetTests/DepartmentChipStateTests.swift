import XCTest
@testable import codepet

/// A guess and a pick must not render alike. The old menu checkmarked on
/// `armed ?? suggestedDept`, so Codepet's guess appeared as the founder's decision —
/// while the composer chip, reading the same state, correctly drew it dashed.
final class DepartmentChipStateTests: XCTestCase {

    private func dept(_ key: String) throws -> Department {
        try XCTUnwrap(DepartmentCatalog.find(key), "no department '\(key)' in the catalog")
    }

    /// The regression this whole type exists to prevent. Collapse the two cases and
    /// this goes red.
    func testAGuessAndAPickAreDifferentStates() throws {
        let mkt = try dept("mkt")
        let guessed = DepartmentChipState.of(mkt, armed: nil, suggested: mkt)
        let picked = DepartmentChipState.of(mkt, armed: mkt, suggested: nil)
        XCTAssertEqual(guessed, .suggested)
        XCTAssertEqual(picked, .picked)
        XCTAssertNotEqual(guessed, picked)
    }

    /// A pick outranks a suggestion on the SAME department — it is no longer a guess
    /// once the founder has chosen it.
    func testPickingTheSuggestedDepartmentMakesItPicked() throws {
        let mkt = try dept("mkt")
        XCTAssertEqual(DepartmentChipState.of(mkt, armed: mkt, suggested: mkt), .picked)
    }

    /// A suggestion is suppressed entirely once anything is armed — the rule
    /// `ChatComposer.departmentControl` already applies as
    /// `activeSuggestion = armed == nil ? suggestion : nil`. Without this, arming Sales
    /// would leave Marketing dashed beside it and two chips would claim the turn.
    func testASuggestionIsSuppressedWhileSomethingElseIsArmed() throws {
        let mkt = try dept("mkt")
        let sales = try dept("sales")
        XCTAssertEqual(DepartmentChipState.of(mkt, armed: sales, suggested: mkt), .idle)
    }

    func testEverythingElseIsIdle() throws {
        let eng = try dept("eng")
        let mkt = try dept("mkt")
        XCTAssertEqual(DepartmentChipState.of(eng, armed: nil, suggested: nil), .idle)
        XCTAssertEqual(DepartmentChipState.of(eng, armed: mkt, suggested: nil), .idle)
    }
}
