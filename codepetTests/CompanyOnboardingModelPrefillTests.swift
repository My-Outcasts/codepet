// codepetTests/CompanyOnboardingModelPrefillTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyOnboardingModelPrefillTests: XCTestCase {
    func testPrefillMapsFieldsAndStage() {
        let m = CompanyOnboardingModel()
        m.prefill(from: CompanyBrief(founderName: "Mona", role: "Founder", stage: "Launched",
                                     projectName: "Codepet", oneLiner: "AI companion", audience: "devs"))
        XCTAssertEqual(m.founderName, "Mona")
        XCTAssertEqual(m.role, "Founder")
        XCTAssertEqual(m.projectName, "Codepet")
        XCTAssertEqual(m.oneLiner, "AI companion")
        XCTAssertEqual(m.audience, "devs")
        XCTAssertEqual(m.stageIndex, 4)   // "Launched" is index 4 in stages
    }
    func testPrefillEmptyBriefDefaults() {
        let m = CompanyOnboardingModel()
        m.prefill(from: CompanyBrief())
        XCTAssertEqual(m.founderName, "")
        XCTAssertEqual(m.stageIndex, 2)   // nil stage → default
    }
}
