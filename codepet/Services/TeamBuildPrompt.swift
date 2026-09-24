// codepet/Services/TeamBuildPrompt.swift
import Foundation

/// The build prompt lives here, not in functions/, on purpose: it has no cloud path to share
/// with, and CLIRunner is Swift. See the plan's "deliberate deviations".
enum TeamBuildPrompt {
    static let requiredHeadings = ["## What this is", "## What the team decided", "## Who did what",
                                   "## How to run", "## Next steps"]
    static let allowedTools = ["Read", "Write", "Edit", "Glob", "Grep"]
    /// Denied outright (deny wins over any allow rule in the founder's own settings), so the
    /// build cannot run shell commands, reach the web, or spawn sub-agents.
    static let disallowedTools = ["Bash", "WebFetch", "WebSearch", "NotebookEdit", "Task"]
    /// Edits are accepted without a prompt, and only inside the working and added directories.
    static let permissionMode = "acceptEdits"

    static func isComplete(_ md: String) -> Bool { requiredHeadings.allSatisfy { md.contains($0) } }

    static func prompt(for run: TeamRun, docs: [String]) -> String {
        let build = run.plan.buildStep?.instruction ?? ""
        return """
        You are the engineer on a small company's team. The founder asked: "\(run.request)"
        Build it as: \(run.plan.projectType). \(build)

        The rest of the team has already done their part. Read every file below BEFORE writing anything:
        \(docs.map { "- \($0)" }.joined(separator: "\n"))

        Build the complete project in the current directory. Use the team's work faithfully — their copy,
        their design direction, their prices. Do not invent facts they did not give you.
        You cannot run shell commands: write every file in full, and document installation instead.
        If this is not software, produce a well-organised document project with a README.md.

        Finally write CLAUDE.md with exactly these sections, in this order:
        \(requiredHeadings.joined(separator: "\n"))
        "Who did what" must link each file in docs/. "How to run" must say nothing has been installed yet.
        """
    }

    static func fallbackClaudeMd(for run: TeamRun, docs: [String]) -> String {
        let decided = run.brief.map { "\($0.recommendation)\n\nTrade-off you own: \($0.tradeoffFounderMustOwn)" }
            ?? run.plan.summary
        let who = run.plan.departmentSteps.map { step -> String in
            let name = DepartmentCatalog.find(step.dept)?.name ?? step.dept
            let file = docs.first { $0.contains("-\(step.dept)-") } ?? ""
            return "- **\(name)** — \(step.title)" + (file.isEmpty ? "" : " ([\(file)](\(file)))")
        }.joined(separator: "\n")
        return """
        # \(run.plan.title)

        ## What this is
        \(run.plan.projectType) — built by Codepet's team from the request: "\(run.request)"

        ## What the team decided
        \(decided)

        ## Who did what
        \(who.isEmpty ? "- The engineer built this from the decision alone." : who)
        - **Engineering** — built the project

        ## How to run
        Nothing has been installed yet. Open this folder with Claude Code and ask it to set the project up.

        ## Next steps
        Review docs/, then ask Claude Code in this folder for the first change you want.
        """
    }
}
