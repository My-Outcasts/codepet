// codepet/Services/SpeakingVoice.swift
import AVFoundation
import Foundation

/// Reads sentences aloud, one after another, and says when it has run dry.
///
/// A protocol so the suite can drive a fake — see `SpeechFakesTests` for why that
/// is a hard rule here rather than a preference.
protocol SpeakingVoice: AnyObject {
    /// Called when the queue drains. The overlay turns this into `.replyFinished`.
    var onFinishedAll: (() -> Void)? { get set }
    var isSpeaking: Bool { get }
    /// Add one complete sentence. Never a fragment — see `SentenceSplitter`.
    func enqueue(_ sentence: String, profile: VoiceProfile)
    /// Stop mid-word. This is barge-in, so it cannot wait for the sentence to end.
    func stopImmediately()
}

/// `AVSpeechSynthesizer`, wrapped.
///
/// **Ducks the chiptune SFX while speaking** (spec §5). `ChiptuneEngine` is a
/// separate `AVAudioEngine` playing 8-bit sounds, and bleeps over a spoken sentence
/// is a mess. Volume is restored when the queue drains — including when it drains
/// because of barge-in, which is why the restore lives in one place.
final class SpeechSpeaker: NSObject, SpeakingVoice, AVSpeechSynthesizerDelegate {
    var onFinishedAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queued = 0
    private var duckedFrom: Float?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func enqueue(_ sentence: String, profile: VoiceProfile) {
        let u = AVSpeechUtterance(string: sentence)
        // PetVoice.pick works in names so it stays testable; this is the ONE line
        // that turns a name into a voice. nil is fine — system default.
        let installed = AVSpeechSynthesisVoice.speechVoices()
        u.voice = PetVoice.pick(profile, from: installed.map(\.name))
            .flatMap { name in installed.first { $0.name == name } }
        u.rate = profile.rate
        u.pitchMultiplier = profile.pitch
        duckSFX()
        queued += 1
        synth.speak(u)
    }

    func stopImmediately() {
        queued = 0
        synth.stopSpeaking(at: .immediate)
        unduckSFX()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queued = max(0, queued - 1)
        if queued == 0 {
            unduckSFX()
            onFinishedAll?()
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queued = max(0, queued - 1)
        if queued == 0 { unduckSFX() }
    }

    // MARK: - SFX ducking

    private func duckSFX() {
        guard duckedFrom == nil else { return }   // already ducked; don't stack
        let mixer = ChiptuneEngine.shared.sfxVolume
        duckedFrom = mixer
        ChiptuneEngine.shared.sfxVolume = 0
    }

    private func unduckSFX() {
        if let was = duckedFrom { ChiptuneEngine.shared.sfxVolume = was }
        duckedFrom = nil
    }
}
