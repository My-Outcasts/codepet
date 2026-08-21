import Foundation

/// When the founder's turn is over.
///
/// Extracted from `SpeechListener` so the one number she is most likely to
/// complain about is adjustable and testable without a microphone.
enum VoiceTurn {
    /// Founder's call, 21 Aug — matches ChatGPT's feel. Spec §2, decision 3.
    ///
    /// Deliberately a single named constant: 1.2s is wrong for someone who pauses
    /// mid-thought and wrong for someone who talks fast, and no spike settles it.
    /// It needs the founder talking to the built thing.
    static let silenceThreshold: TimeInterval = 1.2

    /// Whether `now` is far enough past the last speech to end the turn.
    ///
    /// `nil` means nothing has been heard yet and NEVER ends a turn: otherwise
    /// opening the overlay and pausing to think would send an empty message and
    /// spend a credit on it. A `lastSpeechAt` in the future (clock adjustment,
    /// injected test date) is treated the same way.
    static func shouldEndTurn(lastSpeechAt: Date?, now: Date,
                              threshold: TimeInterval = silenceThreshold) -> Bool {
        guard let last = lastSpeechAt else { return false }
        let gap = now.timeIntervalSince(last)
        guard gap >= 0 else { return false }
        return gap >= threshold
    }
}
