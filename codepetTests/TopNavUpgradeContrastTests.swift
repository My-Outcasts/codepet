// codepetTests/TopNavUpgradeContrastTests.swift
import XCTest
import SwiftUI
import AppKit
@testable import codepet

/// The top-nav Upgrade pill is an INVERTED "ink" CTA: it fills with
/// `CodepetTheme.primaryText`, which flips near-black (light) → near-cream (dark).
/// A hardcoded white label therefore disappeared against the dark-mode pill.
///
/// These tests RENDER the real `UpgradePillLabel` offscreen under each appearance and
/// read its pixels, so they fail if the label color is ever hardcoded back to `.white`
/// — a token-only assertion would not catch that.
final class TopNavUpgradeContrastTests: XCTestCase {

    /// Render the pill under `appearance` and return the luminance of its darkest and
    /// lightest pixels — i.e. the pill fill and its label ink, in some order.
    @MainActor
    private func pillLuminanceRange(_ appearance: NSAppearance.Name) throws -> (min: Double, max: Double) {
        let nsAppearance = try XCTUnwrap(NSAppearance(named: appearance))
        let host = NSHostingView(rootView: UpgradePillLabel(title: "Upgrade"))
        host.appearance = nsAppearance
        host.frame = CGRect(origin: .zero, size: host.fittingSize)

        XCTAssertGreaterThan(host.frame.width, 20, "pill failed to lay out")
        XCTAssertGreaterThan(host.frame.height, 10, "pill failed to lay out")

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                               "could not allocate a bitmap for the pill")
        // `host.appearance` alone does NOT drive `Color.dyn` — those resolve against the
        // CURRENT DRAWING appearance, so the draw itself must happen inside this block or
        // every render silently comes out in light mode.
        nsAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }

        var lo = 1.0, hi = 0.0
        var counted = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // The capsule leaves the frame's corners TRANSPARENT. Those pixels read
                // as pure black and would masquerade as dark ink, hiding a white-on-cream
                // regression — so only fully opaque pixels (pill fill + glyph) count.
                guard c.alphaComponent > 0.99 else { continue }
                let lum = 0.2126 * Double(c.redComponent)
                        + 0.7152 * Double(c.greenComponent)
                        + 0.0722 * Double(c.blueComponent)
                lo = Swift.min(lo, lum)
                hi = Swift.max(hi, lum)
                counted += 1
            }
        }
        XCTAssertGreaterThan(counted, 500, "too few opaque pill pixels sampled to judge contrast")
        return (lo, hi)
    }

    @MainActor
    func testLabelIsReadableInLightMode() throws {
        let (lo, hi) = try pillLuminanceRange(.aqua)
        XCTAssertLessThan(lo, 0.2, "light-mode pill should fill near-black")
        XCTAssertGreaterThan(hi, 0.8, "light-mode label should be near-white")
        XCTAssertGreaterThan(hi - lo, 0.6, "Upgrade label is too close to its pill in light mode")
    }

    @MainActor
    func testLabelIsReadableInDarkMode() throws {
        let (lo, hi) = try pillLuminanceRange(.darkAqua)
        XCTAssertGreaterThan(hi, 0.8, "dark-mode pill should fill near-cream")
        XCTAssertLessThan(lo, 0.2, "dark-mode label should be near-black — a white one vanishes")
        XCTAssertGreaterThan(hi - lo, 0.6, "Upgrade label is too close to its pill in dark mode")
    }

    /// The pill fill is what flips between appearances; pin that too, so a change to
    /// `primaryText` that breaks the inversion is caught at its source.
    func testFillFlipsBetweenAppearances() {
        func luminance(_ color: Color, _ appearance: NSAppearance.Name) -> Double {
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
        XCTAssertLessThan(luminance(CodepetTheme.primaryText, .aqua), 0.2)
        XCTAssertGreaterThan(luminance(CodepetTheme.primaryText, .darkAqua), 0.8)
    }
}
