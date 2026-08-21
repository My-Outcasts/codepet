import XCTest
@testable import codepet

/// **No test in this file touches audio hardware.** The protocols exist so the
/// suite can drive fakes, and this suite is the proof that the protocols are
/// sufficient — if a fake cannot express the behaviour the overlay needs, the
/// boundary is in the wrong place.
///
/// The rule is not style. On 21 Aug, `PetMenuIcon` drew a sprite through
/// `NSImage.lockFocus()`, which needs a window-server graphics context a headless
/// XCTest host lacks, and six unrelated SSE streaming tests began failing — a
/// stream test read `delta("You're ")` instead of `delta("Hello")`. AVFoundation
/// and Speech are the same hazard and worse: they want a microphone.
@MainActor
final class SpeechFakesTests: XCTestCase {

    final class FakeVoice: SpeakingVoice {
        var onFinishedAll: (() -> Void)?
        var spoken: [String] = []
        var stopped = 0
        var isSpeaking = false
        func enqueue(_ sentence: String, profile: VoiceProfile) {
            spoken.append(sentence); isSpeaking = true
        }
        func stopImmediately() { stopped += 1; isSpeaking = false }
        func finishAll() { isSpeaking = false; onFinishedAll?() }
    }

    final class FakeListener: SpeechListening {
        var onPartial: ((String) -> Void)?
        var onLevel: ((Float) -> Void)?
        var isRunning = false
        var startCount = 0
        func start() throws { startCount += 1; isRunning = true }
        func stop() { isRunning = false }
        func emit(_ partial: String) { onPartial?(partial) }
    }

    /// The protocol has to be able to express "speak these, then tell me you're done".
    func testTheVoiceProtocolCarriesQueueAndCompletion() {
        let v = FakeVoice()
        var finished = false
        v.onFinishedAll = { finished = true }
        v.enqueue("One.", profile: PetVoice.profile(for: "nova"))
        v.enqueue("Two.", profile: PetVoice.profile(for: "nova"))
        XCTAssertEqual(v.spoken, ["One.", "Two."])
        XCTAssertTrue(v.isSpeaking)
        v.finishAll()
        XCTAssertTrue(finished)
        XCTAssertFalse(v.isSpeaking)
    }

    /// Barge-in composed end to end from the pieces, with no audio: the founder
    /// speaks while the fake voice is mid-queue, the session moves, the voice stops.
    func testBargeInStopsTheVoiceAndReturnsToListening() {
        var session = VoiceSession()
        let voice = FakeVoice()
        let listener = FakeListener()
        _ = session.apply(.open); _ = session.apply(.heardSilence)
        voice.enqueue("A long reply that is still going.",
                      profile: PetVoice.profile(for: "byte"))
        _ = session.apply(.replyBegan)
        XCTAssertEqual(session.state, .speaking)

        listener.onPartial = { _ in
            if session.state == .speaking {
                voice.stopImmediately()
                _ = session.apply(.founderInterrupted)
            }
        }
        listener.emit("actually wait")

        XCTAssertEqual(voice.stopped, 1, "the voice kept talking over her")
        XCTAssertEqual(session.state, .listening)
    }

    /// The splitter and the queue together: a streaming reply speaks each sentence
    /// exactly once, and never a fragment.
    ///
    /// **Ends with `flush`, not another `take`.** Task 2's `SentenceSplitter` (see
    /// its type doc) deliberately will not release "Third." from `take` alone: its
    /// terminator is the very last character `full` ever has, and a terminator that
    /// happens to be the last character available is not proof the reply is
    /// finished — indistinguishable from a stream that is merely paused there. Only
    /// `flush`, called once streaming is known complete, releases the true final
    /// sentence. The brief's version of this test called `take` in the loop and
    /// nothing after; that leaves "Third." unspoken forever and is a bug in the
    /// brief, not in `SentenceSplitter` — reproduced and confirmed by running it
    /// unmodified before this fix (see task-4-report.md).
    func testStreamingRepliesSpeakEachSentenceOnce() {
        var splitter = SentenceSplitter()
        let voice = FakeVoice()
        let profile = PetVoice.profile(for: "sage")
        let full = "First point. Second point. Third."
        for end in 1...full.count {
            for s in splitter.take(from: String(full.prefix(end))) {
                voice.enqueue(s, profile: profile)
            }
        }
        // Stream is complete: flush releases whatever take() was still holding back.
        for s in splitter.flush(from: full) {
            voice.enqueue(s, profile: profile)
        }
        XCTAssertEqual(voice.spoken, ["First point.", "Second point.", "Third."])
    }

    /// A listener that fails to start must be visible, not silent — the overlay
    /// shows an error instead of a live-looking orb that hears nothing.
    func testAListenerThatCannotStartReportsIt() {
        final class DeadListener: SpeechListening {
            var onPartial: ((String) -> Void)?
            var onLevel: ((Float) -> Void)?
            var isRunning = false
            func start() throws { throw VoiceAudioError.recognizerUnavailable }
            func stop() {}
        }
        let l = DeadListener()
        XCTAssertThrowsError(try l.start())
        XCTAssertFalse(l.isRunning)
    }
}
