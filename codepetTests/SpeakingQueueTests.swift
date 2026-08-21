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

    /// **The credit-spending bug.** A reply streams "Here's the fix." then a fenced
    /// code block then "That should do it." `SentenceSplitter.speakable` deletes the
    /// fence entirely, so for the 5-15s it streams there are no speakable sentences
    /// and the queue is empty. If that reports finished, the overlay applies
    /// `.replyFinished`, the mic opens, the 1.2s silence timer fires on the founder
    /// saying nothing, and `sendChat` sends an empty turn and spends a credit — while
    /// the real reply is still arriving.
    func testADrainMidStreamDoesNotReportTheReplyFinished() {
        var q = SpeakingQueue()
        q.beginReply()
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
        q.beginReply()
        XCTAssertEqual(q.endOfReply(),
                       SpeakingQueue.Effects(unduck: false, finishedReply: true),
                       "a reply of nothing but a code fence must still end the turn")
    }

    /// Reported once, not once per callback: a duplicate `endOfReply` (the consumer
    /// seeing `isStreaming` go false twice) must not move the session twice.
    func testTheReplyFinishesExactlyOnce() {
        var q = SpeakingQueue()
        q.beginReply()
        let t = q.enqueue()!.ticket
        _ = q.endOfReply()
        XCTAssertTrue(q.finishedOne(t).finishedReply)
        XCTAssertFalse(q.endOfReply().finishedReply, "reported the same reply twice")
        XCTAssertFalse(q.finishedOne(t).finishedReply, "a repeated callback reported again")
    }

    // MARK: - I3: barge-in is a latch

    /// The founder interrupts, but the server reply is still streaming and the
    /// consumer keeps offering sentences. Refusing them has to happen HERE — if it
    /// depends on the overlay breaking its own loop, the founder gets ~200ms of
    /// silence and then the pet talks over her again.
    func testEnqueueAfterAStopIsRefusedUntilTheNextReply() {
        var q = SpeakingQueue()
        q.beginReply()
        XCTAssertNotNil(q.enqueue())
        _ = q.stop()
        XCTAssertFalse(q.accepts)
        XCTAssertNil(q.enqueue(), "the pet resumed on the next sentence after barge-in")
        XCTAssertNil(q.enqueue())

        q.beginReply()
        XCTAssertNotNil(q.enqueue(), "the latch never reopened, so the next reply is mute")
    }

    /// After barge-in the session has already left `.speaking` on
    /// `.founderInterrupted`. The stream then ending must not also report finished.
    func testTheStreamEndingAfterBargeInReportsNothing() {
        var q = SpeakingQueue()
        q.beginReply()
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
        q.beginReply()
        let stale = q.enqueue()!.ticket
        _ = q.stop()

        q.beginReply()
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
        q.beginReply()
        let stale = q.enqueue()!.ticket
        q.beginReply()
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
        q.beginReply()
        XCTAssertEqual(q.enqueue()?.shouldDuck, true)
        XCTAssertEqual(q.enqueue()?.shouldDuck, false)
        XCTAssertTrue(q.isDucked)
    }

    /// An interrupted reply hands the volume back — once. Restoring twice writes a
    /// stale volume over whatever a later reply ducked from.
    func testAnInterruptedReplyRestoresTheVolumeExactlyOnce() {
        var q = SpeakingQueue()
        q.beginReply()
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
        q.beginReply()
        XCTAssertFalse(q.endOfReply().unduck)
        XCTAssertFalse(q.stop().unduck)
    }

    /// A clean finish restores it too — the duck must not survive the reply.
    func testACleanFinishRestoresTheVolume() {
        var q = SpeakingQueue()
        q.beginReply()
        let t = q.enqueue()!.ticket
        _ = q.endOfReply()
        XCTAssertEqual(q.finishedOne(t),
                       SpeakingQueue.Effects(unduck: true, finishedReply: true))
        XCTAssertFalse(q.isDucked)
    }

    // MARK: - I7: isSpeaking is the queue, and the fake agrees with production

    /// `SpeechSpeaker.isSpeaking` used to be `synth.isSpeaking`, which is
    /// asynchronous — very likely false immediately after `speak()`. Reporting the
    /// queue instead is what makes an assertion against a fake mean anything.
    func testIsSpeakingFollowsTheQueueAndNotTheSynthesiser() {
        var q = SpeakingQueue()
        XCTAssertFalse(q.isSpeaking)
        q.beginReply()
        let t = q.enqueue()!.ticket
        XCTAssertTrue(q.isSpeaking, "a sentence was handed over and nothing is speaking")
        XCTAssertEqual(q.outstanding, 1)
        _ = q.finishedOne(t)
        XCTAssertFalse(q.isSpeaking)
    }

    func testStopEndsSpeakingImmediately() {
        var q = SpeakingQueue()
        q.beginReply()
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

        q.beginReply()
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
