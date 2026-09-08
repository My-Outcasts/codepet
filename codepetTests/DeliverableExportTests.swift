import XCTest
@testable import codepet

/// `DeliverableExport` is a pure function from a deliverable to file bytes, which is the
/// whole reason it is a type and not view code: a `WKWebView` or an `NSSavePanel` cannot be
/// asserted on, and these can.
final class DeliverableExportTests: XCTestCase {

    private func deliverable(
        _ kind: DeliverableKind,
        title: String = "Untitled",
        body: String = "body text",
        payload: DeliverablePayload? = nil
    ) -> Deliverable {
        Deliverable(kind: kind, title: title, body: body, payload: payload)
    }

    /// Some payload fixtures are DECODED from JSON rather than constructed.
    ///
    /// `SitePayload`, `CalendarItem` and `CalendarWeek` each declare their own
    /// `init(from decoder:)`, which **suppresses Swift's memberwise initialiser** — so
    /// `SitePayload(title:brand:…)` does not exist and will not compile. Decoding is also
    /// how these arrive in production, which makes it the more honest fixture.
    ///
    /// `ChecklistItem`, `DocSection`, `PlanChange`, `DmMessage`, `SheetInput`,
    /// `SheetPayload`, `SiteContent` and `CalendarPayload` declare no initialiser and DO
    /// have a memberwise init, so those are constructed directly below.
    private func payload(json: String) throws -> DeliverablePayload {
        try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
    }

    // MARK: - slug

    func testSlugStripsPathAndPunctuationThatBreaksAFilename() {
        XCTAssertEqual(DeliverableExport.slug("Q4 Pricing / Model: v2"), "q4-pricing-model-v2")
    }

    func testSlugFoldsVietnameseDiacriticsRatherThanDroppingTheName() {
        XCTAssertEqual(DeliverableExport.slug("Kế hoạch ra mắt"), "ke-hoach-ra-mat")
    }

    func testSlugFallsBackWhenNothingSurvives() {
        XCTAssertEqual(DeliverableExport.slug("///", fallback: "deliverable"), "deliverable")
    }

    // MARK: - markdown kinds

    func testDocExportsOneMarkdownFileNamedFromTheTitle() throws {
        let d = deliverable(.doc, title: "What the app is built on")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "what-the-app-is-built-on.md")
    }

    func testDocMarkdownLeadsWithTheCallBecauseTheViewerDoes() throws {
        let d = deliverable(.doc, title: "Stack", body: "ignored for doc",
                            payload: DeliverablePayload(
                                call: "Run on-device where the entry can stay.",
                                sections: [DocSection(h: "Why", p: "Privacy is the product.")],
                                next: ["Measure recall past 3k entries"]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# Stack\n\nRun on-device where the entry can stay."), text)
        XCTAssertTrue(text.contains("## Why"), text)
        XCTAssertTrue(text.contains("Privacy is the product."), text)
        XCTAssertTrue(text.contains("- Measure recall past 3k entries"), text)
    }

    func testChecklistExportsTickBoxesSoTheStateSurvivesTheFile() throws {
        let d = deliverable(.checklist, title: "Release rhythm",
                            payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Tag the build", done: true),
                                ChecklistItem(t: "Notarise", done: false),
                            ]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.contains("- [x] Tag the build"), text)
        XCTAssertTrue(text.contains("- [ ] Notarise"), text)
    }

    func testPlanExportsGoalStepsChangesVerifyAndRisk() throws {
        let d = deliverable(.plan, title: "Add export",
                            payload: DeliverablePayload(
                                goal: "Let a founder save a deliverable",
                                steps: ["Add the pure core", "Add the panel"],
                                changes: [PlanChange(area: "Library viewers", edit: "one export slot")],
                                verify: ["A saved .md opens in any editor"],
                                risks: "A title with a slash breaks the filename"))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        for expected in ["Let a founder save a deliverable", "1. Add the pure core",
                         "Library viewers", "one export slot",
                         "A saved .md opens in any editor",
                         "A title with a slash breaks the filename"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in:\n\(text)")
        }
    }

    /// A kind with no payload still exports — the body is the deliverable. `.legal` is the
    /// case that matters: its viewer reads only `body`, and the schema's `sections` is dead
    /// for it (see the spec's Layer 2 note).
    func testLegalAndTextFallBackToTheMarkdownBody() throws {
        for kind in [DeliverableKind.legal, .text, .other] {
            let d = deliverable(kind, title: "Deletion promise", body: "One tap. Permanent.")
            let files = DeliverableExport.files(for: d)
            XCTAssertEqual(files.count, 1, "\(kind)")
            XCTAssertEqual(files[0].name, "deletion-promise.md", "\(kind)")
            let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
            XCTAssertTrue(text.contains("One tap. Permanent."), "\(kind): \(text)")
        }
    }

    func testEveryKindProducesAtLeastOneFile() {
        for kind in DeliverableKind.allCases {
            let d = deliverable(kind, title: "Anything", body: "some body")
            XCTAssertFalse(DeliverableExport.files(for: d).isEmpty,
                           "\(kind) exported nothing — a founder would see a dead button")
        }
    }
}
