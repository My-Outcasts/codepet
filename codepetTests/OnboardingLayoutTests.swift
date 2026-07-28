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

    func testArtPanelClampsOnWideDisplaysInsteadOfDominating() {
        // 42% of a 2560pt display would be 1075pt; the upper clamp holds it at 620.
        XCTAssertEqual(OnboardingLayout.artWidth(container: 1512), 620, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 2560), 620, accuracy: 0.01)
        XCTAssertEqual(OnboardingLayout.artWidth(container: 5120), 620, accuracy: 0.01)
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
