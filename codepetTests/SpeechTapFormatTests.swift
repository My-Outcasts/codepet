import AVFoundation
import XCTest
@testable import codepet

/// **The tap format, which is where the whole bug lived.**
///
/// Voice mode showed `Listening…` with a flat waveform, no transcript and no error. The
/// tap was on an intermediate `AVAudioMixerNode` with nothing connected downstream, so
/// the mixer was never rendered and every buffer arrived zero-filled at the right frame
/// rate — healthy callback counts, total silence. Three rounds of format tuning happened
/// on top of that, and every one of them measured "does the tap fire" while none measured
/// "is there audio in it".
///
/// The fix taps `inputNode` with an explicit mono format at the input bus's **own**
/// sample rate. `SpeechListener.tapFormat(for:)` is that derivation pulled out as a pure
/// static so it can be held here — the graph itself needs a microphone and a running
/// `AVAudioEngine`, which nothing in this suite may touch.
///
/// **These tests do not claim the microphone works, and cannot.** That is a standalone
/// spike with `say` playing, and non-zero peak amplitude is the only thing that settles
/// it — see `.superpowers/sdd/tap-fix-report.md`. What they hold is the two properties of
/// the format that were each wrong in a shipped build, and that no format dump could tell
/// you were wrong about.
final class SpeechTapFormatTests: XCTestCase {

    /// Every channel count voice processing has been measured negotiating on this Mac. It
    /// renegotiates per session — 3ch, 5ch and 7ch within minutes — so no single one of
    /// these is the constant that comments and specs kept asserting it was.
    private let measuredInputChannels: [AVAudioChannelCount] = [1, 2, 3, 5, 7]

    /// A stand-in for `inputNode.outputFormat(forBus: 0)`.
    ///
    /// **Built from a channel layout, and it has to be.** The convenience
    /// `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)` returns **nil** for
    /// any channel count above 2 — it has no layout to attach — which the first draft of
    /// this fixture discovered by failing. That is not a test detail: it is why
    /// `SpeechListener.start()` reads the input format off the bus instead of constructing
    /// one, and why `tapFormat(for:)` takes a format rather than a channel count and a
    /// rate. `kAudioChannelLayoutTag_DiscreteInOrder | n` is the layout a multi-channel
    /// VPIO bus presents: n discrete channels with no spatial meaning.
    private func inputBus(_ channels: AVAudioChannelCount, at rate: Double) throws -> AVAudioFormat {
        let layout = try XCTUnwrap(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels),
            "fixture: a \(channels)-channel discrete layout")
        return try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate,
                                           channelLayout: layout),
                             "fixture: a \(channels)ch/\(rate) input bus format")
    }

    /// **One channel, whatever came in.** `SFSpeechAudioBufferRecognitionRequest` needs
    /// mono, and `installTap` performs the downmix — but only when it is *asked* for
    /// mono. Inheriting the channel count instead is what handed the recognizer stereo in
    /// the first implementation, and it read as a perfectly plausible format in the log.
    func testTheTapIsAlwaysMonoWhateverVoiceProcessingNegotiated() throws {
        for channels in measuredInputChannels {
            let tap = SpeechListener.tapFormat(for: try inputBus(channels, at: 48000))
            XCTAssertEqual(tap?.channelCount, 1,
                           "a \(channels)ch input bus must still be tapped as mono")
        }
    }

    /// **The input bus's own rate and nothing else — the assertion that goes red if
    /// anyone resamples here.** Measured: any rate other than the bus's makes
    /// `engine.start()` throw `-10875`, so a "helpful" conversion does not degrade voice
    /// mode, it stops it dead. 16000 is the tempting value, being the recognizer's
    /// documented preference, and it is one of the two rates measured throwing.
    func testTheTapRateIsTheInputBusRateAndNothingElse() throws {
        for rate in [16000.0, 24000.0, 44100.0, 48000.0] {
            let tap = SpeechListener.tapFormat(for: try inputBus(3, at: rate))
            XCTAssertEqual(try XCTUnwrap(tap).sampleRate, rate, accuracy: 0.0001,
                           "the tap must inherit \(rate)Hz, never convert to a chosen rate")
        }
    }

    /// **`floatChannelData` must be non-nil, because that is literally what the tap
    /// reads.** The tap body does `buf.floatChannelData?[0]` and returns early on nil, so
    /// any common format other than `.pcmFormatFloat32` — or an interleaved one, where
    /// `[0]` is a stride rather than a plane — puts voice mode straight back into the
    /// silent branch: callbacks arriving, one log line, nothing fed to the recognizer, no
    /// error raised. `VoiceLevel.level` takes an `UnsafeBufferPointer<Float>` for the same
    /// reason. Asserted through a real buffer rather than through the format's properties,
    /// because the pointer is the thing the tap depends on.
    func testABufferInThisFormatExposesFloatChannelDataForTheTapToRead() throws {
        let tap = try XCTUnwrap(SpeechListener.tapFormat(for: try inputBus(7, at: 48000)))
        XCTAssertEqual(tap.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(tap.isInterleaved,
                       "deinterleaved: floatChannelData[0] must be a plane, not a stride")
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: tap, frameCapacity: 4800),
                                   "could not allocate a buffer in the tap format")
        buffer.frameLength = 4800
        XCTAssertNotNil(buffer.floatChannelData?[0],
                        "the tap reads floatChannelData[0]; nil here is the silent branch")
    }
}
