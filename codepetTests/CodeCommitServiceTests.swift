import XCTest
@testable import codepet

final class CodeCommitServiceTests: XCTestCase {

    // MARK: git path

    private func tempGitRepo() -> String {
        let base = NSTemporaryDirectory() + "codepet-2b-svc-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        for a in [["init"], ["config","user.email","t@t.co"], ["config","user.name","t"]] { _ = GitRunner.run(a, in: base) }
        try? "v1".write(toFile: base + "/file.txt", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add","."], in: base)
        _ = GitRunner.run(["commit","-m","init"], in: base)
        return base
    }

    private func currentBranch(_ dir: String) -> String {
        GitRunner.run(["rev-parse","--abbrev-ref","HEAD"], in: dir).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func test_beginGit_createsCodepetBranch() {
        let repo = tempGitRepo()
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "Fix signup")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.branch, "codepet/fix-signup")
        XCTAssertEqual(currentBranch(repo), "codepet/fix-signup")
    }

    func test_commitGit_landsOnBranchNotMain() {
        let repo = tempGitRepo()
        let original = currentBranch(repo)
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        try? "v2".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(CodeCommitService.commitGit(s, files: ["file.txt"], message: "codepet: edit"))
        // The commit is on the codepet branch; the original ref's file is still v1.
        _ = GitRunner.run(["checkout", original], in: repo)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "v1")
    }

    func test_abortGit_restoresOriginalStateAndDeletesBranch() {
        let repo = tempGitRepo()
        let original = currentBranch(repo)
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        try? "dirty".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        CodeCommitService.abortGit(s)
        XCTAssertEqual(currentBranch(repo), original)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "v1")
        let branches = GitRunner.run(["branch"], in: repo).stdout
        XCTAssertFalse(branches.contains("codepet/edit"))
    }

    func test_beginGit_stashesDirtyWorkAndAbortRestoresIt() {
        let repo = tempGitRepo()
        try? "uncommitted".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)  // dirty pre-existing edit
        let s = CodeCommitService.beginGit(projectPath: repo, taskTitle: "edit")!
        XCTAssertTrue(s.stashed)
        CodeCommitService.abortGit(s)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/file.txt", encoding: .utf8), "uncommitted",
                       "pre-existing dirty work must be restored on abort")
    }

    func test_beginGit_returnsNilForNonRepo() {
        let dir = NSTemporaryDirectory() + "codepet-2b-nonrepo-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        XCTAssertNil(CodeCommitService.beginGit(projectPath: dir, taskTitle: "x"))
    }

    // MARK: shadow path

    private func tempPlainProject() -> String {
        let base = NSTemporaryDirectory() + "codepet-2b-shadow-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base + "/node_modules", withIntermediateDirectories: true)
        try? "orig".write(toFile: base + "/app.txt", atomically: true, encoding: .utf8)
        try? "junk".write(toFile: base + "/node_modules/x.txt", atomically: true, encoding: .utf8)
        return base
    }

    func test_beginShadow_copiesProjectExcludingHeavyDirs() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        XCTAssertEqual(try? String(contentsOfFile: s.shadowDir + "/app.txt", encoding: .utf8), "orig")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.shadowDir + "/node_modules"))
    }

    func test_applyShadow_writesAcceptedFilesToRealTreeWithBackup() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        // Simulate the run editing an existing file + creating a new one in the shadow.
        try? "edited".write(toFile: s.shadowDir + "/app.txt", atomically: true, encoding: .utf8)
        try? "new".write(toFile: s.shadowDir + "/added.txt", atomically: true, encoding: .utf8)

        XCTAssertTrue(CodeCommitService.applyShadow(s, acceptedRelPaths: ["app.txt", "added.txt"]))
        XCTAssertEqual(try? String(contentsOfFile: p + "/app.txt", encoding: .utf8), "edited")
        XCTAssertEqual(try? String(contentsOfFile: p + "/added.txt", encoding: .utf8), "new")
    }

    func test_undoShadow_restoresEditedAndRemovesCreated() {
        let p = tempPlainProject()
        let s = CodeCommitService.beginShadow(projectPath: p)!
        try? "edited".write(toFile: s.shadowDir + "/app.txt", atomically: true, encoding: .utf8)
        try? "new".write(toFile: s.shadowDir + "/added.txt", atomically: true, encoding: .utf8)
        _ = CodeCommitService.applyShadow(s, acceptedRelPaths: ["app.txt", "added.txt"])

        CodeCommitService.undoShadow(s)
        XCTAssertEqual(try? String(contentsOfFile: p + "/app.txt", encoding: .utf8), "orig",
                       "edited file restored to original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: p + "/added.txt"),
                       "newly-created file removed on undo")
    }
}
