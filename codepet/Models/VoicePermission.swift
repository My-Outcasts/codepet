// codepet/Models/VoicePermission.swift
import AVFoundation
import Foundation
import Speech

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
    /// `.needsPermission` counts as YES on purpose: tapping is what raises the TCC
    /// prompt, so a button hidden until permission is granted makes the permission
    /// unreachable and voice mode permanently dead. A refusal or a missing
    /// recogniser counts as NO, with `help` supplying the reason — a disabled
    /// control that explains itself beats a dead click that does not.
    static func offersButton(_ availability: VoiceAvailability) -> Bool {
        switch availability {
        case .ready, .needsPermission: return true
        case .denied, .unsupported:    return false
        }
    }

    /// Live statuses, for the view. Not called by tests.
    static func current(locale: Locale) -> VoiceAvailability {
        availability(mic: AVCaptureDevice.authorizationStatus(for: .audio),
                     recognition: SFSpeechRecognizer.authorizationStatus(),
                     hasRecognizer: SFSpeechRecognizer(locale: locale) != nil)
    }
}
