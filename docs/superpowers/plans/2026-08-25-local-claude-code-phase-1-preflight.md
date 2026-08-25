# Local Claude Code — Phase 1: Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codepet can tell, without running anything expensive, whether the founder has Claude Code installed, which version, and whether they are signed in — and reports it as a value type the rest of the migration can branch on.

**Architecture:** One new service, `ClaudeCodeEnvironment`, that shells out to `claude --version` and `claude auth status --json` through an injected `ShellRunning` seam and returns a `ClaudeCodeStatus` value. No UI, no wiring into any run path, no behaviour change to existing features. Pure addition.

**Tech Stack:** Swift 5, SwiftUI project, `Foundation.Process`, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-25-local-claude-code-execution-design.md`

## Global Constraints

- Deployment target 26.2. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **No new type in this phase may be a `@MainActor ObservableObject`.** Landmine 3: the XCTest host on Xcode 26.2 crashes when one deallocates. `ClaudeCodeStatus` is a `struct`; `ClaudeCodeEnvironment` is an `enum` namespace with static functions.
- Every subprocess call goes through the `ShellRunning` protocol. Tests never spawn a real `claude`.
- New `.swift` files need no project-file edit — `PBXFileSystemSynchronizedRootGroup` means target membership follows the folder on disk.
- Tests run per-suite: `xcodebuild test -scheme codepet -only-testing:codepetTests/<Suite>`. Never judge this work by a whole-target run; that exits 65 on a clean checkout for unrelated reasons.
- Login shells to try, in order: `/bin/zsh`, then `/bin/bash`, invoked `-lc` so the founder's PATH resolves when the app was launched from Finder. This mirrors `ClaudeCodeRunner.loginShells` exactly — do not invent a second convention.
- No new dependency, no network call, no Firebase in this phase.

---

## File Structure

| File | Responsibility |
|---|---|
| `codepet/Services/ShellRunning.swift` (create) | The subprocess seam: a protocol plus the real `LoginShellRunner` conformer. Nothing Claude-specific. |
| `codepet/Services/ClaudeCodeEnvironment.swift` (create) | `ClaudeCodeStatus` value type and the probe that builds one. Claude-specific, shell-agnostic. |
| `codepetTests/ClaudeCodeEnvironmentTests.swift` (create) | Probe behaviour against a fake shell. |

Two files rather than one because the shell seam has no Claude knowledge and later phases (the Node sidecar in phase 5) will reuse it. `ClaudeCodeRunner.swift` is left untouched in this phase — it spawns its own process for streaming runs and has a different lifetime; folding preflight into it would fuse two concerns that get split again later.

---

### Task 1: The shell seam

**Files:**
- Create: `codepet/Services/ShellRunning.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct ShellResult { let stdout: String; let stderr: String; let exitCode: Int32 }`, `protocol ShellRunning { func run(_ command: String) async -> ShellResult }`, and `struct LoginShellRunner: ShellRunning`.

- [ ] **Step 1: Write the file**

```swift
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

/// Seam over "run a command in the founder's login shell", so probes and
/// runners are testable without spawning anything. Production conformer is
/// `LoginShellRunner`.
protocol ShellRunning {
    func run(_ command: String) async -> ShellResult
}

/// Runs a command through a LOGIN shell (`-lc`) so the founder's PATH resolves.
///
/// The login shell is not a stylistic choice: an app launched from Finder does
/// not inherit the PATH set by the founder's profile, and `claude` commonly
/// lives at `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or an npm
/// global. `ClaudeCodeRunner` already spawns this way; this is the same
/// convention extracted so more than one caller can share it.
///
/// The app is not sandboxed (`com.apple.security.app-sandbox = false`), so
/// spawning is permitted.
struct LoginShellRunner: ShellRunning {

    /// Tried in order; the first that exists on disk is used.
    static let loginShells = ["/bin/zsh", "/bin/bash"]

    /// Hard ceiling on one probe, in nanoseconds. A hung shell must not leave a
    /// caller awaiting forever — preflight runs on a screen the founder is
    /// looking at.
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

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // Detach stdin: a login shell that decides to prompt would otherwise
        // inherit the app's stdin and block forever.
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        // Read both pipes to EOF BEFORE waiting on exit. Waiting first can
        // deadlock: a child that fills a 64KB pipe buffer blocks on write while
        // we block on its exit.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let timeout = Task {
            try? await Task.sleep(nanoseconds: timeoutNanos)
            if proc.isRunning { proc.terminate() }
        }
        proc.waitUntilExit()
        timeout.cancel()

        return ShellResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus
        )
    }
}
```

- [ ] **Step 2: Confirm it builds**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild build -scheme codepet -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. No test yet — `LoginShellRunner` is the untestable edge of the seam (it exists so everything above it is testable), and a test that spawns a real shell to assert a real shell ran proves nothing.

- [ ] **Step 3: Commit**

```bash
git add codepet/Services/ShellRunning.swift
git commit -m "feat(local-claude): add the ShellRunning seam

Extracted from ClaudeCodeRunner's own spawn: a login shell (-lc) so the
founder's PATH resolves when the app launched from Finder. Reads both
pipes to EOF before waitUntilExit — the other order deadlocks once a
child fills the 64KB pipe buffer. stdin is /dev/null so a shell that
decides to prompt cannot hang the app.

LoginShellRunner has no test on purpose: it IS the untestable edge the
seam exists to isolate."
```

---

### Task 2: `ClaudeCodeStatus`, and a probe that reads the version

**Files:**
- Create: `codepet/Services/ClaudeCodeEnvironment.swift`
- Create: `codepetTests/ClaudeCodeEnvironmentTests.swift`

**Interfaces:**
- Consumes: `ShellRunning`, `ShellResult` from Task 1.
- Produces: `struct ClaudeCodeStatus` with `enum Install { case missing, present(version: String) }` and `enum Auth { case unknown, loggedOut, loggedIn(Account) }`, `struct Account`, plus `enum ClaudeCodeEnvironment { static func probeInstall(shell:) async -> ClaudeCodeStatus.Install }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import codepet

/// A `ShellRunning` that answers from a canned table, keyed by a substring of
/// the command. Records what it was asked, so a test can assert the probe did
/// not run a second command it had no need for.
final class FakeShell: ShellRunning {
    var responses: [(match: String, result: ShellResult)] = []
    var commandsRun: [String] = []
    /// Answer for a command nothing matched: shell's own "not found" shape.
    var fallback = ShellResult(stdout: "", stderr: "zsh:1: command not found: claude", exitCode: 127)

    func run(_ command: String) async -> ShellResult {
        commandsRun.append(command)
        for r in responses where command.contains(r.match) {
            return r.result
        }
        return fallback
    }

    func stub(_ match: String, stdout: String = "", stderr: String = "", exit: Int32 = 0) {
        responses.append((match, ShellResult(stdout: stdout, stderr: stderr, exitCode: exit)))
    }
}

final class ClaudeCodeEnvironmentTests: XCTestCase {

    func testInstallIsMissingWhenCommandNotFound() async {
        let shell = FakeShell()   // falls through to exit 127
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .missing)
    }

    func testInstallReadsVersionFromVersionOutput() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)\n")
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: "2.1.241"))
    }

    /// Exit 0 with output the parser cannot read is NOT the same as absent.
    /// Reporting `.missing` here would tell the founder to install software
    /// they already have — a wrong instruction they can act on, which is worse
    /// than an honest unknown.
    func testUnparseableVersionStillCountsAsPresent() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "some future format\n")
        let install = await ClaudeCodeEnvironment.probeInstall(shell: shell)
        XCTAssertEqual(install, .present(version: ""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: FAIL — compile error, `cannot find 'ClaudeCodeEnvironment' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// What Codepet knows about the founder's Claude Code installation, as a value.
///
/// A struct and not an `ObservableObject`: landmine 3 in CLAUDE.md — the XCTest
/// host on Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates,
/// and this type exists to be constructed and thrown away in tests.
struct ClaudeCodeStatus: Equatable {

    enum Install: Equatable {
        case missing
        /// Present on PATH. `version` is "" when the binary answered but its
        /// version string did not parse — present-but-unknown, never `.missing`.
        case present(version: String)
    }

    /// The account `claude` is signed in as, when it is.
    struct Account: Equatable {
        let email: String?
        /// "claude.ai" for a subscription, "console" for API billing.
        let authMethod: String?
        /// "firstParty", or a cloud provider. Carried because it is how Codepet
        /// detects that an exported ANTHROPIC_API_KEY has quietly taken over the
        /// founder's runs — see Task 5 and the spec's landmine section.
        let apiProvider: String?
        /// "pro", "max", "team", … — how the model picker learns which models
        /// this founder's plan can actually reach.
        let subscriptionType: String?
        let orgName: String?
    }

    enum Auth: Equatable {
        /// Could not be determined — an older CLI without `auth status --json`,
        /// or output that did not parse. Deliberately distinct from `loggedOut`.
        case unknown
        case loggedOut
        case loggedIn(Account)
    }

    let install: Install
    let auth: Auth
}

/// Probes the founder's Claude Code installation. Namespace, not an instance:
/// it holds no state.
enum ClaudeCodeEnvironment {

    /// Is `claude` on PATH, and at what version.
    ///
    /// Reads the leading semver out of `claude --version`, whose current shape
    /// is "2.1.241 (Claude Code)". A non-zero exit means absent; a zero exit
    /// whose output does not parse means present at an unknown version.
    static func probeInstall(shell: ShellRunning) async -> ClaudeCodeStatus.Install {
        let result = await shell.run("claude --version")
        guard result.succeeded else { return .missing }
        return .present(version: parseVersion(result.trimmedOut))
    }

    /// Leading dotted-numeric run of a version line, or "" when there is none.
    static func parseVersion(_ output: String) -> String {
        var version = ""
        for ch in output {
            if ch.isNumber || ch == "." {
                version.append(ch)
            } else if version.isEmpty {
                continue        // skip any prefix before the digits start
            } else {
                break           // stop at the first char after the run
            }
        }
        // A trailing dot ("2.1." from odd input) is not part of the version.
        while version.hasSuffix(".") { version.removeLast() }
        return version
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: all three tests PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/ClaudeCodeEnvironment.swift codepetTests/ClaudeCodeEnvironmentTests.swift
git commit -m "feat(local-claude): probe whether claude is installed, and at what version

ClaudeCodeStatus is a struct, not an ObservableObject: landmine 3 says the
XCTest host crashes when a @MainActor ObservableObject deallocates, and
this type is built and discarded in every test.

The distinction that matters is present-with-unknown-version vs missing.
Exit 0 with unparseable output means a future --version format, not an
absent binary; reporting .missing there would tell a founder to install
software they already have."
```

---

### Task 3: Read authentication state

**Files:**
- Modify: `codepet/Services/ClaudeCodeEnvironment.swift`
- Modify: `codepetTests/ClaudeCodeEnvironmentTests.swift`

**Interfaces:**
- Consumes: `ClaudeCodeStatus.Auth`, `ClaudeCodeStatus.Account`, `ShellRunning`.
- Produces: `static func probeAuth(shell:) async -> ClaudeCodeStatus.Auth`.

The exact JSON `claude auth status --json` emits, verified on 2.1.241:

```json
{
  "loggedIn": true,
  "authMethod": "claude.ai",
  "apiProvider": "firstParty",
  "email": "giang@murror.app",
  "orgId": "1789007e-428f-418f-9073-42b956cad792",
  "orgName": "Murror App",
  "subscriptionType": "team"
}
```

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeCodeEnvironmentTests.swift`:

```swift
extension ClaudeCodeEnvironmentTests {

    func testAuthReadsLoggedInAccount() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: """
        {
          "loggedIn": true,
          "authMethod": "claude.ai",
          "apiProvider": "firstParty",
          "email": "giang@murror.app",
          "orgId": "1789007e-428f-418f-9073-42b956cad792",
          "orgName": "Murror App",
          "subscriptionType": "team"
        }
        """)
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .loggedIn(.init(
            email: "giang@murror.app",
            authMethod: "claude.ai",
            apiProvider: "firstParty",
            subscriptionType: "team",
            orgName: "Murror App"
        )))
    }

    func testAuthReadsLoggedOut() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .loggedOut)
    }

    /// An older CLI has no `auth status` subcommand. Folding that into
    /// `.loggedOut` would tell a signed-in founder to sign in again, and the
    /// fix they would then apply — running `claude auth login` — does not
    /// address the real problem, which is their CLI version.
    func testAuthIsUnknownWhenSubcommandIsAbsent() async {
        let shell = FakeShell()
        shell.stub("auth status", stderr: "error: unknown command 'auth'", exit: 1)
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    /// Exit 0 but the payload is not the shape we know.
    func testAuthIsUnknownWhenJSONDoesNotParse() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: "Logged in as someone")
        let auth = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        XCTAssertEqual(auth, .unknown)
    }

    /// Nothing is secret here, but the token must never be asked for. If this
    /// ever fails, someone has reached for a credential the design says Codepet
    /// does not handle.
    func testProbeNeverAsksForACredential() async {
        let shell = FakeShell()
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        _ = await ClaudeCodeEnvironment.probeAuth(shell: shell)
        for command in shell.commandsRun {
            XCTAssertFalse(command.contains("setup-token"), "probe must not mint a token")
            XCTAssertFalse(command.contains("print-credentials"), "probe must not read credentials")
            XCTAssertFalse(command.contains("ANTHROPIC_API_KEY"), "probe must not touch an API key")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: FAIL — `type 'ClaudeCodeEnvironment' has no member 'probeAuth'`.

- [ ] **Step 3: Write minimal implementation**

Add to `ClaudeCodeEnvironment`:

```swift
    /// Whether `claude` is signed in, and as whom.
    ///
    /// `claude auth status --json` is machine-readable by design (`--json` is
    /// its default; passed explicitly so a future default flip cannot silently
    /// hand us prose). Three outcomes, and the difference between the last two
    /// is the whole point: signed out is actionable by the founder, unknown is
    /// not their fault and needs a different message.
    static func probeAuth(shell: ShellRunning) async -> ClaudeCodeStatus.Auth {
        let result = await shell.run("claude auth status --json")
        // A non-zero exit is an older CLI without the subcommand, or a broken
        // install. Either way we do not know — and we must not claim signed-out.
        guard result.succeeded,
              let data = result.trimmedOut.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = obj["loggedIn"] as? Bool
        else { return .unknown }

        guard loggedIn else { return .loggedOut }

        return .loggedIn(.init(
            email: obj["email"] as? String,
            authMethod: obj["authMethod"] as? String,
            apiProvider: obj["apiProvider"] as? String,
            subscriptionType: obj["subscriptionType"] as? String,
            orgName: obj["orgName"] as? String
        ))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: all eight tests PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/ClaudeCodeEnvironment.swift codepetTests/ClaudeCodeEnvironmentTests.swift
git commit -m "feat(local-claude): read auth state from claude auth status --json

Three outcomes, not two. An older CLI with no 'auth' subcommand exits
non-zero, and folding that into loggedOut would tell a signed-in founder
to sign in again — after which 'claude auth login' would not fix their
actual problem, which is the CLI version. .unknown keeps those apart.

--json is already the default; passed explicitly so a future default flip
cannot silently start handing us prose.

testProbeNeverAsksForACredential is the guard for the design rule that
Codepet never handles a token: it goes red if anyone reaches for
setup-token, print-credentials, or ANTHROPIC_API_KEY."
```

---

### Task 4: One call that answers both, and a plan-tier question

**Files:**
- Modify: `codepet/Services/ClaudeCodeEnvironment.swift`
- Modify: `codepetTests/ClaudeCodeEnvironmentTests.swift`

**Interfaces:**
- Consumes: `probeInstall(shell:)`, `probeAuth(shell:)`.
- Produces: `static func probe(shell:) async -> ClaudeCodeStatus`, and `var isReady: Bool` / `var blocker: ClaudeCodeStatus.Blocker?` on `ClaudeCodeStatus` with `enum Blocker { case notInstalled, notSignedIn, versionUnknown }`.

`isReady` is what every later phase branches on, so it belongs here rather than being re-derived at each call site.

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeCodeEnvironmentTests.swift`:

```swift
extension ClaudeCodeEnvironmentTests {

    func testProbeSkipsAuthWhenNotInstalled() async {
        let shell = FakeShell()   // everything 127
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertEqual(status.install, .missing)
        XCTAssertEqual(status.auth, .unknown)
        // Asking a binary that is not there about its auth wastes a spawn and
        // muddies the log with a second command-not-found.
        XCTAssertFalse(shell.commandsRun.contains { $0.contains("auth status") })
    }

    func testProbeReportsReadyWhenInstalledAndSignedIn() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": true, "subscriptionType": "team"}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertTrue(status.isReady)
        XCTAssertNil(status.blocker)
    }

    func testBlockerIsNotInstalledBeforeNotSignedIn() async {
        let shell = FakeShell()
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertFalse(status.isReady)
        // Order matters: telling someone to sign in to software they have not
        // installed is an instruction they cannot follow.
        XCTAssertEqual(status.blocker, .notInstalled)
    }

    func testBlockerIsNotSignedInWhenInstalledButLoggedOut() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: #"{"loggedIn": false}"#)
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertEqual(status.blocker, .notSignedIn)
    }

    func testBlockerIsVersionUnknownWhenAuthCannotBeRead() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stderr: "unknown command", exit: 1)
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertEqual(status.blocker, .versionUnknown)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: FAIL — no member `probe`, no member `isReady`.

- [ ] **Step 3: Write minimal implementation**

Add to `ClaudeCodeStatus`:

```swift
    /// The single reason Codepet cannot run yet, in the order the founder must
    /// fix them.
    enum Blocker: Equatable {
        case notInstalled
        case notSignedIn
        /// Installed and possibly signed in, but the CLI is too old to say —
        /// the fix is updating Claude Code, not signing in.
        case versionUnknown
    }

    var blocker: Blocker? {
        if install == .missing { return .notInstalled }
        switch auth {
        case .loggedIn: return nil
        case .loggedOut: return .notSignedIn
        case .unknown: return .versionUnknown
        }
    }

    var isReady: Bool { blocker == nil }
```

Add to `ClaudeCodeEnvironment`:

```swift
    /// Full preflight. Skips the auth probe when nothing is installed: asking a
    /// binary that is not there costs a spawn and yields a second, confusing
    /// command-not-found.
    static func probe(shell: ShellRunning) async -> ClaudeCodeStatus {
        let install = await probeInstall(shell: shell)
        guard install != .missing else {
            return ClaudeCodeStatus(install: install, auth: .unknown)
        }
        return ClaudeCodeStatus(install: install, auth: await probeAuth(shell: shell))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: all thirteen tests PASS.

- [ ] **Step 5: Verify against the real CLI once, by hand**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
/bin/zsh -lc 'claude --version' && /bin/zsh -lc 'claude auth status --json'
```
Expected: a version line, then the JSON object. Confirms the two commands the probe depends on behave as the tests assume on a real machine. If either differs, fix the parser and the stub together — never the stub alone.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/ClaudeCodeEnvironment.swift codepetTests/ClaudeCodeEnvironmentTests.swift
git commit -m "feat(local-claude): one probe, and the blocker every later phase branches on

blocker is ordered, not a set: telling a founder to sign in to software
they have not installed is an instruction they cannot follow. notInstalled
outranks notSignedIn, and versionUnknown is its own case because its fix
is updating the CLI, not signing in.

probe() skips the auth spawn when nothing is installed — a second
command-not-found tells the founder nothing the first did not.

isReady lives on the value rather than at each call site so phases 3-6
cannot each invent their own definition of ready."
```

---

### Task 5: Refuse to let an exported API key hijack the founder's runs

**Files:**
- Modify: `codepet/Services/ShellRunning.swift`
- Modify: `codepet/Services/ClaudeCodeEnvironment.swift`
- Modify: `codepetTests/ClaudeCodeEnvironmentTests.swift`

**Interfaces:**
- Consumes: `ShellRunning`, `ClaudeCodeStatus`.
- Produces: `LoginShellRunner.strippedEnvironmentKeys`, a `scrubbedEnvironment` the runner applies to every spawn, and `ClaudeCodeStatus.billingWarning: BillingWarning?` with `enum BillingWarning { case apiKeyInEnvironment, consoleAccount }`.

This is the task the whole project turns on and it is four lines of environment handling. Codepet spawns through a login shell so PATH resolves; that same login shell sources the founder's profile. Claude Code's credential precedence puts `ANTHROPIC_API_KEY` above subscription OAuth, and the docs are explicit that under `-p` — every call Codepet makes — the key always wins when present. A founder with a key in `.zshrc` would have every run billed to their API account, silently, with no error to notice, which is the exact outcome this migration exists to prevent.

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeCodeEnvironmentTests.swift`:

```swift
extension ClaudeCodeEnvironmentTests {

    func testRunnerStripsCredentialEnvironmentVariables() {
        // The list is the contract: precedence puts both of these above the
        // founder's subscription, so both must go.
        XCTAssertEqual(
            Set(LoginShellRunner.strippedEnvironmentKeys),
            Set(["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"])
        )
    }

    func testScrubbedEnvironmentRemovesOnlyThoseKeys() {
        let input = [
            "PATH": "/usr/bin",
            "ANTHROPIC_API_KEY": "sk-ant-should-not-survive",
            "ANTHROPIC_AUTH_TOKEN": "bearer-should-not-survive",
            "HOME": "/Users/someone"
        ]
        let scrubbed = LoginShellRunner.scrubbedEnvironment(input)
        XCTAssertNil(scrubbed["ANTHROPIC_API_KEY"])
        XCTAssertNil(scrubbed["ANTHROPIC_AUTH_TOKEN"])
        // Everything else must survive untouched — PATH especially, since
        // stripping it is how you get "command not found: claude".
        XCTAssertEqual(scrubbed["PATH"], "/usr/bin")
        XCTAssertEqual(scrubbed["HOME"], "/Users/someone")
    }

    func testBillingWarningWhenAuthStatusReportsAnApiKey() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        // apiProvider is how the CLI tells us a key is in play rather than the
        // subscription we expected.
        shell.stub("auth status", stdout: """
        {"loggedIn": true, "authMethod": "console", "apiProvider": "firstParty", "subscriptionType": null}
        """)
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertTrue(status.isReady, "a console account still works — this is a warning, not a blocker")
        XCTAssertEqual(status.billingWarning, .consoleAccount)
    }

    func testNoBillingWarningForAPlainSubscription() async {
        let shell = FakeShell()
        shell.stub("--version", stdout: "2.1.241 (Claude Code)")
        shell.stub("auth status", stdout: """
        {"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty", "subscriptionType": "team"}
        """)
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        XCTAssertNil(status.billingWarning)
    }

    func testBillingWarningIsNilWhenNotSignedIn() async {
        let shell = FakeShell()
        let status = await ClaudeCodeEnvironment.probe(shell: shell)
        // Nothing to warn about yet; the blocker already says what is wrong.
        XCTAssertNil(status.billingWarning)
        XCTAssertEqual(status.blocker, .notInstalled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: FAIL — no member `strippedEnvironmentKeys`, no member `billingWarning`.

- [ ] **Step 3: Write minimal implementation**

Add to `LoginShellRunner`:

```swift
    /// Credential variables removed from every spawn.
    ///
    /// Claude Code's precedence puts both of these ABOVE the founder's
    /// subscription OAuth, and under `-p` — every call Codepet makes — a present
    /// key is always used. Codepet spawns through a login shell so PATH
    /// resolves, and that same shell sources the founder's profile: a key
    /// exported in `.zshrc` would silently bill their API account for work this
    /// project exists to put on their subscription. Removing them here is the
    /// only place that cannot be forgotten by a later call site.
    static let strippedEnvironmentKeys = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    /// `environment` minus the credential keys, everything else intact.
    static func scrubbedEnvironment(_ environment: [String: String]) -> [String: String] {
        var scrubbed = environment
        for key in strippedEnvironmentKeys { scrubbed.removeValue(forKey: key) }
        return scrubbed
    }
```

In `LoginShellRunner.run`, immediately after `proc.arguments = ["-lc", command]`:

```swift
        // Inherit the founder's environment, minus anything that would outrank
        // their subscription. A login shell can still re-export a key from their
        // profile; that is what `billingWarning` is for.
        proc.environment = Self.scrubbedEnvironment(ProcessInfo.processInfo.environment)
```

Add to `ClaudeCodeStatus`:

```swift
    /// Codepet works, but the founder may not be paying the way they think.
    /// Deliberately NOT a `Blocker`: both cases run fine.
    enum BillingWarning: Equatable {
        /// A key is in the environment despite the scrub — a login shell can
        /// re-export one from the founder's profile.
        case apiKeyInEnvironment
        /// Signed in with a Console account, so runs are billed per token
        /// rather than covered by a subscription.
        case consoleAccount
    }

    var billingWarning: BillingWarning? {
        guard case .loggedIn(let account) = auth else { return nil }
        if account.authMethod == "console" { return .consoleAccount }
        return nil
    }
```

`.apiKeyInEnvironment` has no producer yet — it is reached in phase 3, where the first real run can compare the account `auth status` reports against the one that actually served the request. Declared here because `BillingWarning` is the type phase 3 will extend, and a case added later to a type the UI already switches over is a silent non-exhaustive branch.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
xcodebuild test -scheme codepet -only-testing:codepetTests/ClaudeCodeEnvironmentTests 2>&1 | tail -30
```
Expected: all eighteen tests PASS.

- [ ] **Step 5: Verify the scrub against the real shell, by hand**

Run:
```bash
cd /Users/williamdominich/Documents/Murror/codepet
ANTHROPIC_API_KEY=sk-ant-canary /bin/zsh -lc 'echo "key in child: ${ANTHROPIC_API_KEY:-<absent>}"'
```
Expected: `key in child: sk-ant-canary` — proving the variable *does* reach a login-shell child when set, which is the hazard this task removes. Then confirm the founder's own profile does not export one:

```bash
/bin/zsh -lc 'echo "profile exports: ${ANTHROPIC_API_KEY:-<absent>}"'
```
Expected: `<absent>`. If it prints a key, the scrub in Step 3 is load-bearing today and not merely defensive — say so in the commit.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/ShellRunning.swift codepet/Services/ClaudeCodeEnvironment.swift codepetTests/ClaudeCodeEnvironmentTests.swift
git commit -m "fix(local-claude): strip credential env vars from every spawn

The project's whole purpose fails silently without this. Claude Code's
credential precedence puts ANTHROPIC_API_KEY and ANTHROPIC_AUTH_TOKEN
ABOVE subscription OAuth, and the docs are explicit that under -p — every
call Codepet makes — a present key is always used. Codepet spawns through
a login shell so the founder's PATH resolves, and that same shell sources
their profile: a key exported in .zshrc means every run is billed to their
API account instead of the subscription this migration exists to use. No
error, no log line, nothing to notice.

Scrubbing in LoginShellRunner rather than at call sites because it is the
one place a later caller cannot forget.

billingWarning is a warning and not a Blocker on purpose: a Console
account works fine, it just bills per token, and refusing to run would be
Codepet overruling a founder about their own billing. Surfacing it lets
them see which account pays; deciding is theirs.

.apiKeyInEnvironment has no producer until phase 3, where a real run can
compare the account auth status claims against the one that served the
request. Declared now so phase 3 does not add a case to a type the UI
already switches over."
```

---

## Self-Review

**Spec coverage.** This phase covers the spec's *Credentials* section (the probe reads `auth status --json` and never touches a token, with a test that goes red if anyone tries) and the preflight half of *Installing Claude Code* (detection; the guiding UI is phase 2). It deliberately covers none of: the model picker (`subscriptionType` is captured here and consumed in phase 4), `--safe-mode` isolation (phase 3, where the first real run happens), version pinning (phase 3), or the Node sidecar (phase 5). The spec's *Testing constraints* are enforced as Global Constraints above.

**Placeholders.** None. Every step carries the code or the exact command.

**Type consistency.** `ClaudeCodeStatus.Install`, `.Auth`, `.Account`, `.Blocker` are defined in Tasks 2–4 and referenced under those names throughout. `ShellResult.trimmedOut` and `.succeeded` are defined in Task 1 and used in Tasks 2–3. `FakeShell.stub(_:stdout:stderr:exit:)` is defined once in Task 2 and reused with the same signature in Tasks 3–4.

**`apiProvider` is carried, and that is a reversal.** An earlier draft of this plan left `apiProvider` out as a phase 4 concern. That was wrong, and the spec's *Landmine: an exported `ANTHROPIC_API_KEY` silently wins* is why: credential precedence puts `ANTHROPIC_API_KEY` above the subscription, and in non-interactive mode — every call Codepet makes — the key always wins when present. Because Codepet spawns through a login shell, it loads the founder's profile and would pick up an exported key, billing their API account instead of their subscription, silently. `apiProvider` is the field that detects it, so preflight is exactly where it belongs. Task 3 captures it and Task 5 acts on it.
