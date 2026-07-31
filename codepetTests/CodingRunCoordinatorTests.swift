import XCTest
@testable import codepet

/// A fake runner that simulates claude by writing `edits` (relPath → contents) into
/// the working dir, then reporting diffs for them (or a failure).
private final class FakeRunner: CodeRunning {
    let edits: [String: String]
    let failure: String?
    let stepLabels: [String]
    init(edits: [String: String] = [:], failure: String? = nil, stepLabels: [String] = []) {
        self.edits = edits; self.failure = failure; self.stepLabels = stepLabels
    }
    func run(prompt: String, workingDir: String, onStep: @escaping (ExecStep) -> Void) async -> CodeRunOutcome {
        for label in stepLabels { onStep(ExecStep(label: label, done: true)) }
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
        // Separate coordinators: a readyToRun run is now in-flight and blocks a
        // second propose on the same instance (see test_propose_ignoresDuplicate…).
        let small = CodingRunCoordinator(runner: FakeRunner())
        small.propose(ask: "x", plannedFiles: 1, needsBash: false, link: link)
        XCTAssertEqual(small.run?.phase, .readyToRun)
        let multi = CodingRunCoordinator(runner: FakeRunner())
        multi.propose(ask: "x", plannedFiles: 3, needsBash: false, link: link)
        XCTAssertEqual(multi.run?.phase, .previewing)
    }

    func test_propose_ignoresDuplicateWhileInFlight() {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "first", plannedFiles: 1, needsBash: false, link: link)   // → readyToRun (in-flight)
        c.propose(ask: "second", plannedFiles: 1, needsBash: false, link: link)  // rapid duplicate
        // The in-flight run is NOT clobbered; the duplicate is ignored.
        XCTAssertEqual(c.run?.ask, "first")
        XCTAssertEqual(c.run?.phase, .readyToRun)
    }

    // abortGit must NEVER delete a branch that carries commits — reject/supersede on
    // an already-committed run would otherwise destroy the founder's approved work
    // (the "commit vanished" orphaning).
    func test_abortGit_keepsBranchThatHasCommits() {
        let repo = gitRepo()
        guard let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "friendlier greeting") else {
            return XCTFail("beginGit failed")
        }
        try? "v2".write(toFile: repo + "/app.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(CodeCommitService.commitGit(s, files: ["app.txt"], message: "codepet: x").committed)
        CodeCommitService.abortGit(s)   // has a commit → must be kept
        let branches = GitRunner.run(["branch", "--list", "codepet/*"], in: repo).stdout
        XCTAssertTrue(branches.contains(s.branch), "a codepet branch with commits must survive abortGit\n\(branches)")
    }

    // A duplicate commit (clean tree) is flagged nothingToCommit, NOT a failure.
    func test_commitGit_flagsNothingToCommit() {
        let repo = gitRepo()
        guard let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "x") else { return XCTFail() }
        let r = CodeCommitService.commitGit(s, files: ["app.txt"], message: "codepet: x")  // app.txt unchanged
        XCTAssertFalse(r.committed)
        XCTAssertTrue(r.nothingToCommit, "a clean-tree commit must be flagged nothingToCommit, not a hard failure")
    }

    // The coordinator's SHADOW path (non-git project): execute → approve →
    // applyShadow must write the edit in-place to the real project. This is the
    // end-to-end wiring the primitive-level applyShadow test doesn't cover.
    func test_execute_thenApprove_appliesInPlace_shadow() async {
        let repo = NSTemporaryDirectory() + "codepet-shadow-coord-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        try? "v1".write(toFile: repo + "/app.txt", atomically: true, encoding: .utf8)
        let link = ProjectLink(path: repo, isGitRepo: false, hasClaudeMd: false)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        if case .shadow = c.run?.backend {} else { XCTFail("non-git must pick shadow backend"); return }
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        XCTAssertEqual(c.run?.diffs.count, 1)
        await c.approve(acceptedPaths: c.run?.acceptedPaths ?? [])
        XCTAssertEqual(c.run?.phase, .committed)
        // The accepted change is applied in-place to the real (non-git) project.
        XCTAssertEqual(try? String(contentsOfFile: repo + "/app.txt", encoding: .utf8), "v2",
                       "shadow Approve must write the edit into the real project")
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

    func test_secondPropose_tearsDownPriorUnresolvedSession() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "one", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()   // on branch codepet/one, .reviewing (unresolved)
        XCTAssertTrue(GitRunner.run(["branch"], in: repo).stdout.contains("codepet/one"))
        // A new proposal supersedes the un-resolved run → its branch is cleaned up.
        c.propose(ask: "two", plannedFiles: 1, needsBash: false, link: link)
        XCTAssertFalse(GitRunner.run(["branch"], in: repo).stdout.contains("codepet/one"),
                       "the un-resolved prior run's branch must be torn down")
    }

    func test_approve_failedCommit_goesToFailedNotCommitted() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        // Approve a path that wasn't changed → nothing staged → git commit fails.
        await c.approve(acceptedPaths: ["ghost.txt"])
        XCTAssertEqual(c.run?.phase, .failed("Couldn't commit the changes."),
                       "a failed commit must surface as .failed, not a false .committed")
    }

    func test_approve_beforeReviewing_isIgnored() async {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "x", plannedFiles: 1, needsBash: false, link: link)   // .readyToRun
        await c.approve(acceptedPaths: [])                                    // wrong phase
        XCTAssertEqual(c.run?.phase, .readyToRun, "approve before .reviewing must be a no-op")
    }

    func test_execute_collectsLiveSteps() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"], stepLabels: ["Edited app.txt", "Ran swift build"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.steps.map(\.label), ["Edited app.txt", "Ran swift build"])
    }
}
