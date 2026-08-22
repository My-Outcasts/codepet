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
    /// credits in about two minutes", stated as the per-turn number so the line on
    /// screen and the spec cannot drift.
    static let creditsPerTurn = 0.25

    // MARK: - The compact line, and the one case it cannot stay compact for

    /// **Spec §2's `2 credits · on-device`** — the running credit count (§7) and the
    /// privacy disclosure (§3) on one line, because the composer has room for one line
    /// where the takeover had room for two.
    ///
    /// **It escalates when the audio is leaving the Mac, and that is deliberate.**
    /// On-device is the benign case and a two-word tag is enough for it. Off-device is
    /// the case §3 exists for — her voice is going to Apple's servers — and two grey
    /// words in footnote type would be exactly the footnote §3 forbids ("It has to be
    /// visible, not a footnote"). So that case renders `privacyLine` in full, unchanged,
    /// and the surface paints it as a warning rather than as chrome. Compactness is
    /// what gets given up, in the one case where the spec says legibility outranks it.
    ///
    /// **`onDevice` decides it, not `lang`.** See `privacyLine`: this is a property of
    /// which Assistant assets are installed, and a line that reads the language and
    /// ignores the fact is the `lang == .vi ? why : why` defect in a new place.
    ///
    /// **The turn count is dropped, and that is a real loss.** The retired `creditLine`
    /// read "8 turns · ~2 credits this session", arguing that "the number that
    /// surprises a founder is how many turns two minutes of talking is". The founder's
    /// measured target line is two segments, so the turns are gone; the credits — the
    /// number that is actually spent — are not.
    static func statusLine(turns: Int, onDevice: Bool, _ lang: AppLanguage) -> String {
        "\(creditFragment(turns: turns, lang)) · \(privacyFragment(onDevice: onDevice, lang))"
    }

    /// `~2 credits`. `%g`, not `%.2f`: 2.5 must read "2.5" and 0 must read "0", not
    /// "2.50"/"0.00".
    private static func creditFragment(turns: Int, _ lang: AppLanguage) -> String {
        let amount = String(format: "%g", Double(turns) * creditsPerTurn)
        return lang == .vi ? "~\(amount) tín dụng" : "~\(amount) credits"
    }

    /// The compact tag, or the full disclosure — see `statusLine`.
    private static func privacyFragment(onDevice: Bool, _ lang: AppLanguage) -> String {
        guard onDevice else { return privacyLine(lang, onDevice: false) }
        return lang == .vi ? "chạy trên máy này" : "on-device"
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
        default:
            return failure.localizedDescription
        }
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
