// codepetTests/DemoProjectTests.swift
import XCTest
@testable import codepet

/// Guards on the demo-project selector.
///
/// This is a SECOND prototype-mode preference, and the first one caused issue #117: it was read
/// off `UserDefaults.standard`, the XCTest host IS the app and shares that domain, so a founder
/// clicking the prototype toggle changed what the suite exercised — and the loud failure was the
/// lucky one, because any test that would pass against fixtures and fail against the real client
/// passes for the WRONG REASON while prototype mode is on.
///
/// `testSelectionIsIsolatedFromStandardDefaults` is the test that would have caught that, written
/// here so the second preference cannot repeat it.
final class DemoProjectTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PrototypeMode.store.removeObject(forKey: DemoProject.key)
        PrototypeMode.store.removeObject(forKey: DemoProject.launchKey)
    }

    override func tearDown() {
        PrototypeMode.store.removeObject(forKey: DemoProject.key)
        PrototypeMode.store.removeObject(forKey: DemoProject.launchKey)
        super.tearDown()
    }

    func testDefaultsToCodepet() {
        XCTAssertEqual(DemoProject.current.id, "codepet")
    }

    /// The #117 guard. A selection must not reach the founder's real preferences.
    func testSelectionIsIsolatedFromStandardDefaults() {
        UserDefaults.standard.removeObject(forKey: DemoProject.key)
        DemoProject.select("murror")
        XCTAssertNil(UserDefaults.standard.object(forKey: DemoProject.key),
                     "the selector wrote to the founder's real preferences — see #117")
    }

    func testSelectionRoundTrips() {
        DemoProject.select("murror")
        XCTAssertEqual(DemoProject.current.id, "murror")
    }

    /// A typo in the launch argument shows the default demo, not an empty company.
    func testUnknownIdFallsBackToCodepet() {
        DemoProject.select("nonesuch")
        XCTAssertEqual(DemoProject.current.id, "codepet")
    }

    /// `NSArgumentDomain` outranks every preference file, so a flag cannot be overridden by a
    /// stored value — the demo cannot be left half-selected between the two.
    func testLaunchKeyOutranksThePersistedValue() {
        DemoProject.select("codepet")
        PrototypeMode.store.set("murror", forKey: DemoProject.launchKey)
        XCTAssertEqual(DemoProject.current.id, "murror")
    }

    // MARK: - The extraction is lossless

    /// `.codepet` must still carry what the literals in `MockChat` said, because every
    /// pre-existing suite is written against them.
    func testCodepetBriefIsUnchanged() {
        let brief = DemoProject.codepet.brief
        XCTAssertEqual(brief.founderName, "Mona")
        XCTAssertEqual(brief.projectName, "Codepet")
        XCTAssertEqual(brief.oneLiner, "Your AI cofounder that runs the whole company with you.")
    }

    /// The exact id set `MockChat.roadmap()` returned before the extraction. A count alone would
    /// pass on a swapped task; this fails on a lost, renamed or added one.
    func testCodepetBoardIsTheSameTwelveTasks() {
        XCTAssertEqual(Set(DemoProject.codepet.tasks.map(\.id)), [
            "mock-competitors", "mock-personas", "mock-market",
            "mock-brand", "mock-landing", "mock-pricing",
            "mock-waitlist", "mock-outreach", "mock-faq",
            "mock-deploy", "mock-privacy", "mock-interviews",
        ])
    }

    /// The catch-all is reached by the `?? last` fallback rather than by matching an empty
    /// keyword, so it must be last and must have no keywords of its own.
    func testCodepetCatchAllIsLastAndKeywordless() {
        let last = DemoProject.codepet.deliverables.last
        XCTAssertEqual(last?.kind, "plan")
        XCTAssertEqual(last?.keywords, [])
    }

    /// A title matching nothing still resolves — to the catch-all.
    func testUnmatchedTitleResolvesToTheCatchAll() {
        let d = DemoProject.codepet.deliverable(for: "zzzz nothing matches this")
        XCTAssertEqual(d.kind, "plan")
    }

    /// The chain's order was load-bearing: "landing" resolved to `post` ahead of the catch-all.
    func testCodepetDeliverableOrderIsPreserved() {
        XCTAssertEqual(DemoProject.codepet.deliverable(for: "Write your landing page copy").kind, "post")
        XCTAssertEqual(DemoProject.codepet.deliverable(for: "Draft a simple pricing plan").kind, "doc")
        XCTAssertEqual(DemoProject.codepet.deliverable(for: "Draft a privacy policy").kind, "legal")
        XCTAssertEqual(DemoProject.codepet.deliverable(for: "Set up a waitlist signup").kind, "checklist")
    }

    /// The `{{title}}` token replaced a direct interpolation when the catch-all became a value.
    func testCatchAllStillCarriesTheTaskTitle() {
        let d = DemoProject.codepet.deliverable(for: "Do a thing nothing matches")
        XCTAssertTrue(d.body.contains("{{title}}"))
        let filled = MockChat.fill(d.body, title: "Do a thing nothing matches")
        XCTAssertTrue(filled.contains("Do a thing nothing matches"))
        XCTAssertFalse(filled.contains("{{title}}"))
    }
}
