// codepet/Services/ProjectAssembler.swift
import Foundation
import Combine

protocol ProjectCodeRunning {
    /// Returns nil on success, else a founder-readable failure reason.
    func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String?
    /// The same, with folders the run may read but never change (`CLIRunner.claudeCommand`).
    func run(prompt: String, dir: String, readOnlyDirs: [String], allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String?
}

extension ProjectCodeRunning {
    /// Test doubles implement only the first form. The real runner implements both.
    func run(prompt: String, dir: String, readOnlyDirs: [String], allowedTools: [String], maxTurns: Int,
             timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
        await run(prompt: prompt, dir: dir, allowedTools: allowedTools, maxTurns: maxTurns,
                  timeout: timeout, onEvent: onEvent)
    }
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
        await run(prompt: prompt, dir: dir, readOnlyDirs: [], allowedTools: allowedTools, maxTurns: maxTurns,
                  timeout: timeout, onEvent: onEvent)
    }

    func run(prompt: String, dir: String, readOnlyDirs: [String], allowedTools: [String], maxTurns: Int,
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
                runner.run(prompt: prompt, projectDir: dir, allowedTools: allowedTools, maxTurns: maxTurns,
                           disallowedTools: TeamBuildPrompt.disallowedTools,
                           permissionMode: TeamBuildPrompt.permissionMode,
                           readOnlyDirs: readOnlyDirs)
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
    /// Runs one shell command in the project folder: (succeeded, tail of its output). Only
    /// reached when the build wrote a `package.json` — a seam so the suite never runs npm.
    var shell: (_ command: String, _ dir: URL, _ timeout: TimeInterval) async -> (ok: Bool, tail: String) = {
        cmd, dir, timeout in await ProjectAssembler.runShell(cmd, dir, timeout: timeout)
    }

    /// The founder's linked folder, readable as reference and never changed. Empty when none.
    var referenceDirs: [String] = []
    /// What the team knows about the product (`ProductDossier`); its images are copied into
    /// `public/product/` before the build so the page can show the real product.
    var dossier: ProductDossier?

    static let buildTimeout: TimeInterval = 900
    static let maxTurns = 40
    /// The repair pass after a failed `npm run build` is a narrower job than the build.
    static let repairTurns = 20
    static let installTimeout: TimeInterval = 600
    static let compileTimeout: TimeInterval = 300
    /// Written into the project when the build still fails after the repair pass, so the
    /// founder (or Claude Code opened in the folder) sees the error instead of a green card.
    static let buildErrorsFile = "BUILD-ERRORS.md"

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

        let reference = referenceDirs.filter(CLIRunner.isShellSafePath)
        let assets = copyProductAssets(into: dir)
        if !assets.isEmpty { onLog("copied \(assets.count) product image\(assets.count == 1 ? "" : "s")") }
        if let failure = await coder.run(prompt: TeamBuildPrompt.prompt(for: run, docs: docs, reference: reference,
                                                                        dossier: dossier, assets: assets),
                                         dir: dir.path, readOnlyDirs: reference,
                                         allowedTools: TeamBuildPrompt.allowedTools, maxTurns: Self.maxTurns,
                                         timeout: Self.buildTimeout, onEvent: onLog) {
            return .failure(failure)
        }

        ensureGitignore(dir)
        await verifyBuild(run, dir: dir, onLog: onLog)

        let mdURL = dir.appendingPathComponent("CLAUDE.md")
        let existing = (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
        if !TeamBuildPrompt.isComplete(existing) {
            try? TeamBuildPrompt.fallbackClaudeMd(for: run, docs: docs).write(to: mdURL, atomically: true, encoding: .utf8)
        }
        _ = await git(["add", "-A"], dir)
        _ = await git(["commit", "-m", "Initial project from Codepet Team Build"], dir)   // failure is not fatal
        return .success(path: dir.path)
    }

    /// Copies the dossier's images into `public/product/`, returning the project-relative paths.
    /// Re-validated here — the dossier is read back from disk — and names de-duplicated, since
    /// two `logo.png`s from different folders would otherwise overwrite each other.
    func copyProductAssets(into dir: URL) -> [String] {
        guard let d = dossier, !d.assets.isEmpty else { return [] }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: d.folder).standardizedFileURL.path + "/"
        let dest = dir.appendingPathComponent("public/product")
        guard (try? fm.createDirectory(at: dest, withIntermediateDirectories: true)) != nil else { return [] }
        var out: [String] = []
        for src in d.assets.prefix(ProductDossier.maxAssets) {
            let path = URL(fileURLWithPath: src).standardizedFileURL.path
            guard path.hasPrefix(root),
                  ProductDossier.imageExtensions.contains((path as NSString).pathExtension.lowercased()),
                  let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int,
                  size > 0, size <= ProductDossier.maxAssetBytes else { continue }
            var name = TeamSlug.make((path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "image")
                + "." + (path as NSString).pathExtension.lowercased()
            var n = 1
            while fm.fileExists(atPath: dest.appendingPathComponent(name).path) {
                n += 1
                name = TeamSlug.make((path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "image")
                    + "-\(n)." + (path as NSString).pathExtension.lowercased()
            }
            if (try? fm.copyItem(atPath: path, toPath: dest.appendingPathComponent(name).path)) != nil {
                out.append("public/product/\(name)")
            }
        }
        return out
    }

    /// `node_modules` and `.next` must never reach the commit — a guarantee, not something the
    /// prompt is trusted to remember.
    func ensureGitignore(_ dir: URL) {
        let url = dir.appendingPathComponent(".gitignore")
        let existing = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        let present = Set(existing.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
        let missing = ["node_modules/", ".next/", ".env*.local", ".DS_Store"].filter { entry in
            !present.contains(entry.hasSuffix("/") ? String(entry.dropLast()) : entry)
        }
        guard !missing.isEmpty else { return }
        try? ((existing + missing).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// The build is file-only, so it cannot run npm itself; this does, deterministically, after
    /// it. A failed `npm run build` gets ONE file-only repair pass fed the error, then a
    /// rebuild. Still failing is not fatal — the project exists — but it is written down in
    /// `BUILD-ERRORS.md` and said in the log, never reported as a clean build.
    /// No `package.json` (a docs project) skips all of it.
    func verifyBuild(_ run: TeamRun, dir: URL, onLog: @escaping (String) -> Void) async {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("package.json").path) else { return }
        onLog("npm install")
        let install = await shell("npm install --no-audit --no-fund", dir, Self.installTimeout)
        guard install.ok else {
            onLog("✗ npm install failed")
            writeBuildErrors(dir, step: "npm install", output: install.tail)
            return
        }
        guard !Task.isCancelled else { return }
        onLog("npm run build")
        var build = await shell("npm run build", dir, Self.compileTimeout)
        if build.ok { onLog("✓ npm run build passed"); return }
        guard !Task.isCancelled else { return }

        onLog("✗ build failed — fixing")
        _ = await coder.run(prompt: TeamBuildPrompt.repairPrompt(errors: build.tail), dir: dir.path,
                            readOnlyDirs: referenceDirs.filter(CLIRunner.isShellSafePath),
                            allowedTools: TeamBuildPrompt.allowedTools, maxTurns: Self.repairTurns,
                            timeout: Self.buildTimeout, onEvent: onLog)
        onLog("npm run build")
        build = await shell("npm run build", dir, Self.compileTimeout)
        if build.ok {
            onLog("✓ npm run build passed")
        } else {
            onLog("✗ build still fails — see \(Self.buildErrorsFile)")
            writeBuildErrors(dir, step: "npm run build", output: build.tail)
        }
    }

    private func writeBuildErrors(_ dir: URL, step: String, output: String) {
        let md = "# Build errors\n\n`\(step)` failed after the Team Build. Open this folder with Claude Code and ask it to fix the build.\n\n```\n\(output)\n```\n"
        try? md.write(to: dir.appendingPathComponent(Self.buildErrorsFile), atomically: true, encoding: .utf8)
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

    /// `command` in `dir` through a login shell (npm lives on the founder's PATH), output sent to
    /// a temp file rather than a pipe: npm prints far past the 64 KB pipe buffer, and a child
    /// blocked on a full pipe never exits. Returns the last `tailChars` characters of that output.
    nonisolated static func runShell(_ command: String, _ dir: URL, timeout: TimeInterval,
                                     tailChars: Int = 4000) async -> (ok: Bool, tail: String) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("codepet-build-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        // `exec` so the shell becomes npm, and a terminate (timeout or Stop) reaches npm itself.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: LoginShellRunner.loginShells.first {
            FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh")
        p.arguments = ["-lc", "exec " + command]
        p.currentDirectoryURL = dir
        var env = LoginShellRunner.spawnEnvironment()
        env["CI"] = "1"                       // no interactive prompts, no spinners
        env["NEXT_TELEMETRY_DISABLED"] = "1"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        nonisolated(unsafe) let proc = p
        let ok = await withTaskCancellationHandler { await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let handle = try? FileHandle(forWritingTo: log)
            p.standardOutput = handle
            p.standardError = handle

            let lock = NSLock()
            var resumed = false
            @Sendable func finish(_ ok: Bool) {
                lock.lock(); let already = resumed; resumed = true; lock.unlock()
                guard !already else { return }
                try? handle?.close()
                cont.resume(returning: ok)
            }
            p.terminationHandler = { finish($0.terminationStatus == 0) }
            do { try p.run() } catch { finish(false); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard p.isRunning else { return }
                p.terminate()
                finish(false)
            }
        } } onCancel: {
            // Stop on the card cancels the build Task; without this npm ran on regardless.
            if proc.isRunning { proc.terminate() }
        }
        let out = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (ok, String(out.suffix(tailChars)))
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
