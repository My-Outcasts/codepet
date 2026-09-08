import XCTest
import SwiftUI
@testable import codepet

/// Row-breaking arithmetic, separated from SwiftUI so it can be checked.
///
/// The composer must show every attached file — ten tiles cannot fit one 380pt row, and
/// hiding the overflow behind a counter puts invisible state in the control the founder is
/// about to spend credits from.
final class WrapLayoutTests: XCTestCase {

    /// Widths that fit on one row stay on one row.
    func testOneRowWhenEverythingFits() {
        let rows = WrapLayout.rows(widths: [50, 50, 50], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1, 2]])
    }

    /// The item that does not fit starts the next row rather than being dropped or clipped.
    func testBreaksToASecondRow() {
        let rows = WrapLayout.rows(widths: [80, 80, 80], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    /// Spacing counts toward the row width — without it the last tile on each row overhangs.
    func testSpacingCountsTowardTheRowWidth() {
        // 3x64 = 192 fits 200 on width alone; with 2 gaps of 6 it is 204 and must break.
        let rows = WrapLayout.rows(widths: [64, 64, 64], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    /// An item wider than the row gets its own row rather than looping forever.
    func testAnOversizeItemGetsItsOwnRow() {
        let rows = WrapLayout.rows(widths: [400, 50], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0], [1]])
    }

    func testNoItemsIsNoRows() {
        XCTAssertEqual(WrapLayout.rows(widths: [], available: 200, spacing: 6), [])
    }
}
