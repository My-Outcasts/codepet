import XCTest
@testable import codepet

/// The bookkeeping behind speaking a reply, with no synthesiser anywhere near it.
///
/// **Four Task 4 review findings were defects in these rules** (C3, I2, I3, I4) and
/// not one of them was reachable while the rules lived inside `SpeechSpeaker` next
/// to `AVSpeechSynthesizer`. Every test below is the direct expression of one of
/// them: delete the guard it names and this suite goes red.
final class SpeakingQueueTests: XCTestCase {

    // MARK: - C3: a drain is not the end of a reply

    /// **The mid-reply reset bug.** A reply streams "Here's the fix." then a fenced
    /// code block then "That should do it." `SentenceSplitter.speakable` deletes the
    /// fence entirely, so for the 5-15s it streams there are no speakable sentences
    /// and the queue is empty. If that reports finished, the surface applies
    /// `.replyFinished` and leaves `.speaking` while the real reply is still arriving —
    /// so `VoiceComposer.speak` refuses every sentence after the fence and the
    /// founder hears half an answer. It was worse than that: it also cleared her
    /// transcript (deleted 22 Aug, see `VoiceTurnFlow.replyEnded`), and until 21 Aug
    /// the mic reopened, the 1.2s silence timer fired on the founder saying nothing,
    /// and an empty turn was sent and charged.
    func testADrainMidStreamDoesNotReportTheReplyFinished() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let first = q.enqueue()!.ticket
        XCTAssertEqual(q.finishedOne(first), SpeakingQueue.Effects(),
                       "the queue emptied mid-stream and claimed the reply was over")
        XCTAssertFalse(q.isSpeaking)

        // The fence streams for seconds, producing nothing. Then the last sentence.
        let last = q.enqueue()!.ticket
        XCTAssertEqual(q.endOfReply(), SpeakingQueue.Effects(),
                       "the stream ended but a sentence is still being spoken")
        XCTAssertEqual(q.finishedOne(last),
                       SpeakingQueue.Effects(unduck: true, finishedReply: true))
    }

    /// The other half of C3: `endOfReply` is what makes a drain mean something, and
    /// a reply that was ONLY a code fence never speaks a word yet is still over.
    func testAReplyThatSpokeNothingStillFinishesWhenTheStreamEnds() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        XCTAssertEqual(q.endOfReply(),
                       SpeakingQueue.Effects(unduck: false, finishedReply: true),
                       "a reply of nothing but a code fence must still end the turn")
    }

    /// Reported once, not once per callback: a duplicate `endOfReply` (the consumer
    /// seeing `isStreaming` go false twice) must not move the session twice.
    func testTheReplyFinishesExactlyOnce() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let t = q.enqueue()!.ticket
        _ = q.endOfReply()
        XCTAssertTrue(q.finishedOne(t).finishedReply)
        XCTAssertFalse(q.endOfReply().finishedReply, "reported the same reply twice")
        XCTAssertFalse(q.finishedOne(t).finishedReply, "a repeated callback reported again")
    }

    // MARK: - I3: barge-in is a latch

    /// The founder interrupts, but the server reply is still streaming and the
    /// consumer keeps offering sentences. Refusing them has to happen HERE — if it
    /// depends on the surface breaking its own loop, the founder gets ~200ms of
    /// silence and then the pet talks over her again.
    func testEnqueueAfterAStopIsRefusedUntilTheNextReply() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        XCTAssertNotNil(q.enqueue())
        _ = q.stop()
        XCTAssertFalse(q.accepts)
        XCTAssertNil(q.enqueue(), "the pet resumed on the next sentence after barge-in")
        XCTAssertNil(q.enqueue())

        _ = q.beginReply()
        XCTAssertNotNil(q.enqueue(), "the latch never reopened, so the next reply is mute")
    }

    /// After barge-in the session has already left `.speaking` on
    /// `.founderInterrupted`. The stream then ending must not also report finished.
    func testTheStreamEndingAfterBargeInReportsNothing() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()
        _ = q.stop()
        XCTAssertEqual(q.endOfReply(), SpeakingQueue.Effects())
    }

    // MARK: - I4: a callback belongs to an utterance, not to a counter

    /// `stopSpeaking(at:)` returns NO when nothing is speaking yet — the window
    /// between `speak` and synthesis starting — so the cancel for the abandoned
    /// reply arrives AFTER the next reply has begun. A counter would decrement the
    /// new reply to zero and report a drain that has not happened.
    func testAStaleCallbackFromAnAbandonedReplyIsIgnored() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let stale = q.enqueue()!.ticket
        _ = q.stop()

        _ = q.beginReply()
        let live = q.enqueue()!.ticket
        XCTAssertEqual(q.endOfReply(), SpeakingQueue.Effects())

        XCTAssertEqual(q.finishedOne(stale), SpeakingQueue.Effects(),
                       "a cancel from the interrupted reply ended the new one")
        XCTAssertTrue(q.isSpeaking, "the new reply's sentence was counted as done")
        XCTAssertTrue(q.finishedOne(live).finishedReply)
    }

    /// The same hazard without a stop: `beginReply` abandons whatever the previous
    /// reply left outstanding.
    func testBeginReplyAbandonsThePreviousReplysOutstandingWork() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let stale = q.enqueue()!.ticket
        _ = q.beginReply()
        XCTAssertFalse(q.isSpeaking)
        _ = q.enqueue()
        _ = q.endOfReply()
        XCTAssertEqual(q.finishedOne(stale), SpeakingQueue.Effects())
    }

    // MARK: - I2: the SFX volume is restored exactly once

    /// One duck per reply, not one per sentence, so there is exactly one volume to
    /// restore and no flapping across the gaps between sentences.
    func testOnlyTheFirstSentenceOfAReplyDucks() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        XCTAssertEqual(q.enqueue()?.shouldDuck, true)
        XCTAssertEqual(q.enqueue()?.shouldDuck, false)
        XCTAssertTrue(q.isDucked)
    }

    /// An interrupted reply hands the volume back — once. Restoring twice writes a
    /// stale volume over whatever a later reply ducked from.
    func testAnInterruptedReplyRestoresTheVolumeExactlyOnce() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()
        let stale = q.enqueue()!.ticket
        XCTAssertEqual(q.stop(), SpeakingQueue.Effects(unduck: true, finishedReply: false))
        XCTAssertFalse(q.isDucked)
        XCTAssertFalse(q.stop().unduck, "a second stop restored the volume again")
        XCTAssertFalse(q.finishedOne(stale).unduck,
                       "a late callback restored the volume again")
    }

    /// A reply that nothing ever ducked for must not restore a volume it never took.
    func testAReplyThatSpokeNothingDoesNotRestoreAVolume() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        XCTAssertFalse(q.endOfReply().unduck)
        XCTAssertFalse(q.stop().unduck)
    }

    /// A clean finish restores it too — the duck must not survive the reply.
    func testACleanFinishRestoresTheVolume() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let t = q.enqueue()!.ticket
        _ = q.endOfReply()
        XCTAssertEqual(q.finishedOne(t),
                       SpeakingQueue.Effects(unduck: true, finishedReply: true))
        XCTAssertFalse(q.isDucked)
    }

    // MARK: - R4: a stalled reply must not leave the SFX ducked for the session

    /// The normal path. The drain already handed the volume back, so beginning the
    /// next reply must not hand it back again — that writes a stale volume over
    /// whatever the new reply is about to duck from, and it is what makes "restore
    /// exactly once" untrue by construction.
    func testANormalBeginReplyDoesNotUnduck() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        let t = q.enqueue()!.ticket
        _ = q.endOfReply()
        XCTAssertTrue(q.finishedOne(t).unduck)
        XCTAssertEqual(q.beginReply(), SpeakingQueue.Effects(),
                       "the next reply flapped the SFX volume")
    }

    /// **`didFinish` never arrives** — AirPods disconnecting mid-sentence, an audio
    /// device change, a synthesis stall. `live` stays non-empty forever, so
    /// `endOfReply()` never drains and the duck is never released. Left there, every
    /// later reply sees `ducked == true`, is told `shouldDuck: false`, and the sound
    /// effects stay at zero for the rest of the session, recoverable only by a
    /// barge-in or by quitting the app. Releasing it as the next reply begins bounds
    /// the damage to the one reply that stalled.
    func testABeginReplyAfterAStalledReplyUnducks() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        XCTAssertEqual(q.enqueue()?.shouldDuck, true)
        XCTAssertEqual(q.endOfReply(), SpeakingQueue.Effects(),
                       "a sentence is still outstanding, so the reply is not over")
        XCTAssertTrue(q.isDucked)

        XCTAssertEqual(q.beginReply(), SpeakingQueue.Effects(unduck: true),
                       "the stuck duck survived into the next reply")
        XCTAssertFalse(q.isDucked)
        XCTAssertEqual(q.enqueue()?.shouldDuck, true,
                       "the new reply could not duck, so the SFX stay at zero")
    }

    // MARK: - R2: an armed stop-retry belongs to the barge-in that armed it

    /// **The silent reply.** `stopSpeaking(at:)` answers NO in the window between
    /// `speak()` and synthesis starting, so the barge-in owes a retry. Reply B then
    /// arrives and is enqueued. While this flag lived on the audio class, nothing
    /// cleared it, and it fired on reply B's first delegate callback —
    /// `AVSpeechSynthesis.h`: `stopSpeaking` "clears the queue". So **reply B was
    /// spoken silently in its entirety**: the pet said nothing, the session cleanly
    /// reported the reply finished, and hands-free the founder got no audio and no
    /// error. Nothing logged.
    func testARetryArmedDuringReplyAMustNotFireDuringReplyB() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()          // reply A's sentence, already handed to speak()
        _ = q.stop()             // the founder interrupts
        q.armStopRetry()         // ...and the framework answered NO

        _ = q.beginReply()       // reply B
        _ = q.enqueue()
        XCTAssertFalse(q.takeStopRetry(),
                       "reply B's utterance was cancelled by reply A's stale retry")
    }

    /// It still has to work for the barge-in that armed it, or I4's window is
    /// unguarded and the interrupted sentence is spoken in full.
    func testTheRetryFiresOnceWhileTheLatchIsStillClosed() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()
        _ = q.stop()
        q.armStopRetry()
        XCTAssertTrue(q.takeStopRetry(), "the interrupted sentence was never stopped")
        XCTAssertFalse(q.takeStopRetry(), "the retry fired a second time")
    }

    /// Half one of the two defences, on its own: **the latch gate.** A retry may
    /// only fire while nothing is being accepted, because firing it into an
    /// accepting queue clears that queue's utterances.
    func testARetryArmedWithoutABargeInNeverFires() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()
        q.armStopRetry()         // no stop() — the latch is open
        XCTAssertFalse(q.takeStopRetry(),
                       "a retry fired into an accepting queue and cleared its work")
    }

    /// Half two, on its own: **the next reply disarms it.** The gate cannot cover
    /// this — a second barge-in closes the latch again, and the stale arming from
    /// the first reply would then be spent cancelling this reply's work.
    func testAnArmingFromAPreviousReplyIsDisarmed() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.stop()
        q.armStopRetry()

        _ = q.beginReply()
        _ = q.enqueue()
        _ = q.stop()             // a second barge-in: latch closed, nothing owed
        XCTAssertFalse(q.takeStopRetry(),
                       "an arming from a previous reply survived into this one")
    }

    // MARK: - I7: isSpeaking is the queue, and the fake agrees with production

    /// `SpeechSpeaker.isSpeaking` used to be `synth.isSpeaking`, which is
    /// asynchronous — very likely false immediately after `speak()`. Reporting the
    /// queue instead is what makes an assertion against a fake mean anything.
    func testIsSpeakingFollowsTheQueueAndNotTheSynthesiser() {
        var q = SpeakingQueue()
        XCTAssertFalse(q.isSpeaking)
        _ = q.beginReply()
        let t = q.enqueue()!.ticket
        XCTAssertTrue(q.isSpeaking, "a sentence was handed over and nothing is speaking")
        XCTAssertEqual(q.outstanding, 1)
        _ = q.finishedOne(t)
        XCTAssertFalse(q.isSpeaking)
    }

    func testStopEndsSpeakingImmediately() {
        var q = SpeakingQueue()
        _ = q.beginReply()
        _ = q.enqueue()
        _ = q.enqueue()
        _ = q.stop()
        XCTAssertFalse(q.isSpeaking)
        XCTAssertEqual(q.outstanding, 0)
    }

    // MARK: - the whole reply, in order

    /// Three sentences arriving with a gap in the middle, spoken, and reported once.
    func testAWholeReplyFromFirstSentenceToFinished() {
        var q = SpeakingQueue()
        var ducks = 0
        var unducks = 0
        var finished = 0
        func apply(_ e: SpeakingQueue.Effects) {
            if e.unduck { unducks += 1 }
            if e.finishedReply { finished += 1 }
        }

        _ = q.beginReply()
        var live: [SpeakingQueue.Ticket] = []
        for _ in 0..<3 {
            let a = q.enqueue()!
            if a.shouldDuck { ducks += 1 }
            live.append(a.ticket)
            // Each one finishes before the next arrives — the slow-stream case.
            apply(q.finishedOne(live.removeFirst()))
        }
        XCTAssertEqual(finished, 0, "the reply finished three times over, mid-stream")
        apply(q.endOfReply())
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(ducks, 1)
        XCTAssertEqual(unducks, 1)
    }
}
