import Foundation

/// The outcome of one shell command.
struct ShellResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    /// stdout with surrounding whitespace removed — what nearly every caller wants.
    var trimmedOut: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Seam over "run a command in the founder's login shell", so probes are testable
/// without spawning anything. Production conformer is `LoginShellRunner`.
protocol ShellRunning {
    func run(_ command: String) async -> ShellResult
}

/// Runs a command through a LOGIN shell (`-lc`) so the founder's PATH resolves.
///
/// The login shell is not a stylistic choice: an app launched from Finder does not
/// inherit the PATH set by the founder's profile, and `claude` commonly lives at
/// `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or an npm global.
/// `ClaudeCodeRunner` already spawns this way; this is that convention extracted so
/// more than one caller can share it rather than inventing a second one.
///
/// The app is not sandboxed (`com.apple.security.app-sandbox = false`), so spawning is
/// permitted. It also means the child does NOT inherit an App Sandbox, which is the
/// whole reason driving the founder's own `claude` is possible at all.
///
/// No unit test, on purpose: this IS the untestable edge the seam exists to isolate,
/// and a test that spawns a real shell to prove a real shell was spawned proves nothing.
struct LoginShellRunner: ShellRunning {

    /// Tried in order; the first that exists on disk is used.
    static let loginShells = ["/bin/zsh", "/bin/bash"]

    /// Credential variables removed from every spawn.
    ///
    /// Claude Code's credential precedence puts both of these ABOVE the founder's
    /// subscription OAuth, and under `-p` — every call Codepet makes — a present key is
    /// always used. Codepet spawns through a login shell so PATH resolves, and that same
    /// shell sources the founder's profile: a key exported in `.zshrc` would silently
    /// bill their API account for work this whole design exists to put on the
    /// subscription they already pay for. No error, no log line, nothing to notice.
    ///
    /// Scrubbed here rather than at call sites because this is the one place a later
    /// caller cannot forget.
    static let strippedEnvironmentKeys = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    /// `environment` minus the credential keys, everything else intact.
    static func scrubbedEnvironment(_ environment: [String: String]) -> [String: String] {
        var scrubbed = environment
        for key in strippedEnvironmentKeys { scrubbed.removeValue(forKey: key) }
        return scrubbed
    }

    /// Hard ceiling on one command, in nanoseconds. A hung shell must not leave a caller
    /// awaiting forever — preflight runs on a screen the founder is looking at.
    let timeoutNanos: UInt64

    init(timeoutNanos: UInt64 = 10 * 1_000_000_000) {
        self.timeoutNanos = timeoutNanos
    }

    func run(_ command: String) async -> ShellResult {
        let shell = Self.loginShells.first { FileManager.default.fileExists(atPath: $0) }
            ?? "/bin/zsh"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", command]
        proc.environment = Self.scrubbedEnvironment(ProcessInfo.processInfo.environment)

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // Detach stdin: a shell that decides to prompt would otherwise inherit the app's
        // stdin and block forever.
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        let timeout = Task {
            try? await Task.sleep(nanoseconds: timeoutNanos)
            if proc.isRunning { proc.terminate() }
        }
        // Read both pipes to EOF BEFORE waiting on exit. The other order deadlocks: a
        // child that fills the 64KB pipe buffer blocks on write while we block on exit.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        timeout.cancel()

        return ShellResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus
        )
    }
}
