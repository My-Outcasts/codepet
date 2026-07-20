// codepetTests/CompanyBriefTests.swift
import XCTest
@testable import codepet

final class CompanyBriefTests: XCTestCase {
    func testRoundTripsThroughCodableWithOptionalFields() throws {
        let brief = CompanyBrief(
            founderName: "Mona", role: "Founder", projectName: "Codepet",
            oneLiner: "a recap tool", categories: ["macOS app"], audience: "developers"
        )
        let data = try JSONEncoder().encode(brief)
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: data)
        XCTAssertEqual(decoded, brief)
    }

    func testDecodesEmptyObjectToAllNils() throws {
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.projectName)
        XCTAssertNil(decoded.categories)
    }
}
