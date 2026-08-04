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
}
