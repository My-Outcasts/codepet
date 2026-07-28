// codepetTests/OnboardingMotionTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// The motion layer is a 1:1 port of the web's keyframes, so these lock the timings
/// against the stylesheet. If someone retunes a duration here, it should be a
/// deliberate divergence from `app.css`, not a drift nobody noticed.
final class OnboardingMotionTests: XCTestCase {

    // MARK: riseIn timings — `.splash-*`, `.ob-cold-in > *`, `.ob-body > *`

    func testRiseDurationsMatchTheWeb() {
        XCTAssertEqual(OnboardingMotion.riseSplash, 0.9)   // .splash-title/-btn/-hint
        XCTAssertEqual(OnboardingMotion.riseWord, 0.7)     // .splash-sub .w
        XCTAssertEqual(OnboardingMotion.riseCold, 0.85)    // .ob-cold-in > *
        XCTAssertEqual(OnboardingMotion.riseStep, 0.55)    // .ob-body > *
    }

    func testEntranceDelaysMatchTheWeb() {
        XCTAssertEqual(OnboardingMotion.splashTitleDelay, 0.15)
        XCTAssertEqual(OnboardingMotion.splashButtonDelay, 0.48)
        XCTAssertEqual(OnboardingMotion.splashHintDelay, 0.66)
        XCTAssertEqual(OnboardingMotion.coldHeadlineDelay, 0.10)
        XCTAssertEqual(OnboardingMotion.coldParagraphDelay, 0.24)
        XCTAssertEqual(OnboardingMotion.coldChipsDelay, 0.50)
        XCTAssertEqual(OnboardingMotion.stepHeadingDelay, 0.04)
        XCTAssertEqual(OnboardingMotion.stepSubDelay, 0.12)
        XCTAssertEqual(OnboardingMotion.stepRestDelay, 0.20)
    }

    /// `.splash-sub .w { animation-delay: calc(.32s + var(--i) * 60ms) }`
    func testPerWordDelayIsBaseThenSixtyMsSteps() {
        XCTAssertEqual(OnboardingMotion.wordDelay(0), 0.32, accuracy: 0.0001)
        XCTAssertEqual(OnboardingMotion.wordDelay(1), 0.38, accuracy: 0.0001)
        XCTAssertEqual(OnboardingMotion.wordDelay(5), 0.62, accuracy: 0.0001)
    }

    func testPerWordDelayIsStrictlyIncreasing() {
        for i in 0..<20 {
            XCTAssertLessThan(OnboardingMotion.wordDelay(i), OnboardingMotion.wordDelay(i + 1))
        }
    }

    /// The whole splash entrance should be over in about a second — a stagger that
    /// outlasts the screen would just read as jank.
    func testSplashEntranceSettlesQuickly() {
        let lastWord = OnboardingMotion.wordDelay(7) + OnboardingMotion.riseWord
        let lastChrome = OnboardingMotion.splashHintDelay + OnboardingMotion.riseSplash
        XCTAssertLessThan(max(lastWord, lastChrome), 1.75)
    }

    // MARK: Ken Burns — `@keyframes kenburns`

    func testKenBurnsPeriodsAndScale() {
        XCTAssertEqual(OnboardingMotion.kenBurnsSplash, 30)  // .splash:before
        XCTAssertEqual(OnboardingMotion.kenBurnsCold, 32)    // .ob-cold:after
        XCTAssertEqual(OnboardingMotion.kenBurnsScale, 1.08)
    }

    /// `translate(-1.2%, -1.6%)` of the layer's own size — up and to the left.
    func testKenBurnsDriftIsProportionalAndNegative() {
        let d = OnboardingMotion.kenBurnsDrift(width: 1000, height: 500)
        XCTAssertEqual(d.width, -12, accuracy: 0.001)
        XCTAssertEqual(d.height, -8, accuracy: 0.001)

        let big = OnboardingMotion.kenBurnsDrift(width: 2560, height: 1440)
        XCTAssertEqual(big.width, -30.72, accuracy: 0.001)
        XCTAssertEqual(big.height, -23.04, accuracy: 0.001)
    }

    func testKenBurnsDriftScalesWithTheLayer() {
        let small = OnboardingMotion.kenBurnsDrift(width: 800, height: 600)
        let large = OnboardingMotion.kenBurnsDrift(width: 1600, height: 1200)
        XCTAssertEqual(large.width, small.width * 2, accuracy: 0.001)
        XCTAssertEqual(large.height, small.height * 2, accuracy: 0.001)
    }

    // MARK: titleSweep — `@keyframes titleSweep` over 4.6s, crossing in the first 55%

    func testSweepCrossPlusHoldIsTheFullCycle() {
        XCTAssertEqual(OnboardingMotion.sweepCross + OnboardingMotion.sweepHold, 4.6, accuracy: 0.01)
    }

    func testSweepCrossesInFiftyFivePercentOfTheCycle() {
        let cycle = OnboardingMotion.sweepCross + OnboardingMotion.sweepHold
        XCTAssertEqual(OnboardingMotion.sweepCross / cycle, 0.55, accuracy: 0.005)
    }

    func testSweepTravelsFullyOffBothEdges() {
        // ±120% so the bar is never parked visibly on the glyphs.
        XCTAssertLessThanOrEqual(OnboardingMotion.sweepFrom, -1.0)
        XCTAssertGreaterThanOrEqual(OnboardingMotion.sweepTo, 1.0)
    }

    // MARK: looping accents

    func testHintPulseRange() {
        XCTAssertEqual(OnboardingMotion.hintPeriod, 2.8)
        XCTAssertEqual(OnboardingMotion.hintOpacityLow, 0.42)
        XCTAssertEqual(OnboardingMotion.hintOpacityHigh, 0.72)
        XCTAssertLessThan(OnboardingMotion.hintOpacityLow, OnboardingMotion.hintOpacityHigh)
    }

    func testTitleGlowRangeGrowsAndStaysSubtle() {
        XCTAssertEqual(OnboardingMotion.glowPeriod, 5)
        XCTAssertLessThan(OnboardingMotion.glowRadiusLow, OnboardingMotion.glowRadiusHigh)
        XCTAssertLessThan(OnboardingMotion.glowOpacityLow, OnboardingMotion.glowOpacityHigh)
        XCTAssertLessThanOrEqual(OnboardingMotion.glowOpacityHigh, 1.0)
    }

    // MARK: art panel — `.ob-art span { transition: opacity 1.1s, transform 7s }`

    func testArtCrossfadeIsMuchFasterThanTheScaleSettle() {
        XCTAssertEqual(OnboardingMotion.artCrossfade, 1.1)
        XCTAssertEqual(OnboardingMotion.artSettle, 7)
        // The image must be fully opaque long before it finishes settling, otherwise
        // the drift reads as a load glitch rather than a slow push-in.
        XCTAssertLessThan(OnboardingMotion.artCrossfade, OnboardingMotion.artSettle / 3)
    }

    func testArtEnterScaleOverscansSoNoEdgeShowsDuringTheSettle() {
        XCTAssertEqual(OnboardingMotion.artEnterScale, 1.07)
        // Must be > 1, or the layer would settle outward and reveal the panel edge.
        XCTAssertGreaterThan(OnboardingMotion.artEnterScale, 1.0)
    }
}
