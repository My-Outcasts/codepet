# Part 2B — Run + Commit Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide the safe commit substrate the coding agent runs on top of: a `CodeCommitService` that isolates an `edit_code` run on a throwaway git branch (git repos) or a shadow copy (non-git), and commits accepted changes on approval / instantly undoes them on reject.

**Architecture:** `ClaudeCodeRunner` is reused unchanged — it already runs `claude` in any `projectDir` with configurable `allowedTools`/`maxTurns` and computes real `FileDiff`s. 2B adds **`CodeCommitService`** (+ a small `GitRunner` Process wrapper). The service chooses the run's working directory and handles commit/undo:
- **git repo** → stash any dirty changes, branch `codepet/<slug>` off HEAD, run there, commit accepted files on approve, or hard-reset + delete branch + restore stash on reject.
- **no git** → copy the project to a temp shadow dir, run there, on approve copy accepted files back to the real tree (backing up the originals first), or discard on reject; **undo** restores the backup.

The approval gate + chat UI that drive this are 2C — 2B ships the primitives, TDD'd against temp repos/dirs.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild, system `git`. No new dependencies.

## Scope

**Part 2B** — second of four Part-2 sub-plans (2A linking ✅ → **2B run+commit engine** → 2C edit_code verb+chat UI → 2D triggers+Engineering dept).

**In 2B:** `GitRunner`, `CodeCommitService` git-path (branch/commit/abort, dirty-tree stash) and shadow-path (copy/apply/backup/undo), slug generation. Reuse `ClaudeCodeRunner` as-is.

**Explicitly deferred:**
- The **orchestration with the approval gate** (begin → run `ClaudeCodeRunner` → show diffs → await Approve/Reject → commit/abort) and its chat UI → **2C**.
- The **honest-plan fallback** when `claude` is missing → 2C (the runner already surfaces the error; 2C turns it into the plan).
- Actually invoking `ClaudeCodeRunner` from the service → 2C wires begin/run/commit together. 2B's service exposes the primitives 2C calls.

## Robustness decisions (made explicit — please confirm at review)

1. **Dirty working tree (git path):** before branching, if `git status --porcelain` is non-empty, `git stash push -u`; restore with `git stash pop` after commit *and* after abort, on the original branch. Only stash/pop when there was something to stash. This keeps the founder's pre-existing uncommitted work intact regardless of approve/reject.
2. **git run happens in the real working tree on a throwaway branch** (not a separate worktree) — matches the spec's stated model; the branch (never `main`) is the revert boundary.
3. **Shadow copy excludes** `.git`, `node_modules`, `.next`, `build`, `DerivedData` (mirrors `ClaudeCodeRunner.snapshot`'s skips) to stay fast and avoid copying VCS/artifacts.
4. **Backup granularity (shadow path):** per-run backup directory holding the pre-apply copy of exactly the accepted files (and a record of files that were newly created, so undo deletes them). Undo restores/removes to the exact pre-apply state.

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest. App is NOT sandboxed — spawning `git` and reading/writing real dirs is permitted (as `ClaudeCodeRunner` already spawns `claude`).
- **Never a change you can't instantly undo** (spec §4): git path is a throwaway branch off HEAD, `main` never touched; shadow path never writes the real tree until `apply`, and keeps a restorable backup.
- **Never merges/deploys/deletes unattended:** the service commits only to `codepet/<slug>`, never merges, never pushes, never deploys.
- Spawn `git` at `/usr/bin/git` (present on macOS); set the process's `currentDirectoryURL`. Capture stdout/stderr/exit; never throw across the API — return a typed result.
- Build/test signing: `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`.
- **Close any running `codepet.app` before `xcodebuild test`** (Firestore lock). These tests are pure/temp-dir/subprocess and don't touch Firestore, so they run in the host like `ProjectLinkTests`.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Create** `codepet/Services/GitRunner.swift` — synchronous `git` subprocess wrapper (run subcommand in a dir → `{stdout, stderr, exitCode}`), plus `CommitSlug.make(from:)`.
- **Create** `codepet/Services/CodeCommitService.swift` — the git-path + shadow-path session lifecycle.
- **Create** `codepetTests/GitRunnerTests.swift`, `codepetTests/CodeCommitServiceTests.swift` — TDD against temp git repos / temp dirs.

`ClaudeCodeRunner` is unchanged (reused by 2C).

---

## Task 1: `GitRunner` + `CommitSlug`

**Files:**
- Create: `codepet/Services/GitRunner.swift`
- Test: `codepetTests/GitRunnerTests.swift`

**Interfaces:**
- Produces:
  - `struct GitResult: Equatable { let stdout: String; let stderr: String; let exitCode: Int32; var ok: Bool { exitCode == 0 } }`
  - `enum GitRunner { @discardableResult static func run(_ args: [String], in dir: String) -> GitResult }` — runs `/usr/bin/git <args>` with `currentDirectoryURL = dir`; never throws.
  - `enum CommitSlug { static func make(from title: String) -> String }` — pure: lowercased, non-alphanumerics → `-`, collapsed, trimmed, capped ~40 chars; empty → `"change"`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/GitRunnerTests.swift`:

```swift
import XCTest
@testable import codepet

final class GitRunnerTests: XCTestCase {

    private func tempGitRepo() -> String {
        let base = NSTemporaryDirectory() + "codepet-2b-git-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        _ = GitRunner.run(["init"], in: base)
        _ = GitRunner.run(["config", "user.email", "t@t.co"], in: base)
        _ = GitRunner.run(["config", "user.name", "t"], in: base)
        try? "hello".write(toFile: base + "/README.md", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add", "."], in: base)
        _ = GitRunner.run(["commit", "-m", "init"], in: base)
        return base
    }

    func test_run_reportsExitAndOutput() {
        let repo = tempGitRepo()
        let r = GitRunner.run(["rev-parse", "--is-inside-work-tree"], in: repo)
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.stdout.contains("true"))
    }

    func test_run_nonZeroOnBadCommand() {
        let repo = tempGitRepo()
        let r = GitRunner.run(["checkout", "no-such-branch"], in: repo)
        XCTAssertFalse(r.ok)
    }

    func test_slug_isKebabAndCapped() {
        XCTAssertEqual(CommitSlug.make(from: "Fix the Signup Validation!"), "fix-the-signup-validation")
        XCTAssertEqual(CommitSlug.make(from: "   "), "change")
        XCTAssertLessThanOrEqual(CommitSlug.make(from: String(repeating: "a", count: 100)).count, 40)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/GitRunnerTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `GitRunner`/`CommitSlug` not found.

- [ ] **Step 3: Implement**

Create `codepet/Services/GitRunner.swift`:

```swift
import Foundation

/// Result of a `git` subprocess call.
struct GitResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var ok: Bool { exitCode == 0 }
}

/// Minimal synchronous `git` wrapper. Runs `/usr/bin/git <args>` in `dir`,
/// captures stdout/stderr/exit. Never throws — a launch failure returns a
/// non-zero `GitResult`. (App is non-sandboxed; spawning git is permitted, same
/// as ClaudeCodeRunner spawning claude.)
enum GitRunner {
    private static let gitPath = "/usr/bin/git"

    @discardableResult
    static func run(_ args: [String], in dir: String) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gitPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do { try proc.run() } catch {
            return GitResult(stdout: "", stderr: String(describing: error), exitCode: -1)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return GitResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus)
    }
}

/// Pure branch/commit slug from a human title.
enum CommitSlug {
    static func make(from title: String) -> String {
        let lowered = title.lowercased()
        var slug = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                slug.append(ch); lastDash = false
            } else if !lastDash {
                slug.append("-"); lastDash = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > 40 { slug = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        return slug.isEmpty ? "change" : slug
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/GitRunnerTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/GitRunner.swift codepetTests/GitRunnerTests.swift
git commit -F - <<'EOF'
feat(coding-agent): GitRunner subprocess wrapper + commit slug (Part 2B)

Synchronous /usr/bin/git wrapper (stdout/stderr/exit, never throws) + a pure
kebab CommitSlug. Foundation for CodeCommitService.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: `CodeCommitService` — git path (branch / commit / abort)

**Files:**
- Create: `codepet/Services/CodeCommitService.swift`
- Test: `codepetTests/CodeCommitServiceTests.swift`

**Interfaces:**
- Consumes: `GitRunner`, `CommitSlug`.
- Produces:
  - `struct GitSession: Equatable { let projectPath: String; let branch: String; let originalRef: String; let stashed: Bool }`
  - `enum CodeCommitService`:
    - `static func beginGit(projectPath: String, taskTitle: String) -> GitSession?` — records the current ref, stashes dirty work if any (`git stash push -u`), creates + checks out `codepet/<slug>`. Returns nil if not a git repo or a git step fails.
    - `static func commitGit(_ s: GitSession, files: [String], message: String) -> Bool` — `git add <files>` (relative paths) + `git commit -m`; then restores the stash (still on the codepet branch). Returns true on a successful commit.
    - `static func abortGit(_ s: GitSession)` — `git checkout -- .`, `git checkout <originalRef>`, `git branch -D <branch>`, and restore the stash. Leaves the repo exactly as before `beginGit`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/CodeCommitServiceTests.swift`:

```swift
import XCTest
@testable import codepet

final class CodeCommitServiceTests: XCTestCase {

    private func tempGitRepo() -> String {
        let base = NSTemporaryDirectory() + "codepet-2b-svc-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        for a in [["init"], ["config","user.email","t@t.co"], ["config","user.name","t"]] { _ = GitRunner.run(a, in: base) }
        try? "v1".write(toFile: base + "/file.txt", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add","."], in: base)
        _ = GitRunner.run(["commit","-m","init"], in: base)
        return base
    }

    private func currentBranch(_ dir: String) -> String {
        GitRunner.run(["rev-parse","--abbrev-ref","HEAD"], in: dir).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func test_beginGit_createsCodepetBranch() {
        let repo = tempGitRepo()
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "Fix signup")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.branch, "codepet/fix-signup")
        XCTAssertEqual(currentBranch(repo), "codepet/fix-signup")
    }

    func test_commitGit_landsOnBranchNotMain() {
        let repo = tempGitRepo()
        let original = currentBranch(repo)
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        try? "v2".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(CodeCommitService.commitGit(s, files: ["file.txt"], message: "codepet: edit"))
        // The commit is on the codepet branch; the original ref's file is still v1.
        _ = GitRunner.run(["checkout", original], in: repo)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "v1")
    }

    func test_abortGit_restoresOriginalStateAndDeletesBranch() {
        let repo = tempGitRepo()
        let original = currentBranch(repo)
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        try? "dirty".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        CodeCommitService.abortGit(s)
        XCTAssertEqual(currentBranch(repo), original)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "v1")
        let branches = GitRunner.run(["branch"], in: repo).stdout
        XCTAssertFalse(branches.contains("codepet/edit"))
    }

    func test_beginGit_stashesDirtyWorkAndAbortRestoresIt() {
        let repo = tempGitRepo()
        try? "uncommitted".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)  // dirty pre-existing edit
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        XCTAssertTrue(s.stashed)
        CodeCommitService.abortGit(s)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "uncommitted",
                       "pre-existing dirty work must be restored on abort")
    }

    func test_beginGit_returnsNilForNonRepo() {
        let dir = NSTemporaryDirectory() + "codepet-2b-nonrepo-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        XCTAssertNil(CodeCommitService.beginGit(projectPath: dir, taskTitle: "x"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeCommitServiceTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `CodeCommitService` not found.

- [ ] **Step 3: Implement the git path**

Create `codepet/Services/CodeCommitService.swift`:

```swift
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
/// a throwaway branch; non-git projects use a shadow copy (see the shadow path in
/// Task 3). Never merges, pushes, or deploys — only commits to `codepet/<slug>`.
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
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeCommitServiceTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: PASS — 5 git-path tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/CodeCommitService.swift codepetTests/CodeCommitServiceTests.swift
git commit -F - <<'EOF'
feat(coding-agent): CodeCommitService git path — branch/commit/abort (Part 2B)

Isolates a run on a throwaway codepet/<slug> branch off HEAD (stashing any
pre-existing dirty work); commit lands on the branch (never main), abort
hard-resets + deletes the branch + restores the stash. Never merges/pushes.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 3: `CodeCommitService` — shadow path (copy / apply+backup / undo)

**Files:**
- Modify: `codepet/Services/CodeCommitService.swift`
- Test: `codepetTests/CodeCommitServiceTests.swift` (add shadow cases)

**Interfaces:**
- Produces (on `CodeCommitService`):
  - `struct ShadowSession { let projectPath: String; let shadowDir: String; let backupDir: String }`
  - `static func beginShadow(projectPath: String) -> ShadowSession?` — copies the project (excluding `.git`/`node_modules`/`.next`/`build`/`DerivedData`) into a fresh temp `shadowDir`; prepares an empty `backupDir`. The `ClaudeCodeRunner` will run in `shadowDir`.
  - `static func applyShadow(_ s: ShadowSession, acceptedRelPaths: [String]) -> Bool` — for each accepted relative path: back up the real file (if it exists) into `backupDir` (recording new-file paths as tombstones), then copy `shadowDir/<rel>` → `projectPath/<rel>`. Returns true if all copies succeeded.
  - `static func undoShadow(_ s: ShadowSession)` — restore every backed-up file to the real tree; delete files that were newly created (tombstoned).
  - `static func discardShadow(_ s: ShadowSession)` — remove `shadowDir` (+ `backupDir` if not needed).

- [ ] **Step 1: Write the failing tests**

Add to `codepetTests/CodeCommitServiceTests.swift`:

```swift
    private func tempPlainProject() -> String {
        let base = NSTemporaryDirectory() + "codepet-2b-shadow-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base + "/node_modules", withIntermediateDirectories: true)
        try? "orig".write(toFile: base + "/app.txt", atomically: true, encoding: .utf8)
        try? "junk".write(toFile: base + "/node_modules/x.txt", atomically: true, encoding: .utf8)
        return base
    }

    func test_beginShadow_copiesProjectExcludingHeavyDirs() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        XCTAssertEqual(try? String(contentsOfFile: s.shadowDir + "/app.txt", encoding: .utf8), "orig")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.shadowDir + "/node_modules"))
    }

    func test_applyShadow_writesAcceptedFilesToRealTreeWithBackup() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        // Simulate the run editing an existing file + creating a new one in the shadow.
        try? "edited".write(toFile: s.shadowDir + "/app.txt", atomically: true, encoding: .utf8)
        try? "new".write(toFile: s.shadowDir + "/added.txt", atomically: true, encoding: .utf8)

        XCTAssertTrue(CodeCommitService.applyShadow(s, acceptedRelPaths: ["app.txt", "added.txt"]))
        XCTAssertEqual(try? String(contentsOfFile: p + "/app.txt", encoding: .utf8), "edited")
        XCTAssertEqual(try? String(contentsOfFile: p + "/added.txt", encoding: .utf8), "new")
    }

    func test_undoShadow_restoresEditedAndRemovesCreated() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        try? "edited".write(toFile: s.shadowDir + "/app.txt", atomically: true, encoding: .utf8)
        try? "new".write(toFile: s.shadowDir + "/added.txt", atomically: true, encoding: .utf8)
        _ = CodeCommitService.applyShadow(s, acceptedRelPaths: ["app.txt", "added.txt"])

        CodeCommitService.undoShadow(s)
        XCTAssertEqual(try? String(contentsOfFile: p + "/app.txt", encoding: .utf8), "orig",
                       "edited file restored to original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: p + "/added.txt"),
                       "newly-created file removed on undo")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeCommitServiceTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL — `beginShadow`/`applyShadow`/`undoShadow` not found.

- [ ] **Step 3: Implement the shadow path**

Append to `codepet/Services/CodeCommitService.swift` (inside the `enum`):

```swift
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
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeCommitServiceTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: PASS — 8 tests (5 git + 3 shadow).

- [ ] **Step 5: Build + commit**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
git add codepet/Services/CodeCommitService.swift codepetTests/CodeCommitServiceTests.swift
git commit -F - <<'EOF'
feat(coding-agent): CodeCommitService shadow path — copy/apply/backup/undo (Part 2B)

Non-git projects run in a temp shadow copy (heavy dirs excluded); apply copies
accepted files to the real tree after backing up originals (tombstoning new
files); undo restores/removes to the exact pre-apply state. Real tree untouched
until apply.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (Part 2 §2 commit / §4 safety):**
- git path: throwaway `codepet/<slug>` off HEAD, commit on branch (never main), abort deletes branch + restores → Task 2. ✅
- dirty-tree safety → stash/pop in begin/commit/abort (Task 2). ✅
- no-git: shadow copy, apply-on-approve with backup, undo restores → Task 3. ✅
- "never a change you can't instantly undo" → git branch revert + shadow backup/undo, both tested. ✅
- Runner reused unchanged (dir + caps already configurable) → noted; no runner task. ✅
- Approval gate + `ClaudeCodeRunner` invocation + honest-plan fallback + chat UI → **deferred to 2C** (2B ships the primitives 2C orchestrates). Not gaps.

**2. Placeholder scan:** No TBD/TODO; each code step complete; each command has expected output.

**3. Type consistency:** `GitRunner.run(_:in:)`/`GitResult`/`CommitSlug.make(from:)`, `GitSession`, `ShadowSession`, and `beginGit`/`commitGit`/`abortGit`/`beginShadow`/`applyShadow`/`undoShadow`/`discardShadow` are named identically across tasks and tests.

**Deferred (2C):** orchestration (begin → `ClaudeCodeRunner.run` → `FileDiff`s → await Approve/Reject → commit/abort), the `edit_code` verb dispatch + adaptive plan-preview gate, the diff-review chat card, and the honest-plan fallback.
