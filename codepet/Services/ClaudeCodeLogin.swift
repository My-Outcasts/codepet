import Foundation
import Combine

/// What one line of `claude auth login` output tells us.
///
/// Pure, so it is tested. The process driver that feeds it is the untestable edge, same
/// as `LoginShellRunner`.
///
/// **There is deliberately no producer of `.failed` here.** Success and failure are
/// decided by `claude auth status --json`, never by a matched string — so when a CLI
/// update changes this prose, the cues degrade to "the poll will tell us" instead of
/// reporting a login that actually worked as broken. The cases exist to drive the UI
/// forward (show a URL, ask for a code), not to reach a verdict.
enum ClaudeLoginCue: Equatable {
    /// A login URL, so the founder can open or copy it when the browser did not launch.
    case openedURL(String)
    /// The browser showed a code instead of redirecting — documented for WSL2, SSH, and
    /// containers, where it cannot reach Claude Code's local callback server. Rare on a
    /// Mac desktop, not impossible.
    case awaitingCode
    /// The CLI says it is done. Still verified by a probe before we believe it.
    case succeeded

    static func cue(for line: String) -> ClaudeLoginCue? {
        let lower = line.lowercased()
        if lower.contains("login successful") { return .succeeded }
        if lower.contains("paste code") { return .awaitingCode }
        if let url = firstURL(in: line) { return .openedURL(url) }
        return nil
    }

    /// First https URL on the line, stopping at whitespace. Deliberately not a regex:
    /// the greedy-URL trap is a known way to swallow trailing prose.
    private static func firstURL(in line: String) -> String? {
        guard let start = line.range(of: "https://") else { return nil }
        let rest = line[start.lowerBound...]
        let url = rest.prefix { !$0.isWhitespace }
        // Trailing punctuation belongs to the sentence, not the URL.
        let trimmed = url.drop(while: { _ in false })
            .reversed()
            .drop(while: { ".,;:)]".contains($0) })
            .reversed()
        let result = String(trimmed)
        return result.count > "https://".count ? result : nil
    }
}

/// Drives `claude auth login` from inside the app, with no Terminal window.
///
/// `claude auth login` opens the browser itself and runs a LOCAL CALLBACK SERVER: the
/// browser redirects back to it and the login completes. So all Codepet has to do is
/// spawn it, keep stdin open for the paste-code fallback, and then ask
/// `claude auth status --json` who is signed in.
///
/// **Codepet never sees a token.** Credentials land in the macOS Keychain under
/// `Claude Safe Storage`, owned and refreshed by Claude Code. That is also why
/// `claude setup-token` is not used here despite fitting a GUI more tidily: it prints a
/// one-year token and saves it nowhere, which would make Codepet the holder of a
/// long-lived credential.
///
/// `@MainActor ObservableObject` because a view observes it. Per landmine 3 no test
/// constructs this type — the tested part is `ClaudeLoginCue`.
@MainActor
final class ClaudeCodeLogin: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Spawned; the browser should be opening.
        case waitingForBrowser
        /// The callback could not be reached, so the founder has a code to paste.
        case needsCode
        case signedIn(ClaudeCodeStatus.Account?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// A login URL to offer when the browser did not open on its own.
    @Published private(set) var loginURL: String?

    private var process: Process?
    private var stdinHandle: FileHandle?
    /// Main-actor owned, like the rest of this class. Login output is a handful of lines,
    /// so parsing it on the main actor costs nothing — and the alternative (a background
    /// parse queue reaching into main-actor state) is the concurrency bug it looks like.
    private var buffer = Data()

    var isRunning: Bool {
        switch phase {
        case .waitingForBrowser, .needsCode: return true
        default: return false
        }
    }

    /// Spawn the login flow. Idempotent while one is in flight.
    func start() {
        guard !isRunning else { return }
        loginURL = nil
        buffer.removeAll()
        phase = .waitingForBrowser

        let shell = LoginShellRunner.loginShells
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/bin/zsh"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        // `--claudeai` is the default, stated explicitly: this flow exists to reach the
        // founder's SUBSCRIPTION. If a future release flips the default to Console, an
        // unstated flag would quietly start billing them per token.
        proc.arguments = ["-lc", "claude auth login --claudeai"]
        proc.environment = LoginShellRunner.scrubbedEnvironment(ProcessInfo.processInfo.environment)

        let outPipe = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = outPipe
        // Merged: the CLI's prompts are not reliably on one stream, and a prompt we miss
        // is a founder staring at a spinner.
        proc.standardError = outPipe
        proc.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.ingest(chunk) }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                outPipe.fileHandleForReading.readabilityHandler = nil
                await self?.confirmWithProbe()
            }
        }

        do {
            try proc.run()
            process = proc
            stdinHandle = inPipe.fileHandleForWriting
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Send the code the browser displayed, for the callback-unreachable path.
    func submitCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let stdinHandle else { return }
        stdinHandle.write(Data((trimmed + "\n").utf8))
        phase = .waitingForBrowser
    }

    func cancel() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        phase = .idle
    }

    // MARK: - Output

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(String(data: lineData, encoding: .utf8) ?? "")
        }
        // The paste-code prompt has no trailing newline — it waits on the same line. So
        // the unterminated tail is inspected too, without consuming it.
        if let tail = String(data: buffer, encoding: .utf8),
           ClaudeLoginCue.cue(for: tail) == .awaitingCode,
           phase == .waitingForBrowser {
            phase = .needsCode
        }
    }

    private func handle(_ line: String) {
        guard let cue = ClaudeLoginCue.cue(for: line) else { return }
        switch cue {
        case .openedURL(let url):
            loginURL = url
        case .awaitingCode:
            phase = .needsCode
        case .succeeded:
            // The CLI may now be waiting on Enter before it exits.
            stdinHandle?.write(Data("\n".utf8))
            Task { await confirmWithProbe() }
        }
    }

    /// `auth status` is the authority, not the prose. This is what makes a changed cue
    /// string a cosmetic problem instead of a false failure.
    ///
    /// Asks `probeAuth` rather than the full `probe`: signing in and being authorised to
    /// spend the plan are different questions, and this flow has no business knowing the
    /// founder's grant. Conflating them would let a successful sign-in read as a failure
    /// purely because the toggle happened to be off.
    private func confirmWithProbe() async {
        // Already resolved by whichever of the two paths got here first.
        if case .signedIn = phase { return }
        switch await ClaudeCodeEnvironment.probeAuth(shell: LoginShellRunner()) {
        case .loggedIn(let account):
            phase = .signedIn(account)
        case .loggedOut:
            phase = .failed(NSLocalizedString(
                "Sign-in did not complete. Try again.", comment: "claude login failed"))
        case .unknown:
            phase = .failed(NSLocalizedString(
                "Couldn't read the sign-in state. Update Claude Code and try again.",
                comment: "claude auth status unreadable"))
        }
        process = nil
        stdinHandle = nil
    }
}
