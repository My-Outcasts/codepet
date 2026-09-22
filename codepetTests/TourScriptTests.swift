// codepetTests/TourScriptTests.swift
import XCTest
@testable import codepet

/// "Show me around" must answer without a model call.
///
/// Chat is `.claudeOnly` (`BlockedOffer.Surface`) and `ChatTransportRouter.transport` blocks
/// on the grant, so a tour that asked the model would return the grant wall on a fresh
/// account — teaching a brand-new founder that the button is broken at the exact moment we
/// are trying to build confidence. So it is a script, like the greeting.
final class TourScriptTests: XCTestCase {

    func testTheTourNamesTheSurfacesAFounderCanReach() {
        let out = TourScript.message(language: .en)
        for surface in ["Roadmap", "Tasks", "Library"] {
            XCTAssertTrue(out.contains(surface), "the tour never mentions \(surface)")
        }
    }

    /// `AppView.from(navDestination:)` resolves five strings. A chip pointing anywhere else
    /// makes `activateNav` return early and renders a button that silently does nothing.
    func testTheChipPointsSomewhereTheRouterCanResolve() {
        let nav = TourScript.chip()
        XCTAssertNotNil(AppView.from(navDestination: nav.destination),
                        "the tour chip's destination is unroutable")
    }

    /// The tour hands off to `OverviewIntroSheet`, which lives on Roadmap and holds
    /// "How to read this map". Pointing elsewhere would duplicate shipped work.
    func testTheChipGoesToRoadmapSoTheExistingBriefingFires() {
        XCTAssertEqual(TourScript.chip().destination, "roadmap")
        XCTAssertNil(TourScript.chip().target, "roadmap takes no target")
    }

    /// `environment` is tooling, not part of understanding what Codepet does for you.
    func testTheTourDoesNotAdvertiseTheEnvironmentTab() {
        XCTAssertFalse(TourScript.message(language: .en).contains("Environment"))
    }

    func testBothLanguagesAreReal() {
        XCTAssertNotEqual(TourScript.message(language: .en), TourScript.message(language: .vi))
        XCTAssertFalse(TourScript.message(language: .vi).isEmpty)
        XCTAssertFalse(TourScript.offerLabel(lang: .vi).isEmpty)
        XCTAssertNotEqual(TourScript.offerLabel(lang: .en), TourScript.offerLabel(lang: .vi))
    }

    /// `CopilotChatView.prose` splits on blank lines, so the tour must be paragraphs rather
    /// than one wall.
    func testTheTourIsParagraphs() {
        XCTAssertTrue(TourScript.message(language: .en).contains("\n\n"))
        XCTAssertTrue(TourScript.message(language: .vi).contains("\n\n"))
    }
}
