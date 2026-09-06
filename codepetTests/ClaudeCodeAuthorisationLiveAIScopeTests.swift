// codepetTests/ClaudeCodeAuthorisationLiveAIScopeTests.swift
import XCTest
@testable import codepet

/// Guards the Amendment 4 follow-up: `CODEPET_LIVE_AI` closed the loop end-to-end
/// (`4ef81e5` swapped `MockChat`'s transport for `LocalTransportRouter`) but nothing
/// ever granted `ClaudeCodeAuthorisation` for `"prototype"`, so `transport()` still fell
/// through to `.cloud` — which now 401s, the API key having been deleted 26 Aug. The
/// founder's live-mode flag was inert.
///
/// **The fix is scoped, not a bypass.** `ClaudeCodeAuthorisation`'s DEFAULT `isAuthorised`
/// closure now also answers true when `PrototypeMode.liveAI` is on AND the id being asked
/// about is exactly `ContentView.prototypeCompanyId`. Every other id — including one that
/// has never been granted at all — must resolve exactly as it always has, from the real
/// stored `cp_claude_authorised_<id>` key. These tests exercise the DEFAULT closure
/// itself (the thing that changed), never a custom one, and never call anything that
/// could spawn `claude` or spend a token.
final class ClaudeCodeAuthorisationLiveAIScopeTests: XCTestCase {

    // A real company id, never granted, that will not collide with anything a founder
    // (or another suite) might have set — asserts "no stored grant stays unauthorised".
    private let ungranted = "clc-live-scope-ungranted-\(UUID().uuidString)"
    // A real company id whose grant we set ourselves, to prove `liveAI` never touches a
    // stored grant for a non-prototype id either way.
    private let storedGrant = "clc-live-scope-granted-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        clearLiveAI()
        // Defensive: these are freshly minted UUIDs, so neither key should exist, but
        // clear explicitly rather than trust that.
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(ungranted))
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(storedGrant))
    }

    override func tearDown() {
        clearLiveAI()
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(ungranted))
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(storedGrant))
        super.tearDown()
    }

    private func clearLiveAI() {
        PrototypeMode.store.removeObject(forKey: "CODEPET_LIVE_AI")
    }

    // MARK: - The main guard

    /// **This is the guard.** With `liveAI` on: the prototype id is authorised, an
    /// ungranted real id stays unauthorised, and a real id with its own stored grant
    /// keeps working — proving the exception adds exactly one case and touches nothing
    /// else. Revert the `$0 == ContentView.prototypeCompanyId, PrototypeMode.liveAI`
    /// branch in `ClaudeCodeAuthorisation.isAuthorised` and the first assertion goes red.
    func testLiveAIGrantsOnlyThePrototypeCompanyId() {
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        UserDefaults.standard.set(true, forKey: ClaudeCodeAuthorisation.key(storedGrant))

        let auth = ClaudeCodeAuthorisation()

        XCTAssertTrue(auth.isAuthorised(ContentView.prototypeCompanyId),
                      "CODEPET_LIVE_AI is the founder's consent for the prototype id — it must grant it")
        XCTAssertFalse(auth.isAuthorised(ungranted),
                       "an id with no stored grant must stay unauthorised even while liveAI is on")
        XCTAssertTrue(auth.isAuthorised(storedGrant),
                      "a real company's own stored grant must be unaffected by liveAI")
    }

    /// With `liveAI` off, the prototype id has no grant of its own kind — it falls back
    /// to the stored check exactly like any other id, and nothing was ever stored for it.
    func testWithLiveAIOffThePrototypeIdIsNotAuthorised() {
        XCTAssertFalse(PrototypeMode.liveAI)
        let auth = ClaudeCodeAuthorisation()
        XCTAssertFalse(auth.isAuthorised(ContentView.prototypeCompanyId),
                       "the gate's default must be untouched: no flag, no grant")
    }

    /// A real company id is never affected by `liveAI`, granted or not.
    func testLiveAIOnNeverAuthorisesAnUngrantedRealCompany() {
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        let auth = ClaudeCodeAuthorisation()
        XCTAssertFalse(auth.isAuthorised(ungranted))
    }

    /// A real company's stored grant is exactly as authoritative with `liveAI` off as on.
    func testStoredGrantForARealCompanyIsUnchangedByLiveAIEitherWay() {
        UserDefaults.standard.set(true, forKey: ClaudeCodeAuthorisation.key(storedGrant))
        let auth = ClaudeCodeAuthorisation()

        XCTAssertTrue(auth.isAuthorised(storedGrant), "liveAI off: the real grant still holds")
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        XCTAssertTrue(auth.isAuthorised(storedGrant), "liveAI on: the real grant still holds, unmodified")
    }

    // MARK: - The injected-closure seam survives

    /// A test (or any caller) that supplies its own `isAuthorised` must see ONLY its own
    /// answer — `liveAI` must never leak in underneath a closure that overrode it.
    func testInjectedClosureOverridesTheDefaultEvenWithLiveAIOn() {
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        let auth = ClaudeCodeAuthorisation(
            isAuthorised: { $0 == "only-this-one" },
            setAuthorised: { _, _ in }
        )
        XCTAssertFalse(auth.isAuthorised(ContentView.prototypeCompanyId),
                       "an injected closure must not be bypassed by the default's liveAI branch")
        XCTAssertTrue(auth.isAuthorised("only-this-one"))
    }
}
