// codepetTests/VoiceHotkeyTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// **The three keys the expanded composer answers to** — founder, 22 Aug: Esc leaves
/// voice mode, ⌘⏎ is ✓, ⌘⌫ is ✕.
///
/// **What this suite cannot see, said up front rather than implied by a green tick.**
/// Nothing here renders `VoiceComposer`, and nothing anywhere can: a `.keyboardShortcut`
/// modifier is invisible to `ImageRenderer`, which fires no lifecycle hooks and reports
/// only a size. So *that the composer attaches these keys to those buttons* is a handoff
/// to the founder's own keyboard, exactly like the note on
/// `VoiceComposerTests.testTheComposersMeasuredHeightIsPinnedWithAndWithoutTheDisclosure`
/// about the circles' mere presence. What IS asserted is everything that decides whether
/// a press does anything — which is where all three of this feature's silent failures
/// would live: a key that fires when the button under it is greyed, a key that sends an
/// empty turn, and a key assigned to something the app already owns.
///
/// No audio here: `VoiceHotkey` is pure and takes its inputs explicitly, for the same
/// reason `VoiceTurnFlow` does.
@MainActor
final class VoiceHotkeyTests: XCTestCase {

    // MARK: - The assignment

    /// **⌘⏎ sends and ⌘⌫ discards, and they are not the other way round.**
    ///
    /// Not a tautology in the direction that matters: swapping the two is a single-line
    /// edit whose cost is asymmetric and silent. ⌘⌫ landing on ✓ spends 0.25 credits on a
    /// sentence she had just decided to throw away — §7's own prediction is that
    /// "Codepet", "byte", "nova" and the department names are exactly what the recognizer
    /// mangles — and ⌘⏎ landing on ✕ bins a sentence she had just finished checking, with
    /// `listener.endTurn()` making sure it cannot come back.
    ///
    /// RED: swap the two `case` bodies in `VoiceHotkey.key`.
    func testSendIsCommandReturnAndDiscardIsCommandDeleteAndNotTheReverse() {
        XCTAssertEqual(VoiceHotkey.send.key.character, KeyEquivalent.return.character,
                       "✓ is not on ⏎")
        XCTAssertEqual(VoiceHotkey.send.modifiers, .command, "✓'s key is not ⌘-modified")
        XCTAssertEqual(VoiceHotkey.discard.key.character, KeyEquivalent.delete.character,
                       "✕ is not on ⌫")
        XCTAssertEqual(VoiceHotkey.discard.modifiers, .command,
                       "✕'s key is not ⌘-modified")
        XCTAssertEqual(VoiceHotkey.exit.key.character, KeyEquivalent.escape.character,
                       "the exit is not on Esc")
        XCTAssertEqual(VoiceHotkey.exit.modifiers, [],
                       "Esc picked up a modifier — 'get me out' is a bare key everywhere "
                       + "else in this app")
    }

    /// **The two destructive keys are modified, so they cannot be typing.**
    ///
    /// The founder's stated reason for ⌘ rather than bare ⏎/⌫. It is currently true for a
    /// second reason too — `CopilotChatView` renders `VoiceComposer` *instead of*
    /// `ChatComposer`, so `ComposerField`'s bare-Return `onSubmit` is not on screen while
    /// these are live — and that second reason is exactly why this assertion is worth
    /// having: it is a property of the current surface, one composer change away from
    /// being false, and a bare ⏎ would then send whatever the recognizer had heard the
    /// moment she pressed Return in a text field.
    ///
    /// RED: return `[]` for either case in `VoiceHotkey.modifiers`.
    func testTheTwoKeysThatTakeOrDropATurnAreBothModified() {
        for hotkey in [VoiceHotkey.send, .discard] {
            XCTAssertTrue(hotkey.modifiers.contains(.command),
                          "\(hotkey) is a bare key on a surface that can regain a text "
                          + "field: \(hotkey.key.character)")
        }
    }

    /// **No two voice keys are the same key, and none is a shortcut this app already
    /// owns.**
    ///
    /// The `taken` list was built 22 Aug by grepping every `keyboardShortcut` in the
    /// target, plus the one the spec reserves. It is a snapshot and it will go stale — but
    /// it goes stale in the safe direction: a shortcut that moves away frees a key this
    /// asserts is unavailable, which costs nothing, while a shortcut that moves *onto*
    /// Esc/⌘⏎/⌘⌫ is a real collision this catches. A collision is silent in the worst
    /// way: macOS gives the key to one responder and the other control simply stops
    /// working, with nothing on screen saying which won.
    ///
    /// ⌘D is in the list without existing yet: spec §10 reserves it for record ("Press
    /// and hold to record ⌘D"), and voice mode taking it would be discovered by whoever
    /// builds that.
    ///
    /// RED: set `.send`'s key to `"b"` with `.command`, or give `.discard` the same key
    /// and modifiers as `.send`.
    func testNoTwoVoiceHotkeysShareAKeyAndNoneIsAnExistingAppShortcut() {
        let mine = VoiceHotkey.allCases.map { "\($0.key.character)+\($0.modifiers.rawValue)" }
        XCTAssertEqual(Set(mine).count, VoiceHotkey.allCases.count,
                       "two voice hotkeys are the same keystroke: \(mine)")

        // Audited 22 Aug: AppShellView/TwoModeShellView/ReflectionTab (⌘B), CodePetApp
        // (⌘, and ⌘1–7, ⌘⇧T, ⌘⇧M), TopNavView (⌘⇧H), spec §10 (⌘D, reserved for record).
        var taken: [(Character, EventModifiers)] = [
            ("b", .command), (",", .command), ("d", .command),
            ("t", [.command, .shift]), ("m", [.command, .shift]),
            ("h", [.command, .shift]),
        ]
        for digit in "1234567" { taken.append((digit, .command)) }

        for hotkey in VoiceHotkey.allCases {
            for (character, modifiers) in taken {
                XCTAssertFalse(hotkey.key.character == character
                               && hotkey.modifiers == modifiers,
                               "\(hotkey) collides with the app's existing "
                               + "\(modifiers.rawValue)+\(character) — one of the two will "
                               + "silently stop working")
            }
        }
    }

    // MARK: - The gates

    /// **⌘⏎ can send exactly what the lit ✓ can send, and nothing else.**
    ///
    /// Three ways a press could do nothing or do harm, all three silent, all three owned
    /// by `VoiceTurnFlow.canTakeTurn` rather than restated here: an empty transcript
    /// (`sendChat` drops the string, so the key looks dead), a state that is not
    /// `.listening` (there is no turn to take while the pet thinks or talks), and a turn
    /// already in flight (`sendMessage` early-returns on its own guard, and a keypress has
    /// no next tick to retry on). The whitespace case is the recognizer reporting `" "`.
    ///
    /// This is the assertion that stops ⌘⏎ becoming a bypass. The button is greyed by the
    /// same expression (`VoiceComposer.isEnabled(_:)`), which is why it is one expression.
    ///
    /// RED, 22 Aug: `case .send: return true` — 7 of the 8 assertions below fail, and 8
    /// across the suite (`testEscapeIsTheOnlyHotkeyThatIsLiveInEveryState` loses its
    /// "⌘⏎ is dead somewhere" half, which is the point of that half).
    func testCommandReturnIsLiveExactlyWhenTheCheckmarkIs() {
        for text in ["", " ", "\n  \t"] {
            XCTAssertFalse(VoiceHotkey.isEnabled(.send, partial: text, state: .listening,
                                                 isBusy: false),
                           "⌘⏎ would have sent \(text.debugDescription) — `sendChat` drops "
                           + "it, so the key is a dead press that spends nothing and says "
                           + "nothing")
        }
        XCTAssertTrue(VoiceHotkey.isEnabled(.send, partial: "add pricing",
                                            state: .listening, isBusy: false),
                      "⌘⏎ is dead on a sentence the lit ✓ would send")
        XCTAssertFalse(VoiceHotkey.isEnabled(.send, partial: "add pricing",
                                             state: .listening, isBusy: true),
                       "⌘⏎ was live while a turn was already in flight — `sendMessage` "
                       + "drops it and a keypress has no next tick")
        for state in [VoiceState.idle, .thinking, .speaking] {
            XCTAssertFalse(VoiceHotkey.isEnabled(.send, partial: "add pricing",
                                                 state: state, isBusy: false),
                           "⌘⏎ was live in \(state), where ✓ is greyed or not on screen")
        }
    }

    /// **⌘⌫ is live exactly where ✕ is on screen — including with nothing heard yet.**
    ///
    /// Two directions, and they fail differently. In `.idle` the circle is not drawn at
    /// all (`VoiceChrome.controls(for:)` offers only `Cancel`, because nothing has been
    /// heard), so a live ⌘⌫ there is a key with no visible control and nothing to discard.
    /// In `.listening` with an empty transcript the circle IS drawn and IS enabled on
    /// purpose — a ✕ that greyed out the moment she paused to think reads as a composer
    /// that has stopped working, and clearing nothing is harmless — so gating this on
    /// `canTakeTurn` like ✓ would be wrong.
    ///
    /// RED, 22 Aug: `case .discard: return VoiceTurnFlow.canTakeTurn(partial: partial,
    /// state: state, isBusy: isBusy)` — 7 of the 10 assertions fail: `.listening` with an
    /// empty transcript, all four `.thinking`/`.speaking` rows (`canTakeTurn` refuses both
    /// states outright, which is right for ✓ and wrong for ✕), and both `isBusy` cases.
    func testCommandDeleteIsLiveWhereverTheCrossIsDrawnEvenWithNothingHeard() {
        for text in ["", "add pricing"] {
            XCTAssertFalse(VoiceHotkey.isEnabled(.discard, partial: text, state: .idle,
                                                 isBusy: false),
                           "⌘⌫ fired in Connecting…, where ✕ is not on screen and the "
                           + "recognizer has heard nothing to discard")
        }
        for state in [VoiceState.listening, .thinking, .speaking] {
            for text in ["", "add pricing"] {
                XCTAssertTrue(VoiceHotkey.isEnabled(.discard, partial: text, state: state,
                                                    isBusy: false),
                              "⌘⌫ was dead in \(state) on \(text.debugDescription), where "
                              + "✕ is drawn and enabled")
            }
        }
        for text in ["", "add pricing"] {
            XCTAssertTrue(VoiceHotkey.isEnabled(.discard, partial: text, state: .listening,
                                                isBusy: true),
                          "⌘⌫ went dead because a reply was streaming — ✕ does not send, "
                          + "so `isBusy` is not its business, and greying it mid-reply is "
                          + "the pause-to-think defect")
        }
    }

    /// **Esc is the one hotkey nothing gates, and the other two are not.**
    ///
    /// The first half has no RED and is a statement of intent, not a guard: spec §4 makes
    /// the waveform button both the toggle and the exit, so the composer is never on
    /// screen without a way out — including after a fatal `listener.start()` failure,
    /// which leaves `.idle` on screen with a message and is the state a founder most wants
    /// out of. It goes red only if someone gates the exit.
    ///
    /// The second half is a real guard, and it is what keeps this test from being three
    /// tautologies: each of ⌘⏎ and ⌘⌫ must be dead in at least one reachable state. RED:
    /// `case .discard: return true` — the `.discard` half fails.
    func testEscapeIsTheOnlyHotkeyThatIsLiveInEveryState() {
        let states: [VoiceState] = [.idle, .listening, .thinking, .speaking]
        for state in states {
            for isBusy in [false, true] {
                for text in ["", "add pricing"] {
                    XCTAssertTrue(VoiceHotkey.isEnabled(.exit, partial: text, state: state,
                                                        isBusy: isBusy),
                                  "Esc was refused in \(state)/isBusy=\(isBusy) — the "
                                  + "composer is on screen with no way out")
                }
            }
        }
        for hotkey in [VoiceHotkey.send, .discard] {
            let dead = states.contains { state in
                !VoiceHotkey.isEnabled(hotkey, partial: "add pricing", state: state,
                                       isBusy: false)
            }
            XCTAssertTrue(dead,
                          "\(hotkey) is live in every state, so its gate decides nothing")
        }
    }
}
#endif
