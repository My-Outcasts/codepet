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

    // MARK: - Finding 3 (review, Task 6 fix pass): a guard that can actually fail

    /// **Replaces three tests that could never go red** —
    /// `testProvenanceIsReadFromTheStampNeverFromGrantedOrInstalledProvider`,
    /// `testACallSiteWithACodexDeliverableRendersTheCodexLine`, and
    /// `testACallSiteWithNoProvenanceRendersNoRow`, all deleted from this file.
    ///
    /// The first stood up a real hydrated `CompanyStore` granted Claude-only and a real
    /// `InstalledProviders` refreshed against a `FakeShell` reporting only Claude — then
    /// never routed anything through either. Its assertion was `d.producedBy == .codex`, a
    /// bare local-field read taken three lines after `d.producedBy = .codex` was set. No
    /// mutation to any of the eleven `DeliverableFrame(` call sites, to `ProvenanceRowView`,
    /// or to any viewer struct could ever turn it red — the store and the
    /// installed-providers cache were inert set-dressing. The other two were the same shape:
    /// assert a property immediately after setting it, which no code change can falsify.
    ///
    /// This asserts over the SOURCE instead — the only way to check "never a current-state
    /// lookup" against a call site that, by construction, has no state to look up in a unit
    /// test. Same shape as the `ONE_SHOT_OPS` registry key-list pin
    /// (`functions/src/__tests__/oneShotSidecar.test.ts`): a literal expectation a rename, or
    /// a re-derivation, has to fail here rather than slip past onto a founder's screen.

    /// The three files that hold all eleven `DeliverableFrame(` call sites, read from disk.
    /// `#filePath` is THIS file's own location at compile time, so it resolves in any
    /// checkout, CI included — same technique as `EngineeringReachabilityTests`.
    private static func source(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // codepetTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("codepet/Views/Library")
            .appendingPathComponent(fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Every `provenance:` argument across the three files, in source order — the value each
    /// `DeliverableFrame(` call actually passes, trimmed of the label and trailing comma.
    private static func provenanceArguments() -> [String] {
        let files = ["MessageDraftCard.swift", "LibraryView.swift", "DeliverableViewers.swift"]
        var out: [String] = []
        for file in files {
            for line in source(file).split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("provenance:") else { continue }
                var value = trimmed.dropFirst("provenance:".count)
                    .trimmingCharacters(in: .whitespaces)
                if value.hasSuffix(",") { value.removeLast() }
                out.append(value)
            }
        }
        return out
    }

    func testTheSourcesWereFoundAtAll() {
        // Without this, both assertions below pass vacuously on an empty array — exactly
        // when the suite stops being able to check anything at all.
        XCTAssertFalse(Self.source("DeliverableViewers.swift").isEmpty,
                       "DeliverableViewers.swift was not found — the path derived from #filePath is wrong")
    }

    /// **The count is pinned too**, so a new call site that forgets `provenance:` entirely
    /// (or reads it from somewhere `DeliverableFrame` doesn't surface as a plain
    /// `provenance:` argument) fails this test rather than silently joining the eleven that
    /// already behave.
    func testElevenCallSitesPassAProvenanceArgument() {
        XCTAssertEqual(Self.provenanceArguments().count, 11)
    }

    /// **The actual guard.** Every `provenance:` argument is the deliverable's OWN stamp —
    /// `deliverable.producedBy`, or (the chat draft card, which may have nothing approved yet)
    /// `export?.producedBy` — never anything re-derived from what is currently granted or
    /// installed. A call site that starts passing `companyStore.something` or
    /// `installedProviders.something` fails here immediately, which is the actual regression
    /// this suite exists to catch.
    func testEveryCallSitePassesTheDeliverablesOwnStamp() {
        let allowed: Set<String> = ["deliverable.producedBy", "export?.producedBy"]
        for value in Self.provenanceArguments() {
            XCTAssertTrue(allowed.contains(value),
                         "provenance: \(value) is not the deliverable's own stamp")
        }
    }
}
