// codepetTests/VoiceOverlayLayoutTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// Measures the overlay offscreen. The founder confirms how it LOOKS; these
/// assertions cover the three things a screenshot cannot answer from here: that it
/// spreads to the surface it is given, that the transcript line does not resize the
/// surface as words arrive, and that ✕ and ✓ are on the surface at all — which since
/// 21 Aug is the only way a turn is taken.
///
/// **Every number below was checked for vacuity before it was trusted, and the
/// brief's draft of this file failed that check three times over.** Recorded here
/// because the next person to edit these tests will reach for the same three
/// shortcuts.
///
/// 1. It measured `ImageRenderer(content: v.frame(width: 900, height: 700))` and then
///    asserted the result was 900×700. Measured 21 Aug: `Text("hi")` and `Color.red`
///    inside that frame both report exactly 900×700. A fixed frame reports its own
///    arguments, so the assertion was true of any view with content.
/// 2. **CORRECTED.** This note used to read "vertical fill is not measurable with
///    `ImageRenderer`" and cite a non-filling overlay measuring 900×700 anyway. That
///    is wrong, and it is the kind of wrong that spreads: there are six other
///    `ImageRenderer` suites in `codepetTests/`, and a sentence saying the framework
///    cannot measure a filled dimension will suppress a correct test in one of them.
///    `ImageRenderer` reports the **resolved** size on both axes. Re-probed on this
///    branch at a 900×700 proposal, by deleting the code and running the test:
///
///        frame + spacers          -> (900, 700)
///        maxHeight deleted only   -> (900, 700)   <- what the original probe saw
///        both deleted             -> (900, 426)   <- intrinsic, correctly reported
///
///    **426, not the 368 this note carried until 21 Aug.** ✕ and ✓ were added beneath
///    the transcript (spec §2 decision 4), and that row costs exactly 84pt — 62pt of
///    row plus 22pt of `VStack` spacing — which is confirmed by the 496/412 pair
///    below. But 368 + 84 is 452, not 426, so **368 does not reconcile and is not
///    reproducible**, the same unexplained ~25pt drift already noted for 389 -> 412.
///    Every number here was re-measured, not adjusted; do not try to derive one from
///    another across that drift.
///
///    The real limitation is narrower and applies to width just as much: the
///    overlay's vertical fill is implemented **twice** — `.frame(maxHeight:
///    .infinity)` and two `Spacer(minLength: 0)`s, which take all offered height on
///    their own — so a height assertion is a property guard, not a modifier guard,
///    and deleting either mechanism alone still measures 700. That is a real limit on
///    what the test below proves; it is not a limit on the framework.
/// 3. The reflow test's own long string does not wrap. At the transcript's 520pt
///    measure, the brief's 66-character partial is ONE line — so the test compared
///    one line against one line and passed with the fixed-height frame deleted. The
///    string below is 122 characters, which measures as two.
///
/// `ImageRenderer` fires no `.onAppear` and no `.task`, so `preview(state:partial:)`
/// seeds its state directly; a host that armed itself in a lifecycle hook would
/// render the idle overlay and make all of this meaningless. It also draws nothing
/// inside a `ScrollView` — the overlay deliberately has none.
@MainActor
final class VoiceOverlayLayoutTests: XCTestCase {

    /// The founder's partial, at a length that really wraps. 122 characters: two
    /// lines at the transcript's 520pt measure, against one for "why".
    private static let twoLinePartial =
        "why is onboarding losing people at step three and what should I do "
        + "about the pricing page before the beta freeze on Friday"

    /// Renders `v` against a proposal and reports what it took. `nil` is
    /// unconstrained, which is the only way an intrinsic dimension gets measured —
    /// see note 2 above.
    private func size(_ v: some View, w: CGFloat?, h: CGFloat?) -> CGSize {
        let renderer = ImageRenderer(content: v)
        renderer.proposedSize = ProposedViewSize(width: w, height: h)
        return renderer.nsImage?.size ?? .zero
    }

    /// A takeover that does not take over is the feature failing quietly: sized to
    /// its content it would sit in the middle of the pane with the transcript showing
    /// through around it. Measured at an unconstrained height, an intrinsically-sized
    /// overlay reports its own ~289pt instead of the 900 it was offered.
    func testItSpreadsToTheWidthItIsOffered() {
        let s = size(VoiceModeOverlay.preview(state: .listening, partial: ""), w: 900, h: nil)
        XCTAssertEqual(s.width, 900, accuracy: 2,
                       "the overlay took \(s.width)pt of the 900 it was offered")
    }

    /// The other half of the takeover, and it **is** measurable — see note 2. Sized to
    /// its content the overlay would sit in a band across the middle of the pane with
    /// the transcript showing above and below it; intrinsically, with both fill
    /// mechanisms gone, it reports 426pt of the 700 it was offered (measured 21 Aug,
    /// with ✕/✓ on the surface).
    ///
    /// A property guard, deliberately: the fill is doubly implemented, so this catches
    /// "the overlay stopped filling" and does not catch "one of the two mechanisms was
    /// deleted". The second is not a defect on its own.
    func testItFillsTheHeightItIsOffered() {
        let s = size(VoiceModeOverlay.preview(state: .listening, partial: ""), w: 900, h: 700)
        XCTAssertEqual(s.height, 700, accuracy: 2,
                       "the overlay took \(s.height)pt of the 700 it was offered")
    }

    /// **The partial transcript must not resize the surface.** It grows word by word
    /// as she talks, and a surface that reflows on every word moves the ✕ under her
    /// cursor mid-sentence.
    ///
    /// Height is unproposed on purpose: handed 700 with a filling overlay both
    /// renders answer 700 whatever the transcript does, which is the vacuous version
    /// of this test. Unconstrained, the height is the content's own — **496pt for one
    /// line and 496pt for two, measured 21 Aug on this branch.** Delete the
    /// transcript's fixed-height slot and a 17pt gap opens between them: probed at 429
    /// against 446 in a run that had also removed the two `Spacer`s (worth 44pt of
    /// `VStack` spacing at an unconstrained height), so the 17 is the number that
    /// matters here, not the absolutes.
    func testAGrowingTranscriptDoesNotChangeTheSize() {
        let a = size(VoiceModeOverlay.preview(state: .listening, partial: "why"),
                     w: 900, h: nil)
        let b = size(VoiceModeOverlay.preview(state: .listening,
                                              partial: Self.twoLinePartial),
                     w: 900, h: nil)
        XCTAssertEqual(a, b, "the overlay reflowed as she spoke: \(a) then \(b)")
    }

    func testEveryStateRenders() {
        for st in [VoiceState.listening, .thinking, .speaking] {
            let s = size(VoiceModeOverlay.preview(state: st, partial: "test"), w: 900, h: nil)
            XCTAssertGreaterThan(s.height, 100, "\(st) did not lay out")
        }
    }

    /// **✕ and ✓ are actually on the surface**, which after 21 Aug is the only way a
    /// turn is taken or dropped: with no row, voice mode can hear her and can never
    /// send. Nothing else in this file would notice — every other assertion here passed
    /// with `turnControls` deleted from `body`.
    ///
    /// A property guard on the intrinsic height, in the shape note 2 explains: the row
    /// is a fixed 62pt in a 22pt-spaced `VStack`, so it is worth exactly 84pt. Measured
    /// 21 Aug — 496 with the row, **412 with it commented out of `body`**, which is the
    /// RED for this test.
    ///
    /// The number is checked against the two states that offer the row rather than
    /// against a constant alone, so a change that moved 84pt of something *else* onto
    /// the surface still has to be looked at.
    func testTheTurnControlsAreOnTheSurface() {
        for state in [VoiceState.listening, .thinking] {
            let s = size(VoiceModeOverlay.preview(state: state, partial: "why"),
                         w: 900, h: nil)
            XCTAssertEqual(s.height, 496, accuracy: 2,
                           "\(state) measured \(s.height)pt: 412 is this overlay with "
                           + "no ✕/✓ row, and a voice mode that cannot send")
        }
    }

    // MARK: - Founder-visible copy
    //
    // Not pixel measurements, and here rather than in `VoiceReplyDriverTests`
    // because that file is the speaking pipeline's suite. Both strings below are
    // overlay chrome, and both fail in a way no layout number can see.

    /// **Spec §3 is a privacy disclosure, not a nicety** — and `onDevice`, not the
    /// language, is what decides it.
    ///
    /// Three cases, not two. The line used to switch on `lang` alone and tell every
    /// English founder "Recognition runs on this Mac. Nothing you say leaves it.",
    /// while `openRecognition` sets `requiresOnDeviceRecognition` from
    /// `recognizer.supportsOnDeviceRecognition` — `false` on any Mac without the en-US
    /// Assistant asset, where the audio goes to Apple's servers and the overlay said
    /// the opposite of the truth. Delete the `onDevice` branch and the EN pair below
    /// collapses, with every layout assertion above still green.
    func testThePrivacyLineTellsEachLanguageTheTruth() {
        let enLocal = VoiceModeOverlay.privacyLine(.en, onDevice: true)
        let enRemote = VoiceModeOverlay.privacyLine(.en, onDevice: false)
        let viLocal = VoiceModeOverlay.privacyLine(.vi, onDevice: true)
        let viRemote = VoiceModeOverlay.privacyLine(.vi, onDevice: false)

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

    /// **I4: the header said "Listening" over a dead microphone.** Two paths land in
    /// `.idle` with the overlay deliberately still on screen — `run()`'s catch and
    /// `onFailure`'s fatal branch — and both set `failure`, so the transcript is
    /// already reading "The microphone stopped: …". Folded in with `.listening`, as it
    /// was, the founder was told the mic is live and dead in the same frame.
    func testTheHeaderDoesNotClaimToBeListeningAfterAFatalFailure() {
        for lang in [AppLanguage.en, .vi] {
            XCTAssertNotEqual(VoiceModeOverlay.stateCaption(.idle, lang),
                              VoiceModeOverlay.stateCaption(.listening, lang),
                              "\(lang): a stopped overlay still says it is listening")
        }
        XCTAssertNotEqual(VoiceModeOverlay.stateCaption(.idle, .en),
                          VoiceModeOverlay.stateCaption(.idle, .vi),
                          "the header is chrome and must be bilingual")
        // The three live states are unchanged and still distinct from each other.
        let live = [VoiceState.listening, .thinking, .speaking]
            .map { VoiceModeOverlay.stateCaption($0, .en) }
        XCTAssertEqual(Set(live).count, 3, "two live states share a caption: \(live)")
    }

    /// **The two labels under ✕ and ✓, and they are load-bearing.** There are two ✕s
    /// on this surface — the header one closes voice mode, this one discards a sentence
    /// and keeps listening — so the words underneath are the only thing that tells them
    /// apart. Unlabelled or identically labelled, ✕ reads as "quit" and a founder who
    /// wants to retype one misheard word leaves voice mode instead.
    ///
    /// Following `ApprovalTier.label(_:)`: chrome is bilingual, and a `lang == .vi`
    /// branch that returns the same string both ways is the defect this suite has
    /// already caught twice (`privacyLine`, `stateCaption`).
    func testTheTurnButtonsSayWhatTheyDoInBothLanguages() {
        for lang in [AppLanguage.en, .vi] {
            let discard = VoiceModeOverlay.discardLabel(lang)
            let send = VoiceModeOverlay.sendLabel(lang)
            XCTAssertFalse(discard.isEmpty, "\(lang): ✕ is an unlabelled glyph")
            XCTAssertFalse(send.isEmpty, "\(lang): ✓ is an unlabelled glyph")
            XCTAssertNotEqual(discard, send,
                              "\(lang): both buttons carry the same label — one of them "
                              + "spends a credit and the other throws the sentence away")
        }
        XCTAssertNotEqual(VoiceModeOverlay.discardLabel(.en),
                          VoiceModeOverlay.discardLabel(.vi),
                          "✕'s label is not bilingual")
        XCTAssertNotEqual(VoiceModeOverlay.sendLabel(.en),
                          VoiceModeOverlay.sendLabel(.vi),
                          "✓'s label is not bilingual")
        // And ✕ does not read as "leave voice mode", which is what the header ✕ does.
        XCTAssertNotEqual(VoiceModeOverlay.discardLabel(.en),
                          VoiceModeOverlay.stateCaption(.idle, .en))
    }

    /// Spec §7: voice mode is the feature that makes turns cheap to spend without
    /// noticing — ten exchanges is ~2.5 credits in about two minutes — so the count
    /// is on screen. A line that reads 0 after ten turns is the exact failure it
    /// exists to prevent.
    func testTheCreditLineCountsWhatTheTurnsCost() {
        XCTAssertTrue(VoiceModeOverlay.creditLine(turns: 10, .en).contains("2.5"),
                      "ten turns is ~2.5 credits: \(VoiceModeOverlay.creditLine(turns: 10, .en))")
        XCTAssertTrue(VoiceModeOverlay.creditLine(turns: 0, .en).contains("0"))
        XCTAssertNotEqual(VoiceModeOverlay.creditLine(turns: 3, .vi),
                          VoiceModeOverlay.creditLine(turns: 3, .en),
                          "the credit line is chrome and must be bilingual")
    }
}
#endif
