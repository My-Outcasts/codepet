// codepetTests/CompanyDataSaveTests.swift
import XCTest
@testable import codepet

final class CompanyDataSaveTests: XCTestCase {
    func testStateMapsOnboardedAtISOString() {
        let iso = "2026-07-20T10:00:00Z"
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(projectName: "Codepet"),
                                                   stage: "building", companionId: "nova", onboardedAt: iso))
        XCTAssertNotNil(s.onboardedAt)
        XCTAssertNil(CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil, onboardedAt: nil)).onboardedAt)
    }
    func testBriefPayloadHasBriefDictAndOnboardedAt() {
        let payload = CompanyData.briefPayload(CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"),
                                               onboardedAt: "2026-07-20T10:00:00Z")
        XCTAssertEqual(payload["onboardedAt"] as? String, "2026-07-20T10:00:00Z")
        let brief = payload["brief"] as? [String: Any]
        XCTAssertEqual(brief?["projectName"] as? String, "Codepet")
        XCTAssertEqual(brief?["oneLiner"] as? String, "a recap tool")
    }
}
