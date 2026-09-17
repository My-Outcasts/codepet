// codepetTests/ProviderAuthorisationTests.swift
import XCTest
@testable import codepet

/// **The grant is per PROVIDER, and it is never inherited.**
///
/// Until now there was one grant per company: "Codepet may spend my Claude plan." A second
/// CLI (`codex`, on the founder's ChatGPT plan) makes that one switch wrong, because the two
/// switches buy from two different accounts. Permission to spend one is not permission to
/// spend the other, and the founder who granted Claude Code before this change was never
/// asked about Codex — so she must be ASKED, not migrated.
///
/// The type carried its old Claude-specific name when this file was written, and was renamed
/// to `ProviderAuthorisation` in a follow-up task kept separate from this consent change —
/// doing both at once would have hidden a consent change inside a rename, so this file
/// carried the eventual name before the type did.
final class ProviderAuthorisationTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "provider-auth-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Reads and writes the REAL key function against a scratch suite, so a collapsed key
    /// shows up here rather than being papered over by a fake that keys on the provider
    /// anyway. This is what makes the mutation in step 4 of the task actually bite.
    private func authorisation() -> ProviderAuthorisation {
        ProviderAuthorisation(
            isAuthorised: { [defaults] provider, companyId in
                defaults!.bool(forKey: ProviderAuthorisation.key(provider, companyId))
            },
            setAuthorised: { [defaults] provider, companyId, on in
                defaults!.set(on, forKey: ProviderAuthorisation.key(provider, companyId))
            }
        )
    }

    // MARK: - The load-bearing one

    /// **Consent is not transitive.** Permission to spend a Claude plan is not permission to
    /// spend a ChatGPT plan. A founder who granted Claude before this change must be ASKED
    /// about Codex, never migrated into consent she did not give — that would spend money on
    /// an account she never put on the table.
    func testAClaudeGrantDoesNotAuthoriseCodex() {
        let auth = authorisation()
        auth.setAuthorised(.claudeCode, "c1", true)
        XCTAssertTrue(auth.isAuthorised(.claudeCode, "c1"))
        XCTAssertFalse(auth.isAuthorised(.codex, "c1"), "a Claude grant leaked into Codex")
    }

    /// The mirror image: granting Codex must not hand over the Claude plan either. Same
    /// failure, opposite direction — a collapsed key fails both.
    func testACodexGrantDoesNotAuthoriseClaude() {
        let auth = authorisation()
        auth.setAuthorised(.codex, "c1", true)
        XCTAssertTrue(auth.isAuthorised(.codex, "c1"))
        XCTAssertFalse(auth.isAuthorised(.claudeCode, "c1"), "a Codex grant leaked into Claude Code")
    }

    /// Withdrawing one grant leaves the other standing. A shared key would revoke both.
    func testWithdrawingOneProviderLeavesTheOther() {
        let auth = authorisation()
        auth.setAuthorised(.claudeCode, "c1", true)
        auth.setAuthorised(.codex, "c1", true)
        auth.setAuthorised(.codex, "c1", false)
        XCTAssertTrue(auth.isAuthorised(.claudeCode, "c1"), "revoking Codex withdrew the Claude grant")
        XCTAssertFalse(auth.isAuthorised(.codex, "c1"))
    }

    /// The founder turning the Settings toggle OFF must actually withdraw the Claude
    /// grant, not merely leave a sibling provider's grant standing (that is the test
    /// above). Without this, Codepet keeps spending her Claude plan after she said stop.
    func testClaudeGrantCanBeWithdrawn() {
        let auth = authorisation()
        auth.setAuthorised(.claudeCode, "c1", true)
        auth.setAuthorised(.claudeCode, "c1", false)
        XCTAssertFalse(auth.isAuthorised(.claudeCode, "c1"), "withdrawing the Claude grant did not stick")
    }

    // MARK: - The stored key must not move

    /// **The existing key must not move**, or every founder who already granted Claude Code
    /// silently loses the grant she gave and is asked again for something she agreed to.
    /// This string is on founders' disks right now.
    func testTheClaudeKeyIsUnchanged() {
        XCTAssertEqual(ProviderAuthorisation.key(.claudeCode, "c1"), "cp_claude_authorised_c1")
    }

    func testTheCodexKeyIsItsOwn() {
        XCTAssertEqual(ProviderAuthorisation.key(.codex, "c1"), "cp_codex_authorised_c1")
    }

    /// Every provider's key is distinct, so adding a third CLI cannot quietly re-use a
    /// grant given for a different plan. `CaseIterable` is on `AIProvider` for this.
    func testEveryProviderHasADistinctKey() {
        let keys = AIProvider.allCases.map { ProviderAuthorisation.key($0, "c1") }
        XCTAssertEqual(Set(keys).count, AIProvider.allCases.count, "two providers share one key")
    }

    /// The `cp_` prefix puts every provider's key in the set `AccountDataStore` sweeps per
    /// uid on an account switch; the company suffix keeps it correct if some future switch
    /// path forgets to go through that vault.
    func testEveryProviderKeyIsPrefixedAndScopedToTheCompany() {
        for provider in AIProvider.allCases {
            let key = ProviderAuthorisation.key(provider, "company-a")
            XCTAssertTrue(key.hasPrefix("cp_"), "\(provider.rawValue) must be swept by AccountDataStore")
            XCTAssertTrue(key.contains("company-a"), "\(provider.rawValue) must not be device-global")
        }
    }

    // MARK: - Per company still holds, per provider

    /// Per company AND per provider: one founder's Codex grant is not another's.
    func testGrantsAreStillScopedPerCompany() {
        let auth = authorisation()
        auth.setAuthorised(.codex, "company-a", true)
        XCTAssertFalse(auth.isAuthorised(.codex, "company-b"))
        XCTAssertFalse(auth.isAuthorised(.claudeCode, "company-b"))
    }

    /// The mirror of the test above, with Claude as the granted provider rather than
    /// merely the one left unchecked. One Mac has ONE Claude Code login, so a
    /// device-global grant would mean founder A's consent silently lets founder B
    /// spend the plan A signed in with — and B is the one who would never be asked.
    func testOneFoundersClaudeGrantDoesNotAuthoriseAnother() {
        let auth = authorisation()
        auth.setAuthorised(.claudeCode, "company-a", true)
        XCTAssertFalse(auth.isAuthorised(.claudeCode, "company-b"), "a Claude grant crossed companies")
    }

    /// Absent means NOT granted, for every provider. A founder who has never seen a toggle
    /// has never agreed to anything.
    func testEveryProviderIsOffUntilItIsGiven() {
        let auth = authorisation()
        for provider in AIProvider.allCases {
            XCTAssertFalse(auth.isAuthorised(provider, "company-a"), "\(provider.rawValue) defaulted to granted")
        }
    }

    // MARK: - The prototype live-AI grant is Claude's, and only Claude's

    /// `-CODEPET_LIVE_AI` is the founder typing "spend my Claude plan on the demo" on the
    /// command line. It is a grant for THAT plan. It must not silently extend to a ChatGPT
    /// plan she never named — the same non-transitivity as the stored grant, on the branch
    /// that bypasses storage.
    func testLiveAIAuthorisesClaudeOnlyNotCodex() {
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        defer {
            PrototypeMode.store.removeObject(forKey: PrototypeMode.key)
            PrototypeMode.store.removeObject(forKey: "CODEPET_LIVE_AI")
        }
        let auth = ProviderAuthorisation()
        XCTAssertTrue(auth.isAuthorised(.claudeCode, ContentView.prototypeCompanyId))
        XCTAssertFalse(auth.isAuthorised(.codex, ContentView.prototypeCompanyId),
                       "the live-AI Claude grant leaked into Codex")
    }
}
