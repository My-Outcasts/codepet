import XCTest
@testable import codepet

/// The chat's reading column: a margin that is a SHARE of the chat box, clamped at both
/// ends, with the words taking the rest.
///
/// Worth a suite of its own because this arithmetic took six passes to get right by eye.
/// Four fixed-point attempts each read correctly at exactly one dock width and wrong either
/// side of it; the fifth was a pure 18% ratio, right at the ~800pt pane it was measured from
/// and too generous at the 381pt dock the founder actually had. Every failure looked
/// reasonable in review — the numbers were all plausible. These assertions fail loudly.
final class ChatColumnTests: XCTestCase {

    /// Between the clamps the ratio governs: 12% a side, so the words keep 76%.
    func testMarginIsTwelvePercentASideThroughTheDocksUsualTravel() {
        for box in [CGFloat(381), 420, 480, 500, 560, 700, 900] {
            let share = ChatColumn.margin(forBox: box) / box
            XCTAssertEqual(share, 0.12, accuracy: 0.005,
                           "box \(box): margin \(ChatColumn.margin(forBox: box))pt is \(share * 100)% a side")
        }
    }

    /// The point of a ratio: the column tracks the box instead of standing still. A fixed
    /// measure passes the percentage test at ONE width and fails this one.
    func testColumnGrowsWithTheBox() {
        let narrow = ChatColumn.textWidth(forBox: 400)
        let wide = ChatColumn.textWidth(forBox: 800)
        XCTAssertGreaterThan(wide, narrow)
        XCTAssertEqual(wide, narrow * 2, accuracy: 1)   // strictly proportional inside the band
    }

    /// Narrow end: the floor is a guard against a degenerate layout pass, not a working
    /// case — at `ShellLayout.dockMinWidth` (360pt) the ratio still governs, and the floor
    /// only bites well below any width the dock can actually be dragged to.
    func testFloorOnlyBitesBelowTheDockMinimum() {
        XCTAssertEqual(ChatColumn.margin(forBox: 360), 43.2, accuracy: 0.01)   // ratio still governs
        XCTAssertEqual(ChatColumn.margin(forBox: 150), ChatColumn.minMargin)   // floor
        XCTAssertEqual(ChatColumn.margin(forBox: 100), ChatColumn.minMargin)
    }

    /// Wide end: a dock dragged very wide must not become two enormous gutters. Past ~933pt
    /// the ceiling holds the margin and every further point goes to the words.
    func testCeilingHoldsTheMarginOnAVeryWideDock() {
        XCTAssertEqual(ChatColumn.margin(forBox: 1200), ChatColumn.maxMargin)
        XCTAssertEqual(ChatColumn.margin(forBox: 1600), ChatColumn.maxMargin)
        let a = ChatColumn.textWidth(forBox: 1200)
        let b = ChatColumn.textWidth(forBox: 1400)
        XCTAssertEqual(b - a, 200, accuracy: 1)   // surplus goes to the column, one for one
    }

    /// Rounded to whole points — a fractional column width lands the text's leading edge
    /// off-pixel and blurs the glyphs.
    func testColumnIsWholePoints() {
        for box in [CGFloat(361), 483, 501, 999] {
            let w = ChatColumn.textWidth(forBox: box)
            XCTAssertEqual(w, w.rounded(), "box \(box) produced a fractional column: \(w)")
        }
    }

    /// A zero or negative proposal happens during layout (a collapsing dock, a first pass
    /// before measurement) and must not produce a negative frame width.
    func testDegenerateBoxNeverGoesNegative() {
        XCTAssertEqual(ChatColumn.textWidth(forBox: 0), 0)
        XCTAssertEqual(ChatColumn.textWidth(forBox: -50), 0)
        XCTAssertEqual(ChatColumn.textWidth(forBox: 40), 0)   // narrower than its own margins
    }
}
