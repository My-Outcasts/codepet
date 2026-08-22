// codepet/Services/VoiceLog.swift
import AVFoundation
import Foundation
import Speech
import os

/// **Diagnostics for the voice path, which had none at all.**
///
/// The whole stack — `VoicePermission`, `SpeechListener`, `VoiceTurn`,
/// `VoiceComposer` — shipped with zero logging, and the one failure it was built to
/// prevent is invisible without it: a composer reading `Listening…` with a flat
/// waveform, no partial, no failure. Every layer is individually correct and
/// individually tested, and the fault is *between* the layers, in the one place no
/// test may go (a real `AVAudioEngine`, a real `SFSpeechRecognizer`, a real
/// microphone). There was literally nothing to read.
///
/// **`os.Logger`, not `print`.** The app is launched with `open`, which discards
/// stdout, so `print` from a released build goes nowhere at all — which is part of why
/// this was invisible. The unified log survives the process and is readable after the
/// fact:
///
/// ```
/// log show --last 5m --predicate 'subsystem == "app.murror.codepet.voice"' --style compact
/// ```
///
/// **Its own subsystem, not `app.murror.codepet` + a category.** The rest of the app
/// logs under the bundle id, so sharing it would mean the founder's read command has to
/// carry a category filter she has to get right while chasing a bug. One tap of the
/// waveform button should be one predicate.
///
/// **Everything is `.public` and every level is default (`log`/`error`).** Two traps,
/// both of which produce a log that looks like it worked:
///
/// 1. `Logger`'s default interpolation privacy is `.private`, which renders every value
///    as `<private>` when read back from another process. A trace of `<private>` is not
///    a trace.
/// 2. `log show` without `--info --debug` shows only default-level and above. A
///    `.debug` line is not persisted at all unless the subsystem is being streamed
///    live. So the ~25 lines one tap produces are all at default level, and the
///    high-frequency paths are *rate-limited by count* (see `Counter`) rather than
///    demoted to `.debug` — an absence you can point to beats a line you cannot read.
///
/// **No transcript text is ever logged, only its length.** The founder's words are the
/// one thing on this path that is hers.
///
/// **Every member is `nonisolated`, and that is load-bearing.** Under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` even a `static let` on an enum is
/// *inferred* main-actor, so reading one from `AVAudioEngine`'s render thread — which
/// is exactly where the tap probe lives — would be a main-actor access from a
/// nonisolated context. Silent in Swift 5 mode, an error in Swift 6. Same reasoning,
/// and the same fix, as `VoiceLevel` and `SpeechListener.RequestFeed`.
enum VoiceLog {

    nonisolated static let subsystem = "app.murror.codepet.voice"

    /// The two TCC grants: what they were, whether they were asked for, what came back.
    nonisolated static let permission = Logger(subsystem: subsystem, category: "permission")
    /// `SpeechListener.start()`/`stop()` — the audio graph, step by step.
    nonisolated static let listener = Logger(subsystem: subsystem, category: "listener")
    /// The audio tap. **Count-limited**: the first three callbacks and nothing after.
    nonisolated static let tap = Logger(subsystem: subsystem, category: "tap")
    /// `SFSpeechRecognitionTask` results and errors, and the renewal decisions.
    nonisolated static let recognition = Logger(subsystem: subsystem, category: "recognition")
    /// The surface: entering voice mode, opening the mic, showing a failure.
    nonisolated static let surface = Logger(subsystem: subsystem, category: "surface")

    // MARK: - Describing the things that matter

    /// **Domain and code, not `localizedDescription`.** `kAFAssistantErrorDomain` codes
    /// are the only thing that separates "no speech detected" from an authorisation
    /// failure, and both render as the same unhelpful sentence. The description is kept
    /// as well, last, because it is occasionally the only readable part.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)/\(ns.code) — \(ns.localizedDescription)"
    }

    /// Channels, rate, interleaving. All three have been the fault at some point on
    /// this path, and a rate alone reads as fine while a channel count is wrong.
    nonisolated static func describe(_ format: AVAudioFormat) -> String {
        "\(format.channelCount)ch/\(Int(format.sampleRate))Hz"
            + " interleaved=\(format.isInterleaved) common=\(format.commonFormat.rawValue)"
    }

    nonisolated static func describe(mic: AVAuthorizationStatus) -> String {
        switch mic {
        case .notDetermined: return "notDetermined"
        case .restricted:    return "restricted"
        case .denied:        return "denied"
        case .authorized:    return "authorized"
        @unknown default:    return "unknown(\(mic.rawValue))"
        }
    }

    nonisolated static func describe(recognition status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .authorized:    return "authorized"
        @unknown default:    return "unknown(\(status.rawValue))"
        }
    }

    nonisolated static func describe(_ availability: VoiceAvailability) -> String {
        switch availability {
        case .ready:                  return "ready"
        case .needsPermission:        return "needsPermission"
        case .denied(let which):      return "denied(\(which))"
        case .unsupported(let why):   return "unsupported(\(why))"
        }
    }

    // MARK: - Counting on the render thread

    /// A call counter for a callback that fires ten times a second on a real-time
    /// thread, so the log can carry its first few and then go quiet.
    ///
    /// **Why a type and not an `Int`.** The audio tap is `@Sendable` and runs on
    /// `AVAudioEngine`'s render thread while the 2s census reads the same count from the
    /// main actor. A bare captured `var` would be a data race — the exact class of
    /// defect the tap's own comments spend twenty lines being careful about, and it
    /// would be indefensible to introduce one *in a diagnostic*.
    ///
    /// **`OSAllocatedUnfairLock`, not `NSLock`.** `SpeechListener.RequestFeed` argues
    /// its `NSLock` on the render thread from measured numbers, and that argument is
    /// about a lock that has to be there. This one does not have to be: an unfair lock
    /// is a single atomic in the uncontended case, the critical section is one integer
    /// add, and the only competing reader takes it twice in the life of a session. It is
    /// also `Sendable` by construction, so the closure capture needs no `@unchecked`.
    ///
    /// **The logging it gates is bounded by construction.** `note()` returns the new
    /// count and every call site logs only while that count is small, so a session that
    /// runs for an hour writes the same number of lines as one that runs for a second.
    nonisolated final class Counter: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: Tally())

        private struct Tally { var calls = 0; var frames = 0 }

        /// Record a callback carrying `frames` samples; returns the new call count.
        func note(frames: Int) -> Int {
            state.withLock { tally in
                tally.calls += 1
                tally.frames += frames
                return tally.calls
            }
        }

        var calls: Int { state.withLock { $0.calls } }
        var frames: Int { state.withLock { $0.frames } }
    }
}
