// codepetTests/OnboardingProviderCopyTests.swift
import XCTest
@testable import codepet

/// The gate told the founder she would "choose whether to use it later". She does not choose:
/// without a grant nothing in the product runs. What is true is that nothing is spent until
/// she is asked, which is a promise worth making and a different sentence.
final class OnboardingProviderCopyTests: XCTestCase {

    func testTheGateNoLongerOffersAChoiceThatDoesNotExist() {
        for lang in [AppLanguage.en, .vi] {
            let copy = OnboardingProviderStep.gateSubtitle(lang: lang).lowercased()
            XCTAssertFalse(copy.contains("choose whether"))
            XCTAssertFalse(copy.contains("chọn xem"))
        }
    }

    /// It must still say installation is all that is wanted here — the screen has no toggle
    /// and asks for no grant, and saying otherwise would make the install look insufficient.
    func testItStillAsksOnlyForAnInstall() {
        let copy = OnboardingProviderStep.gateSubtitle(lang: .en)
        XCTAssertTrue(copy.contains("Install either one"))
    }

    /// The promise that replaces the false choice: nothing is spent unasked.
    func testItPromisesToAskBeforeSpending() {
        XCTAssertTrue(OnboardingProviderStep.gateSubtitle(lang: .en)
            .contains("ask before it spends"))
        XCTAssertFalse(OnboardingProviderStep.gateSubtitle(lang: .vi).isEmpty)
    }

    /// Both languages are real copy, not one string used twice.
    func testBothLanguagesAreDistinct() {
        XCTAssertNotEqual(OnboardingProviderStep.gateSubtitle(lang: .en),
                          OnboardingProviderStep.gateSubtitle(lang: .vi))
    }

    // MARK: - CP-012: the gate's own heading and button were English in every language

    /// Found 22 Sep verifying CP-006 side by side: the subtitle was localised but the heading
    /// above it was a literal, so a Vietnamese founder read English over Vietnamese.
    func testTheHeadingIsLocalised() {
        XCTAssertEqual(OnboardingProviderStep.gateHeading(lang: .en), "One more thing before you start")
        XCTAssertEqual(OnboardingProviderStep.gateHeading(lang: .vi), "Còn một bước nữa trước khi bắt đầu")
    }

    /// Same screen, same bug: the install row's copy button was a literal too.
    func testTheCopyCommandButtonIsLocalised() {
        XCTAssertEqual(OnboardingProviderStep.copyCommandLabel(lang: .en), "Copy command")
        XCTAssertEqual(OnboardingProviderStep.copyCommandLabel(lang: .vi), "Sao chép lệnh")
    }
}
