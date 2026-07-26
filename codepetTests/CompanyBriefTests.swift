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

    func testGoalTractionProblemRoundTrip() throws {
        let brief = CompanyBrief(goal: "Ship v1", traction: "40 on waitlist", problem: "Recaps are manual")
        let data = try JSONEncoder().encode(brief)
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: data)
        XCTAssertEqual(decoded, brief)
    }

    func testOldDocDecodesNewFieldsToNil() throws {
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.goal)
        XCTAssertNil(decoded.traction)
        XCTAssertNil(decoded.problem)
    }

    func testHasAnySignal_goalOnlyIsTrue() { XCTAssertTrue(CompanyBrief(goal: "Ship v1").hasAnySignal) }
    func testHasAnySignal_tractionOnlyIsTrue() { XCTAssertTrue(CompanyBrief(traction: "40 users").hasAnySignal) }
    func testHasAnySignal_problemOnlyIsTrue() { XCTAssertTrue(CompanyBrief(problem: "Manual recaps").hasAnySignal) }
    func testHasAnySignal_blankGoalIsFalse() { XCTAssertFalse(CompanyBrief(goal: "  ").hasAnySignal) }
}
