# Two-Tier Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the founder's team a second memory tier so it stops quoting facts from a repo the founder is not working in, and stops forgetting a repo it has not seen in a while.

**Architecture:** A project gets an opaque id minted once and stored in the cloud; `DecisionEntry` gains an optional `scope` holding that id, where `nil` means shared. `ChatContext.compose` composes two decision blocks — shared, plus the open project's — instead of one. Detection proposes a scope from two signals and the founder confirms; disagreement always falls back to shared.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Firestore under `companies/{uid}`, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-21-two-tier-memory-design.md` (revised 2026-08-22)

## Global Constraints

- **Deployment target 26.2.** Not 13 — an older CLAUDE.md said 13 and it was wrong.
- **`nil` scope means shared, always.** Every document written before this feature must decode and behave exactly as it does today. No backfill, no version flag.
- **Uncertain always resolves to shared.** Never to a repo. Calling a fact shared makes it merely surplus and visible; calling it repo-scoped makes it vanish silently from every other repo.
- **New `.swift` files need no project-file edit.** `PBXFileSystemSynchronizedRootGroup` — target membership follows the folder on disk.
- **Run tests per-suite with `-only-testing:`.** The XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates; a whole-target run exits 65 on a clean checkout and tells you nothing. `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/<SuiteName>`
- **Pure types over stores.** `Decisions`, `ChatContext`, `MemoryDigest` and everything added here stay pure and non-`@MainActor` so they are testable without touching a founder's real data.
- **Every guard gets a test that goes red when the guard is deleted.** A test that passes with and without the code it protects is not protecting anything.
- **Do not commit to `main`.** Branch `feat/two-tier-memory` off `main`, PR into `main`.

---

## File Structure

**PR 1 — Project identity** (this plan covers PR 1 in full; later PRs are scoped at the end)

- Create `codepet/Models/ProjectIdentity.swift` — pure. Mints ids, holds the matching-hint value type, and decides whether a cloud project matches a local folder. No filesystem, no network, no `@MainActor`.
- Create `codepet/Managers/ProjectIdentityMap.swift` — the per-machine path→id map over UserDefaults, with an injectable suite so a test never touches the real map.
- Modify `codepet/Services/GitRunner.swift` — add a remote-URL reader on top of the existing generic `run(_:in:)`.
- Modify `codepet/Managers/CompanyStore.swift` — `linkProject` resolves an id; a new published `activeProjectId`.
- Create `codepetTests/ProjectIdentityTests.swift`
- Create `codepetTests/ProjectIdentityMapTests.swift`

Identity is split from the map on purpose: the decisions worth proving (does this folder match that project? what happens with no remote?) are pure, and the storage is not.

---

## Task 1: Mint and normalise a project id

**Files:**
- Create: `codepet/Models/ProjectIdentity.swift`
- Test: `codepetTests/ProjectIdentityTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct ProjectHints: Codable, Hashable, Sendable` with `var gitRemote: String?` and `var folderName: String?`
  - `enum ProjectIdentity` with:
    - `static func mint() -> String`
    - `static func normalizeRemote(_ raw: String?) -> String?`
    - `static func hints(folderName: String?, gitRemote: String?) -> ProjectHints`

- [ ] **Step 1: Write the failing tests**

```swift
// codepetTests/ProjectIdentityTests.swift
import XCTest
@testable import codepet

final class ProjectIdentityTests: XCTestCase {

    // An id must carry nothing about the machine. If it ever becomes path-derived again,
    // repo-tier facts orphan on a second machine — the failure the whole design removes.
    func test_mint_producesOpaqueDistinctIds() {
        let a = ProjectIdentity.mint()
        let b = ProjectIdentity.mint()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 32)
        XCTAssertFalse(a.contains("/"))
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }

    // The same repo reached over ssh and https is the same repo. Without this, a founder
    // who clones with a different protocol on their second machine gets a second project.
    func test_normalizeRemote_sshAndHttpsAgree() {
        let ssh = ProjectIdentity.normalizeRemote("git@github.com:TruongGiang2000/PouchTaper.git")
        let https = ProjectIdentity.normalizeRemote("https://github.com/TruongGiang2000/PouchTaper.git")
        XCTAssertEqual(ssh, "github.com/truonggiang2000/pouchtaper")
        XCTAssertEqual(ssh, https)
    }

    func test_normalizeRemote_ignoresTrailingSlashAndCase() {
        XCTAssertEqual(ProjectIdentity.normalizeRemote("https://GitHub.com/Acme/Repo/"),
                       "github.com/acme/repo")
    }

    // Blank and nil are the same absence. A hint of "" must never match another "".
    func test_normalizeRemote_blankIsNil() {
        XCTAssertNil(ProjectIdentity.normalizeRemote(nil))
        XCTAssertNil(ProjectIdentity.normalizeRemote("   "))
    }

    func test_hints_normalizesRemoteAndKeepsFolderName() {
        let h = ProjectIdentity.hints(folderName: "codepet",
                                      gitRemote: "git@github.com:Acme/Codepet.git")
        XCTAssertEqual(h.folderName, "codepet")
        XCTAssertEqual(h.gitRemote, "github.com/acme/codepet")
    }

    func test_hints_blankFolderNameIsNil() {
        XCTAssertNil(ProjectIdentity.hints(folderName: "  ", gitRemote: nil).folderName)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityTests`
Expected: FAIL — `cannot find 'ProjectIdentity' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/ProjectIdentity.swift
import Foundation

/// The hints that let a folder linked on one machine be recognised as a project the
/// founder already has, rather than minted as a second one.
///
/// Both are hints and neither is an identity. `gitRemote` is strong enough to propose a
/// match; `folderName` is only ever shown to the founder so they can tell two candidates
/// apart. Nothing here is trusted enough to merge two projects without being asked.
struct ProjectHints: Codable, Hashable, Sendable {
    var gitRemote: String?
    var folderName: String?
}

/// A project's identity — minted once, opaque forever.
///
/// Deliberately carries nothing derived from the machine. An absolute path, or any hash
/// of one, would put the same repo under two different keys on two machines and silently
/// orphan every fact scoped to it. That was the first draft of the design and it was
/// wrong; see §4.1 and §4.3 of the spec.
enum ProjectIdentity {

    /// A fresh id. 32 lowercase hex characters — a UUID with its dashes removed, which is
    /// safe as a Firestore document ID (no `/`, no leading `.`, well under the length cap).
    static func mint() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// A git remote reduced to the part that identifies the repository, so the same repo
    /// cloned over ssh on one machine and https on another compares equal.
    ///
    /// Drops the scheme, any `user@`, the `.git` suffix, a trailing slash, and case. What
    /// survives is `host/owner/name`. Returns nil for nil or blank — an absent hint must
    /// never match another absent hint.
    static func normalizeRemote(_ raw: String?) -> String? {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // scp-style (`git@host:owner/name`) has no scheme and uses `:` as the separator.
        if let at = s.firstIndex(of: "@"), !s.contains("://") {
            s = String(s[s.index(after: at)...])
            if let colon = s.firstIndex(of: ":") {
                s.replaceSubrange(colon...colon, with: "/")
            }
        } else if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
            // A URL form can still carry credentials before the host.
            if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        }

        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        s = s.lowercased()
        return s.isEmpty ? nil : s
    }

    /// Package what is known about a folder. Blank strings become nil so an empty hint is
    /// never mistaken for a present one.
    static func hints(folderName: String?, gitRemote: String?) -> ProjectHints {
        let name = (folderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectHints(gitRemote: normalizeRemote(gitRemote),
                            folderName: name.isEmpty ? nil : name)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ProjectIdentity.swift codepetTests/ProjectIdentityTests.swift
git commit -m "feat(memory): mint an opaque project id, and normalise the git remote that matches it

A project's identity has to survive the founder opening their other laptop. An
absolute path does not, and neither does a hash of one — the same repo lands under
two keys and every fact scoped to it is silently orphaned. So the id is minted once
and carries nothing about the machine.

normalizeRemote reduces a remote to host/owner/name so an ssh clone on one machine
and an https clone on another compare equal. Without it, protocol choice alone would
split one project in two."
```

---

## Task 2: Read the git remote

**Files:**
- Modify: `codepet/Services/GitRunner.swift`
- Test: `codepetTests/GitRemoteTests.swift`

**Interfaces:**
- Consumes: `GitRunner.run(_ args: [String], in dir: String) -> GitResult` (already exists).
- Produces: `static func remoteURL(in dir: String) -> String?` on `GitRunner`.

- [ ] **Step 1: Read the existing file first**

Run: `sed -n 1,40p codepet/Services/GitRunner.swift`
You need `GitResult`'s actual property names before writing anything — do not guess them. The implementation in step 3 uses `.stdout` and a success flag; correct them to whatever the type really exposes.

- [ ] **Step 2: Write the failing tests**

```swift
// codepetTests/GitRemoteTests.swift
import XCTest
@testable import codepet

final class GitRemoteTests: XCTestCase {

    /// A directory that is definitely not a git repo. Uses a temp dir rather than a
    /// hardcoded path so the test says the same thing on any machine.
    func test_remoteURL_nilOutsideAGitRepo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(GitRunner.remoteURL(in: dir.path))
    }

    func test_remoteURL_nilForAMissingDirectory() {
        XCTAssertNil(GitRunner.remoteURL(in: "/nope/definitely/not/here"))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/GitRemoteTests`
Expected: FAIL — `type 'GitRunner' has no member 'remoteURL'`.

- [ ] **Step 4: Write the implementation**

Append to `codepet/Services/GitRunner.swift`, inside the existing `GitRunner` type:

```swift
    /// The `origin` remote's URL, or nil when there isn't one.
    ///
    /// A hint for matching a folder to a project the founder already has (see
    /// `ProjectIdentity`), never an identity on its own — a fork, a re-pointed remote, and
    /// two clones of one upstream all disagree with it in different directions.
    ///
    /// Nil rather than throwing on every failure: not a repo, no remote, git absent, path
    /// gone. A missing hint is an ordinary outcome here, and every caller treats it the
    /// same way — fall back to asking the founder.
    static func remoteURL(in dir: String) -> String? {
        let result = run(["remote", "get-url", "origin"], in: dir)
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
```

If `GitResult` exposes an exit code or success flag, gate on it before reading `stdout` — a non-zero exit with text on stdout must still return nil.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/GitRemoteTests`
Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/GitRunner.swift codepetTests/GitRemoteTests.swift
git commit -m "feat(memory): read the origin remote as a project-matching hint

Nil on every failure rather than throwing — not a repo, no remote, git missing, path
gone. A folder with no remote is an ordinary case, not an error, and every caller
handles it the same way: ask the founder instead of guessing."
```

---

## Task 3: The per-machine path→id map

**Files:**
- Create: `codepet/Managers/ProjectIdentityMap.swift`
- Test: `codepetTests/ProjectIdentityMapTests.swift`

**Interfaces:**
- Consumes: `ProjectIdentity.mint()`.
- Produces: `final class ProjectIdentityMap` with
  - `init(defaults: UserDefaults = .standard, key: String = "cp_project_ids_v1")`
  - `func id(forPath path: String) -> String?`
  - `func bind(path: String, to id: String)`
  - `func paths(for id: String) -> [String]`
  - `func resetAll()`
  - `func reload()`

- [ ] **Step 1: Write the failing tests**

```swift
// codepetTests/ProjectIdentityMapTests.swift
import XCTest
@testable import codepet

final class ProjectIdentityMapTests: XCTestCase {

    /// Its own suite, never `.standard`. A test that wrote to the real key could have its
    /// cleanup clobbered by a running app — i.e. eat the founder's real project bindings.
    private func makeMap() -> (ProjectIdentityMap, UserDefaults, String) {
        let name = "cp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test"), defaults, name)
    }

    func test_unknownPathHasNoId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        XCTAssertNil(map.id(forPath: "/Users/a/work/codepet"))
    }

    func test_bindThenLookup() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
    }

    // The whole point of the indirection: one project, two machines, two paths, one id.
    // If this ever fails, repo-tier facts have gone back to being machine-local.
    func test_twoPathsCanShareOneId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        map.bind(path: "/Users/b/src/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
        XCTAssertEqual(map.id(forPath: "/Users/b/src/codepet"), id)
        XCTAssertEqual(map.paths(for: id).sorted(),
                       ["/Users/a/work/codepet", "/Users/b/src/codepet"])
    }

    func test_rebindingAPathReplacesItsId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let first = ProjectIdentity.mint(), second = ProjectIdentity.mint()
        map.bind(path: "/p", to: first)
        map.bind(path: "/p", to: second)
        XCTAssertEqual(map.id(forPath: "/p"), second)
        XCTAssertEqual(map.paths(for: first), [])
    }

    func test_bindingSurvivesReload() {
        let (map, defaults, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/p", to: id)

        let fresh = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        XCTAssertEqual(fresh.id(forPath: "/p"), id)
    }

    func test_resetAllClearsEverything() {
        let (map, defaults, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        map.bind(path: "/p", to: ProjectIdentity.mint())
        map.resetAll()
        XCTAssertNil(map.id(forPath: "/p"))

        let fresh = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        XCTAssertNil(fresh.id(forPath: "/p"))
    }

    func test_blankPathIsIgnored() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        map.bind(path: "   ", to: ProjectIdentity.mint())
        XCTAssertNil(map.id(forPath: "   "))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityMapTests`
Expected: FAIL — `cannot find 'ProjectIdentityMap' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Managers/ProjectIdentityMap.swift
import Foundation
import os

/// This machine's map from a local folder path to a project id.
///
/// The path stays here and never reaches Firestore: it names a location on one machine and
/// means nothing on another. The id is what travels, and it is what `DecisionEntry.scope`
/// stores — which is the whole reason this indirection exists.
///
/// `defaults` and `key` are injectable ONLY so a test can point an instance at its own
/// suite. The app always uses `.standard` with `cp_project_ids_v1`; a test writing there
/// could have its cleanup clobbered by a running app and eat real bindings.
@MainActor
final class ProjectIdentityMap {

    private let logger = Logger(subsystem: "app.murror.codepet", category: "ProjectIdentity")
    private let defaults: UserDefaults
    private let key: String

    /// path → id. Many paths may point at one id; that is the supported case, not an edge.
    private var pathToId: [String: String] = [:]

    init(defaults: UserDefaults = .standard, key: String = "cp_project_ids_v1") {
        self.defaults = defaults
        self.key = key
        load()
    }

    func id(forPath path: String) -> String? {
        pathToId[normalize(path)]
    }

    /// Bind a path to a project id, replacing any previous binding for that path.
    ///
    /// Rebinding is a real operation: a founder who moves a folder, or who corrects a
    /// wrong match, needs the old binding gone rather than kept alongside the new one.
    func bind(path: String, to id: String) {
        let p = normalize(path)
        let i = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !i.isEmpty else { return }
        pathToId[p] = i
        save()
        logger.info("Bound a local folder to project \(i, privacy: .public)")
    }

    /// Every local path currently bound to this id. Sorted for a stable read.
    func paths(for id: String) -> [String] {
        pathToId.filter { $0.value == id }.keys.sorted()
    }

    /// Called on account switch. A different founder's bindings are not this founder's.
    func resetAll() {
        pathToId = [:]
        defaults.removeObject(forKey: key)
    }

    /// Re-hydrate from the (account-swapped) key. Clears first so a fresh account starts
    /// empty. Mirrors `PetMemoryStore.reload()`.
    func reload() {
        pathToId = [:]
        load()
    }

    // MARK: - Private

    /// Trailing slashes only. Deliberately NOT resolving symlinks or case: that would need
    /// the filesystem, and this type stays answerable without one.
    private func normalize(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        pathToId = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pathToId) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityMapTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/ProjectIdentityMap.swift codepetTests/ProjectIdentityMapTests.swift
git commit -m "feat(memory): keep the path->id map on the machine, so the id can travel

The path names a location on one machine; the id is what DecisionEntry.scope will
store and what has to mean the same thing everywhere. Many paths mapping to one id is
the supported case — that is the whole reason the indirection exists rather than
scoping facts by path directly.

Injectable defaults for the same reason PetMemoryStore has them: a test writing to the
real key could have its cleanup clobbered by a running app and eat real bindings."
```

---

## Task 4: Decide whether a folder matches a project the founder already has

**Files:**
- Modify: `codepet/Models/ProjectIdentity.swift`
- Test: `codepetTests/ProjectIdentityTests.swift`

**Interfaces:**
- Consumes: `ProjectHints`, `ProjectIdentity.hints(folderName:gitRemote:)`.
- Produces:
  - `struct CloudProject: Codable, Hashable, Sendable` with `let id: String`, `var hints: ProjectHints`, `var displayName: String`
  - `enum ProjectMatch: Equatable` with cases `bound(String)`, `propose(String, reason: String)`, `mint`
  - `static func match(localId: String?, hints: ProjectHints, against: [CloudProject]) -> ProjectMatch`

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/ProjectIdentityTests.swift`:

```swift
extension ProjectIdentityTests {

    private func cloud(_ id: String, remote: String?, name: String) -> CloudProject {
        CloudProject(id: id,
                     hints: ProjectIdentity.hints(folderName: name, gitRemote: remote),
                     displayName: name)
    }

    // Already bound on this machine: no question to ask, no hint to consult.
    func test_match_alreadyBoundWinsOverEverything() {
        let projects = [cloud("aaa", remote: "git@github.com:Acme/Repo.git", name: "repo")]
        let m = ProjectIdentity.match(localId: "zzz",
                                      hints: ProjectIdentity.hints(folderName: "repo",
                                                                   gitRemote: "git@github.com:Acme/Repo.git"),
                                      against: projects)
        XCTAssertEqual(m, .bound("zzz"))
    }

    // A remote match is PROPOSED, never applied. Deleting the propose case and returning
    // .bound here is exactly the silent mis-merge this guard exists to stop.
    func test_match_remoteHitIsProposedNotAdopted() {
        let projects = [cloud("aaa", remote: "https://github.com/Acme/Repo.git", name: "repo")]
        let m = ProjectIdentity.match(localId: nil,
                                      hints: ProjectIdentity.hints(folderName: "repo-clone",
                                                                   gitRemote: "git@github.com:Acme/Repo.git"),
                                      against: projects)
        guard case .propose(let id, _) = m else { return XCTFail("expected a proposal, got \(m)") }
        XCTAssertEqual(id, "aaa")
    }

    func test_match_noRemoteMintsRatherThanGuessingFromFolderName() {
        let projects = [cloud("aaa", remote: "git@github.com:Acme/Repo.git", name: "repo")]
        let m = ProjectIdentity.match(localId: nil,
                                      hints: ProjectIdentity.hints(folderName: "repo", gitRemote: nil),
                                      against: projects)
        XCTAssertEqual(m, .mint)
    }

    func test_match_differentRemoteMints() {
        let projects = [cloud("aaa", remote: "git@github.com:Acme/Repo.git", name: "repo")]
        let m = ProjectIdentity.match(localId: nil,
                                      hints: ProjectIdentity.hints(folderName: "other",
                                                                   gitRemote: "git@github.com:Acme/Other.git"),
                                      against: projects)
        XCTAssertEqual(m, .mint)
    }

    // Two cloud projects sharing a remote is ambiguous, and ambiguity is not a proposal.
    func test_match_ambiguousRemoteMints() {
        let projects = [cloud("aaa", remote: "git@github.com:Acme/Repo.git", name: "one"),
                        cloud("bbb", remote: "https://github.com/Acme/Repo", name: "two")]
        let m = ProjectIdentity.match(localId: nil,
                                      hints: ProjectIdentity.hints(folderName: "one",
                                                                   gitRemote: "git@github.com:Acme/Repo.git"),
                                      against: projects)
        XCTAssertEqual(m, .mint)
    }

    func test_match_noCloudProjectsMints() {
        let m = ProjectIdentity.match(localId: nil,
                                      hints: ProjectIdentity.hints(folderName: "repo",
                                                                   gitRemote: "git@github.com:Acme/Repo.git"),
                                      against: [])
        XCTAssertEqual(m, .mint)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityTests`
Expected: FAIL — `cannot find 'CloudProject' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `codepet/Models/ProjectIdentity.swift`:

```swift
/// A project as the cloud holds it. The local path is deliberately absent — it lives in
/// `ProjectIdentityMap` because it describes one machine.
struct CloudProject: Codable, Hashable, Sendable {
    let id: String
    var hints: ProjectHints
    var displayName: String
}

/// What to do with a folder the founder just linked.
enum ProjectMatch: Equatable {
    /// This machine already knows the folder. Nothing to ask.
    case bound(String)
    /// A hint says this is an existing project. The founder confirms before anything binds.
    case propose(String, reason: String)
    /// No usable hint, or an ambiguous one. Mint a new id.
    case mint
}

extension ProjectIdentity {

    /// Resolve a linked folder to a project.
    ///
    /// Pure, so the interesting cases — no remote, wrong remote, two projects with the
    /// same remote — are all provable without a folder, a network, or a founder.
    ///
    /// A remote hit is `.propose`, never `.bound`. Adopting it silently would attach one
    /// repo's memory to another with nothing on screen, and a duplicate project is the
    /// cheaper mistake: it is visible, and it can be merged later. Wrongly merged memory
    /// is neither.
    ///
    /// `folderName` never decides anything. Two unrelated checkouts called `api` are
    /// ordinary, and a hint that common is not evidence — it exists only so the founder
    /// can tell two candidates apart when asked.
    static func match(localId: String?,
                      hints: ProjectHints,
                      against projects: [CloudProject]) -> ProjectMatch {
        if let bound = localId?.trimmingCharacters(in: .whitespacesAndNewlines), !bound.isEmpty {
            return .bound(bound)
        }
        guard let remote = hints.gitRemote else { return .mint }

        let hits = projects.filter { $0.hints.gitRemote == remote }
        // Exactly one, or nothing to say. Two projects claiming one remote is a state the
        // founder has to resolve, and picking either would be a coin toss with their memory.
        guard hits.count == 1, let hit = hits.first else { return .mint }

        return .propose(hit.id, reason: remote)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityTests`
Expected: PASS, 12 tests (6 from Task 1, 6 here).

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ProjectIdentity.swift codepetTests/ProjectIdentityTests.swift
git commit -m "feat(memory): propose a project match, never adopt one

A matching git remote returns .propose, not .bound. Adopting it silently would attach
one repo's memory to another with nothing on screen — and a duplicate project is the
cheaper mistake of the two: it is visible and it can be merged, where wrongly merged
memory is neither.

Two cloud projects sharing a remote mints instead of picking one. Choosing either
would be a coin toss with the founder's facts. folderName never decides anything: two
unrelated checkouts called api are ordinary, so it is shown to the founder rather than
acted on."
```

---

## Task 5: `linkProject` resolves an id

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (`linkProject` at `:558`; new published property near `activeProjectLink` at `:42`)
- Test: `codepetTests/CompanyStoreProjectIdentityTests.swift`

**Interfaces:**
- Consumes: `ProjectIdentityMap`, `ProjectIdentity.match(localId:hints:against:)`, `GitRunner.remoteURL(in:)`.
- Produces on `CompanyStore`:
  - `@Published private(set) var activeProjectId: String?`
  - `@Published private(set) var pendingProjectMatch: (id: String, reason: String)?`
  - `func confirmProjectMatch()` / `func rejectProjectMatch()`

- [ ] **Step 1: Read the surrounding code first**

Run:
```
sed -n 36,50p codepet/Managers/CompanyStore.swift
sed -n 200,250p codepet/Managers/CompanyStore.swift
sed -n 550,580p codepet/Managers/CompanyStore.swift
sed -n 2315,2330p codepet/Managers/CompanyStore.swift
```
You need the real initialiser shape (it takes injected closures), and the sign-out path that clears `activeProjectLink`. Match those patterns rather than inventing new ones. Note that `CompanyStore` is testable **through its injected closures** — add an injected `cloudProjects: () async -> [CloudProject]` rather than reaching for Firestore directly.

- [ ] **Step 2: Write the failing tests**

```swift
// codepetTests/CompanyStoreProjectIdentityTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreProjectIdentityTests: XCTestCase {

    /// A real folder, because `linkProject` probes the filesystem. Not a git repo, so
    /// `GitRunner.remoteURL` returns nil and the no-hint path is what runs.
    private func makeFolder() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_linkingAFolderWithNoHintMintsAndBinds() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(cloudProjects: [])
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNil(store.pendingProjectMatch)
    }

    func test_relinkingTheSameFolderReusesTheId() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(cloudProjects: [])
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        let first = store.activeProjectId

        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertEqual(store.activeProjectId, first)
    }

    // The founder must be asked. Until they answer, nothing is bound and no scope resolves.
    func test_aProposalWaitsForConfirmation() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(cloudProjects: [], forcedRemote: "git@github.com:Acme/Repo.git",
                              cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "repo",
                                                                                gitRemote: "git@github.com:Acme/Repo.git"),
                                                   displayName: "repo")])
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertEqual(store.pendingProjectMatch?.id, "aaa")
        XCTAssertNil(store.activeProjectId, "nothing may resolve while the founder has not answered")

        store.confirmProjectMatch()
        XCTAssertEqual(store.activeProjectId, "aaa")
        XCTAssertNil(store.pendingProjectMatch)
    }

    func test_rejectingAProposalMintsInstead() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(cloudProjects: [], forcedRemote: "git@github.com:Acme/Repo.git",
                              cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "repo",
                                                                                gitRemote: "git@github.com:Acme/Repo.git"),
                                                   displayName: "repo")])
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        store.rejectProjectMatch()

        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNotEqual(store.activeProjectId, "aaa")
        XCTAssertNil(store.pendingProjectMatch)
    }
}
```

`makeStore(cloudProjects:forcedRemote:cloud:)` is a helper you write in this file over `CompanyStore`'s existing injected-closure initialiser, pointing `ProjectIdentityMap` at a per-test suite. Read step 1's output to get the initialiser's real parameters — do not guess them. `forcedRemote` exists because a temp folder has no git remote; inject the remote reader rather than creating a repo in a test.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CompanyStoreProjectIdentityTests`
Expected: FAIL — `value of type 'CompanyStore' has no member 'activeProjectId'`.

- [ ] **Step 4: Write the implementation**

In `CompanyStore`, beside `activeProjectLink`:

```swift
    /// The open project's id — what `DecisionEntry.scope` will compare against once the
    /// repo tier lands. Nil while nothing is linked, and deliberately nil while a match is
    /// waiting on the founder: a scope resolved from an unconfirmed guess is the silent
    /// mis-attachment this whole flow exists to prevent.
    @Published private(set) var activeProjectId: String?

    /// A proposed match the founder has not answered yet. `reason` is the normalised remote
    /// that produced it, shown so they can see WHY it was proposed rather than being asked
    /// to trust it.
    @Published private(set) var pendingProjectMatch: (id: String, reason: String)?
```

Then in `linkProject`, after `activeProjectLink = link`:

```swift
        resolveProjectIdentity(for: link)
```

And the resolution itself:

```swift
    /// Resolve a linked folder to a project id: reuse this machine's binding, propose a
    /// remote match for the founder to confirm, or mint.
    ///
    /// `.propose` leaves `activeProjectId` nil on purpose. Everything downstream reads that
    /// property, so an unanswered proposal cannot scope a fact by accident.
    private func resolveProjectIdentity(for link: ProjectLink) {
        let hints = ProjectIdentity.hints(folderName: URL(fileURLWithPath: link.path).lastPathComponent,
                                          gitRemote: link.isGitRepo ? remoteURLReader(link.path) : nil)
        switch ProjectIdentity.match(localId: identityMap.id(forPath: link.path),
                                     hints: hints,
                                     against: knownCloudProjects) {
        case .bound(let id):
            pendingProjectMatch = nil
            activeProjectId = id
        case .propose(let id, let reason):
            activeProjectId = nil
            pendingProjectMatch = (id: id, reason: reason)
        case .mint:
            pendingProjectMatch = nil
            adopt(id: ProjectIdentity.mint(), for: link.path)
        }
    }

    /// The founder said yes to the proposal.
    func confirmProjectMatch() {
        guard let pending = pendingProjectMatch, let path = activeProjectLink?.path else { return }
        pendingProjectMatch = nil
        adopt(id: pending.id, for: path)
    }

    /// The founder said no — this is a different project, so it gets its own id.
    func rejectProjectMatch() {
        guard let path = activeProjectLink?.path else { return }
        pendingProjectMatch = nil
        adopt(id: ProjectIdentity.mint(), for: path)
    }

    private func adopt(id: String, for path: String) {
        identityMap.bind(path: path, to: id)
        activeProjectId = id
    }
```

Add stored properties `identityMap`, `remoteURLReader` and `knownCloudProjects` to the initialiser following the file's existing injection pattern — `remoteURLReader` defaults to `GitRunner.remoteURL(in:)`. Clear `activeProjectId` and `pendingProjectMatch` alongside `activeProjectLink` at `:2324`, and call `identityMap.reload()` wherever `PetMemoryStore.shared.reload()` is called on account switch.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CompanyStoreProjectIdentityTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Run the neighbouring suites**

Run each and confirm no regression:
```
xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityTests
xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/ProjectIdentityMapTests
xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/GitRemoteTests
```

- [ ] **Step 7: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreProjectIdentityTests.swift
git commit -m "feat(memory): resolve a linked folder to a project id, asking when unsure

activeProjectId stays nil while a proposal is unanswered. Everything downstream reads
that property, so an unconfirmed guess cannot scope a fact by accident — the guard is
the nil, not a flag somebody has to remember to check.

pendingProjectMatch carries the normalised remote that produced it, so the founder is
shown why the match was proposed instead of being asked to trust it. Rejecting mints a
fresh id rather than leaving the folder unresolved."
```

---

## Later PRs (scoped, not yet planned)

Each gets its own plan, written after the PR before it merges — the spec's §9 order.

- **PR 2 — `DecisionEntry.scope` + `ProjectStore` cloud sync + two-block grounding.** Spec §4.1, §4.2, §5, §6. One PR for the reason §4.2 gives.
- **PR 3 — per-tier budget (18 shared / 12 per repo) + the eviction notice.** Spec §7.
- **PR 4 — the 280-character statement ceiling, rejecting rather than clipping.** Spec §8.
- **PR 5 — read the repo's `CLAUDE.md` into grounding.** Spec §6.1. `ProjectLink.hasClaudeMd` is already the probe.

---

## Self-Review

**Spec coverage of PR 1 (§4.3, §5.2):** id minting → Task 1. Remote hint → Task 2. Per-machine path→id map → Task 3. Match-with-confirmation, and mint when there is no usable hint → Task 4. `activeProjectLink` as the anchor, plus the founder-facing confirm/reject → Task 5. §4.3's cloud document *write* is deliberately in PR 2, where `ProjectStore` sync lands; PR 1 reads a `knownCloudProjects` list that is empty until then, so Task 5's `.mint` path is the only one that runs in production on day one. That is intentional and harmless — an id minted now is the id forever.

**Spec tests placed:** "same project, two paths, one id" → Task 3. "proposed, not adopted" → Task 4 and Task 5. "no remote, no confirmation → new id" → Task 4. The remaining §10 tests belong to PR 2–4 and are listed there.

**Type consistency:** `ProjectHints`, `CloudProject`, `ProjectMatch` are defined in Tasks 1 and 4 and used with those exact names and cases in Task 5. `ProjectIdentityMap.id(forPath:)` and `bind(path:to:)` match between Tasks 3 and 5. `GitRunner.remoteURL(in:)` matches between Tasks 2 and 5.

**Known soft spot:** Tasks 2 and 5 begin by reading real code (`GitResult`'s properties, `CompanyStore`'s initialiser) rather than asserting their shape. Those are the two places this plan could not pin down without inventing names, so it says so instead of guessing.
