// codepetTests/CompanyStoreProjectIdentityTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreProjectIdentityTests: XCTestCase {

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
        return CompanyStore(identityMap: map,
                            remoteURLReader: { _ in forcedRemote },
                            repoRootReader: { _ in forcedRoot },
                            knownCloudProjects: cloud)
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


    // The guard that protects every EXISTING CompanyStore suite. Four test files already
    // call linkProject (CompanyStoreCodeRunTests, ChatModeEngineeringTests,
    // CompanyStoreChatTests) and none of them injects an identity map, so each gets the
    // production default pointed at UserDefaults.standard. Nothing lands there only because
    // those tests never hydrate, so `account` is nil and `bind` no-ops. That is luck until
    // it is a test — this is the test.
    func test_linkingWritesNothingWhileNoAccountIsSet() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        let map = ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test")
        map.account = nil                            // nobody signed in
        let store = CompanyStore(identityMap: map, remoteURLReader: { _ in nil },
                                 repoRootReader: { _ in nil },
                                 knownCloudProjects: [])

        store.linkProject(path: dir.path, bootstrapClaudeMd: false)

        XCTAssertNil(map.id(forPath: dir.path), "a bind with no account must not land")
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
}
