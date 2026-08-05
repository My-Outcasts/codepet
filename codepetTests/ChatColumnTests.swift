import XCTest
@testable import codepet

/// The chat's reading column is a SHARE of the chat box, so its one number is the spec:
/// 18% margin a side, 64% for the words, at every width the dock can be dragged to.
///
/// Worth a suite of its own because this arithmetic took five passes to get right by eye.
/// Four fixed-point attempts each read correctly at exactly one dock width and wrong either
/// side of it, and the failure mode was invisible in code review — the numbers all looked
/// reasonable. These assertions fail loudly instead.
final class ChatColumnTests: XCTestCase {

    /// The margin each side, derived the way the view derives it: whatever the column
    /// does not take, split in two.
    private func margin(inBox box: CGFloat) -> CGFloat {
        (box - ChatColumn.textWidth(forBox: box)) / 2
    }

    /// 18% a side, to within a point of rounding, across the dock's whole travel —
    /// `ShellLayout.dockMinWidth` (360) through `dockIdealMaxWidth` (560) and beyond,
    /// since dragging the handle overrides the ideal cap.
    func testMarginIsEighteenPercentASideAtEveryDockWidth() {
        for box in [CGFloat(360), 420, 480, 500, 560, 700, 900, 1100] {
            let share = margin(inBox: box) / box
            XCTAssertEqual(share, 0.18, accuracy: 0.005,
                           "box \(box): margin \(margin(inBox: box))pt is \(share * 100)% a side")
        }
    }

    /// The point of a ratio: the column tracks the box instead of standing still. A fixed
    /// measure passes the percentage test at ONE width and fails this one.
    func testColumnGrowsWithTheBox() {
        let narrow = ChatColumn.textWidth(forBox: 400)
        let wide = ChatColumn.textWidth(forBox: 800)
        XCTAssertGreaterThan(wide, narrow)
        XCTAssertEqual(wide, narrow * 2, accuracy: 1)   // strictly proportional
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
    }
}
