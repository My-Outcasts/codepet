// codepet/Models/VoicePermission.swift
import AVFoundation
import Foundation
import Speech
import os

/// Whether voice mode can run right now, and why not.
enum VoiceAvailability: Equatable {
    case ready
    /// Not asked yet — the button should ask rather than look broken.
    case needsPermission
    /// Refused. The string names WHICH grant is missing.
    case denied(String)
    /// Nothing the founder can grant will help — no recognizer for this locale.
    case unsupported(String)
}

/// Maps the two TCC statuses onto one answer.
///
/// Pure, taking raw statuses, because a test cannot drive TCC and every
/// combination matters: either grant can be refused on its own, and a missing
/// recognizer is a third thing that looks like a refusal but is not.
enum VoicePermission {

    static func availability(mic: AVAuthorizationStatus,
                             recognition: SFSpeechRecognizerAuthorizationStatus,
                             hasRecognizer: Bool) -> VoiceAvailability {
        guard hasRecognizer else {
            return .unsupported("No speech recogniser for this language.")
        }
        if mic == .denied || mic == .restricted {
            return .denied("Microphone access is off.")
        }
        if recognition == .denied || recognition == .restricted {
            return .denied("Speech recognition is off.")
        }
        if mic == .notDetermined || recognition == .notDetermined {
            return .needsPermission
        }
        return (mic == .authorized && recognition == .authorized)
            ? .ready
            : .denied("Microphone access is off.")
    }

    /// What to put under a disabled button. `nil` when there is nothing to say.
    ///
    /// Every branch names the fix. "Voice mode unavailable" with no reason is the
    /// message that generates support mail.
    static func help(_ availability: VoiceAvailability, _ lang: AppLanguage) -> String? {
        switch availability {
        case .ready:
            return nil
        case .needsPermission:
            return lang == .vi
                ? "Codepet sẽ xin quyền micro và nhận dạng giọng nói."
                : "Codepet will ask for microphone and speech recognition access."
        case .denied(let which):
            return lang == .vi
                ? "\(which) Mở System Settings › Privacy & Security để bật."
                : "\(which) Turn it on in System Settings › Privacy & Security."
        case .unsupported(let why):
            return lang == .vi
                ? "\(why) Không có cách nào bật tính năng này cho ngôn ngữ này."
                : why
        }
    }

    /// Whether the waveform button is tappable.
    ///
    /// `.needsPermission` counts as YES on purpose: tapping is what **requests** the
    /// two grants (`request(locale:)`), so a button hidden until permission is
    /// granted makes the permission unreachable and voice mode permanently dead. A
    /// refusal or a missing recogniser counts as NO, with `help` supplying the
    /// reason — a disabled control that explains itself beats a dead click that
    /// does not.
    static func offersButton(_ availability: VoiceAvailability) -> Bool {
        switch availability {
        case .ready, .needsPermission: return true
        case .denied, .unsupported:    return false
        }
    }

    /// The waveform button's whole rule: permission **and** an idle conversation.
    ///
    /// **`isBusy` is here because of what happens without it, and it is not a
    /// cosmetic dim.** The surface can be opened while a typed turn is still
    /// streaming; the founder then speaks into a `.listening` surface that has never
    /// called `beginReply()`, so when that typed reply finishes, `endOfReply()` lands
    /// on a virgin `SpeakingQueue`, which drains and reports — firing
    /// `onFinishedAll`, i.e. the whole reply-end path, for a reply this surface never
    /// asked for. That used to clear `partial`: her spoken question erased mid-flight,
    /// with no message, no waveform change and no credit spent — silence, and she had to say
    /// it again. `VoiceTurnFlow.replyEnded` no longer clears the transcript, so what
    /// is left is the waveform dropping to zero and a `.replyFinished` taken on someone
    /// else's reply. `VoiceComposer`'s `replyStreamEnded` gate closes the same hole
    /// from the other side; this is the half that stops her getting into the situation
    /// at all.
    ///
    /// Extracted rather than written inline in `.disabled` because its failure is
    /// invisible on screen — a button that is merely enabled one moment too early
    /// looks exactly like a button that is right.
    static func canEnterVoiceMode(_ availability: VoiceAvailability, isBusy: Bool) -> Bool {
        offersButton(availability) && !isBusy
    }

    /// Live statuses, for the view. Not called by tests.
    static func current(locale: Locale) -> VoiceAvailability {
        availability(mic: AVCaptureDevice.authorizationStatus(for: .audio),
                     recognition: SFSpeechRecognizer.authorizationStatus(),
                     hasRecognizer: SFSpeechRecognizer(locale: locale) != nil)
    }

    /// **Raise both TCC prompts, then answer with what the founder actually chose.**
    /// Live TCC, so not called by tests — same rule as `current`.
    ///
    /// This exists because `availability` only ever *reads*. Nothing in the app
    /// requested speech-recognition authorisation, and macOS never raises that prompt
    /// on its own: Apple requires the explicit `requestAuthorization` call, so
    /// `authorizationStatus()` stayed `.notDetermined` for every founder forever. The
    /// button offered a prompt the app never asked for, `SpeechListener.start()`
    /// succeeded anyway (`isAvailable` is service availability, not authorisation),
    /// the waveform pulsed, and the recognition task failed with a raw
    /// `kAFAssistantErrorDomain` string. Voice mode could not work for anyone.
    ///
    /// **Microphone first, and it short-circuits.** Recognition cannot do anything
    /// with an input the app may not open, so a second dialog after a refused
    /// microphone asks for a grant that buys nothing — and leaving recognition
    /// `.notDetermined` is what lets the *next* tap ask for it once the founder has
    /// turned the microphone back on in System Settings.
    ///
    /// The microphone is requested explicitly rather than left to the implicit prompt
    /// macOS raises when the input node is touched: that one arrives *after* the
    /// surface is on screen and the engine is starting, so the order the founder sees
    /// would depend on how fast `start()` got that far.
    ///
    /// `SFSpeechRecognizer.requestAuthorization`'s completion arrives on an arbitrary
    /// queue. It is bridged through a continuation, so the `await` resumes back on
    /// this actor and every caller's state write is already on the main actor —
    /// rather than hopping by hand inside a callback, or blocking on a semaphore
    /// while a modal TCC dialog waits for the main thread that would be blocked.
    static func request(locale: Locale) async -> VoiceAvailability {
        // **The two statuses BEFORE anything is asked for.** The shipped defect was that
        // recognition authorisation stayed `.notDetermined` forever because nothing ever
        // called `requestAuthorization`, and the only way to be sure the fix is reached
        // is to see the status go from `notDetermined` to something else across this
        // function — which needs both ends recorded.
        VoiceLog.permission.log("""
            request(): entry mic=\(describe(mic: AVCaptureDevice.authorizationStatus(for: .audio)), privacy: .public) \
            recognition=\(describe(recognition: SFSpeechRecognizer.authorizationStatus()), privacy: .public) \
            locale=\(locale.identifier, privacy: .public)
            """)

        // Nothing to ask for: no recogniser for this locale is `.unsupported`, and no
        // grant the founder can give changes it. Asking anyway would raise two
        // dialogs for a feature that still cannot run.
        guard SFSpeechRecognizer(locale: locale) != nil else {
            VoiceLog.permission.error("""
                request(): no recogniser for \(locale.identifier, privacy: .public) — asking for nothing
                """)
            return logged(current(locale: locale))
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            VoiceLog.permission.log("request(): raising the microphone prompt")
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            VoiceLog.permission.log("""
                request(): microphone prompt returned, now \
                \(describe(mic: AVCaptureDevice.authorizationStatus(for: .audio)), privacy: .public)
                """)
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            VoiceLog.permission.log("request(): microphone not authorised — short-circuiting")
            return logged(current(locale: locale))
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            VoiceLog.permission.log("request(): raising the speech-recognition prompt")
            let status = await requestRecognition()
            // **The completion, honoured and visible.** This is the continuation
            // resuming; if this line is missing from a trace while the previous one is
            // present, the callback never came back and the `await` is still parked.
            VoiceLog.permission.log("""
                request(): recognition prompt returned \
                \(describe(recognition: status), privacy: .public) \
                (status now \(describe(recognition: SFSpeechRecognizer.authorizationStatus()), privacy: .public))
                """)
        }
        return logged(current(locale: locale))
    }

    /// Every `return` out of `request` goes through here, so the answer the button and
    /// `startVoiceMode` act on is in the trace exactly once per tap — including the
    /// early exits, which are the ones that used to leave a tap looking like a no-op.
    private static func logged(_ availability: VoiceAvailability) -> VoiceAvailability {
        VoiceLog.permission.log("""
            request(): answer=\(VoiceLog.describe(availability), privacy: .public) \
            mic=\(describe(mic: AVCaptureDevice.authorizationStatus(for: .audio)), privacy: .public) \
            recognition=\(describe(recognition: SFSpeechRecognizer.authorizationStatus()), privacy: .public)
            """)
        return availability
    }

    private static func describe(mic status: AVAuthorizationStatus) -> String {
        VoiceLog.describe(mic: status)
    }

    private static func describe(recognition status: SFSpeechRecognizerAuthorizationStatus) -> String {
        VoiceLog.describe(recognition: status)
    }

    private static func requestRecognition() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // `@Sendable` deliberately: under `SWIFT_DEFAULT_ACTOR_ISOLATION =
            // MainActor` this closure would otherwise be *inferred* main-actor while
            // Speech invokes it on an arbitrary queue. Only the status crosses, and
            // `resume` is safe from any thread.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
}
