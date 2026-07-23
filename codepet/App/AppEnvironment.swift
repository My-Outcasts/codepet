import Foundation
import FirebaseAuth

/// Centralized opt-out for ALL off-device data transmission.
///
/// Any signed-in account whose email is in `optedOutEmails` has every server
/// data flow disabled: Firestore progress sync (`CloudSyncService`), the Cloud
/// Functions reflection pipeline (`ReflectionAPIClient`), and feedback uploads
/// (`FeatureFeedbackManager`). Local-only features (auth, on-disk state,
/// reading `~/.codepet`) are unaffected — nothing leaves the device.
enum ServerLoggingGate {
    /// Emails (compared lowercased) for which all uploads/logging are disabled.
    static let optedOutEmails: Set<String> = [
        "giang@murror.app"
    ]

    /// True when the currently signed-in account has opted out of server logging.
    static var isOptedOut: Bool {
        guard let email = Auth.auth().currentUser?.email else { return false }
        return optedOutEmails.contains(email.lowercased())
    }
}

enum AppEnvironment {
    /// True when the process is running inside an XCTest bundle.
    ///
    /// Firebase/Firestore abort (SIGABRT) when their backing store isn't
    /// available under the `xcodebuild test` runner, which takes the whole test
    /// host down before any test can run. We use this flag to skip all
    /// Firebase initialization and Firestore access while testing. It's purely
    /// launch-time test detection and has no effect on the shipping app.
    static let isRunningTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}
