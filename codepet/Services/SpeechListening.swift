// codepet/Services/SpeechListening.swift
import AVFoundation
import Foundation
import Speech

enum VoiceAudioError: Error {
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
final class SpeechListener: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let downmix = AVAudioMixerNode()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// `contextualStrings` is why the locale is held: product nouns are exactly the
    /// words a general recognizer mishears.
    private let hints: [String]

    init(locale: Locale, hints: [String]) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.hints = hints
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceAudioError.recognizerUnavailable
        }
        guard !isRunning else { return }

        // BEFORE start(), never after — see the -10849 note above.
        do { try engine.inputNode.setVoiceProcessingEnabled(true) }
        catch { throw VoiceAudioError.engineFailed("voice processing: \(error.localizedDescription)") }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device in English; vi-VN has no asset and falls back to the network.
        // Requesting it is still correct: it is honoured where possible.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = hints
        request = req

        engine.attach(downmix)
        // Connect at the INPUT's own format; the mixer does the downmix.
        engine.connect(engine.inputNode, to: downmix,
                       format: engine.inputNode.outputFormat(forBus: 0))
        let tapFormat = downmix.outputFormat(forBus: 0)
        downmix.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buf, _ in
            self?.request?.append(buf)
            self?.reportLevel(buf)
        }

        do { try engine.start() }
        catch { throw VoiceAudioError.engineFailed(error.localizedDescription) }

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let result else { return }
            self?.onPartial?(result.bestTranscription.formattedString)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        downmix.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
    }

    /// RMS, for the orb. Cheap on purpose — it runs per buffer on the audio thread.
    private func reportLevel(_ buf: AVAudioPCMBuffer) {
        guard let data = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = (sum / Float(n)).squareRoot()
        let level = min(1, rms * 12)   // empirical gain; speech RMS is small
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
