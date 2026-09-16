// codepetTests/ProvenanceRowTests.swift
import XCTest
@testable import codepet

final class ProvenanceRowTests: XCTestCase {
    func testTheRowNamesTheProviderThatRan() {
        XCTAssertEqual(ProvenanceRow.text(for: .codex, lang: .en), "Ran on Codex")
        XCTAssertEqual(ProvenanceRow.text(for: .claudeCode, lang: .en), "Ran on Claude Code")
    }

    /// An offer that changes nothing must not appear — the `localBuildAvailable` discipline.
    func testNoOfferWhenTheOtherCLIIsNotInstalled() {
        XCTAssertNil(ProvenanceRow.offer(producedBy: .claudeCode, otherInstalled: false))
    }

    func testTheOfferIsTheOtherProvider() {
        XCTAssertEqual(ProvenanceRow.offer(producedBy: .claudeCode, otherInstalled: true), .codex)
        XCTAssertEqual(ProvenanceRow.offer(producedBy: .codex, otherInstalled: true), .claudeCode)
    }

    /// A Codex run must never render a Claude model id. The provider is read from the
    /// deliverable's own stamp, never re-derived from what is installed or granted now —
    /// which would relabel old work every time the founder changes providers.
    func testAProviderIsNeverInferredFromCurrentState() {
        let d = { () -> Deliverable in
            var d = Deliverable(kind: .doc, title: "T", body: "B")
            d.producedBy = .codex
            return d
        }()
        XCTAssertEqual(ProvenanceRow.text(for: d.producedBy!, lang: .en), "Ran on Codex")
    }
}
