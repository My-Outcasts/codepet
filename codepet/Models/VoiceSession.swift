// codepet/Models/VoiceSession.swift
import Foundation

/// Where a voice-mode conversation is — spec §4.
enum VoiceState: Equatable {
    /// No overlay. The mic is not running.
    case idle
    /// Mic live, recognition streaming partials, ✕ and ✓ offered beneath the
    /// transcript. **No timer** — spec §2 decision 4: silence does nothing at all,
    /// and the mic keeps capturing until the founder decides.
    case listening
    /// The turn was sent; `sendChat` is working. Nothing is captured.
    case thinking
    /// A reply is being read aloud, sentence by sentence.
    case speaking
}

/// What can happen to a voice session.
enum VoiceEvent: Equatable {
    /// The founder tapped the waveform.
    case open
    /// The founder tapped ✓ — she is taking her turn.
    ///
    /// **It was `heardSilence` until 21 Aug, and the name was the design.** A timer
    /// fired this event 1.2s after she stopped talking; spec §2 decision 4 reversed
    /// that, so the only thing that produces it now is a tap. The transition it
    /// drives is unchanged — a turn taken is a turn taken, whoever decided it — but a
    /// case called `heardSilence` in a file with no timer in it is the kind of stale
    /// name that gets a silence deadline re-implemented to match it.
    case founderSentTurn
    /// The first speakable sentence of the reply is ready.
    case replyBegan
    /// The synthesiser drained its queue and the reply is complete.
    case replyFinished
    /// The founder started talking over the reply.
    case founderInterrupted
    /// The founder dismissed the overlay.
    case close
}

/// The loop, as a value type.
///
/// **Why this is not just `@State` in the overlay.** The interesting behaviour is
/// what it REFUSES. Audio callbacks are asynchronous and arrive late: a recognition
/// result after the founder closed the overlay, a synthesiser `didFinish` for a
/// reply that was already interrupted. `apply` returns whether the transition was
/// legal so a late callback is a no-op instead of a reopened overlay with a dead
/// microphone — and a test can assert the refusal, which it cannot do to a view.
struct VoiceSession {
    private(set) var state: VoiceState = .idle

    init() {}

    var isActive: Bool { state != .idle }

    /// Apply `event`, returning `false` when it was not legal from the current
    /// state. A `false` return is expected and normal, not an error to log.
    @discardableResult
    mutating func apply(_ event: VoiceEvent) -> Bool {
        // Close always wins, from anywhere, including idle→idle being a no-op that
        // still counts as handled: the founder pressing ✕ twice is not a bug.
        if event == .close {
            let changed = state != .idle
            state = .idle
            return changed
        }
        switch (state, event) {
        case (.idle, .open):
            state = .listening;  return true
        case (.listening, .founderSentTurn):
            state = .thinking;   return true
        case (.thinking, .replyBegan):
            state = .speaking;   return true
        case (.speaking, .replyFinished),
             (.speaking, .founderInterrupted):
            // Both return to listening: a finished reply and an interrupted one
            // leave the founder holding the conversation either way.
            state = .listening;  return true
        default:
            return false
        }
    }
}
