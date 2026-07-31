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
}

/// The track is inset by half a thumb at each end (web `.sb-track { inset: 0 15px }`).
/// Drawing and hit-testing must share that span — if one uses the full width and the
/// other the inset track, the thumb drifts away from the cursor.
final class StageSliderInsetTests: XCTestCase {
    private let inset: CGFloat = 15
    private let count = 6

    func testTrackExcludesBothInsets() {
        XCTAssertEqual(StageSliderMath.trackWidth(container: 500, inset: inset), 470)
        XCTAssertEqual(StageSliderMath.trackWidth(container: 1000, inset: inset), 970)
    }

    func testTrackNeverCollapsesToZeroOnTinyContainers() {
        // Guards a divide-by-zero in the frac maths on a mid-resize layout pass.
        XCTAssertGreaterThan(StageSliderMath.trackWidth(container: 20, inset: inset), 0)
        XCTAssertGreaterThan(StageSliderMath.trackWidth(container: 0, inset: inset), 0)
    }

    func testEndpointsSitFullyInsideTheContainer() {
        let w: CGFloat = 500
        let first = StageSliderMath.centerX(forIndex: 0, container: w, inset: inset, count: count)
        let last = StageSliderMath.centerX(forIndex: count - 1, container: w, inset: inset, count: count)
        // A 26pt thumb centred here must not overhang either edge.
        XCTAssertGreaterThanOrEqual(first - 13, 0, "thumb clipped at the left edge")
        XCTAssertLessThanOrEqual(last + 13, w, "thumb clipped at the right edge")
    }

    func testDrawingAndHitTestingAgreeAtEveryStage() {
        for w in [CGFloat(400), 500, 900, 1400] {
            let track = StageSliderMath.trackWidth(container: w, inset: inset)
            for i in 0..<count {
                let x = StageSliderMath.centerX(forIndex: i, container: w, inset: inset, count: count)
                // The view hands the gesture `location.x - inset` against `track`.
                let hit = StageSliderMath.stageIndex(atX: x - inset, width: track, count: count)
                XCTAssertEqual(hit, i, "thumb at stage \(i) hit-tests as \(hit) at width \(w)")
            }
        }
    }

    func testSingleStageIsSafe() {
        XCTAssertEqual(StageSliderMath.centerX(forIndex: 0, container: 500, inset: inset, count: 1), inset)
    }
}
