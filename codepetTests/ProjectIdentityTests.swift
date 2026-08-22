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
