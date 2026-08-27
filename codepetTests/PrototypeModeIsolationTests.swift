import XCTest
@testable import codepet

/// **A human clicking a toggle in the app must not be able to change a test's outcome.**
///
/// `CompanyChatClient.send`/`sendStream` short-circuit on `MockChat.enabled`, which is
/// `PrototypeMode.isOn`, which read `UserDefaults.standard`. The XCTest host IS the app, so it
/// shares that defaults domain: turning prototype mode on made six `CompanyChatClientTests`
/// receive `MockChat` fixture text where the real client's bytes were expected (issue #117).
///
/// The failure those six showed is the LUCKY direction — loud and red. The same coupling means
/// any test that would pass against fixtures and fail against the real client passes **for the
/// wrong reason** whenever prototype mode is on, and nobody notices a green run.
///
/// It also could not be diagnosed by looking: the plist read `cp_prototypeMode = false` while the
/// suite was still seeing mock data, because a RUNNING app holds the live value in `cfprefsd` and
/// the test host reads through the same daemon. `defaults read` confirms the wrong answer twice
/// over, resolving to an empty sandbox container while the unsandboxed app uses
/// `~/Library/Preferences/app.murror.codepet.plist`.
final class PrototypeModeIsolationTests: XCTestCase {

    /// Writes to the REAL domain exactly as the app's toggle does, then asserts the test target
    /// cannot see it. Restores whatever was there — a test that leaves prototype mode on would
    /// be doing to the founder's app what this issue is about.
    private func withRealDomainPrototypeMode(_ on: Bool, _ body: () -> Void) {
        let previous = UserDefaults.standard.object(forKey: PrototypeMode.key)
        UserDefaults.standard.set(on, forKey: PrototypeMode.key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: PrototypeMode.key) }
            else { UserDefaults.standard.removeObject(forKey: PrototypeMode.key) }
        }
        body()
    }

    func testTheFoundersToggleIsInvisibleToTests() {
        withRealDomainPrototypeMode(true) {
            XCTAssertFalse(PrototypeMode.isOn,
                           "a preference set in the app's own domain reached the test host")
            XCTAssertFalse(MockChat.enabled,
                           "MockChat would intercept the real client for every test in this target")
        }
    }

    /// The gate that keeps fixture data out of a real company document reads the same global.
    /// If prototype mode leaks in, this silently flips too.
    func testTheCloudWriteGateIsAlsoIsolated() {
        withRealDomainPrototypeMode(true) {
            XCTAssertTrue(PrototypeMode.allowsCloudWrites,
                          "allowsCloudWrites follows isOn, so it leaks with it")
        }
    }

    /// Isolation must not be one-way: a test that sets the mode through the injected store still
    /// sees it, or the seam would be useless for testing prototype-mode behaviour itself.
    func testTheInjectedStoreIsStillHonoured() {
        let before = PrototypeMode.isOn
        PrototypeMode.store.set(true, forKey: PrototypeMode.key)
        defer { PrototypeMode.store.removeObject(forKey: PrototypeMode.key) }
        XCTAssertTrue(PrototypeMode.isOn, "the seam must remain usable, not merely inert")
        XCTAssertFalse(before, "the target should start with prototype mode off")
    }
}
