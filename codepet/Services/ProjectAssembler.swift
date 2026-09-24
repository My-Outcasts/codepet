// codepet/Services/ProjectAssembler.swift
import Foundation
import Combine

protocol ProjectCodeRunning {
    /// Returns nil on success, else a founder-readable failure reason.
    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String?
}

/// `CodeRunning`'s adapter hardcodes the default 8 turns and the base tools (which include Bash),
/// so a project build gets its own thin wrapper over the same `CLIRunner`.
@MainActor
final class CLIProjectRunner: ProjectCodeRunning {
    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
        let runner = CLIRunner()
        var bag = Set<AnyCancellable>()
        var seen = 0
        return await withCheckedContinuation { cont in
            var resumed = false
            func finish(_ r: String?) { guard !resumed else { return }; resumed = true; bag.removeAll(); cont.resume(returning: r) }
            runner.$events.sink { events in
                for e in events.dropFirst(seen) where e.kind == .toolUse {
                    let tool = e.toolName ?? "tool"
                    onEvent(e.filePath.map { "\(tool) \(($0 as NSString).lastPathComponent)" } ?? tool)
                }
                seen = events.count
            }.store(in: &bag)
            runner.$state.sink { state in
                switch state {
                case .finished(let code): finish(code == 0 ? nil : "Claude Code exited \(code)")
                case .failed(let reason): finish(reason)
                default: break
                }
            }.store(in: &bag)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                runner.cancel()
                finish("Timed out after \(Int(timeout / 60)) min")
            }
            runner.run(prompt: prompt, projectDir: dir, allowedTools: allowedTools, maxTurns: maxTurns)
        }
    }
}

struct ProjectAssembler {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Codepet Projects")
    var coder: ProjectCodeRunning
    var git: (_ args: [String], _ dir: URL) -> Bool = ProjectAssembler.runGit

    static let buildTimeout: TimeInterval = 900
    static let maxTurns = 40

    func makeFolder(slug: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = slug.isEmpty ? "project" : slug
        var name = base, n = 1
        while fm.fileExists(atPath: root.appendingPathComponent(name).path) { n += 1; name = "\(base)-\(n)" }
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func assemble(_ run: TeamRun, onLog: @escaping (String) -> Void) async -> TeamAssemblyResult {
        let dir: URL
        do { dir = try makeFolder(slug: run.plan.slug) } catch { return .failure("Could not create the project folder") }
        _ = git(["init"], dir)

        let docs: [String]
        do { docs = try writeDocs(run, into: dir) } catch { return .failure("Could not write the team's docs") }

        if let failure = await coder.run(prompt: TeamBuildPrompt.prompt(for: run, docs: docs), dir: dir.path,
                                         allowedTools: TeamBuildPrompt.allowedTools, maxTurns: Self.maxTurns,
                                         timeout: Self.buildTimeout, onEvent: onLog) {
            return .failure(failure)
        }

        let mdURL = dir.appendingPathComponent("CLAUDE.md")
        let existing = (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
        if !TeamBuildPrompt.isComplete(existing) {
            try? TeamBuildPrompt.fallbackClaudeMd(for: run, docs: docs).write(to: mdURL, atomically: true, encoding: .utf8)
        }
        _ = git(["add", "-A"], dir)
        _ = git(["commit", "-m", "Initial project from Codepet Team Build"], dir)   // failure is not fatal
        return .success(path: dir.path)
    }

    private func writeDocs(_ run: TeamRun, into dir: URL) throws -> [String] {
        let docsDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        var names = ["docs/00-decision.md"]
        try decisionMarkdown(run).write(to: docsDir.appendingPathComponent("00-decision.md"), atomically: true, encoding: .utf8)
        var n = 0
        for step in run.plan.departmentSteps {
            guard let draft = run.state(step.id)?.draft else { continue }
            n += 1
            let file = String(format: "%02d-%@-%@.md", n, step.dept, TeamSlug.make(step.title))
            let name = DepartmentCatalog.find(step.dept)?.name ?? step.dept
            try DeliverableMarkdown.render(draft, dept: name, instruction: step.instruction)
                .write(to: docsDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
            names.append("docs/\(file)")
        }
        return names
    }

    private func decisionMarkdown(_ run: TeamRun) -> String {
        guard let b = run.brief else {
            return "# Decision\n\n**Request:** \(run.request)\n\n\(run.plan.summary)\n"
        }
        return """
        # Decision

        **Request:** \(run.request)

        ## Recommendation
        \(b.recommendation)

        **Confidence:** \(b.confidence) — \(b.confidenceReason)

        ## The trade-off you own
        \(b.tradeoffFounderMustOwn)

        ## Kill criteria
        \(b.killCriteria.map { "- \($0)" }.joined(separator: "\n"))

        ## What we don't know
        \(b.whatWeDontKnow)
        """
    }

    static func runGit(_ args: [String], _ dir: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = LoginShellRunner.spawnEnvironment()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}

/// Same rules as the op's `teamSlug`, for file names derived from step titles.
enum TeamSlug {
    static func make(_ s: String) -> String {
        let ascii = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
        let kebab = ascii.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let capped = String(kebab.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return capped.isEmpty ? "project" : capped
    }
}
