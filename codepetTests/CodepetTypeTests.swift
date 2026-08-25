// codepetTests/CodepetTypeTests.swift
import AppKit
import XCTest
@testable import codepet

/// Pins the type scale to macOS's OWN text styles, read from AppKit at runtime.
///
/// Asserted against the live metric rather than against numbers in a comment,
/// because the whole failure this fixes was numbers chosen by hand and written
/// down: Codepet's type came from the web app's px values, and every surface since
/// picked from the gaps between them. The two-mode shell reached thirteen distinct
/// sizes, four of them half-points sitting next to their own whole number.
final class CodepetTypeTests: XCTestCase {

    private func systemSize(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }

    func testEveryStepIsAMacOSTextStyle() {
        XCTAssertEqual(CodepetType.title1, systemSize(.title1))
        XCTAssertEqual(CodepetType.title2, systemSize(.title2))
        XCTAssertEqual(CodepetType.title3, systemSize(.title3))
        XCTAssertEqual(CodepetType.body, systemSize(.body))
        XCTAssertEqual(CodepetType.callout, systemSize(.callout))
        XCTAssertEqual(CodepetType.subheadline, systemSize(.subheadline))
        XCTAssertEqual(CodepetType.footnote, systemSize(.footnote))
    }

    /// `body` is also what a standard control's label is set at, `subheadline` what
    /// a small one is. A sidebar row or a push-button title belongs on one of those
    /// rather than between them.
    func testBodyAndSubheadlineMatchTheSystemControlSizes() {
        XCTAssertEqual(CodepetType.body, NSFont.systemFontSize)
        XCTAssertEqual(CodepetType.subheadline, NSFont.smallSystemFontSize)
    }

    /// macOS defines no text style below `footnote`, and 10 is `labelFontSize` —
    /// the floor for text a user is expected to read. The rail's count badge was at
    /// 9, which is `NSControl.ControlSize.mini`, a size for controls and not for
    /// numbers someone has to read across a sidebar.
    func testNothingIsBelowTheSystemLabelFloor() {
        XCTAssertEqual(CodepetType.footnote, NSFont.labelFontSize)
        for size in CodepetType.all {
            XCTAssertGreaterThanOrEqual(size, NSFont.labelFontSize,
                                        "\(size)pt is below every macOS text style")
        }
    }

    /// No half-points, and no two steps closer than a point. Both were true before:
    /// 10 sat beside 10.5, and 11 beside 11.5 — differences the eye reads as
    /// sloppiness rather than as hierarchy.
    func testTheScaleHasNoHalfPointsAndNoNearDuplicates() {
        for size in CodepetType.all {
            XCTAssertEqual(size, size.rounded(), "\(size) is a half-point step")
        }
        let sorted = CodepetType.all.sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 1, "\(a) and \(b) are indistinguishable")
        }
    }

    /// Seven steps, descending, no repeats — a scale, not a list.
    func testTheScaleIsOrderedAndDistinct() {
        XCTAssertEqual(CodepetType.all, CodepetType.all.sorted(by: >))
        XCTAssertEqual(Set(CodepetType.all).count, CodepetType.all.count)
    }
}
