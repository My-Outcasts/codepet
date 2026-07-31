// codepetTests/OnboardingLayoutTests.swift
import XCTest
@testable import codepet

/// The onboarding chrome is sized fluidly on the web (`.ob-art { width: 42% }`,
/// `clamp()` on the cold-open headline and inset). The first native port froze those
/// at their ~860pt design-width values, so the flow degraded on a full-screen window.
/// These pin the proportional behaviour AND the clamps at both extremes.
final class OnboardingLayoutTests: XCTestCase {

    // MARK: art panel — web `.ob-art { width: 42% }`

    func testArtPanelIsFortyTwoPercentInTheNormalRange() {
        // 42% exactly, wherever the clamps don't bite.
        XCTAssertEqual(OnboardingLayout.artWidth(container: 860), 361.2, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 1200), 504, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 1400), 588, accuracy: 0.01)
    }

    func testArtPanelKeepsIts42PercentShareOnWideDisplays() {
        // No upper clamp — the web's `.ob-art` is a straight 42% at any width. An
        // earlier 620pt ceiling reduced this to 24% at 2560pt, recreating the collapsed
        // composition the original fixed 360pt width caused.
        XCTAssertEqual(OnboardingLayout.artWidth(container: 1512), 635.04, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 2560), 1075.2, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 5120), 2150.4, accuracy: 0.01)
    }

    func testArtPanelStaysAProportionNotACeiling() {
        // The ratio must hold across the whole realistic range, not just at one width.
        for w in stride(from: CGFloat(800), through: 3200, by: 100) {
            let ratio = OnboardingLayout.artWidth(container: w) / w
            XCTAssertEqual(ratio, 0.42, accuracy: 0.001, "art panel drifted off 42% at \(w)pt")
        }
    }

    /// 600pt is a max-width, not a fixed width — below ~1256pt the column compresses,
    /// exactly as the web's `.ob-body { width: 100%; max-width: 600px }` does.
    /// Threshold: w − 0.42w − 128 ≥ 600  ⇒  w ≥ 1255.17.
    private func formRoom(_ w: CGFloat) -> CGFloat {
        w - OnboardingLayout.artWidth(container: w) - 128
    }

    func testFullMeasureFitsOnceTheWindowIsFullScreenSized() {
        for w in stride(from: CGFloat(1280), through: 3200, by: 100) {
            XCTAssertGreaterThanOrEqual(formRoom(w), 600, "form measure squeezed at \(w)pt")
        }
    }

    func testMeasureCompressesGracefullyBelowThatThresholdRatherThanBreaking() {
        // Still positive and usable everywhere down to the 560pt minimum window —
        // the regression being guarded against is a negative width, not a narrow one.
        for w in stride(from: CGFloat(560), to: 1280, by: 20) {
            XCTAssertGreaterThan(formRoom(w), 0, "form panel collapsed at \(w)pt")
        }
        XCTAssertLessThan(formRoom(1200), 600)   // documents the compression, 568pt
        XCTAssertGreaterThan(formRoom(1260), 600) // just above the threshold
    }

    func testArtPanelClampsOnNarrowWindowsSoTheFormStillFits() {
        // 42% of 560 is 235pt; the lower clamp keeps the art readable at 320.
        XCTAssertEqual(OnboardingLayout.artWidth(container: 560), 320, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 200), 320, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 0), 320, accuracy: 0.01)
    }

    func testArtPanelNeverStarvesTheFormAtTheMinimumWindowWidth() {
        // The regression that motivated raising minWidth 400 → 560: art + the form's
        // 2×64pt padding must leave positive room for the step column.
        let minWindow: CGFloat = 560
        let formPadding: CGFloat = 64 * 2
        let remaining = minWindow - OnboardingLayout.artWidth(container: minWindow) - formPadding
        XCTAssertGreaterThan(remaining, 0, "form panel would be driven to a negative width")
    }

    // MARK: cold open — web `clamp(34px, 4vw, 52px)` / `clamp(40px, 9vw, 150px)`

    func testColdHeadlineScalesWithWidthThenClamps() {
        XCTAssertEqual(OnboardingLayout.coldHeadline(container: 860), 34.4, accuracy: 0.01) // 4vw
        XCTAssertEqual(OnboardingLayout.coldHeadline(container: 1100), 44, accuracy: 0.01)  // 4vw
        XCTAssertEqual(OnboardingLayout.coldHeadline(container: 1512), 52, accuracy: 0.01)  // upper clamp
        XCTAssertEqual(OnboardingLayout.coldHeadline(container: 2560), 52, accuracy: 0.01)  // upper clamp
        XCTAssertEqual(OnboardingLayout.coldHeadline(container: 600), 34, accuracy: 0.01)   // lower clamp
    }

    func testColdLeadingScalesWithWidthThenClamps() {
        XCTAssertEqual(OnboardingLayout.coldLeading(container: 860), 77.4, accuracy: 0.01)  // 9vw
        XCTAssertEqual(OnboardingLayout.coldLeading(container: 1512), 136.08, accuracy: 0.01) // 9vw
        XCTAssertEqual(OnboardingLayout.coldLeading(container: 2560), 150, accuracy: 0.01) // upper clamp
        XCTAssertEqual(OnboardingLayout.coldLeading(container: 300), 40, accuracy: 0.01)   // lower clamp
    }

    func testHelpersAreMonotonicSoTheLayoutNeverJumpsBackwards() {
        var lastArt: CGFloat = 0, lastHead: CGFloat = 0, lastLead: CGFloat = 0
        for w in stride(from: CGFloat(200), through: 3000, by: 50) {
            let art = OnboardingLayout.artWidth(container: w)
            let head = OnboardingLayout.coldHeadline(container: w)
            let lead = OnboardingLayout.coldLeading(container: w)
            XCTAssertGreaterThanOrEqual(art, lastArt, "art width regressed at \(w)")
            XCTAssertGreaterThanOrEqual(head, lastHead, "headline regressed at \(w)")
            XCTAssertGreaterThanOrEqual(lead, lastLead, "leading regressed at \(w)")
            lastArt = art; lastHead = head; lastLead = lead
        }
    }
}
