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
        XCTAssertEqual(OnboardingContent.total, 8)
        // step art covers steps 0...7 and every name resolves to an imageset base
        XCTAssertEqual(OnboardingContent.stepArt.count, 8)
        XCTAssertEqual(OnboardingContent.stepArt[0], "ob-team")
        XCTAssertEqual(OnboardingContent.stepArt[6], "ob-boardroom")
    }
}
