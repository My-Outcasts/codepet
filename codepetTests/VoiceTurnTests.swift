import XCTest
@testable import codepet

/// When is the founder's turn over? Pure arithmetic, extracted from the listener
/// so the one number the founder will complain about is testable without a mic.
final class VoiceTurnTests: XCTestCase {

    func testTheThresholdIsTheFoundersNumber() {
        XCTAssertEqual(VoiceTurn.silenceThreshold, 1.2, accuracy: 0.001)
    }

    func testSilenceShorterThanTheThresholdDoesNotEndTheTurn() {
        let now = Date()
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(-0.9),
                                               now: now,
                                               threshold: VoiceTurn.silenceThreshold))
    }

    func testSilencePastTheThresholdEndsIt() {
        let now = Date()
        XCTAssertTrue(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(-1.3),
                                              now: now,
                                              threshold: VoiceTurn.silenceThreshold))
    }

    /// **Nothing heard yet must never end a turn.** Otherwise opening the overlay
    /// and pausing to think sends an empty message and spends a credit.
    func testNoSpeechYetNeverEndsTheTurn() {
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: nil, now: Date(),
                                               threshold: VoiceTurn.silenceThreshold))
    }

    func testAClockThatWentBackwardsDoesNotEndTheTurn() {
        let now = Date()
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(5),
                                               now: now, threshold: VoiceTurn.silenceThreshold))
    }
}
