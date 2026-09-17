// codepetTests/OnboardingStageSliderTests.swift
import XCTest
@testable import codepet

final class OnboardingStageSliderTests: XCTestCase {
    func testMapsXToNearestStageAndClamps() {
        // width 500, 6 stages ⇒ segment 100pt; snap to nearest index.
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 0, width: 500, count: 6), 0)
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 500, width: 500, count: 6), 5)
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 240, width: 500, count: 6), 2) // 0.48*5=2.4→2
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 260, width: 500, count: 6), 3) // 0.52*5=2.6→3
        XCTAssertEqual(StageSliderMath.stageIndex(atX: -50, width: 500, count: 6), 0) // clamp low
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 999, width: 500, count: 6), 5) // clamp high
    }
    func testZeroWidthIsSafe() {
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 10, width: 0, count: 6), 0)
    }

    // MARK: - Tick geometry (the label-alignment fix)

    /// The stage ticks, and therefore the labels that name them, are laid out across
    /// `width - inset * 2` starting `inset` in. Hand-traced at 1100pt: w = 1070, spacing 214.
    func testTickXIsInsetTrackGeometry() {
        let expected: [CGFloat] = [15, 229, 443, 657, 871, 1085]
        for (i, x) in expected.enumerated() {
            XCTAssertEqual(StageSliderMath.tickX(stage: i, width: 1100, count: 6), x,
                           accuracy: 0.001, "stage \(i)")
        }
    }

    /// The bug this replaced: labels were distributed in six equal cells across the FULL
    /// width, which is a DIFFERENT geometry — not a rounding difference. At 1100pt the
    /// interior labels sat 46pt and 15pt away from the tick they name, outward from the
    /// centre in both directions, so "Launched" pointed at nearly the wrong stage.
    ///
    /// This pins the gap rather than the fix, so it stays meaningful if the layout is
    /// rewritten again: whatever else changes, an even full-width distribution is wrong.
    func testEvenFullWidthDistributionIsNotTheTickGeometry() {
        let width: CGFloat = 1100
        let cell = width / 6
        let evenCentre = { (i: Int) in cell * (CGFloat(i) + 0.5) }
        let drift = { (i: Int) in
            evenCentre(i) - StageSliderMath.tickX(stage: i, width: width, count: 6)
        }
        XCTAssertEqual(drift(1), 46, accuracy: 0.01)
        XCTAssertEqual(drift(2), 15.33, accuracy: 0.01)
        XCTAssertEqual(drift(3), -15.33, accuracy: 0.01)
        XCTAssertEqual(drift(4), -46, accuracy: 0.01)
    }

    /// Ticks and labels read the same inset from one place. A second literal is how they
    /// drifted apart the first time.
    func testTrackInsetIsSharedNotRewritten() {
        XCTAssertEqual(StageSliderMath.tickX(stage: 0, width: 800, count: 6),
                       StageSliderMath.trackInset, accuracy: 0.001)
        XCTAssertEqual(StageSliderMath.tickX(stage: 5, width: 800, count: 6),
                       800 - StageSliderMath.trackInset, accuracy: 0.001)
    }

    /// A width narrower than the two insets is the case that can go negative — `stage: 0`
    /// would return the inset whatever the width, so it proves nothing on its own.
    func testTickXDegenerateInputsAreSafe() {
        XCTAssertEqual(StageSliderMath.tickX(stage: 5, width: 0, count: 6),
                       StageSliderMath.trackInset, accuracy: 0.001)
        XCTAssertEqual(StageSliderMath.tickX(stage: 5, width: 20, count: 6),
                       StageSliderMath.trackInset, accuracy: 0.001,
                       "width < inset * 2 must clamp, never place a tick left of the track")
        XCTAssertEqual(StageSliderMath.tickX(stage: 0, width: 500, count: 1),
                       StageSliderMath.trackInset, accuracy: 0.001)
    }
}
