// codepetTests/CompanyStoreProjectIdentityTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreProjectIdentityTests: XCTestCase {

    /// Task 4 mitigation attempt: hold every `CompanyStore` this class creates so none of
    /// them deallocates before the process exits. `CompanyStore` is a `@MainActor
    /// ObservableObject`, which gives it an isolated deinit, and this suite crashes with
    /// `abort` -> `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED` ->
    /// `swift_task_deinitOnExecutorImpl` -> `CompanyStore.__deallocating_deinit` on every
    /// run, verified fresh against this branch (see the fix-wave report for the full frame).
    /// Deliberately never cleared — the crash is triggered by deallocation, and clearing
    /// this array in `tearDown()` would deallocate everything it holds at exactly the point
    /// this exists to avoid.
    private var retained: [CompanyStore] = []

    /// A real folder, because `linkProject` probes the filesystem. Not a git repo, so the
    /// injected remote reader is what decides whether there is a hint.
    private func makeFolder() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ONE signature. `cloud` defaults empty (PR 1's production state), `forcedRemote`
    /// defaults nil (a temp folder has no git remote, and creating a repo in a test to get
    /// one would be testing git rather than this code), and `forcedRoot` defaults nil too —
    /// so by default the folder looks like it has no git ancestry at all. A test that wants
    /// a remote to actually count as a hint must also say the folder IS the repo root, via
    /// `forcedRoot`; that is what distinguishes a root folder from one merely nested inside
    /// a tracked ancestor.
    ///
    /// The identity map gets its own UserDefaults suite so no test can touch the founder's
    /// real bindings, and an account is set because a bind with nobody signed in is a no-op.
    private func makeStore(cloud: [CloudProject] = [],
                           forcedRemote: String? = nil,
                           forcedRoot: String? = nil) -> CompanyStore {
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        let map = ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test")
        map.account = "co-test"
        let store = CompanyStore(identityMap: map,
                                 remoteURLReader: { _ in forcedRemote },
                                 repoRootReader: { _ in forcedRoot },
                                 knownCloudProjects: cloud)
        retained.append(store)
        return store
    }

    func test_linkingAFolderWithNoHintMintsAndBinds() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore()
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNil(store.pendingProjectMatch)
    }

    func test_relinkingTheSameFolderReusesTheId() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore()
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        let first = store.activeProjectId

        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertEqual(store.activeProjectId, first)
    }

    // The founder must be asked. Until they answer, nothing binds and no scope resolves.
    func test_aProposalWaitsForConfirmation() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let remote = "git@github.com:Acme/Repo.git"
        let store = makeStore(cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "repo",
                                                                                gitRemote: remote),
                                                   displayName: "repo")],
                              forcedRemote: remote,
                              forcedRoot: dir.path)
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

        let remote = "git@github.com:Acme/Repo.git"
        let store = makeStore(cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "repo",
                                                                                gitRemote: remote),
                                                   displayName: "repo")],
                              forcedRemote: remote,
                              forcedRoot: dir.path)
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        store.rejectProjectMatch()

        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNotEqual(store.activeProjectId, "aaa")
        XCTAssertNil(store.pendingProjectMatch)
    }

    // reset() must not leave the outgoing founder's project id visible to the next account.
    func test_resetClearsTheProjectIdAndAnyPendingMatch() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore()
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertNotNil(store.activeProjectId)

        store.reset()
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.pendingProjectMatch)
        XCTAssertNil(store.activeProjectLink)
    }


    // The guard that protects every account-less CompanyStore. Three other test files call
    // linkProject too (CompanyStoreCodeRunTests, ChatModeEngineeringTests's
    // BuildDestinationTests, and CompanyStoreChatTests) and now all inject their own
    // UserDefaults suite, the way `makeStore` above does — CompanyStoreChatTests needs to,
    // since one of its tests DOES call `hydrate` before `linkProject` and would otherwise
    // bind for real. This test does not depend on any of that: it constructs its own
    // no-account store directly and covers the no-account path on its own terms — the case
    // none of those suites exercises, because in every one of them `account` happens to be
    // set (or, before this fix wave, happened to stay nil by accident) rather than proven nil.
    func test_linkingWritesNothingWhileNoAccountIsSet() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        let map = ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test")
        map.account = nil                            // nobody signed in
        let store = CompanyStore(identityMap: map, remoteURLReader: { _ in nil },
                                 repoRootReader: { _ in nil },
                                 knownCloudProjects: [])
        retained.append(store)

        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNil(map.id(forPath: dir.path), "a bind with no account must not land")
        XCTAssertNil(store.activeProjectId,
                     "no disk record backs this id — activeProjectId must not go live on a bind that did not land")
        map.account = "co-test"
        XCTAssertNil(map.id(forPath: dir.path), "and it must not appear once someone signs in")
    }

    // A folder with no git remote must never join an existing project on a folder-name
    // hunch — two unrelated checkouts called `api` are ordinary.
    func test_noRemoteMintsEvenWhenAFolderNameWouldMatch() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let name = dir.lastPathComponent
        let store = makeStore(cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: name,
                                                                                gitRemote: nil),
                                                   displayName: name)],
                              forcedRemote: nil)
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNil(store.pendingProjectMatch)
        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNotEqual(store.activeProjectId, "aaa")
    }

    // The hole the review found: a folder inside a tracked ancestor must not borrow the
    // ancestor's remote and get proposed as the ancestor's project.
    func test_nestedFolderDoesNotBorrowTheAncestorsRemote() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let remote = "git@github.com:Acme/Parent.git"
        let store = makeStore(cloud: [CloudProject(id: "parent",
                                                   hints: ProjectIdentity.hints(folderName: "parent",
                                                                                gitRemote: remote),
                                                   displayName: "parent")],
                              forcedRemote: remote,
                              forcedRoot: "/some/other/ancestor")   // root is NOT this folder
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNil(store.pendingProjectMatch, "a nested folder must not be proposed as its ancestor")
        XCTAssertNotNil(store.activeProjectId)
        XCTAssertNotEqual(store.activeProjectId, "parent")
    }

    func test_repoRootFolderStillProposes() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let remote = "git@github.com:Acme/Repo.git"
        let store = makeStore(cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "repo",
                                                                                gitRemote: remote),
                                                   displayName: "repo")],
                              forcedRemote: remote,
                              forcedRoot: dir.path)                 // root IS this folder
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertEqual(store.pendingProjectMatch?.id, "aaa")
    }

    // The case the other tests structurally cannot see: every test above injects the SAME
    // raw string as both the linked path and `forcedRoot`, so it would pass even if
    // `resolveProjectIdentity` compared two unresolved strings. Real `git rev-parse
    // --show-toplevel` canonicalises symlinks, so this test links via an UNRESOLVED symlink
    // path while `forcedRoot` stands in for what real git would report — the RESOLVED
    // target. If `linkProject` ever stops canonicalising the incoming path once at the top,
    // this regresses to `.mint` (the safe direction, but still a lost hint) rather than
    // proposing.
    func test_symlinkedPathStillMatchesTheResolvedRoot() throws {
        let parent = try makeFolder()
        defer { try? FileManager.default.removeItem(at: parent) }

        let real = parent.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = URL(fileURLWithPath: link.path).resolvingSymlinksInPath().path
        XCTAssertNotEqual(resolved, link.path, "the fixture must actually exercise a symlink")

        let remote = "git@github.com:Acme/Repo.git"
        let store = makeStore(cloud: [CloudProject(id: "aaa",
                                                   hints: ProjectIdentity.hints(folderName: "real",
                                                                                gitRemote: remote),
                                                   displayName: "repo")],
                              forcedRemote: remote,
                              forcedRoot: resolved)   // what real git would report: the RESOLVED path
        store.linkProject(path: link.path, bootstrapClaudeMd: false)   // linked via the unresolved symlink

        XCTAssertEqual(store.pendingProjectMatch?.id, "aaa",
                       "a symlinked path must still be recognised as the repo root once canonicalised")
    }
}
