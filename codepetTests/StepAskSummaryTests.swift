// codepetTests/StepAskSummaryTests.swift
import XCTest
@testable import codepet

/// CP-035: step detail opened with the full ~380-word instruction sent to the department. It now
/// opens with the result, and the ask is summarised in a line or two; the full instruction is
/// behind a disclosure.
final class StepAskSummaryTests: XCTestCase {
    func testAShortInstructionIsShownWhole() {
        XCTAssertEqual(StepAskSummary.summary("Write 5 plain FAQ answers."), "Write 5 plain FAQ answers.")
    }

    /// The first sentences that fit, cut at a sentence end, never mid-word.
    func testALongInstructionStopsAtASentenceEnd() {
        let long = "Pull the real blocker list from the last two weeks of beta feedback. "
                 + "Group it by where people got stuck. " + String(repeating: "Include every detail you can find. ", count: 12)
        XCTAssertEqual(StepAskSummary.summary(long, limit: 120),
                       "Pull the real blocker list from the last two weeks of beta feedback. Group it by where people got stuck.")
        XCTAssertTrue(StepAskSummary.isShortened(long, limit: 120))
    }

    /// No sentence end inside the limit: cut at a word boundary and mark it.
    func testNoSentenceEndCutsAtAWord() {
        let run = String(repeating: "word ", count: 60)
        let s = StepAskSummary.summary(run, limit: 40)
        XCTAssertTrue(s.hasSuffix("…"))
        XCTAssertLessThanOrEqual(s.count, 41)
        XCTAssertFalse(s.dropLast().hasSuffix(" "), "no dangling space before the ellipsis")
    }

    /// Markdown in the instruction is stripped, so the summary reads as prose.
    func testMarkdownIsStripped() {
        XCTAssertEqual(StepAskSummary.summary("## Goal\n**Write** the FAQ answers."), "Goal\nWrite the FAQ answers.")
    }

    func testAShortInstructionIsNotMarkedShortened() {
        XCTAssertFalse(StepAskSummary.isShortened("Write 5 plain FAQ answers."))
    }
}
