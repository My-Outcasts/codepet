import Foundation

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
