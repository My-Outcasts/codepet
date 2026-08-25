// codepet/Models/RecordTurn.swift
import SwiftUI
import os

/// **Where a record capture is** — spec §10, the second composer voice control, added
/// 22 Aug.
///
/// Not `VoiceState`, and the difference is the whole feature. `VoiceState` has
/// `.thinking` and `.speaking` because voice mode sends a turn and a pet answers it
/// aloud; record sends nothing and nothing is spoken back, so both of those states are
/// unreachable — and a machine that can reach a state its surface cannot describe is how
/// a composer ends up reading "Thinking…" over a draft nobody is thinking about.
///
/// What record has instead is a state voice mode does not: **`.held`.** Release stops
/// capturing and the transcript stays so it can be judged (spec §10), and that moment is
/// visibly different from capturing — the bars are flat and the microphone is off — while
/// still offering ✕ and ✓. Voice mode has no equivalent because its ✓ is the end of the
/// turn rather than the start of an edit.
enum RecordPhase: Equatable {
    /// `listener.start()` is spinning the engine up (~200ms). The composer is on screen
    /// reading `Connecting…` while it happens, for the same reason voice mode's `.idle`
    /// is: started before the surface existed there would be no frame in which the
    /// founder is told what is happening.
    case connecting
    /// The microphone is live and partials are arriving. Bars track the level.
    case capturing
    /// **She let go.** The microphone is off, the transcript stands, and the only two
    /// things left are ✓ (into the field) and ✕ (bin it). Bars flat, because nothing is
    /// being captured and a bar that moved here would be claiming otherwise.
    case held
    /// Recognition died — `start()` threw, or `onFailure` fired after it returned. The
    /// composer stays expanded to show it; the only useful control is out.
    case failed
}

/// **The rules record keeps, and the one thing this file cannot do.**
///
/// `RecordFlow` is to `RecordTurn` what `VoiceTurnFlow` is to `VoiceTurn`: the pure
/// decisions, taking their inputs explicitly, so `RecordFlowTests` drives all of them
/// without a microphone. It is a separate type rather than five more statics on
/// `VoiceTurnFlow` because that file's statics are byte-identical to a reviewed original
/// and that property is load-bearing.
///
/// **No function here takes a `SpeakingVoice`, and that is the requirement rather than
/// an accident.** Spec §10: record never touches `SpeakingVoice` — no `beginReply`, no
/// `enqueue`, no `endOfReply`, no `stopImmediately`. A rule enforced by the type system
/// cannot be broken by a future edit that forgets it, where a rule enforced by a test
/// can only be broken loudly. Compare `VoiceTurnFlow.takeTurn`, which takes a
/// `SpeakingVoice` **because** its first job is `voice.beginReply()`: the two signatures
/// are the difference between the two features, in the one place a compiler reads.
///
/// **And `takeDraft` takes no `SpeechListening` either**, which is the second half of the
/// same argument. ✓ in record is a string arriving in a text field; the microphone was
/// already stopped by the release (`RecordTurn.endCapture`) and the listener is released
/// when record mode collapses. A `listener.endTurn()` here would be a call with no
/// possible RED — nothing can reach the glued-question failure it exists to prevent,
/// because a record session's listener never survives to hear a second turn.
enum RecordFlow {

    // MARK: - ✓

    /// Whether ✓ can take the draft. **Two ways a tap could do nothing, both silent.**
    ///
    /// 1. An empty transcript. Writing `""` into the field looks exactly like a dead
    ///    button, and it is the state a founder reaches by pressing the mic and not
    ///    speaking — which is common, not exotic.
    /// 2. A phase with nothing to take. `.connecting` has heard nothing yet and
    ///    `.failed` never will.
    ///
    /// **`isBusy` is deliberately absent, and it is the one place record and voice mode
    /// disagree on a rule rather than on a surface.** `VoiceTurnFlow.canTakeTurn` gates
    /// on it because `CompanyStore.sendMessage` early-returns while a turn is in flight,
    /// so ✓ would spend a tap on nothing. Record does not call `sendChat` at all — ✓
    /// writes a string into `chatDraft` — and the founder is *already* free to type into
    /// that field while a reply streams. A busy gate here would take away, from the
    /// dictated draft, something the typed draft has.
    static func canTakeDraft(partial: String, phase: RecordPhase) -> Bool {
        guard phase == .capturing || phase == .held else { return false }
        return !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ✓ — the text, trimmed, or `nil` when there was nothing to take.
    ///
    /// Pure and total: no listener, no voice, no store. See the type's note for why both
    /// absences are the requirement.
    static func takeDraft(partial: String, phase: RecordPhase) -> String? {
        guard canTakeDraft(partial: partial, phase: phase) else { return nil }
        return partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **What the field ends up holding — and it appends rather than replaces.**
    ///
    /// Spec §10 says ✓ puts the text into the composer's field "as an editable draft".
    /// It does not say what happens to a draft that is already there, and the two
    /// answers are not equally safe: replacing silently destroys typing the founder has
    /// no other copy of, and the record surface is swapped in *over* the field, so while
    /// she is dictating she cannot see what she is about to lose. Appending destroys
    /// nothing, and the surface she lands in is a text field with a caret in it — the
    /// one place undoing an unwanted append costs a selection and a keypress.
    ///
    /// A single space joins them, and only when the existing draft does not already end
    /// in whitespace: she may well have typed "and then " on purpose.
    static func merge(draft: String, dictated: String) -> String {
        guard !draft.isEmpty else { return dictated }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return dictated
        }
        return draft.last?.isWhitespace == true ? draft + dictated : draft + " " + dictated
    }
}

/// **One record capture's state**, hoisted onto `CopilotChatView` for exactly the reason
/// `VoiceTurn` is: the composer slot is rendered from inside a three-way `if/else`, and
/// different branches of an `if/else` are different structural identities, so `@State`
/// on the surface does not survive the transcript going from empty to non-empty.
///
/// Record cannot reach that branch flip by sending — it never sends — but it can reach it
/// the other way round: a typed reply arriving while she dictates flips
/// `chatMessages.isEmpty` under her, and a `@State` transcript would be destroyed
/// mid-sentence with nothing on screen saying so. The hoist costs one `@Binding` and
/// removes the whole class.
///
/// Smaller than `VoiceTurn` by exactly the reply pipeline: no `VoiceReplyDriver`, because
/// there is no reply to split into sentences.
struct RecordTurn {

    var phase: RecordPhase = .connecting
    /// What recognition has heard. Shown for spec §4's reason, which record inherits
    /// unchanged: a founder who cannot see what was heard will not trust it — and here
    /// she is about to edit it, so seeing it is the point rather than the reassurance.
    var partial = ""
    /// Input level 0…1, for the bar waveform. Only read while `.capturing`.
    var level: Float = 0
    /// Recognition died after `start()` returned, or `start()` itself threw.
    var failure: Error?

    /// Whether the microphone has been opened for **this** record session.
    ///
    /// The same flag `VoiceTurn.micOpened` is, for the same reason: the surface's `.task`
    /// opens the mic and that `.task` runs again on every structural rebuild, so without
    /// this a branch flip restarts the engine mid-capture and the live
    /// `SFSpeechAudioBufferRecognitionRequest`'s transcript goes with it. Set **before**
    /// `start()` is attempted, so a fatal start failure is not retried once per rebuild.
    var micOpened = false

    init() {}
}

// MARK: - Lifecycle

extension RecordTurn {

    /// Open the microphone, once per record session. The failure is SHOWN, not
    /// swallowed, and the composer stays expanded to show it.
    mutating func openMic(_ listener: SpeechListening) {
        let wasOpened = micOpened
        VoiceLog.surface.log("record openMic(): micOpened=\(wasOpened, privacy: .public)")
        guard !micOpened else { return }
        micOpened = true
        do {
            try listener.start()
        } catch {
            VoiceLog.surface.error("""
                record openMic(): listener.start() THREW \
                \(VoiceLog.describe(error), privacy: .public) — showing it
                """)
            failure = error
            phase = .failed
            return
        }
        phase = .capturing
    }

    /// **Installs the listener's three callbacks against the hoisted state.**
    ///
    /// A `Binding` rather than `mutating` for `VoiceTurn.wire`'s reason: every closure
    /// here outlives the call, and a binding derived from `CopilotChatView`'s `@State`
    /// keeps writing through after the surface instance that installed it has been torn
    /// down by a branch flip.
    ///
    /// **Three closures, not four.** `VoiceTurn.wire` also installs
    /// `voice.onFinishedAll`, and there is no `voice`. `onPartial` also has no barge-in
    /// branch, because nothing is ever speaking for her to interrupt — the `.speaking`
    /// arm of `VoiceTurn`'s `onPartial` and the `.speaking` suppression in its
    /// `onFailure` are both unreachable here rather than omitted.
    static func wire(_ turn: Binding<RecordTurn>, listener: SpeechListening) {
        listener.onPartial = { text in turn.wrappedValue.partial = text }
        listener.onLevel = { level in turn.wrappedValue.level = level }
        // Recognition died after `start()` returned — the grant was revoked, the service
        // went away, the network dropped under vi-VN (server-side, spec §3), or
        // `RecognitionWatchdog` found that real audio flowed and nothing ever came back.
        //
        // **Unsuppressed, unlike voice mode's, and the asymmetry is the point.**
        // `VoiceTurn.wire` swallows a failure raised while the pet is speaking, because
        // voice processing cancels the pet's own audio out of the microphone and a
        // request left open through a reply hears genuine silence. Record has no reply
        // and no `.speaking`, so every failure it can see is a real one and every one of
        // them must reach the screen — the alternative is the founder holding the mic
        // against a transcript that will never fill.
        listener.onFailure = { error in
            VoiceLog.surface.log("record onFailure: \(VoiceLog.describe(error), privacy: .public)")
            listener.stop()
            var t = turn.wrappedValue
            t.failure = error
            t.level = 0
            t.phase = .failed
            turn.wrappedValue = t
        }
    }

    /// **Release, or ⌘D a second time: stop capturing and keep the words.**
    ///
    /// `listener.stop()` rather than `endTurn()`, and the choice is a privacy one rather
    /// than a tidiness one. `endTurn()` retires the recognition request but leaves the
    /// engine running and the tap installed — the microphone stays open. The founder has
    /// just taken her finger off a button whose whole affordance is that holding it is
    /// what records; a surface that shows flat bars while the tap is still feeding audio
    /// to Apple would be lying in the one direction spec §3 exists to prevent.
    ///
    /// **The cost, stated because it is real and is not recoverable here.**
    /// `stop()` → `retireRecognition()` calls `feed.endAudio()` and then `task?.cancel()`
    /// on the next line, so the final result never arrives: the last ~100–200ms of audio,
    /// which is often the last word she said, is not transcribed. That is a truncated
    /// draft rather than a wrong one, it is visible on screen before ✓, and ✓ lands it in
    /// a text field with a caret — which is the one surface where finishing a clipped
    /// word costs two keystrokes. Fixing it properly means an `endCapture()` on
    /// `SpeechListening` that ends the audio, removes the tap and waits for the final
    /// result without cancelling; that is a change to the audio service and is not in
    /// this feature.
    mutating func endCapture(_ listener: SpeechListening) {
        guard phase == .capturing else { return }
        listener.stop()
        level = 0
        phase = .held
    }

    /// Leaving record — ✕, `Cancel`, or Esc. Nothing is written anywhere.
    ///
    /// **No `voice.stopImmediately()`, because there is no voice.** `VoiceTurn.leave`
    /// needs it (invariant 4: the pet keeps talking to a composer that is gone, with the
    /// chiptune SFX ducked to zero for the rest of the process); record's teardown is one
    /// microphone and nothing else, which is the whole of why ⌘B mid-record is harmless
    /// where ⌘B mid-reply was not.
    mutating func leave(_ listener: SpeechListening) {
        listener.stop()
        level = 0
    }
}

// MARK: - ✓

extension RecordTurn {

    /// ✓ — the text to put in the field, or `nil` when there was nothing to take.
    ///
    /// Takes nothing and touches nothing. The write itself is `CopilotChatView`'s, which
    /// is where `companyStore.chatDraft` and `RecordFlow.merge` meet.
    func take() -> String? {
        RecordFlow.takeDraft(partial: partial, phase: phase)
    }
}

/// **The three keys the record composer answers to** — spec §10 reserved ⌘D, and the
/// other two are the keys the same two circles already carry in voice mode.
///
/// A type for `VoiceHotkey`'s reasons, not restated here: a key that silently does
/// nothing, or fires while the button under it is greyed, has nothing on screen to give
/// it away, and inline in a `.keyboardShortcut` no test can reach it.
///
/// **⌘⌫ is deliberately not one of them, and that is the one place record has fewer keys
/// than voice mode.** In voice mode ✕ discards a sentence and *keeps listening*, so it is
/// a different action from Esc and needs its own key. In record the microphone is already
/// off by the time ✕ is worth pressing, so there is nothing to keep — ✕ discards the
/// transcript and leaves. Esc is what "get me out of here" reads as everywhere in this
/// app, so Esc is that key, and a second ⌘⌫ for the identical action would be two keys
/// for one rule.
///
/// **⌘D is the toggle, because a keyboard shortcut cannot be held.** The mouse gesture
/// presses and releases; ⌘D starts on the mic button in `ChatComposer` and stops on this
/// surface. The two halves are on two views that are never on screen at once, which is
/// what makes one keystroke a toggle without any state deciding which half it is.
enum RecordHotkey: CaseIterable {
    /// ⌘D — stop capturing. The start half of the same keystroke lives on
    /// `ChatComposer`'s mic button.
    case toggle
    /// Esc — discard and leave record. Attached to ✕, so there is exactly one path out
    /// and `RecordTurn.leave`'s `stop()` cannot be reached by a second route that
    /// forgets it.
    case exit
    /// ⌘⏎ — ✓, the text into the field.
    case send

    /// The voice-mode hotkey this shares a keystroke with, or `nil` for ⌘D, which is
    /// record's own.
    ///
    /// Derived rather than copied: Esc and ⌘⏎ are the same two circles in the same corner
    /// of the same card, so a change to voice mode's assignment has to move record's with
    /// it. Two literals would be two things that can disagree, and the disagreement is
    /// invisible — each surface would work perfectly on its own.
    var sharedWithVoiceMode: VoiceHotkey? {
        switch self {
        case .toggle: return nil
        case .exit:   return .exit
        case .send:   return .send
        }
    }

    var key: KeyEquivalent { sharedWithVoiceMode?.key ?? "d" }
    var modifiers: EventModifiers { sharedWithVoiceMode?.modifiers ?? .command }

    /// **Whether pressing it right now does anything — the same value the button under it
    /// uses for `.disabled`**, so the two cannot disagree.
    ///
    /// - `.send` defers entirely to `RecordFlow.canTakeDraft`, which owns both ways a ✓
    ///   could do nothing.
    /// - `.toggle` is live only while `.capturing`. `.connecting` has no capture to stop
    ///   yet, and in `.held`/`.failed` it is already stopped — a ⌘D that fired there would
    ///   be a keystroke doing nothing at all, which is the thing this type exists to
    ///   catch.
    /// - `.exit` is unconditional, and that has **no RED**, because there is nothing to
    ///   gate: the composer is never on screen without a way out, including after a fatal
    ///   `start()` failure, which is the state a founder most wants out of. The assertion
    ///   documents the intent and goes red only if someone gates the exit.
    static func isEnabled(_ hotkey: RecordHotkey, partial: String, phase: RecordPhase) -> Bool {
        switch hotkey {
        case .exit:
            return true
        case .toggle:
            return phase == .capturing
        case .send:
            return RecordFlow.canTakeDraft(partial: partial, phase: phase)
        }
    }
}
