import XCTest
@testable import codepet

/// The renew-or-fail decision, which used to be three lines of inline state on
/// `SpeechListener` where no test could reach it — reaching it needed an
/// `SFSpeechRecognizer`. It is the bound that keeps a broken recognizer from becoming
/// a silent tight loop of failing tasks behind a live-looking orb, and it contained a
/// defect (`""` counted as a transcript) that a test of exactly this shape would have
/// caught the day it was written.
///
/// No audio, no Speech types: the decision is an `Int` and a `String`.
final class RenewalBudgetTests: XCTestCase {

    /// A conversation the recognizer is handling: every task ends having transcribed
    /// something, so renewal never runs out. Voice mode must survive an hour of this —
    /// a request lasts about a minute, so an hour is ~60 renewals.
    func testAHealthyConversationRenewsIndefinitely() {
        var budget = RenewalBudget()
        for minute in 1...60 {
            budget.sawTranscript("what should we charge for the beta")
            XCTAssertEqual(budget.taskEnded(), .renew,
                           "voice mode gave up at minute \(minute) of a working conversation")
        }
    }

    /// The condition the bound exists for: recognition is dead (authorisation revoked
    /// in System Settings, the recognizer withdrawn, the network gone under vi-VN), so
    /// every task we open dies having transcribed nothing. One renewal is spent finding
    /// out; the second failure is reported instead of renewed, because renewing forever
    /// is a silent loop of failing tasks and the founder just watches the orb.
    func testTwoTasksThatTranscribeNothingEscalateToFailure() {
        var budget = RenewalBudget()
        XCTAssertEqual(budget.taskEnded(), .renew, "the first end is not yet evidence")
        XCTAssertEqual(budget.taskEnded(), .fail,
                       "a fresh task that heard nothing either was renewed again")
        // And it stays failed — nothing resets it but a transcript or a fresh listener.
        XCTAssertEqual(budget.taskEnded(), .fail)
    }

    /// **The defect.** The call site reset the counter on `if let text`, where `text` is
    /// `result?.bestTranscription.formattedString` — so a result carrying `""` cleared
    /// the budget. An empty transcript is precisely what a task delivers while it is
    /// failing to hear anything: it is the absence of evidence, and treating it as
    /// evidence disarms the bound in the one condition it exists to detect.
    func testAnEmptyTranscriptDoesNotClearTheBudget() {
        var budget = RenewalBudget()
        budget.sawTranscript("")
        XCTAssertEqual(budget.taskEnded(), .renew)
        budget.sawTranscript("")
        XCTAssertEqual(budget.taskEnded(), .fail,
                       "an empty result cleared the budget, so a dead recognizer renews forever")

        // One real word is enough to make it whole again — the recognizer works.
        budget.sawTranscript("hello")
        XCTAssertEqual(budget.taskEnded(), .renew)
    }

    /// The allowance is a stated number, not an accident of the comparison. Flipping
    /// `<` to `<=` doubles it silently.
    func testTheAllowanceIsOneRenewal() {
        XCTAssertEqual(RenewalBudget.allowance, 1)
        var budget = RenewalBudget()
        var renewals = 0
        // Bounded on purpose: an unbounded loop here would hang the test host — which
        // takes ~27 unrelated tests with it — instead of failing.
        while renewals < 10, budget.taskEnded() == .renew { renewals += 1 }
        XCTAssertEqual(renewals, RenewalBudget.allowance)
    }
}
