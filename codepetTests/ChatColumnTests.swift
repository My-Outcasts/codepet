import XCTest
@testable import codepet

/// The chat's reading column: a fixed inset that holds at the widths the dock actually uses,
/// plus a cap that turns a dragged-wide dock into gutter.
///
/// Worth a suite of its own because this took seven passes. Four fixed-point attempts were
/// each right at exactly one dock width; then two percentages, which were the wrong MODEL —
/// the references do not scale their gutters with the pane at all (ChatGPT: `max-width: 800px`
/// with `40px 16px` padding), which is why they read tight when narrow and generous when wide.
/// Every failure looked reasonable in review. These assertions fail loudly instead.
final class ChatColumnTests: XCTestCase {

    /// The inset holds from `ShellLayout.dockMinWidth` (360pt) up to where the cap takes
    /// over at `measureCap + 2 × inset` (380pt). This is the assertion the percentage model
    /// fails — a ratio drifts at every one of these widths.
    func testInsetHoldsAtEveryDockWidthBelowTheCap() {
        for box in [CGFloat(360), 380, 420, 480, 500, 560, 620, 676] {
            XCTAssertEqual(ChatColumn.margin(forBox: box), ChatColumn.inset, accuracy: 0.51,
                           "box \(box): margin drifted to \(ChatColumn.margin(forBox: box))pt")
        }
    }

    /// Below the cap the words take everything the inset leaves, so a DRAGGED dock lengthens
    /// the lines one point for one. Window resizing can no longer reach this code path —
    /// `ShellLayout.dockWidth` is a constant now — so the only caller is a deliberate drag.
    func testColumnAbsorbsWidthUpToTheCap() {
        XCTAssertEqual(ChatColumn.textWidth(forBox: 380), 380 - ChatColumn.inset * 2, accuracy: 1)
        let a = ChatColumn.textWidth(forBox: 400)
        let b = ChatColumn.textWidth(forBox: 500)
        XCTAssertEqual(b - a, 100, accuracy: 1)
    }

    /// The column at the shell's default dock width is the layout the founder approved, and
    /// it must be the inset that decides it rather than the cap — if the cap ever binds here,
    /// the default dock and the reading column have drifted out of step.
    func testTheDefaultDockYieldsTheApprovedColumn() {
        let box = ShellLayout.dockDefaultWidth
        XCTAssertEqual(ChatColumn.textWidth(forBox: box), box - ChatColumn.inset * 2, accuracy: 1)
        XCTAssertEqual(ChatColumn.margin(forBox: box), ChatColumn.inset, accuracy: 0.51)
        XCTAssertLessThan(ChatColumn.textWidth(forBox: box), ChatColumn.measureCap)
    }

    /// Past the cap the words stop growing and every further point becomes margin — the
    /// behaviour that makes a wide dock read like the references rather than a billboard.
    func testSurplusPastTheCapBecomesMargin() {
        XCTAssertEqual(ChatColumn.textWidth(forBox: 900), ChatColumn.measureCap)
        XCTAssertEqual(ChatColumn.margin(forBox: 900), (900 - ChatColumn.measureCap) / 2, accuracy: 0.51)
        XCTAssertGreaterThan(ChatColumn.margin(forBox: 1400), ChatColumn.margin(forBox: 900))
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
        XCTAssertEqual(ChatColumn.textWidth(forBox: 30), 0)   // narrower than its own insets
        XCTAssertGreaterThanOrEqual(ChatColumn.margin(forBox: 0), 0)
    }
}

/// The chat's vertical rhythm. Only the speaker-change rule has logic worth testing; the
/// rest are constants the views read directly.
final class ChatRhythmTests: XCTestCase {

    /// A turn boundary gets the extra gap; a continuation from the same speaker does not.
    /// This is the rule that stopped a question and its answer sitting as close together as
    /// two paragraphs from one speaker.
    func testSpeakerChangeEarnsTheExtraGap() {
        XCTAssertEqual(ChatRhythm.extraGap(after: .me, before: .companion), ChatRhythm.speakerChangeGap)
        XCTAssertEqual(ChatRhythm.extraGap(after: .companion, before: .me), ChatRhythm.speakerChangeGap)
    }

    func testSameSpeakerStaysAContinuation() {
        XCTAssertEqual(ChatRhythm.extraGap(after: .companion, before: .companion), 0)
        XCTAssertEqual(ChatRhythm.extraGap(after: .me, before: .me), 0)
    }

    /// The first message has no predecessor — the transcript's top padding already spaces it,
    /// so adding a turn gap would double it.
    func testFirstMessageGetsNoExtraGap() {
        XCTAssertEqual(ChatRhythm.extraGap(after: nil, before: .companion), 0)
        XCTAssertEqual(ChatRhythm.extraGap(after: nil, before: .me), 0)
    }

    /// The references put ~1.6em under a line of body text; SwiftUI's lineSpacing adds to the
    /// font's natural ~1.2em, so this is the arithmetic that has to hold for 13.5pt body.
    func testLineSpacingLandsNearTheReferenceLineHeight() {
        let body: CGFloat = 13.5
        let lineHeight = body * 1.2 + ChatRhythm.lineSpacing
        XCTAssertEqual(lineHeight / body, 1.6, accuracy: 0.1)
    }
}
