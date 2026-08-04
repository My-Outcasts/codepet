// codepetTests/ToolkitTests.swift
import XCTest
@testable import codepet

final class ToolkitTests: XCTestCase {
    func testCatalog13UniqueIds() {
        XCTAssertEqual(Toolkit.catalog.count, 13)
        XCTAssertEqual(Set(Toolkit.catalog.map(\.id)).count, 13)
    }
    func testDefaultsAndPartition() {
        XCTAssertEqual(Toolkit.defaultEnabledIds, ["prd-writer", "github", "explorer"])
        XCTAssertTrue(Toolkit.defaultEnabledIds.isSubset(of: Set(Toolkit.catalog.map(\.id))))
        let sum = ToolCategory.allCases.map { Toolkit.items(in: $0).count }.reduce(0, +)
        XCTAssertEqual(sum, 13)
    }
    func testEnabledSkillIdsReturnsOnlySkillsThatAreOn() {
        let on: Set<String> = ["prd-writer", "github", "explorer", "code-review"]
        let ids = Toolkit.enabledSkillIds(in: on)
        // github is a connector and explorer an agent — neither belongs in
        // `enabled_skills`, which is the skills channel only.
        XCTAssertEqual(ids, ["code-review", "prd-writer"])
    }
    func testEnabledSkillIdsIsSortedForAStablePayload() {
        // A Set has no order; an order that churns per turn would look like a
        // new cache prefix on every request.
        let ids = Toolkit.enabledSkillIds(in: Set(Toolkit.items(in: .skills).map(\.id)))
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(ids.count, Toolkit.items(in: .skills).count)
    }
    func testEnabledSkillIdsEmptyWhenNothingOn() {
        XCTAssertTrue(Toolkit.enabledSkillIds(in: []).isEmpty)
    }
    func testPrdWriterShipsOnByDefaultSoItWorksOutOfTheBox() {
        // It is one of the two skills the CF implements; defaultOn is what makes
        // a fresh account get real behaviour without hunting for a toggle.
        XCTAssertTrue(Toolkit.enabledSkillIds(in: Toolkit.defaultEnabledIds).contains("prd-writer"))
    }
    func testRecommendedNonEmptyAllHaveWhy() {
        XCTAssertFalse(Toolkit.recommended.isEmpty)
        XCTAssertTrue(Toolkit.recommended.allSatisfy { $0.why != nil })
    }
    func testCategoryLabelsBothLanguages() {
        for c in ToolCategory.allCases {
            for lang in [AppLanguage.en, .vi] {
                XCTAssertFalse(c.label(lang).isEmpty)
                XCTAssertFalse(c.enableVerb(lang).isEmpty)
                XCTAssertFalse(c.onLabel(lang).isEmpty)
            }
        }
    }
}
