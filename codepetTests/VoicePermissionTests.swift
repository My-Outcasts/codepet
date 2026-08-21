import AVFoundation
import Speech
import XCTest
@testable import codepet

/// Voice mode needs TWO grants — microphone and speech recognition — and either can
/// be refused independently. The mapping is pure so every combination is testable
/// without touching TCC, which a test cannot drive anyway.
final class VoicePermissionTests: XCTestCase {

    func testBothGrantedIsReady() {
        XCTAssertEqual(VoicePermission.availability(mic: .authorized,
                                                    recognition: .authorized,
                                                    hasRecognizer: true), .ready)
    }

    func testUndeterminedAsksRatherThanRefusing() {
        XCTAssertEqual(VoicePermission.availability(mic: .notDetermined,
                                                    recognition: .notDetermined,
                                                    hasRecognizer: true), .needsPermission)
    }

    /// **Either refusal is a refusal**, and the copy must name which one — "voice
    /// mode unavailable" with no reason is the thing that generates support mail.
    func testEitherDenialIsDeniedAndNamesWhich() {
        guard case .denied(let m1) = VoicePermission.availability(
            mic: .denied, recognition: .authorized, hasRecognizer: true) else {
            return XCTFail("mic denial not reported")
        }
        XCTAssertTrue(m1.lowercased().contains("microphone"), "got: \(m1)")

        guard case .denied(let m2) = VoicePermission.availability(
            mic: .authorized, recognition: .denied, hasRecognizer: true) else {
            return XCTFail("recognition denial not reported")
        }
        XCTAssertTrue(m2.lowercased().contains("speech"), "got: \(m2)")
    }

    /// No recognizer for the locale is a different thing from a refusal: nothing
    /// the founder can grant will fix it, so the button must not offer to ask.
    func testAMissingRecognizerIsUnsupportedNotDenied() {
        guard case .unsupported = VoicePermission.availability(
            mic: .authorized, recognition: .authorized, hasRecognizer: false) else {
            return XCTFail("a missing recognizer must be .unsupported")
        }
    }

    /// **Closes a gap found in review.** `AVAuthorizationStatus` and
    /// `SFSpeechRecognizerAuthorizationStatus` each have exactly four cases
    /// (notDetermined/restricted/denied/authorized), so by the time `availability`
    /// reaches its final line, both statuses are already forced to `.authorized` —
    /// the trailing `: .denied(...)` half of that ternary can never run. That made
    /// the single-grant "mic denied" assertion above pass for the WRONG reason: with
    /// the dedicated mic branch deleted, the case falls through to that same dead
    /// fallback text and reports "microphone" anyway by coincidence. The only input
    /// that actually distinguishes "there is a dedicated mic-first branch" from "mic
    /// denial is reported by accident" is BOTH grants denied at once — mic must win
    /// that race, because fixing the mic is a precondition for recognition to run at
    /// all. Delete the mic branch and this goes red (recognition's branch fires
    /// instead, reporting "speech").
    func testBothDeniedReportsMicFirst() {
        guard case .denied(let m) = VoicePermission.availability(
            mic: .denied, recognition: .denied, hasRecognizer: true) else {
            return XCTFail("simultaneous denial must still be .denied")
        }
        XCTAssertTrue(m.lowercased().contains("microphone"), "got: \(m)")
    }

    /// **The button's own rule, separate from the mapping.** `.needsPermission`
    /// must still OFFER the button — tapping it is what triggers the TCC prompt, so
    /// hiding it makes the permission unreachable and voice mode permanently dead.
    /// A refusal or an unsupported locale must not offer it: a dead click tells the
    /// founder nothing, where a disabled control with a reason tells her what to do.
    func testTheButtonIsOfferedWhenReadyOrUnasked() {
        XCTAssertTrue(VoicePermission.offersButton(.ready))
        XCTAssertTrue(VoicePermission.offersButton(.needsPermission))
        XCTAssertFalse(VoicePermission.offersButton(.denied("Microphone access is off.")))
        XCTAssertFalse(VoicePermission.offersButton(.unsupported("No recogniser.")))
    }

    func testHelpTextIsBilingualAndAbsentWhenReady() {
        XCTAssertNil(VoicePermission.help(.ready, .en))
        let en = VoicePermission.help(.denied("Microphone access is off."), .en)
        let vi = VoicePermission.help(.denied("Microphone access is off."), .vi)
        XCTAssertNotNil(en); XCTAssertNotNil(vi)
        XCTAssertNotEqual(en, vi, "help text is chrome and must be translated")
    }

    /// **Closes a second review gap.** The brief's own draft of `.unsupported`'s
    /// branch was `lang == .vi ? why : why` — a ternary that inspects `lang` and
    /// then ignores it, returning the same untranslated English sentence either way.
    /// That would have made "no recogniser for this locale" the one help string a
    /// Vietnamese founder sees in English, silently exempt from "chrome is
    /// bilingual." Same shape as the `.denied` bilingual test above, so a
    /// regression back to the dead ternary goes red here too.
    func testHelpTextForUnsupportedIsBilingual() {
        let en = VoicePermission.help(.unsupported("No speech recogniser for this language."), .en)
        let vi = VoicePermission.help(.unsupported("No speech recogniser for this language."), .vi)
        XCTAssertNotNil(en); XCTAssertNotNil(vi)
        XCTAssertNotEqual(en, vi, "unsupported help text is chrome too and must be translated")
    }

    /// `.needsPermission`'s copy was untested for content in the brief — only its
    /// non-nil-ness followed from `.ready` returning nil. Pin its bilinguality the
    /// same way the other two branches are pinned.
    func testHelpTextForNeedsPermissionIsBilingual() {
        let en = VoicePermission.help(.needsPermission, .en)
        let vi = VoicePermission.help(.needsPermission, .vi)
        XCTAssertNotNil(en); XCTAssertNotNil(vi)
        XCTAssertNotEqual(en, vi, "needsPermission help text is chrome too and must be translated")
    }
}
