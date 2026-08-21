import AVFoundation
import XCTest
@testable import codepet

/// Which of the 25 installed voices each pet gets.
///
/// No test asks the synthesiser to speak. These assert the MAPPING — that it is
/// total, that no two pets are indistinguishable, and that a missing voice falls
/// back rather than crashing.
final class PetVoiceTests: XCTestCase {

    private let pets = ["byte", "crash", "luna", "nova", "sage", "glitch"]

    func testEveryPetHasAProfile() {
        for p in pets {
            let prof = PetVoice.profile(for: p)
            XCTAssertFalse(prof.preferredVoices.isEmpty, "\(p) has no voice candidates")
            XCTAssertGreaterThan(prof.rate, 0)
            XCTAssertGreaterThan(prof.pitch, 0)
        }
    }

    /// **No two pets may be indistinguishable.** If two share a voice, a rate AND a
    /// pitch, the founder hears one person — which defeats naming the speaker.
    func testNoTwoPetsSoundIdentical() {
        var seen = Set<String>()
        for p in pets {
            let prof = PetVoice.profile(for: p)
            let key = "\(prof.preferredVoices.first ?? "")|\(prof.rate)|\(prof.pitch)"
            XCTAssertTrue(seen.insert(key).inserted, "\(p) is indistinguishable from another pet")
        }
    }

    /// An unknown pet — or the host, which is nil — gets the neutral default rather
    /// than nothing. The overlay must never be voiceless.
    func testUnknownAndNilFallBackToTheHostProfile() {
        XCTAssertEqual(PetVoice.profile(for: nil), PetVoice.profile(for: "byte"))
        XCTAssertEqual(PetVoice.profile(for: "no-such-pet"), PetVoice.profile(for: "byte"))
    }

    /// The candidates are ordered, and the last one must be a voice macOS always
    /// has. `Samantha` ships with every install; the accented voices can be absent.
    func testEveryCandidateListEndsInAVoiceThatAlwaysExists() {
        for p in pets {
            XCTAssertEqual(PetVoice.profile(for: p).preferredVoices.last, "Samantha",
                           "\(p) has no guaranteed fallback voice")
        }
    }

    /// Rate must stay inside what AVSpeechUtterance accepts, or the setter clamps
    /// silently and the pets converge on one speed.
    func testRatesAreInsideTheSynthesisersRange() {
        for p in pets {
            let r = PetVoice.profile(for: p).rate
            XCTAssertGreaterThanOrEqual(r, AVSpeechUtteranceMinimumSpeechRate)
            XCTAssertLessThanOrEqual(r, AVSpeechUtteranceMaximumSpeechRate)
        }
    }
}
