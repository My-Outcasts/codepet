# Local Claude Code Execution — Design

**Date:** 2026-08-25
**Status:** Approved direction, phase 1 not yet built
**Feasibility report:** https://claude.ai/code/artifact/9cfcc1cb-1148-473f-bdb3-c7455b93e317

## Goal

Every Codepet feature that calls a model runs on the founder's own Claude Code
installation, on the Claude subscription they already pay for. `ANTHROPIC_API_KEY`
leaves the project entirely.

## The decision that shapes everything

**Codepet does not go to the Mac App Store.** It ships as a direct download,
Developer ID signed and notarized.

This is not a preference. Spawning the user's `claude` binary is blocked from a
Mac App Store build on two independent grounds, and patching either one still
leaves the other:

1. **Sandbox inheritance.** A child process created with `fork/exec`,
   `posix_spawn`, or `NSTask` always inherits its parent's sandbox. There is no
   way to give the child a different profile while keeping the parent-child
   relationship, and the child may carry exactly two entitlements —
   `com.apple.security.app-sandbox` and `com.apple.security.inherit`. Any other
   App Sandbox entitlement makes the system abort the child. A `claude` spawned
   from a sandboxed Codepet therefore cannot reach the keychain holding its
   OAuth credentials, cannot read `~/.claude/`, cannot write the founder's repo,
   and cannot spawn `bash` or `git`. Violations return `EPERM`, so it does not
   fail cleanly — it degrades confusingly.
2. **App Review guideline 2.5.2.** Apps must be self-contained in their bundle
   and "may not read or write data outside the designated container area, nor
   may they download, install, or execute code which introduces or changes
   features or functionality of the app."

Anysphere hit the same wall and documented it: they rejected App Sandbox because
it "is designed for the Mac App Store and would require Cursor to sign every
binary an agent might execute", and used Seatbelt via `sandbox-exec` instead —
which is only available to a process that is not itself in the App Sandbox. The
Cursor on the App Store is their iOS/iPadOS/visionOS companion, not the macOS
editor.

**Codepet already satisfies this.** `codepet/codepet.entitlements` sets
`com.apple.security.app-sandbox = false`. No entitlement changes are required.

### What we give up, recorded so nobody re-litigates it

- The Mac App Store channel, and the App Store workspace in `CLAUDE.md` with it.
- App Store discovery. Judged an acceptable loss: every Codepet user must hold a
  paid Anthropic plan anyway, so they do not arrive by browsing the store.
- We take on Developer ID signing, notarization, stapling, and a self-update
  mechanism.

## The rejected alternative

**Codepet as an MCP server**, with the founder's Claude Code as the client, would
have kept the App Store. It was rejected because the app could no longer run a
task on its own: pressing Run would queue work in Firestore and wait for the
founder to open a Claude Code session. Recorded here because it is the only
design that survives if the App Store requirement ever returns.

## Architecture

Every model-calling path on `CompanyStore` is **already an injected closure** on
`init`. Migration replaces default arguments; it is not a refactor.

| Seam on `CompanyStore.init` | Current default | Becomes |
|---|---|---|
| `taskRunner` | `RunTaskClient.run` | local runner |
| `chatSender` | `CompanyChatClient.send` | local runner |
| `chatStreamer` | `CompanyChatClient.sendStream` | local runner |
| `vcRunner` | `VirtualCompanyClient.run` | local runner |
| `roadmapFetcher` | `CompanyData.fetchRoadmap` | local runner |
| `enricher` | `ReflectionAPIClient().enrichBrief` | local runner |
| `decisionExtractor` | `DecisionsClient.extract` | local runner |

### Two execution shapes, not one

**Single-call features** (`runTask`, `generateRoadmap`, `enrichBrief`,
`extractDecisions`, `generatePlan`, `generateGuidance`, `generateDictionary`,
`distillReference`, `synthesizeBrief`) force one tool call and read structured
JSON out of it. These map onto `claude -p --json-schema <schema>` directly and
are driven from Swift, extending `ClaudeCodeRunner`.

**Virtual Company** runs six orchestrated phases with a nine-rule SSE contract.
Its orchestration is not reimplemented. `functions/src/company/` is packaged as a
local Node CLI, and only `defaultAgentCaller` (`company/virtualCompany.ts:74`,
~25 lines) is rewritten to shell out to `claude -p` instead of the Anthropic SDK.
Every field `AgentCaller` (`company/router.ts:182`) carries has a CLI flag:

| `AgentCaller` field | CLI flag |
|---|---|
| `model` | `--model` |
| `system` | `--append-system-prompt` |
| `userMessage` | stdin |
| `tool` + `toolName` | `--json-schema` |
| `effort` | `--effort` |
| `maxTokens` | no equivalent — see Known losses |

`docs/superpowers/specs/virtual-company-sse-contract.md` remains the authority
and is not modified. The local runner synthesises the same event stream in the
same order.

### Isolation of every spawned run

Every `claude` invocation Codepet makes passes `--safe-mode` and
`--strict-mcp-config`. Without them the founder's own `CLAUDE.md`, hooks,
plugins, skills, and MCP servers load into Codepet's run, and one of their hooks
can break the structured output Codepet is parsing. `--safe-mode` disables
customisation while leaving authentication intact.

**`--bare` must never be used.** It forces `ANTHROPIC_API_KEY` or `apiKeyHelper`
and never reads OAuth or the keychain — the exact opposite of what this design
needs.

### Credentials

Codepet never sees, stores, or transmits a token. Credentials live in the macOS
keychain under `Claude Safe Storage`; Claude Code owns and refreshes them.
Codepet spawns processes and reads `claude auth status --json`.

`claude auth status --json` returns `loggedIn`, `authMethod`, `apiProvider`,
`email`, `orgId`, `orgName`, `subscriptionType`. `subscriptionType` is how the
model picker knows which models the founder's plan can actually reach, so a
model they cannot use is never offered.

### Version pinning

Codepet pins a version range it has tested. The native installer accepts an
exact version (`curl -fsSL https://claude.ai/install.sh | bash -s 2.1.241`), and
`DISABLE_UPDATES` blocks every update path — the documentation names this exact
use case: "Use this when you distribute Claude Code through your own channels
and need users to stay on the version you provide." `minimumVersion`,
`requiredMinimumVersion`, and `requiredMaximumVersion` express the range.

### Installing Claude Code

Codepet **detects and guides**; it does not silently install. Missing binary →
show the official install command with a copy button, the pattern
`HookInstaller.swift` already uses. Chosen over having the app run the installer
because the founder should see what is being put on their machine.

**The binary is never bundled.** Anthropic publishes an installer, not a
redistribution licence. The macOS build is signed by "Anthropic PBC" and
notarized, and each release ships a GPG-signed `manifest.json` of SHA256
checksums (key fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`),
so Codepet can verify what it found before trusting it.

## Hard requirement on the founder

Claude Code requires a Pro, Max, Team, Enterprise, or Console account. The free
Claude.ai plan has no Claude Code access. **Every Codepet user must therefore
hold a paid Anthropic plan.** There is no fallback path — accepted deliberately,
because a cloud fallback would mean keeping `ANTHROPIC_API_KEY` and maintaining
two implementations of twelve features.

## Backend after the migration

Survives: Firestore (`companies/{uid}`, `users/{uid}`), Firebase Auth,
`githubOAuthStart` / `githubOAuthCallback` (needs the GitHub client secret
server-side).

Deleted: the twelve model-calling functions, and the `eng*` family (13 handlers,
~2,407 lines) whose entire purpose was remote execution — made redundant, not
migrated.

Loses its reason to exist: the credit model in `engBudget.ts` and
`entitlements.ts`. `PLAN_GATING_ENABLED` is already `false`, so nothing is being
sold yet; whether Codepet still needs a paid tier once it has no inference cost
is a business decision to take deliberately, not a side effect.

## Known losses

- **Prompt caching.** `AgentCaller.system` is a `SystemBlock[]` carrying
  `cache_control`, guarded by `companyCachePrefix.test.ts`. The CLI does not
  expose it. Costs latency and founder rate limit; unmeasured until phase 5.
- **`maxTokens` per call.** No CLI equivalent. Phases currently declare their own
  cap because a Vietnamese decision brief truncates under a shared one, and
  truncation silently drops trailing fields. Mitigation: `--effort`, plus
  detecting invalid JSON as truncation rather than as a schema violation.
- **Rate-limit visibility.** A convened decision is 8–10 model calls against the
  founder's 5-hour window, and nothing exposes how much of that window is left.
  Codepet can fail honestly but cannot warn in advance.

## Open questions

Neither blocks phase 1; both block shipping.

1. **Terms of service.** Whether a third-party app may drive a personal Claude
   subscription. Must be answered before any of this ships. This is the
   cheapest question here and the only one that can end the project.
2. **Cost baseline.** `CLAUDE.md` records ~$0.20 per convened decision against
   ~$0.005 otherwise. Re-measure with
   `docs/superpowers/virtual-company-test-runbook.md` before claiming a saving.

## Testing constraints

- `ClaudeCodeEnvironment` and every new service here is a **struct or enum, never
  a `@MainActor ObservableObject`.** Landmine 3: the XCTest host on Xcode 26.2
  crashes when a `@MainActor ObservableObject` deallocates.
- Subprocess spawning is injected behind a protocol so tests never touch a real
  `claude`.
- Run per-suite: `-only-testing:codepetTests/<Suite>`. A whole-target run exits
  65 on a clean checkout for reasons unrelated to this work.
