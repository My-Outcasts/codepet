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
        // Eight steps, 0...7, ending on the reveal. The companion picker was
        // step 8 until 14 Aug; it asked a question with no consequence, and
        // Settings has carried the same picker since #98.
        XCTAssertEqual(OnboardingContent.total, 8)
        // One art entry per step. Fewer than `total` and the last step crashes
        // on the index; more and a step silently shows the wrong panel.
        XCTAssertEqual(OnboardingContent.stepArt.count, OnboardingContent.total)
        XCTAssertEqual(OnboardingContent.stepArt[0], "ob-team")
        XCTAssertEqual(OnboardingContent.stepArt[6], "ob-boardroom")
    }
}
