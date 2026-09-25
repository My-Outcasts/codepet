import XCTest
@testable import codepet

/// Founder decision #9: a Team Build may read and write files, nothing else. `--allowedTools`
/// alone does not deny anything — the founder's own ~/.claude/settings.json allow rules and
/// defaultMode still apply under `-p` — so the build run also passes a deny list (deny wins over
/// allow) and `acceptEdits` (edits scoped to the working and added directories). The existing
/// Build path must keep its exact command.
final class CLIRunnerCommandTests: XCTestCase {

    /// The existing Build path, byte for byte as it was before the Team Build flags existed.
    func testTheDefaultCommandIsUnchanged() {
        let cmd = CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 8, allowedTools: CodeRunTools.base)
        XCTAssertEqual(cmd, """
        claude -p \
        --output-format stream-json \
        --verbose \
        --max-turns 8 \
        --allowedTools "Edit,Write,Read,Bash,Glob,Grep" \
        --add-dir "/tmp/p"
        """)
        XCTAssertFalse(cmd.contains("--disallowedTools"))
        XCTAssertFalse(cmd.contains("--permission-mode"))
    }

    func testTheTeamBuildDeniesShellAndWebAndScopesEdits() {
        let cmd = CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 40,
                                          allowedTools: TeamBuildPrompt.allowedTools,
                                          disallowedTools: TeamBuildPrompt.disallowedTools,
                                          permissionMode: TeamBuildPrompt.permissionMode)
        XCTAssertTrue(cmd.contains(#"--allowedTools "Read,Write,Edit,Glob,Grep""#), cmd)
        XCTAssertTrue(cmd.contains(#"--disallowedTools "Bash,WebFetch,WebSearch,NotebookEdit,Task""#), cmd)
        XCTAssertTrue(cmd.contains("--permission-mode acceptEdits"), cmd)
        XCTAssertTrue(cmd.contains(#"--add-dir "/tmp/p""#), cmd)
        // The shared prefix is the default command's, so the two paths cannot drift apart.
        XCTAssertTrue(cmd.hasPrefix(CLIRunner.claudeCommand(dir: "/tmp/p", maxTurns: 40,
                                                            allowedTools: TeamBuildPrompt.allowedTools)))
    }

    func testTheTeamBuildConstants() {
        XCTAssertEqual(TeamBuildPrompt.disallowedTools, ["Bash", "WebFetch", "WebSearch", "NotebookEdit", "Task"])
        XCTAssertEqual(TeamBuildPrompt.permissionMode, "acceptEdits")
    }
}
