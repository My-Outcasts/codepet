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

    /// One tape both fakes write to, because two of this feature's five invariants are
    /// about ORDER across two objects — `voice.beginReply()` before the reply's first
    /// enqueue, `listener.endTurn()` at the send site — and a count on each fake
    /// separately cannot tell "both happened" from "both happened in the right order".
    final class Tape {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

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
        var tape: Tape?

        private var queue = SpeakingQueue()
        private var outstanding: [SpeakingQueue.Ticket] = []

        var isSpeaking: Bool { queue.isSpeaking }

        func beginReply() {
            tape?.record("beginReply")
            outstanding.removeAll()
            // Carries `unduck` only when the previous reply stalled — R4.
            apply(queue.beginReply())
        }

        func enqueue(_ sentence: String, profile: VoiceProfile) {
            tape?.record("enqueue")
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
        /// Turn boundaries taken. `0` is the assertion behind "silence sent nothing".
        var endTurnCount = 0
        var tape: Tape?
        /// Settable, because the whole finding behind `privacyLine(_:onDevice:)` is
        /// that this is a property of the installed assets and not of the language.
        var isOnDevice = true
        /// When set, `start()` throws it. Deliberately the SAME fake that can start
        /// successfully: asserting `isRunning == false` after a refusal only means
        /// something because this fake sets it true whenever it does start.
        var refuseStart: Error?

        /// **The real `TurnTranscript`, not a re-implementation.** Same reason
        /// `FakeVoice` drives the real `SpeakingQueue`: a fake with its own idea of
        /// how partials accumulate would let the protocol's monotonic-within-a-turn
        /// promise pass here and fail in production.
        private var transcript = TurnTranscript()

        /// **The live recognition request's own memory, modelled rather than assumed
        /// away.** `SFSpeechAudioBufferRecognitionRequest` has no reset:
        /// `bestTranscription` is the transcription of *every* buffer appended to that
        /// request for its whole ~1 minute life, so the only way to obtain a transcript
        /// that starts from empty is to replace the request. This array is therefore
        /// cleared by exactly one thing — `retireLiveRequest()` — and whether a turn
        /// boundary reaches it is the whole question T1 turned on.
        ///
        /// The earlier version of this fake cleared its transcript inside `endTurn()`
        /// and modelled the next partial as the new request's first word. That made the
        /// glued-question bug pass review twice: the fake kept a promise production did
        /// not.
        private var liveRequest: [String] = []

        func start() throws {
            startCount += 1
            if let refuseStart { throw refuseStart }
            isRunning = true
        }
        func stop() {
            isRunning = false
            transcript.endTurn()
            retireLiveRequest()
        }

        /// **A line-for-line mirror of `SpeechListener.endTurn()`, and it has to stay
        /// one.** Clearing `transcript` is half of it; retiring the live request is the
        /// half whose absence sent the founder's previous question again. If the two
        /// bodies drift, this fake goes back to certifying a promise production does not
        /// keep — and no test can catch that, because testing the real `endTurn()`
        /// needs an `SFSpeechRecognizer`.
        func endTurn() {
            endTurnCount += 1
            tape?.record("endTurn")
            transcript.endTurn()
            retireLiveRequest()      // `SpeechListener.endTurn()` calls `renew()`
        }

        /// The founder says more words into the live request. The request re-reports
        /// its **whole** transcript, not just the new words — that is the behaviour
        /// this fake exists to reproduce.
        func emit(_ words: String) {
            liveRequest.append(words)
            report()
        }

        /// The recognizer revises what the live request has heard so far ("teh" → "the"):
        /// the transcript is replaced wholesale, not appended to.
        func revise(to whole: String) {
            liveRequest = [whole]
            report()
        }

        /// The ~1 minute audio limit was hit mid-turn: this request retires and a
        /// fresh one starts transcribing from empty. Invisible to a consumer, which is
        /// the whole point — the next `emit` is the new request's first partial.
        func renewMidTurn() { retireLiveRequest() }

        /// What the consumer sees: the request's cumulative transcript, folded into the
        /// turn. Suppressed when nothing changed, mirroring `recognitionUpdate`.
        private func report() {
            if transcript.update(liveRequest.joined(separator: " ")) {
                onPartial?(transcript.text)
            }
        }

        /// The listener replaced the request — `renew()`, or `stop()`. The retiring
        /// request's words are kept (they are the first half of a sentence the founder
        /// may still be saying) and its memory goes with it.
        private func retireLiveRequest() {
            transcript.commit()
            liveRequest.removeAll()
        }
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
        _ = session.apply(.open); _ = session.apply(.founderSentTurn)
        voice.onFinishedAll = { _ = session.apply(.replyFinished) }
        let profile = PetVoice.profile(for: "byte")

        voice.beginReply()
        voice.enqueue("Here's the fix.", profile: profile)
        _ = session.apply(.replyBegan)
        fake.speakingCaughtUp()       // spoken in ~1.1s; the fence streams for 5-15s
        XCTAssertFalse(voice.isSpeaking)
        XCTAssertEqual(session.state, .speaking,
                       "the reply was reported finished while a code fence was still "
                       + "streaming — the mic reopens and her transcript is cleared mid-reply")

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
        _ = session.apply(.open); _ = session.apply(.founderSentTurn)
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

    // MARK: - The turn survives a renewal

    /// **The one the overlay depends on.** A recognition request lasts about a minute
    /// and a question does not have to, so a long question is heard by two requests in
    /// succession. The consumer takes the latest partial as the founder's message, and
    /// it cannot compensate for a renewal because nothing tells it one happened — so
    /// if the second request's transcript arrives alone, the founder asks a long
    /// question, watches a truncated fragment of it get sent, and pays a credit for
    /// the fragment.
    ///
    /// Driven through the protocol existential, with the renewal poked in on the fake,
    /// because "a renewal happened" is not something a consumer can see or trigger.
    func testATurnSpanningTwoRequestsArrivesAsOneString() {
        let fake = FakeListener()
        let listener: SpeechListening = fake
        var partials: [String] = []
        listener.onPartial = { partials.append($0) }
        XCTAssertNoThrow(try listener.start())

        fake.emit("what do you")
        fake.revise(to: "what do you think about")
        fake.renewMidTurn()
        fake.emit("pricing")
        fake.revise(to: "pricing for the beta")

        XCTAssertEqual(partials.last, "what do you think about pricing for the beta",
                       "the renewal truncated the founder's question")
        // Monotonic within the turn: never shorter than the partial before it.
        XCTAssertEqual(partials, partials.sorted { $0.count < $1.count },
                       "a partial went backwards, so the consumer cannot trust the latest one")
    }

    /// The other half of owning the accumulation: it has to be given back. Without
    /// `endTurn()` the founder's next question arrives with the previous one glued to
    /// the front of it — and that one gets sent.
    func testEndTurnClearsSoTheNextQuestionIsNotInherited() {
        let fake = FakeListener()
        let listener: SpeechListening = fake
        var partials: [String] = []
        listener.onPartial = { partials.append($0) }
        XCTAssertNoThrow(try listener.start())

        fake.emit("what should we charge")
        fake.renewMidTurn()
        fake.emit("for the beta")
        XCTAssertEqual(partials.last, "what should we charge for the beta")

        listener.endTurn()
        fake.emit("thanks")
        XCTAssertEqual(partials.last, "thanks",
                       "the next turn inherited the previous question's words")
    }

    /// **T1, the version with no renewal in it — the sequence from the plan's own Task
    /// 6 wiring.** The listener runs continuously across turns because barge-in needs
    /// the microphone open while the pet speaks, so one recognition request spans
    /// several turns. `endTurn()` clearing only our own accumulation leaves that
    /// request live and still holding turn 1: its next partial is
    /// `"what should we charge for the beta thanks"`, which is sent and spends a
    /// credit, and it compounds every turn for the session with nothing thrown and
    /// nothing logged.
    ///
    /// The fake models the request's memory (see `liveRequest`), so this is red for the
    /// production reason unless `endTurn()` retires the request.
    func testTheNextTurnDoesNotInheritTheLiveRequestsMemory() {
        let fake = FakeListener()
        let listener: SpeechListening = fake
        var sent: [String] = []
        listener.onPartial = { sent = [$0] }        // the consumer keeps only the latest
        XCTAssertNoThrow(try listener.start())

        // Turn 1, heard by one request, no renewal anywhere near it.
        fake.emit("what should we charge")
        fake.emit("for the beta")
        XCTAssertEqual(sent.last, "what should we charge for the beta")
        listener.endTurn()                          // sent; a credit spent

        // Turn 2. The founder says one word; the pet is still speaking, so the
        // listener never stopped.
        fake.emit("thanks")
        XCTAssertEqual(sent.last, "thanks",
                       "turn 2 carried turn 1: the live request was never retired")

        // Turn 3 compounds it, which is how a session-long defect looks in a test.
        listener.endTurn()
        fake.emit("and what about the annual plan")
        XCTAssertEqual(sent.last, "and what about the annual plan",
                       "turns are accumulating in the request for the whole session")
    }

    /// A recognizer re-reports a string it has already reported, freely. The overlay
    /// reads every partial as speech and, while the pet is speaking, treats any partial
    /// as barge-in — so an unchanged partial cuts the pet off with words the founder
    /// has already had answered. Only real changes reach the consumer.
    func testAnUnchangedPartialIsNotReportedAgain() {
        var t = TurnTranscript()
        XCTAssertTrue(t.update("what should we charge"))
        XCTAssertFalse(t.update("what should we charge"),
                       "the same transcript was reported as a change")
        XCTAssertTrue(t.update("what should we charge for"))
        t.commit()
        XCTAssertFalse(t.update(""),
                       "an empty live request after a commit is not a change")
        XCTAssertTrue(t.update("the beta"))
        XCTAssertEqual(t.text, "what should we charge for the beta")
    }

    /// Tearing the microphone down ends the turn too. `renew()` bridges 100-200ms;
    /// a `stop()` is unbounded and the founder was told listening stopped, so
    /// resuming her half-sentence afterwards is wrong.
    func testStoppingEndsTheTurn() {
        let fake = FakeListener()
        var partials: [String] = []
        fake.onPartial = { partials.append($0) }
        XCTAssertNoThrow(try fake.start())
        fake.emit("half a sentence")
        fake.stop()
        XCTAssertNoThrow(try fake.start())
        fake.emit("a new question")
        XCTAssertEqual(partials.last, "a new question")
    }

    // MARK: - The microphone is alive whenever the overlay says it is

    /// **C2.** A recognition failure raised while the pet is speaking is expected
    /// rather than broken, so the overlay deliberately shows nothing — but
    /// `SpeechListener.endOfTask`'s `.fail` branch calls `stop()` **before**
    /// `onFailure`, so the listener is already fully torn down by then, and nothing
    /// ever called `start()` a second time: `run()` calls it once and `endTurn()`
    /// early-returns on `guard isRunning`.
    ///
    /// The reachable sequence is not exotic. Voice processing cancels the pet's own
    /// audio out of the microphone — that is what makes barge-in possible — so a
    /// request left open while the founder merely LISTENS to a long reply hears
    /// genuine silence, self-terminates, renews, does it again and exhausts
    /// `RenewalBudget`. The reply then ends, the session returns to `.listening`, the
    /// header reads "Listening", the orb sits at 0, **and the founder talks into a
    /// microphone that is gone with no error displayed, for the rest of the session.**
    ///
    /// So the rule is not "restart on failure" (that re-enters the same silence-death
    /// loop and churns the engine for the whole reply) but "the mic is running
    /// whenever the overlay claims to be listening", checked at the transition back.
    func testAMicThatDiedWhileThePetSpokeIsRunningAgainOnceListening() throws {
        let fake = FakeListener()
        let listener: SpeechListening = fake
        var session = VoiceSession()
        var shown: Error?
        listener.onFailure = { error in
            guard session.state != .speaking else { return }   // the overlay's guard
            shown = error
        }

        _ = session.apply(.open)
        _ = session.apply(.founderSentTurn)
        _ = session.apply(.replyBegan)
        XCTAssertEqual(session.state, .speaking)
        XCTAssertNoThrow(try listener.start())
        let startsBefore = fake.startCount

        // `SpeechListener` stops before it reports, which is exactly why the overlay's
        // guard is not enough on its own.
        fake.failMidSession(VoiceAudioError.engineFailed("no speech detected"))
        XCTAssertNil(shown, "a silence-terminated request was shown as a failure mid-answer")
        XCTAssertFalse(listener.isRunning)

        // The reply ends. This is the moment the header starts saying "Listening".
        _ = session.apply(.replyFinished)
        XCTAssertEqual(session.state, .listening)
        XCTAssertTrue(try VoiceModeOverlay.ensureListening(listener, state: session.state),
                      "the overlay claimed to be listening with the microphone torn down")
        XCTAssertTrue(listener.isRunning)
        XCTAssertEqual(fake.startCount, startsBefore + 1)
    }

    /// The other three cases, so the ensure is a check and not an unconditional
    /// restart: a healthy listener must not be churned, and `.speaking`/`.thinking`
    /// must be left alone — `.speaking` tolerates a dead request on purpose.
    func testEnsureListeningOnlyActsWhenTheOverlayIsClaimingToListen() throws {
        let fake = FakeListener()
        XCTAssertNoThrow(try fake.start())
        XCTAssertFalse(try VoiceModeOverlay.ensureListening(fake, state: .listening),
                       "a running listener was restarted")
        XCTAssertEqual(fake.startCount, 1)

        fake.stop()
        for st in [VoiceState.idle, .thinking, .speaking] {
            XCTAssertFalse(try VoiceModeOverlay.ensureListening(fake, state: st))
            XCTAssertFalse(fake.isRunning, "\(st) restarted a mic the overlay was not promising")
        }
        XCTAssertEqual(fake.startCount, 1)
    }

    /// If the restart itself refuses, that is a real failure and must be surfaced —
    /// the one thing worse than a dead mic under a "Listening" header is a dead mic
    /// under a "Listening" header that the app tried and failed to revive silently.
    func testARefusedRestartThrowsSoTheOverlayCanShowIt() {
        let fake = FakeListener()
        fake.refuseStart = VoiceAudioError.recognizerUnavailable
        XCTAssertThrowsError(try VoiceModeOverlay.ensureListening(fake, state: .listening)) {
            XCTAssertEqual($0 as? VoiceAudioError, .recognizerUnavailable)
        }
    }

    // MARK: - A turn is taken by a tap, and by nothing else

    /// The overlay's `@State partial`, as something a callback can fill and a test can
    /// read afterwards.
    final class Transcript {
        var text = ""
    }

    /// One fixture for all four of the tests below: a listening session, the two fakes
    /// sharing a tape, and the overlay's own `onPartial` wiring.
    private struct TurnFixture {
        let listener: FakeListener
        let voice: FakeVoice
        let tape: Tape
        let partial = Transcript()
        var session = VoiceSession()
        var driver = VoiceReplyDriver()
    }

    /// Listening, with the microphone open and the partial handler wired.
    private func listeningFixture() throws -> TurnFixture {
        let tape = Tape()
        let listener = FakeListener()
        let voice = FakeVoice()
        listener.tape = tape
        voice.tape = tape
        var fixture = TurnFixture(listener: listener, voice: voice, tape: tape)
        _ = fixture.session.apply(.open)
        // `wire()`'s partial handler, minus the barge-in branch, which needs
        // `.speaking` and is covered by `testBargeInStopsTheVoiceAndReturnsToListening`.
        // **Note what it does NOT do: there is nothing left here to arm.** It stamped
        // `lastSpeechAt` until 21 Aug, and that stamp was the whole input to the 1.2s
        // deadline.
        let transcript = fixture.partial
        listener.onPartial = { transcript.text = $0 }
        try listener.start()
        return fixture
    }

    /// **The guard for spec §2 decision 4, and the one that goes red if auto-send ever
    /// comes back.**
    ///
    /// The founder says something the recognizer may well have mangled — §7 predicts
    /// exactly these words — and then stops talking and reads it. Nothing may happen.
    /// A gap of 1.6s is well past the 1.2s deadline that used to end a turn, and the
    /// `await` hands the main actor back, so a `Task` or `Timer` watcher scheduled by a
    /// re-added auto-send gets its chance to fire before the assertions run.
    ///
    /// **Verified RED, 21 Aug**, by putting the deleted watcher back into this test's
    /// own wiring — `onPartial` stamping a date, plus a 4Hz `Task` loop calling
    /// `takeTurn` once the gap reached 1.2s. It sends "add pricing for the beta" and
    /// three of the four assertions below fail. The limit of that check, stated because
    /// it matters: the watcher lived in the *view*, which no test can host, so this
    /// proves the assertions have teeth against the mechanism rather than proving the
    /// view cannot grow a new one. `VoiceModeOverlay.takeTurn` being the only
    /// send-side path in the app is what makes it the right assertion to have.
    func testSilenceAloneNeverTakesTheTurn() async throws {
        let fixture = try listeningFixture()
        fixture.listener.emit("add pricing for the beta")
        XCTAssertEqual(fixture.partial.text, "add pricing for the beta")

        try await Task.sleep(nanoseconds: 1_600_000_000)

        XCTAssertEqual(fixture.listener.endTurnCount, 0,
                       "silence retired the recognition request — the turn was taken")
        XCTAssertEqual(fixture.tape.events, [],
                       "silence began a reply: \(fixture.tape.events)")
        XCTAssertEqual(fixture.session.state, .listening,
                       "silence moved the session out of .listening")
        XCTAssertEqual(fixture.partial.text, "add pricing for the beta",
                       "her sentence was cleared while she was reading it")

        // And the fixture is not simply inert: the same state, with the tap, sends.
        var session = fixture.session
        var driver = fixture.driver
        XCTAssertEqual(VoiceModeOverlay.takeTurn(partial: fixture.partial.text,
                                                 session: &session,
                                                 listener: fixture.listener,
                                                 voice: fixture.voice,
                                                 driver: &driver, isBusy: false),
                       "add pricing for the beta",
                       "nothing above was asserting anything: ✓ cannot send either")
    }

    /// ✓ takes the turn **once**, and takes both of the send site's invariants with it:
    /// `beginReply()` before the reply's first `enqueue` (or sentence 1 of every
    /// post-barge-in reply is dropped) and `endTurn()` at the send site (or the next
    /// question arrives with this one glued to its front). Both fail silently.
    ///
    /// The second tap is not hypothetical: the button is under her finger, and it used
    /// to be a timer that could only fire once per turn by construction.
    func testConfirmTakesTheTurnOnceAndKeepsTheSendSiteInvariants() throws {
        var fixture = try listeningFixture()
        fixture.listener.emit("what should we charge for the beta")

        let sent = VoiceModeOverlay.takeTurn(partial: fixture.partial.text,
                                             session: &fixture.session,
                                             listener: fixture.listener,
                                             voice: fixture.voice,
                                             driver: &fixture.driver, isBusy: false)
        XCTAssertEqual(sent, "what should we charge for the beta")
        XCTAssertEqual(fixture.session.state, .thinking,
                       "the orb never stopped tracking her level — she cannot see the "
                       + "turn was taken")
        fixture.partial.text = ""                      // what the view does after ✓

        // The reply's first sentence, to place the enqueue against `beginReply()`.
        fixture.voice.enqueue("Charge forty.", profile: PetVoice.profile(for: "nova"))
        XCTAssertEqual(fixture.tape.events, ["beginReply", "endTurn", "enqueue"],
                       "the send site's order changed: \(fixture.tape.events)")
        XCTAssertEqual(fixture.voice.spoken, ["Charge forty."],
                       "the latch was closed when the reply's first sentence arrived")

        // Tap twice — and again with a transcript still on screen, which is what a
        // late partial from the retired request would leave.
        XCTAssertNil(VoiceModeOverlay.takeTurn(partial: fixture.partial.text,
                                               session: &fixture.session,
                                               listener: fixture.listener,
                                               voice: fixture.voice,
                                               driver: &fixture.driver, isBusy: false),
                     "a second ✓ took a second turn")
        XCTAssertNil(VoiceModeOverlay.takeTurn(partial: "still on screen",
                                               session: &fixture.session,
                                               listener: fixture.listener,
                                               voice: fixture.voice,
                                               driver: &fixture.driver, isBusy: false),
                     "✓ sent again while the pet was thinking about the first question")
        XCTAssertEqual(fixture.listener.endTurnCount, 1,
                       "the turn was taken \(fixture.listener.endTurnCount) times")
    }

    /// **✓ with an empty transcript is impossible** (spec §5). `sendChat` drops an
    /// empty string, so this is not a crash but a credit-shaped no-op: the orb stops
    /// listening, the session leaves `.listening`, and no question was ever asked.
    ///
    /// Whitespace counts as empty. A recognizer that reports `" "` is the reachable
    /// version of this — it was `endTurnIfSilent`'s own second guard before the change.
    func testConfirmingAnEmptyTranscriptIsImpossible() {
        for text in ["", " ", "\n  \t"] {
            var session = VoiceSession()
            _ = session.apply(.open)
            var driver = VoiceReplyDriver()
            let tape = Tape()
            let listener = FakeListener()
            let voice = FakeVoice()
            listener.tape = tape
            voice.tape = tape

            XCTAssertFalse(VoiceModeOverlay.canTakeTurn(partial: text, state: .listening,
                                                        isBusy: false),
                           "✓ was enabled on \(text.debugDescription)")
            XCTAssertNil(VoiceModeOverlay.takeTurn(partial: text, session: &session,
                                                   listener: listener, voice: voice,
                                                   driver: &driver, isBusy: false))
            XCTAssertEqual(session.state, .listening,
                           "\(text.debugDescription) took the turn: the orb stops "
                           + "listening and nothing was asked")
            XCTAssertEqual(tape.events, [],
                           "\(text.debugDescription) opened a reply and retired the "
                           + "request: \(tape.events)")
        }

        // The other side of the rule, so the assertions above are not just "always
        // false", and the two conditions that are not about emptiness at all.
        XCTAssertTrue(VoiceModeOverlay.canTakeTurn(partial: "hi", state: .listening,
                                                   isBusy: false))
        XCTAssertFalse(VoiceModeOverlay.canTakeTurn(partial: "hi", state: .listening,
                                                    isBusy: true),
                       "✓ was live while a turn was already in flight — `sendMessage` "
                       + "drops it and there is no next tick to retry on")
        for state in [VoiceState.idle, .thinking, .speaking] {
            XCTAssertFalse(VoiceModeOverlay.canTakeTurn(partial: "hi", state: state,
                                                        isBusy: false),
                           "✓ was live in \(state)")
        }
    }

    /// **✕ spends nothing, and takes the discarded words with it.**
    ///
    /// The second half is the one that is easy to get wrong: clearing only the view's
    /// `partial` leaves the live request still holding the sentence, so her *next*
    /// partial arrives as "add pricing for the beta what about the annual plan" — the
    /// mangled sentence she just rejected, back on screen and one tap from being sent
    /// at 0.25 credits. Same defect as T1, reached from ✕ instead of from the send.
    func testDiscardSpendsNothingAndTakesTheWordsWithIt() throws {
        let fixture = try listeningFixture()
        fixture.listener.emit("add pricing for the beta")

        VoiceModeOverlay.abandonTurn(fixture.listener)
        fixture.partial.text = ""                      // what the view does after ✕

        XCTAssertEqual(fixture.session.state, .listening,
                       "✕ left voice mode or took the turn — it must keep listening")
        XCTAssertEqual(fixture.tape.events, ["endTurn"],
                       "✕ began a reply: \(fixture.tape.events)")
        XCTAssertFalse(VoiceModeOverlay.canTakeTurn(partial: fixture.partial.text,
                                                    state: fixture.session.state,
                                                    isBusy: false),
                       "✕ left a transcript ✓ could still charge for")
        // The count itself moves in exactly one place — `sendTurn()`'s Task, after a
        // non-nil `takeTurn` — and nothing above went near it.
        XCTAssertTrue(VoiceModeOverlay.creditLine(turns: 0, .en).contains("0"))

        fixture.listener.emit("what about the annual plan")
        XCTAssertEqual(fixture.partial.text, "what about the annual plan",
                       "the discarded sentence came back glued to the next one")
    }

    // MARK: - Opening voice mode over a live typed turn

    /// **C3.** `SpeakingQueue` starts `accepting = true, reported = false`, so
    /// `endOfReply()` on a queue that never had a `beginReply()` **drains and
    /// reports** — firing `onFinishedAll`, which unconditionally clears the partial,
    /// the timestamp and the level.
    ///
    /// That is reachable because the overlay can be opened over a typed turn already
    /// in flight: she taps the waveform, speaks into a `.listening` overlay (so no
    /// barge-in and the latch stays open), `canTakeTurn`'s `isBusy` correctly holds ✓
    /// disabled while that reply streams — and then the TYPED reply finishes and erases
    /// her question mid-flight, with no message, no orb change and no credit spent.
    ///
    /// The first assertion is the guard; the rest is why it must answer that way.
    func testAStreamEndInListeningIsNotThisOverlaysReply() {
        XCTAssertFalse(VoiceModeOverlay.streamEndBelongsToVoiceTurn(.listening),
                       "a typed reply's stream end was treated as the spoken turn's")
        XCTAssertFalse(VoiceModeOverlay.streamEndBelongsToVoiceTurn(.idle))
        XCTAssertTrue(VoiceModeOverlay.streamEndBelongsToVoiceTurn(.thinking))
        XCTAssertTrue(VoiceModeOverlay.streamEndBelongsToVoiceTurn(.speaking))

        // And what the `.listening` answer is protecting: a virgin queue reports.
        let voice = FakeVoice()
        var finished = 0
        voice.onFinishedAll = { finished += 1 }
        voice.endOfReply()
        XCTAssertEqual(finished, 1,
                       "if a virgin queue no longer reports, this guard has lost its reason")
    }

    /// A recognizer revises what it already said ("teh" → "the"), so the live
    /// request's transcript replaces rather than appends — while committed fragments
    /// stay put. Straight at the struct: this is the distinction that makes the
    /// accumulation correct rather than merely additive.
    func testARevisionReplacesTheLiveRequestButKeepsWhatIsCommitted() {
        var t = TurnTranscript()
        _ = t.update("what do you thing")
        _ = t.update("what do you think")
        XCTAssertEqual(t.text, "what do you think", "a revision was appended instead of replacing")
        t.commit()
        _ = t.update("about")
        _ = t.update("about pricing")
        XCTAssertEqual(t.text, "what do you think about pricing")
    }

    /// A renewal during silence must not leave a seam in the middle of the sentence.
    func testARequestThatHeardNothingAddsNoSeam() {
        var t = TurnTranscript()
        _ = t.update("hello")
        t.commit()
        t.commit()          // a second renewal, nothing heard in between
        XCTAssertEqual(t.text, "hello")
        _ = t.update("there")
        XCTAssertEqual(t.text, "hello there", "an empty request left a stray space")

        var fresh = TurnTranscript()
        fresh.commit()
        XCTAssertEqual(fresh.text, "", "a turn that heard nothing is empty, not whitespace")
        fresh.endTurn()
        XCTAssertEqual(fresh, TurnTranscript(), "endTurn left state behind")
    }
}
