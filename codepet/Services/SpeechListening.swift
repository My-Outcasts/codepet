// codepet/Services/SpeechListening.swift
import AVFoundation
import Foundation
import Speech
import os

/// `Equatable` so a test can name which failure it means. Deliberately carries no
/// founder-facing text: Task 5/6 renders it, and chrome is bilingual.
enum VoiceAudioError: Error, Equatable {
    case recognizerUnavailable
    case engineFailed(String)
    /// **Real audio flowed and recognition never said a word about it** — see
    /// `RecognitionWatchdog`, which decides when that is true, and `VoiceChrome
    /// .failureText`, which carries the remedy (macOS has to download its speech model,
    /// and the only place to make it do that is System Settings → Keyboard → Dictation).
    ///
    /// Its own case rather than an `engineFailed(String)`: nothing about the engine
    /// failed — it started, the tap fires, the buffers are real — and the remedy is
    /// unguessable, so a founder cannot be handed a generic "the microphone stopped"
    /// here. `Equatable` so a test can name which failure it means.
    case recognitionNeverAnswered
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
/// **The tap is on `inputNode`, mono, at the input bus's own sample rate — and the
/// intermediate `AVAudioMixerNode` this used to route through was the bug.**
///
/// Voice processing changes the input format to multi-channel (measured 3ch/24000,
/// 5ch/48000 and 7ch/48000 on this same Mac — it is renegotiated per session, never a
/// constant), and the recognizer needs mono. The mixer was introduced to do that
/// downmix, on the reasoning that `AVAudioConverter(7ch→1ch)` cannot: it *constructs* —
/// so the obvious code compiles and looks right — but reports `channelMap == [-1]`, no
/// valid source mapping, and its output is all zeros.
///
/// **That converter measurement is true and reproducible; the conclusion drawn from it
/// was not.** A mixer whose output bus is connected to nothing is never rendered, so
/// the tap on it fired ~10×/s, at the right frame count, delivering buffers that were
/// exactly zero in every sample — "voice mode hears nothing", no throw, nothing to
/// chase, and `onFailure` never reached because nothing failed. `installTap` on
/// `inputNode` with an explicit mono format does the 7ch→1ch downmix itself, which is
/// the only thing the mixer was ever for. Measured with `say` playing: five runs, real
/// audio, every buffer non-zero, peak 0.19–0.81.
///
/// **The sample rate must be the input bus's own.** Any other rate makes
/// `engine.start()` throw `-10875` (measured at 16000 and 44100) — so the class of
/// mistake that produced this bug can no longer be silent: `openMic` catches the throw
/// and renders it. Do not "help" by resampling here; `SFSpeechAudioBufferRecognitionRequest`
/// accepts the device rate and mono is the part it actually needs.
///
/// Two measured dead ends, so nobody re-derives them: connecting the mixer onward to
/// `mainMixerNode` to force it to render fails `engine.start()` with `-10875` while
/// voice processing is on — it does not even initialise, so the old "do not route the
/// mic to the speakers" warning reached the right answer by the wrong mechanism — and
/// dropping voice processing fails `-10868`, besides costing barge-in.
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

    /// **The four facts `RecognitionWatchdog` decides on, gathered from the two threads
    /// that know them.**
    ///
    /// Voiced buffers are counted on `AVAudioEngine`'s render thread; recognition
    /// callbacks arrive on whatever queue `SFSpeechRecognitionTask` uses; the verdict is
    /// read on the main actor. So this is a box, captured as a value by both closures
    /// exactly the way `feed` and the tap's `Counter` are — **no `self`**, so neither
    /// closure can keep a listener alive past its `deinit`, and no main-actor hop is
    /// introduced on the render thread.
    ///
    /// **`OSAllocatedUnfairLock`, following `VoiceLog.Counter` rather than
    /// `RequestFeed`.** `RequestFeed` argues its `NSLock` from measured numbers because
    /// it has to hold a lock across `SFSpeechAudioBufferRecognitionRequest.append`; this
    /// holds one across two integer adds, so an unfair lock — one atomic uncontended —
    /// is the cheaper and `Sendable`-by-construction choice, and needs no `@unchecked`.
    ///
    /// **`nonisolated`, not merely `Sendable`.** Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a bare `final class` is *inferred*
    /// main-actor, so `noteVoicedBuffer()` from the render thread would be a main-actor
    /// call from a nonisolated context: silent in Swift 5 mode, an error in Swift 6.
    /// Same reasoning as `RequestFeed`, `VoiceLevel` and `VoiceLog`.
    nonisolated final class RecognitionCensus: Sendable {

        /// A snapshot, so the watchdog reads all four facts from one lock acquisition
        /// and cannot decide against a half-updated pair.
        struct Facts: Equatable {
            /// Appended buffers whose level was not exactly zero. Cumulative for the
            /// session: "has real audio EVER arrived" is a session-level fact.
            var voicedBuffers = 0
            /// Recognition results delivered this session. Cumulative, and sticky by
            /// design — see `RecognitionWatchdog.Verdict.recognitionAnswered`.
            var results = 0
            /// Whether the **current** request has errored. Cleared by
            /// `requestOpened()`, because a renewal is a fresh chance to answer.
            var errored = false
            /// When the current request first saw real audio, on the monotonic clock.
            var firstVoiced: UInt64?
        }

        private let state = OSAllocatedUnfairLock(initialState: Facts())

        /// A buffer arrived carrying something other than digital silence.
        ///
        /// **`DispatchTime`, not `Date`.** The grace window is a duration, and
        /// `Date` is wall-clock: an NTP correction or the founder changing her clock
        /// mid-session would make the watchdog fire instantly or never.
        /// `uptimeNanoseconds` is `mach_absolute_time`, monotonic and cheap enough for
        /// the render thread.
        func noteVoicedBuffer() {
            let now = DispatchTime.now().uptimeNanoseconds
            state.withLock { facts in
                facts.voicedBuffers += 1
                if facts.firstVoiced == nil { facts.firstVoiced = now }
            }
        }

        /// A recognition callback arrived. **Counted before the listener's identity
        /// guard can drop it**, for the same reason the log line is: a dropped callback
        /// is still proof the channel is alive.
        func noteRecognitionCallback(isError: Bool) {
            state.withLock { facts in
                if isError { facts.errored = true } else { facts.results += 1 }
            }
        }

        /// A fresh request is now being fed. Clears the per-request facts and restarts
        /// the grace clock; `results` and `voicedBuffers` deliberately survive.
        func requestOpened() {
            state.withLock { facts in
                facts.errored = false
                facts.firstVoiced = nil
            }
        }

        var facts: Facts { state.withLock { $0 } }

        /// Seconds since the current request first saw real audio; `0` if it has not.
        /// `&-` because both readings come from the same monotonic clock and it cannot
        /// go backwards — the wrapping subtraction states that rather than trusting it.
        var sinceFirstVoicedBuffer: TimeInterval {
            guard let first = facts.firstVoiced else { return 0 }
            let now = DispatchTime.now().uptimeNanoseconds
            return Double(now &- first) / 1_000_000_000
        }
    }

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private let feed = RequestFeed()
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// Graph state, tracked so `stop()` can undo exactly what `start()` did, from
    /// any point at which it failed.
    ///
    /// **`AVAudioNode.h`'s "only one tap may be installed on any bus" now applies to
    /// `inputNode`,** which is the whole reason this flag and `stop()`'s `removeTap`
    /// have to name the same node as `installTap` does. Let them drift apart and the
    /// second `start()` installs a second tap on the input bus — an internal assertion,
    /// an uncatchable crash, not a thrown error. Verified: three start/stop cycles on
    /// one engine, each delivering real non-zero audio, no assertion.
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

    /// **Diagnostics only, and the one number that separates the two failures that
    /// look identical on screen.** A flat waveform with no partial is either "the tap
    /// never fired" or "the tap fired and every buffer was silence", and nothing on
    /// this path could tell them apart — see `VoiceLog`. Replaced on every `start()` so
    /// a second session counts from zero. Read from the render thread and from the main
    /// actor, which is why it is a `Counter` and not an `Int`.
    private var tapCounter = VoiceLog.Counter()

    /// The facts `RecognitionWatchdog` judges. Replaced on every `start()` so a second
    /// session is judged on its own evidence, and so a watchdog left running by a
    /// previous session can recognise that it is stale (`census === ` in `start()`).
    private var census = RecognitionCensus()

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

    // MARK: - The audio graph

    /// The tap format for a given input-bus format: **one channel, that bus's own
    /// sample rate.**
    ///
    /// Pure and `static` so the rule is testable. It is a two-line function carrying
    /// two separately-shipped defects, and neither was visible from a format dump:
    ///
    /// - **One channel** is what `SFSpeechAudioBufferRecognitionRequest` needs, and
    ///   `installTap` performs the downmix from whatever multi-channel format voice
    ///   processing negotiated. Inheriting the channel count instead handed the
    ///   recognizer stereo.
    /// - **That bus's own rate, never a chosen one.** Any other rate makes
    ///   `engine.start()` throw `-10875` — measured at 16000 and at 44100 — so a
    ///   resample "helpfully" added here does not degrade voice mode, it stops it dead.
    ///   16000 would be the tempting choice; it is the one that throws.
    ///
    /// `nil` only if `AVAudioFormat` refuses the combination, which `start()` reports
    /// as a thrown `engineFailed` rather than a silent fallback.
    nonisolated static func tapFormat(for inputFormat: AVAudioFormat) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: inputFormat.sampleRate,
                      channels: 1,
                      interleaved: false)
    }

    func start() throws {
        // Liveness before availability: a redundant `start()` on a healthy running
        // listener must be a no-op, not a thrown `recognizerUnavailable` because the
        // service happened to go away since it started.
        // The whole entry state on one line, because every one of these has been the
        // answer at some point: a redundant start, a withdrawn service, a recogniser
        // that exists and is unauthorised (`isAvailable` is service availability, NOT
        // authorisation — that defect shipped once), and the on-device claim the surface
        // makes in its credit line.
        VoiceLog.listener.log("""
            start(): isRunning=\(self.isRunning, privacy: .public) \
            hasRecognizer=\(self.recognizer != nil, privacy: .public) \
            isAvailable=\(self.recognizer?.isAvailable ?? false, privacy: .public) \
            supportsOnDevice=\(self.recognizer?.supportsOnDeviceRecognition ?? false, privacy: .public) \
            recognitionAuth=\(VoiceLog.describe(recognition: SFSpeechRecognizer.authorizationStatus()), privacy: .public) \
            micAuth=\(VoiceLog.describe(mic: AVCaptureDevice.authorizationStatus(for: .audio)), privacy: .public)
            """)

        guard !isRunning else {
            VoiceLog.listener.log("start(): already running — no-op")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            VoiceLog.listener.error("start(): recognizerUnavailable — throwing")
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
            VoiceLog.listener.log("setVoiceProcessingEnabled(true): ok")
        } catch {
            VoiceLog.listener.error("""
                setVoiceProcessingEnabled(true) THREW \
                \(VoiceLog.describe(error), privacy: .public)
                """)
            throw VoiceAudioError.engineFailed("voice processing: \(error.localizedDescription)")
        }

        // **Logged before anything uses it, because it is not a constant.** With voice
        // processing on, the VPIO unit renegotiates this per session — measured 3ch/24000,
        // 5ch/48000 and 7ch/48000 on the SAME Mac minutes apart — so a format recorded
        // once in a comment is a format that is wrong on the run you are chasing. It is
        // also the only input to `tapFormat` below, which is why it is read once here
        // rather than at each use.
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        VoiceLog.listener.log("""
            inputNode.outputFormat(0) = \(VoiceLog.describe(inputFormat), privacy: .public)
            """)

        // **Mono at the input bus's OWN rate. No intermediate node — see the class
        // comment for why one was here and why it produced silence.**
        //
        // `installTap` does the multi-channel → 1ch downmix itself, and the rate must
        // match the bus: 16000 and 44100 each make `engine.start()` throw `-10875`, so
        // getting this wrong is loud now instead of silent. `SpeechListener.tapFormat`
        // is the pure derivation, so a test can hold the "same rate, one channel" rule
        // without a microphone.
        guard let tapFormat = Self.tapFormat(for: inputFormat) else {
            VoiceLog.listener.error("""
                could not build the mono tap format at \
                \(inputFormat.sampleRate, privacy: .public)Hz — throwing
                """)
            throw VoiceAudioError.engineFailed("could not build the mono tap format")
        }
        VoiceLog.listener.log("tapFormat = \(VoiceLog.describe(tapFormat), privacy: .public)")

        // **Fresh per session, and before `openRecognition` so the recognition callback
        // captures THIS session's box.** A session that inherited a previous one's
        // `results > 0` would never police itself again — armed and permanently
        // satisfied.
        let census = RecognitionCensus()
        self.census = census

        openRecognition(recognizer)

        // 4800 frames is 100ms at 48000 and 200ms at 24000 — both rates the input bus
        // has been measured at. `AVAudioNode.h`: "Supported range is [100, 400] ms", so
        // 4800 is inside it at every rate this bus has produced. The shipped 1024 was
        // 23ms, outside it.
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
        // **Captured the same way `feed` is, and for the same reason.** A `Counter` is
        // `Sendable`, so this is a value the closure owns rather than a reach back
        // through `self` — no main-actor hop, no race, and nothing here can keep the
        // listener alive. A fresh one per `start()` so the census below counts THIS
        // session.
        let counter = VoiceLog.Counter()
        self.tapCounter = counter
        engine.inputNode.installTap(onBus: 0, bufferSize: 4800, format: tapFormat) { @Sendable [weak self] buf, _ in
            // **Counted first, before any guard can return.** The point of the count is
            // to distinguish "the tap never fired" from "the tap fired and the buffers
            // were wrong", so a callback that falls out of one of the guards below must
            // still be counted — otherwise the two failures look identical again, which
            // is the whole reason this exists.
            let calls = counter.note(frames: Int(buf.frameLength))
            feed.append(buf)
            guard let channel = buf.floatChannelData?[0] else {
                if calls <= 3 {
                    VoiceLog.tap.error("""
                        tap #\(calls, privacy: .public): no float channel data — \
                        format=\(VoiceLog.describe(buf.format), privacy: .public)
                        """)
                }
                return
            }
            let frames = Int(buf.frameLength)
            guard frames > 0 else {
                if calls <= 3 {
                    VoiceLog.tap.error("tap #\(calls, privacy: .public): frameLength 0")
                }
                return
            }
            let level = VoiceLevel.level(from: UnsafeBufferPointer(start: channel, count: frames))
            // **The one fact `RecognitionWatchdog` needs from this thread**, recorded
            // here rather than up beside `counter.note` because it is the *level* that
            // decides it and the level is not known until now. `> 0`, not a tuned floor:
            // see `RecognitionWatchdog.verdict` — a level of exactly zero cannot come
            // from a live microphone, so this separates "the audio path is dead" from
            // "the audio path is alive", which is all it claims to do and all it can.
            //
            // A second lock acquisition per buffer on the render thread, deliberately:
            // it keeps `counter.note` first and unguarded (the reason that ordering
            // exists), and an uncontended `OSAllocatedUnfairLock` around one integer add
            // is a single atomic. See `RecognitionCensus`.
            if level > 0 { census.noteVoicedBuffer() }
            // **The first three and then silence, forever.** `os_log` is cheap but it is
            // not real-time safe, and this runs ~10 times a second on the render thread
            // for as long as voice mode is open; three calls in the life of a session is
            // a cost worth paying and three hundred is not. The count keeps rising after
            // the logging stops, so the census below still has a real number.
            //
            // `level == 0` is reported as its own flag, not left to be read off a
            // formatted Float. It is the single most diagnostic bit on this path: RMS
            // over 4800 samples of a live microphone is never EXACTLY zero — a real mic
            // has a noise floor — so `zero=true` means the buffers are zero-filled and
            // the audio is not arriving, while a small non-zero level means it is
            // arriving and the founder is simply not talking loudly enough.
            if calls <= 3 {
                VoiceLog.tap.log("""
                    tap #\(calls, privacy: .public): frames=\(frames, privacy: .public) \
                    level=\(level, privacy: .public) zero=\(level == 0, privacy: .public) \
                    totalFrames=\(counter.frames, privacy: .public)
                    """)
            }
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
        catch {
            // **Domain and code.** `-10875` (`kAudioUnitErr_FailedInitialization`) and
            // `-10868` (`kAudioUnitErr_FormatNotSupported`) are how this graph refuses a
            // format it cannot render, and both read as the same empty
            // `localizedDescription` — which is what `engineFailed` carries to the
            // surface.
            VoiceLog.listener.error("""
                engine.start() THREW \(VoiceLog.describe(error), privacy: .public)
                """)
            throw VoiceAudioError.engineFailed(error.localizedDescription)
        }
        VoiceLog.listener.log("""
            engine.start(): ok — isRunning=\(self.engine.isRunning, privacy: .public)
            """)

        // **The census, and it is the whole point of the counter.**
        //
        // A tap that never fires produces no log lines at all, and no log lines is
        // exactly what a working-but-quiet tap that has stopped after its third line
        // also produces. So one line, once, that states the count out loud — an absence
        // becomes `callbacks=0`, which is a fact you can point at instead of a gap you
        // have to infer.
        //
        // 2s at ~10 callbacks a second means a healthy session reports ~19, and the
        // `tap` lines' `zero=` flag is what says whether those callbacks carried audio —
        // the two facts that came apart and cost this feature a week. Captures the
        // `Counter` and nothing else: no `self`, so this cannot keep a listener alive
        // past its `deinit`, and a session torn down before the deadline simply reports
        // the count it reached. Deliberately not cancelled on `stop()` — a stopped
        // listener's count is the most interesting count there is.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            VoiceLog.listener.log("""
                census 2s after start: callbacks=\(counter.calls, privacy: .public) \
                frames=\(counter.frames, privacy: .public) \
                voicedBuffers=\(census.facts.voicedBuffers, privacy: .public) \
                recognitionResults=\(census.facts.results, privacy: .public) \
                errored=\(census.facts.errored, privacy: .public) \
                — 0 callbacks means the tap never fired; callbacks with 0 voicedBuffers \
                means it fired on a bus nothing renders
                """)
        }

        startWatchdog(census)

        succeeded = true
        isRunning = true
    }

    /// **The one periodic thing on this path, and the only mechanism that can see the
    /// failure it exists for.**
    ///
    /// Every other safety net here is driven by a recognition callback —
    /// `recognitionUpdate` → `endOfTask` → `RenewalBudget` — so a recognizer that
    /// accepts audio and answers *nothing* is invisible to all of them. Reproduced
    /// standalone, outside the project, on this Mac: 45s, 450 real buffers appended,
    /// zero callbacks. There is nothing to hang a check off, so the check has to ask.
    ///
    /// The decision is `RecognitionWatchdog`'s and every number in it is stated there.
    /// This is the loop and nothing else — deliberately, because the loop is the part no
    /// test may run and the decision is the part that has to be tested.
    ///
    /// **It is not the 4Hz silence watcher spec §2 decision 4 deleted.** That one took
    /// the founder's turn on silence. This takes no turn, touches no transcript, and can
    /// only report a fault — see `RecognitionWatchdog.tick`.
    ///
    /// **`[weak self]` and a stale-census guard.** The task must not keep a listener
    /// alive past its `deinit`, and a task left running by session N must not fire
    /// against session N+1's listener — so it exits when `self` is gone, when the
    /// listener has stopped, and when `self.census` is no longer the box it was started
    /// with. It also exits the moment the verdict is decided either way, so a healthy
    /// conversation pays for a handful of ticks and then nothing.
    private func startWatchdog(_ census: RecognitionCensus) {
        Task { @MainActor [weak self] in
            while true {
                // **`do`/`catch`, not the `try?` the 2s census uses.** That one sleeps
                // once; this one loops, and `Task.sleep` returns immediately when the
                // task is cancelled — swallowed with `try?` a cancellation would turn
                // this into a hot spin on the main actor rather than an exit.
                do {
                    try await Task.sleep(nanoseconds: UInt64(RecognitionWatchdog.tick * 1_000_000_000))
                } catch {
                    return
                }
                guard let self, self.isRunning, self.census === census else { return }
                let facts = census.facts
                let verdict = RecognitionWatchdog.verdict(
                    voicedBuffers: facts.voicedBuffers,
                    results: facts.results,
                    errored: facts.errored,
                    sinceFirstVoicedBuffer: census.sinceFirstVoicedBuffer)
                switch verdict {
                case .keepWaiting:
                    continue
                case .recognitionAnswered:
                    // Once, so a healthy session's trace says the watchdog stood down
                    // rather than simply going quiet — the same reason the 2s census
                    // exists at all.
                    VoiceLog.recognition.log("""
                        watchdog: standing down — recognition answered \
                        (results=\(facts.results, privacy: .public))
                        """)
                    return
                case .recognitionNeverAnswered:
                    VoiceLog.recognition.error("""
                        watchdog: FAILING after \
                        \(RecognitionWatchdog.grace, privacy: .public)s — \
                        voicedBuffers=\(facts.voicedBuffers, privacy: .public) \
                        results=0 errored=false. Real audio flowed and recognition never \
                        answered: macOS most likely has no speech model installed \
                        (System Settings → Keyboard → Dictation)
                        """)
                    // Ordered exactly as `endOfTask`'s `.fail` branch is: stop first, so
                    // `isRunning` is already false when the surface handles this and the
                    // cancellation callback `retireRecognition()` may deliver is dropped
                    // by the identity guard rather than reported twice.
                    self.stop()
                    self.onFailure?(VoiceAudioError.recognitionNeverAnswered)
                    return
                }
            }
        }
    }

    /// Idempotent and unconditional. It used to `guard isRunning`, which made it
    /// useless as a rollback for a half-configured graph — the exact case it is
    /// most needed for.
    func stop() {
        // The tap's lifetime total, at the one moment it is final. A session that ends
        // with `callbacks=0` never heard anything and never could have.
        VoiceLog.listener.log("""
            stop(): isRunning=\(self.isRunning, privacy: .public) \
            tapInstalled=\(self.tapInstalled, privacy: .public) \
            voiceProcessingOn=\(self.voiceProcessingOn, privacy: .public) \
            tapCallbacks=\(self.tapCounter.calls, privacy: .public) \
            tapFrames=\(self.tapCounter.frames, privacy: .public) \
            voicedBuffers=\(self.census.facts.voicedBuffers, privacy: .public) \
            recognitionResults=\(self.census.facts.results, privacy: .public)
            """)
        // Tap first, then end the audio: the other order can let one more buffer
        // reach a request that has already been closed.
        // **`inputNode`, the same node `start()` tapped.** If these two ever name
        // different nodes the tap is never removed and the next `start()` is an
        // uncatchable assertion — see `tapInstalled`.
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
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
        // **A renewal is a fresh chance to answer, so the grace window restarts here.**
        // Without this the founder's own sequence stays broken: request 1 errors
        // (`kAFAssistantErrorDomain/1110`), `RenewalBudget` renews, and request 2 answers
        // nothing at all — with `errored` still set from request 1 the watchdog would
        // defer to a budget that is never consulted again, which is the original bug
        // with one more mechanism failing to notice it.
        let census = self.census
        census.requestOpened()

        VoiceLog.recognition.log("""
            openRecognition(): requiresOnDevice=\(req.requiresOnDeviceRecognition, privacy: .public) \
            hints=\(self.hints.count, privacy: .public) \
            isAvailable=\(recognizer.isAvailable, privacy: .public) \
            auth=\(VoiceLog.describe(recognition: SFSpeechRecognizer.authorizationStatus()), privacy: .public)
            """)

        // **Count-limited per request, not per session.** Partials arrive several times a
        // second once recognition is working, and the question this log has to answer is
        // "did ANY partial ever arrive", which the first few settle. Errors and finals are
        // always logged: those are the ones that end a task, and there are at most a
        // couple per request.
        let callbacks = VoiceLog.Counter()
        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            // Only `String` and `Bool` cross the hop from the result:
            // `SFSpeechRecognitionResult` is not Sendable.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            // **Logged HERE, before the hop and before the identity guard.** A callback
            // that `recognitionUpdate` drops as stale is still a callback that happened,
            // and the guard dropping every one of them is itself a candidate cause — so
            // this has to be recorded upstream of it or the drop is invisible.
            //
            // **Length, never the text.** The transcript is the founder's words.
            let n = callbacks.note(frames: text?.count ?? 0)
            // **Recorded here for the same reason the log line is, and it is what
            // disarms the watchdog.** A callback that `recognitionUpdate` drops as stale
            // is still proof the recognition channel is alive, and the watchdog's whole
            // question is whether it ever is.
            census.noteRecognitionCallback(isError: error != nil)
            if let error {
                VoiceLog.recognition.error("""
                    task callback #\(n, privacy: .public): ERROR \
                    \(VoiceLog.describe(error), privacy: .public) \
                    isFinal=\(isFinal, privacy: .public) textLen=\(text?.count ?? -1, privacy: .public)
                    """)
            } else if isFinal || n <= 5 {
                VoiceLog.recognition.log("""
                    task callback #\(n, privacy: .public): \
                    isFinal=\(isFinal, privacy: .public) textLen=\(text?.count ?? -1, privacy: .public)
                    """)
            }
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
        guard isRunning, feed.isCurrent(req) else {
            // The drop is a fact, and a session where EVERY callback is dropped looks
            // from the surface exactly like a session where none ever arrived.
            VoiceLog.recognition.log("""
                recognitionUpdate: DROPPED — isRunning=\(self.isRunning, privacy: .public) \
                isCurrentRequest=\(self.feed.isCurrent(req), privacy: .public)
                """)
            return
        }

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
        let decision = budget.taskEnded()
        // The decision AND the counter behind it. `renewalsSpent` is read after
        // `taskEnded()` has moved it, so this line is the state the next task end will
        // be judged against — which is the number you want when asking why a session
        // gave up (or why it never does).
        VoiceLog.recognition.log("""
            endOfTask: decision=\(String(describing: decision), privacy: .public) \
            renewalsSpent=\(self.budget.renewalsSpent, privacy: .public)/\(RenewalBudget.allowance, privacy: .public) \
            error=\(error.map { VoiceLog.describe($0) } ?? "none", privacy: .public)
            """)
        switch decision {
        case .renew:
            renew()
        case .fail:
            // Ordered: stop first, so `isRunning` is already false when the surface
            // handles this, and the cancellation error `retireRecognition()` may
            // deliver is dropped by the identity guard rather than reported twice.
            stop()
            VoiceLog.recognition.error("endOfTask: reporting failure to the surface")
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
            VoiceLog.recognition.error("""
                renew(): UNREACHABLE branch taken — isRunning=\(self.isRunning, privacy: .public) \
                hasRecognizer=\(self.recognizer != nil, privacy: .public)
                """)
            stop()
            onFailure?(VoiceAudioError.recognizerUnavailable)
            return
        }
        VoiceLog.recognition.log("renew(): retiring the request and opening a fresh one")
        // `retireRecognition()` commits the retiring request's transcript, so the
        // founder's turn crosses the swap intact — see `TurnTranscript`.
        retireRecognition()
        openRecognition(recognizer)
    }
}
