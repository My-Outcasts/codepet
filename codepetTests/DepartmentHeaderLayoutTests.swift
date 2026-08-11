// codepetTests/DepartmentHeaderLayoutTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// The guard: `DepartmentDetailView`'s masthead must go through `viewHeadPadding()`,
/// which is `padding(.top, 32).padding(.horizontal, 26).pageColumn()`.
///
/// This page was the one surface in the company layer that had opted out — it never
/// called `pageColumn()`, so its hero ran the full width of the window while the
/// roster that links to it capped at 1280 and centred. Nothing went red when that
/// happened, which is what this suite fixes.
///
/// It measures rather than inspects: `ImageRenderer` at `scale = 1` (so one pixel is
/// one point) draws the header offscreen, and we scan left-to-right for the first
/// column holding any non-transparent pixel. That number IS the left content edge,
/// so the assertions cannot pass with the layout deleted.
///
/// Measured, Aug 11 (macOS 26.2): first drawn column 27 at a 1000pt window, 337 at
/// 1900pt. Both are one point right of the arithmetic (26 and 26 + (1900-1280)/2 = 336)
/// because the first glyph carries a point of left side bearing — hence the ±3
/// tolerance, which is far tighter than the 310pt difference under test.
@MainActor
final class DepartmentHeaderLayoutTests: XCTestCase {

    /// Half the window's overhang past the 1280 column, at a 1900pt window.
    private static let centringOffset = (1900 - CodepetTokens.pageColumnWidth) / 2  // 310

    /// Exactly what `DepartmentDetailView` renders: the masthead plus `viewHeadPadding()`.
    /// Plain values, no store, so nothing here touches Firebase.
    private func paddedHeader() -> some View {
        DepartmentHeader(name: "Engineering",
                         rationale: "Builds and ships the product.",
                         onBack: {})
            .environment(\.uiLanguage, .en)
            .viewHeadPadding()
    }

    /// The x of the leftmost pixel column that has anything drawn in it, and the
    /// rightmost, at the given window width. `nil` when the render produced nothing —
    /// reported rather than silently treated as a pass.
    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1  // one pixel == one point; otherwise we read backing-scale units
        guard let cg = renderer.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // The view is unbacked, so anything drawn is the only opacity in the buffer.
        // 8/255 rather than 0 so a stray antialiasing crumb cannot move the edge.
        var first: Int?, last: Int?
        for x in 0..<w {
            var drawn = false
            for y in 0..<h where pixels[(y * w + x) * 4 + 3] > 8 { drawn = true; break }
            if drawn {
                if first == nil { first = x }
                last = x
            }
        }
        guard let f = first, let l = last else { return nil }
        return (f, l)
    }

    /// Fails loudly if offscreen rendering ever stops producing a usable image — without
    /// this the edge assertions would have nothing to measure and could look green.
    func test_headerActuallyRendersSomething() throws {
        let extent = try XCTUnwrap(drawnExtent(paddedHeader(), width: 1000),
                                   "ImageRenderer produced no drawn pixels for DepartmentHeader")
        XCTAssertGreaterThan(extent.last - extent.first, 100,
                             "only \(extent.last - extent.first)pt of content drew — the masthead did not render")
    }

    /// Under the 1280 cap the column is the window, so content starts at the 26pt margin.
    func test_narrowWindow_contentStartsAtTheHorizontalMargin() throws {
        let extent = try XCTUnwrap(drawnExtent(paddedHeader(), width: 1000))
        XCTAssertEqual(Double(extent.first), 26, accuracy: 3,
                       "content starts at \(extent.first)pt, not the 26pt viewHeadPadding margin")
    }

    /// The assertion that matters. Over the cap the 1280 column is centred in the window,
    /// so the left edge moves right by (1900-1280)/2 = 310 and content starts at 336.
    /// Delete `pageColumn()` from `viewHeadPadding()` and this reads 26 instead; delete the
    /// 26pt margin and it reads 310.
    func test_wideWindow_columnIsCappedAndCentred() throws {
        let extent = try XCTUnwrap(drawnExtent(paddedHeader(), width: 1900))
        XCTAssertEqual(Double(extent.first), Self.centringOffset + 26, accuracy: 3,
                       "content starts at \(extent.first)pt — the 1280 column is not centred at a 1900pt window")
    }

    /// The same fact stated without glyph metrics in the way: widening the window past the
    /// cap must push the same content right by exactly half the overhang. An uncapped page
    /// would not move at all, so this one is exact rather than tolerant.
    func test_wideningPastTheCap_shiftsContentByHalfTheOverhang() throws {
        let narrow = try XCTUnwrap(drawnExtent(paddedHeader(), width: 1000))
        let wide = try XCTUnwrap(drawnExtent(paddedHeader(), width: 1900))
        XCTAssertEqual(wide.first - narrow.first, Int(Self.centringOffset),
                       "content moved \(wide.first - narrow.first)pt going 1000→1900; a centred 1280 column moves 310")
        XCTAssertEqual(wide.last - narrow.last, Int(Self.centringOffset),
                       "the right edge moved \(wide.last - narrow.last)pt — the column is not capped at 1280")
    }
}
