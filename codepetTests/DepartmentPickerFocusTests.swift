import XCTest
@testable import codepet

/// Traversal is a pure function so it can be asserted on at all — a SwiftUI row cannot be.
final class DepartmentPickerFocusTests: XCTestCase {

    private var rows: [PetRow] { DepartmentPickerRows.rows }

    /// Down from the Anyone row enters the list at the first pet's first chip.
    func testDownFromAnyoneEntersTheFirstRow() {
        XCTAssertEqual(DepartmentPickerFocus.down(from: .anyone, rows: rows),
                       .chip(pet: 0, dept: 0))
    }

    /// Up from the first row returns to Anyone rather than dead-ending.
    func testUpFromTheFirstRowReturnsToAnyone() {
        XCTAssertEqual(DepartmentPickerFocus.up(from: .chip(pet: 0, dept: 0), rows: rows),
                       .anyone)
    }

    /// Crossing rows resets to the first chip: arriving at Nova should land on Marketing,
    /// not on whichever column the previous row happened to leave behind.
    func testMovingBetweenRowsResetsToTheFirstChip() {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        XCTAssertEqual(DepartmentPickerFocus.down(from: .chip(pet: nova, dept: 1), rows: rows),
                       .chip(pet: nova + 1, dept: 0))
    }

    /// Left/right walk a two-chip row and STOP at both ends — clamped, not wrapped.
    /// Wrapping would make Sales one keypress from Marketing in both directions, which
    /// reads as the focus jumping rather than moving.
    func testRightAndLeftWalkNovasTwoChipsAndClamp() {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        let first = PickerFocus.chip(pet: nova, dept: 0)
        let second = PickerFocus.chip(pet: nova, dept: 1)
        XCTAssertEqual(DepartmentPickerFocus.right(from: first, rows: rows), second)
        XCTAssertEqual(DepartmentPickerFocus.right(from: second, rows: rows), second)
        XCTAssertEqual(DepartmentPickerFocus.left(from: second, rows: rows), first)
        XCTAssertEqual(DepartmentPickerFocus.left(from: first, rows: rows), first)
    }

    /// A one-chip row has nowhere to go sideways.
    func testSidewaysOnASingleChipRowStaysPut() {
        let byte = rows.firstIndex { $0.petId == "byte" }!
        let only = PickerFocus.chip(pet: byte, dept: 0)
        XCTAssertEqual(DepartmentPickerFocus.right(from: only, rows: rows), only)
        XCTAssertEqual(DepartmentPickerFocus.left(from: only, rows: rows), only)
    }

    /// Down from the last row stays on the last row.
    func testDownFromTheLastRowClamps() {
        let last = rows.count - 1
        let end = PickerFocus.chip(pet: last, dept: 0)
        XCTAssertEqual(DepartmentPickerFocus.down(from: end, rows: rows), end)
    }

    /// Sideways from Anyone does nothing — it has no chips.
    func testSidewaysFromAnyoneDoesNothing() {
        XCTAssertEqual(DepartmentPickerFocus.right(from: .anyone, rows: rows), .anyone)
        XCTAssertEqual(DepartmentPickerFocus.left(from: .anyone, rows: rows), .anyone)
    }

    /// Return needs to know what is under the cursor.
    func testDepartmentAtResolvesTheFocusedChip() throws {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        let dep = try XCTUnwrap(
            DepartmentPickerFocus.department(at: .chip(pet: nova, dept: 1), rows: rows))
        XCTAssertEqual(dep.key, "sales")
        XCTAssertNil(DepartmentPickerFocus.department(at: .anyone, rows: rows))
    }

    /// Opening the picker on a single-department pet lands on its one chip.
    func testLocateFindsASingleDepartmentPetsChip() throws {
        let byte = rows.firstIndex { $0.petId == "byte" }!
        let engineering = try XCTUnwrap(rows[byte].departments.first)
        XCTAssertEqual(DepartmentPickerFocus.locate(engineering, in: rows),
                       .chip(pet: byte, dept: 0))
    }

    /// Opening on the SECOND chip of a two-department pet lands on that slot, not the first.
    func testLocateFindsTheSecondChipOfATwoDepartmentPet() throws {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        let sales = try XCTUnwrap(rows[nova].departments.first { $0.key == "sales" })
        XCTAssertEqual(DepartmentPickerFocus.locate(sales, in: rows),
                       .chip(pet: nova, dept: 1))
    }

    /// Product is in the catalog but filtered out of `rosterOrder`, so no row carries it.
    /// This is the silent fallback the view used to hide — pin it explicitly.
    func testLocateFallsBackToAnyoneForADepartmentNoRowCarries() throws {
        let product = try XCTUnwrap(DepartmentCatalog.find("product"))
        XCTAssertEqual(DepartmentPickerFocus.locate(product, in: rows), .anyone)
    }

    /// A row's `departments` array can be empty by construction (`PetRow` is publicly
    /// constructible), which used to make `right(from:rows:)` yield `dept: -1` and then
    /// `department(at:rows:)` would trap on `rows[pet].departments[-1]` instead of
    /// reporting "nothing here." The guard needs a lower bound, not just an upper one.
    func testDepartmentAtReturnsNilRatherThanTrappingOnANegativeIndex() {
        XCTAssertNil(DepartmentPickerFocus.department(at: .chip(pet: 0, dept: -1), rows: rows))
    }

    /// `locate` and `department(at:)` are inverses for every chip actually on screen.
    func testLocateAndDepartmentAtRoundTripForEveryChip() {
        for row in rows {
            for dep in row.departments {
                let focus = DepartmentPickerFocus.locate(dep, in: rows)
                XCTAssertEqual(DepartmentPickerFocus.department(at: focus, rows: rows)?.key, dep.key)
            }
        }
    }
}
