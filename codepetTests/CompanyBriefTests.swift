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

    func testHasAnySignal_emptyBriefIsFalse() {
        XCTAssertFalse(CompanyBrief().hasAnySignal)
    }

    func testHasAnySignal_blankStringsAreFalse() {
        XCTAssertFalse(CompanyBrief(founderName: "  ", projectName: "\n").hasAnySignal)
    }

    func testHasAnySignal_emptyCategoriesIsFalse() {
        XCTAssertFalse(CompanyBrief(categories: []).hasAnySignal)
    }

    func testHasAnySignal_roleOnlyIsTrue() {
        XCTAssertTrue(CompanyBrief(role: "Founder").hasAnySignal)
    }

    func testHasAnySignal_stageOnlyIsTrue() {
        XCTAssertTrue(CompanyBrief(stage: "Idea").hasAnySignal)
    }

    func testHasAnySignal_categoriesIsTrue() {
        XCTAssertTrue(CompanyBrief(categories: ["SaaS"]).hasAnySignal)
    }

    func testHasAnySignal_projectNameIsTrue() {
        XCTAssertTrue(CompanyBrief(projectName: "Codepet").hasAnySignal)
    }
}
