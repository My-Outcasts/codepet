import XCTest
import FirebaseCore
@testable import codepet

/// Regression test for the flaky test-host crash: under XCTest the app skips
/// `FirebaseApp.configure()`, so `Auth.auth()` hits its "must be configured"
/// `fatalError` and SIGABRTs the whole host. `ServerLoggingGate.isOptedOut`
/// reached `Auth.auth()` unguarded (invoked at launch via the reflection
/// pipeline's auth-token provider), which is what crashed. It must degrade to a
/// safe default when the default FirebaseApp isn't configured, never crash.
final class ServerLoggingGateTests: XCTestCase {
    func testIsOptedOutIsSafeWhenFirebaseUnconfigured() {
        XCTAssertNil(FirebaseApp.app(), "test host must not have Firebase configured")
        // Before the fix this call fatal-errors (crashes the host); after the
        // fix it returns false without touching Auth.
        XCTAssertFalse(ServerLoggingGate.isOptedOut)
    }
}
