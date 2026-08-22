// codepet/Models/RecordChrome.swift
import Foundation

/// **What the founder READS while record is capturing** — spec §10's "the same chrome
/// voice mode uses", which is mostly true and is not entirely true, and this file is
/// where the difference is written down.
///
/// Pure and static for `VoiceChrome`'s reason: every string below fails in a way no
/// layout number can see, and inside a `View`'s private computed property no test can
/// reach one.
///
/// **It delegates rather than duplicates.** ✕, ✓, `Cancel`, the failure copy and spec
/// §3's privacy disclosure are `VoiceChrome`'s already and are reached through it, so
/// there is exactly one Vietnamese translation of each. Only two things are record's own:
/// the phase captions (record has `.held`, voice mode has `.thinking`/`.speaking`, and
/// neither machine can reach the other's states) and the mic toggle's label.
enum RecordChrome {

    // MARK: - The one text slot

    /// What the composer's text slot is showing, and how to paint it. Reuses
    /// `VoiceChrome.Line` — the same three sources compete for the same one line, and a
    /// second `Kind` enum would be a second thing for the surface's `.italic` and
    /// `.foregroundStyle` to switch on.
    ///
    /// **The precedence is the invariant, and it is `VoiceChrome.line`'s precedence.** A
    /// failure outranks every caption, because the founder must never be told the
    /// microphone is live and dead in the same frame; the transcript outranks the caption
    /// while it is hers, which in record is every phase that has one.
    static func line(phase: RecordPhase, partial: String, failure: Error?,
                     _ lang: AppLanguage) -> VoiceChrome.Line {
        if let failure {
            return VoiceChrome.Line(text: VoiceChrome.failureText(failure, lang), kind: .failure)
        }
        let heard = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unlike voice mode, there is no phase in which she has words AND the slot has
        // something more urgent to say. `.thinking` and `.speaking` are why
        // `VoiceChrome.line` restricts the transcript to `.listening`; record has neither.
        if !heard.isEmpty {
            return VoiceChrome.Line(text: partial, kind: .transcript)
        }
        return VoiceChrome.Line(text: caption(phase, lang), kind: .caption)
    }

    /// The phase, as the placeholder reads it.
    ///
    /// `.connecting` and `.capturing` borrow voice mode's own words — the founder is
    /// looking at the same box doing the same thing, and two different translations of
    /// "Listening…" in one composer would be a tell that these are two features rather
    /// than two controls.
    static func caption(_ phase: RecordPhase, _ lang: AppLanguage) -> String {
        switch phase {
        case .connecting: return VoiceChrome.caption(.idle, lang)
        case .capturing:  return VoiceChrome.caption(.listening, lang)
        case .held:       return nothingHeardText(lang)
        // A `.failed` phase with no failure object is not reachable — `openMic` and
        // `wire`'s `onFailure` are the only two writers of it and both set `failure`
        // first — but "Connecting…" is the honest fallback if it ever becomes so,
        // because it is what the slot said before anything was heard.
        case .failed:     return VoiceChrome.caption(.idle, lang)
        }
    }

    /// **`.held` with nothing heard, which is the one state record can reach that voice
    /// mode cannot, and the one place the watchdog cannot help.**
    ///
    /// `RecognitionWatchdog` needs `grace` (10s) of real audio before it will say that
    /// recognition never answered, and a press-and-hold is usually two seconds. Release
    /// stops the listener, the watchdog loop exits on `guard self.isRunning`, and the
    /// verdict is never reached — so a founder who held the mic, spoke, and got nothing
    /// would otherwise be looking at an empty italic slot with no explanation at all.
    ///
    /// **It does not diagnose, and that is deliberate.** The watchdog's own message names
    /// System Settings → Keyboard → Dictation because after 10s of real audio a missing
    /// speech model is the measured cause. Two seconds establishes nothing: she may not
    /// have spoken, the press may have been shorter than the engine's ~200ms spin-up, or
    /// the model may indeed be missing. Naming a remedy on that evidence is the
    /// `privacyLine` defect again — a claim from a flag that does not establish it — so
    /// this says what happened and what to do about it, and stops there. Hold for ten
    /// seconds and the watchdog's own diagnosis takes this slot instead.
    static func nothingHeardText(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Không nghe được gì. Hãy giữ micro và nói lại."
            : "No words came back. Hold the mic and speak again."
    }

    // MARK: - The controls

    /// **Which controls a phase offers.** `VoiceChrome.Control` rather than a fourth
    /// enum: the circles are the same circles, and `VoiceChrome.label(for:_:)` is the one
    /// entry point that keeps the surface from labelling ✕ with the exit's words.
    ///
    /// Its failure is not cosmetic in either direction — `Cancel` beside ✕/✓ steals the
    /// width they sit in, and ✕/✓ in `.connecting` offers two controls that can do
    /// nothing.
    ///
    /// **`.held` reads `partial`, and voice mode's equivalent does not have to.** ✕ in
    /// voice mode stays enabled with an empty transcript because it clears and keeps
    /// listening, so a greyed ✕ would read as a composer that had stopped working. Record
    /// is not listening any more: with nothing heard, ✕ and ✓ are both inert and the one
    /// useful control is out — which is exactly the argument `VoiceChrome.controls`
    /// makes for `.idle`.
    static func controls(for phase: RecordPhase, partial: String) -> [VoiceChrome.Control] {
        switch phase {
        case .connecting, .failed:
            return [.cancel]
        case .capturing:
            return [.discard, .send]
        case .held:
            return partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [.cancel]
                : [.discard, .send]
        }
    }

    /// The mic toggle's tooltip and accessibility label. **Two meanings, and the label is
    /// the only thing that tells them apart**, so it is not decoration.
    ///
    /// While `.capturing` the button stops the capture — the same thing releasing the
    /// mouse does, which is why it is the same glyph in the same corner. Once stopped
    /// there is nothing left to stop, and the button is disabled rather than quietly
    /// becoming a second exit: ✕ is the exit, and a control that changes what it does
    /// under her pointer is the defect the fixed-height transcript slot exists to avoid.
    static func toggleLabel(for phase: RecordPhase, _ lang: AppLanguage) -> String {
        if phase == .capturing {
            return lang == .vi ? "Dừng ghi" : "Stop recording"
        }
        return lang == .vi ? "Đã dừng ghi" : "Recording stopped"
    }

    /// The mic button in `ChatComposer` — the way *in*. Names the gesture, because
    /// press-and-hold is not what a button looks like: this is the tooltip Claude's own
    /// composer carries, and it is where the founder read it (spec §10).
    static func micLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Giữ để ghi âm (⌘D)" : "Press and hold to record (⌘D)"
    }
}
