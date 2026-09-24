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
    /// Bridges `CLIRunner`'s Combine state to the continuation AND to
    /// `withTaskCancellationHandler`'s `onCancel`, which is `@Sendable` and can fire on any
    /// thread — including before `attach` has even run, if the surrounding `Task` was already
    /// cancelled the moment `run` was called. `attach` and `finish` both check that case (a
    /// `finish` that arrives first is remembered and replayed the moment a continuation shows
    /// up), so cancellation is never silently dropped. `resumed` stays the single gate every
    /// caller — the two Combine sinks, the timeout, and `onCancel` — goes through.
    private final class Resolver: @unchecked Sendable {
        private var resumed = false
        private var bag = Set<AnyCancellable>()
        private var cont: CheckedContinuation<String?, Never>?
        private var pending: String??

        func attach(_ c: CheckedContinuation<String?, Never>) {
            guard !resumed else { return }
            if let pending {
                resumed = true
                c.resume(returning: pending)
                return
            }
            cont = c
        }
        func hold(_ c: AnyCancellable) { bag.insert(c) }
        func finish(_ r: String?) {
            guard !resumed else { return }
            resumed = true
            bag.removeAll()
            if let cont {
                cont.resume(returning: r)
                self.cont = nil
            } else {
                pending = .some(r)
            }
        }
    }

    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
        let runner = CLIRunner()
        let resolver = Resolver()
        var seen = 0
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
                resolver.attach(cont)
                resolver.hold(runner.$events.sink { events in
                    for e in events.dropFirst(seen) where e.kind == .toolUse {
                        let tool = e.toolName ?? "tool"
                        onEvent(e.filePath.map { "\(tool) \(($0 as NSString).lastPathComponent)" } ?? tool)
                    }
                    seen = events.count
                })
                resolver.hold(runner.$state.sink { state in
                    switch state {
                    case .finished(let code): resolver.finish(code == 0 ? nil : "Claude Code exited \(code)")
                    case .failed(let reason): resolver.finish(reason)
                    default: break
                    }
                })
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    // Resolve BEFORE cancelling: `cancel()` can flip `runner.state` to
                    // `.finished(-1)` synchronously, and the still-subscribed `$state` sink
                    // above would then win the `resumed` race with "Claude Code exited -1",
                    // burying the timeout reason the founder is supposed to see.
                    resolver.finish("Timed out after \(Int(timeout / 60)) min")
                    runner.cancel()
                }
                runner.run(prompt: prompt, projectDir: dir, allowedTools: allowedTools, maxTurns: maxTurns)
            }
        } onCancel: {
            // Without this handler, `TeamRunCoordinator.stop()` cancelling the build `Task`
            // had no effect here at all: `withCheckedContinuation` has no cancellation
            // handler by default, so `claude` kept running — and kept writing into the
            // project folder — for up to the full 15-minute timeout.
            Task { @MainActor in
                resolver.finish("Stopped")
                runner.cancel()
            }
        }
    }
}

struct ProjectAssembler {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Codepet Projects")
    var coder: ProjectCodeRunning
    var git: (_ args: [String], _ dir: URL) async -> Bool = { args, dir in await ProjectAssembler.runGit(args, dir) }

    static let buildTimeout: TimeInterval = 900
    static let maxTurns = 40

    func makeFolder(slug: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // `TeamSlug.make` also maps empty → "project" — and, load-bearingly here, strips
        // anything that isn't `[a-z0-9-]`. `slug` comes off a `TeamRun` that can be reloaded
        // from Firestore, so a raw `"../x"` or `"a/b"` would otherwise let a project folder
        // escape or nest under `root` when handed straight to `appendingPathComponent`.
        let base = TeamSlug.make(slug)
        var name = base, n = 1
        while fm.fileExists(atPath: root.appendingPathComponent(name).path) { n += 1; name = "\(base)-\(n)" }
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func assemble(_ run: TeamRun, onLog: @escaping (String) -> Void) async -> TeamAssemblyResult {
        let dir: URL
        do { dir = try makeFolder(slug: run.plan.slug) } catch { return .failure("Could not create the project folder") }
        _ = await git(["init"], dir)

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
        _ = await git(["add", "-A"], dir)
        _ = await git(["commit", "-m", "Initial project from Codepet Team Build"], dir)   // failure is not fatal
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

    /// `nonisolated` so this genuinely runs off the main actor (the module defaults every
    /// declaration to `@MainActor` — `SWIFT_DEFAULT_ACTOR_ISOLATION` in the project settings —
    /// so without this a `struct`'s static func is isolated too, same as an instance method),
    /// and driven by `terminationHandler` + a continuation rather than `waitUntilExit()`, which
    /// blocked synchronously with no way out: `git commit` can sit forever on a gpg passphrase
    /// prompt or a slow hook. `timeout` (default the spec's 30s; overridable so a test can prove
    /// the kill path without a real 30-second wait) terminates a stuck process and returns
    /// `false` instead. `-c commit.gpgsign=false` and a null stdin close the two ways a
    /// `commit` specifically could still ask for input; the gpgsign flag is added here, not at
    /// call sites, so the `git` closure's argument list callers see/assert on is unchanged.
    nonisolated static func runGit(_ args: [String], _ dir: URL, timeout: TimeInterval = 30,
                                   environment: [String: String]? = nil) async -> Bool {
        var procArgs = args
        if procArgs.first == "commit" {
            procArgs = ["-c", "commit.gpgsign=false"] + procArgs
            // A Mac with no git identity fails the commit, and non-technical founders are the
            // ones without one. Fill only what is missing, so a real identity is kept.
            procArgs = await fallbackIdentity(dir, environment: environment) + procArgs
        }
        return await capture(procArgs, dir, timeout: timeout, environment: environment).ok
    }

    /// `-c` flags for whichever of user.name / user.email this repo cannot resolve (empty when
    /// both resolve). The fallback is "Codepet <team-build@codepet.local>".
    private nonisolated static func fallbackIdentity(_ dir: URL, environment: [String: String]?) async -> [String] {
        var flags: [String] = []
        for (key, value) in [("user.name", "Codepet"), ("user.email", "team-build@codepet.local")] {
            let current = await gitOutput(["config", key], dir, timeout: 5, environment: environment)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty { flags += ["-c", "\(key)=\(value)"] }
        }
        return flags
    }

    /// stdout of a git command that exited 0, else nil. For reads such as `git log`.
    nonisolated static func gitOutput(_ args: [String], _ dir: URL, timeout: TimeInterval = 30,
                                      environment: [String: String]? = nil) async -> String? {
        let r = await capture(args, dir, timeout: timeout, environment: environment)
        return r.ok ? r.out : nil
    }

    /// `environment` is a test seam: nil means the founder's login-shell environment.
    private nonisolated static func capture(_ procArgs: [String], _ dir: URL, timeout: TimeInterval,
                                            environment: [String: String]?) async -> (ok: Bool, out: String) {
        return await withCheckedContinuation { (cont: CheckedContinuation<(ok: Bool, out: String), Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = procArgs
            p.currentDirectoryURL = dir
            p.environment = environment ?? LoginShellRunner.spawnEnvironment()
            p.standardInput = FileHandle.nullDevice
            // stdout is read after exit, so only small outputs belong here (a config value, a
            // one-line log): anything past the pipe buffer would block the child from exiting.
            let outPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = FileHandle.nullDevice

            let lock = NSLock()
            var resumed = false
            @Sendable func finish(_ ok: Bool, _ out: String) {
                lock.lock()
                let already = resumed
                resumed = true
                lock.unlock()
                guard !already else { return }
                cont.resume(returning: (ok, out))
            }

            p.terminationHandler = { proc in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                finish(proc.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
            }

            do {
                try p.run()
            } catch {
                finish(false, "")
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                lock.lock()
                let already = resumed
                lock.unlock()
                guard !already else { return }
                p.terminationHandler = nil
                p.terminate()
                finish(false, "")
            }
        }
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
