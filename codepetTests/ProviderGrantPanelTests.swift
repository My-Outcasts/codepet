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
}
