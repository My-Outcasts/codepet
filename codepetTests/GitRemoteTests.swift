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

    // MARK: - repoRoot

    /// A directory that is definitely not a git repo. Same reasoning as
    /// `test_remoteURL_nilOutsideAGitRepo`: a temp dir rather than a hardcoded path so the
    /// test says the same thing on any machine, and so it can never accidentally sit inside
    /// this checkout's own `.git` ancestry.
    func test_repoRoot_nilOutsideAGitRepo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(GitRunner.repoRoot(in: dir.path))
    }

    func test_repoRoot_nilForAMissingDirectory() {
        XCTAssertNil(GitRunner.repoRoot(in: "/nope/definitely/not/here"))
    }

    // THE test the guard exists for, mirroring `test_remoteURL_nilWhenTheCommandFailsEvenWithStdout`:
    // a non-zero exit that still wrote to stdout must yield nil.
    func test_repoRoot_nilWhenTheCommandFailsEvenWithStdout() {
        let failed = GitResult(stdout: "/some/path\n",
                               stderr: "fatal: not a git repository", exitCode: 128)
        XCTAssertNil(GitRunner.repoRoot(in: "/anywhere", run: { _, _ in failed }))
    }

    func test_repoRoot_returnsTheTrimmedPathOnSuccess() {
        let ok = GitResult(stdout: "  /Users/a/work/codepet\n  ",
                           stderr: "", exitCode: 0)
        XCTAssertEqual(GitRunner.repoRoot(in: "/anywhere", run: { _, _ in ok }),
                       "/Users/a/work/codepet")
    }

    func test_repoRoot_nilOnSuccessWithBlankStdout() {
        let blank = GitResult(stdout: "   \n", stderr: "", exitCode: 0)
        XCTAssertNil(GitRunner.repoRoot(in: "/anywhere", run: { _, _ in blank }))
    }
}
