import Foundation

/// Returns the real user home directory, bypassing macOS sandbox container redirection.
///
/// When an app has (or previously had) a sandbox container, `FileManager.homeDirectoryForCurrentUser`
/// may return `~/Library/Containers/<bundle-id>/Data` even after the sandbox entitlement is removed.
/// This uses `getpwuid` to always get the true home from the system password database.
///
/// Usage:
///     let eventsURL = RealHome.url.appendingPathComponent(".codepet/events.jsonl")
enum RealHome {

    /// The actual `/Users/<name>` directory, never the container path.
    static let url: URL = {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        // Fallback — should never happen on macOS.
        return FileManager.default.homeDirectoryForCurrentUser
    }()
}
