import XCTest
@testable import codepet

/// CP-002 A: a `.legal` deliverable renders, exports and hands a Team Build its clauses,
/// numbered — and a legal draft filed before that, which has no payload, keeps rendering its body.
final class LegalClausesTests: XCTestCase {

    private let clauses = [DocSection(h: "Definitions", p: "“Service” means Murror."),
                           DocSection(h: "Deletion", p: "One tap. Permanent.")]

    private func legal(_ sections: [DocSection]?, body: String = "BODY-ONLY TEXT") -> Deliverable {
        Deliverable(kind: .legal, title: "Privacy policy", body: body,
                    payload: sections.map { DeliverablePayload(sections: $0) })
    }

    // MARK: - which deliverables have clauses

    func testTheWireShapeDecodesIntoClauses() throws {
        let json = #"{"id":"d1","kind":"legal","title":"NDA","body":"md","payload":{"sections":[{"h":"Term","p":"Two years."}]}}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(LegalClauses.of(d), [DocSection(h: "Term", p: "Two years.")])
    }

    func testALegacyLegalDraftHasNoClauses() {
        XCTAssertNil(LegalClauses.of(legal(nil)))
        XCTAssertNil(LegalClauses.of(legal([])))
        XCTAssertNil(LegalClauses.of(legal([DocSection(h: "", p: "orphan")])))
    }

    /// A doc has `sections` too, and they are reasoning blocks, not clauses — numbering them
    /// would turn "Why it's right" into "1. Why it's right".
    func testADocIsNeverNumbered() {
        let d = Deliverable(kind: .doc, title: "D", body: "b",
                            payload: DeliverablePayload(call: "c", sections: clauses))
        XCTAssertNil(LegalClauses.of(d))
    }

    func testEmptyClausesAreDroppedBeforeNumbering() {
        let d = legal([clauses[0], DocSection(h: "", p: "orphan"), clauses[1]])
        XCTAssertEqual(LegalClauses.of(d)?.count, 2)
        XCTAssertTrue(LegalClauses.markdown(LegalClauses.of(d)!).contains("## 2. Deletion"),
                      "a dropped clause must not leave a gap in the numbering")
    }

    // MARK: - export (Layer 4)

    func testExportNumbersTheClauses() throws {
        let files = DeliverableExport.files(for: legal(clauses))
        XCTAssertEqual(files.map(\.name), ["privacy-policy.md"])
        let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# Privacy policy\n"), text)
        XCTAssertTrue(text.contains("## 1. Definitions\n\n“Service” means Murror."), text)
        XCTAssertTrue(text.contains("## 2. Deletion\n\nOne tap. Permanent."), text)
        XCTAssertFalse(text.contains("BODY-ONLY TEXT"), "the clauses are the document; the body is its fallback")
    }

    func testALegacyLegalDraftStillExportsItsBody() throws {
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: legal(nil))[0].data, encoding: .utf8))
        XCTAssertEqual(text, "# Privacy policy\n\nBODY-ONLY TEXT\n")
    }

    // MARK: - Team Build docs/

    func testTeamBuildMarkdownCarriesTheNumberedClauses() {
        let md = DeliverableMarkdown.render(legal(clauses), dept: "Legal", instruction: "Draft the privacy policy")
        XCTAssertTrue(md.contains("## 1. Definitions"), md)
        XCTAssertTrue(md.contains("## 2. Deletion"), md)
    }

    func testTeamBuildMarkdownForALegacyLegalDraftIsItsBody() {
        let md = DeliverableMarkdown.render(legal(nil), dept: "Legal", instruction: "x")
        XCTAssertTrue(md.hasSuffix("BODY-ONLY TEXT"), md)
        XCTAssertFalse(md.contains("## 1."), md)
    }

    // MARK: - copy

    func testCopyTextIsWhatTheViewerShows() {
        XCTAssertEqual(LegalClauses.plainText(clauses),
                       "1. Definitions\n“Service” means Murror.\n\n2. Deletion\nOne tap. Permanent.")
    }
}
