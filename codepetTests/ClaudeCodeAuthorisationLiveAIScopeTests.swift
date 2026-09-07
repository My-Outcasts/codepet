// codepetTests/ClaudeCodeAuthorisationLiveAIScopeTests.swift
import XCTest
@testable import codepet

/// Guards the Amendment 4 follow-up: `CODEPET_LIVE_AI` closed the loop end-to-end
/// (`4ef81e5` swapped `MockChat`'s transport for `LocalTransportRouter`) but nothing
/// ever granted `ClaudeCodeAuthorisation`, so `transport()` still fell through to
/// `.cloud` — which now 401s, the API key having been deleted 26 Aug. The founder's
/// live-mode flag was inert.
///
/// **Amendment 2, 6 Sep — keyed on prototype mode, not on a literal id.** The first fix
/// (`f54d570`) answered true only for `ContentView.prototypeCompanyId`, on the assumption
/// prototype mode always hydrates under that literal string. It does — but only while
/// nobody is signed in. A founder who is actually signed in and flips prototype mode +
/// live AI on from inside the running app keeps her REAL uid as `companyId` throughout,
/// so the literal-id check granted nothing for her: `transport()` fell to `.cloud`, her
/// real session made the token succeed, and the call went out and 401'd anyway — the
/// exact failure this file exists to prevent, reached from the opposite direction (a
/// grant that exists but is keyed to an id nobody is using). The fix asks the real
/// question — is prototype mode's live-AI switch ON — rather than which id happens to be
/// active. These tests exercise the DEFAULT `isAuthorised` closure itself (the thing that
/// changed both times), never a custom one, and never call anything that could spawn
/// `claude` or spend a token.
final class ClaudeCodeAuthorisationLiveAIScopeTests: XCTestCase {

    // A real company id, never granted, that will not collide with anything a founder
    // (or another suite) might have set — asserts "no stored grant stays unauthorised
    // whenever prototype mode itself is off".
    private let ungranted = "clc-live-scope-ungranted-\(UUID().uuidString)"
    // A real company id whose grant we set ourselves, to prove `liveAI` never touches a
    // stored grant for a non-prototype id either way.
    private let storedGrant = "clc-live-scope-granted-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        clearPrototypeState()
        // Defensive: these are freshly minted UUIDs, so neither key should exist, but
        // clear explicitly rather than trust that.
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(ungranted))
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(storedGrant))
    }

    override func tearDown() {
        clearPrototypeState()
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(ungranted))
        UserDefaults.standard.removeObject(forKey: ClaudeCodeAuthorisation.key(storedGrant))
        super.tearDown()
    }

    private func clearPrototypeState() {
        PrototypeMode.store.removeObject(forKey: "CODEPET_LIVE_AI")
        PrototypeMode.store.removeObject(forKey: PrototypeMode.key)
    }

    // MARK: - The main guard

    /// **This is the guard that replaces the literal-id check.** With prototype mode AND
    /// `liveAI` both on, ANY id is authorised — the prototype id, and a real, never-granted
    /// uid exactly like a signed-in founder's own. That second assertion is the case that
    /// broke: revert the branch back to `$0 == ContentView.prototypeCompanyId` and it goes
    /// red, because a signed-in founder's uid is never that literal string.
    func testLiveAIWithPrototypeModeOnAuthorisesAnyCompanyId() {
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")

        let auth = ClaudeCodeAuthorisation()

        XCTAssertTrue(auth.isAuthorised(ContentView.prototypeCompanyId),
                      "the prototype id must still be authorised — this is not a narrowing")
        XCTAssertTrue(auth.isAuthorised(ungranted),
                      "a signed-in founder's real (never granted) uid must ALSO be authorised "
                      + "while prototype mode + liveAI are both on — this is the exact bug")
    }

    /// `liveAI` alone, with prototype mode OFF, must grant nothing — `PrototypeMode.liveAI`'s
    /// own doc comment calls it "meaningless with all three [launch keys] off", and this is
    /// what makes that true for authorisation specifically, not just for which transport a
    /// scheduled call would take.
    func testLiveAIAloneWithoutPrototypeModeAuthorisesNothing() {
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        XCTAssertFalse(PrototypeMode.isOn, "test setup sanity: prototype mode must be off here")

        let auth = ClaudeCodeAuthorisation()
        XCTAssertFalse(auth.isAuthorised(ContentView.prototypeCompanyId))
        XCTAssertFalse(auth.isAuthorised(ungranted))
    }

    /// With `liveAI` off (prototype mode on or not), nothing here grants anything — it falls
    /// back to the stored check exactly like any other id, and nothing was ever stored.
    func testWithLiveAIOffNothingIsAuthorisedByThisBranch() {
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
        XCTAssertFalse(PrototypeMode.liveAI)
        let auth = ClaudeCodeAuthorisation()
        XCTAssertFalse(auth.isAuthorised(ContentView.prototypeCompanyId),
                       "the gate's default must be untouched: no flag, no grant")
        XCTAssertFalse(auth.isAuthorised(ungranted))
    }

    /// A real company's stored grant is exactly as authoritative with `liveAI` off as on.
    func testStoredGrantForARealCompanyIsUnchangedByLiveAIEitherWay() {
        UserDefaults.standard.set(true, forKey: ClaudeCodeAuthorisation.key(storedGrant))
        let auth = ClaudeCodeAuthorisation()

        XCTAssertTrue(auth.isAuthorised(storedGrant), "liveAI off: the real grant still holds")
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")
        XCTAssertTrue(auth.isAuthorised(storedGrant), "liveAI on: the real grant still holds, unmodified")
    }

    // MARK: - The injected-closure seam survives

    /// A test (or any caller) that supplies its own `isAuthorised` must see ONLY its own
    /// answer — `liveAI` must never leak in underneath a closure that overrode it.
    func testInjectedClosureOverridesTheDefaultEvenWithLiveAIOn() {
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
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
