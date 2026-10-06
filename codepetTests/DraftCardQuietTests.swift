// codepetTests/DraftCardQuietTests.swift
import XCTest
@testable import codepet

/// The chat draft card, 6 Oct design pass (mock approved).
final class DraftCardQuietTests: XCTestCase {
    /// One summary, not two: when the structured preview (the recommendation and its reasons) is
    /// on the card, the clamped prose preview of the body is not drawn above it. That pair was the
    /// "three text tiers" on the build-8 FAQ card: a grey body excerpt, a white recommendation and
    /// grey reasons. With no structured preview, the prose stays the card's only summary.
    func testTheProsePreviewStepsAsideForTheStructuredOne() {
        XCTAssertFalse(DraftCardCopy.showsProsePreview(hasStructuredPreview: true))
        XCTAssertTrue(DraftCardCopy.showsProsePreview(hasStructuredPreview: false))
    }

    /// The folded run log reads as how the draft was made, not as a status.
    func testTheStepsLinkSaysHowItWasMade() {
        XCTAssertEqual(DraftCardCopy.howMadeLink(who: "Sage", steps: 6, lang: .en), "How Sage made it · 6 steps")
        XCTAssertEqual(DraftCardCopy.howMadeLink(who: "Sage", steps: 1, lang: .en), "How Sage made it · 1 step")
        XCTAssertEqual(DraftCardCopy.howMadeLink(who: "Sage", steps: 6, lang: .vi), "Sage đã làm thế nào · 6 bước")
    }

    func testReviseIsOneMenu() {
        XCTAssertEqual(DraftCardCopy.reviseMenu(.en), "Revise")
        XCTAssertEqual(ReviseKind.allCases.count, 3, "the menu still offers all three")
    }
}
