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

    /// A `DeliverableFrame` call site given a deliverable stamped `.codex` passes that stamp
    /// straight through — the contract every one of the eleven call sites follows
    /// (`provenance: deliverable.producedBy`).
    func testACallSiteWithACodexDeliverableRendersTheCodexLine() {
        var d = Deliverable(kind: .doc, title: "T", body: "B")
        d.producedBy = .codex
        XCTAssertEqual(d.producedBy, .codex)
        XCTAssertEqual(ProvenanceRow.text(for: d.producedBy!, lang: .en), "Ran on Codex")
    }

    /// A deliverable nobody stamped renders no row at all — `DeliverableFrame` draws nothing
    /// for a `nil` provenance (see `DeliverableStyle.swift`), never a guess.
    func testACallSiteWithNoProvenanceRendersNoRow() {
        let d = Deliverable(kind: .doc, title: "T", body: "B")
        XCTAssertNil(d.producedBy)
    }

    // MARK: - The real "never inferred" guard (Task 6)

    /// **This is the guard Task 5's version only claimed to be.** That version had nothing to
    /// infer FROM — `ProvenanceRow` takes only a provider and a language. This one stands up
    /// the two facts that could tempt a re-derivation and proves they never reach the label:
    ///
    /// - A genuine `CompanyStore`, hydrated, whose granted/active provider is Claude (Codex is
    ///   NOT authorised at all).
    /// - A genuine `InstalledProviders` cache, refreshed against a fake shell that reports
    ///   ONLY `claude` on disk — Codex is not installed either.
    /// - A `Deliverable` stamped `.codex` — produced, presumably, before the founder switched
    ///   back to Claude, or on a machine that later lost the Codex CLI.
    ///
    /// An implementation that read the "current" provider (granted or installed) instead of
    /// the deliverable's own stamp would relabel this card "Ran on Claude Code" — exactly the
    /// history-rewrite the whole phase exists to rule out. The real call sites pass
    /// `provenance: deliverable.producedBy` verbatim (never `companyStore.something`), so what
    /// reaches `ProvenanceRow.text` is the value asserted below, unmoved by either fact above.
    @MainActor
    func testProvenanceIsReadFromTheStampNeverFromGrantedOrInstalledProvider() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date())
        // The company's active/granted provider is Claude — and ONLY Claude.
        let auth = ProviderAuthorisation(isAuthorised: { provider, _ in provider == .claudeCode },
                                          setAuthorised: { _, _, _ in })
        let store = CompanyStore(loader: { _ in seed }, claudeAuthorisation: auth)
        await store.hydrate(companyId: "c1")

        // InstalledProviders reports only Claude on this Mac — Codex is not installed.
        let shell = FakeShell()
        shell.stub("claude --version", stdout: "2.1.241 (Claude Code)")
        await store.installedProviders.refresh(shell: shell)
        XCTAssertEqual(store.installedProviders.installed, [.claudeCode],
                        "the scenario requires Codex to be genuinely absent, not just unchecked")

        // The deliverable itself is stamped Codex.
        var d = Deliverable(kind: .doc, title: "T", body: "B")
        d.producedBy = .codex

        // What every real call site passes to `DeliverableFrame`:
        let provenance = d.producedBy

        XCTAssertEqual(provenance, .codex,
                       "must still read Codex — active=Claude and installed={Claude} never enter this value")
        XCTAssertEqual(ProvenanceRow.text(for: provenance!, lang: .en), "Ran on Codex")
    }
}
