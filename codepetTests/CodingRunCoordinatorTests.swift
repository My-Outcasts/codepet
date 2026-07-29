import XCTest
@testable import codepet

/// A fake runner that simulates claude by writing `edits` (relPath → contents) into
/// the working dir, then reporting diffs for them (or a failure).
private final class FakeRunner: CodeRunning {
    let edits: [String: String]
    let failure: String?
    init(edits: [String: String] = [:], failure: String? = nil) { self.edits = edits; self.failure = failure }
    func run(prompt: String, workingDir: String) async -> CodeRunOutcome {
        if let failure { return CodeRunOutcome(diffs: [], failure: failure) }
        var diffs: [ClaudeCodeRunner.FileDiff] = []
        for (rel, contents) in edits {
            let url = URL(fileURLWithPath: workingDir).appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            try? contents.write(to: url, atomically: true, encoding: .utf8)
            diffs.append(ClaudeCodeRunner.FileDiff(path: url.path, isNewFile: isNew, lines: []))
        }
        return CodeRunOutcome(diffs: diffs, failure: nil)
    }
}

@MainActor
final class CodingRunCoordinatorTests: XCTestCase {

    private func gitRepo() -> String {
        let base = NSTemporaryDirectory() + "codepet-2c1-git-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        for a in [["init"],["config","user.email","t@t.co"],["config","user.name","t"]] { _ = GitRunner.run(a, in: base) }
        try? "v1".write(toFile: base + "/app.txt", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add","."], in: base); _ = GitRunner.run(["commit","-m","init"], in: base)
        return base
    }

    func test_propose_previewsMultiFile_readyForSmall() {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "x", plannedFiles: 1, needsBash: false, link: link)
        XCTAssertEqual(c.run?.phase, .readyToRun)
        c.propose(ask: "x", plannedFiles: 3, needsBash: false, link: link)
        XCTAssertEqual(c.run?.phase, .previewing)
    }

    func test_propose_noProject_whenLinkNil() {
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "x", plannedFiles: 1, needsBash: false, link: nil)
        XCTAssertEqual(c.run?.phase, .noProject)
    }

    func test_execute_thenApprove_commitsOnBranch_git() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        XCTAssertEqual(c.run?.diffs.count, 1)
        await c.approve(acceptedPaths: ["app.txt"])
        XCTAssertEqual(c.run?.phase, .committed)
        // Commit landed on the codepet branch; the original ref still has v1.
        _ = GitRunner.run(["checkout", "-"], in: repo)   // back to the original branch
        XCTAssertEqual(try? String(contentsOfFile: repo + "/app.txt", encoding: .utf8), "v1")
    }

    func test_execute_thenReject_restores_git() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        await c.reject()
        XCTAssertEqual(c.run?.phase, .discarded)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/app.txt", encoding: .utf8), "v1", "reject restores original")
    }

    func test_execute_runnerFailure_surfacesHonestReasonAndCleansUp() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(failure: "claude not installed"))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.run?.phase, .failed("claude not installed"))
        // A failed run must leave no dangling codepet branch.
        XCTAssertFalse(GitRunner.run(["branch"], in: repo).stdout.contains("codepet/"))
    }
}
