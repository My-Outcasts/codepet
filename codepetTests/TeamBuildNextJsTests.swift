// codepetTests/TeamBuildNextJsTests.swift
import XCTest
@testable import codepet

/// The Next.js half of a Team Build: the prompt asks for it, and the assembler runs npm after
/// the file-only build, repairs once, and never reports a failing build as clean.
@MainActor
final class TeamBuildNextJsTests: XCTestCase {
    private var tmp: URL!
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nx-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp); super.tearDown() }

    /// Writes a package.json on the first pass (the build), records every prompt it is given.
    private final class NodeCoder: ProjectCodeRunning {
        var writesPackageJson = true
        private(set) var prompts: [String] = []
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            prompts.append(prompt)
            if writesPackageJson, prompts.count == 1 {
                try? #"{"name":"x"}"#.write(toFile: dir + "/package.json", atomically: true, encoding: .utf8)
            }
            return nil
        }
    }

    private func teamRun() -> TeamRun {
        let steps = [WorkStep(id: "build", dept: "eng", title: "Build", instruction: "", kind: "other", dependsOn: [])]
        return TeamRun(request: "pants page", createdAt: Date(), brief: nil,
                       plan: WorkPlan(title: "Pants", slug: "pants", summary: "s", projectType: "Next.js landing page", steps: steps))
    }

    /// `results` answers each shell command in order; every command run is recorded.
    private func assembler(_ coder: NodeCoder, results: [Bool], commands: @escaping (String) -> Void) -> ProjectAssembler {
        var queue = results
        return ProjectAssembler(root: tmp, coder: coder, git: { _, _ in true }, shell: { cmd, _, _ in
            commands(cmd)
            let ok = queue.isEmpty ? true : queue.removeFirst()
            return (ok, ok ? "" : "Type error: boom")
        })
    }

    func testPromptAsksForNextJs() {
        let p = TeamBuildPrompt.prompt(for: teamRun(), docs: [])
        XCTAssertTrue(p.contains("Next.js 15 App Router"))
        XCTAssertTrue(p.contains("next 15.5.26"))
        XCTAssertTrue(p.contains("npm run dev"))
    }

    func testNoPackageJsonRunsNoNpm() async {
        let coder = NodeCoder(); coder.writesPackageJson = false
        var cmds: [String] = []
        _ = await assembler(coder, results: [], commands: { cmds.append($0) }).assemble(teamRun()) { _ in }
        XCTAssertEqual(cmds, [])
    }

    func testPassingBuildRunsInstallThenBuildOnly() async throws {
        let coder = NodeCoder()
        var cmds: [String] = []
        var log: [String] = []
        let result = await assembler(coder, results: [true, true], commands: { cmds.append($0) })
            .assemble(teamRun()) { log.append($0) }
        guard case .success(let path) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(cmds.map { $0.components(separatedBy: " ").prefix(3).joined(separator: " ") },
                       ["npm install --no-audit", "npm run build"])
        XCTAssertEqual(coder.prompts.count, 1, "no repair pass after a clean build")
        XCTAssertTrue(log.contains("✓ npm run build passed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "/" + ProjectAssembler.buildErrorsFile))
    }

    func testFailedBuildGetsOneRepairPassFedTheError() async {
        let coder = NodeCoder()
        var cmds: [String] = []
        _ = await assembler(coder, results: [true, false, true], commands: { cmds.append($0) })
            .assemble(teamRun()) { _ in }
        XCTAssertEqual(cmds.filter { $0 == "npm run build" }.count, 2)
        XCTAssertEqual(coder.prompts.count, 2)
        XCTAssertTrue(coder.prompts[1].contains("Type error: boom"), "the repair pass sees the build output")
    }

    /// Still failing after the repair is not fatal — the project exists — but it is written down.
    func testStillFailingBuildIsWrittenDownNotHidden() async throws {
        var log: [String] = []
        let result = await assembler(NodeCoder(), results: [true, false, false], commands: { _ in })
            .assemble(teamRun()) { log.append($0) }
        guard case .success(let path) = result else { return XCTFail("\(result)") }
        let md = try String(contentsOfFile: path + "/" + ProjectAssembler.buildErrorsFile, encoding: .utf8)
        XCTAssertTrue(md.contains("Type error: boom"))
        XCTAssertFalse(log.contains("✓ npm run build passed"))
    }

    func testGitignoreAlwaysCoversNodeModulesAndKeepsExistingLines() async throws {
        let dir = tmp.appendingPathComponent("g")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "coverage\nnode_modules\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        // Held for the whole test: a temporary @MainActor coder deallocating mid-expression is
        // the Xcode 26.2 isolated-deinit crash (CLAUDE.md landmine 3), not this code.
        let coder = NodeCoder()
        ProjectAssembler(root: tmp, coder: coder).ensureGitignore(dir)
        let lines = try String(contentsOf: dir.appendingPathComponent(".gitignore"), encoding: .utf8)
            .components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("coverage"))
        XCTAssertTrue(lines.contains(".next/"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("node_modules") }.count, 1, "an existing entry is not duplicated")
    }

    /// A folder name comes from founder-typed text; a quote in it must not break out of `cd`.
    func testRunScriptQuotesThePath() {
        let s = TeamProjectLauncher.script(for: "/tmp/it's here", pathVar: "/opt/homebrew/bin")
        XCTAssertTrue(s.contains(#"cd '/tmp/it'\''s here' || exit 1"#))
        XCTAssertTrue(s.contains("export PATH='/opt/homebrew/bin':$PATH"))
        XCTAssertTrue(s.contains("exec npm run dev"))
    }

    /// Build 9 (6 Oct): "Run it" opened localhost:3000 while Next.js, finding 3000 taken, had
    /// started the project on 3001 — so the founder saw whatever else held 3000 (here, an old
    /// landing-page dev server). The script must open the port the server actually got.
    ///
    /// Runs the real script with a stand-in `npm` that listens on the port it is told to use and a
    /// stand-in `open` that records the URL, with the start port already occupied.
    func testRunItOpensThePortTheServerGotWhenTheFirstIsTaken() throws {
        let bin = tmp.appendingPathComponent("bin")
        let proj = tmp.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proj.appendingPathComponent("node_modules"),
                                                withIntermediateDirectories: true)
        let opened = tmp.appendingPathComponent("opened.txt")
        // npm run dev -- -p <port>: listen on the last argument, like `next dev -p`.
        try "#!/bin/zsh\nexec nc -l ${@[-1]}\n".write(to: bin.appendingPathComponent("npm"), atomically: true, encoding: .utf8)
        try "#!/bin/zsh\nprint -r -- \"$1\" > '\(opened.path)'\n".write(to: bin.appendingPathComponent("open"), atomically: true, encoding: .utf8)
        for f in ["npm", "open"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent(f).path)
        }

        // Occupy a port the way a leftover dev server would.
        let blocker = Process()
        blocker.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        let start = 40_000 + Int.random(in: 0..<9_000)
        blocker.arguments = ["-l", "\(start)"]
        try blocker.run()
        defer { blocker.terminate() }
        Thread.sleep(forTimeInterval: 0.3)

        let script = TeamProjectLauncher.script(for: proj.path, pathVar: bin.path, startPort: start)
        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/zsh")
        run.arguments = ["-c", script]
        try run.run()
        defer { run.terminate() }

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, (try? String(contentsOf: opened, encoding: .utf8)) == nil {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let url = try String(contentsOf: opened, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(url, "http://localhost:\(start + 1)", "opened the occupied port, not the one the server got")
    }
}
