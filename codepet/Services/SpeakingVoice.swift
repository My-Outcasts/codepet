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
/// barge-in, at the start of the *next* reply if this one stalled, and on `deinit`.
/// A delegate callback that never arrives (AirPods disconnecting mid-sentence, a
/// device change, a synthesis stall) means the reply never drains, and without the
/// next-reply release that one duck then survived every later reply and left the SFX
/// silent for the rest of the process with no recovery but quitting the app.
final class SpeechSpeaker: NSObject, SpeakingVoice, AVSpeechSynthesizerDelegate {
    var onFinishedAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queue = SpeakingQueue()
    /// Which utterance carries which ticket. `AVSpeechUtterance` has no identity of
    /// its own that the delegate hands back, so identity is the object's.
    private var tickets: [ObjectIdentifier: SpeakingQueue.Ticket] = [:]
    /// **The SFX volume to put back — not a second "am I ducked" flag.** `SpeakingQueue`
    /// owns that fact (`isDucked`) and emits `unduck` exactly once per duck; this only
    /// carries the number across, and is nil when there is nothing to put back.
    private var savedSFXVolume: Float?

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
        if let was = savedSFXVolume {
            savedSFXVolume = nil
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
        // Prune here as well as in `stopImmediately`: otherwise the map depends on
        // every abandoned utterance eventually reporting back to be emptied.
        tickets.removeAll()
        // Carries `unduck` when the previous reply stalled and never drained — see
        // `SpeakingQueue.beginReply`. On the normal path it is empty.
        apply(queue.beginReply())
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
        //
        // The retry is armed **on the queue**, whose `beginReply` disarms it and
        // whose `takeStopRetry` refuses to fire it once the latch has reopened. As a
        // `Bool` here it outlived this reply and cancelled the next one's utterance
        // (R2). Armed on the Bool alone: `&& synth.isSpeaking` cancelled the exact
        // case, since it returned NO *because* nothing was speaking.
        if !synth.stopSpeaking(at: .immediate) { queue.armStopRetry() }
        apply(effects)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    // `AVSpeechSynthesizerDelegate` is `NS_SWIFT_SENDABLE` in the SDK — Apple saying
    // these callbacks are not promised on any particular queue. Under
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` they would be inferred main-actor
    // and mutate `tickets` and the queue off it, unsynchronised, with Swift 5 mode
    // reporting nothing. So they are `nonisolated` and hop explicitly. Only the
    // utterance's identity crosses, because `AVSpeechUtterance` is not `Sendable`.

    /// **The only hook that can catch the barge-in window.** `stopImmediately()` in
    /// the gap between `speak()` and synthesis starting has nothing to stop, so the
    /// retry has to wait for a callback — and for that utterance the next callback
    /// is its own `didFinish`, i.e. *after it has been spoken in full*. The founder
    /// interrupts and hears the whole sentence anyway. This is the first moment
    /// there is something to stop.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.speakingStarted() }
        }
    }

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

    /// Something began speaking. If the latch is closed, the founder has already
    /// interrupted and whatever just started belongs to the reply she interrupted.
    private func speakingStarted() {
        guard !queue.accepts else { return }
        // Consumed here so the belt-and-braces path below cannot fire a second time
        // into a reply that has since begun.
        _ = queue.takeStopRetry()
        _ = synth.stopSpeaking(at: .immediate)
    }

    private func reportBack(_ id: ObjectIdentifier) {
        // Belt and braces behind `didStart`: still owed, and still only while the
        // latch is closed — `stopSpeaking` clears the queue, so firing it once a new
        // reply is accepting would cancel that reply instead.
        if queue.takeStopRetry() { _ = synth.stopSpeaking(at: .immediate) }
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

    /// Called only for an `Accepted` whose `shouldDuck` is true, which the queue
    /// hands out once per duck cycle — so there is no "don't stack" guard here to be
    /// a second, silently-divergent copy of that rule.
    private func duckSFX() {
        savedSFXVolume = ChiptuneEngine.shared.sfxVolume
        ChiptuneEngine.shared.sfxVolume = 0
    }

    private func unduckSFX() {
        if let was = savedSFXVolume { ChiptuneEngine.shared.sfxVolume = was }
        savedSFXVolume = nil
    }
}
