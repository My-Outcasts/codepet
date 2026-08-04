// codepetTests/CompanionRowTests.swift
import XCTest
@testable import codepet

final class CompanionRowTests: XCTestCase {
    func test_summaryNamesTheCurrentCompanion() {
        XCTAssertEqual(CompanionRowModel.summary(companionId: "crash", lang: .en), "Crash")
    }

    func test_unknownIdFallsBackRatherThanShowingRaw() {
        XCTAssertEqual(CompanionRowModel.summary(companionId: "nope", lang: .en), "Default")
        XCTAssertEqual(CompanionRowModel.summary(companionId: "", lang: .vi), "Mặc định")
    }

    func test_allFollowsCanonicalNarrativeOrder() {
        let allIds = CompanionRowModel.all.map(\.id)
        XCTAssertEqual(Array(allIds.prefix(PetCharacter.starters.count)), PetCharacter.starters,
                       "Companion list must start with canonical order (PetCharacter.starters), not alphabetical")
    }
}
