import Foundation

/// Dev-only stand-in for `ClaudeCodeRunAdapter` used when the offline flag
/// `CODEPET_MOCK_CHAT` is set. It fakes ONLY the AI brain — it never spawns
/// `claude`, so it costs no Claude subscription usage — while keeping the rest of
/// the flow real: it streams canned tool-use steps and makes a genuine on-disk
/// edit in the run's working directory, so the real `CodeCommitService` still
/// commits a real change to a real `codepet/*` branch. That lets the whole in-app
/// flow (preview → live steps → diff review → approve → commit) be exercised for
/// free. @MainActor so `onStep` and the `Task.sleep` pacing stay on the main actor,
/// matching the real adapter.
@MainActor
final class MockCodeRunner: CodeRunning {

    func run(prompt: String, workingDir: String, onStep: @escaping (ExecStep) -> Void) async -> CodeRunOutcome {
        let (target, before, after, isNew) = Self.plannedEdit(in: workingDir)
        let name = (target as NSString).lastPathComponent

        // Stream a believable step sequence with small pauses so the card visibly grows.
        onStep(ExecStep(label: "Read \(name)", done: true))
        try? await Task.sleep(nanoseconds: 500_000_000)
        onStep(ExecStep(label: "\(isNew ? "Created" : "Edited") \(name)", done: true))

        // Make the change real on disk so the git commit path has something to commit.
        try? after.write(toFile: target, atomically: true, encoding: .utf8)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let lines = ClaudeCodeRunner.unifiedDiff(before: before, after: after)
        let diff = ClaudeCodeRunner.FileDiff(path: target, isNewFile: isNew, lines: lines)
        return CodeRunOutcome(diffs: [diff], failure: nil)
    }

    /// Decide the file to touch and its before/after. Prefers a realistic in-place
    /// edit of an existing file; falls back to creating a marker file so the mock
    /// works in any linked repo.
    /// Returns (absolutePath, before, after, isNewFile).
    private static func plannedEdit(in dir: String) -> (String, String, String, Bool) {
        let fm = FileManager.default

        // 1. A named candidate we know how to edit nicely.
        for name in ["greeting.js", "README.md", "index.js", "main.swift"] {
            let p = (dir as NSString).appendingPathComponent(name)
            if let before = try? String(contentsOfFile: p, encoding: .utf8) {
                return (p, before, transform(before), false)
            }
        }

        // 2. First small, text-decodable, top-level regular file — but never a
        //    meaningful config/meta file (CLAUDE.md, manifests, lockfiles, licenses)
        //    or a dotfile; the mock should touch ordinary source, not project scaffolding.
        let skip: Set<String> = [
            "CLAUDE.md", "AGENTS.md", "LICENSE", "LICENSE.md",
            "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
            "Package.swift", "Package.resolved", "Podfile", "Podfile.lock",
            "Cargo.toml", "Cargo.lock", "go.mod", "go.sum", "Gemfile", "Gemfile.lock",
        ]
        if let entries = try? fm.contentsOfDirectory(atPath: dir) {
            for name in entries.sorted() where !name.hasPrefix(".") && !skip.contains(name) {
                let p = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
                if let size = (try? fm.attributesOfItem(atPath: p)[.size]) as? Int, size > 64 * 1024 { continue }
                if let before = try? String(contentsOfFile: p, encoding: .utf8) {
                    return (p, before, transform(before), false)
                }
            }
        }

        // 3. Nothing editable — create a marker file (new-file diff).
        let p = (dir as NSString).appendingPathComponent("CODEPET_MOCK.md")
        return (p, "", "# Codepet mock run\n\nThis file was created by a mock coding run to demonstrate the flow.\n", true)
    }

    /// A deterministic, always-changing edit: swap a common greeting if present,
    /// else append a marker line.
    private static func transform(_ s: String) -> String {
        if s.contains("\"Hi \"") {
            return s.replacingOccurrences(of: "\"Hi \" + name", with: "\"Hello, \" + name + \"!\"")
                    .replacingOccurrences(of: "\"Hi \"", with: "\"Hello, \"")
        }
        return s + (s.hasSuffix("\n") ? "" : "\n") + "// Edited by Codepet (mock coding run)\n"
    }
}
