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
