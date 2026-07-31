// codepetTests/OnboardingContentTests.swift
import XCTest
@testable import codepet

final class OnboardingContentTests: XCTestCase {
    func testCountsAndKeyValues() {
        XCTAssertEqual(OnboardingContent.roles.count, 8)
        XCTAssertEqual(OnboardingContent.roles.first?.key, "founder")
        XCTAssertEqual(OnboardingContent.tech.count, 3)
        XCTAssertEqual(OnboardingContent.stages.count, 6)
        XCTAssertEqual(OnboardingContent.stageNotes.count, OnboardingContent.stages.count)
        XCTAssertEqual(OnboardingContent.stages[2], "Private beta")
        XCTAssertEqual(OnboardingContent.defaultStageIndex, 2)
        XCTAssertEqual(OnboardingContent.categories.count, 8)
        XCTAssertEqual(OnboardingContent.departments.count, 8)
        XCTAssertEqual(OnboardingContent.departments.first?.name, "Engineering")
        XCTAssertEqual(OnboardingContent.analysisLines.count, 4)
        // 8, not the web's 9 — the companion-picker step is cut (see OnboardingView).
        XCTAssertEqual(OnboardingContent.total, 8)
        // step art covers steps 0...7 (8 entries)
        XCTAssertEqual(OnboardingContent.stepArt.count, 8)
        XCTAssertEqual(OnboardingContent.stepArt[0], "ob-team")
        XCTAssertEqual(OnboardingContent.stepArt[6], "ob-boardroom")
    }

    /// The art and grade arrays are indexed by step, so a mismatch would either crash
    /// or silently clamp the last screens onto the wrong image — which is exactly what
    /// a step removal is prone to leaving behind.
    func testStepArtAndGradeCoverEveryStepExactly() {
        XCTAssertEqual(OnboardingContent.stepArt.count, OnboardingContent.total)
        XCTAssertEqual(OnboardingContent.stepGrade.count, OnboardingContent.total)
    }

    /// The reveal (step 7) is now the last screen, so its footer must read "Step 8 of 8"
    /// — no dangling step beyond the finish button.
    func testTheLastStepIsTheReveal() {
        let lastStepIndex = OnboardingContent.total - 1
        XCTAssertEqual(lastStepIndex, 7)
        XCTAssertEqual(OnboardingContent.stepArt[lastStepIndex], "ob-team")
    }
}
