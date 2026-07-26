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
    func testDecisionsPayloadEncodesAndDocDecodes() throws {
        let decisions = [DecisionEntry(topic: "pricing", statement: "$4/mo", source: "Pricing", updatedAt: 5)]
        let payload = CompanyData.decisionsPayload(decisions)
        let arr = payload["decisions"] as? [[String: Any]]
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["topic"] as? String, "pricing")
    }
    func testStateFromDocNormalizesDecisions() {
        let doc = CompanyDoc(decisions: [DecisionEntry(topic: " ", statement: "x", source: nil, updatedAt: nil),
                                         DecisionEntry(topic: "tech", statement: "SwiftUI", source: nil, updatedAt: nil)])
        XCTAssertEqual(CompanyData.state(from: doc).decisions.map { $0.topic }, ["tech"])
    }
}
