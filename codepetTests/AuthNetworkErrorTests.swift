import XCTest
@testable import codepet

/// Astro, 1 Oct: "can't sign in through Google" showed only "Network error. Check your internet
/// connection". Firebase's 17020 wraps the system error that says WHY — DNS, timeout, a VPN or
/// antivirus intercepting TLS, a wrong clock — and the message and the persisted log both threw
/// it away (the one line that had it was `.debug` + `.private`, which macOS does not keep).
/// Now the cause is named, and its code rides in the message so a tester's screenshot carries it.
final class AuthNetworkErrorTests: XCTestCase {

    private func firebaseNetworkError(wrapping url: Int?) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: "Network error (such as timeout, interrupted connection or unreachable host) has occurred."]
        if let url {
            info[NSUnderlyingErrorKey] = NSError(domain: NSURLErrorDomain, code: url, userInfo: nil)
        }
        return NSError(domain: AuthErrorMessage.firebaseAuthDomain, code: 17020, userInfo: info)
    }

    func testTheUnderlyingCodeIsFoundThroughTheChain() {
        let deep = NSError(domain: "FIRAuthErrorDomain", code: 17020, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "FIRAuthInternalErrorDomain", code: 3, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1200)])])
        XCTAssertEqual(AuthErrorMessage.urlErrorCode(in: deep), -1200)
        XCTAssertEqual(AuthErrorMessage.chain(deep), "FIRAuthErrorDomain:17020 > FIRAuthInternalErrorDomain:3 > NSURLErrorDomain:-1200")
    }

    func testASecurityToolInterceptingTLSIsNamed() {
        for code in [-1200, -1202, -1203, -1205, -1206] {
            let m = AuthErrorMessage.friendly(firebaseNetworkError(wrapping: code))
            XCTAssertTrue(m.contains("VPN, antivirus or proxy"), "\(code): \(m)")
            XCTAssertTrue(m.contains("(code \(code))"), m)
        }
    }

    func testAWrongClockIsNamed() {
        for code in [-1201, -1204] {
            let m = AuthErrorMessage.friendly(firebaseNetworkError(wrapping: code))
            XCTAssertTrue(m.contains("date and time"), "\(code): \(m)")
        }
    }

    func testBlockedHostOfflineAndTimeoutEachSayWhatHappened() {
        XCTAssertTrue(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: -1003)).contains("can't reach Google's sign-in servers"))
        XCTAssertTrue(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: -1004)).contains("can't reach Google's sign-in servers"))
        XCTAssertTrue(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: -1009)).contains("offline"))
        XCTAssertTrue(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: -1001)).contains("didn't answer in time"))
    }

    /// An unrecognised or absent cause still says "Network error" — never worse than before — and
    /// carries whatever code there is, so the next report is diagnosable.
    func testUnknownCausesKeepTheOldMessagePlusTheCode() {
        XCTAssertEqual(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: -1017)),
                       "Network error (code -1017). Check your internet connection and try again.")
        XCTAssertEqual(AuthErrorMessage.friendly(firebaseNetworkError(wrapping: nil)),
                       "Network error. Check your internet connection and try again.")
    }

    /// The 17xxx table is Firebase Auth's. A Google Sign-In SDK error that happens to share a code
    /// number must not be dressed up as a Firebase message.
    func testFirebaseCodesAreOnlyReadFromFirebase() {
        let other = NSError(domain: "com.google.GIDSignIn", code: 17009, userInfo: [NSLocalizedDescriptionKey: "raw"])
        XCTAssertEqual(AuthErrorMessage.friendly(other), "raw")
    }
}
