import XCTest
@testable import codepet

/// CP-002 C: checklist owner/due, doc `rules_out` + section `source`, post platform/limit, email
/// subject/to. Every field is optional, so each legacy shape must decode, export and hand a Team
/// Build exactly what it did before.
final class AdditiveFieldsTests: XCTestCase {

    private func decode(_ kind: String, _ payload: String, body: String = "BODY") throws -> Deliverable {
        let json = #"{"id":"d","kind":""# + kind + #"","title":"T","body":""# + body + #"","payload":"# + payload + "}"
        return try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
    }
    private func exported(_ d: Deliverable) throws -> String {
        try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
    }

    // MARK: - checklist

    func testChecklistOwnerAndDueDecodeAndRenderOnOneLine() throws {
        let d = try decode("checklist", #"{"items":[{"t":"Buy domain","done":true,"owner":"you","due":"today"},{"t":"Ship","done":false}]}"#)
        let items = try XCTUnwrap(d.payload?.items)
        XCTAssertEqual(items[0].markdownLine, "- [x] Buy domain — you · today")
        XCTAssertEqual(items[1].markdownLine, "- [ ] Ship", "a legacy step reads exactly as before")
        XCTAssertTrue(try exported(d).contains("- [x] Buy domain — you · today\n- [ ] Ship\n"))
        XCTAssertTrue(DeliverableMarkdown.render(d, dept: "Ops", instruction: "x").contains("- [x] Buy domain — you · today"))
    }

    func testOnlyOneOfOwnerOrDue() {
        XCTAssertEqual(ChecklistItem(t: "a", done: false, due: "day 3").meta, "day 3")
        XCTAssertEqual(ChecklistItem(t: "a", done: false, owner: "Design").meta, "Design")
        XCTAssertNil(ChecklistItem(t: "a", done: false, owner: "  ", due: "").meta)
    }

    // MARK: - doc

    func testDocRulesOutAndSourceExport() throws {
        let d = try decode("doc", #"{"call":"Charge $8","sections":[{"h":"Why","p":"Because.","source":"the pricing interviews"}],"next":[],"rules_out":["A free tier"]}"#)
        XCTAssertEqual(d.payload?.rulesOutItems, ["A free tier"])
        let text = try exported(d)
        XCTAssertTrue(text.contains("## Why\n\nBecause.\n\n_Source: the pricing interviews_\n"), text)
        XCTAssertTrue(text.contains("## Rules out\n\n- A free tier\n"), text)
        let md = DeliverableMarkdown.render(d, dept: "Fin", instruction: "x")
        XCTAssertTrue(md.contains("_Source: the pricing interviews_") && md.contains("## Rules out"), md)
    }

    func testALegacyDocExportsWithoutEitherHeading() throws {
        let text = try exported(try decode("doc", #"{"call":"Charge $8","sections":[{"h":"Why","p":"Because."}],"next":[]}"#))
        XCTAssertFalse(text.contains("Rules out"), text)
        XCTAssertFalse(text.contains("Source:"), text)
    }

    // MARK: - post

    func testPostLengthUnderAndOver() {
        XCTAssertEqual(PostLength(body: "hello", limit: 280)?.label(.en), "5 / 280 characters")
        let over = PostLength(body: String(repeating: "a", count: 300), limit: 280)
        XCTAssertEqual(over?.over, 20)
        XCTAssertEqual(over?.label(.en), "300 / 280 characters — 20 over")
        XCTAssertNil(PostLength(body: "x", limit: nil), "no limit, no count — a legacy post shows nothing new")
        XCTAssertNil(PostLength(body: "x", limit: 0))
    }

    func testPostExportStaysTheBodyAloneAndTeamBuildNamesThePlatform() throws {
        let d = try decode("post", #"{"platform":"X","limit":280}"#, body: "We shipped.")
        XCTAssertEqual(try exported(d), "We shipped.\n", "the export is what gets pasted")
        let md = DeliverableMarkdown.render(d, dept: "Mkt", instruction: "x")
        XCTAssertTrue(md.contains("**Platform:** X (limit 280 characters)\n\nWe shipped."), md)
        XCTAssertFalse(md.contains("## Notes"), "the body is carried once, not again under Notes")
    }

    // MARK: - email

    func testEmailExportLeadsWithSubjectAndTo() throws {
        let d = try decode("email", #"{"subject":"Your beta invite","to":"the two who asked to pay"}"#, body: "Hi [name]")
        XCTAssertEqual(try exported(d), "Subject: Your beta invite\nTo: the two who asked to pay\n\nHi [name]\n")
        let md = DeliverableMarkdown.render(d, dept: "Sales", instruction: "x")
        XCTAssertTrue(md.contains("**Subject:** Your beta invite\n**To:** the two who asked to pay\n\nHi [name]"), md)
        XCTAssertFalse(md.contains("## Notes"), md)
    }

    func testALegacyEmailExportsItsBodyAlone() throws {
        let d = Deliverable(kind: .email, title: "T", body: "Hi there")
        XCTAssertEqual(try exported(d), "Hi there\n")
        XCTAssertEqual(DeliverableMarkdown.render(d, dept: "Sales", instruction: "x"),
                       "# T\n\n**Department:** Sales\n**Asked for:** x\n\nHi there")
    }

    /// The flat payload keys must round-trip under the server's spelling, `rules_out` included.
    func testTheNewKeysRoundTripUnderTheWireNames() throws {
        let p = DeliverablePayload(rulesOut: ["a"], platform: "X", limit: 280, subject: "s", to: "t")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["rules_out", "platform", "limit", "subject", "to"])
        XCTAssertEqual(try JSONDecoder().decode(DeliverablePayload.self, from: JSONEncoder().encode(p)), p)
    }
}
