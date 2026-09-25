// codepetTests/TeamBuildReferenceFolderTests.swift
import XCTest
@testable import codepet

/// A Team Build may READ the founder's linked folder and must never change it.
@MainActor
final class TeamBuildReferenceFolderTests: XCTestCase {
    func testAReadOnlyDirIsAddedAndDeniedForEdits() async {
        let cmd = CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 40, allowedTools: TeamBuildPrompt.allowedTools,
                                          disallowedTools: TeamBuildPrompt.disallowedTools,
                                          permissionMode: TeamBuildPrompt.permissionMode,
                                          readOnlyDirs: ["/Users/f/My Product"])
        XCTAssertTrue(cmd.contains(#"--add-dir "/Users/f/My Product""#), cmd)
        // `Edit(...)` is the rule the CLI applies to every file-editing tool; `Write(...)` is ignored.
        XCTAssertTrue(cmd.contains(#"Edit(//Users/f/My Product/**)""#), cmd)
        XCTAssertTrue(cmd.contains("Bash,WebFetch,WebSearch,NotebookEdit,Task,Edit("), "the existing denies stay")
    }

    /// A path that could break out of the quoted argument is never added — and so never added
    /// without its deny rule.
    func testAnUnsafePathIsLeftOutEntirely() async {
        for bad in [#"/a"b"#, "/a$b", "/a`b", "/a,b", "relative"] {
            let cmd = CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 1, allowedTools: ["Read"], readOnlyDirs: [bad])
            XCTAssertEqual(cmd, CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 1, allowedTools: ["Read"]), bad)
        }
    }

    private final class RecordingCoder: ProjectCodeRunning {
        private(set) var dirs: [[String]] = []
        private(set) var prompts: [String] = []
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            XCTFail("the reference-aware form must be the one called"); return nil
        }
        func run(prompt: String, dir: String, readOnlyDirs: [String], allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            dirs.append(readOnlyDirs); prompts.append(prompt); return nil
        }
    }

    func testTheAssemblerHandsTheFolderToTheBuildAndSaysItIsReadOnly() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ref-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let coder = RecordingCoder()
        var a = ProjectAssembler(root: tmp, coder: coder, git: { _, _ in true })
        a.referenceDirs = ["/Users/f/codepet"]
        let steps = [WorkStep(id: "build", dept: "eng", title: "Build", instruction: "", kind: "other", dependsOn: [])]
        let run = TeamRun(request: "landing page", createdAt: Date(), brief: nil,
                          plan: WorkPlan(title: "LP", slug: "lp", summary: "s", projectType: "Next.js landing page", steps: steps))
        _ = await a.assemble(run) { _ in }
        XCTAssertEqual(coder.dirs, [["/Users/f/codepet"]])
        XCTAssertTrue(coder.prompts[0].contains("/Users/f/codepet"))
        XCTAssertTrue(coder.prompts[0].contains("READ-ONLY"))
    }

    func testNoFolderMeansNoNote() async {
        XCTAssertEqual(TeamBuildPrompt.referenceNote([]), "")
    }
}
