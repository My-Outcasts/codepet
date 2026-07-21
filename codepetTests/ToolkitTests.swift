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
