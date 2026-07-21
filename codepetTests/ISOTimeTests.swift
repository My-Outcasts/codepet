// codepetTests/ISOTimeTests.swift
import XCTest
@testable import codepet

final class ISOTimeTests: XCTestCase {
    func testUtcCanonicalFormat() {
        XCTAssertEqual(ISOTime.utc(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        // Ends in Z (UTC), no fractional seconds → lexicographic == chronological.
        let s = ISOTime.utc(Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertTrue(s.hasSuffix("Z"))
        XCTAssertFalse(s.contains("."))
    }
    func testLexicographicOrderMatchesTime() {
        let earlier = ISOTime.utc(Date(timeIntervalSince1970: 1000))
        let later = ISOTime.utc(Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(later > earlier)
    }
}
