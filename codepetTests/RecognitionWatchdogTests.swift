import XCTest
@testable import codepet

/// **The verdict that separates "recognition is broken" from "she has not spoken yet",
/// which nothing in the app could tell apart.**
///
/// The bug it exists for: `openRecognition` sets `requiresOnDeviceRecognition` from
/// `SFSpeechRecognizer.supportsOnDeviceRecognition`, which is a *capability* flag and
/// not "the model is downloaded". On a Mac with no speech assets the recognizer accepts
/// every buffer and answers nothing — no result, no error, no `isFinal` — so the
/// composer reads `Listening…` forever. Reproduced standalone outside the project on
/// this Mac: 45s, 450 real buffers appended, **zero callbacks of any kind**. Every other
/// net on this path (`recognitionUpdate` → `endOfTask` → `RenewalBudget`) is driven by a
/// callback, so all of them were unreachable.
///
/// No audio, no `Speech` types, no clock: the decision is two `Int`s, a `Bool` and a
/// `TimeInterval`. Mutation-testable one input at a time, which is exactly what is
/// impossible against a live `AVAudioEngine` — and the reason seven review rounds could
/// not see this class of fault.
final class RecognitionWatchdogTests: XCTestCase {

    /// Convenience so each test moves ONE fact.
    private func verdict(voiced: Int = 100, results: Int = 0, errored: Bool = false,
                         elapsed: TimeInterval = 30) -> RecognitionWatchdog.Verdict {
        RecognitionWatchdog.verdict(voicedBuffers: voiced, results: results,
                                    errored: errored, sinceFirstVoicedBuffer: elapsed)
    }

    // MARK: - The failure this exists to make loud

    /// **The founder's Mac.** Real audio has been flowing for longer than the grace
    /// window and recognition has said nothing at all — not a partial, not an error.
    /// That is a failure and it must be reported, because the alternative is the
    /// composer reading `Listening…` for as long as she is willing to wait.
    ///
    /// RED: delete the `sinceFirstVoicedBuffer >= grace` guard in
    /// `RecognitionWatchdog.verdict` and the "not yet" half below goes red
    /// (`recognitionNeverAnswered` is not `keepWaiting`) — the watchdog would fire on the
    /// first tick, one second in, on every session.
    func testRealAudioWithNoAnswerAtAllIsAFailure() {
        XCTAssertEqual(verdict(elapsed: RecognitionWatchdog.grace),
                       .recognitionNeverAnswered,
                       "audio flowed for the whole grace window with no transcript and no "
                       + "error, and the watchdog still called it normal")
        XCTAssertEqual(verdict(elapsed: RecognitionWatchdog.grace * 10),
                       .recognitionNeverAnswered)

        // And not one tick early: the window is a window, not a hint.
        XCTAssertEqual(verdict(elapsed: RecognitionWatchdog.grace - 0.01), .keepWaiting,
                       "the watchdog fired before its own grace window had elapsed")
        XCTAssertEqual(verdict(elapsed: 0), .keepWaiting)
    }

    // MARK: - The three things that must NOT fire

    /// **A silent audio path is a different bug and must not be reported as this one.**
    ///
    /// `voicedBuffers == 0` means every buffer appended was exactly zero, which cannot
    /// come from a live microphone — a real mic has a noise floor. It is the signature of
    /// the *previous* defect on this path: the tap was installed on an `AVAudioMixerNode`
    /// connected to nothing, so it fired ~10×/s at the right frame count delivering
    /// buffers that were zero in every sample (measured `nonzero=0, peak=0.000000`).
    /// Telling that founder to go and install a speech model would send her to the wrong
    /// place entirely.
    ///
    /// **What this does NOT cover, stated because the brief claims it does.** This is
    /// *not* the "she tapped and said nothing" case, and this input cannot be. Measured
    /// on this Mac through the production graph with nobody deliberately speaking:
    /// `VoiceLevel` median **0.375**, min **0.198**, and **zero** buffers exactly zero —
    /// with voice processing on and off alike. The founder's own trace measured **0.132**
    /// while she *was* talking. Ambient noise under VPIO's gain reads higher than her
    /// speech did, so `voicedBuffers > 0` is satisfied within ~200ms of every session
    /// whether or not anyone speaks, and no level threshold — this one or a tuned one —
    /// can separate the two. The silent founder is protected by `grace` being long and by
    /// `VoiceChrome`'s wording, not by this guard. Asserting otherwise here would be a
    /// green test certifying a promise production does not keep.
    ///
    /// RED: delete the `voicedBuffers > 0` guard and this goes red — a listener whose
    /// audio path is delivering digital silence would be told its speech model is
    /// missing.
    func testAnAudioPathDeliveringOnlySilenceNeverFires() {
        XCTAssertEqual(verdict(voiced: 0, elapsed: 600), .keepWaiting,
                       "every buffer was exactly zero — the audio path is dead, which is "
                       + "not the missing-model failure and has a different remedy")
    }

    /// **One transcript, ever, and this stands down for the whole session.**
    ///
    /// The question is "can this Mac recognise speech at all", and a single result
    /// settles it. Per-request instead of per-session, this would fire on an ordinary
    /// pause: she stops to think for ten seconds mid-conversation, or she is merely
    /// *listening* to a reply while the request opened at the turn boundary hears
    /// nothing — and voice mode would close on a Mac that demonstrably works. A
    /// recognizer that works and later dies *ends a task*, which is `RenewalBudget`'s
    /// business, not this one's.
    ///
    /// RED: delete the `results > 0` guard and this goes red at every elapsed time —
    /// including an hour into a working conversation.
    func testOneTranscriptStandsTheWatchdogDownForGood() {
        XCTAssertEqual(verdict(results: 1, elapsed: RecognitionWatchdog.grace * 2),
                       .recognitionAnswered)
        XCTAssertEqual(verdict(results: 40, elapsed: 3600), .recognitionAnswered,
                       "an hour into a working conversation the watchdog turned on it")
        // It outranks an error too: a recognizer that transcribed and then errored is
        // `RenewalBudget`'s to judge, and it is certainly not model-less.
        XCTAssertEqual(verdict(results: 1, errored: true, elapsed: 3600),
                       .recognitionAnswered)
    }

    /// **An error is not this type's to report, and it is not proof the model is
    /// there either.**
    ///
    /// An error reaches `endOfTask`, which is `RenewalBudget`'s decision — reporting the
    /// same fault twice would race its more accurate message. So the watchdog holds off
    /// while the current request has errored, and re-arms when a fresh one opens
    /// (`RecognitionCensus.requestOpened`).
    ///
    /// **That re-arming is what fixes the founder's exact sequence**, which neither
    /// mechanism caught alone: request 1 delivered `kAFAssistantErrorDomain/1110` at its
    /// first callback, `RenewalBudget` spent its one renewal, and request 2 then answered
    /// *nothing at all* — no callback, so no task end, so no second budget decision, so
    /// no failure, forever. Note that 1110 arrived on a Mac with **zero** speech assets
    /// installed, which is why "it errored" is not treated as "it works".
    ///
    /// RED: delete the `errored` guard and this goes red — the watchdog would fire on
    /// top of a `RenewalBudget` failure and the founder would be told her speech model
    /// was missing when her authorisation had simply been revoked.
    func testAnErrorIsLeftToRenewalBudget() {
        XCTAssertEqual(verdict(errored: true, elapsed: RecognitionWatchdog.grace),
                       .keepWaiting,
                       "recognition errored, so endOfTask/RenewalBudget owns it — the "
                       + "watchdog reported the same fault a second time with the wrong "
                       + "remedy")
        XCTAssertEqual(verdict(errored: true, elapsed: 3600), .keepWaiting)
    }

    // MARK: - The numbers

    /// **The grace window is a stated number, and the direction of its error matters.**
    ///
    /// Ten seconds. Firing late costs the founder seconds, once, on a Mac that is
    /// genuinely broken; firing early closes voice mode under a founder whose Mac is
    /// fine and sends her to fiddle with her Dictation settings — `VoiceTurn.wire`'s
    /// `onFailure` calls `listener.stop()` and `session.apply(.close)`, so a fire is a
    /// teardown and not a hint. So the margin goes to not firing, and a grace shrunk to
    /// the "small number of seconds" the brief proposed would fire on any founder who
    /// taps and thinks for three seconds.
    ///
    /// `tick` well under `grace` is the other half: a tick at or above the window would
    /// make the report arbitrarily late or skip it altogether.
    ///
    /// RED: change `grace` to 3 and the first assertion goes red; make `tick` 10 and the
    /// second does.
    func testTheGraceWindowIsTenSecondsAndTheTickIsWellInsideIt() {
        XCTAssertEqual(RecognitionWatchdog.grace, 10,
                       "the grace window moved — a shorter one fires on a founder who "
                       + "taps and pauses, which is not a failure")
        XCTAssertLessThan(RecognitionWatchdog.tick, RecognitionWatchdog.grace / 2,
                          "the watchdog asks less often than half its own window, so a "
                          + "real failure is reported late or not at all")
        XCTAssertGreaterThan(RecognitionWatchdog.tick, 0)
    }

    /// **The census is the only thing feeding the verdict, so its own rules are the
    /// verdict's rules.** No audio and no `Speech` types are needed to drive it: it is a
    /// locked box over four numbers.
    ///
    /// The two that are not obvious, and both would produce a watchdog that never fires:
    /// `results` must survive a renewal (it is the session-level "this Mac works" fact),
    /// and `errored` must NOT — a renewal is a fresh chance to answer.
    ///
    /// RED: delete `facts.firstVoiced = nil` from `requestOpened()` and the last
    /// assertion goes red — request 2's grace window would be measured from request 1's
    /// first buffer, so a renewal would fire the watchdog instantly. Delete
    /// `facts.errored = false` and the third goes red, which is the founder's own
    /// sequence going unreported.
    func testTheCensusKeepsWhatSurvivesARenewalAndClearsWhatDoesNot() {
        let census = SpeechListener.RecognitionCensus()
        XCTAssertEqual(census.facts, .init())
        XCTAssertEqual(census.sinceFirstVoicedBuffer, 0,
                       "no audio has arrived, so there is no window to measure")

        census.noteVoicedBuffer()
        census.noteVoicedBuffer()
        census.noteRecognitionCallback(isError: false)
        census.noteRecognitionCallback(isError: true)
        XCTAssertEqual(census.facts.voicedBuffers, 2)
        XCTAssertEqual(census.facts.results, 1, "an errored callback was counted as a result")
        XCTAssertTrue(census.facts.errored)
        XCTAssertNotNil(census.facts.firstVoiced)

        census.requestOpened()
        XCTAssertFalse(census.facts.errored,
                       "the new request inherited the old one's error, so the watchdog "
                       + "defers to a RenewalBudget that will never be consulted again")
        XCTAssertEqual(census.facts.results, 1, "a renewal erased the proof that this Mac works")
        XCTAssertEqual(census.facts.voicedBuffers, 2)
        XCTAssertNil(census.facts.firstVoiced,
                     "the fresh request measures its grace window from request 1's first "
                     + "buffer, so a renewal fires the watchdog immediately")
        XCTAssertEqual(census.sinceFirstVoicedBuffer, 0)
    }
}
