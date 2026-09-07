import XCTest
@testable import codepet

/// The rule that decides whether a thumb reaches Firestore. It exists as a pure function
/// precisely because `MessageFeedbackService.submit` cannot be reached under XCTest — its
/// first condition is `!isRunningTests` — so before this there was nowhere to assert the rule,
/// which is how the prototype-mode hole survived.
final class MessageFeedbackGateTests: XCTestCase {

    /// The only combination that may write: a real run, an account that has not opted out,
    /// and cloud writes permitted.
    func testTheOnlyWritingCombination() {
        XCTAssertTrue(MessageFeedbackGate.allowsWrite(isRunningTests: false,
                                                      isOptedOut: false,
                                                      allowsCloudWrites: true))
    }

    /// **The reported leak.** Prototype mode promises, in the sidebar's own words, that
    /// nothing is written to the founder's account — and a thumb wrote one anyway. Rating a
    /// fixture reply produces a document whose `messageId`/`threadId` name nothing outside
    /// memory, and `firestore.rules:42` denies both read and update, so it can never be
    /// corrected or removed.
    func testPrototypeModeBlocksTheWrite() {
        XCTAssertFalse(MessageFeedbackGate.allowsWrite(isRunningTests: false,
                                                       isOptedOut: false,
                                                       allowsCloudWrites: false))
    }

    func testTheSuiteNeverWrites() {
        XCTAssertFalse(MessageFeedbackGate.allowsWrite(isRunningTests: true,
                                                       isOptedOut: false,
                                                       allowsCloudWrites: true))
    }

    func testAnOptedOutAccountNeverWrites() {
        XCTAssertFalse(MessageFeedbackGate.allowsWrite(isRunningTests: false,
                                                       isOptedOut: true,
                                                       allowsCloudWrites: true))
    }

    /// Each condition must block ON ITS OWN, whatever the other two say. An implementation
    /// that had, say, dropped `allowsCloudWrites` would still pass the three cases above if
    /// they were written as one combined expectation — this enumerates the space instead.
    func testAnyBlockingConditionBlocksRegardlessOfTheOthers() {
        let expected: [(tests: Bool, optedOut: Bool, cloudOK: Bool, allowed: Bool)] = [
            (false, false, true,  true),
            (false, false, false, false),
            (false, true,  true,  false),
            (false, true,  false, false),
            (true,  false, true,  false),
            (true,  false, false, false),
            (true,  true,  true,  false),
            (true,  true,  false, false),
        ]
        for c in expected {
            XCTAssertEqual(
                MessageFeedbackGate.allowsWrite(isRunningTests: c.tests,
                                                isOptedOut: c.optedOut,
                                                allowsCloudWrites: c.cloudOK),
                c.allowed,
                "tests=\(c.tests) optedOut=\(c.optedOut) cloudOK=\(c.cloudOK)")
        }
    }

    /// Exactly one of the eight combinations may write. A gate that had been loosened
    /// anywhere would let a second one through and fail here without naming which.
    func testExactlyOneOfTheEightCombinationsWrites() {
        var writing = 0
        for t in [false, true] where true {
            for o in [false, true] {
                for c in [false, true] {
                    if MessageFeedbackGate.allowsWrite(isRunningTests: t, isOptedOut: o,
                                                       allowsCloudWrites: c) { writing += 1 }
                }
            }
        }
        XCTAssertEqual(writing, 1)
    }

    /// In a release build `PrototypeMode` is compiled out to "always allow", so this gate must
    /// not change shipping behaviour — the mode does not exist there to be on.
    func testTheProductionGateIsOpenWhenNothingBlocks() {
        XCTAssertTrue(PrototypeMode.allowsCloudWrites || PrototypeMode.isOn,
                      "allowsCloudWrites may only be false while prototype mode is on")
    }
}
