import Foundation
import Combine

/// Runs the user's locally-installed `claude` CLI headless and streams its
/// output back into the app as structured events.
///
/// PLAN-USAGE NOTE: this deliberately drives the user's *own* `claude` binary
/// (via a login shell so their PATH + auth resolve). The heavy code generation
/// therefore runs on the Claude subscription the user already pays for — Codepet
/// adds no separate API key and no extra billing. Coaching commentary is derived
/// from the events below WITHOUT extra model calls (see ExercisePetCoach).
///
/// The app is not sandboxed (com.apple.security.app-sandbox = false), so spawning
/// a subprocess is permitted. This is the first process Codepet spawns.
final class ClaudeCodeRunner: ObservableObject {

    // MARK: - Types

    enum RunState: Equatable {
        case idle
        case running
        case finished(exitCode: Int32)
        case failed(reason: String)
    }

    struct StreamEvent: Identifiable, Equatable {
        enum Kind: Equatable {
            case system          // session init / meta
            case assistantText   // Claude's prose
            case toolUse         // Claude invoked a tool (Edit/Write/Bash/...)
            case toolResult      // result of a tool call
            case result          // final summary line
        }
        let id = UUID()
        let kind: Kind
        let toolName: String?    // "Edit", "Write", "Bash", "Read", ...
        let filePath: String?    // file the tool touched, when applicable
        let text: String         // human-readable line
        let time: Date = Date()

        static func == (l: StreamEvent, r: StreamEvent) -> Bool { l.id == r.id }
    }

    /// One changed file's before/after, computed once the run finishes by diffing
    /// a pre-run snapshot of the project against what's now on disk. (The stream
    /// events only carry the file path, never the old/new content, so we snapshot
    /// ourselves — see `snapshot(dir:)`.)
    struct FileDiff: Identifiable, Equatable {
        enum LineKind { case context, added, removed }
        struct Line: Identifiable, Equatable {
            let id = UUID()
            let kind: LineKind
            let text: String
        }
        let id = UUID()
        let path: String                 // absolute path of the changed file
        let isNewFile: Bool              // created this run (no pre-run content)
        let lines: [Line]                // unified before/after view
        var fileName: String { (path as NSString).lastPathComponent }

        static func == (l: FileDiff, r: FileDiff) -> Bool { l.id == r.id }
    }

    // MARK: - Published state

    @Published private(set) var state: RunState = .idle
    @Published private(set) var events: [StreamEvent] = []
    /// Distinct file paths Claude Code edited/created this run, in first-seen order.
    @Published private(set) var touchedFiles: [String] = []
    /// Before/after diffs for files that actually changed, published on finish.
    @Published private(set) var fileDiffs: [FileDiff] = []

    var isRunning: Bool { if case .running = state { return true }; return false }

    // MARK: - Private

    private var process: Process?
    private var stdoutBuffer = Data()
    private let queue = DispatchQueue(label: "app.murror.codepet.claude-runner")
    /// Last assistant prose we emitted. `stream-json` repeats the final message
    /// inside the terminal `result` event, so we use this to skip the echo.
    private var lastAssistantText = ""
    /// Text-file contents captured just before the run, keyed by standardized
    /// absolute path. Diffed against the post-run files to build `fileDiffs`.
    private var preRunSnapshot: [String: String] = [:]
    /// The resolved working directory, used to resolve any relative tool paths.
    private var projectDirResolved = ""

    // Login shells to try, in order. `-l` loads the user's profile so `claude`
    // (commonly at ~/.claude/local, /opt/homebrew/bin, /usr/local/bin, or an
    // npm global) is on PATH even though the app was launched from Finder.
    private static let loginShells = ["/bin/zsh", "/bin/bash"]

    // MARK: - API

    /// Spawn `claude` in print mode against `projectDir`, streaming events.
    /// - Parameters:
    ///   - prompt: the exercise prompt (passed via stdin to avoid quoting issues).
    ///   - projectDir: absolute path to the user's project (working directory).
    ///   - allowedTools: tools Claude may use; keeps the run scoped.
    ///   - maxTurns: hard cap so a stuck run can't keep consuming the user's plan.
    func run(prompt: String,
             projectDir: String,
             allowedTools: [String] = ["Edit", "Write", "Read", "Bash", "Glob", "Grep"],
             maxTurns: Int = 8) {

        guard !isRunning else { return }

        // Reset
        stdoutBuffer.removeAll()
        events.removeAll()
        touchedFiles.removeAll()
        fileDiffs.removeAll()
        preRunSnapshot.removeAll()
        lastAssistantText = ""
        state = .running

        var dir = projectDir
        if dir.hasPrefix("~") {
            dir = (dir as NSString).expandingTildeInPath
        }
        guard FileManager.default.fileExists(atPath: dir) else {
            state = .failed(reason: "Project folder not found: \(dir)")
            return
        }
        projectDirResolved = dir
        // Snapshot the project's text files now, so we can show real before/after
        // diffs once Claude finishes editing.
        preRunSnapshot = Self.snapshot(dir: dir)

        let shell = Self.loginShells.first { FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh"

        // Build the claude invocation. Prompt comes from stdin (no arg quoting).
        let toolsArg = allowedTools.joined(separator: ",")
        let claudeCmd = """
        claude -p \
        --output-format stream-json \
        --verbose \
        --max-turns \(maxTurns) \
        --allowedTools "\(toolsArg)" \
        --add-dir "\(dir)"
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", claudeCmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = stdinPipe

        // Stream stdout line-by-line as it arrives.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async { self?.ingest(chunk) }
        }

        proc.terminationHandler = { [weak self] p in
            // Drain any trailing buffered line.
            self?.queue.async {
                self?.flushTrailing()
                let code = p.terminationStatus
                DispatchQueue.main.async {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    // Surface stderr only if claude failed outright (e.g. not installed).
                    if code != 0 && self?.events.isEmpty == true {
                        let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                         encoding: .utf8) ?? ""
                        self?.state = .failed(reason: Self.friendlyError(err, exitCode: code))
                    } else {
                        self?.state = .finished(exitCode: code)
                        // All touchedFiles appends are enqueued on main ahead of
                        // this block (the serial parse queue feeds them), so the
                        // list is complete now. Build diffs off-main, then publish.
                        self?.computeDiffs()
                    }
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
            // Feed the prompt to claude's stdin, then close it.
            if let data = (prompt + "\n").data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } catch {
            state = .failed(reason: "Couldn't launch claude: \(error.localizedDescription)")
        }
    }

    /// Terminate the current run (e.g. user tapped Stop, or left the exercise).
    func cancel() {
        process?.terminate()
        process = nil
        if isRunning { state = .finished(exitCode: -1) }
    }

    // MARK: - Stream parsing

    private func ingest(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        // Split on newlines; keep the trailing partial line in the buffer.
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            parseLine(lineData)
        }
    }

    private func flushTrailing() {
        guard !stdoutBuffer.isEmpty else { return }
        let lineData = stdoutBuffer
        stdoutBuffer.removeAll()
        parseLine(lineData)
    }

    private func parseLine(_ data: Data) {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let type = obj["type"] as? String ?? ""
        switch type {
        case "system":
            // init/meta — keep it quiet; emit nothing user-facing.
            break

        case "assistant":
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content { handleAssistantContent(item) }
            }

        case "user":
            // Tool results arrive as user-role messages with tool_result content.
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content where (item["type"] as? String) == "tool_result" {
                    let text = Self.flatten(item["content"])
                    emit(.init(kind: .toolResult, toolName: nil, filePath: nil,
                               text: text.isEmpty ? "(done)" : text))
                }
            }

        case "result":
            let summary = (obj["result"] as? String) ?? "Run complete."
            // `stream-json` repeats the final assistant message here. If we already
            // showed it as prose, don't echo it a second time.
            if summary.trimmingCharacters(in: .whitespacesAndNewlines) == lastAssistantText {
                break
            }
            emit(.init(kind: .result, toolName: nil, filePath: nil, text: summary))

        default:
            break
        }
    }

    private func handleAssistantContent(_ item: [String: Any]) {
        switch item["type"] as? String {
        case "text":
            let t = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                lastAssistantText = t
                emit(.init(kind: .assistantText, toolName: nil, filePath: nil, text: t))
            }
        case "tool_use":
            let name = item["name"] as? String
            let input = item["input"] as? [String: Any]
            let path = (input?["file_path"] as? String) ?? (input?["path"] as? String)
            let detail = Self.toolDetail(name: name, input: input, path: path)
            emit(.init(kind: .toolUse, toolName: name, filePath: path, text: detail))
            if let path, !path.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !self.touchedFiles.contains(path) { self.touchedFiles.append(path) }
                }
            }
        default:
            break
        }
    }

    private func emit(_ event: StreamEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.events.append(event)
        }
    }

    // MARK: - Diffs

    /// Capture the text files under `dir` so we can diff against them later.
    /// Skips hidden files, dependency/build dirs, and anything large or binary.
    private static func snapshot(dir: String) -> [String: String] {
        var snap: [String: String] = [:]
        let fm = FileManager.default
        let base = URL(fileURLWithPath: dir)
        guard let walker = fm.enumerator(at: base,
                                         includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles]) else { return snap }
        for case let url as URL in walker {
            let p = url.path
            if p.contains("/node_modules/") || p.contains("/.git/") || p.contains("/.next/") { continue }
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard vals?.isRegularFile == true else { continue }
            if let size = vals?.fileSize, size > 256 * 1024 { continue }  // skip large/binary
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                snap[url.standardizedFileURL.path] = content
            }
        }
        return snap
    }

    /// Diff each touched file's pre-run snapshot against its current contents and
    /// publish the result. Reads `touchedFiles` on main (it owns that array),
    /// then does file IO + diffing off-main.
    private func computeDiffs() {
        let touched = touchedFiles
        let snapshot = preRunSnapshot
        let dir = projectDirResolved
        queue.async { [weak self] in
            var diffs: [FileDiff] = []
            for raw in touched {
                // Resolve relative paths against the working dir; standardize so
                // the key matches the snapshot's.
                let abs = (raw as NSString).isAbsolutePath
                    ? raw
                    : (dir as NSString).appendingPathComponent(raw)
                let key = URL(fileURLWithPath: abs).standardizedFileURL.path
                let before = snapshot[key]
                let after = (try? String(contentsOfFile: key, encoding: .utf8)) ?? ""
                // Unchanged (e.g. the file was only Read) — nothing to show.
                if before == after { continue }
                let lines = Self.unifiedDiff(before: before ?? "", after: after)
                guard !lines.isEmpty else { continue }
                diffs.append(FileDiff(path: key, isNewFile: before == nil, lines: lines))
            }
            DispatchQueue.main.async { self?.fileDiffs = diffs }
        }
    }

    /// Build a line-level unified diff (context / added / removed) from two
    /// strings using the stdlib's `CollectionDifference`.
    static func unifiedDiff(before: String, after: String) -> [FileDiff.Line] {
        let beforeLines = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let afterLines = after.isEmpty ? [] : after.components(separatedBy: "\n")
        let diff = afterLines.difference(from: beforeLines)

        var removedAt: [Int: String] = [:]   // offset into beforeLines
        var insertedAt: [Int: String] = [:]  // offset into afterLines
        for change in diff {
            switch change {
            case .remove(let offset, let element, _): removedAt[offset] = element
            case .insert(let offset, let element, _): insertedAt[offset] = element
            }
        }

        var out: [FileDiff.Line] = []
        var bi = 0, ai = 0
        while bi < beforeLines.count || ai < afterLines.count {
            if bi < beforeLines.count, removedAt[bi] != nil {
                out.append(.init(kind: .removed, text: beforeLines[bi])); bi += 1
            } else if ai < afterLines.count, insertedAt[ai] != nil {
                out.append(.init(kind: .added, text: afterLines[ai])); ai += 1
            } else if bi < beforeLines.count {
                out.append(.init(kind: .context, text: beforeLines[bi])); bi += 1; ai += 1
            } else {
                ai += 1
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func toolDetail(name: String?, input: [String: Any]?, path: String?) -> String {
        switch name {
        case "Edit", "Write", "MultiEdit":
            return "\(name == "Write" ? "Created" : "Edited") \(shortPath(path))"
        case "Bash":
            return "Ran: \((input?["command"] as? String) ?? "command")"
        case "Read":
            return "Read \(shortPath(path))"
        case "Glob", "Grep":
            return "Searched \((input?["pattern"] as? String) ?? "the project")"
        default:
            return name ?? "Tool"
        }
    }

    private static func shortPath(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "a file" }
        return (path as NSString).lastPathComponent
    }

    /// tool_result content can be a string or an array of {type,text} parts.
    private static func flatten(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func friendlyError(_ stderr: String, exitCode: Int32) -> String {
        let s = stderr.lowercased()
        if s.contains("command not found") || s.contains("not found") {
            return "Claude Code isn't installed or isn't on your PATH. Install it, then try again."
        }
        if s.contains("not logged in") || s.contains("authenticate") || s.contains("login") {
            return "Claude Code needs you to sign in. Run `claude` once in your terminal to log in."
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "claude exited with code \(exitCode)." : trimmed
    }
}
