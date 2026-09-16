// codepetTests/ProviderConsentTests.swift
import XCTest
@testable import codepet

/// An in-memory `ProviderAuthorisation` — never real `UserDefaults`. Four test files once
/// wrote mock flags into the founder's real preferences; this exists so none ever can again.
final class FakeAuthStore {
    private var grants: Set<String> = []

    private func key(_ provider: AIProvider, _ companyId: String) -> String {
        "\(provider.rawValue)|\(companyId)"
    }

    func grant(_ provider: AIProvider, _ companyId: String) {
        grants.insert(key(provider, companyId))
    }

    func isAuthorised(_ provider: AIProvider, _ companyId: String) -> Bool {
        grants.contains(key(provider, companyId))
    }

    var authorisation: ProviderAuthorisation {
        ProviderAuthorisation(
            isAuthorised: { [weak self] provider, companyId in
                self?.isAuthorised(provider, companyId) ?? false
            },
            setAuthorised: { [weak self] provider, companyId, on in
                guard let self else { return }
                if on { self.grant(provider, companyId) }
                else { self.grants.remove(self.key(provider, companyId)) }
            }
        )
    }
}

@MainActor
final class ProviderConsentTests: XCTestCase {

    /// A consent prompt that runs anyway is worse than no prompt.
    func testDecliningDoesNotRunAndDoesNotGrant() {
        let store = FakeAuthStore()
        var ran = false
        let flow = ProviderConsentFlow(authorisation: store.authorisation)
        flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
        XCTAssertTrue(flow.isAsking, "an ungranted provider must ask first")
        flow.decline()
        XCTAssertFalse(ran)
        XCTAssertFalse(store.isAuthorised(.codex, "c1"))
    }

    func testAllowingGrantsThenRuns() {
        let store = FakeAuthStore()
        var ran = false
        let flow = ProviderConsentFlow(authorisation: store.authorisation)
        flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
        flow.allow()
        XCTAssertTrue(store.isAuthorised(.codex, "c1"))
        XCTAssertTrue(ran)
    }

    /// Consent is not transitive. This is the boundary the whole phase rests on.
    func testGrantingCodexDoesNotGrantClaude() {
        let store = FakeAuthStore()
        let flow = ProviderConsentFlow(authorisation: store.authorisation)
        flow.requestReRun(provider: .codex, companyId: "c1", run: {})
        flow.allow()
        XCTAssertFalse(store.isAuthorised(.claudeCode, "c1"))
    }

    /// An already-granted provider must not re-ask — being asked for permission you already
    /// gave reads as the app having lost it.
    func testAnAlreadyGrantedProviderRunsWithoutAsking() {
        let store = FakeAuthStore()
        store.grant(.codex, "c1")
        var ran = false
        let flow = ProviderConsentFlow(authorisation: store.authorisation)
        flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
        XCTAssertFalse(flow.isAsking)
        XCTAssertTrue(ran)
    }

    /// Declining once must not poison a later ask on the SAME provider — a founder who says
    /// "not now" can still say "allow" the next time the card offers it.
    func testDecliningThenAskingAgainCanStillBeAllowed() {
        let store = FakeAuthStore()
        var runs = 0
        let flow = ProviderConsentFlow(authorisation: store.authorisation)
        flow.requestReRun(provider: .codex, companyId: "c1", run: { runs += 1 })
        flow.decline()
        flow.requestReRun(provider: .codex, companyId: "c1", run: { runs += 1 })
        flow.allow()
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(store.isAuthorised(.codex, "c1"))
    }
}
