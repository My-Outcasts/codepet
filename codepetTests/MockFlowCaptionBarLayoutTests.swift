// codepetTests/MockFlowCaptionBarLayoutTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// Measures the walkthrough band offscreen.
///
/// I cannot screenshot the running app — Screen Recording is denied — so "does it
/// still cover the composer" is normally a handoff. Layout is not: `ImageRenderer`
/// lays a view out for real and reports the size it took, which is the only fact
/// this fix turns on. The band is mounted through `safeAreaInset`, and an inset
/// reserves exactly the height its content renders; a band that measured ~0 would
/// reserve nothing and be back to floating over the composer with no visible
/// difference from the version that was correct.
@MainActor
final class MockFlowCaptionBarLayoutTests: XCTestCase {

    private func height(_ view: some View, width: CGFloat = 900) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        return renderer.nsImage?.size.height ?? 0
    }

    /// The band has real height, so the inset moves the composer by a real amount.
    ///
    /// Measured idle: 89pt when a separate chapter-chips row sat above the transport
    /// (chips + transport + the 8pt `VStack` spacing between them); 60pt now that the
    /// chips row is gone and the chapter + position control folds into the transport
    /// capsule instead (measured with `ImageRenderer` the same way, not estimated —
    /// see the caption-bar report for the before/after numbers this drove). The floor
    /// moved down with it: it was 60 because that was comfortably below the old 89pt
    /// measurement, not because 60 is itself meaningful, and the real height sitting
    /// exactly ON the old floor doesn't prove the same thing the old floor proved. What
    /// this test actually guards is "not collapsed to ~0" — a safeAreaInset reserves
    /// only what its content renders, so a band that measured near-zero would go back
    /// to floating over the composer with no visible difference from the bug this test
    /// was written to catch. 30pt keeps that guard with margin under the new real
    /// height. With a caption it grows by the caption box; the ceiling below is what
    /// keeps that from eating the pane.
    func testTheBandReservesRealHeight() {
        let bar = MockFlowCaptionBar(player: MockFlowPlayer())
        let h = height(bar)
        XCTAssertGreaterThan(h, 30,
                             "the band measured \(h)pt — a safeAreaInset reserves what its "
                             + "content renders, so this would leave the transport sitting "
                             + "on top of the composer again")
        XCTAssertLessThan(h, 400, "the band is eating the conversation")
    }

    /// **It must not resize as the tour talks.** The caption is a floor-height slot
    /// rather than a view that appears and disappears, because an inset that grows
    /// and shrinks moves the composer under the founder's cursor on every beat.
    /// Rendering at two widths stands in for two caption lengths: the same text
    /// wraps differently, and the reserved height must not follow it below the floor.
    func testTheBandKeepsItsHeightWhenNothingIsPlaying() {
        let idle = MockFlowCaptionBar(player: MockFlowPlayer())
        let wide = height(idle, width: 1200)
        let narrow = height(idle, width: 760)
        XCTAssertEqual(wide, narrow, accuracy: 1,
                       "the band changes height with the window, so the composer would "
                       + "shift while the tour runs")
    }
}
#endif
