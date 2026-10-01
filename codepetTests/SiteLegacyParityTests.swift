import XCTest
@testable import codepet

/// CP-002 E2: a landing page filed before typed blocks must render the EXACT HTML it did. The two
/// golden files in `Fixtures/` were captured from `SiteViewer.buildHTML` on `main` at 53ca2b1,
/// before any of this change existed, and are compared byte for byte — not "looks the same", the
/// same bytes. A page is what the founder approved and may have published.
final class SiteLegacyParityTests: XCTestCase {

    private func golden(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTheDemoLandingPageRendersTheSameBytes() throws {
        let entry = try XCTUnwrap(DemoProject.murror.deliverables.first { $0.kind == "site" })
        let p = try JSONDecoder().decode(DeliverablePayload.self, from: Data(try XCTUnwrap(entry.payloadJSON).utf8))
        XCTAssertEqual(SiteViewer.buildHTML(try XCTUnwrap(p.site)), try golden("site-legacy-murror"))
    }

    func testTheLibraryFixturePageRendersTheSameBytes() throws {
        let site = try XCTUnwrap(LibraryFixtures.all.first { $0.kind == .site }?.payload?.site)
        XCTAssertEqual(SiteViewer.buildHTML(site), try golden("site-legacy-fixture"))
    }

    /// Saved in the new shape and reloaded, an old page still renders the same bytes.
    func testALegacyPageSurvivesMigrationUnchanged() throws {
        let site = try XCTUnwrap(LibraryFixtures.all.first { $0.kind == .site }?.payload?.site)
        let migrated = try JSONDecoder().decode(SitePayload.self, from: JSONEncoder().encode(site))
        XCTAssertEqual(migrated, site)
        XCTAssertEqual(SiteViewer.buildHTML(migrated), try golden("site-legacy-fixture"))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(site)) as? [String: Any]).keys
        XCTAssertTrue(keys.contains("blocks"))
        XCTAssertFalse(keys.contains("steps") || keys.contains("features") || keys.contains("quote"), "the old keys are not written back")
    }
}

/// The three new block types, and the rules every block follows.
final class SiteBlocksTests: XCTestCase {

    private func page(_ blocks: [SiteBlock]) -> SitePayload {
        SitePayload(title: "Murror", brand: "Murror", headline: "AI that brings people", ctaPrimary: "Start free",
                    blocks: blocks, finalTitle: "Start", finalCta: "Go", accent: "#6E8E68")
    }

    func testPricingFaqAndTextRender() {
        let html = SiteViewer.buildHTML(page([
            SiteBlock(type: "pricing", eyebrow: "Pricing", title: "Free to start", tiers: [
                SiteTier(name: "Free", price: "$0", points: ["14 days of history"], cta: "Start free"),
                SiteTier(name: "Practice", price: "$6", period: "/ month", points: ["History forever"], cta: "Start", highlight: true)]),
            SiteBlock(type: "faq", title: "Before you ask", items: [SiteContent(h: "Is this therapy?", p: "No.")]),
            SiteBlock(type: "text", title: "Why", text: "Because it is yours."),
        ]))
        XCTAssertTrue(html.contains("<div class=\"tier hl\"><div class=\"tn\">Practice</div><div class=\"tp\">$6<small> / month</small></div>"), html)
        XCTAssertTrue(html.contains("<div class=\"qa\"><h3>Is this therapy?</h3><p>No.</p></div>"), html)
        XCTAssertTrue(html.contains("<p class=\"prose\">Because it is yours.</p>"), html)
        XCTAssertTrue(html.contains("<a href=\"#pricing\">Pricing</a><a href=\"#faq\">FAQ</a>"), "nav follows block order")
        XCTAssertTrue(html.contains(".tiers{"), "the new types bring their CSS")
    }

    func testBlocksRenderInTheModelsOrder() {
        let html = SiteViewer.buildHTML(page([
            SiteBlock(type: "faq", title: "Q", items: [SiteContent(h: "a", p: "b")]),
            SiteBlock(type: "steps", title: "S", items: [SiteContent(h: "c", p: "d")]),
        ]))
        let faq = html.range(of: "id=\"faq\"")!, how = html.range(of: "id=\"how\"")!
        XCTAssertLessThan(faq.lowerBound, how.lowerBound)
    }

    func testARepeatedTypeGetsItsOwnAnchor() {
        let html = SiteViewer.buildHTML(page([
            SiteBlock(type: "features", title: "A", items: [SiteContent(h: "a", p: "b")]),
            SiteBlock(type: "features", title: "B", items: [SiteContent(h: "c", p: "d")]),
        ]))
        XCTAssertTrue(html.contains("id=\"features\""))
        XCTAssertTrue(html.contains("id=\"features-2\""))
    }

    func testAnUnknownOrEmptyBlockDrawsNothing() {
        let html = SiteViewer.buildHTML(page([SiteBlock(type: "carousel", title: "Nope", items: [SiteContent(h: "a", p: "b")]),
                                              SiteBlock(type: "faq", title: "Empty")]))
        XCTAssertFalse(html.contains("Nope"))
        XCTAssertFalse(html.contains("Empty"))
    }

    /// The model writes text, never markup — every string is escaped on the way into the page.
    func testBlockTextIsEscaped() {
        let html = SiteViewer.buildHTML(page([SiteBlock(type: "text", text: "<script>alert(1)</script>"),
                                              SiteBlock(type: "pricing", tiers: [SiteTier(name: "<b>", price: "$1")])]))
        XCTAssertFalse(html.contains("<script>alert"), html)
        XCTAssertFalse(html.contains("<div class=\"tn\"><b>"), html)
    }

    func testANonSitePayloadGrowsNoSite() throws {
        let plan = #"{"id":"p","kind":"plan","title":"T","body":"b","payload":{"goal":"g","steps":["a","b"],"changes":[{"area":"x","edit":"y"}]}}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(plan.utf8))
        XCTAssertNil(d.payload?.site, "a plan's `steps` must not make it a site")
    }
}
