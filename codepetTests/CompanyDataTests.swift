// codepetTests/CompanyDataTests.swift
import XCTest
@testable import codepet

final class CompanyDataTests: XCTestCase {
    func testCompanyDocRoundTripsCodable() throws {
        let doc = CompanyDoc(brief: CompanyBrief(projectName: "Codepet"), stage: "building", companionId: "nova")
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(CompanyDoc.self, from: data)
        XCTAssertEqual(back.brief?.projectName, "Codepet")
        XCTAssertEqual(back.stage, "building")
        XCTAssertEqual(back.companionId, "nova")
    }
    func testStateMappingFromDoc() {
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(projectName: "Codepet"), stage: "launch", companionId: "luna"))
        XCTAssertEqual(s.brief.projectName, "Codepet")
        XCTAssertEqual(s.stage, .launch)
        XCTAssertEqual(s.companionId, "luna")
    }
    func testEmptyOnNilDocAndUnknownStage() {
        XCTAssertEqual(CompanyData.state(from: nil), CompanyState.empty)
        let s = CompanyData.state(from: CompanyDoc(brief: nil, stage: "bogus", companionId: nil))
        XCTAssertEqual(s.stage, .idea)         // unknown stage → default
        XCTAssertEqual(s.companionId, "byte")  // nil companion → default
    }
}
