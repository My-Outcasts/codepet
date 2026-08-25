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
