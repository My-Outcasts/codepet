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
    /// The running transcript so far. Called repeatedly with a growing string.
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
/// **The mixer's output format is stated, not inherited** — see `start()`. Getting
/// that wrong is the same failure mode, one layer down, and it was shipped.
final class SpeechListener: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private let downmix = AVAudioMixerNode()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// Graph state, tracked so `stop()` can undo exactly what `start()` did, from
    /// any point at which it failed. `AVAudioNode.h`: "Only one tap may be installed
    /// on any bus" — a second `installTap` is an internal assertion, an uncatchable
    /// crash, not a thrown error. Repeat `attach` is undocumented.
    private var didAttach = false
    private var tapInstalled = false
    private var voiceProcessingOn = false

    /// `contextualStrings` is why the locale is held: product nouns are exactly the
    /// words a general recognizer mishears.
    private let hints: [String]

    init(locale: Locale, hints: [String]) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.hints = hints
    }

    deinit {
        // I2's other half: a listener deallocated while running would otherwise
        // leave the tap installed and the engine holding the microphone.
        if tapInstalled { downmix.removeTap(onBus: 0) }
        engine.stop()
        request?.endAudio()
        task?.cancel()
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceAudioError.recognizerUnavailable
        }
        guard !isRunning else { return }

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

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device in English; vi-VN has no asset and falls back to the network.
        // Requesting it is still correct: it is honoured where possible.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = hints
        request = req

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
        // 2ch/44100Hz on 21 Aug (the recognizer was being handed stereo 44.1k);
        // stating it here measured exactly 1ch/16000Hz. Legal because the mixer's
        // output bus is connected to no other node — `AVAudioNode.h` restricts
        // stating a format to exactly that case.
        //
        // Do NOT instead connect `downmix` to `mainMixerNode` to force a format:
        // that routes the microphone to the speakers and, with voice processing on,
        // builds a feedback loop.
        guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false) else {
            throw VoiceAudioError.engineFailed("could not build the 16kHz mono tap format")
        }
        // 4800 frames = 300ms at 16kHz. `AVAudioNode.h`: "Supported range is
        // [100, 400] ms", so at this rate 1600–6400 frames. The shipped 1024 (64ms)
        // was outside it.
        //
        // `@Sendable` is load-bearing. Under `SWIFT_DEFAULT_ACTOR_ISOLATION =
        // MainActor` this closure would otherwise be inferred main-actor while
        // `AVAudioEngine` invokes it on the real-time render thread — main-actor
        // state touched off the main actor, with Swift 5 mode reporting nothing.
        // Marked `@Sendable` the compiler refuses any such capture: `req` is a local,
        // the level maths is pure, and `self` is only reached after the hop.
        downmix.installTap(onBus: 0, bufferSize: 4800, format: tapFormat) { @Sendable [weak self] buf, _ in
            req.append(buf)
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

        // **The error is not discardable.** `SFSpeechRecognizer.isAvailable` reflects
        // service availability, not authorisation — that is the separate static
        // `authorizationStatus` — so `start()` succeeds with recognition
        // `.notDetermined` or `.denied`, the tap fires, the orb pulses, and the task
        // fails. Swallowed, the founder watches a live-looking orb that never
        // produces one word, with nothing logged. Same path for a mid-session
        // permission revoke, and for any network drop under vi-VN, which spec §3
        // measured as server-side.
        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            // Only `String` crosses the hop: `SFSpeechRecognitionResult` is not Sendable.
            let text = result?.bestTranscription.formattedString
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    if let error {
                        // Ordered: stop first, so `isRunning` is already false by the
                        // time the overlay handles this, and the cancellation error
                        // that `task.cancel()` may deliver is dropped by the guard
                        // above rather than reported a second time.
                        self.stop()
                        self.onFailure?(error)
                        return
                    }
                    if let text { self.onPartial?(text) }
                }
            }
        }
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
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if voiceProcessingOn {
            // Leave the input node as we found it. `try?` because this can only fail
            // by throwing -10849 on a still-initialised AU, and there is nothing to
            // do about that at teardown; the next `start()` re-enables regardless.
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            voiceProcessingOn = false
        }
        isRunning = false
    }
}
