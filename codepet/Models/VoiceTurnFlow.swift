// codepet/Models/VoiceTurnFlow.swift
import Foundation

/// **The five rules a voice surface has to keep, and the reason they are not in the
/// surface.**
///
/// These were statics on `VoiceModeOverlay` until 22 Aug, when spec §2 decision 2 was
/// reversed and the takeover was replaced by the in-composer surface
/// (`VoiceComposer`). Every body and every signature below is unchanged by that move —
/// which is the payoff for six review rounds spent pushing logic out of a `View`: the
/// surface was rewritten and not one of these rules had to be re-derived, re-argued,
/// or re-tested. They take their collaborators explicitly for exactly this reason, so
/// they are surface-agnostic, and `SpeechFakesTests` drives all of them without a
/// microphone.
///
/// **They live in `Models/` rather than beside the view on purpose.** The previous home
/// was deleted; a rule whose home can be deleted by a surface change is a rule that
/// gets re-derived by whoever writes the next surface. Each one below fails SILENTLY
/// when it is dropped — no throw, no log, a green suite — so the failure mode is
/// written at the call site rather than listed once at the top of a file, because a
/// list at the top of a file is what someone deletes a call under.
enum VoiceTurnFlow {

    // MARK: - ✓

    /// Whether ✓ can take the turn. **Three ways a tap could send nothing, and each
    /// one fails silently.**
    ///
    /// 1. An empty transcript. `sendChat` drops an empty string, so the tap would
    ///    look like a dead button, and spec §5 says ✓ is disabled while the transcript
    ///    is empty rather than merely inert.
    /// 2. Not `.listening`. There is no turn to take while the pet is thinking or
    ///    talking, and `.founderSentTurn` is refused from those states anyway — but a
    ///    tap that quietly does nothing is worse than a control that shows it cannot.
    /// 3. A turn already in flight. `sendMessage` early-returns on its own
    ///    `guard !isCompanionTyping, !isStreaming`, which is reachable here: barge-in
    ///    returns to `.listening` while the interrupted reply is still streaming. The
    ///    old 4Hz watcher answered this by waiting a tick and sending later; a tap has
    ///    no next tick, so the button is disabled instead and her transcript is left
    ///    intact until the stream ends and ✓ lights up again.
    ///
    /// Extracted rather than written inline in `.disabled`, for the same reason as
    /// `VoicePermission.canEnterVoiceMode(_:isBusy:)`: a control that is enabled one
    /// moment too early looks exactly like a control that is right.
    static func canTakeTurn(partial: String, state: VoiceState, isBusy: Bool) -> Bool {
        guard state == .listening, !isBusy else { return false }
        return !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ✓, everything but the network call — **and the order is the point.**
    ///
    /// Returns the text to send, or `nil` when there was nothing to take. Static, and
    /// taking its collaborators, because two of this feature's five invariants live in
    /// these six lines (`voice.beginReply()` before any enqueue, `listener.endTurn()`
    /// at the send site) and both fail silently: a reply that skips its first sentence,
    /// and a question sent with the previous question glued to its front. Inside a
    /// `View`'s private method no test can reach either.
    ///
    /// `sendChat` itself stays in the view: it needs the store and the language, and
    /// the credit count must only move once the send has actually happened.
    static func takeTurn(partial: String,
                         session: inout VoiceSession,
                         listener: SpeechListening,
                         voice: SpeakingVoice,
                         driver: inout VoiceReplyDriver,
                         isBusy: Bool) -> String? {
        guard canTakeTurn(partial: partial, state: session.state, isBusy: isBusy) else {
            return nil
        }
        // A new reply starts from its first sentence. Without this the splitter's
        // count still stands against the PREVIOUS reply and the new one's opening
        // sentences are skipped as already spoken.
        driver.reset()
        // **Reopens the barge-in latch before anything is enqueued.** Also here
        // rather than only in `speak` because `endOfReply` on a queue that already
        // reported its previous reply finished is a no-op — a reply with nothing
        // speakable would then never fire `onFinishedAll` and the surface would hang
        // in `.thinking`.
        voice.beginReply()
        // Retire the recognition request. See the protocol's note: without this the
        // next question arrives with this one glued to its front.
        listener.endTurn()
        // The waveform stops tracking level and flattens, so she can see the turn was
        // taken.
        session.apply(.founderSentTurn)
        return partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ✕

    /// ✕. **Both copies of what she said, not just ours.**
    ///
    /// The live `SFSpeechAudioBufferRecognitionRequest` transcribes every buffer ever
    /// appended to it and the listener keeps running across turns, so a discard that
    /// cleared only `partial` would hand the *next* partial back the discarded
    /// sentence with the new words appended — and that is the sentence ✕ exists to
    /// stop. The words §7 predicts will be mangled ("Codepet", "byte", "nova", pet and
    /// department names) would come straight back and get sent at 0.25 credits.
    /// `endTurn()`'s own contract covers this: "sent as a message, or abandoned".
    ///
    /// No session event: ✕ leaves the state at `.listening`, which is what "keeps
    /// listening" means, so the machine's shape is untouched.
    static func abandonTurn(_ listener: SpeechListening) {
        listener.endTurn()
    }

    // MARK: - The reply ending

    /// **The reply is over.** Steps the machine, hands back the transcript that must
    /// still be on screen, and makes "Listening" true again.
    ///
    /// Static and taking its collaborators for the same reason as `takeTurn` and
    /// `ensureListening`: this runs inside `voice.onFinishedAll`, and a SwiftUI
    /// closure is unreachable from `ImageRenderer`, which fires no lifecycle hooks.
    /// Every rule below fails silently, and one of them shipped.
    ///
    /// 1. **`.replyBegan` first, from `.thinking`.** A reply with nothing speakable —
    ///    an answer that is only a fenced code block, which
    ///    `SentenceSplitter.speakable` deletes entirely — never reached `.speaking`,
    ///    and `.replyFinished` is not legal from `.thinking`. Without the step the
    ///    surface hangs in `.thinking` with the turn taken, the mic shut, and nothing
    ///    to wait for.
    /// 2. **The mic may have died during the reply.** See `VoiceComposer.wire()`'s
    ///    `onFailure` `.speaking` branch: a recognition failure raised while the pet
    ///    spoke is deliberately not shown, and `SpeechListener` has already torn itself
    ///    down by then. This is the transition that makes the placeholder say
    ///    "Listening", so it is where that has to become true again. It throws rather
    ///    than swallowing a refusal, so the caller can show it.
    /// 3. **`pending` comes back unchanged, and that deletion is the fix.** This used
    ///    to be `partial = ""`, and the sequence it destroyed is ordinary: she asks
    ///    Q1 and taps ✓, then while the pet is thinking she adds "and check the
    ///    runway". `onPartial` fires — the state is `.thinking`, not `.speaking`, so
    ///    this is **not** barge-in — and `partial` and `TurnTranscript` both hold that
    ///    sentence. The reply arrives, she listens to it in silence, the reply drains,
    ///    and the clear erased it. **And nothing can bring it back:**
    ///    `recognitionUpdate` calls `onPartial` only when `TurnTranscript.update`
    ///    returns true, and the live request re-reporting the identical string is not
    ///    a change — so the sentence is off screen with ✓ disabled, and the next words
    ///    she says resurrect the whole thing glued to their front, one tap from being
    ///    sent. Those are the two failures `streamEndBelongsToVoiceTurn` and ✕'s own
    ///    `endTurn()` exist to prevent, reached from inside a legitimate voice turn.
    ///
    ///    The clear was redundant everywhere else, which is why deleting it is safe
    ///    rather than a trade. `.founderSentTurn` is the only way into `.thinking` and
    ///    it is applied at exactly one production site — `takeTurn`, from the ✓ handler,
    ///    which clears `partial` on the next line — and the ✕ handler clears after
    ///    `abandonTurn`. So `partial` is already empty on every path where the turn was
    ///    taken or dropped, and the only words this could ever destroy are ones spoken
    ///    *after* that. Barge-in cannot reach here either: `SpeakingQueue.stop()` sets
    ///    `reported = true`, so an interrupted reply never reports finished.
    ///
    ///    **Not `listener.endTurn()` either**, which review proposed alongside. That
    ///    discards her words deliberately instead of accidentally — the same loss with
    ///    a clear conscience.
    @discardableResult
    static func replyEnded(session: inout VoiceSession,
                           pending: String,
                           listener: SpeechListening) throws -> String {
        if session.state == .thinking { session.apply(.replyBegan) }
        session.apply(.replyFinished)
        try ensureListening(listener, state: session.state)
        return pending
    }

    /// **The microphone is alive whenever the surface claims to be listening.**
    ///
    /// A recognition failure raised while the pet was speaking is deliberately not
    /// shown (see `VoiceComposer.wire()`) — but `SpeechListener` has already fully torn
    /// itself down by then, and nothing else ever calls `start()` a second time.
    /// Without this the surface returns to `.listening`, the placeholder says so, and
    /// the founder talks into a dead microphone for the rest of the session with no
    /// error on screen.
    ///
    /// Static and taking the state explicitly so the rule is reachable from a test:
    /// everything inside a `View`'s private closures is not. Returns whether it
    /// actually restarted, so a test can tell "was already running" from "did nothing".
    @discardableResult
    static func ensureListening(_ listener: SpeechListening, state: VoiceState) throws -> Bool {
        // Only `.listening` makes the promise. `.speaking` deliberately tolerates a
        // dead request, and in `.idle`/`.thinking` the surface claims nothing.
        guard state == .listening else { return false }
        // `isRunning` rather than a flag set by `onFailure`: it is the same fact, it
        // is already on the protocol, and a second copy of it is one more thing that
        // can disagree with the listener about whether the listener is running.
        guard !listener.isRunning else { return false }
        try listener.start()
        return true
    }

    /// Whether `isStreaming` going false is the end of a reply **this surface asked
    /// for**. Only `.thinking` and `.speaking` follow a `beginReply()`.
    ///
    /// Extracted so it can be tested: its failure is silent — the reply-end path run
    /// against a reply that was never this surface's — and every other line of
    /// `VoiceComposer.replyStreamEnded` is unreachable from a test. It cost an erased
    /// question until `replyEnded` stopped clearing the transcript; what it costs now
    /// is written out at the call site, and it is still not nothing.
    static func streamEndBelongsToVoiceTurn(_ state: VoiceState) -> Bool {
        state == .thinking || state == .speaking
    }
}
