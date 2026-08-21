import XCTest
@testable import codepet

/// The loop from spec §4, as a value type.
///
/// **`.founderSentTurn` was `.heardSilence` until 21 Aug.** Spec §2 decision 4 made a
/// turn something the founder taps rather than something a timer notices, so the event
/// is renamed and nothing else about this machine moves: the transition is still
/// `listening → thinking`, and the refusals below are still the interesting part.
///
/// It is a separate type rather than `@State` in the overlay for one reason: the
/// illegal transitions are the interesting ones, and a view cannot be asked what
/// it refuses to do. `apply` returns a Bool so a caller that fires an event at the
/// wrong moment — a late recognition callback, a synthesiser finishing after the
/// founder closed the overlay — is a no-op rather than a state corruption.
final class VoiceSessionTests: XCTestCase {

    func testStartsIdle() {
        XCTAssertEqual(VoiceSession().state, .idle)
        XCTAssertFalse(VoiceSession().isActive)
    }

    func testTheHappyLoop() {
        var s = VoiceSession()
        XCTAssertTrue(s.apply(.open));            XCTAssertEqual(s.state, .listening)
        XCTAssertTrue(s.apply(.founderSentTurn));    XCTAssertEqual(s.state, .thinking)
        XCTAssertTrue(s.apply(.replyBegan));      XCTAssertEqual(s.state, .speaking)
        XCTAssertTrue(s.apply(.replyFinished));   XCTAssertEqual(s.state, .listening)
    }

    /// Barge-in: the founder talks over the reply. Only legal while speaking —
    /// firing it while listening would restart a turn that is already running.
    func testBargeInFromSpeakingReturnsToListening() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.founderSentTurn); _ = s.apply(.replyBegan)
        XCTAssertTrue(s.apply(.founderInterrupted))
        XCTAssertEqual(s.state, .listening)
    }

    func testBargeInIsIgnoredWhenNotSpeaking() {
        var s = VoiceSession()
        _ = s.apply(.open)
        XCTAssertFalse(s.apply(.founderInterrupted), "interrupting nothing must be a no-op")
        XCTAssertEqual(s.state, .listening)
    }

    /// **The late-callback case, and why `apply` returns Bool.** A recognition or
    /// synthesis callback can arrive after the founder has closed the overlay. It
    /// must not reopen it.
    func testEventsAfterCloseAreRefused() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.founderSentTurn)
        XCTAssertTrue(s.apply(.close))
        XCTAssertEqual(s.state, .idle)
        for late in [VoiceEvent.replyBegan, .replyFinished, .founderSentTurn, .founderInterrupted] {
            XCTAssertFalse(s.apply(late), "\(late) reopened a closed session")
            XCTAssertEqual(s.state, .idle)
        }
    }

    /// **A double-tap of ✓ must not re-send the turn.** It was the silence timer that
    /// could fire twice before; now it is a button under her finger, which is if
    /// anything easier to hit twice — and the second one would take a turn against a
    /// transcript that has already been cleared and charge for it.
    func testASecondConfirmIsIgnoredOnceTheTurnIsTaken() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.founderSentTurn)   // now thinking
        XCTAssertFalse(s.apply(.founderSentTurn), "a second ✓ must not re-send the turn")
        XCTAssertEqual(s.state, .thinking)
    }

    func testCloseIsLegalFromEveryState() {
        for setup: [VoiceEvent] in [[], [.open], [.open, .founderSentTurn],
                                    [.open, .founderSentTurn, .replyBegan]] {
            var s = VoiceSession()
            for e in setup { _ = s.apply(e) }
            _ = s.apply(.close)
            XCTAssertEqual(s.state, .idle, "close failed after \(setup)")
        }
    }

    func testOpeningAnOpenSessionIsRefused() {
        var s = VoiceSession()
        _ = s.apply(.open)
        XCTAssertFalse(s.apply(.open))
        XCTAssertEqual(s.state, .listening)
    }
}
