import XCTest
@testable import codepet

/// A `ShellRunning` that answers from a canned table, keyed by a substring of the
/// command. Records what it was asked, so a test can assert the probe did not run a
/// command it had no need for — and did run the ones it must.
final class FakeShell: ShellRunning {
    private var responses: [(match: String, result: ShellResult)] = []
    var commandsRun: [String] = []

    /// Answer for a command nothing matched: the shell's own not-found shape.
    var fallback = ShellResult(stdout: "", stderr: "zsh:1: command not found: claude", exitCode: 127)

    func run(_ command: String) async -> ShellResult {
        commandsRun.append(command)
        for r in responses where command.contains(r.match) { return r.result }
        return fallback
    }

    func stub(_ match: String, stdout: String = "", stderr: String = "", exit: Int32 = 0) {
        responses.append((match, ShellResult(stdout: stdout, stderr: stderr, exitCode: exit)))
    }
}

// MARK: - Install detection

final class CLIEnvironmentTests: XCTestCase {

    func testInstallIsMissingOnlyWhenEveryKnownPathFails() async {
        let shell = FakeShell()   // everything falls through to 127
        let install = await CLIEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .missing)
        // PATH first, then every documented install location. Concluding `.missing`
        // without checking them would tell a founder to install software they have.
        XCTAssertEqual(shell.commandsRun.count, 1 + CLIEnvironment.knownInstallPaths.count)
    }

    func testInstallReadsVersionFromPath() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)\n")
        let install = await CLIEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: "2.1.241"))
        // One command: found on PATH, so no absolute-path fallbacks were needed.
        XCTAssertEqual(shell.commandsRun.count, 1)
    }

    func testInstallFoundAtAbsolutePathWhenNotOnPath() async {
        let shell = FakeShell()
        // Bare `claude` is not found, but the native installer's location answers.
        shell.stub(".local/bin/claude", stdout: "2.1.241 (Claude Code)")
        let install = await CLIEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: "2.1.241"))
    }

    /// Exit 0 with output the parser cannot read is NOT the same as absent. Reporting
    /// `.missing` here would tell the founder to install software they already have —
    /// a wrong instruction they can act on, which is worse than an honest unknown.
    func testUnparseableVersionStillCountsAsPresent() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "some future format\n")
        let install = await CLIEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: ""))
    }
}

// MARK: - Auth detection

extension CLIEnvironmentTests {

    func testAuthReadsLoggedInAccount() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: """
        {
          "loggedIn": true,
          "authMethod": "claude.ai",
          "apiProvider": "firstParty",
          "email": "founder@example.com",
          "orgId": "1789007e-428f-418f-9073-42b956cad792",
          "orgName": "Example Co",
          "subscriptionType": "team"
        }
        """)
        let auth = await CLIEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .loggedIn(.init(
            email: "founder@example.com",
            authMethod: "claude.ai",
            apiProvider: "firstParty",
            subscriptionType: "team",
            orgName: "Example Co"
        )))
    }

    func testAuthReadsLoggedOut() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        let auth = await CLIEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .loggedOut)
    }

    /// An older CLI has no `auth` subcommand. Folding that into `.loggedOut` would tell
    /// a signed-in founder to sign in again — and `claude auth login`, the fix they
    /// would then apply, does not address the real problem, which is the CLI version.
    func testAuthIsUnknownWhenSubcommandIsAbsent() async {
        let shell = FakeShell()
        shell.stub("auth status", stderr: "error: unknown command 'auth'", exit: 1)
        let auth = await CLIEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    func testAuthIsUnknownWhenJSONDoesNotParse() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: "Logged in as someone")
        let auth = await CLIEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    /// The design rule is that Codepet never handles a token. This goes red if anyone
    /// reaches for one.
    func testProbeNeverAsksForACredential() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        _ = await CLIEnvironment.probe(shell: shell, authorised: false)
        for command in shell.commandsRun {
            XCTAssertFalse(command.contains("setup-token"), "must not mint a token")
            XCTAssertFalse(command.contains("print-credentials"), "must not read credentials")
            XCTAssertFalse(command.contains("ANTHROPIC_API_KEY"), "must not touch an API key")
        }
    }
}

// MARK: - Combined probe and blockers

extension CLIEnvironmentTests {

    func testProbeSkipsAuthWhenNotInstalled() async {
        let shell = FakeShell()
        let status = await CLIEnvironment.probe(shell: shell, authorised: false)
        XCTAssertEqual(status.install, .missing)
        XCTAssertEqual(status.auth, .unknown)
        // A second command-not-found tells the founder nothing the first did not.
        XCTAssertFalse(shell.commandsRun.contains { $0.contains("auth status") })
    }

    func testProbeReportsReadyWhenInstalledAndSignedIn() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "team"}"#)
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        XCTAssertTrue(status.isReady)
        XCTAssertNil(status.blocker)
    }

    /// Order matters: telling someone to sign in to software they have not installed is
    /// an instruction they cannot follow.
    func testBlockerIsNotInstalledBeforeNotSignedIn() async {
        let shell = FakeShell()
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.blocker, .notInstalled)
    }

    func testBlockerIsNotSignedInWhenInstalledButLoggedOut() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        XCTAssertEqual(status.blocker, .notSignedIn)
    }

    func testBlockerIsVersionUnknownWhenAuthCannotBeRead() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stderr: "unknown command", exit: 1)
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        // The fix is updating Claude Code, not signing in.
        XCTAssertEqual(status.blocker, .versionUnknown)
    }
}

// MARK: - Credential environment scrubbing

extension CLIEnvironmentTests {

    /// The list is the contract: credential precedence puts both of these ABOVE the
    /// founder's subscription, and under `-p` a present key is always used.
    func testStrippedKeysAreExactlyTheTwoThatOutrankTheSubscription() {
        XCTAssertEqual(
            Set(LoginShellRunner.strippedEnvironmentKeys),
            Set(["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"])
        )
    }

    func testScrubbedEnvironmentRemovesOnlyThoseKeys() {
        let scrubbed = LoginShellRunner.scrubbedEnvironment([
            "PATH": "/usr/bin",
            "ANTHROPIC_API_KEY": "sk-ant-should-not-survive",
            "ANTHROPIC_AUTH_TOKEN": "bearer-should-not-survive",
            "HOME": "/Users/someone"
        ])
        XCTAssertNil(scrubbed["ANTHROPIC_API_KEY"])
        XCTAssertNil(scrubbed["ANTHROPIC_AUTH_TOKEN"])
        // Everything else survives — PATH especially, since stripping it is how you
        // manufacture "command not found: claude".
        XCTAssertEqual(scrubbed["PATH"], "/usr/bin")
        XCTAssertEqual(scrubbed["HOME"], "/Users/someone")
    }

    // MARK: - PATH for a Finder launch

    /// The 2026-09-22 release, opened from Finder, got exactly this PATH — and the native
    /// installer's `~/.local/bin` is not on it. Delete the augmentation and this goes red.
    func testFinderLaunchPathGainsTheNativeInstallerDir() {
        let finderPath = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let env = LoginShellRunner.pathAugmented(
            ["PATH": finderPath], home: "/Users/f",
            fileExists: { $0 == "/Users/f/.local/bin" })
        XCTAssertEqual(env["PATH"], finderPath + ":/Users/f/.local/bin")
    }

    /// Appended, never prepended — the founder's own ordering still decides which
    /// `claude` runs — and never duplicated.
    func testPathAugmentationKeepsOrderAndSkipsDuplicatesAndMissingDirs() {
        let env = LoginShellRunner.pathAugmented(
            ["PATH": "/Users/f/.local/bin:/usr/bin"], home: "/Users/f",
            fileExists: { $0 != "/Users/f/.volta/bin" })
        let dirs = env["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(Array(dirs.prefix(2)), ["/Users/f/.local/bin", "/usr/bin"])
        XCTAssertEqual(dirs.filter { $0 == "/Users/f/.local/bin" }.count, 1)
        XCTAssertFalse(dirs.contains("/Users/f/.volta/bin"), "a dir that is not on disk is not added")
    }

    func testSpawnEnvironmentScrubsCredentialsToo() {
        let env = LoginShellRunner.spawnEnvironment(["PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-x"])
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertEqual(env["PATH"]?.split(separator: ":").first, "/usr/bin")
    }

    func testConsoleAccountRaisesABillingWarningButStillRuns() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "console", "apiProvider": "firstParty"}"#)
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        XCTAssertTrue(status.isReady, "a Console account works — this is a warning, not a blocker")
        XCTAssertEqual(status.billingWarning, .consoleAccount)
    }

    func testNoBillingWarningForAPlainSubscription() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"}"#)
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        XCTAssertNil(status.billingWarning)
    }

    func testNoBillingWarningWhenNotSignedIn() async {
        let shell = FakeShell()
        let status = await CLIEnvironment.probe(shell: shell, authorised: true)
        // Nothing to warn about yet; the blocker already says what is wrong.
        XCTAssertNil(status.billingWarning)
        XCTAssertEqual(status.blocker, .notInstalled)
    }
}

// MARK: - Login output cues

/// The cue parser is pure, so it is tested; the process driver that feeds it is the
/// untestable edge, same as `LoginShellRunner`.
final class ClaudeLoginCueTests: XCTestCase {

    func testLoginSuccessfulIsRecognised() {
        XCTAssertEqual(ClaudeLoginCue.cue(for: "Login successful"), .succeeded)
    }

    func testSuccessMatchIsCaseInsensitiveAndTolerantOfSurroundingText() {
        XCTAssertEqual(ClaudeLoginCue.cue(for: "  ✓ LOGIN SUCCESSFUL. Press Enter to continue"),
                       .succeeded)
    }

    /// Documented for WSL2, SSH, and containers: the browser shows a code because it
    /// cannot reach the local callback server. Rare on a Mac desktop, not impossible.
    func testPasteCodePromptAsksForACode() {
        XCTAssertEqual(ClaudeLoginCue.cue(for: "Paste code here if prompted:"), .awaitingCode)
    }

    func testALoginURLIsOfferedSoItCanBeCopied() {
        let line = "Opening https://claude.ai/oauth/authorize?code=1 in your browser"
        XCTAssertEqual(ClaudeLoginCue.cue(for: line),
                       .openedURL("https://claude.ai/oauth/authorize?code=1"))
    }

    func testOrdinaryChatterProducesNoCue() {
        XCTAssertNil(ClaudeLoginCue.cue(for: ""))
        XCTAssertNil(ClaudeLoginCue.cue(for: "Checking for updates…"))
    }

    /// Success and failure are decided by `claude auth status --json`, never by a matched
    /// string. So error-shaped prose must produce NO cue: a CLI whose wording changes
    /// then degrades to "the poll will tell us" instead of reporting a login that
    /// actually worked as broken. `ClaudeLoginCue` has no `.failed` case at all, which is
    /// the compiler enforcing this — these lines prove the parser does not smuggle a
    /// verdict in through another case.
    func testErrorShapedLinesProduceNoCue() {
        for line in ["error: something went wrong", "Login failed", "unknown command 'auth'"] {
            XCTAssertNil(ClaudeLoginCue.cue(for: line),
                         "cue parsing must not reach a verdict from prose: \(line)")
        }
    }
}

// MARK: - Per-provider probe

extension CLIEnvironmentTests {

    func testCodexVersionIsReadFromItsOwnBinary() async {
        let shell = FakeShell()
        shell.stub("codex --version", stdout: "codex-cli 0.154.0")
        let install = await CLIEnvironment.probeInstall(provider: .codex, shell: shell)
        XCTAssertEqual(install, .present(version: "0.154.0"))
    }

    /// Claude installed and Codex absent must not read as both present. This is the fact
    /// every screen in the provider-choice UI branches on.
    func testProvidersAreProbedIndependently() async {
        let shell = FakeShell()
        shell.stub("claude --version", stdout: "2.1.241 (Claude Code)")
        // No `codex` response: FakeShell falls back to exit 127, i.e. not found.
        let claude = await CLIEnvironment.probeInstall(provider: .claudeCode, shell: shell)
        let codex  = await CLIEnvironment.probeInstall(provider: .codex, shell: shell)
        XCTAssertEqual(claude, .present(version: "2.1.241"))
        XCTAssertEqual(codex, .missing)
    }

    /// Verified on the real binary: exit 0 with "Logged in using ChatGPT".
    func testCodexSignedInIsReadFromExitCode() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "Logged in using ChatGPT", exit: 0)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        // Codex reports no account detail at all — an empty Account, never `.unknown`.
        XCTAssertEqual(auth, .loggedIn(CLIStatus.Account(email: nil, authMethod: nil,
                                                        apiProvider: nil, subscriptionType: nil,
                                                        orgName: nil)))
    }

    /// Verified with CODEX_HOME pointed at an empty dir: exit 1, "Not logged in".
    /// **The bug that shipped, and that only running the app found.**
    ///
    /// `codex login status` puts its answer on STDERR and leaves stdout EMPTY. Every earlier
    /// test in this file fed the string through `stdout:`, so all of them passed while a
    /// signed-in founder's Codex probe returned `.unknown` — which made `CLIStatus.account`
    /// nil, which removed her Codex grant row from Settings entirely. She could not grant
    /// Codex at all, and nothing in 2653 tests noticed.
    ///
    /// Note the stub: `stdout` is deliberately left empty. A version of this test that also
    /// passed `stdout:` would pass against the broken code and prove nothing.
    func testCodexReportsSignedInWhenTheAnswerIsOnStderr() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "", stderr: "Logged in using ChatGPT", exit: 0)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        guard case .loggedIn = auth else {
            return XCTFail("stderr-carried answer must read as signed in, got \(auth)")
        }
    }

    /// The signed-out direction, also on stderr, also with empty stdout.
    func testCodexReportsSignedOutWhenThatAnswerIsOnStderr() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "", stderr: "Not logged in", exit: 1)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        XCTAssertEqual(auth, .loggedOut)
    }

    func testCodexSignedOutIsNotReportedAsUnknown() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "Not logged in", exit: 1)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        XCTAssertEqual(auth, .loggedOut)
    }

    /// Regression: "not logged in" contains "logged in" as a substring. An exit-0
    /// response worded "Not logged in" -- unverified against the real CLI, but not
    /// ruled out -- must not be misread as signed in just because the signed-in check
    /// used to run first and matched the substring.
    func testCodexExitZeroWordedNotLoggedInIsNotReadAsLoggedIn() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "Not logged in", exit: 0)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        XCTAssertNotEqual(auth, .loggedIn(CLIStatus.Account(email: nil, authMethod: nil,
                                                            apiProvider: nil, subscriptionType: nil,
                                                            orgName: nil)))
        // The exit code and the wording disagree, so this is unresolvable -- never a
        // false signed-out either.
        XCTAssertEqual(auth, .unknown)
    }

    /// The Claude JSON parser must not be pointed at Codex, and vice versa. A provider
    /// whose probe returns something unparseable is `.unknown` — never a false signed-out.
    func testCodexGibberishIsUnknownNotSignedOut() async {
        let shell = FakeShell()
        shell.stub("codex login status", stdout: "\u{FFFD}garbage\u{FFFD}", exit: 3)
        let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    func testClaudeAuthStillParsesItsJSON() async {
        let shell = FakeShell()
        shell.stub("claude auth status --json",
                 stdout: #"{"loggedIn":true,"email":"f@x.com","authMethod":"claude.ai"}"#)
        let auth = await CLIEnvironment.probeAuth(provider: .claudeCode, shell: shell)
        guard case .loggedIn(let account) = auth else { return XCTFail("expected loggedIn") }
        XCTAssertEqual(account.email, "f@x.com")
        XCTAssertEqual(account.authMethod, "claude.ai")
    }
}

// MARK: - InstalledProviders cache

@MainActor
final class InstalledProvidersTests: XCTestCase {

    func testUnrefreshedCacheReportsNothingInstalled() {
        let cache = InstalledProviders()
        XCTAssertEqual(cache.installed, [])
    }

    func testRefreshFindsOnlyTheProviderThatAnswers() async {
        let shell = FakeShell()
        shell.stub("claude --version", stdout: "2.1.241 (Claude Code)")
        // No `codex` response: falls back to exit 127, i.e. not found.
        let cache = InstalledProviders()
        await cache.refresh(shell: shell)
        XCTAssertEqual(cache.installed, [.claudeCode])
    }
}
