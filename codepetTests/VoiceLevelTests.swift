import XCTest
@testable import codepet

/// The waveform's number. It was `min(1, rms * 12)` inline in the audio tap, annotated
/// "empirical" and asserted nowhere — the gain could have become 120 and the suite
/// would have stayed green while the waveform sat pinned at full deflection on room noise.
final class VoiceLevelTests: XCTestCase {

    func testSilenceReadsZero() {
        XCTAssertEqual(VoiceLevel.level(from: [Float](repeating: 0, count: 512)), 0, accuracy: 0.0001)
    }

    /// An empty buffer is silence, not a divide by zero.
    func testAnEmptyBufferReadsZeroRatherThanNaN() {
        XCTAssertEqual(VoiceLevel.level(from: []), 0)
    }

    /// The gain, stated as behaviour: a constant 0.05 signal is RMS 0.05, which must
    /// land at 0.6. This is the assertion that catches a 12 becoming a 120.
    func testTheGainMapsSpeechRMSToTheMiddleOfTheRange() {
        let samples = [Float](repeating: 0.05, count: 1000)
        XCTAssertEqual(VoiceLevel.level(from: samples), 0.6, accuracy: 0.001)
    }

    /// **The reason the gain is not 120.** Measured speaking-voice RMS on a built-in
    /// mic is roughly 0.02–0.08 full-scale; across that whole span the waveform has to
    /// still be moving, not clipped.
    func testOrdinarySpeechMovesTheWaveformWithoutPinningIt() {
        for rms in [Float(0.02), 0.04, 0.08] {
            let level = VoiceLevel.level(from: [Float](repeating: rms, count: 256))
            XCTAssertGreaterThan(level, 0.1, "speech at RMS \(rms) barely moved the waveform")
            XCTAssertLessThan(level, 1, "speech at RMS \(rms) pinned the waveform at full")
        }
    }

    /// Louder is higher, all the way up.
    func testLouderReadsHigher() {
        let quiet = VoiceLevel.level(from: [Float](repeating: 0.01, count: 256))
        let loud = VoiceLevel.level(from: [Float](repeating: 0.04, count: 256))
        XCTAssertGreaterThan(loud, quiet)
    }

    /// Clamped: a shout must not hand the waveform a scale factor above 1.
    func testAShoutIsClampedToOne() {
        XCTAssertEqual(VoiceLevel.level(from: [Float](repeating: 0.9, count: 256)), 1)
        XCTAssertEqual(VoiceLevel.level(from: [Float](repeating: -1, count: 256)), 1)
    }

    /// RMS, not mean — a signal that swings symmetrically about zero is loud, and a
    /// plain average would call it silence.
    func testAnAlternatingSignalIsLoudAndNotSilent() {
        var samples = [Float]()
        for i in 0..<256 { samples.append(i.isMultiple(of: 2) ? 0.05 : -0.05) }
        XCTAssertEqual(VoiceLevel.level(from: samples), 0.6, accuracy: 0.001)
    }
}
