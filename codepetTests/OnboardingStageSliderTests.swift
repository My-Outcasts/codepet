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
