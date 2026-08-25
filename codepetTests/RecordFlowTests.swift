// codepetTests/RecordFlowTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// **Record — spec §10's second composer voice control, the rules half.**
///
/// Every decision record makes that is not layout is here: what ✓ can take, where the
/// dictated text ends up, which of the two controls may start, what the one text slot says,
/// which controls a phase offers, and which keys are live. The surface is measured in
/// `RecordComposerTests`.
///
/// **No test here starts an audio engine, calls `speak()`, or constructs an
/// `SFSpeechRecognizer`.** The lifecycle assertions drive `SpeechFakesTests.FakeListener`,
/// which is the real `TurnTranscript` behind a fake request rather than a re-implementation
/// of one.
///
/// **What this suite cannot reach, stated because the last three defects on this feature
/// lived exactly there.** Record's defining property — that it never touches
/// `SpeakingVoice`, so it can never speak and can never spend a credit — is enforced by the
/// *absence of a parameter*: `RecordFlow`, `RecordTurn` and `RecordComposer` have no
/// `SpeakingVoice` and no `CompanyStore` in scope, so `beginReply`/`enqueue`/`endOfReply`/
/// `stopImmediately`/`sendChat` are not nameable in those files. A runtime assertion would
/// add nothing to that: a spy handed to nothing records nothing whatever the code does. The
/// compiler is the guard, and a review that widens one of those signatures is the only thing
/// that can remove it.
@MainActor
final class RecordFlowTests: XCTestCase {

    // MARK: - ✓ can take

    /// **What ✓ can take, across every phase — two silent failures, both owned here.**
    ///
    /// An empty transcript writes `""` into the field and looks exactly like a dead button;
    /// a phase with nothing to take (`.connecting` has heard nothing, `.failed` never will)
    /// is a control offering something it cannot do. The whitespace case is the recognizer
    /// reporting `" "`.
    ///
    /// **RED, 22 Aug — measured, in failing TESTS across this suite.** `guard phase ==
    /// .capturing || phase == .held` deleted from `canTakeDraft`: **4 tests fail** (this one,
    /// `testCommandReturnIsLiveExactlyWhenRecordsCheckmarkIs`,
    /// `testEscapeIsTheOnlyRecordHotkeyLiveInEveryPhase`, and
    /// `testTheHeldPhaseWithNothingHeardOffersOnlyTheWayOut`). Deleting the emptiness check
    /// instead: **4 tests fail**. Assertion-level counts are not reported here because the
    /// harness counts tests, and a figure nobody measured is worse than no figure.
    func testTakingADraftNeedsBothWordsAndAPhaseThatStillHasThem() {
        // Capturing and held both have words worth taking — held is the whole point,
        // because release is when she reads it.
        XCTAssertTrue(RecordFlow.canTakeDraft(partial: "add pricing", phase: .capturing))
        XCTAssertTrue(RecordFlow.canTakeDraft(partial: "add pricing", phase: .held))

        // Nothing heard: ✓ must be dead in every phase, not merely inert.
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "", phase: .capturing))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "", phase: .held))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "   \n ", phase: .capturing),
                       "whitespace is what the recognizer reports when it has heard nothing")

        // No phase before the mic is up, and none after it has died, can take anything —
        // with or without a stale transcript behind it.
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "add pricing", phase: .connecting))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "add pricing", phase: .failed))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "", phase: .connecting))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "", phase: .failed))

        // `takeDraft` is the same rule with a value, so it cannot answer differently.
        XCTAssertNil(RecordFlow.takeDraft(partial: "add pricing", phase: .failed))
    }

    /// ✓ hands back the words with the recognizer's own leading and trailing space
    /// removed, because the next thing that happens to this string is that it is joined to
    /// whatever she had already typed.
    ///
    /// RED, 22 Aug (measured): dropping the `trimmingCharacters` from `takeDraft`'s return
    /// — **1 test fails**, this one.
    func testTheTextHandedToTheFieldIsTrimmedNotRaw() {
        XCTAssertEqual(RecordFlow.takeDraft(partial: "  add pricing for the beta \n",
                                            phase: .held),
                       "add pricing for the beta")
        XCTAssertNil(RecordFlow.takeDraft(partial: "  ", phase: .held))
    }

    // MARK: - Where the words land

    /// **✓ appends to a typed draft rather than replacing it, and that is a data-loss rule
    /// rather than a preference.**
    ///
    /// The record surface is swapped in *over* the field, so while she dictates she cannot
    /// see the draft she is about to overwrite, and there is no other copy of it. Appending
    /// destroys nothing and lands her in a text field with a caret, which is the one place
    /// an unwanted append costs a selection and a keypress.
    ///
    /// RED, 22 Aug (measured): `merge` reduced to `return dictated` — **1 test fails**, this
    /// one. Replacing the whitespace-tail branch with an unconditional `draft + " " +
    /// dictated` — **1 test fails**, also this one. Both are caught here and nowhere else,
    /// which is worth knowing: this is the only test in either suite that reads `merge`.
    func testDictationJoinsTheTypedDraftAndNeverOverwritesIt() {
        XCTAssertEqual(RecordFlow.merge(draft: "check the runway",
                                        dictated: "and the pricing page"),
                       "check the runway and the pricing page")
        // She left a trailing space on purpose; a second one would be a double space in
        // the middle of her own sentence.
        XCTAssertEqual(RecordFlow.merge(draft: "check the runway ",
                                        dictated: "and the pricing page"),
                       "check the runway and the pricing page")
        // Nothing typed: the dictation is the draft, with no leading space.
        XCTAssertEqual(RecordFlow.merge(draft: "", dictated: "add pricing"), "add pricing")
        XCTAssertEqual(RecordFlow.merge(draft: "   ", dictated: "add pricing"), "add pricing",
                       "a field holding only whitespace is an empty field to the founder")
        // The typed half survives verbatim — this is the assertion that goes red if
        // `merge` ever becomes an assignment.
        XCTAssertTrue(RecordFlow.merge(draft: "keep me", dictated: "and this")
                        .hasPrefix("keep me"))
        XCTAssertEqual(RecordFlow.merge(draft: "keep me", dictated: ""), "keep me ",
                       "an empty dictation cannot delete what she typed")
    }

    // MARK: - The two controls, never at once

    /// **Spec §10: the two controls share one `SpeechListener` and one recognition request,
    /// so entering either while the other is live has to be refused.**
    ///
    /// The `live` argument is not "the other surface is on screen" — the composer swap
    /// already makes them mutually invisible. It is "the other control has started", which
    /// includes the whole time `startVoiceMode()` is awaiting two TCC dialogs with the
    /// typing composer and its live mic button still up. That is the window in which a
    /// press used to leave record's `AVAudioEngine` orphaned behind `VoiceComposer`, with
    /// the microphone open and nothing left able to stop it.
    ///
    /// RED, 22 Aug (measured): `guard live == nil else { return false }` deleted from
    /// `canEnter` — **1 test fails**, this one. It is the only test that passes a non-nil
    /// `live`, so this assertion is the entire guard against the two controls running at
    /// once; nothing in the layout suite or in `VoicePermissionTests` can see it.
    func testNeitherVoiceControlMayStartWhileTheOtherHasAlreadyStarted() {
        // Nothing live: both are offered.
        XCTAssertTrue(VoicePermission.canEnter(.record, .ready, isBusy: false, live: nil))
        XCTAssertTrue(VoicePermission.canEnter(.voiceMode, .ready, isBusy: false, live: nil))

        // Voice mode owns the microphone — including while its dialogs are still up.
        XCTAssertFalse(VoicePermission.canEnter(.record, .ready, isBusy: false,
                                                live: .voiceMode))
        // …and cannot be entered twice, which is what `voiceRequesting` used to guard alone.
        XCTAssertFalse(VoicePermission.canEnter(.voiceMode, .ready, isBusy: false,
                                                live: .voiceMode))

        // Record owns it: the waveform is refused, and so is a second press of the mic.
        XCTAssertFalse(VoicePermission.canEnter(.voiceMode, .ready, isBusy: false,
                                                live: .record))
        XCTAssertFalse(VoicePermission.canEnter(.record, .ready, isBusy: false,
                                                live: .record))

        // The exclusion outranks permission: a `.ready` grant does not buy a second engine.
        for control in VoiceControlKind.allCases {
            for live in VoiceControlKind.allCases {
                XCTAssertFalse(VoicePermission.canEnter(control, .ready, isBusy: false,
                                                        live: live),
                               "\(control) was allowed to start while \(live) was live")
            }
        }
    }

    /// **The one rule the two controls genuinely disagree on: busyness.**
    ///
    /// Voice mode refuses to open over a live typed turn — `VoicePermission.canEnterVoiceMode`
    /// writes out the sequence, which cost the founder her first spoken question. Record has
    /// neither half of that: it never calls `sendChat`, and it never touches the
    /// `SpeakingQueue` whose virgin state was the defect. Meanwhile she is *already* free to
    /// type into `chatDraft` while a reply streams, so a busy gate here would take from the
    /// dictated draft something the typed draft has.
    ///
    /// RED, 22 Aug (measured): routing `.record` through `canEnterVoiceMode` inside
    /// `canEnter` — **1 test fails**, this one.
    func testRecordIsOfferedWhileAReplyStreamsAndVoiceModeIsNot() {
        XCTAssertTrue(VoicePermission.canEnter(.record, .ready, isBusy: true, live: nil),
                      "she can type into the draft mid-stream; she may dictate into it too")
        XCTAssertFalse(VoicePermission.canEnter(.voiceMode, .ready, isBusy: true, live: nil),
                       "entering voice mode over a live typed turn cost her first question")
        // The permission half is shared, which is the other half of the claim: record is
        // not a looser gate, it is the same gate minus one term.
        XCTAssertFalse(VoicePermission.canEnterRecord(.denied("Microphone access is off.")))
        XCTAssertFalse(VoicePermission.canEnterRecord(.unsupported("no recogniser")))
        XCTAssertTrue(VoicePermission.canEnterRecord(.needsPermission),
                      "the first press is what raises the two prompts — a hidden mic is a "
                      + "permission nobody can ever grant")
    }

    // MARK: - The one text slot

    /// **A recognition failure takes the slot from both the transcript and the caption.**
    ///
    /// `VoiceChrome.line`'s precedence, restated for record's phases because record's
    /// machine cannot reach `VoiceState` and so cannot reuse the function. Its failure is
    /// the one this whole slot exists to prevent: a founder told the microphone is live and
    /// dead in the same frame.
    ///
    /// RED, 22 Aug (measured): moving `RecordChrome.line`'s failure branch below the
    /// transcript branch — **3 tests fail** (this one,
    /// `testTheHeldEmptyLineSaysWhatHappenedWithoutDiagnosingIt` and
    /// `testAFatalStartIsShownOnceAndNotRetriedOnEveryRebuild`).
    func testAFailureOutranksBothTheTranscriptAndTheCaption() {
        let dead = VoiceAudioError.recognitionNeverAnswered
        for phase in [RecordPhase.connecting, .capturing, .held, .failed] {
            let line = RecordChrome.line(phase: phase, partial: "add pricing",
                                         failure: dead, .en)
            XCTAssertEqual(line.kind, .failure,
                           "\(phase) showed something other than the failure")
            XCTAssertEqual(line.text, VoiceChrome.failureText(dead, .en),
                           "record wrote its own copy for a failure VoiceChrome already owns")
        }
    }

    /// **What the slot says in each phase when there is nothing to show but the phase.**
    ///
    /// `.connecting` and `.capturing` borrow voice mode's own words, deliberately: it is the
    /// same box doing the same thing, and two translations of "Listening…" in one composer
    /// would read as two features rather than two controls.
    ///
    /// RED, 22 Aug (measured): making `.capturing` fall through to `.idle`'s caption —
    /// **1 test fails**, this one. Making `.held` return `caption(.listening)` — **1 test
    /// fails**, also this one; `testTheHeldEmptyLineSaysWhatHappenedWithoutDiagnosingIt`
    /// stays green there, because "Listening…" contains no "System Settings" either. That is
    /// the honest limit of that test and the reason this one pins `.held`'s caption by
    /// identity.
    func testEachPhaseHasItsOwnPlaceholderAndTwoOfThemAreVoiceModesOwn() {
        XCTAssertEqual(RecordChrome.caption(.connecting, .en), VoiceChrome.caption(.idle, .en))
        XCTAssertEqual(RecordChrome.caption(.capturing, .en),
                       VoiceChrome.caption(.listening, .en))
        XCTAssertNotEqual(RecordChrome.caption(.capturing, .en),
                          RecordChrome.caption(.connecting, .en),
                          "the founder cannot tell a spinning-up engine from a live one")
        XCTAssertEqual(RecordChrome.caption(.held, .en), RecordChrome.nothingHeardText(.en))

        // The transcript wins whenever there is one, in every phase that can hold one —
        // which in record is all of them, because there is no `.thinking` to outrank it.
        let line = RecordChrome.line(phase: .held, partial: "add pricing", failure: nil, .en)
        XCTAssertEqual(line.kind, .transcript)
        XCTAssertEqual(line.text, "add pricing")
    }

    /// **`.held` with nothing heard is record's own state, and the line for it says what
    /// happened without claiming to know why.**
    ///
    /// `RecognitionWatchdog` needs 10s of real audio before it will name the missing speech
    /// model, and a press-and-hold is usually two seconds; release stops the listener and
    /// the watchdog loop exits on `guard self.isRunning`, so its verdict is never reached.
    /// Two seconds establishes nothing — she may not have spoken — so naming a remedy on
    /// that evidence would be the `privacyLine` defect again: a claim from a flag that does
    /// not establish it.
    ///
    /// RED, 22 Aug (measured): `nothingHeardText` changed to return
    /// `VoiceChrome.failureText(.recognitionNeverAnswered, lang)` — **1 test fails**, this
    /// one, on the "does not diagnose" assertion, which is the whole point of it.
    func testTheHeldEmptyLineSaysWhatHappenedWithoutDiagnosingIt() {
        let line = RecordChrome.line(phase: .held, partial: "", failure: nil, .en)
        XCTAssertEqual(line.kind, .caption,
                       "nothing was heard, so this is not a transcript and not a failure")
        XCTAssertFalse(line.text.contains("System Settings"),
                       "two seconds of audio does not establish a missing speech model — "
                       + "the watchdog's diagnosis needs ten")
        // The watchdog's own message still reaches this slot when it HAS earned it.
        let diagnosed = RecordChrome.line(phase: .failed, partial: "",
                                          failure: VoiceAudioError.recognitionNeverAnswered,
                                          .en)
        XCTAssertTrue(diagnosed.text.contains("System Settings"),
                      "the watchdog fires on record's listener too and must still be heard")
    }

    /// Chrome is bilingual — the `lang == .vi ? why : why` defect inspects the language and
    /// ignores it, and it has shipped on this feature once.
    func testEveryLineRecordOwnsDiffersBetweenEnglishAndVietnamese() {
        XCTAssertNotEqual(RecordChrome.nothingHeardText(.en), RecordChrome.nothingHeardText(.vi))
        XCTAssertNotEqual(RecordChrome.micLabel(.en), RecordChrome.micLabel(.vi))
        XCTAssertNotEqual(RecordChrome.toggleLabel(for: .capturing, .en),
                          RecordChrome.toggleLabel(for: .capturing, .vi))
        XCTAssertNotEqual(RecordChrome.toggleLabel(for: .held, .en),
                          RecordChrome.toggleLabel(for: .held, .vi))
        for phase in [RecordPhase.connecting, .capturing, .held, .failed] {
            XCTAssertNotEqual(RecordChrome.caption(phase, .en), RecordChrome.caption(phase, .vi),
                              "\(phase)'s caption reads the language and ignores it")
        }
        // The mic's tooltip names the gesture, because press-and-hold is not what a button
        // looks like — this is the tooltip the founder read on Claude's own composer.
        XCTAssertTrue(RecordChrome.micLabel(.en).contains("⌘D"))
    }

    // MARK: - Which controls a phase offers

    /// **`Cancel` while there is nothing else worth doing, ✕ and ✓ once there is.**
    ///
    /// Not cosmetic in either direction: `Cancel` beside ✕/✓ steals the width they sit in,
    /// and ✕/✓ in `.connecting` offers two controls that can do nothing at all.
    ///
    /// RED, 22 Aug (measured): `.connecting`/`.failed` changed to `[.discard, .send]` —
    /// **2 tests fail** (this one and `testAFatalStartIsShownOnceAndNotRetriedOnEveryRebuild`).
    /// `.held` changed to ignore an empty transcript — **2 tests fail** (this one and
    /// `testTheHeldPhaseWithNothingHeardOffersOnlyTheWayOut`).
    func testOnlyAPhaseWithWordsInItOffersTheTwoCircles() {
        XCTAssertEqual(RecordChrome.controls(for: .connecting, partial: ""), [.cancel])
        XCTAssertEqual(RecordChrome.controls(for: .failed, partial: ""), [.cancel])
        XCTAssertEqual(RecordChrome.controls(for: .capturing, partial: ""), [.discard, .send],
                       "✕/✓ stay put while she is talking — a control that appears under "
                       + "her pointer mid-sentence is the defect the fixed slot avoids")
        XCTAssertEqual(RecordChrome.controls(for: .held, partial: "add pricing"),
                       [.discard, .send])
        XCTAssertEqual(RecordChrome.controls(for: .held, partial: ""), [.cancel],
                       "the mic is off and nothing was heard: both circles are inert and "
                       + "the one useful control is out")
    }

    /// **`.held` with nothing heard offers only the way out, and that is where record and
    /// voice mode part company on ✕.**
    ///
    /// Voice mode keeps ✕ enabled with an empty transcript because it clears and *keeps
    /// listening*, so a greyed ✕ would read as a composer that had stopped working. Record's
    /// microphone is already off by then, so there is nothing to keep.
    func testTheHeldPhaseWithNothingHeardOffersOnlyTheWayOut() {
        XCTAssertFalse(RecordChrome.controls(for: .held, partial: "").contains(.discard))
        XCTAssertFalse(RecordChrome.controls(for: .held, partial: "").contains(.send))
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: "", phase: .held))
        // Voice mode's own answer for the comparable state, so the difference is asserted
        // rather than asserted about.
        XCTAssertTrue(VoiceChrome.controls(for: .listening).contains(.discard))
    }

    // MARK: - The keys

    /// **⌘D is record's and record's alone, and Esc/⌘⏎ are derived from voice mode rather
    /// than copied.**
    ///
    /// Two literals for the same keystroke are two things that can disagree, and the
    /// disagreement is invisible: each surface would work perfectly on its own.
    ///
    /// RED, 22 Aug (measured): `var key: KeyEquivalent { "d" }` (dropping the delegation) —
    /// **2 tests fail** (this one and
    /// `testNoTwoRecordHotkeysShareAKeyAndNoneIsAnExistingAppShortcut`, because all three
    /// keys collapse onto one keystroke).
    func testRecordDerivesTheTwoCirclesKeysFromVoiceModeAndOwnsCommandDAlone() {
        XCTAssertEqual(RecordHotkey.toggle.key.character, "d")
        XCTAssertEqual(RecordHotkey.toggle.modifiers, .command)
        XCTAssertNil(RecordHotkey.toggle.sharedWithVoiceMode)

        XCTAssertEqual(RecordHotkey.exit.key.character, VoiceHotkey.exit.key.character)
        XCTAssertEqual(RecordHotkey.send.key.character, VoiceHotkey.send.key.character)
        XCTAssertEqual(RecordHotkey.send.modifiers, VoiceHotkey.send.modifiers)

        // ⌘D belongs to record, so no voice hotkey may claim it — the other half of this
        // is `VoiceHotkeyTests`, which lists ⌘D among the keystrokes voice mode must avoid.
        for hotkey in VoiceHotkey.allCases {
            XCTAssertFalse(hotkey.key.character == "d" && hotkey.modifiers == .command,
                           "\(hotkey) took ⌘D, which spec §10 reserved for record")
        }
    }

    /// **No two record hotkeys are the same keystroke, and none is one the app already
    /// owns.** Audited 22 Aug by grepping every `keyboardShortcut` in the target:
    /// `AppShellView`/`TwoModeShellView`/`ReflectionTab` (⌘B), `CodePetApp` (⌘, ⌘1–7, ⌘⇧T,
    /// ⌘⇧M), `TopNavView` (⌘⇧H). ⌘D is deliberately absent from that list — record is its
    /// owner now, which is the change this feature makes to the audit.
    func testNoTwoRecordHotkeysShareAKeyAndNoneIsAnExistingAppShortcut() {
        let mine = RecordHotkey.allCases.map { "\($0.key.character)+\($0.modifiers.rawValue)" }
        XCTAssertEqual(Set(mine).count, RecordHotkey.allCases.count,
                       "two record hotkeys are the same keystroke: \(mine)")

        var taken: [(Character, EventModifiers)] = [
            ("b", .command), (",", .command),
            ("t", [.command, .shift]), ("m", [.command, .shift]),
            ("h", [.command, .shift]),
        ]
        for digit in "1234567" { taken.append((digit, .command)) }

        for hotkey in RecordHotkey.allCases {
            for (character, modifiers) in taken {
                XCTAssertFalse(hotkey.key.character == character
                               && hotkey.modifiers == modifiers,
                               "\(hotkey) collides with the app's existing "
                               + "\(modifiers.rawValue)+\(character) — one of the two will "
                               + "silently stop working")
            }
        }
    }

    /// **⌘D can only stop a capture that is running.**
    ///
    /// `.connecting` has nothing to stop yet and `.held`/`.failed` are already stopped, so a
    /// ⌘D that fired there would be a keystroke doing nothing at all — which is precisely
    /// what `RecordHotkey` exists to make visible. The mic button under it is greyed by this
    /// same expression, so the two cannot disagree.
    ///
    /// RED, 22 Aug (measured): `case .toggle: return true` — **2 tests fail** (this one and
    /// `testEscapeIsTheOnlyRecordHotkeyLiveInEveryPhase`, which loses its "⌘D is dead
    /// somewhere" half — that half is the point of it).
    func testCommandDStopsACaptureOnlyWhileOneIsRunning() {
        XCTAssertTrue(RecordHotkey.isEnabled(.toggle, partial: "x", phase: .capturing))
        XCTAssertTrue(RecordHotkey.isEnabled(.toggle, partial: "", phase: .capturing),
                      "stopping a capture that has heard nothing is still stopping it")
        XCTAssertFalse(RecordHotkey.isEnabled(.toggle, partial: "x", phase: .held))
        XCTAssertFalse(RecordHotkey.isEnabled(.toggle, partial: "", phase: .connecting))
        XCTAssertFalse(RecordHotkey.isEnabled(.toggle, partial: "x", phase: .failed))
    }

    /// **⌘⏎ is live exactly when ✓ is, and nothing else.** One expression for the key and
    /// the button, so a keypress cannot become a bypass of the rule that greys the circle.
    ///
    /// RED, 22 Aug (measured): `case .send: return true` — **2 tests fail** (this one and
    /// `testEscapeIsTheOnlyRecordHotkeyLiveInEveryPhase`).
    func testCommandReturnIsLiveExactlyWhenRecordsCheckmarkIs() {
        for phase in [RecordPhase.connecting, .capturing, .held, .failed] {
            for partial in ["", "   ", "add pricing"] {
                XCTAssertEqual(
                    RecordHotkey.isEnabled(.send, partial: partial, phase: phase),
                    RecordFlow.canTakeDraft(partial: partial, phase: phase),
                    "⌘⏎ and ✓ disagree in \(phase) with \(partial.debugDescription)")
            }
        }
        XCTAssertTrue(RecordHotkey.isEnabled(.send, partial: "add pricing", phase: .held))
        XCTAssertFalse(RecordHotkey.isEnabled(.send, partial: "", phase: .held))
        XCTAssertFalse(RecordHotkey.isEnabled(.send, partial: "add pricing", phase: .failed))
    }

    /// **Esc is the only record hotkey that is live in every phase, and it has no RED.**
    ///
    /// There is nothing to gate: the composer is never on screen without a way out,
    /// including after a fatal `start()` failure, which is the state a founder most wants
    /// out of. This documents that intent and goes red only if someone gates the exit.
    ///
    /// It is also the assertion behind record having *fewer* keys than voice mode: in voice
    /// mode ✕ discards a sentence and keeps listening, so ✕ and the exit are two actions
    /// needing two keys. Here the microphone is already off, so they are one action and Esc
    /// is it.
    func testEscapeIsTheOnlyRecordHotkeyLiveInEveryPhase() {
        for phase in [RecordPhase.connecting, .capturing, .held, .failed] {
            XCTAssertTrue(RecordHotkey.isEnabled(.exit, partial: "", phase: phase),
                          "the way out is gated in \(phase)")
        }
        // Each of the other two is dead somewhere, which is what makes the claim above
        // mean something.
        XCTAssertFalse(RecordHotkey.isEnabled(.toggle, partial: "x", phase: .held))
        XCTAssertFalse(RecordHotkey.isEnabled(.send, partial: "x", phase: .connecting))
        // And there is no ⌘⌫ to be live or dead: record has three keys, not four.
        XCTAssertEqual(RecordHotkey.allCases.count, 3)
        XCTAssertFalse(RecordHotkey.allCases.contains { $0.sharedWithVoiceMode == .discard },
                       "⌘⌫ would be a second key for the action Esc already performs")
    }

    // MARK: - The capture lifecycle

    /// **Release really stops the microphone, and the bars really go flat.**
    ///
    /// `listener.stop()` rather than `endTurn()`, and the difference is a privacy one:
    /// `endTurn()` retires the recognition request but leaves the engine running and the tap
    /// installed. She has just taken her finger off a button whose whole affordance is that
    /// holding it is what records, and a surface showing flat bars over a live tap would be
    /// lying in the one direction spec §3 exists to prevent.
    ///
    /// **RED, 22 Aug (measured).** `endCapture` changed to `listener.endTurn()` — **1 test
    /// fails**, this one, on `isRunning`. Deleting the `level = 0` — **1 test fails**, this
    /// one.
    ///
    /// **And the phase guard is NOT covered here, which this note used to claim it was.**
    /// Deleting `guard phase == .capturing` from `endCapture` leaves this test green: `stop()`
    /// is idempotent and `.held` → `.held` changes nothing, so releasing twice measures
    /// identically with and without it. The phase that makes that guard load-bearing is
    /// `.failed`, and it has its own test —
    /// `testReleasingAfterRecognitionDiedLeavesTheFailureOnScreen`, written because this
    /// claim was measured and found false.
    func testReleaseStopsTheMicrophoneAndKeepsTheWords() {
        let listener = SpeechFakesTests.FakeListener()
        var turn = RecordTurn()
        turn.openMic(listener)
        XCTAssertEqual(turn.phase, .capturing)
        XCTAssertTrue(listener.isRunning)

        turn.partial = "add pricing for the beta"
        turn.level = 0.6
        turn.endCapture(listener)

        XCTAssertEqual(turn.phase, .held)
        XCTAssertFalse(listener.isRunning, "the microphone is still open after she let go")
        XCTAssertEqual(turn.level, 0, "flat bars are the disclosure that the mic is off")
        XCTAssertEqual(turn.partial, "add pricing for the beta",
                       "the transcript has to survive release — judging it is the point")
        XCTAssertEqual(turn.take(), "add pricing for the beta")

        // A second release — the mouse-up that follows a ⌘D stop — must not re-enter.
        turn.endCapture(listener)
        XCTAssertEqual(turn.phase, .held)
    }

    /// **A mouse-up after recognition has died must not erase the error off the screen.**
    ///
    /// This is the guard in `endCapture` that `testReleaseStopsTheMicrophoneAndKeepsTheWords`
    /// claimed and did not have: releasing twice measures identically with and without it,
    /// because `stop()` is idempotent and `.held` → `.held` changes nothing. The phase that
    /// makes it load-bearing is `.failed`, and it is ordinary — she holds the mic,
    /// recognition dies mid-hold (a revoked grant, a dropped network under vi-VN,
    /// `RecognitionWatchdog` firing at ten seconds), the composer shows why, and *then* she
    /// lets go. Ungated, that mouse-up overwrites `.failed` with `.held`: the diagnosis is
    /// replaced by "No words came back. Hold the mic and speak again.", which is advice
    /// rather than the reason, and the founder retries against a microphone that will fail
    /// the same way. Nothing throws and nothing logs.
    ///
    /// RED, 22 Aug (measured): `guard phase == .capturing` deleted from `endCapture` — this
    /// test fails and it is the only one in either suite that does.
    func testReleasingAfterRecognitionDiedLeavesTheFailureOnScreen() {
        let listener = SpeechFakesTests.FakeListener()
        var turn = RecordTurn()
        let binding = Binding(get: { turn }, set: { turn = $0 })
        RecordTurn.wire(binding, listener: listener)
        turn.openMic(listener)
        listener.failMidSession(VoiceAudioError.recognitionNeverAnswered)
        XCTAssertEqual(turn.phase, .failed)

        // She lets go of the mouse, which she was still holding when it died.
        turn.endCapture(listener)

        XCTAssertEqual(turn.phase, .failed,
                       "the release overwrote the failure with an ordinary held capture")
        XCTAssertEqual(RecordChrome.line(phase: turn.phase, partial: turn.partial,
                                         failure: turn.failure, .en).kind, .failure,
                       "the founder is now reading advice instead of the reason")
        XCTAssertTrue(RecordChrome.line(phase: turn.phase, partial: turn.partial,
                                        failure: turn.failure, .en).text
                        .contains("System Settings"),
                      "the watchdog's remedy was replaced by \"hold the mic and speak again\"")
    }

    /// **The microphone opens once per capture, however many times the surface is rebuilt.**
    ///
    /// `RecordComposer`'s `.task` runs again on a branch flip and on every closed History
    /// panel. Without `micOpened` the second run restarts the engine mid-capture and the
    /// live request's transcript goes with it, with nothing on screen saying so.
    ///
    /// RED, 22 Aug (measured): `guard !micOpened` deleted from `openMic` — **2 tests fail**
    /// (this one, where `startCount` reads 3, and
    /// `testAFatalStartIsShownOnceAndNotRetriedOnEveryRebuild`).
    func testTheMicrophoneOpensOncePerCaptureNoMatterHowOftenTheSurfaceIsRebuilt() {
        let listener = SpeechFakesTests.FakeListener()
        var turn = RecordTurn()
        turn.openMic(listener)
        turn.openMic(listener)
        turn.openMic(listener)
        XCTAssertEqual(listener.startCount, 1)
        XCTAssertEqual(turn.phase, .capturing)
    }

    /// **A refused `start()` is shown, and it is not retried once per rebuild.**
    ///
    /// `micOpened` is set *before* `start()` is attempted for exactly this: a fatal failure
    /// re-attempted on every structural rebuild would churn the engine behind an error the
    /// founder is already reading.
    ///
    /// **RED, 22 Aug (measured).** Moving `micOpened = true` below the `do`/`catch` — **2
    /// tests fail** (this one, where `startCount` reads 2, and
    /// `testTheMicrophoneOpensOncePerCaptureNoMatterHowOftenTheSurfaceIsRebuilt`). Swallowing
    /// the `catch` instead — **1 test fails**, this one: `phase` stays `.connecting` and
    /// `failure` is nil, which is the "Connecting… forever" surface.
    func testAFatalStartIsShownOnceAndNotRetriedOnEveryRebuild() {
        let listener = SpeechFakesTests.FakeListener()
        listener.refuseStart = VoiceAudioError.engineFailed("-10875")
        var turn = RecordTurn()
        turn.openMic(listener)
        turn.openMic(listener)

        XCTAssertEqual(listener.startCount, 1)
        XCTAssertEqual(turn.phase, .failed)
        XCTAssertNotNil(turn.failure)
        XCTAssertEqual(RecordChrome.line(phase: turn.phase, partial: turn.partial,
                                         failure: turn.failure, .en).kind, .failure)
        XCTAssertEqual(RecordChrome.controls(for: turn.phase, partial: turn.partial), [.cancel],
                       "after a fatal start the one useful control is out")
    }

    /// **Recognition dying mid-capture reaches the screen — unsuppressed, unlike voice
    /// mode's.**
    ///
    /// `VoiceTurn.wire` swallows a failure raised while the pet is speaking, because voice
    /// processing cancels the pet's own audio out of the microphone and a request left open
    /// through a reply hears genuine silence. Record has no reply and no `.speaking`, so
    /// every failure it can see is a real one — the alternative is the founder holding the
    /// mic against a transcript that will never fill, which is the whole day
    /// `RecognitionWatchdog` was built for.
    ///
    /// RED, 22 Aug (measured): dropping the `onFailure` closure from `wire` — **1 test
    /// fails**, this one; `phase` stays `.capturing` with `failure` nil, and the surface is a
    /// live-looking waveform that hears nothing.
    func testRecognitionDyingMidCaptureTakesTheSlotInsteadOfBeingSwallowed() {
        let listener = SpeechFakesTests.FakeListener()
        var turn = RecordTurn()
        let binding = Binding(get: { turn }, set: { turn = $0 })
        RecordTurn.wire(binding, listener: listener)
        turn.openMic(listener)

        listener.emit("add pricing")
        XCTAssertEqual(turn.partial, "add pricing", "onPartial never reached the slot")
        listener.onLevel?(0.5)
        XCTAssertEqual(turn.level, 0.5, accuracy: 0.001)

        listener.failMidSession(VoiceAudioError.recognitionNeverAnswered)
        XCTAssertEqual(turn.phase, .failed)
        XCTAssertNotNil(turn.failure)
        XCTAssertEqual(turn.level, 0)
        XCTAssertFalse(listener.isRunning)
        XCTAssertFalse(RecordFlow.canTakeDraft(partial: turn.partial, phase: turn.phase),
                       "a dead recognizer must not leave ✓ live over a stale transcript")
    }

    /// **Leaving stops the microphone, and it is the only thing leaving has to do.**
    ///
    /// `VoiceTurn.leave` also calls `voice.stopImmediately()` — without it the pet keeps
    /// talking to a composer that is gone, with the chiptune SFX ducked to zero for the rest
    /// of the process. Record's teardown is one microphone, which is the whole of why ⌘B
    /// mid-capture is harmless where ⌘B mid-reply was not.
    ///
    /// RED, 22 Aug (measured): emptying `leave`'s body — **1 test fails**, this one, on
    /// `isRunning`.
    func testLeavingRecordStopsTheMicrophoneAndHasNothingElseToUndo() {
        let listener = SpeechFakesTests.FakeListener()
        var turn = RecordTurn()
        turn.openMic(listener)
        turn.level = 0.9
        turn.leave(listener)
        XCTAssertFalse(listener.isRunning)
        XCTAssertEqual(turn.level, 0)
    }

    /// **A fresh capture starts from a fresh turn, and the field that fails loudest while
    /// being invisible is `micOpened`.**
    ///
    /// The state is hoisted onto `CopilotChatView` so it survives that view's re-renders,
    /// which means it also survives the previous capture ending. A capture that inherited
    /// `micOpened == true` would never open its microphone and would read `Connecting…`
    /// forever, with no error anywhere.
    func testAFreshCaptureCarriesNothingOverFromTheLastOne() {
        let turn = RecordTurn()
        XCTAssertEqual(turn.phase, .connecting)
        XCTAssertEqual(turn.partial, "")
        XCTAssertEqual(turn.level, 0)
        XCTAssertNil(turn.failure)
        XCTAssertFalse(turn.micOpened)
    }
}
#endif
