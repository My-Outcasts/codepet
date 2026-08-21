// codepetTests/VoiceOverlayLayoutTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// Measures the overlay offscreen. The founder confirms how it LOOKS; these
/// assertions cover the two things a screenshot cannot answer from here: that it
/// spreads to the surface it is given, and that the transcript line does not resize
/// the surface as words arrive.
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
/// 2. `proposedSize` is no better for a filled dimension: a deliberately
///    non-filling overlay proposed 900×700 still measured 900×700. **Vertical fill
///    is not measurable with `ImageRenderer`** and is left to the founder's eye;
///    horizontal fill is, against an unconstrained height, and is asserted below.
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

    /// **The partial transcript must not resize the surface.** It grows word by word
    /// as she talks, and a surface that reflows on every word moves the ✕ under her
    /// cursor mid-sentence.
    ///
    /// Height is unproposed on purpose: handed 700 with a filling overlay both
    /// renders answer 700 whatever the transcript does, which is the vacuous version
    /// of this test. Unconstrained, the height is the content's own — measured 389pt
    /// for one line and 406pt for two, so a transcript without its fixed-height slot
    /// shows up as a 17pt difference here.
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

    // MARK: - Founder-visible copy
    //
    // Not pixel measurements, and here rather than in `VoiceReplyDriverTests`
    // because that file is the speaking pipeline's suite. Both strings below are
    // overlay chrome, and both fail in a way no layout number can see.

    /// **Spec §3 is a privacy disclosure, not a nicety.** In English recognition is
    /// on-device and nothing leaves the Mac; in Vietnamese the founder's speech goes
    /// to Apple's servers, because no on-device asset exists for `vi-VN`. Flip the
    /// ternary and the VI founder is told the opposite of the truth about where her
    /// voice goes, with every layout assertion above still green.
    func testThePrivacyLineTellsEachLanguageTheTruth() {
        let vi = VoiceModeOverlay.privacyLine(.vi)
        let en = VoiceModeOverlay.privacyLine(.en)
        XCTAssertEqual(vi, "Giọng nói của bạn được gửi tới Apple để nhận dạng.")
        XCTAssertNotEqual(vi, en, "both languages got the same disclosure")
        XCTAssertTrue(en.contains("Mac"), "the EN line must say the audio stays here: \(en)")
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
