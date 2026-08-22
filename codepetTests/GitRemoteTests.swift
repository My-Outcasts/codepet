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

    // THE test the guard exists for. A non-zero exit that still wrote to stdout must yield
    // nil. Delete `guard result.ok` and this is the test that goes red — the other two
    // cannot, because real git writes nothing to stdout when it fails.
    func test_remoteURL_nilWhenTheCommandFailsEvenWithStdout() {
        let failed = GitResult(stdout: "https://example.com/not-real.git\n",
                               stderr: "fatal: something went wrong", exitCode: 128)
        XCTAssertNil(GitRunner.remoteURL(in: "/anywhere", run: { _, _ in failed }))
    }

    func test_remoteURL_returnsTheTrimmedURLOnSuccess() {
        let ok = GitResult(stdout: "  git@github.com:Acme/Repo.git\n  ",
                           stderr: "", exitCode: 0)
        XCTAssertEqual(GitRunner.remoteURL(in: "/anywhere", run: { _, _ in ok }),
                       "git@github.com:Acme/Repo.git")
    }

    func test_remoteURL_nilOnSuccessWithBlankStdout() {
        let blank = GitResult(stdout: "   \n", stderr: "", exitCode: 0)
        XCTAssertNil(GitRunner.remoteURL(in: "/anywhere", run: { _, _ in blank }))
    }
}
