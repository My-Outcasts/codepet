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

final class ClaudeCodeEnvironmentTests: XCTestCase {

    func testInstallIsMissingOnlyWhenEveryKnownPathFails() async {
        let shell = FakeShell()   // everything falls through to 127
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .missing)
        // PATH first, then every documented install location. Concluding `.missing`
        // without checking them would tell a founder to install software they have.
        XCTAssertEqual(shell.commandsRun.count, 1 + ClaudeCodeEnvironment.knownInstallPaths.count)
    }

    func testInstallReadsVersionFromPath() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)\n")
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: "2.1.241"))
        // One command: found on PATH, so no absolute-path fallbacks were needed.
        XCTAssertEqual(shell.commandsRun.count, 1)
    }

    func testInstallFoundAtAbsolutePathWhenNotOnPath() async {
        let shell = FakeShell()
        // Bare `claude` is not found, but the native installer's location answers.
        shell.stub(".local/bin/claude", stdout: "2.1.241 (Claude Code)")
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: "2.1.241"))
    }

    /// Exit 0 with output the parser cannot read is NOT the same as absent. Reporting
    /// `.missing` here would tell the founder to install software they already have —
    /// a wrong instruction they can act on, which is worse than an honest unknown.
    func testUnparseableVersionStillCountsAsPresent() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "some future format\n")
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: ""))
    }
}

// MARK: - Auth detection

extension ClaudeCodeEnvironmentTests {

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
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
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
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .loggedOut)
    }

    /// An older CLI has no `auth` subcommand. Folding that into `.loggedOut` would tell
    /// a signed-in founder to sign in again — and `claude auth login`, the fix they
    /// would then apply, does not address the real problem, which is the CLI version.
    func testAuthIsUnknownWhenSubcommandIsAbsent() async {
        let shell = FakeShell()
        shell.stub("auth status", stderr: "error: unknown command 'auth'", exit: 1)
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    func testAuthIsUnknownWhenJSONDoesNotParse() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: "Logged in as someone")
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    /// The design rule is that Codepet never handles a token. This goes red if anyone
    /// reaches for one.
    func testProbeNeverAsksForACredential() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        _ = await ClaudeCodeEnvironment.probe(shell: shell, authorised: false)
        for command in shell.commandsRun {
            XCTAssertFalse(command.contains("setup-token"), "must not mint a token")
            XCTAssertFalse(command.contains("print-credentials"), "must not read credentials")
            XCTAssertFalse(command.contains("ANTHROPIC_API_KEY"), "must not touch an API key")
        }
    }
}

// MARK: - Combined probe and blockers

extension ClaudeCodeEnvironmentTests {

    func testProbeSkipsAuthWhenNotInstalled() async {
        let shell = FakeShell()
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: false)
        XCTAssertEqual(status.install, .missing)
        XCTAssertEqual(status.auth, .unknown)
        // A second command-not-found tells the founder nothing the first did not.
        XCTAssertFalse(shell.commandsRun.contains { $0.contains("auth status") })
    }

    func testProbeReportsReadyWhenInstalledAndSignedIn() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "team"}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        XCTAssertTrue(status.isReady)
        XCTAssertNil(status.blocker)
    }

    /// Order matters: telling someone to sign in to software they have not installed is
    /// an instruction they cannot follow.
    func testBlockerIsNotInstalledBeforeNotSignedIn() async {
        let shell = FakeShell()
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.blocker, .notInstalled)
    }

    func testBlockerIsNotSignedInWhenInstalledButLoggedOut() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        XCTAssertEqual(status.blocker, .notSignedIn)
    }

    func testBlockerIsVersionUnknownWhenAuthCannotBeRead() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stderr: "unknown command", exit: 1)
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        // The fix is updating Claude Code, not signing in.
        XCTAssertEqual(status.blocker, .versionUnknown)
    }
}

// MARK: - Credential environment scrubbing

extension ClaudeCodeEnvironmentTests {

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

    func testConsoleAccountRaisesABillingWarningButStillRuns() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "console", "apiProvider": "firstParty"}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        XCTAssertTrue(status.isReady, "a Console account works — this is a warning, not a blocker")
        XCTAssertEqual(status.billingWarning, .consoleAccount)
    }

    func testNoBillingWarningForAPlainSubscription() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
        XCTAssertNil(status.billingWarning)
    }

    func testNoBillingWarningWhenNotSignedIn() async {
        let shell = FakeShell()
        let status = await ClaudeCodeEnvironment.probe(shell: shell, authorised: true)
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
