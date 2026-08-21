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
///
/// **What changed after review.** The four tests here used to pass with the bodies
/// of both service classes deleted, because everything they asserted lived in the
/// fakes. The behavioural rules now live in `SpeakingQueue` and `VoiceLevel`, which
/// are pure and have their own suites; `FakeVoice` below is built on the same
/// `SpeakingQueue` the real speaker uses, so it can no longer answer a question
/// differently from production (I7) — and these tests are the protocol's own
/// contract: the shapes the overlay will be written against.
@MainActor
final class SpeechFakesTests: XCTestCase {

    /// **Backed by the real `SpeakingQueue`, on purpose.** The reviewed defect was a
    /// fake that flipped `isSpeaking` synchronously inside `enqueue` while
    /// `SpeechSpeaker.isSpeaking` returned the synthesiser's asynchronous flag. Any
    /// overlay logic validated only against that fake would behave differently when
    /// it shipped. Sharing the bookkeeping makes the two agree by construction; all
    /// the fake adds is the audio the test host cannot have.
    final class FakeVoice: SpeakingVoice {
        var onFinishedAll: (() -> Void)?
        var spoken: [String] = []
        var stopped = 0
        var unducks = 0

        private var queue = SpeakingQueue()
        private var outstanding: [SpeakingQueue.Ticket] = []

        var isSpeaking: Bool { queue.isSpeaking }

        func beginReply() {
            queue.beginReply()
            outstanding.removeAll()
        }

        func enqueue(_ sentence: String, profile: VoiceProfile) {
            guard let accepted = queue.enqueue() else { return }
            outstanding.append(accepted.ticket)
            spoken.append(sentence)
        }

        func endOfReply() { apply(queue.endOfReply()) }

        func stopImmediately() {
            stopped += 1
            outstanding.removeAll()
            apply(queue.stop())
        }

        /// The synthesiser reporting one utterance back.
        func speakingFinishedOne() {
            guard !outstanding.isEmpty else { return }
            apply(queue.finishedOne(outstanding.removeFirst()))
        }

        /// Everything handed over so far reports back.
        func speakingCaughtUp() {
            while !outstanding.isEmpty { speakingFinishedOne() }
        }

        private func apply(_ effects: SpeakingQueue.Effects) {
            if effects.unduck { unducks += 1 }
            if effects.finishedReply { onFinishedAll?() }
        }
    }

    final class FakeListener: SpeechListening {
        var onPartial: ((String) -> Void)?
        var onLevel: ((Float) -> Void)?
        var onFailure: ((Error) -> Void)?
        var isRunning = false
        var startCount = 0
        /// When set, `start()` throws it. Deliberately the SAME fake that can start
        /// successfully: asserting `isRunning == false` after a refusal only means
        /// something because this fake sets it true whenever it does start.
        var refuseStart: Error?

        func start() throws {
            startCount += 1
            if let refuseStart { throw refuseStart }
            isRunning = true
        }
        func stop() { isRunning = false }
        func emit(_ partial: String) { onPartial?(partial) }
        /// Recognition dying after `start()` returned. Mirrors `SpeechListener`,
        /// which stops before it reports.
        func failMidSession(_ error: Error) {
            stop()
            onFailure?(error)
        }
    }

    /// The protocol has to be able to express "speak these, then tell me the reply
    /// is over" — and to keep those two apart.
    func testTheVoiceProtocolCarriesQueueAndCompletion() {
        let v = FakeVoice()
        var finished = 0
        v.onFinishedAll = { finished += 1 }
        v.beginReply()
        v.enqueue("One.", profile: PetVoice.profile(for: "nova"))
        v.enqueue("Two.", profile: PetVoice.profile(for: "nova"))
        XCTAssertEqual(v.spoken, ["One.", "Two."])
        XCTAssertTrue(v.isSpeaking)
        v.speakingCaughtUp()
        XCTAssertFalse(v.isSpeaking)
        XCTAssertEqual(finished, 0, "the queue drained, but the stream had not ended")
        v.endOfReply()
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(v.unducks, 1, "the SFX were left ducked after the reply")
    }

    /// **C3 through the protocol.** The overlay cannot infer end-of-reply from a
    /// drain, so the protocol must not let it: a gap while a code fence streams
    /// leaves the queue empty and the reply unfinished.
    ///
    /// **Driven through the protocol existential on purpose.** The point of the
    /// finding is that the PROTOCOL gave the overlay no way to tell a drain from an
    /// end-of-reply, so deleting `beginReply`/`endOfReply` from it must fail to
    /// compile rather than be quietly absorbed by the fake's own methods.
    func testAGapWhileACodeFenceStreamsIsNotTheEndOfTheReply() {
        let fake = FakeVoice()
        let voice: SpeakingVoice = fake
        var session = VoiceSession()
        _ = session.apply(.open); _ = session.apply(.heardSilence)
        voice.onFinishedAll = { _ = session.apply(.replyFinished) }
        let profile = PetVoice.profile(for: "byte")

        voice.beginReply()
        voice.enqueue("Here's the fix.", profile: profile)
        _ = session.apply(.replyBegan)
        fake.speakingCaughtUp()       // spoken in ~1.1s; the fence streams for 5-15s
        XCTAssertFalse(voice.isSpeaking)
        XCTAssertEqual(session.state, .speaking,
                       "the mic reopened mid-reply — the next silence spends a credit")

        voice.enqueue("That should do it.", profile: profile)
        voice.endOfReply()
        XCTAssertEqual(session.state, .speaking, "a sentence is still being spoken")
        fake.speakingCaughtUp()
        XCTAssertEqual(session.state, .listening)
    }

    /// Barge-in composed end to end from the pieces, with no audio: the founder
    /// speaks while the fake voice is mid-queue, the session moves, the voice stops
    /// — and the rest of the reply, which is still streaming, stays unspoken.
    func testBargeInStopsTheVoiceAndReturnsToListening() {
        var session = VoiceSession()
        let voice = FakeVoice()
        let listener = FakeListener()
        _ = session.apply(.open); _ = session.apply(.heardSilence)
        voice.beginReply()
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
        XCTAssertFalse(voice.isSpeaking)
        XCTAssertEqual(voice.unducks, 1, "the SFX were left silent after barge-in")

        // The server is still streaming; the consumer keeps offering sentences.
        voice.enqueue("And here is the rest of it.", profile: PetVoice.profile(for: "byte"))
        XCTAssertEqual(voice.spoken.count, 1, "the pet resumed after being interrupted")
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
        voice.beginReply()
        for end in 1...full.count {
            for s in splitter.take(from: String(full.prefix(end))) {
                voice.enqueue(s, profile: profile)
            }
        }
        // Stream is complete: flush releases whatever take() was still holding back.
        for s in splitter.flush(from: full) {
            voice.enqueue(s, profile: profile)
        }
        voice.endOfReply()
        XCTAssertEqual(voice.spoken, ["First point.", "Second point.", "Third."])
    }

    /// A listener that fails to start must be visible, not silent — the overlay
    /// shows an error instead of a live-looking orb that hears nothing.
    func testAListenerThatCannotStartReportsIt() {
        let l = FakeListener()
        l.refuseStart = VoiceAudioError.recognizerUnavailable
        XCTAssertThrowsError(try l.start()) { error in
            XCTAssertEqual(error as? VoiceAudioError, .recognizerUnavailable)
        }
        XCTAssertFalse(l.isRunning)

        // The same fake, allowed to start, does set it — which is what makes the
        // assertion above mean something.
        l.refuseStart = nil
        XCTAssertNoThrow(try l.start())
        XCTAssertTrue(l.isRunning)
    }

    /// **C2.** `start()` succeeding is not the same as recognition working.
    /// `SFSpeechRecognizer.isAvailable` reports service availability, not
    /// authorisation, so `start()` returns cleanly with speech recognition denied,
    /// the tap fires, the orb pulses — and the recognition task fails. Swallowed
    /// (which is what shipped: the callback's error was bound to `_`) the founder
    /// watches a live orb that never produces one word, with nothing logged. Same
    /// path for a mid-session permission revoke, and for any network drop under
    /// vi-VN, which spec §3 measured as server-side.
    ///
    /// **Bound through the protocol existential on purpose**, so that deleting the
    /// `onFailure` requirement fails to compile instead of being absorbed by the
    /// fake's own stored property. The channel has to exist on the protocol: that is
    /// the whole finding — `start() throws` covers only synchronous failure.
    func testRecognitionDyingAfterStartIsReportedAndStopsListening() {
        let fake = FakeListener()
        let listener: SpeechListening = fake
        var reported: Error?
        var partials: [String] = []
        listener.onFailure = { reported = $0 }
        listener.onPartial = { partials.append($0) }

        XCTAssertNoThrow(try listener.start())
        XCTAssertTrue(listener.isRunning)
        fake.emit("hello")

        fake.failMidSession(VoiceAudioError.engineFailed("the network dropped"))
        XCTAssertEqual(reported as? VoiceAudioError, .engineFailed("the network dropped"),
                       "recognition died and the overlay was never told")
        XCTAssertFalse(listener.isRunning, "a dead recognizer left the orb looking live")
        XCTAssertEqual(partials, ["hello"])
    }
}
