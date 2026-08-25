// codepet/Models/VoiceHotkey.swift
import SwiftUI

/// **The three keys the expanded composer answers to, and the rule that gates each.**
///
/// Founder, 22 Aug: **Esc** leaves voice mode, **⌘⏎** is ✓, **⌘⌫** is ✕.
///
/// **Why this is a type and not three `.keyboardShortcut` modifiers.** Every other rule
/// on this feature that decides whether a control can do anything was pulled out of the
/// view for the same reason, written out on `VoiceTurnFlow.canTakeTurn` and
/// `VoicePermission.canEnterVoiceMode`: *a control that is live one moment too early
/// looks exactly like a control that is right.* A hotkey is worse than a button here,
/// because a button at least shows its own disabled state — a key that silently does
/// nothing, or worse fires when the button under it is greyed out, has nothing on screen
/// to give it away. Inline in a `.keyboardShortcut` no test can reach it.
///
/// **The assignment itself is data for a second reason: collisions.** `AppShellView` and
/// `TwoModeShellView` both own ⌘B, `CodePetApp` owns ⌘, / ⌘1–7 / ⌘⇧T / ⌘⇧M, `TopNavView`
/// owns ⌘⇧H, and §10 reserves ⌘D for record. None of those is Esc, ⌘⏎ or ⌘⌫ — audited
/// 22 Aug by grepping every `keyboardShortcut` in the target — and
/// `VoiceHotkeyTests.testNoTwoVoiceHotkeysShareAKeyAndNoneIsTheAppsOwnShortcut` is what
/// notices if that changes.
///
/// **Modified rather than bare, and the reason survives the current surface.** ✓ and ✕
/// carry ⌘ so they cannot collide with typing. Voice mode has no text field of its own —
/// `CopilotChatView` renders `VoiceComposer` *instead of* `ChatComposer`, so
/// `ComposerField`'s bare-Return `onSubmit` is not even on screen while these are live —
/// but a bare ⏎/⌫ pair is one surface change away from eating her keystrokes, and ⌘⌫ is
/// also what "discard" reads as on macOS. Esc alone is the exception, because Esc alone
/// is what "get me out of here" reads as everywhere else in this app
/// (`SettingsModal.onExitCommand`, `TaskNodePanel`'s `.cancelAction`).
enum VoiceHotkey: CaseIterable {

    /// **Esc — leave voice mode.** The same thing the waveform toggle does; it is
    /// deliberately attached to that button rather than to a hidden one, so there is
    /// exactly one exit path and `VoiceTurn.leave`'s `stopImmediately()` +
    /// `listener.stop()` cannot be reached by a second route that forgets one of them.
    /// The other half of that teardown lives on `CopilotChatView`'s `.onDisappear`,
    /// because ⌘B and a mode switch remove the pane without anything calling `close()`.
    case exit
    /// **⌘⌫ — ✕, discard this sentence and keep listening.** `⌫` because it reads as
    /// discard; ⌘ because bare ⌫ is a text-editing key.
    case discard
    /// **⌘⏎ — ✓, take the turn.** Return is send everywhere in this app; ⌘ keeps it off
    /// the composer's own bare-Return submit.
    case send

    var key: KeyEquivalent {
        switch self {
        case .exit:    return .escape
        case .discard: return .delete
        case .send:    return .return
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .exit:              return []
        case .discard, .send:    return .command
        }
    }

    /// **Whether pressing it right now does anything — the same value the button under
    /// it uses for `.disabled`, so the two cannot disagree.**
    ///
    /// This is read by `VoiceComposer` for both purposes at once (see `circleButton`'s
    /// `enabled:`), which is deliberate: a hotkey gated by one expression and a button
    /// greyed by another is exactly the drift this type exists to prevent. A disabled
    /// SwiftUI `Button` does not fire its own `keyboardShortcut`, so attaching the
    /// shortcuts to the real buttons is belt to this braces rather than the only guard.
    ///
    /// Nothing here is restated from elsewhere:
    ///
    /// - **`.send` defers entirely to `VoiceTurnFlow.canTakeTurn`**, which owns all three
    ///   ways a send could do nothing — an empty transcript, a state that is not
    ///   `.listening`, and a turn already in flight — and each of those fails silently.
    ///   `canTakeTurn`'s own `state == .listening` is also what keeps ⌘⏎ off the `.idle`
    ///   composer, where `VoiceChrome.controls(for:)` does not offer ✓ at all. A second
    ///   `controls(for:)` check here would therefore be a guard with **no possible RED**,
    ///   which is the thing `CLAUDE.md` forbids.
    /// - **`.discard` defers to `VoiceChrome.controls(for:)`**, and that is not the same
    ///   fact: ✕ stays enabled with an empty transcript on purpose (it clears, and
    ///   clearing nothing is harmless, where a ✕ that greyed out the moment she paused to
    ///   think would read as a composer that had stopped working). What it must NOT do is
    ///   fire in `.idle`, where the button is not on screen — nothing has been heard, so
    ///   there is nothing to discard.
    /// - **`.exit` is unconditional, and that has no RED**, because there is nothing to
    ///   gate: spec §4 makes the waveform button both the toggle and the exit, so the
    ///   composer is never on screen without a way out — including after a fatal
    ///   `start()` failure, which is the state a founder is most likely to want out of.
    ///   The assertion for it documents that intent and goes red only if someone gates
    ///   the exit.
    static func isEnabled(_ hotkey: VoiceHotkey, partial: String,
                          state: VoiceState, isBusy: Bool) -> Bool {
        switch hotkey {
        case .exit:
            return true
        case .discard:
            return VoiceChrome.controls(for: state).contains(.discard)
        case .send:
            return VoiceTurnFlow.canTakeTurn(partial: partial, state: state,
                                             isBusy: isBusy)
        }
    }
}
