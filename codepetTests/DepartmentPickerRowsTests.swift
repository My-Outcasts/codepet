import AppKit
import XCTest
@testable import codepet

/// The picker iterates PETS, not departments — that is the whole point of the redesign.
/// These are the rules that grouping has to hold.
final class DepartmentPickerRowsTests: XCTestCase {

    /// Totality. Every roster department lands in exactly one pet's row: none dropped,
    /// none duplicated. Add a department with no pet, or give one to a second pet, and
    /// this goes red — which is the moment a design decision is owed.
    func testGroupingCoversTheRosterExactlyOnce() {
        let flat = DepartmentPickerRows.rows.flatMap { $0.departments.map(\.key) }
        XCTAssertEqual(flat.sorted(), DepartmentMenu.rosterOrder.map(\.key).sorted(),
                       "the grouping and the roster disagree")
        XCTAssertEqual(Set(flat).count, flat.count, "a department appears in two rows")
    }

    /// The two-department pets are the reason this type exists.
    func testNovaCarriesMarketingAndSalesInOneRow() throws {
        let nova = try XCTUnwrap(DepartmentPickerRows.rows.first { $0.petId == "nova" })
        XCTAssertEqual(nova.departments.map(\.key), ["mkt", "sales"])
        XCTAssertEqual(nova.petName, "Nova")
    }

    func testGlitchCarriesOperationsAndLegalInOneRow() throws {
        let glitch = try XCTUnwrap(DepartmentPickerRows.rows.first { $0.petId == "glitch" })
        XCTAssertEqual(glitch.departments.map(\.key), ["ops", "legal"])
    }

    /// Pet order follows first appearance in the roster, so the visual order the
    /// founder already knows is preserved by the redesign rather than reshuffled.
    func testPetOrderFollowsFirstAppearanceInTheRoster() {
        XCTAssertEqual(DepartmentPickerRows.rows.map(\.petId),
                       ["byte", "luna", "nova", "sage", "crash", "glitch"])
    }

    /// Six rows for eight departments — the duplication the redesign removes.
    func testSixRowsForEightDepartments() {
        XCTAssertEqual(DepartmentPickerRows.rows.count, 6)
        XCTAssertEqual(DepartmentMenu.rosterOrder.count, 8)
    }

    /// Every pet the picker can summon needs art, or a row shows a blank face. This is the
    /// asset-existence guard `PetMenuIconTests.testEverySpriteReportsMenuIconSize` used to
    /// carry before `PetMenuIcon` was deleted; `CharacterImage` has no nil-image fallback to
    /// text the way `PetMenuIcon.image` did, so a missing sprite now renders a blank 20×20
    /// box instead of failing loudly.
    func testEveryRowsPetHasArt() {
        for row in DepartmentPickerRows.rows {
            XCTAssertNotNil(NSImage(named: "char-\(row.petId)"),
                             "no sprite for \(row.petId) — the picker would show a blank face")
        }
    }
}
