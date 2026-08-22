// codepet/Models/VoiceChrome.swift
import Foundation

/// What the founder READS while voice mode is running — spec §2's "two pieces of
/// chrome the composer must still carry", plus the one text slot that carries the
/// state.
///
/// Pure and static for the same reason `VoiceTurnFlow` is: every string below fails in
/// a way no layout number can see, and inside a `View`'s private computed property no
/// test can reach one. The words moved here from `VoiceModeOverlay` when the takeover
/// was replaced by the in-composer surface (spec §2 decision 2, reversed 22 Aug);
/// `privacyLine`, `discardLabel` and `sendLabel` are unchanged, and the three
/// deliberate changes are each argued at their declaration.
enum VoiceChrome {

    /// 0.25 credits per spoken exchange — spec §7's "ten spoken exchanges is ~2.5
    /// credits in about two minutes", stated as the per-turn number so the price and
    /// the spec cannot drift.
    ///
    /// **Nothing on screen reads this as of 22 Aug** — see `disclosure`, where the
    /// credit count was removed on the founder's instruction. It is kept, labelled,
    /// rather than deleted with the line: the price is a product fact, and putting the
    /// count back is one `Text` if she reverses. `VoiceTurn.turns` is the count itself
    /// and carries the same note.
    static let creditsPerTurn = 0.25

    // MARK: - The bottom-left slot, and the one case it still has something to say

    /// **What the composer's bottom-left slot says — `nil` almost always, as of
    /// 22 Aug.**
    ///
    /// Until 22 Aug this was `statusLine(turns:onDevice:_:)` and always rendered
    /// something: spec §2's `~2 credits · on-device`, escalating to §3's full sentence
    /// when the audio was leaving the Mac. The founder screenshotted that line and said
    /// "remove this info". Both halves of what happened next are argued here, because
    /// one is a spec requirement deliberately dropped and the other is a spec
    /// requirement deliberately kept.
    ///
    /// **The credit count goes, in every case** (founder, 22 Aug) — which drops §7's
    /// "the composer carries a running count". §7 and §2 are amended rather than left
    /// contradicted by this file. The cost is real and is not hidden: nothing on screen
    /// now says what talking spends, while §7's reason for the count — talking is much
    /// faster than typing, so voice makes turns cheap to spend without noticing — is
    /// untouched by removing it. `creditsPerTurn` and `VoiceTurn.turns` are kept for
    /// that reason.
    ///
    /// **The disclosure stays whenever recognition is not on-device, and that is not
    /// tidiness.** §3 is a privacy disclosure. On a Mac with the en-US asset installed
    /// the tag read `on-device`, disclosed nothing, and was the noise the founder saw.
    /// In Vietnamese the same slot says the opposite — her speech goes to Apple's
    /// servers, because no `vi-VN` on-device asset exists (§3, measured 21 Aug) — and so
    /// does English on a Mac where the en-US asset was never installed. Hiding *that* is
    /// a privacy harm, not a cleaner composer. So the off-device case keeps the full
    /// escalated sentence, unchanged, still painted as a warning rather than as chrome.
    ///
    /// **`onDevice` decides it, not `lang`.** See `privacyLine`: this is a property of
    /// which Assistant assets are installed, and a line that reads the language and
    /// ignores the fact is the `lang == .vi ? why : why` defect in a new place.
    ///
    /// **And it is suppressed while a failure is on screen.** This is a SECOND text
    /// slot, and `line(state:partial:failure:_:)`'s precedence — a failure outranks
    /// every caption, because the founder must never be told the microphone is live and
    /// dead in one frame — does not reach here. After `RecognitionWatchdog` fires, the
    /// transcript slot said the microphone was dead while this slot asserted live
    /// recognition ("Your speech is sent to Apple **for recognition**") in the same
    /// frame. Dropping the on-device tag fixes that for the on-device path by leaving
    /// nothing to contradict; it does NOT fix the off-device path, which is where a
    /// failure is most likely — vi-VN recognition is server-side, so a dropped network
    /// is exactly what raises `onFailure`. So the same precedence rule is stated here,
    /// in the slot it did not reach.
    static func disclosure(onDevice: Bool, failure: Error?,
                           _ lang: AppLanguage) -> String? {
        // A failure owns the surface. See above: this slot cannot claim recognition is
        // happening over a line saying the microphone stopped.
        guard failure == nil else { return nil }
        // On-device discloses nothing, so there is nothing to show (founder, 22 Aug).
        guard !onDevice else { return nil }
        return privacyLine(lang, onDevice: false)
    }

    /// **Spec §3, and it is a disclosure rather than a footnote.** Unchanged from the
    /// takeover — the surface moved, the fact did not.
    ///
    /// **`onDevice` decides it, not `lang`.** This used to switch on the language
    /// alone and tell every English founder "nothing you say leaves it" — but
    /// `openRecognition` sets `requiresOnDeviceRecognition` from
    /// `recognizer.supportsOnDeviceRecognition` (`SpeechListening.swift`), and on a Mac
    /// where the en-US Assistant asset was never installed that is `false`: the audio
    /// goes to Apple's servers while the surface says the opposite. Same shape as the
    /// `lang == .vi ? why : why` defect Task 5 caught — a decision that inspects one
    /// input and ignores the one that determines the answer.
    ///
    /// Vietnamese branches too, rather than being hard-coded to "sent to Apple":
    /// `SFSpeechRecognizer(vi-VN)` reports no on-device asset today (measured 21 Aug),
    /// but that is a fact about Apple's assets, not about the language, and a line
    /// that would still read "sent to Apple" the day the asset ships is the same
    /// defect pointing the other way.
    static func privacyLine(_ lang: AppLanguage, onDevice: Bool) -> String {
        if onDevice {
            return lang == .vi
                ? "Nhận dạng chạy trên chiếc Mac này. Không có gì bạn nói rời khỏi máy."
                : "Recognition runs on this Mac. Nothing you say leaves it."
        }
        return lang == .vi
            ? "Giọng nói của bạn được gửi tới Apple để nhận dạng."
            : "Your speech is sent to Apple for recognition. It does not stay on this Mac."
    }

    // MARK: - The one text slot

    /// What the composer's text slot is showing, and how to paint it. Three sources
    /// compete for one line, where the takeover had a caption row AND a transcript
    /// row, so the precedence has to be decided somewhere a test can see it.
    struct Line: Equatable {
        enum Kind: Equatable {
            /// The state, standing in for a placeholder — grey, upright.
            case caption
            /// What recognition has heard this turn — grey italic, "reads like a draft".
            case transcript
            /// Recognition died after `start()` returned — warning-coloured.
            case failure
        }
        let text: String
        let kind: Kind
    }

    /// **Spec §2: "Placeholder text carries the state."** `Connecting…` → the live
    /// transcript → `Listening…` → `Claude is speaking…`, in one slot.
    ///
    /// **The precedence is the invariant, and it replaces a two-row layout.** The
    /// takeover could say "Listening" in its header and "The microphone stopped: …" in
    /// its transcript at the same time, which is why `stateCaption` gave `.idle` its own
    /// word ("Stopped") — the founder was otherwise told the mic was live and dead in
    /// the same frame. The composer has ONE line, so instead the failure takes it:
    /// a failure is reachable in `.idle` and nowhere else (see `VoiceComposer.wire()`
    /// — a failure raised while the pet speaks is expected rather than broken and is
    /// not recorded), so nothing is hidden by letting it win.
    ///
    /// That precedence is also what lets `.idle` read `Connecting…`. `.idle` means two
    /// things here — the moment between the tap and `listener.start()` returning, and a
    /// surface that failed — and the failure branch takes the second, so the caption is
    /// free to describe the first honestly. "Stopped" was right for a takeover that
    /// stayed on screen after dying; it would be wrong for the 200ms of engine spin-up
    /// that is now the only `.idle` a founder sees.
    static func line(state: VoiceState, partial: String, failure: Error?,
                     _ lang: AppLanguage) -> Line {
        if let failure {
            return Line(text: failureText(failure, lang), kind: .failure)
        }
        let heard = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        // The transcript only outranks the caption while it is HER turn. During
        // `.thinking` and `.speaking` the words she queued are still held (see
        // `VoiceTurnFlow.replyEnded`, which deliberately does not clear them) but what
        // the slot has to say is that the turn was taken.
        if !heard.isEmpty, state == .listening {
            return Line(text: partial, kind: .transcript)
        }
        return Line(text: caption(state, lang), kind: .caption)
    }

    /// The state, as the placeholder reads it.
    ///
    /// The three live captions are the takeover's own words with spec §2's ellipsis;
    /// `.idle` is re-worded from "Stopped" to "Connecting…" for the reason written out
    /// in `line(state:partial:failure:_:)`.
    static func caption(_ state: VoiceState, _ lang: AppLanguage) -> String {
        switch state {
        case .idle:      return lang == .vi ? "Đang kết nối…" : "Connecting…"
        case .listening: return lang == .vi ? "Đang nghe…" : "Listening…"
        case .thinking:  return lang == .vi ? "Đang suy nghĩ…" : "Thinking…"
        case .speaking:  return lang == .vi ? "Đang trả lời…" : "Answering…"
        }
    }

    /// Founder-facing text for a recognition failure. `VoiceAudioError` deliberately
    /// carries no copy of its own — chrome is bilingual, so the words live here.
    static func failureText(_ failure: Error, _ lang: AppLanguage) -> String {
        switch failure {
        case VoiceAudioError.recognizerUnavailable:
            return lang == .vi
                ? "Không dùng được nhận dạng giọng nói lúc này."
                : "Speech recognition is not available right now."
        case VoiceAudioError.engineFailed(let why):
            return lang == .vi ? "Micro đã dừng: \(why)" : "The microphone stopped: \(why)"
        case VoiceAudioError.recognitionNeverAnswered:
            return recognitionNeverAnsweredText(lang)
        default:
            return failure.localizedDescription
        }
    }

    /// **The one failure on this path whose remedy the founder cannot guess** — so the
    /// message is mostly the remedy.
    ///
    /// `RecognitionWatchdog` fired: real audio flowed and recognition never answered.
    /// The cause measured on this Mac is that macOS has **no speech assets installed**
    /// (`~/Library/Application Support/com.apple.SpeechRecognitionCore`,
    /// `/System/Library/AssetsV2/com_apple_MobileAsset_SpeechRecognition` and
    /// `/private/var/db/com.apple.speech.recognition` are all empty), while
    /// `SFSpeechRecognizer.supportsOnDeviceRecognition` still reports `true` — it is a
    /// *capability* flag, not a "the model is downloaded" flag. There is no API to
    /// download the asset and no in-app way to trigger it: the only thing that does is
    /// **System Settings → Keyboard → Dictation** — turning it on, or dictating once
    /// anywhere, pulls the asset down. A founder shown "recognition is not available"
    /// here would have nowhere to go.
    ///
    /// **Named path, no jargon, and the cause is hedged on purpose.** "may need" rather
    /// than "is missing", because the watchdog cannot prove she spoke: measured on this
    /// Mac through the production graph, ambient room noise reads `VoiceLevel` **0.375**
    /// median while the founder's own trace measured **0.132** while she was talking, so
    /// no level threshold separates speech from a room and the same verdict is reachable
    /// from a founder who tapped and said nothing. Hedging is what keeps this honest in
    /// that case while still naming the one thing worth trying — the same discipline as
    /// `privacyLine`, which stopped asserting on-device from a flag that did not
    /// establish it.
    ///
    /// **Length is load-bearing.** This lands in the composer's transcript slot, which
    /// is `.lineLimit(2)` at `CodepetType.body` with `truncationMode(.head)` — so a
    /// sentence that needs three lines loses its *beginning* silently — and the slot is
    /// a fixed 40pt, so three lines do not fit the frame either. Measured at the dock's
    /// real 316pt inner width: two lines are 34pt and three are 51pt; both strings below
    /// sit at 34 with ~6 characters of headroom. Asserted by
    /// `VoiceComposerTests.testTheMissingSpeechModelRemedyFitsTheComposersTwoLines`.
    private static func recognitionNeverAnsweredText(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Không nghe được gì. macOS có thể cần mô hình giọng nói: Cài đặt Hệ thống → Bàn phím → Chính tả."
            : "No words came back. macOS may need its speech model: System Settings → Keyboard → Dictation."
    }

    // MARK: - The controls

    /// ✕. Bilingual because it is chrome, and following `ApprovalTier.label(_:)`.
    ///
    /// "Discard", not "Cancel": cancel reads as *leave voice mode*, which is what the
    /// waveform toggle does. This one throws away a sentence and keeps listening.
    ///
    /// The circles are unlabelled on screen now (founder, 22 Aug: "small circles,
    /// bottom-right — not labelled buttons"), so this is the tooltip and the
    /// accessibility label rather than a caption. It is still the only thing that tells
    /// a screen reader ✕ from the waveform, so it is still load-bearing.
    static func discardLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Loại bỏ" : "Discard"
    }

    /// ✓.
    static func sendLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Gửi" : "Send"
    }

    /// **Shown only while the caption reads `Connecting…`** (founder, 22 Aug). ✕ and ✓
    /// are both meaningless before the mic is up — nothing has been heard, so ✓ is
    /// disabled and ✕ has nothing to discard — and the one thing she may want is out.
    static func cancelLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Huỷ" : "Cancel"
    }

    /// Leaving voice mode. The waveform button is the toggle, which is what lets the
    /// composer carry ONE ✕ instead of the takeover's two — the takeover needed labels
    /// under both buttons purely to tell "close voice mode" from "discard this
    /// sentence", and that ambiguity is gone rather than solved.
    static func closeLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Tắt chế độ giọng nói" : "Leave voice mode"
    }

    /// The controls the turn row offers. `close` is not one of them — the waveform
    /// toggle is always there, in the row's other corner.
    enum Control: Equatable {
        /// Leave, while there is nothing else worth doing.
        case cancel
        /// ✕ — throw this sentence away and keep listening.
        case discard
        /// ✓ — take the turn. Offered but disabled while `canTakeTurn` is false.
        case send
    }

    /// **Which controls a state offers** — founder, 22 Aug: "`Cancel` appears only
    /// during `Connecting…`".
    ///
    /// Extracted for the same reason `line(state:partial:failure:_:)` was: this was an
    /// `if session.state == .idle` inside a private `@ViewBuilder` on the composer,
    /// which nothing could reach, and it is a pure state→controls mapping rather than
    /// anything about layout. Its failure is not cosmetic in either direction — `Cancel`
    /// in `.listening` puts a second exit next to ✕/✓ and steals the width they sit in,
    /// and ✕/✓ in `.idle` offers a founder two controls that can do nothing: nothing
    /// has been heard yet, so ✓ is disabled and ✕ has nothing to discard.
    static func controls(for state: VoiceState) -> [Control] {
        state == .idle ? [.cancel] : [.discard, .send]
    }

    /// The tooltip and accessibility label for one control.
    ///
    /// A single entry point so the composer cannot label ✕ with `closeLabel` — the two
    /// read almost the same and the takeover needed captions purely to tell them
    /// apart. Bilingual, like everything else here.
    static func label(for control: Control, _ lang: AppLanguage) -> String {
        switch control {
        case .cancel:  return cancelLabel(lang)
        case .discard: return discardLabel(lang)
        case .send:    return sendLabel(lang)
        }
    }
}

/// The bar waveform along the bottom of the expanded composer (founder, 22 Aug:
/// `··▂▅█▆▃▂··▃▆█▅▂··`, bottom-centre).
///
/// **Pure, and driven by the level alone — no timer and no history.** The previous
/// surface's only periodic work was a 4Hz silence watcher, and deleting it is what spec
/// §2 decision 4 bought; a decorative animation timer would put a `Task` loop back into
/// a voice surface, which is the thing `SpeechFakesTests.testSilenceAloneNeverTakesTheTurn`
/// exists to argue with. `onLevel` already fires ~10 times a second, so the bars move
/// because the level moves.
enum VoiceWaveform {

    /// Odd, so there is a true centre bar to be tallest.
    static let barCount = 17
    /// Visible at silence: the founder must be able to see the mic is open with nothing
    /// being said. The `··` in her sketch.
    static let minBar: CGFloat = 2
    static let maxBar: CGFloat = 18

    /// Bar heights for `level`, tallest in the middle.
    ///
    /// The envelope is a fixed cosine window rather than random: a waveform that
    /// jitters independently of the level is a lie about what the microphone hears, and
    /// it is also unassertable.
    static func barHeights(level: Float, count: Int = barCount) -> [CGFloat] {
        guard count > 0 else { return [] }
        let clamped = CGFloat(min(max(level, 0), 1))
        guard count > 1 else { return [minBar + (maxBar - minBar) * clamped] }
        let mid = CGFloat(count - 1) / 2
        return (0..<count).map { i in
            // 1 at the centre, 0 at both ends.
            let envelope = cos((CGFloat(i) - mid) / mid * .pi / 2)
            return minBar + (maxBar - minBar) * clamped * envelope
        }
    }
}
