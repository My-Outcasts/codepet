// codepetTests/EnvironmentPlannedTests.swift
import XCTest
@testable import codepet

/// Environment, 6 Oct design pass (mock approved): Browse all lists only what a founder can use
/// today. The unbuilt items — nine "Not built yet" rows on a new company — fold into one
/// "Coming later" line, with the list one click away.
final class EnvironmentPlannedTests: XCTestCase {
    func testItemsSplitIntoAvailableAndPlanned() {
        let built: Set<String> = ["web-research", "prd-writer"]
        let all = Toolkit.catalog
        let split = ToolkitPlanned.split(all, builtSkills: built)
        XCTAssertEqual(split.available.count + split.planned.count, all.count, "nothing lost")
        XCTAssertTrue(split.available.allSatisfy { $0.isBuilt(builtSkills: built) })
        XCTAssertTrue(split.planned.allSatisfy { !$0.isBuilt(builtSkills: built) })
        XCTAssertFalse(split.planned.isEmpty, "precondition: the catalog has planned items")
    }

    func testTheComingLaterLineNamesTheFirstFewAndCountsTheRest() {
        XCTAssertNil(ToolkitPlanned.comingLater([], lang: .en))
        XCTAssertEqual(ToolkitPlanned.comingLater(["Notion", "Figma"], lang: .en), "Coming later: Notion and Figma.")
        XCTAssertEqual(ToolkitPlanned.comingLater(["Notion", "Figma", "Slack", "Changelog", "Explorer"], lang: .en),
                       "Coming later: Notion, Figma, Slack and 2 more.")
        XCTAssertEqual(ToolkitPlanned.comingLater(["Notion"], lang: .vi), "Sắp có: Notion.")
    }
}
