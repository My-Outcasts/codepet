// codepet/Models/VoiceTurn.swift
import SwiftUI
import os

/// **One voice-mode session's state, and the reason it does not live in the surface
/// that renders it.**
///
/// The takeover this replaced hung off `.overlay { }` **outside** the transcript
/// branch, so it survived every change of what the pane was showing. The composer slot
/// does not: `CopilotChatView` renders it from inside a three-way `if/else` on
/// `showHistory` / `chatMessages.isEmpty` / else, and **different branches of an
/// `if/else` are different structural identities, so `@State` is not carried across
/// them.**
///
/// That is not an exotic path — it is the first spoken turn of every thread.
/// `CompanyStore.sendMessage` appends the founder's own message **synchronously, before
/// its first await**, so `chatMessages.isEmpty` flips false while ✓ is still under her
/// finger. With the state in the view, the `VoiceComposer` that took the turn was torn
/// down at `.thinking` and a fresh one was built at `.idle`: `speak()` then refused the
/// reply (it guards on `.thinking || .speaking`), `replyStreamEnded()` returned early
/// (`streamEndBelongsToVoiceTurn(.listening)` is false), and the `SpeakingQueue` latch
/// stayed shut because only `beginReply()` reopens it and that reply's `beginReply()`
/// had already happened. **The question was sent and charged, the reply arrived as
/// text, and the pet said nothing** — no error, no log, green suite. The credit count
/// reset to `~0 credits` on the very turn she was billed for.
///
/// So the state is held by `CopilotChatView` — which is above the `if/else` and above
/// `showHistory` — and handed down as one `@Binding`. `VoiceComposer` owns no turn
/// state at all, and a branch flip re-renders it without resetting it.
///
/// **One binding rather than five.** `session`/`partial`/`level`/`failure`/`driver`
/// are one session's worth of state and are reset together; five separate `@State`s
/// on `CopilotChatView` would be five things a future reset could forget one of. The
/// failure of forgetting one is silent in every case.
///
/// **The methods are here, not on the view, for the same reason `VoiceTurnFlow`'s are
/// not.** Two of them carry invariants 1 and 2, and both are now reached from
/// `CopilotChatView` (the reply observations had to move up with the state — see
/// `speak` and `replyStreamEnded`) *and* from `VoiceComposer`'s buttons. A rule that
/// lived in one of those two views would have to be re-derived by the other.
struct VoiceTurn {

    /// Where the conversation is — spec §4.
    var session = VoiceSession()
    /// What recognition has heard this turn. Shown because a founder who cannot see
    /// what was heard will not trust the reply (spec §4).
    var partial = ""
    /// Mic (listening) or output (speaking) level, 0…1, for the waveform.
    var level: Float = 0
    /// Recognition died after `start()` returned. Takes the text slot — see
    /// `VoiceChrome.line`.
    var failure: Error?
    var driver = VoiceReplyDriver()

    /// Whether the microphone has been opened for **this** voice-mode session.
    ///
    /// **The one piece of state that exists because of the hoist.** `VoiceComposer`'s
    /// `.task` still opens the mic — it has to, because the composer must be on screen
    /// showing `Connecting…` while the engine spins up — but that `.task` now runs
    /// again on every structural rebuild (the branch flip, and every time the History
    /// panel is closed). Without this flag the second run would call `listener.start()`
    /// on a listener that is already running and `session.apply(.open)` on a `.thinking`
    /// session; `.open` is refused from `.thinking` so the state would survive, but the
    /// microphone would be restarted mid-turn — losing the transcript the live
    /// `SFSpeechAudioBufferRecognitionRequest` was holding, with nothing on screen
    /// saying so.
    ///
    /// Set **before** `start()` is attempted, so a fatal start failure is not retried
    /// once per rebuild.
    ///
    /// This is why a fresh `VoiceTurn()` per voice-mode session is load-bearing rather
    /// than tidiness: a session that inherited `micOpened == true` would never open its
    /// microphone and would sit in `Connecting…` forever. See
    /// `CopilotChatView.startVoiceMode()` and its `.onChange(of: voiceMode)`.
    var micOpened = false

    init() {}
}

// MARK: - Lifecycle

extension VoiceTurn {

    /// Open the microphone, once per voice-mode session.
    ///
    /// The failure is SHOWN, not swallowed, and the composer stays expanded to show it.
    /// The state stays `.idle`, which is what puts `Cancel` under it — see
    /// `VoiceChrome.controls(for:)`.
    mutating func openMic(_ listener: SpeechListening) {
        // **`micOpened` is logged, because a second run of the composer's `.task` looks
        // exactly like the first from outside.** A branch flip and a closed History panel
        // both re-run it, and `skipped=true` here is the correct answer to both — but it
        // is also what a session that wrongly inherited the flag would report, and that
        // one sits in `Connecting…` forever.
        //
        // Read into locals first: `Logger`'s message is built through an escaping
        // autoclosure, which a `mutating func` may not capture `self` into.
        let wasOpened = micOpened
        let stateBefore = String(describing: session.state)
        VoiceLog.surface.log("""
            openMic(): micOpened=\(wasOpened, privacy: .public) \
            state=\(stateBefore, privacy: .public)
            """)
        guard !micOpened else { return }
        micOpened = true
        do {
            try listener.start()
        } catch {
            VoiceLog.surface.error("""
                openMic(): listener.start() THREW \(VoiceLog.describe(error), privacy: .public) \
                — staying .idle and showing it
                """)
            failure = error
            return
        }
        session.apply(.open)
        let stateAfter = String(describing: session.state)
        VoiceLog.surface.log("openMic(): started — state=\(stateAfter, privacy: .public)")
    }

    /// **Installs the listener's three callbacks and the voice's completion, against
    /// the hoisted state.**
    ///
    /// Takes a `Binding` rather than being `mutating` because every one of these is an
    /// escaping closure that outlives the call. A binding derived from
    /// `CopilotChatView`'s `@State` writes through to that view's storage, so the
    /// closures keep working after the `VoiceComposer` instance that installed them has
    /// been torn down by a branch flip — which is the whole point of the hoist. The
    /// re-wire on the next instance's `.task` is therefore belt-and-braces, not
    /// load-bearing.
    ///
    /// Each closure takes a local copy, mutates it, and writes it back once. Reading
    /// one member of `turn.wrappedValue` while another is held `inout` is an overlapping
    /// access to a computed property, which traps at runtime rather than at compile
    /// time.
    static func wire(_ turn: Binding<VoiceTurn>,
                     listener: SpeechListening,
                     voice: SpeakingVoice) {
        // Remember the text and — while the pet is talking — treat any speech as
        // barge-in. The listener only calls this when the transcript actually CHANGED
        // (see `TurnTranscript.update`), so a recognizer re-reporting a string it
        // already reported cannot cut the pet off with words she has already had
        // answered.
        listener.onPartial = { text in
            var t = turn.wrappedValue
            t.partial = text
            if t.session.state == .speaking {
                voice.stopImmediately()
                t.session.apply(.founderInterrupted)
            }
            turn.wrappedValue = t
        }

        listener.onLevel = { level in turn.wrappedValue.level = level }

        // Recognition died AFTER start() returned — permission revoked, the service
        // went away, or (vi-VN is server-side) the network dropped.
        // `SFSpeechRecognizer.isAvailable` reports SERVICE availability, not
        // authorisation, so a clean `start()` is no promise that a word will ever
        // arrive. Unshown, the founder watches a composer that says "Listening…" and
        // hears nothing.
        listener.onFailure = { error in
            // **A failure while the pet is speaking is expected, not fatal.** Voice
            // processing cancels the pet's own audio out of the microphone — that is
            // what makes barge-in possible — so a recognition request opened at a
            // turn boundary and left running while the founder merely LISTENS hears
            // genuine silence. A buffer task that self-terminates on silence
            // (`kAFAssistantErrorDomain`, "no speech detected") then dies through no
            // fault of hers, renews, dies again, and exhausts `RenewalBudget`.
            // Closing on that would shut voice mode down mid-answer.
            //
            // The guard CAN fire because the listener stays running through
            // `.speaking` on purpose: barge-in needs the mic open while the pet talks.
            // Every other state is a real failure and must be shown.
            //
            // **But the listener is already dead by the time this runs.** `endOfTask`'s
            // `.fail` branch calls `stop()` *before* `onFailure?(error)` — tap removed,
            // voice processing off, engine stopped, `isRunning == false` — and nothing
            // ever restarts it: `start()` is called once, from `openMic`, and
            // `endTurn()` early-returns on `guard isRunning`. So a long reply whose own
            // audio the voice processing cancels out of the mic exhausts
            // `RenewalBudget` on genuine silence, falls through here, and leaves the
            // founder in a `.listening` composer reading "Listening…" with the bars
            // flat — talking to a microphone that is gone, with nothing shown and
            // nothing logged.
            //
            // Still return, and still show nothing: closing mid-answer is wrong, and
            // restarting *here* re-enters the same silence-death loop and churns the
            // engine for the whole reply. `VoiceTurnFlow.ensureListening` picks it up on
            // the way back to `.listening`, which is the first moment this surface
            // claims the microphone is live.
            // **Both outcomes, because the suppressed one is a silent surface by design
            // and a silent surface is what is being chased.** Suppressed-while-speaking
            // is correct and leaves nothing on screen; shown is the channel doing its
            // job. Without the first line, "onFailure never fired" and "onFailure fired
            // and was deliberately swallowed" are the same trace.
            let suppressed = turn.wrappedValue.session.state == .speaking
            VoiceLog.surface.log("""
                onFailure: \(suppressed ? "SUPPRESSED (speaking)" : "showing", privacy: .public) \
                — \(VoiceLog.describe(error), privacy: .public)
                """)
            guard !suppressed else { return }
            listener.stop()
            var t = turn.wrappedValue
            t.failure = error
            t.session.apply(.close)
            turn.wrappedValue = t
        }

        // The reply is over: drained AND `endOfReply()` was called.
        voice.onFinishedAll = {
            var t = turn.wrappedValue
            // The bars stop tracking anything. `onLevel` is what feeds them and the tap
            // fires ~10 times a second, so this is one frame of honesty and not a
            // latched value — which is why it is here and not inside `replyEnded`,
            // where a returned constant asserted against its own literal would be a
            // test that cannot fail.
            t.level = 0
            // Everything else — the stepping, the mic, and what must survive — is in
            // `VoiceTurnFlow.replyEnded`, which a test can drive. Only the failure path
            // stays here, because it writes `failure`.
            do {
                let pending = t.partial
                t.partial = try VoiceTurnFlow.replyEnded(session: &t.session,
                                                         pending: pending,
                                                         listener: listener)
            } catch {
                // The restart itself refused — that is a real, fatal failure, and it
                // takes the normal path rather than being swallowed a second time.
                listener.stop()
                t.failure = error
                t.session.apply(.close)
            }
            turn.wrappedValue = t
        }
    }

    /// Leaving voice mode. **`stopImmediately()` first, then collapse.** Without it the
    /// pet keeps talking to a composer that is gone, with the chiptune SFX still ducked
    /// to zero for the rest of the process.
    ///
    /// **Invariant 4's other half is not here.** ⌘B and the Developer pill remove the
    /// whole chat pane without anything calling this, so the teardown for that case
    /// lives on `CopilotChatView`'s `.onDisappear` — the view whose disappearance
    /// actually means "the surface is gone". `VoiceComposer` deliberately has no
    /// `.onDisappear`: its disappearance is also what a branch flip and an open History
    /// panel look like, and stopping the microphone on those was the second half of the
    /// defect this hoist fixes.
    mutating func leave(listener: SpeechListening, voice: SpeakingVoice) {
        voice.stopImmediately()
        listener.stop()
        session.apply(.close)
    }
}

// MARK: - The founder's turn

extension VoiceTurn {

    /// ✓: take the turn. Returns the text to send, or `nil` when there was nothing to
    /// take.
    ///
    /// Two of this feature's five invariants live inside `VoiceTurnFlow.takeTurn` —
    /// `voice.beginReply()` before any enqueue, `listener.endTurn()` at the send site —
    /// and this only adds the two clears that belong to the surface.
    mutating func take(listener: SpeechListening,
                       voice: SpeakingVoice,
                       isBusy: Bool) -> String? {
        guard let toSend = VoiceTurnFlow.takeTurn(partial: partial, session: &session,
                                                  listener: listener, voice: voice,
                                                  driver: &driver, isBusy: isBusy)
        else { return nil }
        partial = ""
        level = 0
        return toSend
    }

    /// ✕. No credit is spent.
    mutating func discard(listener: SpeechListening) {
        VoiceTurnFlow.abandonTurn(listener)
        partial = ""
        level = 0
    }

    // `canSend(isBusy:)` lived here until 22 Aug: a one-line pass-through to
    // `VoiceTurnFlow.canTakeTurn`, read only by `VoiceComposer`'s ✓. It is gone because
    // ✓ now shares one enablement expression with its ⌘⏎ hotkey — see
    // `VoiceHotkey.isEnabled` and `VoiceComposer.isEnabled(_:)`. Two names for one rule
    // is how a hotkey ends up gated on a different fact than the button it is printed on.
}

// MARK: - Speaking the reply

extension VoiceTurn {

    /// Feeds the driver and enqueues what comes back.
    ///
    /// Called from two `.onChange`es on **`CopilotChatView`'s** body: the growing reply
    /// text, and `isStreaming` going false. They were on `VoiceComposer`'s body, which
    /// is where they could be lost — a branch flip re-arms an `.onChange` with the
    /// current value as its "old" value, and the History panel removes the composer
    /// (and therefore both observations) entirely while a reply is being spoken, so
    /// `endOfReply()` would never be called and the session would hang in `.speaking`
    /// with the queue never reporting. `CopilotChatView` is above both.
    mutating func speak(_ text: String, streaming: Bool,
                        as profile: VoiceProfile, voice: SpeakingVoice) {
        guard session.state == .thinking || session.state == .speaking else {
            // `.listening` here is barge-in: the stream is still arriving and this is
            // still being called, and the rest of the interrupted reply must stay
            // unspoken. (`SpeakingQueue`'s latch would refuse it too; not relying on
            // one of the two is deliberate.)
            return
        }
        let sentences = driver.sentencesToSpeak(replyText: text, isStreaming: streaming)
        // Nothing speakable yet is ordinary — mid-sentence, or a fenced code block
        // that `speakable` deletes entirely. It is not the reply beginning.
        guard !sentences.isEmpty else { return }
        for sentence in sentences {
            voice.enqueue(sentence, profile: profile)
        }
        // Applied AFTER the enqueues, which is why `beginReply()` cannot be hung off
        // this event: `.replyBegan` is what moves `.thinking` → `.speaking`, so
        // "call beginReply on .replyBegan" reopens the latch one sentence too late
        // and drops sentence 1 of every post-barge-in reply.
        session.apply(.replyBegan)
    }

    /// `isStreaming` went false. **Flush, then `endOfReply()`.**
    ///
    /// The flush is the only thing that releases the reply's last sentence: `take`
    /// refuses a terminator that is merely the last character currently available,
    /// because mid-stream `"The price is $3."` is both a complete sentence and the
    /// first half of `"$3.14 today."`. Omit it and every reply loses its last
    /// sentence — with no exception and no log.
    ///
    /// `endOfReply()` is what lets `onFinishedAll` ever fire. It is NOT inferable
    /// from the queue draining: `speakable` deletes fenced code blocks entirely, so a
    /// 50-line snippet is 5–15 seconds with nothing to say. Treat that drain as the
    /// end and the composer reopens the mic and drops the bars to zero mid-reply, while
    /// the real reply is still arriving — and the session takes `.replyFinished`, which
    /// leaves `.speaking`, so the *rest* of the reply is then spoken from `.listening`,
    /// which `speak()` refuses outright: **the founder hears half an answer.**
    mutating func replyStreamEnded(_ text: String,
                                   as profile: VoiceProfile, voice: SpeakingVoice) {
        // **The stream that just ended has to be OURS.** Voice mode is openable at any
        // moment, including over a typed turn already in flight, and that seam is what
        // this guard closes:
        //
        // She sends a typed message; `isStreaming` is true. She taps the waveform —
        // the composer expands in `.listening` with no `beginReply()` behind it. She
        // speaks: `onPartial` fills `partial`, and because the state is `.listening`
        // rather than `.speaking` this is not barge-in, so the `SpeakingQueue` latch
        // never closes. `canTakeTurn`'s `isBusy` correctly holds ✓ disabled while the
        // typed reply streams, so her sentence is sitting on screen waiting for her
        // tap. Then the TYPED reply finishes, and ungated this fired `endOfReply()` on
        // a queue that had never begun a reply — and `SpeakingQueue` starts
        // `accepting = true, reported = false`, so a virgin queue drains and *reports*.
        // `onFinishedAll` then runs the whole reply-end path for a reply that was never
        // this surface's.
        //
        // **It used to erase her spoken question mid-flight** — no message, no credit
        // spent, and she had to say it all again. That half is fixed at the source:
        // `VoiceTurnFlow.replyEnded` no longer clears the transcript, and this guard is
        // no longer the only thing standing between her sentence and the bin.
        //
        // **It is still the right guard, and it still fires.** What is left ungated is
        // not cosmetic: `endOfReply()` marks the queue `reported`, `level` drops to
        // zero mid-sentence, and `ensureListening` runs against a `.listening` state it
        // was never asked about. Keeping it also means the two facts stay independent —
        // a later change that gives the reply-end path something new to reset does not
        // silently acquire this seam along with it. `VoicePermission.canEnterVoiceMode`
        // keeps her out of the situation; this keeps the situation harmless if she is
        // in it.
        //
        // **It has to stay the first line**, and the hoist made that easier to get
        // wrong rather than harder: this now runs from `CopilotChatView`, which
        // observes `isStreaming` for every typed turn too, so the guard is reached far
        // more often than it was.
        guard VoiceTurnFlow.streamEndBelongsToVoiceTurn(session.state) else { return }
        speak(text, streaming: false, as: profile, voice: voice)
        voice.endOfReply()
    }
}
