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
