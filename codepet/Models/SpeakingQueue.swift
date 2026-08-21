// codepet/Models/SpeakingQueue.swift
import Foundation
// NO `import AVFoundation`. Every decision in this file is bookkeeping, and all of
// it was previously buried inside `SpeechSpeaker` where no test could reach it.

/// The bookkeeping behind reading a reply aloud: what is still in flight, whether
/// the reply is genuinely over, whether the SFX are currently ducked, and whether
/// anything more may be spoken at all.
///
/// **Why this is a separate type.** Four review findings on Task 4 (C3, I2, I3, I4)
/// were all defects in these few lines, and none of them was reachable by a test
/// while they lived next to `AVSpeechSynthesizer` — which wants an audio device the
/// headless test host does not have. Extracted, every one of them is a two-line test.
///
/// **The three facts it keeps apart.**
///
/// 1. *The queue is empty* and *the reply is finished* are different things. A reply
///    streams as prose, then a fenced code block, then prose;
///    `SentenceSplitter.speakable` deletes the fence entirely, so for the 5-15s it
///    takes to stream, there are zero speakable sentences and the synthesiser runs
///    dry. Treating that as end-of-reply opens the microphone mid-reply and clears the
///    founder's transcript while the real reply is still arriving — and until decision
///    4 removed the silence timer it also sent an empty turn and spent a credit on it.
///    So a drain only reports finished once
///    `endOfReply()` has said no more sentences are coming.
/// 2. *Barge-in* is a latch, not an event. When the founder talks over the pet, the
///    server reply is still streaming and the consumer is still calling `enqueue`.
///    `stop()` closes the latch and only `beginReply()` reopens it, so the pet
///    cannot resume on the next sentence — and that is true here, in the type, and
///    not dependent on a caller remembering to break its own loop.
/// 3. *A callback belongs to one utterance*, not to a counter. `stopSpeaking(at:)`
///    returns NO when nothing is speaking yet (the window between `speak` and
///    synthesis starting), and the cancel for the abandoned reply then arrives after
///    the next reply has begun. A bare counter decrements the new reply and reports
///    a drain that has not happened. Tickets make an abandoned callback unknown, and
///    an unknown callback does nothing.
struct SpeakingQueue {

    /// One utterance handed to the synthesiser. The caller carries it back on the
    /// delegate callback so a callback from an abandoned reply is dropped rather
    /// than decrementing the reply that replaced it.
    struct Ticket: Hashable {
        fileprivate let id: Int
    }

    /// What the caller must now do to the world. Both fields are one-shot: the
    /// struct never returns `unduck` twice for one duck, which is how "restore the
    /// SFX volume exactly once" is enforced here instead of in the audio class.
    struct Effects: Equatable {
        var unduck = false
        var finishedReply = false
    }

    /// An accepted sentence. `shouldDuck` is true only for the first sentence of a
    /// duck cycle — ducking is one pair per reply, never per sentence.
    struct Accepted: Equatable {
        let ticket: Ticket
        let shouldDuck: Bool
    }

    private var nextID = 0
    /// Tickets handed out for the reply in flight and not yet reported back.
    private var live: Set<Int> = []
    /// The barge-in latch. Closed by `stop()`, reopened only by `beginReply()`.
    private var accepting = true
    /// `endOfReply()` has been called for the reply in flight.
    private var streamEnded = false
    /// `finishedReply` has already been reported for the reply in flight.
    private var reported = false
    private var ducked = false
    /// The framework's `stopSpeaking(at:)` returned NO for the barge-in that closed
    /// the latch, so a second attempt is owed. **Its lifetime belongs to that
    /// barge-in and to nothing after it** — as a bare `Bool` on the audio class it
    /// outlived the reply it was armed for and cancelled the *next* reply's
    /// utterance, which is R2: reply B spoken silently in its entirety, the session
    /// cleanly reporting it finished, nothing logged.
    private var stopRetryArmed = false

    init() {}

    /// The synthesiser has work outstanding. This — not the framework's own
    /// asynchronous `isSpeaking` — is what the speaker reports, so that a fake and
    /// the real class answer the same question the same way.
    var isSpeaking: Bool { !live.isEmpty }

    /// False between `stop()` and the next `beginReply()`.
    var accepts: Bool { accepting }

    /// True while the caller is holding the SFX volume down.
    var isDucked: Bool { ducked }

    var outstanding: Int { live.count }

    /// A new reply is starting: the latch opens, the end-of-reply flag clears, and
    /// anything the previous reply left armed is disarmed.
    ///
    /// Any ticket still outstanding is abandoned here — it belongs to the previous
    /// reply, and letting it count against this one is exactly the miscount in I4.
    ///
    /// **Returns `Effects`, and it can only ever carry `unduck`.** A reply whose
    /// `didFinish` never arrives (AirPods disconnecting mid-sentence, a device
    /// change, a synthesis stall) leaves `live` non-empty forever, so `endOfReply()`
    /// never drains and the duck is never released. Left to itself that duck then
    /// survives *every later reply* — each one sees `ducked == true`, returns
    /// `shouldDuck: false`, and the SFX stay at zero for the whole session with no
    /// recovery but `stopImmediately()` or quitting. Releasing it here bounds the
    /// damage to the one stalled reply. On the normal path the drain already
    /// released it, so this returns `Effects()` and nothing flaps — which is the
    /// other end of *not* unducking on a mid-stream drain (see `drainIfDone`).
    mutating func beginReply() -> Effects {
        live.removeAll()
        accepting = true
        streamEnded = false
        reported = false
        stopRetryArmed = false
        return releaseDuck()
    }

    /// Offer one sentence. `nil` means refused because the latch is closed — the
    /// founder interrupted and the rest of this reply must stay unspoken.
    mutating func enqueue() -> Accepted? {
        guard accepting else { return nil }
        nextID += 1
        live.insert(nextID)
        let shouldDuck = !ducked
        ducked = true
        return Accepted(ticket: Ticket(id: nextID), shouldDuck: shouldDuck)
    }

    /// No more sentences are coming for this reply. Only after this can a drain
    /// mean the reply is over — and if the whole reply was a code fence, so nothing
    /// was ever spoken, this is what reports it finished.
    ///
    /// Ignored while the latch is closed: after barge-in the session has already
    /// left `.speaking`, and reporting the abandoned reply as finished would move
    /// it again.
    mutating func endOfReply() -> Effects {
        guard accepting else { return Effects() }
        streamEnded = true
        return drainIfDone()
    }

    /// One utterance reported back — finished or cancelled, which are the same fact
    /// here. An unknown ticket is a callback from an abandoned reply: no effect.
    mutating func finishedOne(_ ticket: Ticket) -> Effects {
        guard live.remove(ticket.id) != nil else { return Effects() }
        return drainIfDone()
    }

    /// Barge-in. Closes the latch, abandons everything in flight, and hands back
    /// the volume — once, even if called twice, and even if the framework's own
    /// stop returned NO.
    mutating func stop() -> Effects {
        live.removeAll()
        accepting = false
        streamEnded = false
        // The reply is over by interruption; nothing may report it finished, or the
        // session would take a `.replyFinished` on top of `.founderInterrupted`.
        reported = true
        return releaseDuck()
    }

    /// The framework's `stopSpeaking(at:)` answered NO for the barge-in just taken:
    /// nothing was speaking yet, so there was nothing to stop, and the utterance
    /// already handed to `speak()` will start any moment. A second attempt is owed.
    ///
    /// Arm on the Bool alone. Do **not** also require the synthesiser to say it is
    /// speaking: it returned NO *because* it is not speaking, so that conjunct
    /// cancels the very case this exists for.
    mutating func armStopRetry() {
        stopRetryArmed = true
    }

    /// Consume the owed retry. True at most once per arming, and **only while the
    /// latch is still closed** — the retry calls `stopSpeaking(at:)`, which
    /// `AVSpeechSynthesis.h` says "clears the queue", so firing it once a later
    /// reply is accepting would cancel that reply's utterances instead.
    ///
    /// Consumed either way: a retry that has become irrelevant is spent, not kept.
    mutating func takeStopRetry() -> Bool {
        let armed = stopRetryArmed
        stopRetryArmed = false
        return armed && !accepting
    }

    /// The queue is empty AND the stream has ended AND we have not said so yet.
    ///
    /// Note what is NOT here: a mid-stream drain leaves the duck in place. The
    /// alternative flaps the SFX volume across every gap between sentences, and
    /// makes "restore exactly once" untrue by construction.
    private mutating func drainIfDone() -> Effects {
        guard streamEnded, live.isEmpty, !reported else { return Effects() }
        reported = true
        var effects = releaseDuck()
        effects.finishedReply = true
        return effects
    }

    private mutating func releaseDuck() -> Effects {
        guard ducked else { return Effects() }
        ducked = false
        return Effects(unduck: true, finishedReply: false)
    }
}
