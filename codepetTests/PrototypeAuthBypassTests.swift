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
}
