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

/// Streams what the founder is saying.
///
/// A protocol so the suite can drive a fake — the concrete type wants a microphone,
/// which no test may touch.
protocol SpeechListening: AnyObject {
    /// The running transcript so far, called repeatedly as it grows.
    ///
    /// **Not monotonic across a whole conversation.** `SFSpeechRecognitionTask` has a
    /// documented ~1 minute audio limit per request, and barge-in needs the
    /// microphone live for the length of a conversation rather than a turn — so the
    /// concrete listener retires a request and opens a fresh one when the limit is
    /// hit (see `SpeechListener.renew()`). The next string after a renewal starts
    /// over from the new request. A consumer that needs the whole conversation must
    /// accumulate; one that reads the current utterance, which is what the overlay
    /// wants, can take this as given.
    var onPartial: ((String) -> Void)? { get set }
    /// Input level 0…1, for the orb.
    var onLevel: ((Float) -> Void)? { get set }
    /// Recognition died after start() returned — permission revoked, the network
    /// dropped (vi-VN is server-side; see spec §3), the service went away. The overlay
    /// must show this, because the alternative is a live-looking orb that hears nothing.
    var onFailure: ((Error) -> Void)? { get set }
    var isRunning: Bool { get }
    func start() throws
    func stop()
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
/// not. `renew()` swaps in a fresh request/task pair without touching the engine.
final class SpeechListener: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    /// The request the audio tap is currently feeding.
    ///
    /// **A box, because the tap is installed once and the request is not.** `renew()`
    /// retires a request roughly once a minute; a tap closure that captured the
    /// request directly would go on appending to the retired one for the rest of the
    /// session, which is the "hears nothing, no error" failure again. The lock is
    /// real work, not ceremony: `append` runs on the real-time render thread while
    /// `renew()` and `stop()` swap on the main actor. It is uncontended except for
    /// one pointer swap a minute, and `append` itself is already doing more than this
    /// costs.
    private final class RequestFeed: @unchecked Sendable {
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

    /// Renewals since a recognition task last produced any transcript at all.
    ///
    /// The bound on `renew()`. Hitting the ~1 minute audio limit means a minute of
    /// audio flowed, so a *fresh* task that dies having delivered nothing is not that
    /// — it is a genuinely fatal condition (authorisation revoked in System Settings,
    /// the recognizer withdrawn) that will kill every task we open. Unbounded
    /// renewal there is a tight loop of failing tasks, silently, forever. One
    /// renewal is spent finding out; the second failure is reported.
    private var renewalsWithoutResult = 0

    /// `contextualStrings` is why the locale is held: product nouns are exactly the
    /// words a general recognizer mishears.
    private let hints: [String]

    init(locale: Locale, hints: [String]) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.hints = hints
    }

    deinit {
        // I2's other half: a listener deallocated while running would otherwise leave
        // the tap installed and the engine holding the microphone. `stop()` and
        // nothing else — an inlined copy of three of its four steps is exactly the
        // drift the single-teardown claim was supposed to prevent, and the step it
        // dropped was `setVoiceProcessingEnabled(false)`.
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
            DispatchQueue.main.async {
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
        renewalsWithoutResult = 0
        isRunning = false
    }

    // MARK: - Recognition

    /// Open a request/task pair and start feeding the tap into it.
    ///
    /// **The error is not discardable.** `SFSpeechRecognizer.isAvailable` reflects
    /// service availability, not authorisation — that is the separate static
    /// `authorizationStatus` — so `start()` succeeds with recognition
    /// `.notDetermined` or `.denied`, the tap fires, the orb pulses, and the task
    /// fails. Swallowed, the founder watches a live-looking orb that never produces
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
        // brand-new turn down — the overlay renders "recognition died" and closes
        // voice mode milliseconds after it opened. The same path with a result
        // delivers turn N's transcript as turn N+1's `onPartial`. `renew()` makes
        // that sequence routine rather than a race.
        guard isRunning, feed.isCurrent(req) else { return }

        if let text {
            renewalsWithoutResult = 0
            onPartial?(text)
        }

        // Anything else is this task ending.
        guard error != nil || isFinal else { return }
        endOfTask(error)
    }

    /// A recognition task ended. Renew unless renewing is evidently futile.
    ///
    /// **Renew on any task end, bounded — I could not reliably tell renewable from
    /// fatal by the error.** The resolution offered `isFinal` with no error, or "the
    /// duration limit", as the renewable cases. The first is checkable; the second is
    /// not: the ~1 minute limit surfaces as an `NSError` in `kAFAssistantErrorDomain`
    /// whose codes are undocumented and version-dependent, and I may not construct an
    /// `SFSpeechRecognizer` to find out what this OS reports. Matching on a guessed
    /// code would either close the session on a renewable end (the bug) or renew
    /// forever on a fatal one (worse). So the discriminator is not the error, it is
    /// `renewalsWithoutResult`: renewing costs one request, and a fresh request that
    /// produces nothing at all has answered the question.
    private func endOfTask(_ error: Error?) {
        guard renewalsWithoutResult < 1 else {
            // Ordered: stop first, so `isRunning` is already false when the overlay
            // handles this, and the cancellation error `retireRecognition()` may
            // deliver is dropped by the identity guard rather than reported twice.
            stop()
            onFailure?(error ?? VoiceAudioError.engineFailed("recognition ended"))
            return
        }
        renewalsWithoutResult += 1
        renew()
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
    private func renew() {
        guard isRunning, let recognizer else { return }
        retireRecognition()
        openRecognition(recognizer)
    }
}
