import XCTest
@testable import codepet

final class EnrichInterviewTests: XCTestCase {
    func testNilBriefIsAllThreeGapsInOrder() {
        XCTAssertEqual(EnrichInterview.detectGaps(nil), [.goal, .traction, .problem])
    }
    func testEmptyBriefIsAllThreeGaps() {
        XCTAssertEqual(EnrichInterview.detectGaps(CompanyBrief()), [.goal, .traction, .problem])
    }
    func testFilledFieldsAreExcludedPreservingOrder() {
        let b = CompanyBrief(goal: "Ship v1", problem: "Manual recaps")
        XCTAssertEqual(EnrichInterview.detectGaps(b), [.traction])
    }
    func testBlankFieldCountsAsGap() {
        XCTAssertEqual(EnrichInterview.detectGaps(CompanyBrief(goal: "   ")), [.goal, .traction, .problem])
    }
    func testFullBriefHasNoGaps() {
        let b = CompanyBrief(goal: "a", traction: "b", problem: "c")
        XCTAssertTrue(EnrichInterview.detectGaps(b).isEmpty)
    }
    func testNeverMoreThanMaxQuestions() {
        XCTAssertLessThanOrEqual(EnrichInterview.detectGaps(CompanyBrief()).count, EnrichInterview.maxQuestions)
    }
    // MARK: - remainingGaps (relaunch, no in-memory cursor)

    func testRemainingGapsExcludesWhatTheTranscriptAlreadyAnswered() {
        // goal was answered (and saved), traction was SKIPPED — so the brief still
        // reads traction as empty, but it must not be asked again.
        let b = CompanyBrief(goal: "Ship v1")
        XCTAssertEqual(EnrichInterview.remainingGaps(b, answered: [.goal, .traction]), [.problem])
    }

    func testRemainingGapsMatchesDetectGapsWhenNothingAnswered() {
        XCTAssertEqual(EnrichInterview.remainingGaps(CompanyBrief(), answered: []),
                       EnrichInterview.detectGaps(CompanyBrief()))
    }

    func testRemainingGapsEmptyWhenEveryGapWasAskedAndSkipped() {
        XCTAssertTrue(EnrichInterview.remainingGaps(CompanyBrief(), answered: [.goal, .traction, .problem]).isEmpty)
    }

    func testEnglishGoalQuestion() {
        let q = EnrichInterview.question(for: .goal, language: .en)
        XCTAssertEqual(q.ask, "What\u{2019}s your main goal for the next few weeks?")
        XCTAssertTrue(q.why.contains("get you there first"))
    }
    func testVietnameseTractionQuestionIsLocalized() {
        let q = EnrichInterview.question(for: .traction, language: .vi)
        XCTAssertTrue(q.ask.contains("danh sách chờ"))
        XCTAssertFalse(q.why.isEmpty)
    }
}
