// codepetTests/ProviderGrantPanelTests.swift
import XCTest
@testable import codepet

/// Settings is the durable home for consent: it must let a founder REVIEW and REVOKE a
/// grant per provider, independently of the other. `FakeAuthStore` (see
/// `ProviderConsentTests.swift`) and `FakeShell` (see `CLIEnvironmentTests.swift`) are
/// reused rather than re-invented — two fakes for the same two seams is how a leak like
/// issue #117 happens again.
final class ProviderGrantPanelTests: XCTestCase {

    /// Two independent switches, not one. Revoking Codex must leave Claude running.
    func testRevokingOneGrantLeavesTheOther() {
        let store = FakeAuthStore()
        store.grant(.claudeCode, "c1")
        store.grant(.codex, "c1")
        store.authorisation.setAuthorised(.codex, "c1", false)
        XCTAssertFalse(store.isAuthorised(.codex, "c1"))
        XCTAssertTrue(store.isAuthorised(.claudeCode, "c1"))
    }

    /// The panel probes each provider separately, so an uninstalled Codex reports missing
    /// while Claude reports present — the fact the grant rows render from.
    func testThePanelHoldsAStatusPerProvider() async {
        let shell = FakeShell()
        shell.stub("claude --version", stdout: "2.1.241 (Claude Code)")
        shell.stub("claude auth status", stdout: #"{"loggedIn": true}"#)
        let claude = await CLIEnvironment.probe(provider: .claudeCode, shell: shell, authorised: true)
        let codex  = await CLIEnvironment.probe(provider: .codex, shell: shell, authorised: false)
        XCTAssertEqual(claude.blocker, nil)
        XCTAssertEqual(codex.blocker, .notInstalled)
    }

    // MARK: - `ProviderGrantRow.rowsToShow` — which providers get a row at all

    private func signedIn(_ provider: AIProvider) -> CLIStatus {
        CLIStatus(provider: provider, install: .present(version: "1.0"),
                  auth: .loggedIn(.init(email: nil, authMethod: nil, apiProvider: nil,
                                        subscriptionType: nil, orgName: nil)),
                  authorised: false)
    }

    private func signedOut(_ provider: AIProvider) -> CLIStatus {
        CLIStatus(provider: provider, install: .present(version: "1.0"), auth: .loggedOut, authorised: false)
    }

    private func notInstalled(_ provider: AIProvider) -> CLIStatus {
        CLIStatus(provider: provider, install: .missing, auth: .unknown, authorised: false)
    }

    /// Signed in, never granted: nothing to revoke yet, but there is a login worth
    /// asking about — a row renders so the founder can be asked.
    func testSignedInNotGrantedGetsARow() {
        let rows = ProviderGrantRow.rowsToShow(status: [.codex: signedIn(.codex)], granted: [])
        XCTAssertTrue(rows.contains(.codex))
    }

    /// FINDING 1's regression test. A founder granted Codex, then signed out of it (no
    /// uninstall needed) — `CLIStatus.account` is nil, exactly as it is when nothing was
    /// ever granted. The old `signedInProviders` filter (`status[$0]?.account != nil`)
    /// cannot tell these apart and drops the row either way, making a stored grant
    /// invisible and unrevokable. This must go RED against that old rule and GREEN
    /// against `ProviderGrantRow.rowsToShow` — see the task report for both observations.
    func testSignedOutButGrantedStillGetsARow() {
        let rows = ProviderGrantRow.rowsToShow(status: [.codex: signedOut(.codex)], granted: [.codex])
        XCTAssertTrue(rows.contains(.codex),
                      "a stored grant must stay reachable to revoke, even while its CLI is signed out")
    }

    /// Signed out AND never granted: there is truly nothing to review or revoke, so no
    /// row — this is what keeps the fix from turning into "show every provider always".
    func testSignedOutAndNotGrantedGetsNoRow() {
        let rows = ProviderGrantRow.rowsToShow(status: [.codex: signedOut(.codex)], granted: [])
        XCTAssertFalse(rows.contains(.codex))
    }

    /// Not installed, never granted: same as above, from the other blocker.
    func testNeitherInstalledNorGrantedGetsNoRow() {
        let rows = ProviderGrantRow.rowsToShow(status: [.codex: notInstalled(.codex)], granted: [])
        XCTAssertFalse(rows.contains(.codex))
    }

    /// Consent is never transitive, restated at the row-selection layer: granting Codex
    /// alone must not put Claude's row on screen for the wrong reason, and the reverse.
    /// (The Toggle itself writing only its own provider is already covered by
    /// `testRevokingOneGrantLeavesTheOther` above, against `ProviderAuthorisation`
    /// directly — a mutation making `rowsToShow` ignore which provider is which, e.g.
    /// checking `granted.isEmpty` instead of `granted.contains($0)`, reddens here.)
    func testGrantingOneProviderDoesNotRowTheOther() {
        let rows = ProviderGrantRow.rowsToShow(status: [:], granted: [.codex])
        XCTAssertTrue(rows.contains(.codex))
        XCTAssertFalse(rows.contains(.claudeCode))
    }
}
