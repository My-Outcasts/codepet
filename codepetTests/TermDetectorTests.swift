import XCTest
@testable import codepet

final class TermDetectorTests: XCTestCase {

    private let day1 = "2026-06-20T10:00:00Z"
    private let day2 = "2026-06-21T10:00:00Z"
    private let day3 = "2026-06-22T10:00:00Z"

    // MARK: - Matching

    func testWordContainsRespectsBoundaries() {
        XCTAssertTrue(TermDetector.wordContains("rest api endpoint", "api"))
        XCTAssertFalse(TermDetector.wordContains("this is rapid growth", "api"))
    }

    func testWordContainsMatchesPunctuationPatterns() {
        XCTAssertTrue(TermDetector.wordContains("loaded from .env file", ".env"))
        XCTAssertTrue(TermDetector.wordContains("uses async/await here", "async/await"))
    }

    // MARK: - Evolution

    func testAuthoredOccurrenceIsUsed() {
        let events = [
            CodeEvent(isoTime: day3, text: "added Google sign-in with OAuth", path: "/p/LoginView.swift", cwd: "/p")
        ]
        let term = TermDetector.detect(events: events).first { $0.canonical == "OAuth" }
        XCTAssertEqual(term?.evolution, "used")
        XCTAssertEqual(term?.occurrences.first?.file, "LoginView.swift")
    }

    func testMentionOnlyIsEncountered() {
        let events = [
            CodeEvent(isoTime: day3, text: "we should add a webhook later", path: "", cwd: "/p")
        ]
        let term = TermDetector.detect(events: events).first { $0.canonical == "webhook" }
        XCTAssertEqual(term?.evolution, "encountered")
        XCTAssertTrue(term?.occurrences.first?.file.isEmpty ?? false)
    }

    func testRepeatedAcrossFilesIsMastered() {
        let events = [
            CodeEvent(isoTime: day1, text: "async let x", path: "/p/A.swift", cwd: "/p"),
            CodeEvent(isoTime: day2, text: "await async call", path: "/p/B.swift", cwd: "/p"),
            CodeEvent(isoTime: day3, text: "another async tweak", path: "/p/A.swift", cwd: "/p"),
        ]
        let term = TermDetector.detect(events: events).first { $0.canonical == "async / await" }
        XCTAssertEqual(term?.evolution, "mastered")
    }

    // MARK: - De-duplication & limits

    func testSameFileSameDayCountsOnce() {
        let events = [
            CodeEvent(isoTime: day3, text: "async edit 1", path: "/p/A.swift", cwd: "/p"),
            CodeEvent(isoTime: day3, text: "async edit 2", path: "/p/A.swift", cwd: "/p"),
        ]
        let term = TermDetector.detect(events: events).first { $0.canonical == "async / await" }
        XCTAssertEqual(term?.count, 1)
    }

    func testRespectsMaxTerms() {
        let events = [
            CodeEvent(isoTime: day1, text: "swiftui firebase oauth async git", path: "/p/A.swift", cwd: "/p")
        ]
        XCTAssertLessThanOrEqual(TermDetector.detect(events: events, maxTerms: 2).count, 2)
    }

    // MARK: - Slug parity with the server

    func testSlugMatchesServerScheme() {
        XCTAssertEqual(DictionaryEntry.slug("async / await"), "async-await")
        XCTAssertEqual(DictionaryEntry.slug(".env"), "env")
        XCTAssertEqual(DictionaryEntry.slug("OAuth"), "oauth")
    }
}
