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

    static func prompt(for run: TeamRun, docs: [String], reference: [String] = []) -> String {
        let build = run.plan.buildStep?.instruction ?? ""
        return """
        You are the engineer on a small company's team. The founder asked: "\(run.request)"
        Build it as: \(run.plan.projectType). \(build)

        The rest of the team has already done their part. Read every file below BEFORE writing anything:
        \(docs.map { "- \($0)" }.joined(separator: "\n"))
        \(referenceNote(reference))

        Build the complete project in the current directory. Use the team's work faithfully — their copy,
        their design direction, their prices. Do not invent facts they did not give you.
        You cannot run shell commands: write every file in full.

        \(nextJsRules)

        If this is not software, produce a well-organised document project with a README.md.

        Finally write CLAUDE.md with exactly these sections, in this order:
        \(requiredHeadings.joined(separator: "\n"))
        "Who did what" must link each file in docs/. "How to run" must give `npm install` then `npm run dev`.
        """
    }

    /// Anything a browser shows is a Next.js app — the founder asked for a real project, and a
    /// folder of hand-written HTML is not one. The team's docs may say "static page" or name
    /// plain files; that was the room choosing scope, not a stack, so the rules say to keep the
    /// scope and ignore the stack. `npm install` / `npm run build` are run by the app after this
    /// (`ProjectAssembler.verifyBuild`), which is why versions are pinned and the build must pass.
    static let nextJsRules = """
        If this is a website or web app (anything a browser shows — a landing page included), build it as a
        Next.js project, even if the team's docs describe plain HTML files or a "static page": keep their scope,
        use this stack instead:
        - Next.js 15 App Router, TypeScript, Tailwind CSS v4 (`@tailwindcss/postcss`). No `pages/` directory.
        - package.json with scripts dev/build/start and EXACT versions: next 15.5.26, react 19.1.9,
          react-dom 19.1.9, typescript 5.9.2, @types/react 19.1.13, @types/react-dom 19.1.9, @types/node 22.18.6,
          tailwindcss 4.1.13, @tailwindcss/postcss 4.1.13. Add nothing else unless the project cannot work without it.
        - tsconfig.json (strict, "@/*" path alias), next.config.ts, postcss.config.mjs, next-env.d.ts,
          app/layout.tsx, app/globals.css (`@import "tailwindcss";`), app/page.tsx, a .gitignore
          (node_modules, .next), and .env.example for any keys or URLs the founder must fill in.
        - One route per page the team defined (e.g. app/thanks/page.tsx). Split UI into components/.
          Configuration the founder edits (prices, links) lives in one file under lib/.
        - Server components by default; "use client" only where state or event handlers need it.
        - It must pass `next build` with no type errors: the app runs it right after you finish.
          Use next/image only for files you actually create in public/; otherwise use a styled placeholder.
        """

    /// The linked folder, when there is one. It is the founder's real product — the source of
    /// truth for what it is and does — and it is read-only: `CLIRunner` denies edits there.
    static func referenceNote(_ dirs: [String]) -> String {
        guard !dirs.isEmpty else { return "" }
        return """

        The founder's own product lives in \(dirs.map { "`\($0)`" }.joined(separator: ", ")) — READ-ONLY reference.
        Read its README, docs and source to get the product right (what it is, who it is for, real feature names).
        Never write, edit or create anything there; every file you make goes in the current directory.
        """
    }

    /// The one repair pass after `npm run build` failed. File-only, same tools as the build.
    static func repairPrompt(errors: String) -> String {
        """
        `npm run build` failed in this Next.js project. Fix the cause in the source files so the build
        passes. Do not remove features or pages to make it pass, and do not change dependency versions
        unless the error is about one. You cannot run commands; the build will be re-run after you finish.

        Build output (last part):
        ```
        \(errors)
        ```
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
        If there is a package.json: `npm install`, then `npm run dev` and open http://localhost:3000.
        Otherwise open this folder with Claude Code and ask it to set the project up.

        ## Next steps
        Review docs/, then ask Claude Code in this folder for the first change you want.
        """
    }
}
