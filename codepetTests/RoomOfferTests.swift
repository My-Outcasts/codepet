// codepetTests/RoomOfferTests.swift
import XCTest
@testable import codepet

/// Guards on the room's way back into the two-mode shell.
///
/// The defect these exist for: `CopilotChatView` passes
/// `convenesRoom: mode.convenesRoom`, and `ChatMode.convenesRoom` is true only for
/// `.plan` — the mode whose composer pill this shell removed. The Virtual Company,
/// which `CLAUDE.md` calls the headline feature, was therefore unreachable in the
/// pane while still working in the dock. Nothing failed and nothing logged; the
/// feature was simply gone.
final class RoomOfferTests: XCTestCase {

    /// The rule that made it unreachable, pinned so the reason stays visible: only
    /// `.plan` convenes, and `.plan` has no control in the pane.
    func testOnlyPlanModeConvenesWhichIsWhyTheOfferIsNeeded() {
        XCTAssertTrue(ChatMode.plan.convenesRoom)
        XCTAssertFalse(ChatMode.ask.convenesRoom)
        XCTAssertFalse(ChatSurface.twoMode.showsModePill,
                       "if the pill ever returns to the pane, this offer is a second way in")
    }

    /// Convening spends. An empty composer would spend on nothing, so the control is
    /// dead until there is a question to argue.
    func testAnEmptyDraftCannotConvene() {
        XCTAssertFalse(RoomOffer.canConvene(draft: ""))
        XCTAssertFalse(RoomOffer.canConvene(draft: "   \n  "))
        XCTAssertTrue(RoomOffer.canConvene(draft: "Should we ship the paywall before launch?"))
    }

    /// Credits, never dollars — publishing the measured ~$0.20 would leak cost of
    /// goods. The label has to carry the price, because a founder should not have to
    /// tap to find out what something costs.
    func testThePriceIsShownInCreditsAndNeverInDollars() {
        for language in [AppLanguage.en, .vi] {
            let label = RoomOffer.label(language)
            XCTAssertTrue(label.contains("\(RoomOffer.credits)"), label)
            XCTAssertFalse(label.contains("$"), "dollars leak cost of goods: \(label)")
        }
    }

    /// The spec's number: 0.25 × the measured ~40× an ordinary turn.
    func testThePriceIsTheSpecsNumber() {
        XCTAssertEqual(RoomOffer.credits, 10)
    }

    /// Four seats, matching the cap `parseRoutingToolInput` enforces server-side. A
    /// label promising more than the backend will seat is a lie the founder pays for.
    func testTheSeatCountMatchesTheServerSideCap() {
        XCTAssertEqual(RoomOffer.seats, 4)
        for language in [AppLanguage.en, .vi] {
            XCTAssertTrue(RoomOffer.detail(language).contains("\(RoomOffer.seats)"))
        }
    }
}
