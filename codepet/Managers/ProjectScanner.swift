import Foundation
import Combine
import os

/// Result of scanning a project's files for business/growth signals.
///
/// The scan reads a bounded set of high-signal files (manifests, lockfiles,
/// entry HTML, the Xcode project) plus a shallow directory listing, then
/// concatenates them into one lowercased `haystack`. `ProjectHealthEngine`
/// matches the same rule keywords/patterns against this haystack as it does
/// against the path and brief — so a dependency like `stripe` or a file like
/// `sitemap.xml` is detected from the project's actual contents, not just from
/// what the user happened to type in the brief.
struct ProjectScanResult {
    /// Lowercased: concatenated file contents + filenames found in the project.
    let haystack: String
}

/// Scans detected projects' files in the background and caches the result per
/// project root. Non-sandboxed (`app-sandbox = false`), so it can read the
/// real project directories that `ProjectStore` detects from Claude Code events.
///
/// Scanning is off the main thread and cached for the session: file-based
/// signals (which payment SDK, whether a sitemap exists) change rarely, so a
/// once-per-path scan is plenty and keeps the Tips view's render path free of disk I/O.
@MainActor
final class ProjectScanner: ObservableObject {

    /// Scan results keyed by project root path.
    @Published private(set) var results: [String: ProjectScanResult] = [:]

    /// Paths with an in-flight scan, so we don't launch duplicates.
    private var scanning: Set<String> = []

    private let logger = Logger(subsystem: "app.murror.codepet", category: "ProjectScanner")

    /// Scan any projects not yet scanned this session. Cheap no-op for paths
    /// already cached or mid-scan. Call when the project set changes.
    func refresh(projects: [Project]) {
        for project in projects {
            let path = project.id
            guard results[path] == nil, !scanning.contains(path) else { continue }
            scanning.insert(path)
            Task.detached(priority: .utility) {
                let result = ProjectScanner.scanProject(at: path)
                await MainActor.run {
                    self.results[path] = result
                    self.scanning.remove(path)
                }
            }
        }
    }

    /// Clear cached scans (e.g. on account switch).
    func resetAll() {
        results = [:]
        scanning = []
    }

    // MARK: - Scanning (off main thread)

    /// Per-file read cap — enough to capture a manifest's dependency block or an
    /// HTML head without pulling a huge lockfile fully into memory.
    /// `nonisolated` so the off-main-thread `scanProject` can read them.
    nonisolated private static let maxBytesPerFile = 200_000

    /// Bounded set of high-signal text files to read, relative to the root.
    nonisolated private static let relativeFiles = [
        "package.json", "Podfile", "Podfile.lock",
        "requirements.txt", "pyproject.toml", "Package.resolved",
        "index.html", "public/index.html", "app/index.html", "src/index.html",
        "vercel.json", "netlify.toml",
    ]

    /// Directories (relative to root) whose immediate filenames we collect — so
    /// presence of `sitemap.xml`, `robots.txt`, `privacy.html`, `terms.md`, or a
    /// `.storekit` config registers as a signal.
    nonisolated private static let listDirs = ["", "public", "src", "app", "web", "frontend"]

    nonisolated static func scanProject(at root: String) -> ProjectScanResult {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        var parts: [String] = []

        func readFile(_ url: URL) {
            guard fm.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { return }
            let slice = data.prefix(maxBytesPerFile)
            if let text = String(data: slice, encoding: .utf8) {
                parts.append(text.lowercased())
            }
        }

        // 1. Known manifest / entry files at root and common web subdirs.
        for rel in relativeFiles {
            readFile(rootURL.appendingPathComponent(rel))
        }

        // 2. The first *.xcodeproj — its project file lists linked frameworks
        //    (e.g. StoreKit), and the bundled Package.resolved lists SPM deps
        //    (e.g. RevenueCat, Stripe). Catches iOS/macOS monetization wiring.
        if let children = try? fm.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ), let xcodeproj = children.first(where: { $0.pathExtension == "xcodeproj" }) {
            readFile(xcodeproj.appendingPathComponent("project.pbxproj"))
            readFile(xcodeproj.appendingPathComponent(
                "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
        }

        // 3. Shallow filename listing — presence of named files is itself signal.
        for sub in listDirs {
            let dir = sub.isEmpty ? rootURL : rootURL.appendingPathComponent(sub)
            if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
                parts.append(names.joined(separator: " ").lowercased())
            }
        }

        return ProjectScanResult(haystack: parts.joined(separator: "\n"))
    }
}
