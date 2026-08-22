// codepet/Services/SpeechListening.swift
import AVFoundation
import Foundation
import Speech

/// `Equatable` so a test can name which failure it means. Deliberately carries no
/// founder-facing text: Task 5/6 renders it, and chrome is bilingual.
enum VoiceAudioError: Error, Equatable {
    case recognizerUnavailable
    case engineFailed(String)
}

/// What the founder has said this turn, across however many recognition requests it
/// took to hear it.
///
/// **A turn outlives a request.** `SFSpeechRecognitionTask` has a ~1 minute audio
/// limit, so a long question is heard by two or three requests in succession and each
/// fresh one starts its transcript from empty. Nothing downstream can compensate for
/// that: a renewal is invisible from outside, so a consumer accumulating partials
/// cannot tell "the founder restarted her sentence" from "the recognizer restarted its
/// request", and the founder's long question reaches `sendChat` as only the fragment
/// after the seam — a silently truncated question, with a credit spent on it. So the
/// knowledge lives here, where the renewal happens.
///
/// Pure, and separated out for exactly the reason `SpeakingQueue` is: as inline state
/// on `SpeechListener` no test could reach it, because reaching it needs an
/// `SFSpeechRecognizer`.
struct TurnTranscript: Equatable {
    /// What requests already retired **this turn** heard, in order.
    private var committed: [String] = []
    /// The live request's transcript. Replaced wholesale, never appended to — a
    /// recognizer revises what it already said ("teh" → "the"), and a growing string
    /// is not the same thing as a growing list of words.
    private var current = ""

    /// Everything the founder has said this turn.
    ///
    /// Joined with a space. There is already a gap in the audio at each seam (see
    /// `SpeechListener.renew()`), so the two fragments are two different words far
    /// more often than they are two halves of one.
    var text: String {
        (committed + [current]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The live request revised its transcript.
    ///
    /// **Returns whether `text` actually changed**, so a caller can tell a real
    /// revision from the recognizer re-reporting a string it has already reported.
    /// That distinction is not cosmetic: while the pet is speaking the surface treats
    /// any partial as barge-in — so a repeated partial cuts the pet off with words the
    /// founder has already had answered. Not
    /// `@discardableResult` on purpose: ignoring it is a decision, not a default.
    mutating func update(_ transcript: String) -> Bool {
        let before = text
        current = transcript
        return text != before
    }

    /// The live request is being retired mid-turn: keep what it heard. An empty one
    /// contributes nothing rather than an empty fragment, so a renewal that heard
    /// silence cannot leave a stray space in the middle of the founder's sentence.
    mutating func commit() {
        if !current.isEmpty { committed.append(current) }
        current = ""
    }

    /// The turn is over — it was sent, or the microphone went away. The next turn must
    /// not inherit the previous question's words.
    mutating func endTurn() {
        committed.removeAll()
        current = ""
    }
}

/// Streams what the founder is saying.
///
/// A protocol so the suite can drive a fake — the concrete type wants a microphone,
/// which no test may touch.
protocol SpeechListening: AnyObject {
    /// The running transcript so far, called repeatedly as it grows.
    ///
    /// **Monotonic within a turn**, and it is the listener that makes it so. A
    /// recognition request lasts about a minute (`SFSpeechRecognitionTask`'s audio
    /// limit) while a turn lasts until the founder stops talking, so a long question
    /// spans several requests and each new one transcribes from empty; the listener
    /// accumulates across those renewals so this always carries the whole turn. A
    /// consumer may therefore take the latest string as the founder's message and must
    /// **not** accumulate — see `endTurn()`.
    ///
    /// Known cost, accepted rather than fixed: roughly 100-200ms of audio is dropped
    /// at each renewal seam, so a syllable can be clipped about once a minute. The
    /// alternative is two recognition tasks running on one recognizer, which is
    /// undocumented and cannot be measured without a microphone.
    var onPartial: ((String) -> Void)? { get set }
    /// Input level 0…1, for the waveform.
    var onLevel: ((Float) -> Void)? { get set }
    /// Recognition died after start() returned — permission revoked, the network
    /// dropped (vi-VN is server-side; see spec §3), the service went away. The surface
    /// must show this, because the alternative is a live-looking waveform that hears nothing.
    var onFailure: ((Error) -> Void)? { get set }
    var isRunning: Bool { get }
    /// **Whether the founder's audio stays on this Mac.** On the protocol because the
    /// surface states it as a privacy disclosure (spec §3) and the listener is the only
    /// thing that knows: it is the value handed to
    /// `SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition`.
    ///
    /// It is **not** a property of the language. The surface's line switched on `lang`
    /// alone and said flatly "Recognition runs on this Mac. Nothing you say leaves
    /// it." — so on any Mac where the en-US Assistant asset is not installed the
    /// audio went to Apple's servers while the surface said the opposite. Same shape
    /// as the `lang == .vi ? why : why` defect: a decision that inspects one input and
    /// ignores the one that determines the answer.
    var isOnDevice: Bool { get }
    func start() throws
    func stop()
    /// The founder's turn was taken — sent as a message, or abandoned. The next
    /// `onPartial` starts from empty.
    ///
    /// **The consumer has to call this, and only the consumer can.** It owns the
    /// end-of-turn decision — the founder's ✓ or ✕ — and that decision is not visible
    /// from inside the listener: recognition going quiet looks identical to the founder
    /// pausing mid-sentence, which is exactly why nothing here infers a turn from
    /// silence. Not called, the next question arrives with the previous one still glued
    /// to the front of it.
    ///
    /// **An implementation must retire the live recognition request, not merely clear
    /// its own accumulation.** `SFSpeechAudioBufferRecognitionRequest` has no reset:
    /// `bestTranscription` is the transcription of *all* audio ever appended to that
    /// request, for its whole ~1 minute life, and the listener keeps running across
    /// turns because barge-in needs the microphone open while the pet speaks. So a
    /// listener that clears only its own state hears the previous question again on the
    /// next partial and sends it — a glued question, with a credit spent on it, growing
    /// every turn for the rest of the session. Nothing throws and nothing logs. This is
    /// stated on the protocol rather than in one implementation because a fake that
    /// gets it wrong certifies a promise production does not keep.
    func endTurn()
}

/// `SFSpeechRecognizer` over our own `AVAudioEngine`.
///
/// **Its own engine, measured.** `setVoiceProcessingEnabled(true)` throws `-10849`
/// (`kAudioUnitErr_Initialized`) on a running engine, and `ChiptuneEngine` starts
/// lazily then stays running — so sharing would mean stopping the SFX engine and
/// restarting it every time voice mode opens. Two engines were verified to run
/// simultaneously. Keeping the mic out of `ChiptuneEngine` also means sound effects
/// never require microphone permission.
///
/// **Voice processing changes the input format to 7ch / 48kHz / deinterleaved**, and
/// that is what a tap on `inputNode` receives. Feeding it straight to the recognizer
/// is the trap: `AVAudioConverter(7ch→1ch)` *constructs* — so the obvious code
/// compiles and looks right — but reports `channelMap == [-1]`, no valid source
/// mapping, and hands the recognizer silence. The failure mode is "voice mode hears
/// nothing" with no error to chase. So the input goes through an
/// `AVAudioMixerNode`, which downmixes, and the tap is on the mixer.
///
/// **The mixer's channel count is stated and its sample rate is inherited** — see
/// `start()`, where the callback measurements are recorded. Both of the obvious
/// alternatives ship the same silent failure, one layer down, and both have now been
/// shipped once.
///
/// **One request does not last a conversation.** Barge-in needs the microphone open
/// while the pet speaks, so this runs continuously; `SFSpeechRecognitionTask` does
/// not. `renew()` swaps in a fresh request/task pair without touching the engine, and
/// carries the transcript across the swap so a renewal is invisible from outside — see
/// `TurnTranscript`, which is why `endTurn()` exists.
final class SpeechListener: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    /// The request the audio tap is currently feeding.
    ///
    /// **A box, because the tap is installed once and the request is not.** `renew()`
    /// retires a request at every turn boundary and again at the ~1 minute limit; a
    /// tap closure that captured the request directly would go on appending to the
    /// retired one for the rest of the session, which is the "hears nothing, no error"
    /// failure again.
    ///
    /// **`nonisolated`, not merely `@unchecked Sendable`.** Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a bare `final class` is *inferred*
    /// main-actor, and `@unchecked Sendable` does not opt it out — so `feed.append(buf)`
    /// from the render thread was a main-actor call from a nonisolated context. Swift 5
    /// mode says nothing; `-strict-concurrency=complete` reports it, and Swift 6 makes
    /// it an error. The safety argument the tap comment makes was true at runtime and
    /// untrue at the type level, which is the kind of gap that survives review.
    ///
    /// **The lock is held on a real-time thread, deliberately.** `append` runs on
    /// `AVAudioEngine`'s render thread while `renew()` and `stop()` swap on the main
    /// actor, so the swap must not tear — and `NSLock` on the render thread means a
    /// render callback can, in principle, block on a lower-priority thread
    /// (unbounded priority inversion, the textbook real-time hazard). Accepted here on
    /// the measured numbers: the critical section is one pointer read plus
    /// `SFSpeechAudioBufferRecognitionRequest.append`, the tap delivers ~10 callbacks a
    /// second with 4800-frame (100-109ms) buffers, and the only competing writer holds
    /// the lock for one pointer store a turn. A dropped buffer would cost a syllable,
    /// not a glitch in anything audible — nothing here is feeding an output device.
    /// The lock-free alternative (an atomic swap plus a retain race on the request) is
    /// more code and more ways to append to a retired request.
    nonisolated final class RequestFeed: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?

        func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); request = next; lock.unlock()
        }
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); request?.append(buffer); lock.unlock()
        }
        /// Close the current request and stop feeding it. Idempotent.
        func endAudio() {
            lock.lock()
            request?.endAudio()
            request = nil
            lock.unlock()
        }
        /// Is `candidate` still the request being fed? The staleness test for a
        /// recognition callback: a callback from a retired or cancelled request must
        /// not be allowed to act on the run that replaced it.
        func isCurrent(_ candidate: SFSpeechAudioBufferRecognitionRequest) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return request === candidate
        }
    }

    private let engine = AVAudioEngine()
    private let downmix = AVAudioMixerNode()
    private let recognizer: SFSpeechRecognizer?
    private let feed = RequestFeed()
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// Graph state, tracked so `stop()` can undo exactly what `start()` did, from
    /// any point at which it failed. `AVAudioNode.h`: "Only one tap may be installed
    /// on any bus" — a second `installTap` is an internal assertion, an uncatchable
    /// crash, not a thrown error. Repeat `attach` is undocumented.
    private var didAttach = false
    private var tapInstalled = false
    private var voiceProcessingOn = false

    /// The bound on renewing after a task ends by itself. Pure and tested — see
    /// `RenewalBudget`, which is where the reasoning lives.
    ///
    /// Only tasks that end on their own reach it. A task *we* retire (`renew()`,
    /// `stop()`) is cancelled, and its cancellation callback is dropped by the identity
    /// guard in `recognitionUpdate` before it can reach `endOfTask` — so retiring a
    /// request at a turn boundary does not spend budget.
    /// See the protocol. **Reads the same expression `openRecognition` assigns to
    /// `requiresOnDeviceRecognition`, and is next to it so a change to one is visible
    /// against the other.** `false` with no recogniser is the safe answer: no
    /// recogniser means `start()` throws, and claiming "nothing leaves this Mac" is
    /// the one direction this line must never be wrong in.
    var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    private var budget = RenewalBudget()

    /// The founder's turn, accumulated across renewals. See `TurnTranscript`.
    private var transcript = TurnTranscript()

    /// `contextualStrings` is why the locale is held: product nouns are exactly the
    /// words a general recognizer mishears.
    private let hints: [String]

    init(locale: Locale, hints: [String]) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.hints = hints
    }

    /// **`isolated deinit` (SE-0371), because the teardown is main-actor work.** I2's
    /// other half: a listener deallocated while running would otherwise leave the tap
    /// installed and the engine holding the microphone. `stop()` and nothing else — an
    /// inlined copy of three of its four steps is exactly the drift the single-teardown
    /// claim was supposed to prevent, and the step it dropped was
    /// `setVoiceProcessingEnabled(false)`.
    ///
    /// A plain `deinit` is nonisolated, so calling the main-actor `stop()` from it is a
    /// warning under complete checking and an error in Swift 6. The two obvious fixes
    /// are both worse: hopping with `DispatchQueue.main.async` requires capturing
    /// `self` from a deinit, which is a use-after-free, and `MainActor.assumeIsolated`
    /// trades a compile-time warning for a crash on any release that happens off the
    /// main thread. `isolated deinit` is the language feature for exactly this — the
    /// deallocation hops to the main actor when it is not already there. Verified to
    /// compile under `-swift-version 5 -default-isolation MainActor
    /// -strict-concurrency=complete`.
    isolated deinit {
        stop()
    }

    func start() throws {
        // Liveness before availability: a redundant `start()` on a healthy running
        // listener must be a no-op, not a thrown `recognizerUnavailable` because the
        // service happened to go away since it started.
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceAudioError.recognizerUnavailable
        }

        // **Roll back on every throwing path.** Without this, a failed
        // `engine.start()` leaves the tap installed and `isRunning` false, the old
        // `stop()` returned early on that flag and removed nothing, and the next
        // `start()` installed a second tap on the same bus — an uncatchable crash.
        var succeeded = false
        defer { if !succeeded { stop() } }

        // BEFORE start(), never after — see the -10849 note above.
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            voiceProcessingOn = true
        } catch {
            throw VoiceAudioError.engineFailed("voice processing: \(error.localizedDescription)")
        }

        if !didAttach {
            engine.attach(downmix)
            didAttach = true
        }
        // Connect at the INPUT's own format; the mixer does the downmix.
        engine.connect(engine.inputNode, to: downmix,
                       format: engine.inputNode.outputFormat(forBus: 0))

        // The mixer's OUTPUT format is what the recognizer receives, and
        // connect(_:to:format:) does not set it — it sets the SOURCE's output bus and
        // makes the destination's INPUT bus match. Inherited, this bus measured
        // 2ch/44100Hz on 21 Aug: the recognizer was being handed stereo.
        //
        // **Force the channel count, INHERIT the sample rate.** Measured 21 Aug by
        // counting tap callbacks over 2s with microphone authorisation confirmed:
        // an `AVAudioMixerNode` downmixes 7ch→1ch on a tapped output bus but will
        // NOT resample it. 1ch/44100 and 1ch/48000 both deliver ~19 callbacks;
        // asking for 1ch/16000 moves the bus to 1ch/16000 and then the tap NEVER
        // FIRES — zero callbacks, no error, which is precisely the "voice mode hears
        // nothing with nothing to chase" failure the spec names. Moving the bus and
        // audio flowing are different facts, and only the second one matters.
        // `SFSpeechAudioBufferRecognitionRequest` accepts the device rate; mono is
        // the part it actually needs.
        //
        // Do NOT instead connect `downmix` to `mainMixerNode` to force a format:
        // that routes the microphone to the speakers and, with voice processing on,
        // builds a feedback loop.
        let inherited = downmix.outputFormat(forBus: 0)
        guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: inherited.sampleRate,
                                            channels: 1,
                                            interleaved: false) else {
            throw VoiceAudioError.engineFailed("could not build the mono tap format")
        }

        openRecognition(recognizer)

        // 4800 frames is 109ms at 44100 and 100ms at 48000. `AVAudioNode.h`:
        // "Supported range is [100, 400] ms". The shipped 1024 was 23ms, outside it.
        //
        // `@Sendable` is deliberate: under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
        // this closure would otherwise be *inferred* main-actor while `AVAudioEngine`
        // invokes it on the real-time render thread — main-actor state touched off the
        // main actor, with Swift 5 mode reporting nothing. It is a statement of intent
        // that the compiler only partly enforces here: with
        // `SWIFT_STRICT_CONCURRENCY` unset, capture checking is minimal, so it will
        // not reject a wrong capture for us. What makes the body safe is written into
        // it — `feed` is a locked box, the level maths is a pure static over a raw
        // pointer, and `self` is reached only after the hop.
        let feed = self.feed
        downmix.installTap(onBus: 0, bufferSize: 4800, format: tapFormat) { @Sendable [weak self] buf, _ in
            feed.append(buf)
            guard let channel = buf.floatChannelData?[0] else { return }
            let frames = Int(buf.frameLength)
            guard frames > 0 else { return }
            let level = VoiceLevel.level(from: UnsafeBufferPointer(start: channel, count: frames))
            // `[weak self]` on the hop as well, matching `SpeechSpeaker`: reaching the
            // outer closure's captured `self` var from inside a second concurrently
            // executing closure is a warning under complete checking and an error in
            // Swift 6 (`#SendableClosureCaptures`). Re-capturing weakly here is what
            // the rest of the codebase does and costs nothing.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onLevel?(level) }
            }
        }
        tapInstalled = true

        do { try engine.start() }
        catch { throw VoiceAudioError.engineFailed(error.localizedDescription) }

        succeeded = true
        isRunning = true
    }

    /// Idempotent and unconditional. It used to `guard isRunning`, which made it
    /// useless as a rollback for a half-configured graph — the exact case it is
    /// most needed for.
    func stop() {
        // Tap first, then end the audio: the other order can let one more buffer
        // reach a request that has already been closed.
        if tapInstalled {
            downmix.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        retireRecognition()
        if voiceProcessingOn {
            // Leave the input node as we found it. Only clear the flag if it actually
            // came off: swallowing the throw *and* forgetting we enabled it means
            // nothing ever tries again.
            do {
                try engine.inputNode.setVoiceProcessingEnabled(false)
                voiceProcessingOn = false
            } catch {
                // Nothing to do about a -10849 at teardown; the flag stays set so a
                // later `stop()` retries, and the next `start()` re-enables anyway.
            }
        }
        budget = RenewalBudget()
        // A turn cannot survive the microphone being torn down. `renew()` bridges a
        // gap of 100-200ms; this gap is unbounded — the founder was told listening
        // stopped — so resuming her half-sentence afterwards would put words she has
        // moved on from at the front of her next question.
        transcript.endTurn()
        isRunning = false
    }

    /// See the protocol. The listener cannot infer this: recognition going quiet looks
    /// the same whether she finished or paused.
    ///
    /// **Clearing `transcript` is only half of it, and the missing half sent the
    /// founder's previous question again.** `SFSpeechAudioBufferRecognitionRequest` has
    /// no reset — `bestTranscription` covers every buffer appended for that request's
    /// whole life — and this listener deliberately keeps running across turns, because
    /// barge-in needs the microphone open while the pet speaks. So the request that
    /// heard turn 1 was still live and still being fed, and its next partial was
    /// `"what should we charge for the beta thanks"`: sent, credit spent, compounding
    /// every turn for the session, with nothing thrown and nothing logged.
    /// `renew()` is the only thing that yields a request transcribing from empty.
    ///
    /// It costs the 100-200ms seam `renew()` always costs, taken at the one moment it
    /// is free: she has just stopped talking. The alternative — a `dropPrefix` baseline
    /// inside `TurnTranscript` — was rejected because a recognizer revises words it has
    /// already reported, so yesterday's prefix is not reliably still a prefix, and it
    /// would leave the request accumulating the whole session behind our back.
    ///
    /// **Keep this body and `SpeechFakesTests.FakeListener.endTurn()` in step.** The
    /// fake is the only place the promise is tested, because testing it here needs an
    /// `SFSpeechRecognizer`.
    func endTurn() {
        transcript.endTurn()
        // Not running: `stop()` has already ended the turn and retired the request, and
        // renewing would report a failure through `renew()`'s else branch for a
        // listener that is correctly idle.
        guard isRunning else { return }
        renew()
    }

    // MARK: - Recognition

    /// Open a request/task pair and start feeding the tap into it.
    ///
    /// **The error is not discardable.** `SFSpeechRecognizer.isAvailable` reflects
    /// service availability, not authorisation — that is the separate static
    /// `authorizationStatus` — so `start()` succeeds with recognition
    /// `.notDetermined` or `.denied`, the tap fires, the waveform pulses, and the task
    /// fails. Swallowed, the founder watches a live-looking waveform that never produces
    /// one word, with nothing logged. Same path for a mid-session permission revoke,
    /// and for any network drop under vi-VN, which spec §3 measured as server-side.
    private func openRecognition(_ recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device in English; vi-VN has no asset and falls back to the network.
        // Requesting it is still correct: it is honoured where possible.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = hints
        feed.replace(with: req)

        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            // Only `String` and `Bool` cross the hop from the result:
            // `SFSpeechRecognitionResult` is not Sendable.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.recognitionUpdate(req, text: text, isFinal: isFinal, error: error)
                }
            }
        }
    }

    /// Close the current request/task pair. Safe to call twice, and safe to call on a
    /// pair that was never opened.
    private func retireRecognition() {
        // **Here rather than in `renew()`, deliberately.** This is the moment a request
        // stops being fed, so committing here means no future caller has to remember
        // to save its transcript first — the retiring request's words are the first
        // half of a sentence the founder is still saying, and dropped here they are
        // dropped for good, since the new request cannot re-hear audio already past.
        // `stop()` calls this too and then ends the turn outright, and `endTurn()`
        // clears the transcript before it renews, so in both of those the commit is a
        // no-op on an already-empty `current` rather than a resurrection of words the
        // founder has moved on from.
        transcript.commit()
        feed.endAudio()
        task?.cancel()
        task = nil
    }

    private func recognitionUpdate(_ req: SFSpeechAudioBufferRecognitionRequest,
                                   text: String?, isFinal: Bool, error: Error?) {
        // **Identity, not just liveness.** `isRunning` belongs to the listener, so it
        // cannot tell "this listener is running" from "this listener is running a
        // DIFFERENT request". `SFSpeechRecognitionTask.cancel()` delivers its error
        // asynchronously, so with `isRunning` alone: stop(), start(), then the old
        // task's cancellation error arrives, sees a live listener, and tears the
        // brand-new turn down — the surface renders "recognition died" and closes
        // voice mode milliseconds after it opened. The same path with a result
        // delivers turn N's transcript as turn N+1's `onPartial`. `renew()` makes
        // that sequence routine rather than a race.
        guard isRunning, feed.isCurrent(req) else { return }

        if let text {
            // Non-empty only, and `RenewalBudget` enforces that rather than this call
            // site: a result carrying `""` is what a task delivers while it is failing
            // to hear anything, so clearing the budget on it clears it in exactly the
            // condition the budget exists to detect.
            budget.sawTranscript(text)
            // Only on a real change. A recognizer re-reports the same string freely,
            // and the surface reads every partial as speech — barge-in while the pet
            // is talking — so an unchanged partial cuts the pet off with words the
            // founder has already had answered.
            if transcript.update(text) {
                // The whole turn, not this request's fragment of it.
                onPartial?(transcript.text)
            }
        }

        // Anything else is this task ending.
        guard error != nil || isFinal else { return }
        endOfTask(error)
    }

    /// A recognition task ended by itself. Renew unless renewing is evidently futile —
    /// the decision is `RenewalBudget`'s, and so is the reasoning for it.
    private func endOfTask(_ error: Error?) {
        switch budget.taskEnded() {
        case .renew:
            renew()
        case .fail:
            // Ordered: stop first, so `isRunning` is already false when the surface
            // handles this, and the cancellation error `retireRecognition()` may
            // deliver is dropped by the identity guard rather than reported twice.
            stop()
            onFailure?(error ?? VoiceAudioError.engineFailed("recognition ended"))
        }
    }

    /// Retire the request/task pair and open a fresh one.
    ///
    /// **The engine, the tap and voice processing are deliberately untouched.**
    /// `setVoiceProcessingEnabled` throws -10849 on a running engine, so rebuilding
    /// that once a minute would mean stopping and restarting the microphone in the
    /// middle of a conversation; and `AVAudioNode.h` allows only one tap per bus, so
    /// re-installing is the uncatchable-assertion path for no gain. Only the
    /// recognition pair has the ~1 minute limit.
    ///
    /// There is a seam: the retiring request is closed before the new one is fed, so
    /// a buffer or two (roughly 100-200ms) is not transcribed. That is preferable to
    /// running two tasks on one recognizer, which is undocumented and unmeasurable
    /// here, and it matches how `start()`/`stop()` already use it — one task at a time.
    ///
    /// Called at every turn boundary (`endTurn()`) as well as on task end, because the
    /// request's transcript is the only copy of the previous question that neither we
    /// nor the consumer can clear.
    private func renew() {
        guard isRunning, let recognizer else {
            // **Unreachable, and it must not be silent anyway.** `endOfTask` only gets
            // here behind the identity guard, so the listener is running; `endTurn()`
            // returns early when it is not; and a nil recognizer makes `start()` throw
            // before anything can renew. If it ever is reached, returning quietly
            // leaves no task and no request with `isRunning` still true — a
            // live-looking waveform that hears nothing, the exact failure this class exists
            // to report. Stop first so `isRunning` is already false when the surface
            // reacts, matching `endOfTask`.
            stop()
            onFailure?(VoiceAudioError.recognizerUnavailable)
            return
        }
        // `retireRecognition()` commits the retiring request's transcript, so the
        // founder's turn crosses the swap intact — see `TurnTranscript`.
        retireRecognition()
        openRecognition(recognizer)
    }
}
