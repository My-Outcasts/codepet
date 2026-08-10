// codepetTests/ComposerMetricsTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// How tall the chat composer's text field gets, and when it starts scrolling.
///
/// Founder, Aug 10, with a screenshot of a pasted email: the field was a vertical `TextField`
/// capped at `lineLimit(1...6)`, so past six lines the rest of the message was in the draft with
/// no way to reach it — no scrollbar, no wheel. The cap now lives on a `ScrollView` instead, and
/// these are the numbers that decide whether it grows or scrolls.
///
/// Tested rather than eyeballed because this view cannot be screenshotted from here, and both
/// failure modes are silent: an unmeasured first frame collapsing the field to nothing, and a
/// long paste growing it until it eats the transcript.
final class ComposerMetricsTests: XCTestCase {

    /// Before the first measurement lands the height is 0. Honouring that literally would render
    /// an invisible composer on the frame the founder first sees.
    func testAnUnmeasuredFieldStillHasAVisibleHeight() {
        XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: 0), ComposerMetrics.minTextHeight)
        XCTAssertGreaterThan(ComposerMetrics.minTextHeight, 0)
    }

    /// A short draft sizes to its own content — the composer must not reserve six lines of
    /// empty space for a one-line question.
    func testAShortDraftSizesToItsContent() {
        let oneAndAHalfLines: CGFloat = 40
        XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: oneAndAHalfLines), oneAndAHalfLines)
    }

    /// The reported case: a pasted email, far taller than the cap. The field stops growing —
    /// that part always worked — and the assertion that matters is that it is now scrollable.
    func testAPastedEmailIsCappedAndScrolls() {
        let pastedEmail: CGFloat = 900
        XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: pastedEmail),
                       ComposerMetrics.maxTextHeight)
        XCTAssertTrue(ComposerMetrics.scrolls(contentHeight: pastedEmail))
    }

    /// The cap is deliberately the height the old `lineLimit(1...6)` settled at: the composer
    /// sits above the transcript in a 380pt dock, and growing it further would take the
    /// conversation's space to solve something scrolling solves for free.
    func testTheCapIsUnchangedFromTheSixLineField() {
        XCTAssertEqual(ComposerMetrics.maxTextHeight, 132)
    }

    /// A one-line composer that shows a scrollbar or rubber-bands reads as broken, so every
    /// scrolling affordance keys off this and it must be false right up to the cap.
    func testNothingScrollsUntilTheContentActuallyOverflows() {
        XCTAssertFalse(ComposerMetrics.scrolls(contentHeight: 0))
        XCTAssertFalse(ComposerMetrics.scrolls(contentHeight: ComposerMetrics.minTextHeight))
        XCTAssertFalse(ComposerMetrics.scrolls(contentHeight: ComposerMetrics.maxTextHeight),
                       "exactly full is not overflowing")
        XCTAssertTrue(ComposerMetrics.scrolls(contentHeight: ComposerMetrics.maxTextHeight + 1))
    }

    /// The height is monotonic in the content: growing a draft may never shrink the field.
    /// A non-monotonic clamp would make the composer jitter as the founder types.
    func testTheFieldNeverShrinksAsTheDraftGrows() {
        var previous: CGFloat = 0
        for h in stride(from: CGFloat(0), through: 400, by: 7) {
            let height = ComposerMetrics.fieldHeight(forContent: h)
            XCTAssertGreaterThanOrEqual(height, previous, "shrank at content height \(h)")
            XCTAssertLessThanOrEqual(height, ComposerMetrics.maxTextHeight)
            previous = height
        }
    }

    // MARK: - The reflection panel shares the field, not the cap

    /// `SessionChatPanel` had the identical defect with different styling (pixel font, its own
    /// padding, an 8-line limit). It now shares `ComposerField` — but not its height, because
    /// the two surfaces sit above different things and neither cap should follow the other.
    func testTheReflectionCapIsHonouredAndIsItsOwnNumber() {
        let cap = ComposerMetrics.reflectionMaxTextHeight
        XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: 900, cap: cap), cap)
        XCTAssertEqual(cap, 120, "~8 lines of the 12pt pixel font, matching the old lineLimit(1...8)")
        XCTAssertNotEqual(cap, ComposerMetrics.maxTextHeight)
    }

    /// Every rule holds under the second cap too — a caller passing its own height must not
    /// lose the floor, the clamp, or the overflow test.
    func testTheClampBehavesIdenticallyUnderAnyCap() {
        for cap in [ComposerMetrics.maxTextHeight, ComposerMetrics.reflectionMaxTextHeight, 60] {
            XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: 0, cap: cap),
                           ComposerMetrics.minTextHeight, "lost the floor at cap \(cap)")
            XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: cap + 500, cap: cap), cap)
            XCTAssertFalse(ComposerMetrics.scrolls(contentHeight: cap, cap: cap))
            XCTAssertTrue(ComposerMetrics.scrolls(contentHeight: cap + 1, cap: cap))
        }
    }

    /// The default cap is the chat composer's, so the existing call site and these tests keep
    /// meaning what they did before the parameter existed.
    func testTheDefaultCapIsTheChatComposers() {
        XCTAssertEqual(ComposerMetrics.fieldHeight(forContent: 900),
                       ComposerMetrics.fieldHeight(forContent: 900, cap: ComposerMetrics.maxTextHeight))
        XCTAssertEqual(ComposerMetrics.scrolls(contentHeight: 140),
                       ComposerMetrics.scrolls(contentHeight: 140, cap: ComposerMetrics.maxTextHeight))
    }
}
