// codepetTests/MeaningfulTextTests.swift
import XCTest
@testable import codepet

final class MeaningfulTextTests: XCTestCase {
    func testPassesThroughAndTrims() {
        XCTAssertEqual(MeaningfulText.clean("  Codepet  "), "Codepet")
        XCTAssertEqual(MeaningfulText.clean("Codepet"), "Codepet")
        XCTAssertEqual(MeaningfulText.clean("co"), "co")
    }

    func testRejectsEmptyAndBlank() {
        XCTAssertNil(MeaningfulText.clean(nil))
        XCTAssertNil(MeaningfulText.clean(""))
        XCTAssertNil(MeaningfulText.clean("   "))
    }

    func testRejectsSingleCharacter() {
        XCTAssertNil(MeaningfulText.clean("1"))
        XCTAssertNil(MeaningfulText.clean("a"))
    }

    func testRejectsAllDigits() {
        XCTAssertNil(MeaningfulText.clean("12"))
        XCTAssertNil(MeaningfulText.clean("2026"))
    }

    func testRejectsEmailAddresses() {
        XCTAssertNil(MeaningfulText.clean("mona@example.com"))
    }
}
