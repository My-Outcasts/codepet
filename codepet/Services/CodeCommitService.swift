import Foundation

/// A live git-path commit session: work happens on `branch` (a throwaway
/// `codepet/<slug>` off `originalRef`); `stashed` records whether pre-existing
/// dirty work was stashed so abort/commit can restore it.
struct GitSession: Equatable {
    let projectPath: String
    let branch: String
    let originalRef: String
    let stashed: Bool
}

/// Isolates an edit_code run so any change is instantly revertible. Git repos use
/// a throwaway branch; non-git projects use a shadow copy (see the shadow path
/// below). Never merges, pushes, or deploys — only commits to `codepet/<slug>`.
enum CodeCommitService {

    // MARK: Git path

    static func beginGit(projectPath: String, taskTitle: String) -> GitSession? {
        let inside = GitRunner.run(["rev-parse", "--is-inside-work-tree"], in: projectPath)
        guard inside.ok, inside.stdout.contains("true") else { return nil }

        let ref = GitRunner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: projectPath)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return nil }

        let dirty = !GitRunner.run(["status", "--porcelain"], in: projectPath)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if dirty { _ = GitRunner.run(["stash", "push", "-u"], in: projectPath) }

        let branch = "codepet/" + CommitSlug.make(from: taskTitle)
        let checkout = GitRunner.run(["checkout", "-b", branch], in: projectPath)
        guard checkout.ok else {
            if dirty { _ = GitRunner.run(["stash", "pop"], in: projectPath) }
            return nil
        }
        return GitSession(projectPath: projectPath, branch: branch, originalRef: ref, stashed: dirty)
    }

    @discardableResult
    static func commitGit(_ s: GitSession, files: [String], message: String) -> Bool {
        guard !files.isEmpty else { return false }
        _ = GitRunner.run(["add"] + files, in: s.projectPath)
        let commit = GitRunner.run(["commit", "-m", message], in: s.projectPath)
        if s.stashed { _ = GitRunner.run(["stash", "pop"], in: s.projectPath) }
        return commit.ok
    }

    static func abortGit(_ s: GitSession) {
        _ = GitRunner.run(["checkout", "--", "."], in: s.projectPath)   // drop uncommitted run edits
        _ = GitRunner.run(["checkout", s.originalRef], in: s.projectPath)
        _ = GitRunner.run(["branch", "-D", s.branch], in: s.projectPath)
        if s.stashed { _ = GitRunner.run(["stash", "pop"], in: s.projectPath) }
    }

    // MARK: Shadow path (non-git)

    struct ShadowSession {
        let projectPath: String
        let shadowDir: String
        let backupDir: String
    }

    private static let shadowSkip: Set<String> = [".git", "node_modules", ".next", "build", "DerivedData"]

    static func beginShadow(projectPath: String) -> ShadowSession? {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "codepet-shadow-" + UUID().uuidString
        let shadowDir = root + "/work"
        let backupDir = root + "/backup"
        do {
            try fm.createDirectory(atPath: shadowDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
            let base = URL(fileURLWithPath: projectPath)
            guard let items = try? fm.contentsOfDirectory(atPath: projectPath) else { return nil }
            for name in items where !shadowSkip.contains(name) {
                try fm.copyItem(at: base.appendingPathComponent(name),
                                to: URL(fileURLWithPath: shadowDir).appendingPathComponent(name))
            }
        } catch { return nil }
        return ShadowSession(projectPath: projectPath, shadowDir: shadowDir, backupDir: backupDir)
    }

    /// A newly-created file (no pre-apply original) records a `.tombstone` marker in
    /// the backup so `undoShadow` deletes it rather than restoring content.
    @discardableResult
    static func applyShadow(_ s: ShadowSession, acceptedRelPaths: [String]) -> Bool {
        let fm = FileManager.default
        var allOK = true
        for rel in acceptedRelPaths {
            let realURL = URL(fileURLWithPath: s.projectPath).appendingPathComponent(rel)
            let shadowURL = URL(fileURLWithPath: s.shadowDir).appendingPathComponent(rel)
            let backupURL = URL(fileURLWithPath: s.backupDir).appendingPathComponent(rel)
            try? fm.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: realURL.path) {
                try? fm.copyItem(at: realURL, to: backupURL)                 // back up the original
            } else {
                fm.createFile(atPath: backupURL.path + ".tombstone", contents: Data())  // mark as new
            }
            do {
                try fm.createDirectory(at: realURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: realURL.path) { try fm.removeItem(at: realURL) }
                try fm.copyItem(at: shadowURL, to: realURL)                  // apply the shadow version
            } catch { allOK = false }
        }
        return allOK
    }

    static func undoShadow(_ s: ShadowSession) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: s.backupDir) else { return }
        for case let rel as String in walker {
            let backupURL = URL(fileURLWithPath: s.backupDir).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: backupURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            if rel.hasSuffix(".tombstone") {
                let created = String(rel.dropLast(".tombstone".count))
                try? fm.removeItem(at: URL(fileURLWithPath: s.projectPath).appendingPathComponent(created))
            } else {
                let realURL = URL(fileURLWithPath: s.projectPath).appendingPathComponent(rel)
                if fm.fileExists(atPath: realURL.path) { try? fm.removeItem(at: realURL) }
                try? fm.copyItem(at: backupURL, to: realURL)
            }
        }
    }

    static func discardShadow(_ s: ShadowSession) {
        try? FileManager.default.removeItem(atPath: (s.shadowDir as NSString).deletingLastPathComponent)
    }
}
