// codepetTests/VoiceComposerTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// The in-composer voice surface — spec §2 decision 5, which reversed the takeover on
/// 22 Aug. Replaces `VoiceOverlayLayoutTests`; what was ported and what was dropped is
/// recorded on each test, because the two surfaces have opposite layout contracts and a
/// number carried across without re-measuring would be worse than no number.
///
/// **The takeover's height-fill assertion is inverted rather than ported.** It pinned
/// `.frame(maxHeight: .infinity)` on a surface whose whole job was to cover the pane.
/// This composer must do the opposite — the chat stays visible, which is the point of
/// the reversal — so "it fills the height it is offered" is now the defect, not the
/// guard. See `testItExpandsWithoutTakingOverThePane`.
///
/// **And one of its assertions could not be made to work at all**, which is recorded on
/// `testTheComposersShapeIsPinned` rather than quietly dropped.
///
/// **Two figures from the deleted file (368 and 389) were marked irreproducible there
/// and are not carried forward.** Every number below was measured on this branch, by
/// deleting the code it protects and running the test.
///
/// `ImageRenderer` fires no `.onAppear` and no `.task`, so `preview(state:partial:…)`
/// seeds its state directly; a host that armed itself in a lifecycle hook would render a
/// connecting composer and make all of this meaningless. It also draws nothing inside a
/// `ScrollView` — this surface deliberately has none, which is one reason it does not
/// reuse `ComposerField`.
///
/// **No test here calls `speak()`, starts an audio engine, or constructs an
/// `SFSpeechRecognizer`.** `InertSpeechListening`/`InertSpeakingVoice` do nothing at
/// all; the behaviour they would otherwise stand in for is asserted through the two
/// protocols in `SpeechFakesTests`.
@MainActor
final class VoiceComposerTests: XCTestCase {

    /// The founder's partial, at a length that really wraps. 122 characters: two lines
    /// in the transcript slot, against one for "why".
    private static let twoLinePartial =
        "why is onboarding losing people at step three and what should I do "
        + "about the pricing page before the beta freeze on Friday"

    /// Renders `v` against a proposal and reports what it took.
    ///
    /// **Constrain one axis and measure the free one.** A fixed
    /// `.frame(width:height:)` reports its own arguments — `Text("hi")` and `Color.red`
    /// inside one both measure exactly the frame — so asserting a rendered size equals
    /// the frame is vacuous. `nil` is unconstrained, which is the only way an intrinsic
    /// dimension gets measured.
    private func size(_ v: some View, w: CGFloat?, h: CGFloat?) -> CGSize {
        let renderer = ImageRenderer(content: v)
        renderer.proposedSize = ProposedViewSize(width: w, height: h)
        return renderer.nsImage?.size ?? .zero
    }

    /// The composer's own width, so the numbers below are read at the width the pane
    /// actually gives it rather than at a round number.
    private static let paneWidth: CGFloat = 520

    // MARK: - Layout

    /// **PORTED** from `testItSpreadsToTheWidthItIsOffered`, and it is still true of
    /// this surface for a different reason: the composer is sized by the reading column
    /// (`readingColumn(_:)`), so a box that shrank to its content would sit narrow in
    /// the middle of a column the transcript above it fills — visibly not the same
    /// object as the composer it replaced. Intrinsically, unconstrained, it reports
    /// 168pt — the status line's own measure.
    ///
    /// **A property guard, not a modifier guard, and measured to be one.** The width
    /// fill is implemented twice over: by the two `maxWidth: .infinity` frames, and
    /// independently by the `Spacer` in `bottomRow`, which takes all offered width on
    /// its own. Verified 22 Aug — with BOTH `maxWidth` frames deleted this still
    /// measured 520. So it catches "the composer stopped spreading" and does not catch
    /// "one of the two mechanisms was deleted"; the second is not a defect on its own.
    func testItSpreadsToTheWidthItIsOffered() {
        let s = size(VoiceComposer.preview(state: .listening, partial: "why"),
                     w: Self.paneWidth, h: nil)
        XCTAssertEqual(s.width, Self.paneWidth, accuracy: 2,
                       "the composer took \(s.width)pt of the \(Self.paneWidth) it was offered")
    }

    /// **The reversal, as a measurement — spec §2 decision 5.**
    ///
    /// This is the takeover's `testItFillsTheHeightItIsOffered` **inverted**, and the
    /// inversion is the whole change: that surface existed to cover the pane, and this
    /// one exists so the conversation stays visible. Offered 700pt of height it must
    /// take its own ~122 and leave the rest to the chat. Put `.frame(maxHeight:
    /// .infinity)` back on `body` — the one line that would quietly turn the composer
    /// back into a takeover — and this reports 700 and goes red.
    ///
    /// The lower bound is the other half: it has to have GROWN, or "voice lives in the
    /// composer" is just the composer with its field swapped out. Derived from
    /// `ComposerMetrics.paneMinTextHeight`, the typing area an ordinary composer
    /// reserves, so it stays a comparison against the thing it expanded from rather than
    /// a second copy of 122.
    func testItExpandsWithoutTakingOverThePane() {
        let offered = size(VoiceComposer.preview(state: .listening, partial: "why"),
                           w: Self.paneWidth, h: 700)
        XCTAssertLessThan(offered.height, 200,
                          "the composer took \(offered.height)pt of the 700 it was offered "
                          + "— that is the takeover again, and the chat is behind it")

        let intrinsic = size(VoiceComposer.preview(state: .listening, partial: "why"),
                             w: Self.paneWidth, h: nil)
        XCTAssertGreaterThan(intrinsic.height,
                             ComposerMetrics.paneMinTextHeight + VoiceComposer.transcriptHeight,
                             "the composer did not grow: \(intrinsic.height)pt")
    }

    /// **PORTED** from `testAGrowingTranscriptDoesNotChangeTheSize`, unchanged in
    /// intent and more load-bearing here than it was on the takeover: ✕ and ✓ are now
    /// small circles at the bottom-right of this box, so a box that reflows as she talks
    /// moves them out from under her pointer mid-sentence.
    ///
    /// Measured 22 Aug: with `transcriptSlot`'s fixed-height slot deleted, one line
    /// reports **99pt against two lines' 116pt** — the 17pt gap this assertion closes.
    func testAGrowingTranscriptDoesNotChangeTheSize() {
        let a = size(VoiceComposer.preview(state: .listening, partial: "why"),
                     w: Self.paneWidth, h: nil)
        let b = size(VoiceComposer.preview(state: .listening, partial: Self.twoLinePartial),
                     w: Self.paneWidth, h: nil)
        XCTAssertEqual(a, b, "the composer reflowed as she spoke: \(a) then \(b)")
    }

    /// **PARTIALLY PORTED** from `testTheTurnControlsAreOnTheSurface`, and the part
    /// that did not survive is recorded here because the next person will reach for it.
    ///
    /// The takeover's version worked by isolation: its ✕/✓ row was the only thing of
    /// its height in a `VStack`, so deleting it took exactly 84pt off the surface. **That
    /// does not transfer.** Here the circles share a `ZStack` row with `waveformToggle`,
    /// which is the same `controlDiameter` tall — so deleting `controls` from `bottomRow`
    /// changes the rendered height by **nothing at all**. Verified: with `controls`
    /// commented out, this suite went **fully green**. A height assertion for "the
    /// circles are on the surface" is therefore vacuous, in exactly the shape the deleted
    /// file's own note 1 warned about, and it is not written.
    ///
    /// What replaces it is one pinned figure for the whole composer — a property guard,
    /// deliberately. It goes red when the transcript slot, the control row's height, the
    /// status line or the padding changes, and it does NOT isolate which. The circles'
    /// *behaviour* is covered where it can be: `VoiceTurnFlow.canTakeTurn`/`takeTurn`/
    /// `abandonTurn` in `SpeechFakesTests`, and their labels in
    /// `testTheTurnCirclesSayWhatTheyDoInBothLanguages`. Their mere presence in `body` is
    /// the one thing nothing here can see, and saying so is better than a green test that
    /// implies otherwise.
    ///
    /// Measured 22 Aug at 520pt: **122pt**, in every state and at both surfaces (the
    /// 380pt dock reports the same height). **RED at 99pt** two independent ways: with
    /// `statusLine` deleted from the `VStack`, and with the transcript's fixed slot
    /// deleted. The two land on the same number by coincidence — the status line is worth
    /// 23pt with its spacing, and collapsing the 40pt slot to one line costs the same 23
    /// — so do not read either figure as derived from the other.
    func testTheComposersShapeIsPinned() {
        for state in [VoiceState.idle, .listening, .thinking, .speaking] {
            let s = size(VoiceComposer.preview(state: state, partial: "why"),
                         w: Self.paneWidth, h: nil)
            XCTAssertEqual(s.height, 122, accuracy: 2,
                           "\(state) measured \(s.height)pt — 99 is this composer with no "
                           + "status line, which is where the privacy disclosure and the "
                           + "credit count live")
        }
    }

    /// **PORTED** from `testEveryStateRenders`, with `.idle` added — the takeover had no
    /// `.idle` surface worth rendering, and this one does: `Connecting…` with `Cancel`
    /// under it is what the founder sees for the ~200ms of engine spin-up, and it is
    /// also what a fatal `start()` failure leaves on screen.
    func testEveryStateRenders() {
        for st in [VoiceState.idle, .listening, .thinking, .speaking] {
            let s = size(VoiceComposer.preview(state: st, partial: "test"),
                         w: Self.paneWidth, h: nil)
            XCTAssertGreaterThan(s.height, 60, "\(st) did not lay out")
        }
    }

    // MARK: - The one text slot

    /// **PORTED** from `testTheHeaderDoesNotClaimToBeListeningAfterAFatalFailure`, and
    /// this is where the port had to change shape.
    ///
    /// The takeover had two rows — a caption AND a transcript — so it could say
    /// "Listening" above "The microphone stopped: …", and the fix was giving `.idle` its
    /// own word. The composer has ONE line, so the fix is precedence: the failure takes
    /// the slot. Delete the `if let failure` branch in `VoiceChrome.line` and a founder
    /// whose microphone just died reads `Connecting…` over it, with every layout
    /// assertion above still green.
    func testAFailureTakesTheTextSlotFromEveryCaption() {
        let dead = VoiceAudioError.engineFailed("no speech detected")
        for state in [VoiceState.idle, .listening, .thinking, .speaking] {
            for lang in [AppLanguage.en, .vi] {
                let line = VoiceChrome.line(state: state, partial: "add pricing",
                                            failure: dead, lang)
                XCTAssertEqual(line.kind, .failure,
                               "\(state)/\(lang): the composer showed \(line.text) over a "
                               + "microphone that had stopped")
                XCTAssertNotEqual(line.text, VoiceChrome.caption(state, lang))
                XCTAssertNotEqual(line.text, "add pricing")
            }
        }
        // And the captions are still distinct from each other, so no two states read
        // the same — `.idle` included, which is the one the takeover got wrong.
        let captions = [VoiceState.idle, .listening, .thinking, .speaking]
            .map { VoiceChrome.caption($0, .en) }
        XCTAssertEqual(Set(captions).count, 4, "two states share a caption: \(captions)")
        for state in [VoiceState.idle, .listening, .thinking, .speaking] {
            XCTAssertNotEqual(VoiceChrome.caption(state, .en),
                              VoiceChrome.caption(state, .vi),
                              "\(state)'s caption is chrome and must be bilingual")
        }
    }

    /// **Spec §2: the placeholder carries the state, and the transcript replaces it
    /// while it is her turn.** The sequence is `Connecting…` → transcript → `Listening…`
    /// → `Answering…`, in one slot.
    ///
    /// The `.thinking`/`.speaking` half is the guard that matters. `VoiceTurnFlow
    /// .replyEnded` deliberately does NOT clear the pending transcript — a question
    /// spoken while the pet was thinking must survive with ✓ lit — so those words are
    /// still in `partial` while the pet answers. Show them as the live transcript and
    /// the founder cannot tell a sentence that was taken from one that is still being
    /// heard. Delete the `state == .listening` condition and the two assertions below
    /// go red.
    func testTheSlotShowsHerWordsOnlyWhileItIsHerTurn() {
        let listening = VoiceChrome.line(state: .listening, partial: "add pricing",
                                         failure: nil, .en)
        XCTAssertEqual(listening.kind, .transcript)
        XCTAssertEqual(listening.text, "add pricing")

        for state in [VoiceState.thinking, .speaking] {
            let line = VoiceChrome.line(state: state, partial: "add pricing",
                                        failure: nil, .en)
            XCTAssertEqual(line.kind, .caption,
                           "\(state) showed her queued words as if they were still "
                           + "being heard: \(line.text)")
            XCTAssertEqual(line.text, VoiceChrome.caption(state, .en))
        }

        // Nothing heard yet is the caption, not an empty line — and whitespace counts
        // as nothing, which is what a recognizer reporting " " gives.
        for text in ["", " ", "\n  \t"] {
            XCTAssertEqual(VoiceChrome.line(state: .listening, partial: text,
                                            failure: nil, .en).kind, .caption)
        }
    }

    // MARK: - Founder-visible copy

    /// **PORTED verbatim** from `testThePrivacyLineTellsEachLanguageTheTruth`. Spec §3
    /// is a privacy disclosure, not a nicety — and `onDevice`, not the language, is what
    /// decides it.
    ///
    /// Three cases, not two. The line used to switch on `lang` alone and tell every
    /// English founder "Recognition runs on this Mac. Nothing you say leaves it.", while
    /// `openRecognition` sets `requiresOnDeviceRecognition` from
    /// `recognizer.supportsOnDeviceRecognition` — `false` on any Mac without the en-US
    /// Assistant asset, where the audio goes to Apple's servers and the composer said
    /// the opposite of the truth. Delete the `onDevice` branch and the EN pair below
    /// collapses, with every layout assertion above still green.
    func testThePrivacyLineTellsEachLanguageTheTruth() {
        let enLocal = VoiceChrome.privacyLine(.en, onDevice: true)
        let enRemote = VoiceChrome.privacyLine(.en, onDevice: false)
        let viLocal = VoiceChrome.privacyLine(.vi, onDevice: true)
        let viRemote = VoiceChrome.privacyLine(.vi, onDevice: false)

        XCTAssertTrue(enLocal.contains("Mac"), "on-device EN must say it stays here: \(enLocal)")
        XCTAssertTrue(enLocal.lowercased().contains("nothing you say leaves"),
                      "on-device EN must be unambiguous: \(enLocal)")
        XCTAssertTrue(enRemote.contains("Apple"),
                      "off-device EN must name where the audio goes: \(enRemote)")
        XCTAssertNotEqual(enLocal, enRemote,
                          "the EN line ignored whether recognition is actually on-device")

        XCTAssertEqual(viRemote, "Giọng nói của bạn được gửi tới Apple để nhận dạng.")
        XCTAssertNotEqual(viLocal, viRemote,
                          "the VI line hard-codes 'sent to Apple' and would lie the day "
                          + "Apple ships a vi-VN asset")
        XCTAssertNotEqual(viLocal, enLocal, "both languages got the same disclosure")
        XCTAssertNotEqual(viRemote, enRemote, "both languages got the same disclosure")
    }

    /// **The compact line has to carry BOTH requirements** — spec §2: "Both fit as one
    /// compact line inside the expanded composer — `2 credits · on-device`".
    ///
    /// This is the port of `testTheCreditLineCountsWhatTheTurnsCost` (§7: voice makes
    /// turns cheap to spend without noticing — ten exchanges is ~2.5 credits in about
    /// two minutes, so the count is on screen) fused with §3's disclosure, because the
    /// two are now one string and a compression that dropped either would be invisible
    /// on screen.
    ///
    /// **The off-device assertion is the one that would rot.** Compressing "Your speech
    /// is sent to Apple for recognition" to a two-word tag is the tempting version of
    /// this line, and it is the footnote §3 forbids; this is what goes red if someone
    /// tries it.
    func testTheCompactLineCarriesBothTheCreditsAndTheDisclosure() {
        let ten = VoiceChrome.statusLine(turns: 10, onDevice: true, .en)
        XCTAssertTrue(ten.contains("2.5"), "ten turns is ~2.5 credits: \(ten)")
        XCTAssertTrue(ten.contains("credits"), "the credit count lost its unit: \(ten)")
        XCTAssertTrue(ten.contains("on-device"), "the disclosure fell off: \(ten)")
        // Not "2.50"/"0.00" — %g, so a whole number reads as one.
        XCTAssertTrue(VoiceChrome.statusLine(turns: 0, onDevice: true, .en).contains("0"))
        XCTAssertFalse(VoiceChrome.statusLine(turns: 4, onDevice: true, .en).contains("1.00"))
        XCTAssertTrue(VoiceChrome.statusLine(turns: 4, onDevice: true, .en).contains("1 "))

        let remote = VoiceChrome.statusLine(turns: 10, onDevice: false, .en)
        XCTAssertTrue(remote.contains("Apple"),
                      "the compact line dropped the one disclosure §3 exists for: \(remote)")
        XCTAssertTrue(remote.contains("2.5"), "the credits fell off the off-device line: \(remote)")
        XCTAssertNotEqual(remote, ten,
                          "the status line ignored whether recognition is on-device")

        XCTAssertNotEqual(VoiceChrome.statusLine(turns: 3, onDevice: true, .vi),
                          VoiceChrome.statusLine(turns: 3, onDevice: true, .en),
                          "the status line is chrome and must be bilingual")
        XCTAssertNotEqual(VoiceChrome.statusLine(turns: 3, onDevice: false, .vi),
                          VoiceChrome.statusLine(turns: 3, onDevice: false, .en),
                          "the status line is chrome and must be bilingual")
    }

    /// **PORTED** from `testTheTurnButtonsSayWhatTheyDoInBothLanguages`, with the reason
    /// changed rather than dropped.
    ///
    /// The circles are unlabelled on screen now (founder, 22 Aug: "not labelled
    /// buttons"), so these are the tooltips and the accessibility labels — which makes
    /// them the *only* thing that tells ✕ from ✓ to a screen reader, and the only thing
    /// that says ✕ discards a sentence rather than leaving voice mode. The takeover
    /// needed captions because it carried two ✕s; this surface gives the exit its own
    /// glyph, so `closeLabel` is what `discardLabel` must not read like.
    ///
    /// Following `ApprovalTier.label(_:)`: chrome is bilingual, and a `lang == .vi`
    /// branch that returns the same string both ways is the defect this feature has
    /// already caught twice (`privacyLine`, the old `stateCaption`).
    func testTheTurnCirclesSayWhatTheyDoInBothLanguages() {
        for lang in [AppLanguage.en, .vi] {
            let discard = VoiceChrome.discardLabel(lang)
            let send = VoiceChrome.sendLabel(lang)
            let close = VoiceChrome.closeLabel(lang)
            let cancel = VoiceChrome.cancelLabel(lang)
            for (name, label) in [("✕", discard), ("✓", send),
                                  ("the waveform toggle", close), ("Cancel", cancel)] {
                XCTAssertFalse(label.isEmpty, "\(lang): \(name) is an unlabelled glyph")
            }
            XCTAssertNotEqual(discard, send,
                              "\(lang): both circles carry the same label — one of them "
                              + "spends a credit and the other throws the sentence away")
            XCTAssertNotEqual(discard, close,
                              "\(lang): ✕ reads as 'leave voice mode', so a founder who "
                              + "wants to retype one misheard word leaves instead")
        }
        for (name, label) in [("✕", VoiceChrome.discardLabel),
                              ("✓", VoiceChrome.sendLabel),
                              ("the waveform toggle", VoiceChrome.closeLabel),
                              ("Cancel", VoiceChrome.cancelLabel)] {
            XCTAssertNotEqual(label(.en), label(.vi), "\(name)'s label is not bilingual")
        }
    }

    // MARK: - The waveform

    /// **The bars have to answer to the microphone.** They are the only thing on this
    /// surface that says it is live, and a waveform that moves on its own — an
    /// animation phase, a random jitter, the "empirical" constant `VoiceLevel` was
    /// extracted for — looks exactly like one that is listening. Silence must be
    /// visibly silence.
    ///
    /// Delete `clamped` from the envelope (`minBar + (maxBar - minBar) * envelope`) and
    /// the first two assertions go red: every bar reports its full height at level 0.
    func testTheBarsTrackTheLevelAndNothingElse() {
        let silent = VoiceWaveform.barHeights(level: 0)
        XCTAssertEqual(silent.count, VoiceWaveform.barCount)
        XCTAssertEqual(Set(silent.map { ($0 * 100).rounded() }), [VoiceWaveform.minBar * 100],
                       "the bars deflected with nothing being said: \(silent)")

        let loud = VoiceWaveform.barHeights(level: 1)
        let mid = loud.count / 2
        XCTAssertEqual(loud[mid], VoiceWaveform.maxBar, accuracy: 0.01,
                       "the centre bar never reaches full deflection")
        XCTAssertEqual(loud.first!, VoiceWaveform.minBar, accuracy: 0.01)
        XCTAssertEqual(loud.last!, VoiceWaveform.minBar, accuracy: 0.01,
                       "the envelope is not symmetric — the bars read as scrolling")

        // Monotonic in the level, so louder is never shorter.
        let half = VoiceWaveform.barHeights(level: 0.5)
        for i in 0..<VoiceWaveform.barCount {
            XCTAssertLessThanOrEqual(silent[i], half[i] + 0.001, "bar \(i)")
            XCTAssertLessThanOrEqual(half[i], loud[i] + 0.001, "bar \(i)")
        }

        // Out-of-range levels are clamped rather than drawn — `VoiceLevel` already
        // clamps, and two clamps that disagree is one bug.
        XCTAssertEqual(VoiceWaveform.barHeights(level: 5)[mid], VoiceWaveform.maxBar,
                       accuracy: 0.01)
        XCTAssertEqual(VoiceWaveform.barHeights(level: -3), silent)
    }
}
#endif
