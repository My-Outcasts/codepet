import AVFoundation
import XCTest
@testable import codepet

/// Which of the 25 installed voices each pet gets.
///
/// No test asks the synthesiser to speak. These assert the MAPPING — that it is
/// total, that no two pets are indistinguishable, and that a missing voice falls
/// back rather than crashing.
final class PetVoiceTests: XCTestCase {

    /// **All SEVEN starters, from `PetCharacter.starters`.** An earlier draft of this
    /// plan listed six and dropped `null` — "The Chaos Gremlin", a real shipped
    /// character with its own `voiceGuide` and its own match score. It fell into
    /// `default` and got byte's exact profile: same voice, same rate, same pitch. The
    /// collision was invisible because `null` was missing from this very list, so
    /// `testNoTwoPetsSoundIdentical` never saw it. Derive from the roster, do not
    /// retype it.
    private let pets = PetCharacter.starters

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

    /// **Pitch needs the same guard as rate, and for the same reason.**
    /// `pitchMultiplier` accepts 0.5…2.0 and clamps silently outside it, so a future
    /// edit to 3.0 would ship sounding wrong with a green suite. `testEveryPetHasAProfile`
    /// only asserts `pitch > 0`, which 3.0 passes.
    func testPitchesAreInsideTheSynthesisersRange() {
        for p in pets {
            let pitch = PetVoice.profile(for: p).pitch
            XCTAssertGreaterThanOrEqual(pitch, 0.5, "\(p) pitch clamps low")
            XCTAssertLessThanOrEqual(pitch, 2.0, "\(p) pitch clamps high")
        }
    }

    /// `pick` walks the preference list IN ORDER and takes the first available.
    /// Working in names is what makes this testable at all — see the doc comment on
    /// `pick`. Deleting the ordering (returning `available.first`, say) turns the
    /// second assertion red.
    func testPickTakesTheFirstAvailableInPreferenceOrder() {
        let crash = PetVoice.profile(for: "crash")   // ["Daniel", "Samantha"]
        XCTAssertEqual(PetVoice.pick(crash, from: ["Daniel", "Samantha"]), "Daniel")
        XCTAssertEqual(PetVoice.pick(crash, from: ["Samantha", "Daniel"]), "Daniel",
                       "order comes from the PROFILE, not from what the system lists first")
        XCTAssertEqual(PetVoice.pick(crash, from: ["Samantha"]), "Samantha",
                       "falls through to the guaranteed voice")
    }

    /// Nothing installed matches: return nil so the caller can let the synthesiser
    /// choose. Refusing to speak would be worse than speaking in the wrong voice.
    func testPickReturnsNilWhenNothingMatches() {
        XCTAssertNil(PetVoice.pick(PetVoice.profile(for: "crash"), from: []))
        XCTAssertNil(PetVoice.pick(PetVoice.profile(for: "crash"), from: ["Zarvox"]))
    }
}
