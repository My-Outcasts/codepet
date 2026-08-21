// codepet/Models/VoiceLevel.swift
import Foundation
// NO `import AVFoundation`. The orb's number is arithmetic over samples; pulling a
// buffer apart is the listener's job and one line of it.

/// How loud the founder is, 0…1, for the orb.
///
/// **Extracted because the gain was unmeasured and unasserted.** It lived inline in
/// the audio tap as `min(1, rms * 12)` annotated "empirical", where no test could
/// see it: the constant could become `120` — pinning the orb at full deflection on
/// room noise — and the suite would stay green.
///
/// **Every member is `nonisolated`, and that is load-bearing.** Under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` even a `static` on an enum is inferred
/// main-actor, so calling `level(from:)` from `AVAudioEngine`'s render thread was a
/// main-actor call from a nonisolated context — silent in Swift 5 mode, a warning
/// under `-strict-concurrency=complete`, an error in Swift 6. The arithmetic was
/// always thread-safe (pure, over one `let`); the type just never said so.
enum VoiceLevel {

    /// Speech RMS on a built-in mic is small: normal speaking voice measures roughly
    /// 0.02–0.08 full-scale, so 12 puts ordinary speech across the middle of the
    /// range instead of against either end. Asserted by `VoiceLevelTests`.
    nonisolated static let gain: Float = 12

    /// Root-mean-square of `samples`, scaled by `gain` and clamped to 1.
    ///
    /// An empty buffer is silence, not a divide by zero.
    nonisolated static func level(from samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { level(from: $0) }
    }

    /// The same arithmetic over a raw buffer. The audio tap runs on the real-time
    /// render thread once per buffer, so it must not allocate an `Array` to get
    /// here; `Array.withUnsafeBufferPointer` makes the tested entry point free.
    nonisolated static func level(from samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        return min(1, rms * gain)
    }
}
