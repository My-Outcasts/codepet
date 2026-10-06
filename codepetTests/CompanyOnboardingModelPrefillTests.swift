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
        XCTAssertEqual(m.stageIndex, 0)   // nil stage → "Just an idea" (CP-065)
    }

    /// Briefs saved under the wizard's old five-stage list still land on a real stage.
    /// Static on purpose: an instance crashes the 26.2 test host on dealloc (landmine 3).
    func testTheOldFiveStageValuesMapOntoOnboardingsStages() {
        func label(_ stage: String?) -> String {
            CompanyOnboardingModel.stages[CompanyOnboardingModel.stageIndex(for: stage)]
        }
        XCTAssertEqual(label("Idea"), "Just an idea")
        XCTAssertEqual(label("Building"), "Prototype")
        XCTAssertEqual(label("Private beta"), "Private beta")
        XCTAssertEqual(label("Growing"), "Growing")
        XCTAssertEqual(label(nil), "Just an idea")
        XCTAssertEqual(label("Scaling"), "Just an idea")
    }
}
