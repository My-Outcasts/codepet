// codepetTests/BriefContextTests.swift
import XCTest
@testable import codepet

final class BriefContextTests: XCTestCase {
    func testReturnsNilWithoutProductSignal() {
        XCTAssertNil(BriefContext.compose(nil))
        XCTAssertNil(BriefContext.compose(CompanyBrief(role: "founder")))
    }

    func testUsesOneLinerAndNotesWhenNotEnriched() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", oneLiner: "a recap tool", notes: "reads sessions")) ?? ""
        XCTAssertTrue(ctx.contains("a recap tool."))
        XCTAssertTrue(ctx.contains("reads sessions."))
    }

    func testSummaryReplacesOneLinerAndNotes() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", oneLiner: "a recap tool",
            summary: "A local-first macOS companion that recaps coding sessions.",
            notes: "reads sessions and builds a dictionary")) ?? ""
        XCTAssertTrue(ctx.contains("A local-first macOS companion that recaps coding sessions."))
        XCTAssertFalse(ctx.contains("a recap tool."))
        XCTAssertFalse(ctx.contains("reads sessions and builds a dictionary"))
    }

    func testIncludesCategoriesAndAudienceAlongsideSummary() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", summary: "A recap companion.",
            categories: ["macOS app", "dev tool"], audience: "AI-first developers")) ?? ""
        XCTAssertTrue(ctx.contains("macos app / dev tool"))
        XCTAssertTrue(ctx.contains("It's for AI-first developers."))
    }
}
