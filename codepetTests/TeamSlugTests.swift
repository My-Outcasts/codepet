// codepetTests/TeamSlugTests.swift
import XCTest
@testable import codepet

/// Build 12 (8 Oct): Team build doc files came out as `…privacy-checklis.md` and
/// `…vietnamese-firs.md`, because the slug was cut at exactly 40 characters, mid-word.
/// Mirrors `teamSlug` in functions/src/planTeamWorkCore.ts — keep the two in step.
final class TeamSlugTests: XCTestCase {
    func testLongTitleEndsOnAWholeWord() {
        let s = TeamSlug.make("Lockerly launch email and privacy checklist for tenants")
        XCTAssertLessThanOrEqual(s.count, 40)
        XCTAssertEqual(s, "lockerly-launch-email-and-privacy")
    }

    func testCutThatLandsOnAWordBoundaryKeepsTheWord() {
        // exactly 40 chars of whole words, then more
        let s = TeamSlug.make("abcdefghij abcdefghij abcdefghij abcdefg more words")
        XCTAssertEqual(s, "abcdefghij-abcdefghij-abcdefghij-abcdefg")
    }

    func testOneUnbrokenWordStillCapsAt40() {
        XCTAssertEqual(TeamSlug.make(String(repeating: "a", count: 60)), String(repeating: "a", count: 40))
    }

    func testShortTitlesAndFallbackUnchanged() {
        XCTAssertEqual(TeamSlug.make("Bán quần văn phòng!"), "ban-quan-van-phong")
        XCTAssertEqual(TeamSlug.make("🚀🚀"), "project")
    }

    func testIdempotentSoAPlanSlugSurvivesMakeFolder() {
        let once = TeamSlug.make("Lockerly launch email and privacy checklist for tenants")
        XCTAssertEqual(TeamSlug.make(once), once)
    }
}
