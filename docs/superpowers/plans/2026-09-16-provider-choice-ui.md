# Provider Choice UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Codex provider reachable by a founder — choose it on the run card, grant it at first use, and be told the truth about which plan paid for a deliverable.

**Architecture:** Generalise the CLI probe from one hard-coded binary to a per-provider one; give `transport()` a provider precedence and a per-call override; record provenance on the deliverable so the card can state it; then three surfaces (run card, blocked state, Settings/onboarding) read those facts.

**Tech Stack:** Swift 5 / SwiftUI, macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-16-provider-choice-ui-design.md`

## Global Constraints

- **Consent is never transitive.** A Codex grant must not write, read, or imply `cp_claude_authorised_<companyId>`, and the reverse. `ProviderAuthorisation.key` stays written per-`case`, never derived from `rawValue`, so an enum rename cannot move a live grant.
- **Never claim signed-out without evidence.** `CLIStatus.Auth` has three cases for this reason; `.unknown` is the answer whenever the probe cannot tell. Claude's own comment: "signed-out is something the founder can act on, unknown is not their fault."
- **Never render one provider's model id on the other provider's run.** Codex reports no model; the sidecar already labels its stand-in as requested-not-confirmed.
- **An offer that changes nothing must not appear.** The other-provider offer renders only when that CLI is installed — the existing `localBuildAvailable` discipline.
- **The Aug 10 footer rule holds:** "a card that always carries a status line teaches you to stop reading it." Provenance renders only when it is actually recorded.
- **Probe by PATH first, absolute paths as fallback.** Codex's Homebrew cask links to `/opt/homebrew/bin/codex` on Apple Silicon; `/usr/local/bin/codex` must not be hard-coded as the only path.
- Tests must not write founder prefs. Inject the store/shell — never touch real `UserDefaults`.
- Branch from `spec/provider-choice-ui`. Do not commit to `main`.

## Verified Codex facts (use these verbatim — do not re-derive or guess)

Recorded in `.superpowers/sdd/codex-cli-findings.md`, which is **gitignored scratch**; these are
repeated here because this file is tracked and that one can be destroyed by `git clean -fdx`.

| Fact | Value | How it was verified |
| --- | --- | --- |
| Version command | `codex --version` → `codex-cli 0.154.0` | Run on this machine |
| Install location | `/opt/homebrew/bin/codex` (Homebrew **cask**) | `which codex` after `brew install codex` |
| npm global install | Fails with EACCES on this machine | `npm install -g @openai/codex` |
| Signed in | `codex login status` → exit **0**, `Logged in using ChatGPT` | Run against real credentials |
| Signed OUT | `codex login status` → exit **1**, `Not logged in` | `CODEX_HOME=/tmp/codex-empty-probe`, real `~/.codex/auth.json` confirmed untouched |
| Account detail | **None.** No email, no plan type, no JSON | Same runs — Codex prints one prose line |

**`CLIEnvironment.parseVersion` already handles Codex unchanged.** Hand-traced against
`"codex-cli 0.154.0"`: every character before the first digit is skipped while `version` is
empty, the digit-and-dot run accumulates `0.154.0`, and the loop breaks at end of input with no
trailing dot to strip. Do not write a second parser.

**Still unverified:** the first-run interactive `codex login` flow. No task below depends on it;
do not write a test that asserts its behaviour.

---

### Task 1: Per-provider CLI probe

Today `CLIStatus` describes one CLI and `CLIEnvironment` probes three hard-coded `claude`
paths. Every screen in this plan branches on "which provider is installed", so this comes first.

**Files:**
- Modify: `codepet/Services/CLIEnvironment.swift`
- Test: `codepetTests/CLIEnvironmentTests.swift`

**Interfaces:**
- Consumes: `AIProvider` (`codepet/Models/AIProvider.swift`), `ShellRunning`.
- Produces: `CLIEnvironment.spec(for: AIProvider) -> CLISpec`; `CLIEnvironment.probe(provider:shell:authorised:) async -> CLIStatus`; `CLIStatus.provider: AIProvider`; `InstalledProviders` (below).
- **`InstalledProviders` lands here, not later.** Tasks 5, 8 and 9 all branch on "which CLI is installed", and a cache created in the last of them would leave the earlier two half-wired.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/CLIEnvironmentTests.swift`. `FakeShell` already exists in this file
(matches a canned response by command substring, falling back to exit 127).

```swift
// MARK: - Per-provider probe

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
func testCodexSignedOutIsNotReportedAsUnknown() async {
    let shell = FakeShell()
    shell.stub("codex login status", stdout: "Not logged in", exit: 1)
    let auth = await CLIEnvironment.probeAuth(provider: .codex, shell: shell)
    XCTAssertEqual(auth, .loggedOut)
}

/// The Claude JSON parser must not be pointed at Codex, and vice versa. A provider
/// whose probe returns something unparseable is `.unknown` — never a false signed-out.
func testCodexGibberishIsUnknownNotSignedOut() async {
    let shell = FakeShell()
    shell.stub("codex login status", stdout: "�garbage�", exit: 3)
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
```

`FakeShell.stub(...)` already accepts `exit:` with a default of `0`. Use it; do not write a
second fake.

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/CLIEnvironmentTests 2>&1 | tail -30`
Expected: FAIL — no `probeInstall(provider:shell:)` overload exists.

- [ ] **Step 3: Add the per-provider spec and probes**

In `codepet/Services/CLIEnvironment.swift`, add `provider` to `CLIStatus` and introduce a spec
per provider. Keep the existing single-provider entry points delegating to the new ones so no
call site breaks in this task.

```swift
/// What differs between one CLI and another. Everything else about probing is shared.
///
/// A struct of values rather than a protocol: the two providers differ only in strings and
/// in how one line of output is read, and a protocol would be a ceremony around a table.
/// This mirrors `CliAdapter` on the TypeScript side deliberately — same seam, same reason.
struct CLISpec {
    let binary: String
    /// Tried by absolute path only when PATH resolution fails. A founder whose shell
    /// profile the installer never touched has the binary installed and invisible, and
    /// telling them to install software they already have is the specific wrong answer.
    let knownInstallPaths: [String]
    /// The sub-command that answers "is this signed in", and how to read its answer.
    let authCommand: String
    let readAuth: (ShellResult) -> CLIStatus.Auth
}

extension CLIEnvironment {

    static func spec(for provider: AIProvider) -> CLISpec {
        switch provider {
        case .claudeCode:
            return CLISpec(
                binary: "claude",
                knownInstallPaths: ["~/.local/bin/claude",
                                    "/opt/homebrew/bin/claude",
                                    "/usr/local/bin/claude"],
                authCommand: "claude auth status --json",
                readAuth: readClaudeAuth
            )
        case .codex:
            // Homebrew ships Codex as a CASK, linked to /opt/homebrew/bin on Apple
            // silicon — verified on a real install, where the npm global route failed
            // with EACCES. /usr/local/bin is kept for Intel and a writable npm prefix.
            return CLISpec(
                binary: "codex",
                knownInstallPaths: ["/opt/homebrew/bin/codex",
                                    "/usr/local/bin/codex",
                                    "~/.local/bin/codex"],
                authCommand: "codex login status",
                readAuth: readCodexAuth
            )
        }
    }

    static func probeInstall(provider: AIProvider, shell: ShellRunning) async -> CLIStatus.Install {
        let spec = spec(for: provider)
        let onPath = await shell.run("\(spec.binary) --version")
        if onPath.succeeded { return .present(version: parseVersion(onPath.trimmedOut)) }
        for path in spec.knownInstallPaths {
            let expanded = (path as NSString).expandingTildeInPath
            let direct = await shell.run("\"\(expanded)\" --version")
            if direct.succeeded { return .present(version: parseVersion(direct.trimmedOut)) }
        }
        return .missing
    }

    static func probeAuth(provider: AIProvider, shell: ShellRunning) async -> CLIStatus.Auth {
        let spec = spec(for: provider)
        return spec.readAuth(await shell.run(spec.authCommand))
    }

    /// Claude answers in JSON, by design — `--json` is passed explicitly so a future
    /// default flip cannot silently start handing us prose.
    static func readClaudeAuth(_ result: ShellResult) -> CLIStatus.Auth {
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

    /// Codex answers in one prose line and reports NOTHING about the account — no email,
    /// no plan type. Verified on the real binary: exit 0 "Logged in using ChatGPT",
    /// exit 1 "Not logged in". Keyed on the exit code with the string as corroboration,
    /// because an exit code cannot be reworded by a release note.
    ///
    /// An empty `Account` is the honest answer for signed-in-but-anonymous. Anything that
    /// matches neither shape is `.unknown`, never `.loggedOut`.
    static func readCodexAuth(_ result: ShellResult) -> CLIStatus.Auth {
        let out = result.trimmedOut.lowercased()
        if result.succeeded, out.contains("logged in") {
            return .loggedIn(.init(email: nil, authMethod: nil, apiProvider: nil,
                                   subscriptionType: nil, orgName: nil))
        }
        if out.contains("not logged in") { return .loggedOut }
        return .unknown
    }

    static func probe(provider: AIProvider,
                      shell: ShellRunning = LoginShellRunner(),
                      authorised: Bool) async -> CLIStatus {
        let install = await probeInstall(provider: provider, shell: shell)
        guard install != .missing else {
            return CLIStatus(provider: provider, install: install,
                             auth: .unknown, authorised: authorised)
        }
        return CLIStatus(provider: provider, install: install,
                         auth: await probeAuth(provider: provider, shell: shell),
                         authorised: authorised)
    }
}
```

Add `let provider: AIProvider` to `CLIStatus` and give `unprobed` a provider:

```swift
    let provider: AIProvider
    ...
    /// Nothing probed yet. Distinct from a probe that ran and found nothing.
    static func unprobed(_ provider: AIProvider = .claudeCode) -> CLIStatus {
        CLIStatus(provider: provider, install: .missing, auth: .unknown, authorised: false)
    }
```

`static let unprobed` becomes a function, so fix its call sites (`ClaudeCodePanel.swift:24` at
minimum) to `.unprobed()`. Let the compiler find them: `grep -rn "\.unprobed" codepet codepetTests`.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/CLIEnvironmentTests 2>&1 | tail -30`
Expected: PASS, including the pre-existing tests in this file.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/CLIEnvironment.swift codepet/Managers/InstalledProviders.swift codepetTests/CLIEnvironmentTests.swift
git commit -m "feat: probe each CLI provider independently"
```

- [ ] **Step 6: Add the install cache the UI reads**

Create `codepet/Managers/InstalledProviders.swift`. No render path may spawn a subprocess, and
`transport()`'s comment gives the reason it refuses to probe: "that costs a subprocess per call".

```swift
/// Which CLIs are on this Mac, probed once rather than per render.
///
/// A stale-but-cheap answer is the right trade here: a founder who installs a CLI
/// mid-session sees the offer after the next refresh, and the alternative is a subprocess
/// every time a card draws. Settings and onboarding call `refresh()`; everything else reads
/// the cache.
@MainActor
final class InstalledProviders {
    private(set) var installed: Set<AIProvider> = []

    func refresh(shell: ShellRunning = LoginShellRunner()) async {
        var found: Set<AIProvider> = []
        for provider in AIProvider.allCases
        where await CLIEnvironment.probeInstall(provider: provider, shell: shell) != .missing {
            found.insert(provider)
        }
        installed = found
    }
}
```

Add a test that an un-refreshed cache reports nothing installed rather than guessing, and that
`refresh` against a `FakeShell` answering only `claude --version` yields exactly `[.claudeCode]`.

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/CLIEnvironmentTests 2>&1 | tail -30`
Expected: PASS.

---

### Task 2: Transport picks a provider, and a caller may override it

`LocalTransportRouter.transport()` hard-codes `.claudeCode` twice — once in the grant check,
once in the derived provider. Both are the lines this task replaces.

**Files:**
- Modify: `codepet/Services/LocalTransportRouter.swift:58-70` (`forOneShot`), `:110-135` (`transport`)
- Test: `codepetTests/LocalTransportRouterTests.swift`

**Interfaces:**
- Consumes: `ProviderAuthorisation.isAuthorised(_:_:)`, `AIProvider`.
- Produces: `forOneShot(companyId:authorisation:prefer:)` where `prefer: AIProvider? = nil`.

**Two existing tests are retired by this task, on purpose.**
`testNoGrantedCompanyRoutesToCodexThisPhase` and `testACodexGrantAloneDoesNotRouteLocal` pin
"Codex is unreachable"; their own doc comments say *this phase*. They are phase markers, not
invariants. Replace them with the tests below — do not delete them silently, and do not weaken
`testOneFoundersGrantDoesNotRouteAnothersCall`, which IS an invariant.

- [ ] **Step 1: Write the failing tests**

```swift
/// A founder who granted only Codex is a first-class founder. This is the case that was
/// impossible before, and the whole reason this phase exists.
func testACodexOnlyFounderRoutesToCodex() {
    codexGranted.insert("c1")
    XCTAssertTrue(granted.isEmpty, "setup sanity: no Claude grant exists")
    XCTAssertEqual(transport(companyId: "c1"), .local(.codex))
}

/// Claude wins when both are granted — today's behaviour, preserved. The spec ships the
/// run card's offer INSTEAD of a per-company default, so this precedence is the default.
func testClaudeWinsWhenBothAreGranted() {
    granted.insert("c1")
    codexGranted.insert("c1")
    XCTAssertEqual(transport(companyId: "c1"), .local(.claudeCode))
}

/// "Re-run on Codex" is this: the caller names the provider, and it is honoured even
/// though Claude would otherwise win.
func testAnExplicitPreferenceOverridesThePrecedence() {
    granted.insert("c1")
    codexGranted.insert("c1")
    XCTAssertEqual(transport(companyId: "c1", prefer: .codex), .local(.codex))
}

/// A preference is not a grant. Asking for a provider the founder never authorised must
/// block, not silently spend the other plan — a silent fallback makes "which plan paid
/// for this" unanswerable, which is the question this whole phase exists to answer.
func testAPreferenceForAnUngrantedProviderIsBlockedNotSubstituted() {
    granted.insert("c1")
    XCTAssertTrue(codexGranted.isEmpty, "setup sanity: no Codex grant")
    XCTAssertEqual(transport(companyId: "c1", prefer: .codex), .blocked(.notGranted))
}

func testNoGrantAtAllIsStillBlocked() {
    XCTAssertEqual(transport(companyId: "c1"), .blocked(.notGranted))
}
```

Extend the test helper's `transport(companyId:)` to forward a `prefer:` argument defaulting
to `nil`.

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/LocalTransportRouterTests 2>&1 | tail -30`
Expected: FAIL — no `prefer:` parameter; Codex-only blocks.

- [ ] **Step 3: Replace the two hard-coded `.claudeCode` lines**

```swift
    /// Which provider runs this call.
    ///
    /// **Precedence, not preference-by-default.** Claude wins a tie because it is the
    /// incumbent and because the spec deliberately ships NO per-company default — the run
    /// card's offer is how a founder deviates, and shipping the card first is how we learn
    /// whether a stored default is wanted at all.
    ///
    /// `prefer` is that deviation. It is honoured only when the founder has actually
    /// granted it: a preference is not consent, and substituting the other provider would
    /// spend a plan she did not pick.
    static func chooseProvider(companyId: String,
                               authorisation: ProviderAuthorisation,
                               prefer: AIProvider?) -> AIProvider? {
        if let prefer {
            return authorisation.isAuthorised(prefer, companyId) ? prefer : nil
        }
        for candidate in [AIProvider.claudeCode, .codex]
        where authorisation.isAuthorised(candidate, companyId) {
            return candidate
        }
        return nil
    }

    static func transport(
        companyId: String? = activeCompanyId,
        authorisation: ProviderAuthorisation = ProviderAuthorisation(),
        prefer: AIProvider? = nil,
        sidecarAvailable: () -> Bool
    ) -> Transport {
        guard let companyId, !companyId.isEmpty else {
            log.error("transport: blocked — no companyId (mirror unset)")
            return .blocked(.notGranted)
        }
        guard let provider = chooseProvider(companyId: companyId,
                                            authorisation: authorisation,
                                            prefer: prefer) else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) not granted")
            return .blocked(.notGranted)
        }
        guard sidecarAvailable() else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) granted but sidecar missing")
            return .blocked(.sidecarMissing)
        }
        log.error("transport: local — companyId=\(companyId, privacy: .public) provider=\(provider.rawValue, privacy: .public)")
        return .local(provider)
    }
```

Thread `prefer` through `forOneShot` only. **`forVirtualCompany` keeps no `prefer`** — meetings
stay Claude-only per the spec, and a parameter nobody may pass is an invitation to pass it.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/LocalTransportRouterTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/LocalTransportRouter.swift codepetTests/LocalTransportRouterTests.swift
git commit -m "feat: route one-shot ops to the granted provider, with an override"
```

---

### Task 3: The blocked state names the provider the founder can actually grant

Today a Codex-only founder hits `.blocked(.notGranted)` and reads *"Codepet needs permission to
use your Claude plan. Turn it on in Settings."* — wrong for her twice: she has a plan, just not
that one, and there is no Settings control for it yet.

**Files:**
- Modify: `codepet/Services/BlockReason.swift`
- Test: `codepetTests/BlockReasonTests.swift` (create if absent)

**Interfaces:**
- Produces: `BlockReason.notGrantedFor(AIProvider)`, `BlockReason.needsClaudeCode`.
- **Consumed by Task 9**, which is what makes `notGrantedProvider` reachable. This task
  adds the vocabulary; Task 9 adds the only producer. Neither is complete alone.

- [ ] **Step 1: Write the failing tests**

```swift
/// The grant a Codex-only founder is asked for must be the Codex one. Naming Claude
/// here is the specific wrong answer: she has a plan, just not that one.
func testTheCodexBlockAsksForTheCodexGrant() {
    let reason = BlockReason.notGrantedFor(.codex)
    XCTAssertTrue(reason.founderText.lowercased().contains("chatgpt"),
                  "expected the ChatGPT plan named, got: \(reason.founderText)")
    XCTAssertFalse(reason.founderText.lowercased().contains("claude"),
                   "must not name Claude to a Codex founder: \(reason.founderText)")
}

func testTheClaudeBlockStillAsksForTheClaudeGrant() {
    let reason = BlockReason.notGrantedFor(.claudeCode)
    XCTAssertTrue(reason.founderText.lowercased().contains("claude"))
}

/// Chat and meetings are Claude-only. The copy must name an action, because every other
/// BlockReason names one — a case that only states a fact would be the odd one out.
func testNeedsClaudeCodeNamesAnAction() {
    let text = BlockReason.needsClaudeCode.founderText.lowercased()
    XCTAssertTrue(text.contains("install") || text.contains("switch"),
                  "expected an action, got: \(BlockReason.needsClaudeCode.founderText)")
}

/// Every case carries both languages. A missing Vietnamese string renders English to a
/// Vietnamese founder, which reads as a bug rather than a fallback.
func testEveryNewCaseHasVietnamese() {
    for reason in [BlockReason.notGrantedFor(.codex),
                   .notGrantedFor(.claudeCode),
                   .needsClaudeCode] {
        XCTAssertFalse(reason.founderTextVi.isEmpty)
        XCTAssertNotEqual(reason.founderTextVi, reason.founderText)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/BlockReasonTests 2>&1 | tail -30`
Expected: FAIL — `notGrantedFor` and `needsClaudeCode` do not exist.

- [ ] **Step 3: Add the cases**

Add to `BlockReason`, keeping `notGranted` as-is so existing call sites compile:

```swift
    /// Granted nothing, and we know which plan to ask about. Separate from `notGranted`
    /// because the founder who has a ChatGPT plan and no Claude one is told to grant the
    /// thing she actually owns, rather than being sent to install a competitor.
    case notGrantedProvider(AIProvider)

    /// This surface runs on Claude Code and no other. Chat streaming and the virtual
    /// company meeting are the two: different protocol risk entirely — event framing, and
    /// an MCP tool story Codex's CLI may not have.
    case needsClaudeCode
```

Convenience so call sites read as prose: `static func notGrantedFor(_ p: AIProvider) -> BlockReason { .notGrantedProvider(p) }`

Copy, in the register the other four cases use — plain, naming an action:

```swift
        case .notGrantedProvider(.claudeCode):
            return "Codepet needs permission to use your Claude plan. Turn it on to continue."
        case .notGrantedProvider(.codex):
            return "Codepet needs permission to use your ChatGPT plan. Turn it on to continue."
        case .needsClaudeCode:
            return "Chat and meetings run on Claude Code. Install it, or switch this company to it."
```

```swift
        case .notGrantedProvider(.claudeCode):
            return "Codepet cần quyền dùng gói Claude của bạn. Hãy bật để tiếp tục."
        case .notGrantedProvider(.codex):
            return "Codepet cần quyền dùng gói ChatGPT của bạn. Hãy bật để tiếp tục."
        case .needsClaudeCode:
            return "Trò chuyện và cuộc họp chạy trên Claude Code. Hãy cài đặt, hoặc chuyển công ty này sang đó."
```

**Note the assertion/copy trap this plan is avoiding:** the Phase 1 plan asserted
`contains("install")` case-sensitively against copy beginning *"Install it…"*, and an implementer
satisfied both by lowercasing the sentence's first letter. Every assertion above lowercases the
copy before matching; do not "fix" a failure by editing the copy's capitalisation.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/BlockReasonTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/BlockReason.swift codepetTests/BlockReasonTests.swift
git commit -m "feat: block states name the provider the founder can grant"
```

---

### Task 4: Record which provider produced a deliverable

**`Deliverable` carries no provenance today** — no provider, no model. The spec's run-card line
cannot render without this, and no amount of view work substitutes for a fact that was never
stored.

**Files:**
- Modify: `codepet/Models/Deliverable.swift` (the `Deliverable` struct, ~line 293)
- Modify: `codepet/Managers/CompanyStore.swift:2933` (`buildDeliverable(from:task:)`)
- Test: `codepetTests/DeliverableProvenanceTests.swift` (create)

**Interfaces:**
- Produces: `Deliverable.producedBy: AIProvider?`.

- [ ] **Step 1: Write the failing tests**

```swift
/// Provenance is optional because every deliverable created before this field existed
/// has none — and a card that invents one would be worse than a card that says nothing.
func testADeliverableDecodedWithoutProvenanceHasNone() throws {
    let json = #"{"id":"d1","kind":"doc","title":"T","body":"B"}"#
    let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
    XCTAssertNil(d.producedBy)
}

func testProvenanceSurvivesARoundTrip() throws {
    var d = Deliverable(kind: .doc, title: "T", body: "B")
    d.producedBy = .codex
    let data = try JSONEncoder().encode(d)
    let back = try JSONDecoder().decode(Deliverable.self, from: data)
    XCTAssertEqual(back.producedBy, .codex)
}

/// An unrecognised provider string must not throw and take the whole deliverable with
/// it — a future provider id read by an older build degrades to "unknown", not a crash.
func testAnUnknownProviderStringDegradesToNil() throws {
    let json = #"{"id":"d1","kind":"doc","title":"T","body":"B","producedBy":"gemini"}"#
    let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
    XCTAssertNil(d.producedBy)
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/DeliverableProvenanceTests 2>&1 | tail -30`
Expected: FAIL — `producedBy` does not exist.

- [ ] **Step 3: Add the field and stamp it**

On `Deliverable`:

```swift
    /// Which founder plan paid for this deliverable.
    ///
    /// Optional, and permanently so: every deliverable written before 16 Sep 2026 has no
    /// provenance, and there is no honest way to backfill one. The card renders this only
    /// when it is present — the Aug 10 rule, that a card which always carries a status
    /// line teaches you to stop reading it.
    ///
    /// Stored as the provider, not the model id. "Which plan paid for this" is the
    /// question a founder asks; the model that answered is a different, noisier fact, and
    /// on Codex it is not reported at all.
    var producedBy: AIProvider? = nil
```

`Deliverable` uses the SYNTHESISED `Codable` today — no `CodingKeys` block exists, so every key
is the property name (`createdAt`, `sourceTaskId`). Lenient decoding needs a custom
`init(from:)`, which needs an explicit `CodingKeys`.

**Danger: once you write that block you own every key string.** Get one of the seven existing
names wrong and every stored deliverable fails to decode. Copy them EXACTLY, and add
`producedBy` in the same camelCase style — do not give the new field a snake_case key of its
own. Decode it **leniently** so an unknown string degrades rather than throws:

```swift
        producedBy = (try? c.decodeIfPresent(String.self, forKey: .producedBy))
            .flatMap { $0 }
            .flatMap(AIProvider.init(rawValue:))
```

A plain `decodeIfPresent(AIProvider.self, …)` would THROW on an unknown rawValue and take the
whole deliverable with it — that is the failure the third test exists to prevent. Decode the
raw `String` first, then map it through `AIProvider(rawValue:)`.

You must also write `encode(to:)` to match, or the synthesised encoder disappears with the
synthesised decoder and the round-trip test fails.

At `CompanyStore.swift:2933`, stamp the provider that actually ran. `buildDeliverable` has no
provider argument today; add one and pass it from each of the five call sites (2468, 2875, 2894,
3048, 3316), which learn it from the `Transport` they routed through. Do **not** default the
parameter — a defaulted provenance is how a Codex run gets stamped "Claude" silently.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/DeliverableProvenanceTests 2>&1 | tail -30`
Then the full suite: `xcodebuild test -scheme codepet 2>&1 | tail -20`
Expected: PASS. Any decode test elsewhere that round-trips a `Deliverable` must still pass.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/Deliverable.swift codepet/Managers/CompanyStore.swift codepetTests/DeliverableProvenanceTests.swift
git commit -m "feat: record which provider produced a deliverable"
```

---

### Task 5: The card says where it ran, and offers the other

**Files:**
- Modify: `codepet/Views/Library/DeliverableStyle.swift` (`DeliverableFrame`, line 78)
- Create: `codepet/Views/Library/ProvenanceRow.swift`
- Test: `codepetTests/ProvenanceRowTests.swift` (create)

**Interfaces:**
- Consumes: `Deliverable.producedBy` (Task 4), `CLIStatus` (Task 1), `AIProvider.displayName`.
- Produces: `ProvenanceRow.text(for:lang:)`, `ProvenanceRow.offer(producedBy:otherInstalled:) -> AIProvider?`.

Keep the logic in static functions, tested directly. A SwiftUI body is not the place to put a
decision, and the XCTest host on Xcode 26.2 crashes on `@MainActor ObservableObject` dealloc —
landmine 3 in CLAUDE.md.

- [ ] **Step 1: Write the failing tests**

```swift
func testTheRowNamesTheProviderThatRan() {
    XCTAssertEqual(ProvenanceRow.text(for: .codex, lang: .en), "Ran on Codex")
    XCTAssertEqual(ProvenanceRow.text(for: .claudeCode, lang: .en), "Ran on Claude Code")
}

/// An offer that changes nothing must not appear — the `localBuildAvailable` discipline.
func testNoOfferWhenTheOtherCLIIsNotInstalled() {
    XCTAssertNil(ProvenanceRow.offer(producedBy: .claudeCode, otherInstalled: false))
}

func testTheOfferIsTheOtherProvider() {
    XCTAssertEqual(ProvenanceRow.offer(producedBy: .claudeCode, otherInstalled: true), .codex)
    XCTAssertEqual(ProvenanceRow.offer(producedBy: .codex, otherInstalled: true), .claudeCode)
}

/// A Codex run must never render a Claude model id. The provider is read from the
/// deliverable's own stamp, never re-derived from what is installed or granted now —
/// which would relabel old work every time the founder changes providers.
func testAProviderIsNeverInferredFromCurrentState() {
    let d = { () -> Deliverable in
        var d = Deliverable(kind: .doc, title: "T", body: "B")
        d.producedBy = .codex
        return d
    }()
    XCTAssertEqual(ProvenanceRow.text(for: d.producedBy!, lang: .en), "Ran on Codex")
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProvenanceRowTests 2>&1 | tail -30`
Expected: FAIL — no `ProvenanceRow`.

- [ ] **Step 3: Implement**

```swift
import SwiftUI

/// "Ran on Claude Code" plus, when it would change anything, "Re-run on Codex".
///
/// Modelled on `EngineeringResultBar`'s worked row — run metadata, grey and quiet, above
/// the rule, because it is not the answer — and on `CopilotChatView`'s `onRunLocally`,
/// which is offered only when `localBuildAvailable`. Same sentence, different noun.
enum ProvenanceRow {

    static func text(for provider: AIProvider, lang: AppLanguage) -> String {
        let name = provider.displayName
        return lang == .vi ? "Chạy trên \(name)" : "Ran on \(name)"
    }

    /// The provider to offer, or nil when there is nothing worth offering.
    static func offer(producedBy: AIProvider, otherInstalled: Bool) -> AIProvider? {
        guard otherInstalled else { return nil }
        return producedBy == .claudeCode ? .codex : .claudeCode
    }

    static func offerText(_ provider: AIProvider, lang: AppLanguage) -> String {
        lang == .vi ? "Chạy lại trên \(provider.displayName)"
                    : "Re-run on \(provider.displayName)"
    }
}
```

Add an optional slot to `DeliverableFrame` rather than widening `footer`, whose own comment
reserves it for a status line that has earned its rule:

```swift
    /// Which plan paid for this, and the offer to ask the other one. Absent — and drawn
    /// as nothing — for every deliverable made before provenance was recorded.
    var provenance: AIProvider? = nil
    var onReRun: ((AIProvider) -> Void)? = nil
```

Render it under the rule, in `CodepetTheme.mutedText` at `CodepetTheme.inter(12)`, matching the
engineering bar's metadata line. The offer is a `Button` on the same row, trailing.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProvenanceRowTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Library/ProvenanceRow.swift codepet/Views/Library/DeliverableStyle.swift codepetTests/ProvenanceRowTests.swift
git commit -m "feat: deliverable cards state their provider and offer the other"
```

---

### Task 6: Consent at the moment it is spent

Tapping "Re-run on Codex" while Codex is ungranted **is** the consent prompt.

**Files:**
- Create: `codepet/Views/Library/ProviderConsentPrompt.swift`
- Modify: the deliverable card's re-run handler (the `onReRun` added in Task 5)
- Modify: every `DeliverableFrame` call site that renders a run-produced deliverable
- Test: `codepetTests/ProviderConsentTests.swift` (create)

**This task also wires Task 5's slots, which are currently connected to nothing.**
Task 5 added `provenance` and `onReRun` to `DeliverableFrame` and left all 11 call sites
passing neither — so the line renders nowhere and the offer is unreachable. A slot no caller
fills is the same defect as a stamp no test observes, which Task 4's review caught; the plan
simply never scheduled the wiring, and this is where it belongs, because the consent flow and
the display attach at the same call sites.

At each call site that renders a `Deliverable`, pass `provenance: deliverable.producedBy`.
Passing it universally is safe: `producedBy` is `nil` for anything not produced by a run, and a
nil provenance renders nothing. Do NOT try to guess a provider for cards that have none.

Add a test that a call site given a deliverable with `producedBy == .codex` renders the Codex
line, and one given `nil` renders no provenance row at all.

**And the real "never inferred" guard lands here**, because this is the first place the two
facts coexist. Task 5's version of it was decorative — `ProvenanceRow` has nothing to infer
FROM — and a review caught it claiming a guard it did not provide. The genuine test: a card
whose deliverable is stamped `.codex`, rendered while `InstalledProviders` reports only
`.claudeCode` installed and the company's active provider is Claude, must STILL read "Ran on
Codex". That is the case where an implementation that re-derived from current state would
relabel old work, and it is the founder-facing half of the guard Task 4 built structurally.

- [ ] **Step 1: Write the failing tests**

Use a fake `ProviderAuthorisation` store — never real `UserDefaults`; four test files once wrote
mock flags into the founder's real prefs.

```swift
/// A consent prompt that runs anyway is worse than no prompt.
func testDecliningDoesNotRunAndDoesNotGrant() {
    let store = FakeAuthStore()
    var ran = false
    let flow = ProviderConsentFlow(authorisation: store.authorisation)
    flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
    XCTAssertTrue(flow.isAsking, "an ungranted provider must ask first")
    flow.decline()
    XCTAssertFalse(ran)
    XCTAssertFalse(store.isAuthorised(.codex, "c1"))
}

func testAllowingGrantsThenRuns() {
    let store = FakeAuthStore()
    var ran = false
    let flow = ProviderConsentFlow(authorisation: store.authorisation)
    flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
    flow.allow()
    XCTAssertTrue(store.isAuthorised(.codex, "c1"))
    XCTAssertTrue(ran)
}

/// Consent is not transitive. This is the boundary the whole phase rests on.
func testGrantingCodexDoesNotGrantClaude() {
    let store = FakeAuthStore()
    let flow = ProviderConsentFlow(authorisation: store.authorisation)
    flow.requestReRun(provider: .codex, companyId: "c1", run: {})
    flow.allow()
    XCTAssertFalse(store.isAuthorised(.claudeCode, "c1"))
}

/// An already-granted provider must not re-ask — being asked for permission you already
/// gave reads as the app having lost it.
func testAnAlreadyGrantedProviderRunsWithoutAsking() {
    let store = FakeAuthStore()
    store.grant(.codex, "c1")
    var ran = false
    let flow = ProviderConsentFlow(authorisation: store.authorisation)
    flow.requestReRun(provider: .codex, companyId: "c1", run: { ran = true })
    XCTAssertFalse(flow.isAsking)
    XCTAssertTrue(ran)
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProviderConsentTests 2>&1 | tail -30`
Expected: FAIL — no `ProviderConsentFlow`.

- [ ] **Step 3: Implement**

`ProviderConsentFlow` holds the pending run and the provider being asked about; `allow()` writes
the grant then invokes the stored closure; `decline()` drops it. Keep it a plain class with the
authorisation injected — not an `ObservableObject`, per landmine 3.

Prompt copy:

> **EN:** "Re-running here uses your ChatGPT plan. Allow Codepet to spend it?" / Allow · Not now
> **VI:** "Chạy lại ở đây sẽ dùng gói ChatGPT của bạn. Cho phép Codepet dùng gói này?" / Cho phép · Để sau

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProviderConsentTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Library/ProviderConsentPrompt.swift codepetTests/ProviderConsentTests.swift codepet/Views/Library/DeliverableStyle.swift
git commit -m "feat: ask for provider consent at the moment the plan is spent"
```

---

### Task 7: Settings reviews and revokes both grants

**Files:**
- Modify: `codepet/Views/Settings/ClaudeCodePanel.swift` (`grantGroup`, line 159; `refresh`, line 296)
- Test: `codepetTests/ProviderGrantPanelTests.swift` (create)

Consent needs a durable home even when it is given elsewhere — revocation especially: a founder
who wants Codepet to stop spending a plan must not have to find a run card to do it.

**There is no Settings picker.** The choice lives on the card.

- [ ] **Step 1: Write the failing tests**

```swift
/// Two independent switches, not one. Revoking Codex must leave Claude running.
func testRevokingOneGrantLeavesTheOther() {
    let store = FakeAuthStore()
    store.grant(.claudeCode, "c1")
    store.grant(.codex, "c1")
    store.authorisation.setAuthorised(.codex, "c1", false)
    XCTAssertFalse(store.isAuthorised(.codex, "c1"))
    XCTAssertTrue(store.isAuthorised(.claudeCode, "c1"))
}

/// The panel probes each provider separately, so an uninstalled Codex reports missing
/// while Claude reports present — the fact the grant rows render from.
func testThePanelHoldsAStatusPerProvider() async {
    let shell = FakeShell()
    shell.stub("claude --version", stdout: "2.1.241 (Claude Code)")
    let claude = await CLIEnvironment.probe(provider: .claudeCode, shell: shell, authorised: true)
    let codex  = await CLIEnvironment.probe(provider: .codex, shell: shell, authorised: false)
    XCTAssertEqual(claude.blocker, nil)
    XCTAssertEqual(codex.blocker, .notInstalled)
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProviderGrantPanelTests 2>&1 | tail -30`
Expected: FAIL to compile until Task 1's `probe(provider:…)` exists (it does — this task depends on it).

- [ ] **Step 3: Generalise the panel**

`grantGroup(companyId:)` takes a provider and renders one row per provider; `@State private var
status` becomes `[AIProvider: CLIStatus]`; `refresh()` probes each. The `granted` `@State` becomes
a set — keep it `@State`, for the reason the existing comment gives at line 28: reading storage
inside `Toggle`'s `get:` looks simpler and does not re-render.

The Toggle's write stays per-provider:

```swift
    authorisation.setAuthorised(provider, companyId, on)
```

Rename the file and type to `ProviderPanel` only if it is free: `grep -rn "ClaudeCodePanel"
codepet codepetTests`. The model-picker half stays Claude's — `ClaudeCodeModel` and
`ClaudeCodeModelPreference` are a hard-coded list of Claude model ids and were deliberately kept
that way in the Phase 2 spec.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/ProviderGrantPanelTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Settings/ codepetTests/ProviderGrantPanelTests.swift
git commit -m "feat: settings reviews and revokes each provider grant"
```

---

### Task 8: Onboarding checks installation, and nothing more

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingProviderStep.swift`
- Modify: `codepet/Views/Onboarding/OnboardingView.swift`
- Test: `codepetTests/OnboardingProviderStepTests.swift` (create)

**There is NO existing CLI step to modify — this creates one.** Phase 1 deferred its onboarding
gate pending this design, and nothing in `codepet/Views/Onboarding/` references `CLIStatus`,
`CLIEnvironment`, or `claude` today. An earlier draft of this plan said "modify the CLI step",
which was wrong.

**Mind the flow's shape.** `OnboardingView` drives the interview with a plain
`@State private var step = 0` and a `switch` over integer cases (1…6), with each button
advancing by literal assignment (`step = 2`, `step = 3`, …). Inserting a step in the middle
renumbers every case and every assignment after it — a large, error-prone diff for a gate that
does not care where it sits. **Append it instead**, so no existing case number changes. If a
mid-flow position is genuinely better, say so in the report and leave the renumbering to a
separate change.

Installation is a fact and can be detected; consent is a decision and needs a reason. Asking a
founder to let Codepet spend a plan before she has seen it do anything is a bad trade for both
sides — which is why the grant is asked for on the card, not here.

- [ ] **Step 1: Write the failing tests**

```swift
/// At least one, not both. A founder who pays OpenAI and not Anthropic is a complete
/// founder, and this step must not tell her otherwise.
func testTheStepPassesWithExactlyOneProviderInstalled() {
    XCTAssertTrue(OnboardingProviderStep.passes(installed: [.codex]))
    XCTAssertTrue(OnboardingProviderStep.passes(installed: [.claudeCode]))
    XCTAssertTrue(OnboardingProviderStep.passes(installed: [.claudeCode, .codex]))
}

func testTheStepBlocksWithNothingInstalled() {
    XCTAssertFalse(OnboardingProviderStep.passes(installed: []))
}

/// Onboarding must never write a grant. Consent belongs where the plan is spent.
func testOnboardingWritesNoGrant() {
    let store = FakeAuthStore()
    _ = OnboardingProviderStep.passes(installed: [.codex])
    XCTAssertFalse(store.isAuthorised(.codex, "c1"))
    XCTAssertFalse(store.isAuthorised(.claudeCode, "c1"))
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/OnboardingProviderStepTests 2>&1 | tail -30`
Expected: FAIL — no `OnboardingProviderStep`.

- [ ] **Step 3: Implement**

```swift
enum OnboardingProviderStep {
    /// Codepet needs ONE way to run a model, not a preferred one.
    static func passes(installed: Set<AIProvider>) -> Bool { !installed.isEmpty }
}
```

Show one row per provider in the states the panel already models: not installed (with its
copyable install command), installed but not signed in (with sign-in), signed in. Codex's install
command is `brew install codex` — a **cask**; the npm global route failed with EACCES on a real
machine, so do not present it as the primary instruction.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/OnboardingProviderStepTests 2>&1 | tail -30`
Then the full suite: `xcodebuild test -scheme codepet 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Onboarding/ codepetTests/OnboardingProviderStepTests.swift
git commit -m "feat: onboarding accepts either CLI and asks for no grant"
```

---

### Task 9: The blocked state offers the grant it is asking for

**This is the task that makes Task 3's `notGrantedProvider` reachable.** Without it that case is
dead code and spec test 5 has no implementation — the self-review of this plan caught exactly
that, so do not treat this task as optional polish.

The obstacle is real and deliberate: `transport()` must NOT probe for an installed binary. Its
own comment says why — "that costs a subprocess per call" — so the router cannot know which
provider is installed, and must keep returning the plain `.notGranted`. The **view** upgrades it,
from a status probed once rather than per call.

**Files:**
- Modify: the blocked-copy sites — `codepet/Managers/CompanyStore.swift:1094`, `:1920`; `codepet/Views/Reflection/SessionChatController.swift:102`
- Test: `codepetTests/BlockedStateOfferTests.swift` (create)

**Interfaces:**
- Consumes: `InstalledProviders` (Task 1), `BlockReason.notGrantedFor` (Task 3), `ProviderConsentFlow` (Task 6).
- Produces: `InstalledProviders.cached() -> Set<AIProvider>`, `BlockedOffer.resolve(reason:installed:) -> BlockedOffer`.

- [ ] **Step 1: Write the failing tests**

```swift
/// A Codex-only founder is asked for the grant she can actually give.
func testTheOfferNamesTheInstalledProvider() {
    let offer = BlockedOffer.resolve(reason: .notGranted, installed: [.codex])
    XCTAssertEqual(offer, .grant(.codex))
    XCTAssertTrue(offer.founderText(lang: .en).lowercased().contains("chatgpt"))
}

/// Claude wins the tie here for the same reason it wins in `chooseProvider` — one
/// precedence, not two that can disagree.
func testClaudeIsOfferedWhenBothAreInstalled() {
    XCTAssertEqual(BlockedOffer.resolve(reason: .notGranted, installed: [.claudeCode, .codex]),
                   .grant(.claudeCode))
}

/// Nothing installed means there is no grant to offer. Telling a founder to authorise
/// software she does not have is an instruction nobody can follow — the same reasoning
/// that puts `notAuthorised` last in `CLIStatus.Blocker`.
func testNothingInstalledOffersInstallNotAGrant() {
    XCTAssertEqual(BlockedOffer.resolve(reason: .notGranted, installed: []), .install)
}

/// Only the not-granted block becomes an offer. A missing sidecar is a build problem and
/// no grant fixes it — offering one there would be a button that cannot work.
func testOtherBlockReasonsAreLeftAlone() {
    XCTAssertEqual(BlockedOffer.resolve(reason: .sidecarMissing, installed: [.codex]),
                   .explain(.sidecarMissing))
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/BlockedStateOfferTests 2>&1 | tail -30`
Expected: FAIL — no `BlockedOffer`.

**Task 3's `needsClaudeCode` gets its producer here too.** The spec says chat and meetings
"stay Claude-only **and say so**" — and the review of Task 3 caught that no task in this plan
produced that case, which would have left it speculative vocabulary. A Codex-only founder who
opens chat today gets `.notGranted` ("grant your Claude plan"), which is not the most useful
thing to tell someone whose problem is that Claude Code is a different product she does not have.
When the blocked surface is chat or a meeting AND Claude is not installed, say `needsClaudeCode`
instead. Add this test:

```swift
/// Chat and meetings run on Claude and nothing else. A founder with only Codex installed
/// needs to be told THAT, not sent to grant a plan she does not have.
func testAClaudeOnlySurfaceTellsACodexFounderWhatItNeeds() {
    let offer = BlockedOffer.resolve(reason: .notGranted,
                                     installed: [.codex],
                                     surface: .claudeOnly)
    XCTAssertEqual(offer, .explain(.needsClaudeCode))
}

/// The same surface for a founder who HAS Claude installed but has not granted it is an
/// ordinary consent problem, not a missing-product problem.
func testAClaudeOnlySurfaceStillOffersTheGrantWhenClaudeIsInstalled() {
    let offer = BlockedOffer.resolve(reason: .notGranted,
                                     installed: [.claudeCode],
                                     surface: .claudeOnly)
    XCTAssertEqual(offer, .grant(.claudeCode))
}
```

`surface` is a two-case enum — `.anyProvider` (the one-shot ops) and `.claudeOnly` (chat and
meetings) — defaulting to `.anyProvider` so the existing call sites read unchanged.

- [ ] **Step 3: Implement**

```swift
/// What a blocked surface should actually show the founder.
///
/// `transport()` returns the plain `.notGranted` because it must not spend a subprocess
/// probing on every call. This turns that into something actionable, using an install
/// status probed once — the one place that knows both facts at the same time.
enum BlockedOffer: Equatable {
    /// Installed, ungranted: ask for this provider's grant, right here.
    case grant(AIProvider)
    /// Nothing installed: a grant would be an instruction nobody can follow.
    case install
    /// Not a consent problem. Say the reason and offer nothing.
    case explain(BlockReason)

    static func resolve(reason: BlockReason, installed: Set<AIProvider>) -> BlockedOffer {
        guard reason == .notGranted else { return .explain(reason) }
        // Same precedence as `LocalTransportRouter.chooseProvider`, deliberately: two
        // orders that can disagree would offer one provider and then run the other.
        for candidate in [AIProvider.claudeCode, .codex] where installed.contains(candidate) {
            return .grant(candidate)
        }
        return .install
    }

    func founderText(lang: AppLanguage) -> String {
        switch self {
        case .grant(let provider):
            let reason = BlockReason.notGrantedFor(provider)
            return lang == .vi ? reason.founderTextVi : reason.founderText
        case .install:
            return lang == .vi ? BlockReason.claudeCodeMissing.founderTextVi
                               : BlockReason.claudeCodeMissing.founderText
        case .explain(let reason):
            return lang == .vi ? reason.founderTextVi : reason.founderText
        }
    }
}
```

`InstalledProviders` already exists from Task 1. Refresh it when the app reaches a signed-in
company; do not add a second cache.

At the three blocked-copy sites, replace the direct `reason.founderText` read with
`BlockedOffer.resolve(reason:installed:).founderText(lang:)`, and render a grant button for the
`.grant` case that calls into Task 6's `ProviderConsentFlow`. `ChatTailAction.stop(reason:)` keeps
carrying a `BlockReason` — the offer is resolved where it is drawn, not where it is thrown.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/BlockedStateOfferTests 2>&1 | tail -30`
Then the full suite: `xcodebuild test -scheme codepet 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/BlockReason.swift codepet/Managers/CompanyStore.swift codepet/Views/Reflection/SessionChatController.swift codepetTests/BlockedStateOfferTests.swift
git commit -m "feat: the blocked state offers the grant for the installed CLI"
```


---

## Out of scope

- A per-company default provider. The spec ships the card's offer first, deliberately, to learn whether a stored default is wanted.
- Chat streaming and the virtual-company meeting on Codex.
- The first-run interactive `codex login` flow — unverified; no task depends on it.
- Any change to `functions/src/local/` — the adapter and ops are done.

## Verification before the branch is finished

- Full Swift suite green: `xcodebuild test -scheme codepet`. Count via `xcresulttool get test-results summary` — a running `codepet.app` or sibling build kills the test host, different victim each run.
- The three sidecar bundles still build: `scripts/build-sidecar.sh`. CI does this on every push, and Jest never would.
- **Open a PR, even a draft.** Pushing a branch runs nothing; a branch with no PR is an untested branch.
