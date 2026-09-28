// codepetTests/MarkdownTableFitTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// Build 4, 28 Sep: "Codepet Unit Economics" showed only Component + Driver. The "Rate assumed"
/// and "Per session" columns — every $ value, the $0.132 total included — sat off to the right,
/// reachable only by a sideways trackpad scroll, with no scroll bar or fade to say they existed.
///
/// The table was ALWAYS in a horizontal `ScrollView` with each cell allowed 240pt, so a 4-column
/// table wanted ~1,000pt in a ~460pt sheet. It now narrows its cells until it fits, and scrolls
/// only when even the narrowest does not.
///
/// Measured through `ImageRenderer`, which draws a macOS scroll view's content as BLANK (the
/// reason `MarkdownTableView` is its own view). So ink in the table's right-hand quarter means the
/// last column was laid out inside the width — not parked behind a scroll.
@MainActor
final class MarkdownTableFitTests: XCTestCase {

    private let unitEconomics = """
    | Component | Driver | Rate assumed | Per session |
    |---|---|---:|---:|
    | Room convened | Four departments argue a decision | $0.050 per department | $0.110 |
    | Chat turns | Ordinary questions between rooms | $0.004 per turn | $0.022 |
    | **Total** | | | **$0.132** |
    """

    private func inkInRightQuarter(_ markdown: String, width: CGFloat) throws -> Bool {
        let renderer = ImageRenderer(content: MarkdownView(markdown: markdown)
            .frame(width: width)
            .padding(0)
            .background(Color.white))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for y in 0..<h {
            for x in (w * 3 / 4)..<w {
                let i = (y * w + x) * 4
                if px[i] < 160 && px[i + 1] < 160 && px[i + 2] < 160 { return true }
            }
        }
        return false
    }

    func testAFourColumnTableFitsTheSheetWidthInsteadOfScrolling() throws {
        XCTAssertTrue(try inkInRightQuarter(unitEconomics, width: 460),
                      "the $ columns were laid out off to the right, behind a sideways scroll")
    }
}
