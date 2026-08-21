// codepet/Services/SpeakingVoice.swift
import AVFoundation
import Foundation

/// Reads sentences aloud, one after another, and says when the reply is over.
///
/// A protocol so the suite can drive a fake — see `SpeechFakesTests` for why that
/// is a hard rule here rather than a preference. The bookkeeping behind it is
/// `SpeakingQueue`, which is pure and tested; this protocol is the audio boundary.
protocol SpeakingVoice: AnyObject {
    /// Fires when the queue has drained AND `endOfReply()` has been called — i.e.
    /// the reply is genuinely over, not merely paused. A drain mid-stream is
    /// ordinary: a fenced code block produces no speakable sentences for many
    /// seconds. Treating that as the end opens the mic and spends a credit on an
    /// empty turn.
    var onFinishedAll: (() -> Void)? { get set }
    var isSpeaking: Bool { get }

    /// A new reply is starting. Opens the latch closed by `stopImmediately`.
    func beginReply()
    /// Add one complete sentence. Never a fragment — see `SentenceSplitter`.
    /// Ignored after `stopImmediately` until the next `beginReply`.
    func enqueue(_ sentence: String, profile: VoiceProfile)
    /// No more sentences are coming for this reply. Wired to `isStreaming` going
    /// false. Required for `onFinishedAll` to ever fire.
    func endOfReply()
    /// Stop mid-word. This is barge-in, so it cannot wait for the sentence to end,
    /// and it must also refuse everything still in flight.
    func stopImmediately()
}

/// `AVSpeechSynthesizer`, wrapped.
///
/// **Everything that can be decided without audio is decided in `SpeakingQueue`.**
/// What is left here is the framework: turning a voice name into an
/// `AVSpeechSynthesisVoice`, speaking, stopping, and the SFX volume. The queue
/// depth, the end-of-reply rule, the barge-in latch and the duck/restore pairing
/// all live in the pure struct, because as inline state they were four review
/// findings that no test could reach.
///
/// **Ducks the chiptune SFX while speaking** (spec §5). `ChiptuneEngine` is a
/// separate `AVAudioEngine` playing 8-bit sounds, and bleeps over a spoken sentence
/// is a mess. The volume is restored exactly once per reply — on a clean finish, on
/// barge-in, and on `deinit`, because a delegate callback that never arrives (AirPods
/// disconnecting mid-sentence, a device change) would otherwise leave the SFX
/// silent for the rest of the process with no recovery but quitting the app.
final class SpeechSpeaker: NSObject, SpeakingVoice, AVSpeechSynthesizerDelegate {
    var onFinishedAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queue = SpeakingQueue()
    /// Which utterance carries which ticket. `AVSpeechUtterance` has no identity of
    /// its own that the delegate hands back, so identity is the object's.
    private var tickets: [ObjectIdentifier: SpeakingQueue.Ticket] = [:]
    private var duckedFrom: Float?
    /// `stopSpeaking(at:)` returned NO — nothing was speaking yet. Retry on the next
    /// callback, once.
    private var stopNeedsRetry = false

    /// **Cached deliberately.** `speechVoices()` was being called for every sentence,
    /// on the main actor, while a reply streamed. Installed voices do not change
    /// during a session.
    private lazy var installedVoices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    private lazy var installedVoiceNames: [String] = installedVoices.map(\.name)

    override init() {
        super.init()
        synth.delegate = self
    }

    deinit {
        // I2: the last line of defence for the SFX volume. If a `didFinish` never
        // arrives, or this speaker is deallocated mid-utterance, the founder is
        // otherwise left with permanently silent sound effects.
        if let was = duckedFrom {
            duckedFrom = nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ChiptuneEngine.shared.sfxVolume = was }
            }
        }
    }

    /// **Our own bookkeeping, not `synth.isSpeaking`.** The framework's flag is
    /// asynchronous: it is very likely still false immediately after `speak()` and
    /// may still be true immediately after `stopSpeaking`. Overlay logic validated
    /// against a fake that flips synchronously would then behave differently in
    /// production. Reporting the queue makes the fake and this class agree.
    var isSpeaking: Bool { queue.isSpeaking }

    func beginReply() {
        queue.beginReply()
    }

    func enqueue(_ sentence: String, profile: VoiceProfile) {
        // Refused after barge-in until the next reply: the server is still streaming
        // and the consumer is still calling this, so the latch is what stops the pet
        // resuming on the next sentence.
        guard let accepted = queue.enqueue() else { return }

        let u = AVSpeechUtterance(string: sentence)
        // PetVoice.pick works in names so it stays testable; this is the ONE line
        // that turns a name into a voice. nil is fine — system default.
        u.voice = PetVoice.pick(profile, from: installedVoiceNames)
            .flatMap { name in installedVoices.first { $0.name == name } }
        u.rate = profile.rate
        u.pitchMultiplier = profile.pitch
        // Spec §5 wants sentence-by-sentence speech to sound like speech; at 0 the
        // sentences run together with no breath between them.
        u.postUtteranceDelay = 0.15

        tickets[ObjectIdentifier(u)] = accepted.ticket
        if accepted.shouldDuck { duckSFX() }
        synth.speak(u)
    }

    func endOfReply() {
        apply(queue.endOfReply())
    }

    func stopImmediately() {
        let effects = queue.stop()
        tickets.removeAll()
        // **The Bool matters.** `AVSpeechSynthesis.h`: it "will operate on the speech
        // utterance that is speaking", so in the window between `speak` and synthesis
        // actually starting there is nothing to stop and this returns NO — while the
        // founder has already interrupted. Retry once on the next callback.
        let stopped = synth.stopSpeaking(at: .immediate)
        stopNeedsRetry = !stopped && synth.isSpeaking
        apply(effects)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    // `AVSpeechSynthesizerDelegate` is `NS_SWIFT_SENDABLE` in the SDK — Apple saying
    // these callbacks are not promised on any particular queue. Under
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` they would be inferred main-actor
    // and mutate `tickets` and the queue off it, unsynchronised, with Swift 5 mode
    // reporting nothing. So they are `nonisolated` and hop explicitly. Only the
    // utterance's identity crosses, because `AVSpeechUtterance` is not `Sendable`.

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        hop(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        hop(ObjectIdentifier(utterance))
    }

    private nonisolated func hop(_ id: ObjectIdentifier) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.reportBack(id) }
        }
    }

    private func reportBack(_ id: ObjectIdentifier) {
        if stopNeedsRetry {
            stopNeedsRetry = false
            _ = synth.stopSpeaking(at: .immediate)
        }
        // An unknown id is a callback for an abandoned reply. The queue drops it;
        // asking it is still the right move, because that is where the rule lives.
        guard let ticket = tickets.removeValue(forKey: id) else { return }
        apply(queue.finishedOne(ticket))
    }

    // MARK: - Effects

    private func apply(_ effects: SpeakingQueue.Effects) {
        if effects.unduck { unduckSFX() }
        if effects.finishedReply { onFinishedAll?() }
    }

    private func duckSFX() {
        guard duckedFrom == nil else { return }   // already ducked; don't stack
        duckedFrom = ChiptuneEngine.shared.sfxVolume
        ChiptuneEngine.shared.sfxVolume = 0
    }

    private func unduckSFX() {
        if let was = duckedFrom { ChiptuneEngine.shared.sfxVolume = was }
        duckedFrom = nil
    }
}
