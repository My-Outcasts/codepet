// codepet/Models/RecognitionWatchdog.swift
import Foundation
// NO `import Speech` and NO `import AVFoundation`. Whether recognition has answered is a
// decision over two Ints, a Bool and a TimeInterval; the request, the task, the engine
// and the buffers are the listener's business and not one of them is needed to make it.
// Same rule as `RenewalBudget` and `VoiceLevel`, and for the same reason: the decision
// is the part that was untestable, because reaching it needed an `SFSpeechRecognizer`.

/// **"Audio is flowing and recognition has produced nothing" is a failure, and until
/// this type existed nothing in the app could tell it from "she has not spoken yet."**
///
/// The measured bug: `openRecognition` sets `requiresOnDeviceRecognition` from
/// `recognizer.supportsOnDeviceRecognition`, which is a **capability** flag — "this Mac
/// and locale *can* recognise on device" — and not "the model is downloaded". On a Mac
/// with no speech assets installed the recognizer accepts every buffer and answers
/// nothing, forever: no result, no error, no `isFinal`. The composer reads `Listening…`
/// with the bars moving and stays that way for as long as she is willing to wait.
///
/// **Why `RenewalBudget` cannot cover it.** Every existing safety net on this path is
/// driven by a recognition callback — `endOfTask` is only reached from one, and
/// `RenewalBudget` is only consulted from `endOfTask`. Reproduced standalone on this Mac,
/// outside the project: **45 seconds, 450 buffers of real microphone audio appended,
/// zero callbacks of any kind.** With no callback there is no task end, so there is no
/// budget decision and `onFailure` is unreachable. The two types are complementary and
/// neither is redundant: `RenewalBudget` bounds a recognizer that keeps *dying*, this
/// bounds one that never *speaks*.
///
/// **Pure, and it takes the facts rather than reading them.** No timer, no clock, no
/// framework. `SpeechListener.RecognitionCensus` gathers the four numbers off the render
/// thread and the recognition callback; this decides what they mean. That split is what
/// makes the decision mutation-testable at all — every input can be moved one at a time,
/// which is impossible against a live `AVAudioEngine`.
enum RecognitionWatchdog {

    /// **How long real audio may flow with recognition saying nothing before that is
    /// called a failure. Ten seconds, and the number is a judgement, not a
    /// measurement.**
    ///
    /// The lower bound is firm. A healthy recognizer returns its first partial within
    /// roughly a second of speech, so ten is a 10× margin: a slow first partial — a cold
    /// model load, a long first word, a renewal seam — cannot trip this.
    ///
    /// The upper bound is the founder. The whole cost of the bug is her sitting in front
    /// of `Listening…`, so a message she has already given up and walked away from is
    /// worth nothing. Ten seconds is inside the window in which she is still looking at
    /// the composer she just opened.
    ///
    /// **What this number is NOT chosen from, stated because the brief's proposed 2-3s
    /// was derived from exactly this and it does not hold.** The reasoning "she began
    /// speaking within about a second of tapping" is one observation of one session, not
    /// a property of the product: nothing on this surface hurries her, and a founder who
    /// taps and then thinks for four seconds is ordinary. At 3s that founder has voice
    /// mode closed under her with a message telling her to go and fix her Dictation
    /// settings — `VoiceTurn.wire`'s `onFailure` calls `listener.stop()` and
    /// `session.apply(.close)`, so firing is not a hint, it is a teardown. The harm is
    /// badly asymmetric: firing late costs seconds, once, on a Mac that is genuinely
    /// broken; firing early costs trust, repeatedly, on one that is not. So the margin
    /// goes to not firing.
    ///
    /// The honest gap: there is no healthy Mac here to measure the *other* side against.
    /// On a working recognizer a silent founder is eventually reported by the
    /// recognizer's own no-speech error (`kAFAssistantErrorDomain/1110`) through
    /// `RenewalBudget`, and how long that takes is undocumented, version-dependent and
    /// unmeasurable on this machine — `RenewalBudget`'s own doc says so about the same
    /// error domain. A longer grace would let that path answer first and give a more
    /// accurate message more often. Ten is where the founder-visible cost of waiting
    /// stops being acceptable; `failureText` is worded so it is not a lie if the
    /// recognizer was merely slow rather than absent.
    static let grace: TimeInterval = 10

    /// How often the listener re-asks. One second: the verdict is three integer
    /// comparisons, and a tick an order of magnitude below `grace` means the report is
    /// never more than a second late.
    ///
    /// **This is not the 4Hz silence watcher spec §2 decision 4 deleted, and the
    /// difference is what that decision was about.** That watcher *took the founder's
    /// turn* on silence, which is why `SpeechFakesTests.testSilenceAloneNeverTakesTheTurn`
    /// exists and why `VoiceComposer` has no periodic work at all. This runs inside the
    /// listener, takes no turn, touches no transcript and cannot send anything; it can
    /// only report a fault. It also stops itself the moment recognition answers once.
    static let tick: TimeInterval = 1

    /// What the facts mean.
    enum Verdict: Equatable {
        /// Not enough evidence. Ask again.
        case keepWaiting
        /// Recognition has spoken to us this session. **Nothing more to police:** the
        /// question this type answers is "can this Mac recognise speech at all", and one
        /// transcript settles it for good. A recognizer that works and later dies ends a
        /// task, which is `RenewalBudget`'s business.
        case recognitionAnswered
        /// Real audio flowed for `grace` and recognition never answered. Report it.
        case recognitionNeverAnswered
    }

    /// The decision.
    ///
    /// - Parameters:
    ///   - voicedBuffers: audio buffers appended whose level was **not exactly zero**.
    ///   - results: recognition results delivered **this session**, including ones the
    ///     listener's identity guard dropped — a callback arriving at all is the fact.
    ///   - errored: whether the **current** request has delivered an error.
    ///   - sinceFirstVoicedBuffer: seconds since the first voiced buffer of the current
    ///     request. Zero when none has arrived.
    static func verdict(voicedBuffers: Int,
                        results: Int,
                        errored: Bool,
                        sinceFirstVoicedBuffer: TimeInterval) -> Verdict {
        // **A transcript, ever, ends this.** Sticky for the session on purpose: a
        // per-request version of this check would fire on an ordinary pause — she stops
        // to think for ten seconds mid-conversation, or she is merely *listening* to a
        // reply while the request opened at the turn boundary hears nothing — and close
        // voice mode on a Mac that demonstrably works.
        if results > 0 { return .recognitionAnswered }

        // **An error is not proof the model is there, and it is not this type's to
        // report.** The founder's own trace is `kAFAssistantErrorDomain/1110` at the
        // first callback on a Mac with zero speech assets, so "it errored" does not mean
        // "it works". But an error reaches `endOfTask`, which is `RenewalBudget`'s
        // decision, and two reports of one fault is worse than one: it would race the
        // budget's more accurate message. So hold off — and the *next* request re-arms
        // (`RecognitionCensus.requestOpened`), which is what fixes her exact sequence:
        // request 1 errors, the budget renews, request 2 answers nothing at all and
        // nothing was ever left to notice.
        if errored { return .keepWaiting }

        // **This is the load-bearing input, and what it actually establishes is
        // narrower than it looks.** A level of exactly zero over 4800 samples cannot
        // come from a live microphone — a real mic has a noise floor — so
        // `voicedBuffers == 0` means the buffers are zero-filled and the audio path is
        // dead, which is the *previous* bug on this path (a tap on a dangling
        // `AVAudioMixerNode`: measured `nonzero=0, peak=0.000000` while the callbacks
        // arrived on schedule). That is not this failure and must not be reported as
        // it: the remedy would be wrong.
        //
        // **It does NOT establish that the founder spoke, and the brief's claim that it
        // does is the one thing here that measurement contradicts.** Measured on this
        // Mac through the production graph, with nobody deliberately speaking:
        // `VoiceLevel` median **0.375**, minimum 0.198, zero buffers exactly zero — with
        // voice processing on *and* off. The founder's own trace measured **0.132**
        // while she was talking. Ambient room noise under VPIO's gain therefore reads
        // *higher* than her speech did, so no level threshold, this one or a tuned one,
        // can separate "she spoke" from "the room exists". The founder who taps and says
        // nothing is not protected by this gate; she is protected by `grace` being long,
        // by an error deferring to `RenewalBudget`, and by `failureText` not asserting a
        // cause it cannot know.
        guard voicedBuffers > 0 else { return .keepWaiting }

        guard sinceFirstVoicedBuffer >= grace else { return .keepWaiting }
        return .recognitionNeverAnswered
    }
}
