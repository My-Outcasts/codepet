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
    /// A deliverable's own stamp is what reaches the row — the label is built from the
    /// value carried on the `Deliverable`, not from a provider this type went and looked up.
    ///
    /// **This does NOT yet prove "never inferred from current state."** `ProvenanceRow` has no
    /// access to installed-or-selected providers, so there is nothing here to infer FROM; any
    /// mutation that reddens this also reddens `testTheRowNamesTheProviderThatRan`. The real
    /// guard belongs where the card is wired to `deliverable.producedBy`, and it is specified
    /// in Task 6 of the provider-choice-ui plan. Named honestly so it is not mistaken for a
    /// guard that already exists — a review caught the original name claiming exactly that.
    func testTheLabelComesFromTheDeliverablesOwnStamp() {
        var d = Deliverable(kind: .doc, title: "T", body: "B")
        d.producedBy = .codex
        XCTAssertEqual(ProvenanceRow.text(for: d.producedBy!, lang: .en), "Ran on Codex")
    }
}
