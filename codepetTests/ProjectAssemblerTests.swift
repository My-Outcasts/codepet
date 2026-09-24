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

    func testCreatesRootAndFallsBackToProject() throws {
        let a = assembler(FakeCoder())
        let url = try a.makeFolder(slug: "")
        XCTAssertEqual(url.lastPathComponent, "project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }
    func testCollisionAppendsASuffix() throws {
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
}
