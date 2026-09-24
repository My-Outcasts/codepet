// codepetTests/ProjectAssemblerTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectAssemblerTests: XCTestCase {
    private var tmp: URL!
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp); super.tearDown() }

    private final class FakeCoder: ProjectCodeRunning {
        var writeClaudeMd: String?
        var failure: String?
        private(set) var tools: [String] = []
        private(set) var prompt = ""
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            self.prompt = prompt; tools = allowedTools
            onEvent("wrote index.html")
            try? "<html></html>".write(toFile: dir + "/index.html", atomically: true, encoding: .utf8)
            if let md = writeClaudeMd { try? md.write(toFile: dir + "/CLAUDE.md", atomically: true, encoding: .utf8) }
            return failure
        }
    }

    private func teamRun(slug: String = "pants") -> TeamRun {
        let steps = [WorkStep(id: "s1", dept: "mkt", title: "Message", instruction: "Write the message", kind: "doc", dependsOn: []),
                     WorkStep(id: "build", dept: "eng", title: "Build", instruction: "static page", kind: "other", dependsOn: ["s1"])]
        var r = TeamRun(request: "pants page", createdAt: Date(), brief: nil,
                        plan: WorkPlan(title: "Pants", slug: slug, summary: "Office pants", projectType: "static landing page", steps: steps))
        r.steps[0].status = .done
        r.steps[0].draft = Deliverable(kind: .doc, title: "Message", body: "Comfy all day.")
        return r
    }
    private func assembler(_ coder: FakeCoder, gitCalls: @escaping ([String]) -> Void = { _ in }) -> ProjectAssembler {
        ProjectAssembler(root: tmp, coder: coder, git: { args, _ in gitCalls(args); return true })
    }

    func testCreatesRootAndFallsBackToProject() async throws {
        let a = assembler(FakeCoder())
        let url = try a.makeFolder(slug: "")
        XCTAssertEqual(url.lastPathComponent, "project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }
    func testCollisionAppendsASuffix() async throws {
        let a = assembler(FakeCoder())
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants")
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants-2")
        XCTAssertEqual(try a.makeFolder(slug: "pants").lastPathComponent, "pants-3")
    }
    func testWritesDecisionAndDepartmentDocs() async throws {
        let coder = FakeCoder(); coder.writeClaudeMd = TeamBuildPrompt.requiredHeadings.joined(separator: "\n\nx\n\n")
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail("\(result)") }
        let docs = try FileManager.default.contentsOfDirectory(atPath: path + "/docs").sorted()
        XCTAssertEqual(docs, ["00-decision.md", "01-mkt-message.md"])
        let mkt = try String(contentsOfFile: path + "/docs/01-mkt-message.md", encoding: .utf8)
        XCTAssertTrue(mkt.contains("Comfy all day."))
        XCTAssertTrue(coder.prompt.contains("docs/01-mkt-message.md"))
    }
    func testMissingClaudeMdGetsTheFallback() async throws {
        let result = await assembler(FakeCoder()).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        let md = try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8)
        XCTAssertTrue(TeamBuildPrompt.isComplete(md))
        XCTAssertTrue(md.contains("pants page"))
    }
    func testIncompleteClaudeMdIsReplaced() async throws {
        let coder = FakeCoder(); coder.writeClaudeMd = "# Pants\n\nno sections"
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        XCTAssertTrue(TeamBuildPrompt.isComplete(try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8)))
    }
    func testACompleteClaudeMdIsLeftAlone() async throws {
        let written = TeamBuildPrompt.requiredHeadings.joined(separator: "\n\nmine\n\n")
        let coder = FakeCoder(); coder.writeClaudeMd = written
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .success(let path) = result else { return XCTFail() }
        XCTAssertEqual(try String(contentsOfFile: path + "/CLAUDE.md", encoding: .utf8), written)
    }
    func testClaudeCodeGetsFileToolsOnly() async {
        let coder = FakeCoder()
        _ = await assembler(coder).assemble(teamRun()) { _ in }
        XCTAssertEqual(coder.tools, ["Read", "Write", "Edit", "Glob", "Grep"])
        XCTAssertFalse(coder.tools.contains("Bash"))
    }
    func testGitInitThenCommit() async {
        var calls: [[String]] = []
        _ = await assembler(FakeCoder(), gitCalls: { calls.append($0) }).assemble(teamRun()) { _ in }
        XCTAssertEqual(calls.first, ["init"])
        XCTAssertTrue(calls.contains(["add", "-A"]))
        XCTAssertTrue(calls.contains { $0.first == "commit" })
    }
    func testCoderFailureFailsTheAssembly() async {
        let coder = FakeCoder(); coder.failure = "Timed out after 15 min"
        let result = await assembler(coder).assemble(teamRun()) { _ in }
        guard case .failure(let why) = result else { return XCTFail() }
        XCTAssertEqual(why, "Timed out after 15 min")
    }
    func testEventsReachTheLog() async {
        var lines: [String] = []
        _ = await assembler(FakeCoder()).assemble(teamRun()) { lines.append($0) }
        XCTAssertTrue(lines.contains("wrote index.html"))
    }

    // MARK: - Review round 1 fixes

    /// Finding 4: a slug reloaded off a `TeamRun` (e.g. from Firestore) is not trustworthy —
    /// `"../evil"` must not let the project folder escape `root`. Verified empirically before
    /// writing this test that unsanitized `root.appendingPathComponent("../evil")` really does
    /// create a SIBLING of `root` (not something under it): `withIntermediateDirectories: false`
    /// still succeeds because that sibling's parent already exists.
    func testMakeFolderSanitizesAPathEscapingSlug() async throws {
        let a = assembler(FakeCoder())
        let url = try a.makeFolder(slug: "../evil")
        XCTAssertEqual(url.lastPathComponent, "evil")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    /// Finding 3, part 1 (smoke/regression): `runGit` is now `async` and off the main actor,
    /// driven by `terminationHandler` instead of `waitUntilExit()`. Exercises the real
    /// `/usr/bin/git` end to end, so a broken continuation or a broken signature would show up
    /// as `false`/a hang here — the strongest available proof this went RED without the fix is
    /// that the OLD synchronous, non-`async` `runGit` signature does not compile against these
    /// `await` call sites at all. This also runs a real `commit` with `-c commit.gpgsign=false`
    /// auto-injected; it does not independently prove the injection took effect (this machine
    /// has no global `commit.gpgsign` to trigger a hang either way), only that injecting it
    /// doesn't break an ordinary commit.
    func testRunGitReallyInitsAddsAndCommits() async throws {
        let repo = tmp.appendingPathComponent("realgit")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let initOk = await ProjectAssembler.runGit(["init"], repo)
        XCTAssertTrue(initOk)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path))

        _ = await ProjectAssembler.runGit(["config", "user.email", "test@example.com"], repo)
        _ = await ProjectAssembler.runGit(["config", "user.name", "Codepet Test"], repo)
        try "hello".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let addOk = await ProjectAssembler.runGit(["add", "-A"], repo)
        XCTAssertTrue(addOk)
        let commitOk = await ProjectAssembler.runGit(["commit", "-m", "Initial"], repo)
        XCTAssertTrue(commitOk)
    }

    /// Finding 3, part 2: a stuck `commit` (a slow hook, standing in for the gpg-passphrase-
    /// prompt case the finding names — both just make the process not exit) must be killed
    /// after the timeout instead of hanging. `timeout:` is overridden short so this doesn't
    /// need a real 30s wait; the hook itself sleeps far longer than that override, so a pass
    /// here only happens if the process was actually terminated early, not if it happened to
    /// finish on its own.
    func testRunGitKillsAStuckCommitAfterTimeout() async throws {
        let repo = tmp.appendingPathComponent("stuckgit")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = await ProjectAssembler.runGit(["init"], repo)
        _ = await ProjectAssembler.runGit(["config", "user.email", "test@example.com"], repo)
        _ = await ProjectAssembler.runGit(["config", "user.name", "Codepet Test"], repo)

        let hooksDir = tmp.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let hook = hooksDir.appendingPathComponent("pre-commit")
        try "#!/bin/sh\nsleep 5\nexit 0\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let start = Date()
        let ok = await ProjectAssembler.runGit(
            ["-c", "core.hooksPath=\(hooksDir.path)", "commit", "--allow-empty", "-m", "x"],
            repo, timeout: 0.3)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(ok)
        XCTAssertLessThan(elapsed, 3.0)   // killed well before the hook's 5s sleep would finish
    }

    /// A Mac with no git identity (no global user.name/user.email) used to fail the commit
    /// silently, and non-technical founders are exactly the people without one. The environment
    /// is isolated from the developer's own config: HOME and GIT_CONFIG_GLOBAL point at an empty
    /// temp config, system config is off, and `user.useConfigOnly` stops git guessing an
    /// identity from the hostname — so this is "no identity" on every machine.
    func testCommitSucceedsWithNoGitIdentityAndIsAuthoredCodepet() async throws {
        let home = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let globalConfig = home.appendingPathComponent(".gitconfig")
        try "[user]\n\tuseConfigOnly = true\n".write(to: globalConfig, atomically: true, encoding: .utf8)
        let env = ["HOME": home.path, "GIT_CONFIG_GLOBAL": globalConfig.path, "GIT_CONFIG_NOSYSTEM": "1",
                   "PATH": "/usr/bin:/bin"]

        let repo = tmp.appendingPathComponent("noident")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = await ProjectAssembler.runGit(["init"], repo, environment: env)
        try "hello".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = await ProjectAssembler.runGit(["add", "-A"], repo, environment: env)
        let ok = await ProjectAssembler.runGit(["commit", "-m", "Initial"], repo, environment: env)
        XCTAssertTrue(ok, "the commit must succeed without a git identity")

        let log = await ProjectAssembler.gitOutput(["log", "--format=%an <%ae>"], repo, environment: env)
        XCTAssertEqual(log?.trimmingCharacters(in: .whitespacesAndNewlines),
                       "Codepet <team-build@codepet.local>", "exactly one commit, authored Codepet")
    }

    /// A founder who HAS an identity keeps it: the fallback only fills what is missing.
    func testCommitKeepsARealIdentity() async throws {
        let home = tmp.appendingPathComponent("home2")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let globalConfig = home.appendingPathComponent(".gitconfig")
        try "[user]\n\tname = Ada\n\temail = ada@example.com\n".write(to: globalConfig, atomically: true, encoding: .utf8)
        let env = ["HOME": home.path, "GIT_CONFIG_GLOBAL": globalConfig.path, "GIT_CONFIG_NOSYSTEM": "1",
                   "PATH": "/usr/bin:/bin"]
        let repo = tmp.appendingPathComponent("ident")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = await ProjectAssembler.runGit(["init"], repo, environment: env)
        try "hello".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = await ProjectAssembler.runGit(["add", "-A"], repo, environment: env)
        let ok = await ProjectAssembler.runGit(["commit", "-m", "Initial"], repo, environment: env)
        XCTAssertTrue(ok)
        let log = await ProjectAssembler.gitOutput(["log", "--format=%an <%ae>"], repo, environment: env)
        XCTAssertEqual(log?.trimmingCharacters(in: .whitespacesAndNewlines), "Ada <ada@example.com>")
    }
}
