import Foundation

/// Result of a `git` subprocess call.
struct GitResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var ok: Bool { exitCode == 0 }
}

/// Minimal synchronous `git` wrapper. Runs `/usr/bin/git <args>` in `dir`,
/// captures stdout/stderr/exit. Never throws — a launch failure returns a
/// non-zero `GitResult`. (App is non-sandboxed; spawning git is permitted, same
/// as ClaudeCodeRunner spawning claude.)
enum GitRunner {
    private static let gitPath = "/usr/bin/git"

    @discardableResult
    static func run(_ args: [String], in dir: String) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gitPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do { try proc.run() } catch {
            return GitResult(stdout: "", stderr: String(describing: error), exitCode: -1)
        }
        // Drain stderr concurrently with stdout: a command whose stderr fills its
        // ~64KB pipe (e.g. a verbose commit hook) would otherwise block on the
        // stderr write while we're still reading stdout — a deadlock.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()
        return GitResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus)
    }

    /// The `origin` remote's URL, or nil when there isn't one.
    ///
    /// A hint for matching a folder to a project the founder already has (see
    /// `ProjectIdentity`), never an identity on its own — a fork, a re-pointed remote, and
    /// two clones of one upstream all disagree with it in different directions.
    ///
    /// Nil rather than throwing on every failure: not a repo, no remote, git absent, path
    /// gone. A missing hint is an ordinary outcome here, and every caller treats it the
    /// same way — fall back to asking the founder. The `run` parameter is injectable only
    /// so the exit-code gate is provable without a corrupted repo on disk.
    static func remoteURL(in dir: String,
                          run: ([String], String) -> GitResult = GitRunner.run) -> String? {
        let result = run(["remote", "get-url", "origin"], dir)
        guard result.ok else { return nil }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
}

/// Pure branch/commit slug from a human title.
enum CommitSlug {
    static func make(from title: String) -> String {
        let lowered = title.lowercased()
        var slug = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                slug.append(ch); lastDash = false
            } else if !lastDash {
                slug.append("-"); lastDash = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > 40 { slug = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        return slug.isEmpty ? "change" : slug
    }
}
