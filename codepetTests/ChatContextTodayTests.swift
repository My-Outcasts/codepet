// codepetTests/ChatContextTodayTests.swift
import XCTest
@testable import codepet

/// 9 Oct: told "runway is 8 months" on 9 Oct 2026, Finance put the deadline at "June 2026".
/// Nothing in the Ask context said what today was, so every date the model computed floated.
final class ChatContextTodayTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testTheContextSaysWhatDayItIs() {
        let out = ChatContext.compose(brief: CompanyBrief(), tasks: [], today: day(2026, 10, 9))
        XCTAssertTrue(out.contains("Today is 2026-10-09 (October 2026)"), out)
    }

    /// First, so a clip of the context (CONTEXT_CAP) can never trim it away.
    func testTheDateLeadsTheContext() {
        let out = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [], today: day(2026, 10, 9))
        XCTAssertTrue(out.hasPrefix("Today is 2026-10-09"))
    }

    /// Callers that pass no date are unchanged.
    func testNoDateWhenNoneIsGiven() {
        XCTAssertFalse(ChatContext.compose(brief: CompanyBrief(), tasks: []).contains("Today is"))
    }
}
