// codepetTests/PrimaryTextInversionTests.swift
import XCTest
import SwiftUI
import AppKit
@testable import codepet

/// `CodepetTheme.primaryText` must INVERT between appearances — near-black in light,
/// near-cream in dark. Anything that fills with it and draws on top has to flip its own
/// ink to match; hardcode `.white` on such a surface and the content vanishes in one of
/// the two themes.
///
/// This survives from `TopNavUpgradeContrastTests`, which rendered the top-nav Upgrade
/// pill offscreen and read its pixels. That pill was removed on Aug 5 (upgrading moved
/// into the account menu), so the two pixel tests went with it — but the token invariant
/// they rested on is still load-bearing for every inverted surface, so it stays.
final class PrimaryTextInversionTests: XCTestCase {

    private func luminance(_ color: Color, _ appearance: NSAppearance.Name) -> Double {
        var lum = 0.0
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            if let c = NSColor(color).usingColorSpace(.sRGB) {
                lum = 0.2126 * Double(c.redComponent)
                    + 0.7152 * Double(c.greenComponent)
                    + 0.0722 * Double(c.blueComponent)
            }
        }
        return lum
    }

    func testPrimaryTextFlipsBetweenAppearances() {
        XCTAssertLessThan(luminance(CodepetTheme.primaryText, .aqua), 0.2,
                          "primaryText should be near-black in light mode")
        XCTAssertGreaterThan(luminance(CodepetTheme.primaryText, .darkAqua), 0.8,
                             "primaryText should be near-cream in dark mode")
    }

    /// The page behind it inverts the other way, so the two never collapse together.
    func testPageInvertsOppositeToPrimaryText() {
        let lightGap = abs(luminance(CodepetTheme.primaryText, .aqua) - luminance(CodepetTokens.page, .aqua))
        let darkGap  = abs(luminance(CodepetTheme.primaryText, .darkAqua) - luminance(CodepetTokens.page, .darkAqua))
        XCTAssertGreaterThan(lightGap, 0.6, "ink and page are too close in light mode")
        XCTAssertGreaterThan(darkGap, 0.6, "ink and page are too close in dark mode")
    }
}
