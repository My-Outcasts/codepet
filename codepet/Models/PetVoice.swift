import Foundation
// NO `import AVFoundation`. This file is pure — see the File-structure table.
// Rate and pitch are plain Floats on AVSpeechUtterance's scales; naming a voice
// is a String. Task 4 owns the one line that touches the framework.

/// A voice, a speed, and a pitch.
struct VoiceProfile: Equatable {
    /// In preference order. Resolution walks it and takes the first installed
    /// voice, so the list must end in one macOS always has.
    let preferredVoices: [String]
    let rate: Float
    let pitch: Float
}

/// Which of the installed voices each pet speaks with — spec §8.
///
/// **Keyed to `PetCharacter.voiceGuide`, which already exists.** That field
/// describes how each pet WRITES — "grizzled engineer who's seen production go
/// down at 3AM", "gentle, flowing… warm rhythm" — and is already sent to Claude to
/// shape its prose. Choosing the spoken voice from the same description keeps the
/// two from drifting into different characters.
///
/// **Not the novelty voices.** macOS also installs `Zarvox`, `Bubbles`, `Trinoids`.
/// Tempting for a pixel-art cast, and wrong: these pets give business advice.
///
/// Measured 21 Aug: 25 English voices installed, every one `default` quality. The
/// six named below are the human-sounding ones, across five accents and both
/// genders, so the cast is distinguishable by WHO is talking and not just by speed.
enum PetVoice {

    static func profile(for petId: String?) -> VoiceProfile {
        switch petId {
        case "crash":
            // Blunt, low, slightly fast. en-GB male reads as authoritative.
            return VoiceProfile(preferredVoices: ["Daniel", "Samantha"], rate: 0.52, pitch: 0.85)
        case "luna":
            // Gentle and flowing — the Irish lilt does most of the work.
            return VoiceProfile(preferredVoices: ["Moira", "Samantha"], rate: 0.46, pitch: 1.05)
        case "nova":
            // Punchy hype coach: fastest and highest.
            return VoiceProfile(preferredVoices: ["Karen", "Samantha"], rate: 0.56, pitch: 1.10)
        case "sage":
            // Measured, deliberate, "sentences that breathe" — the slowest.
            return VoiceProfile(preferredVoices: ["Rishi", "Samantha"], rate: 0.44, pitch: 0.95)
        case "glitch":
            // Clipped and irreverent.
            return VoiceProfile(preferredVoices: ["Tessa", "Samantha"], rate: 0.54, pitch: 1.08)
        case "null":
            // The Chaos Gremlin: "sentences zigzag — starts one thought, finishes
            // another." Fastest and highest, because the zigzag is carried by pace.
            // Junior is a young en-US voice — the only installed HUMAN voice that
            // reads as playful. Not Bahh/Boing/Jester, which are sound effects.
            return VoiceProfile(preferredVoices: ["Junior", "Kathy", "Samantha"], rate: 0.58, pitch: 1.15)
        default:
            // byte, the host — heard most often, so the most listenable. Also the
            // fallback for an unknown pet: the overlay must never be voiceless.
            return VoiceProfile(preferredVoices: ["Samantha"], rate: 0.50, pitch: 1.00)
        }
    }

    /// The first name in the profile's preference list that appears in `available`,
    /// or nil when none do — in which case the caller lets the synthesiser pick the
    /// system default rather than refusing to speak.
    ///
    /// **Takes names, not `AVSpeechSynthesisVoice`.** `AVSpeechSynthesisVoice` has
    /// no public initialiser that sets an arbitrary `name`, so a parameter of that
    /// type can only ever be fed the voices really installed on the machine running
    /// the test — which makes the preference-order walk untestable and pins this
    /// file to AVFoundation for no gain. Task 4 maps the returned name to a real
    /// voice; that one line is the only place the framework is needed.
    static func pick(_ profile: VoiceProfile, from available: [String]) -> String? {
        profile.preferredVoices.first { available.contains($0) }
    }
}
