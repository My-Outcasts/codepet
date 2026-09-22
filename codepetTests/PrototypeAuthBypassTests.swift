// codepetTests/PrototypeAuthBypassTests.swift
import XCTest
@testable import codepet

/// Guards on "prototype mode does not require an account".
///
/// **The bug these exist for.** The auth gate in `ContentView` sat above everything the demo
/// touches: `CompanyData.load` is the only place the selected demo project is read, and it is
/// unreachable while signed out. So prototype mode silently required a live Firebase login and
/// a network — and the way it presented was not "you are signed out", it was *"I cannot press
/// the button"* and *"why don't I see any changes at all?"*. Launch flags correct, fixtures
/// correct, founder staring at a sign-in card.
///
/// Nothing failed. That is the whole problem: every existing test asserted the fixtures were
/// right, and none asserted they were REACHABLE. These test the routing decision itself.
final class PrototypeAuthBypassTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PrototypeMode.store.removeObject(forKey: PrototypeMode.key)
        for k in PrototypeMode.launchKeys { PrototypeMode.store.removeObject(forKey: k) }
    }

    override func tearDown() {
        PrototypeMode.store.removeObject(forKey: PrototypeMode.key)
        for k in PrototypeMode.launchKeys { PrototypeMode.store.removeObject(forKey: k) }
        super.tearDown()
    }

    /// Signed out with prototype mode OFF must still reach the sign-in screen. The bypass must
    /// not become a way into the app for a real, signed-out founder.
    func testSignedOutWithoutPrototypeModeStillNeedsSignIn() {
        XCTAssertFalse(PrototypeMode.isOn)
        XCTAssertTrue(ContentView.needsSignIn(signedIn: false, prototypeOn: PrototypeMode.isOn))
    }

    /// The fix: signed out + prototype mode on falls through to the fixture shell.
    func testSignedOutWithPrototypeModeSkipsSignIn() {
        PrototypeMode.set(true)
        XCTAssertTrue(PrototypeMode.isOn)
        XCTAssertFalse(ContentView.needsSignIn(signedIn: false, prototypeOn: PrototypeMode.isOn))
    }

    /// Being signed in never shows sign-in, prototype mode or not — the bypass changes only
    /// the signed-OUT branch.
    func testSignedInNeverNeedsSignIn() {
        XCTAssertFalse(ContentView.needsSignIn(signedIn: true, prototypeOn: false))
        XCTAssertFalse(ContentView.needsSignIn(signedIn: true, prototypeOn: true))
    }

    /// **The gate that would otherwise hold the demo on the splash screen forever.**
    ///
    /// The bootstrapping branch compares the hydrated company id against the expected one.
    /// Standing in for an account, the expected id must be the fixture id — comparing
    /// `"prototype"` against a nil uid never matches, and the founder watches a splash.
    func testExpectedCompanyIdIsTheFixtureIdWhenStandingIn() {
        XCTAssertEqual(ContentView.expectedCompanyId(uid: nil, prototypeOn: true),
                       ContentView.prototypeCompanyId)
    }

    func testExpectedCompanyIdIsTheUidWhenSignedIn() {
        XCTAssertEqual(ContentView.expectedCompanyId(uid: "abc123", prototypeOn: true), "abc123")
        XCTAssertEqual(ContentView.expectedCompanyId(uid: "abc123", prototypeOn: false), "abc123")
    }

    /// Signed out and NOT in prototype mode, there is no company to expect at all.
    func testExpectedCompanyIdIsNilWhenSignedOutAndNotInPrototypeMode() {
        XCTAssertNil(ContentView.expectedCompanyId(uid: nil, prototypeOn: false))
    }

    /// The stand-in is what triggers the hydrate, so it must be true in exactly one state.
    func testStandInOnlyWhenSignedOutAndPrototypeOn() {
        XCTAssertTrue(ContentView.prototypeStandIn(signedIn: false, prototypeOn: true))
        XCTAssertFalse(ContentView.prototypeStandIn(signedIn: false, prototypeOn: false))
        XCTAssertFalse(ContentView.prototypeStandIn(signedIn: true, prototypeOn: true))
        XCTAssertFalse(ContentView.prototypeStandIn(signedIn: true, prototypeOn: false))
    }

    /// **The reason the bypass is safe at all.** Fixture data must not be able to reach a real
    /// account — and with prototype mode on there is no authorised write path regardless of
    /// whether anyone is signed in.
    func testCloudWritesAreBlockedWheneverPrototypeModeIsOn() {
        PrototypeMode.set(true)
        XCTAssertFalse(PrototypeMode.allowsCloudWrites)
    }

    /// The fixture company must be reachable without an account — the end-to-end claim. A
    /// company with no `onboardedAt` would route to onboarding instead of the shell, which is
    /// the second way this bypass could render nothing.
    func testFixtureCompanyIsOnboardedSoTheShellRenders() {
        PrototypeMode.set(true)
        let company = MockChat.company()
        XCTAssertNotNil(company.onboardedAt,
                        "an un-onboarded fixture sends the demo into onboarding, not the shell")
        XCTAssertFalse(company.tasks.isEmpty, "the shell would render an empty board")
    }

    // MARK: - Sign-out must not strand the demo on the splash (F1)

    /// The bug: `showSplash` is the FIRST branch of `body`, above `needsSignIn`. Signing out
    /// set it unconditionally, so prototype mode — which needs no account — landed on an
    /// auth-driven screen anyway. Every test above passed while this was broken, because they
    /// all ask `needsSignIn` directly and never reach the branch that outranks it.
    func testSignOutInPrototypeModeDoesNotReturnToTheSplash() {
        PrototypeMode.set(true)
        XCTAssertTrue(PrototypeMode.isOn)
        XCTAssertFalse(ContentView.showsSplashOnSignOut(hadPriorSession: true,
                                                       prototypeOn: PrototypeMode.isOn),
                       "prototype mode needs no account; the splash above `needsSignIn` must not claim it does")
    }

    /// The behaviour for a real founder is unchanged, and that is the point of fixing it here
    /// rather than reordering `body`: splash-then-sign-in mirrors web Gate's
    /// `wasAuthed`/`splashSeen` and is deliberate.
    func testSignOutWithoutPrototypeModeStillReturnsToTheSplash() {
        XCTAssertFalse(PrototypeMode.isOn)
        XCTAssertTrue(ContentView.showsSplashOnSignOut(hadPriorSession: true,
                                                       prototypeOn: PrototypeMode.isOn))
    }

    /// No prior session means nothing to return FROM — first launch shows the sign-in screen
    /// directly, prototype mode or not. This pins the `hadPriorSession` half so a future
    /// simplification cannot collapse the two conditions into one.
    func testFirstLaunchNeverReturnsToTheSplash() {
        XCTAssertFalse(ContentView.showsSplashOnSignOut(hadPriorSession: false, prototypeOn: false))
        PrototypeMode.set(true)
        XCTAssertFalse(ContentView.showsSplashOnSignOut(hadPriorSession: false, prototypeOn: true))
    }

    /// The two decisions have to agree: whenever the sign-out splash is skipped, the screen
    /// underneath must be the fixture shell rather than the sign-in card. If they ever
    /// disagree, signing out lands somewhere neither path intended.
    func testSkippingTheSplashAlwaysLandsOnTheFixtureShellNotSignIn() {
        PrototypeMode.set(true)
        let splash = ContentView.showsSplashOnSignOut(hadPriorSession: true, prototypeOn: true)
        let signIn = ContentView.needsSignIn(signedIn: false, prototypeOn: true)
        XCTAssertFalse(splash)
        XCTAssertFalse(signIn, "the branch below the splash must agree the demo needs no account")
    }

    // MARK: - A restored real session must still hydrate

    /// **The bug: every release build ever produced sat on "Loading…" forever.**
    ///
    /// `ContentView`'s `currentUser` handler read `guard !PrototypeMode.isLocked`, and outside
    /// DEBUG `isLocked` is hardcoded `true` — correct for the thing it was written for, which
    /// is whether the in-app toggle may be offered. So the handler returned before
    /// `hydrate`, `prototypeStandIn` is `false` outside DEBUG so the `.task` path was shut
    /// too, and the bootstrapping branch of `body` waited for a company id nothing would
    /// ever set.
    ///
    /// This is the shape of a release build, and it is the case that has to pass.
    func testReleaseBuildShapeStillHydratesTheRealSession() {
        XCTAssertTrue(ContentView.acceptsRealSession(locked: true, prototypeOn: false),
                      "locked with prototype mode OFF is every release build — refusing the "
                      + "session here is the deadlock that shipped")
    }

    /// The case the guard actually exists for: a launch argument forced the demo on, so a
    /// stale real session must not repoint `companyStore.companyId` at the founder's company.
    func testLaunchForcedDemoRefusesTheRealSession() {
        XCTAssertFalse(ContentView.acceptsRealSession(locked: true, prototypeOn: true))
    }

    /// Toggling prototype mode at runtime is a different, legitimate path — the founder is
    /// real and their own grant should keep routing their own transport — so it must keep
    /// hydrating normally.
    func testRuntimeToggleKeepsHydratingTheRealSession() {
        XCTAssertTrue(ContentView.acceptsRealSession(locked: false, prototypeOn: true))
    }

    /// The ordinary case, asserted so the guard cannot regress into refusing everything.
    func testOrdinarySessionHydrates() {
        XCTAssertTrue(ContentView.acceptsRealSession(locked: false, prototypeOn: false))
    }

    /// **The invariant, stated once.** A lock says only that the mode cannot be CHANGED this
    /// session; it says nothing about which way it is held. Only `isOn` decides whether a
    /// demo is in progress, so being locked must never by itself refuse a founder's session.
    /// Any future guard that reads `isLocked` without `isOn` fails here.
    func testBeingLockedAloneNeverRefusesASession() {
        for locked in [true, false] {
            XCTAssertTrue(ContentView.acceptsRealSession(locked: locked, prototypeOn: false),
                          "locked=\(locked) with the demo OFF must hydrate")
        }
    }

    /// Ties the pure decision back to the real type, in the direction that matters: with the
    /// demo off, whatever `isLocked` happens to be on this build, the session hydrates.
    func testRealPrototypeModeWithDemoOffHydrates() {
        XCTAssertFalse(PrototypeMode.isOn)
        XCTAssertTrue(ContentView.acceptsRealSession(locked: PrototypeMode.isLocked,
                                                     prototypeOn: PrototypeMode.isOn))
    }
}
