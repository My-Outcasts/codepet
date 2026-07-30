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

/// Outcome of `commitGit`. `committed` is whether the commit landed; `stashRestored`
/// is whether the founder's pre-existing stashed work was popped back cleanly — false
/// when it conflicted with the agent's commit and was left safely in `git stash` for
/// manual recovery (2C surfaces this to the founder).
struct GitCommitResult: Equatable {
    let committed: Bool
    let stashRestored: Bool
    /// True when `git commit` found nothing to stage.
    var nothingToCommit: Bool = false
    /// True when nothing was staged BUT the branch already carries the change (a real
    /// duplicate Approve). Distinguishes "already done" (→ committed) from "the edit
    /// never reached the branch" (→ honest failure), so the card can't claim a commit
    /// that isn't there.
    var alreadyOnBranch: Bool = false
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
        // `stashed` reflects whether a stash was ACTUALLY created — not merely that the
        // tree looked dirty — so a failed push can't make abort/commit later pop an
        // unrelated stash off the stack.
        var stashed = false
        if dirty {
            let push = GitRunner.run(["stash", "push", "-u"], in: projectPath)
            stashed = push.ok && !push.stdout.contains("No local changes")
        }

        let branch = "codepet/" + CommitSlug.make(from: taskTitle)
        let checkout = GitRunner.run(["checkout", "-b", branch], in: projectPath)
        guard checkout.ok else {
            if stashed { _ = GitRunner.run(["stash", "pop"], in: projectPath) }
            return nil
        }
        return GitSession(projectPath: projectPath, branch: branch, originalRef: ref, stashed: stashed)
    }

    @discardableResult
    static func commitGit(_ s: GitSession, files: [String], message: String) -> GitCommitResult {
        guard !files.isEmpty else { return GitCommitResult(committed: false, stashRestored: false) }
        _ = GitRunner.run(["add"] + files, in: s.projectPath)
        let commit = GitRunner.run(["commit", "-m", message], in: s.projectPath)
        guard commit.ok else {
            // "nothing to commit" is NOT a failure — the change is already on the
            // branch (e.g. a duplicate Approve). Flag it so the caller keeps the
            // branch instead of aborting/deleting it.
            let nothing = (commit.stdout + commit.stderr).contains("nothing to commit")
                || (commit.stdout + commit.stderr).contains("nothing added to commit")
            // If nothing was staged, is the change ALREADY on the branch (true
            // duplicate) or did the edit never land (real problem)? Decide honestly.
            var already = false
            if nothing {
                let ahead = GitRunner.run(["rev-list", "--count", "\(s.originalRef)..\(s.branch)"], in: s.projectPath)
                    .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                already = (ahead != "0" && ahead != "")
            }
            // Commit failed → leave the session intact and do NOT pop here; a
            // follow-up abortGit restores the stash (avoids a double-pop).
            return GitCommitResult(committed: false, stashRestored: false,
                                   nothingToCommit: nothing, alreadyOnBranch: already)
        }
        var stashRestored = true
        if s.stashed {
            let pop = GitRunner.run(["stash", "pop"], in: s.projectPath)
            if !pop.ok {
                // The founder's stashed edits overlap the agent's commit → pop
                // conflicts. Reset the tree back to the clean commit and LEAVE the
                // stash in place (recoverable) rather than leaving conflict markers.
                _ = GitRunner.run(["reset", "--hard", "HEAD"], in: s.projectPath)
                stashRestored = false
            }
        }
        return GitCommitResult(committed: true, stashRestored: stashRestored)
    }

    static func abortGit(_ s: GitSession) {
        _ = GitRunner.run(["checkout", "--", "."], in: s.projectPath)   // revert tracked run edits
        _ = GitRunner.run(["clean", "-fd"], in: s.projectPath)          // remove run-created untracked files (respects .gitignore)
        let switched = GitRunner.run(["checkout", s.originalRef], in: s.projectPath).ok
        // Only delete the throwaway branch if it carries NO commits beyond where it
        // started. A branch with commits holds real, approved work — never destroy it
        // (that was the source of "the commit vanished"): reject/supersede on an
        // already-committed run would otherwise `branch -D` the founder's change.
        if switched {
            let ahead = GitRunner.run(["rev-list", "--count", "\(s.originalRef)..\(s.branch)"], in: s.projectPath)
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only delete when the branch carries no commits — never destroy work.
            if ahead == "0" {
                _ = GitRunner.run(["branch", "-D", s.branch], in: s.projectPath)
            }
        }
        // Only restore the stash once safely back on the original ref — never pop
        // onto the codepet branch if the switch failed.
        if s.stashed && switched { _ = GitRunner.run(["stash", "pop"], in: s.projectPath) }
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
            guard let items = try? fm.contentsOfDirectory(atPath: projectPath) else {
                try? fm.removeItem(atPath: root); return nil
            }
            // NOTE: top-level exclusions only — a nested `sub/node_modules` is still
            // copied. Fine for a v1 non-git project; revisit if monorepos get slow.
            for name in items where !shadowSkip.contains(name) {
                try fm.copyItem(at: base.appendingPathComponent(name),
                                to: URL(fileURLWithPath: shadowDir).appendingPathComponent(name))
            }
        } catch { try? fm.removeItem(atPath: root); return nil }
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
            // Back up the original BEFORE touching the real file. If the backup can't
            // be made, NEVER overwrite it — otherwise undo couldn't restore it (data loss).
            if fm.fileExists(atPath: realURL.path) {
                do { try fm.copyItem(at: realURL, to: backupURL) }
                catch { allOK = false; continue }                            // skip apply: original stays intact
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
