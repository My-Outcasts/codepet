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

**Corrected 2026-08-25 by measurement.** An earlier version of this section said
to pass `--safe-mode`. That is wrong for any run that needs tools:
**`--safe-mode` disables MCP servers**, along with every other customisation, so
a run isolated that way cannot reach the tools Codepet serves it. Measured — with
`--safe-mode` the init frame reports `mcp_servers: []`.

The recipe that actually isolates without disarming:

| Flag | Keeps out |
|---|---|
| `--mcp-config <absolute path>` | — declares Codepet's own tool server |
| `--strict-mcp-config` | the founder's MCP servers |
| `--setting-sources ""` | their settings, and therefore their **hooks** |
| a neutral working directory | `CLAUDE.md` discovery, which walks up from cwd |

Measured on 2.1.241: that combination yields exactly the tools Codepet declares
(the founder's `mcp-image` and `tripo` servers were excluded) and **zero hook
events**. Without `--setting-sources ""` their `SessionStart` hook fired and
injected its own content into Codepet's turn — the leak this section exists to
prevent, observed rather than theorised.

Two traps found the same way:

- **`--strict-mcp-config` alone excludes everything.** With no `--mcp-config`
  alongside it, the run gets no MCP servers at all, including Codepet's.
- **`--allowedTools` is variadic, so it swallows a positional prompt.** The
  prompt must arrive on stdin — which `ClaudeCodeRunner` already does, and is now
  a requirement rather than a preference.

**`--bare` must never be used.** It forces `ANTHROPIC_API_KEY` or `apiKeyHelper`
and never reads OAuth or the keychain — the exact opposite of what this design
needs.

### Tools: MCP, not `--json-schema`

`--json-schema` forces exactly one structured output, so it cannot express what
`companyChat` needs: eight optional tools, deliberately **not** forced —
`companyChat.ts:378` records that "byte stays free to reply in plain text, or ask
a clarifying question, instead of calling any of them."

Codepet therefore serves those tools over a **hand-rolled MCP stdio server**:
JSON-RPC over newline-delimited stdio answering `initialize`, `tools/list`, and
`tools/call`. Hand-rolled rather than `@modelcontextprotocol/sdk` because the
sidecar lives in `functions/`, which is the deploy source — a dependency added
there ships to Cloud Functions for no reason. The server is ~80 lines and the
tool definitions already exist as JSON in `companyChatCore.ts`.

These tools are not actions. They are signals back to the app (navigate here,
remember this, run that task), so the server records the call and returns an
acknowledgement; the app reads what was called out of the `stream-json`.

Measured end to end: the model called `mcp__codepet__navigate` with
`{"destination":"roadmap"}`, the server logged it, and the `tool_use` block
appeared in `stream-json` where the translator can read it.

One cost to expect: Claude Code defers tool loading, so a `ToolSearch` call fires
before the real one. That is an extra turn per tool-using reply.

`WEB_SEARCH_TOOL` does **not** port. It is an Anthropic server tool; Claude Code
has its own `WebSearch` with a different name and shape. It has to be remapped or
dropped on the local path, and that is an open question rather than a decision.

### Credentials

Codepet never sees, stores, or transmits a token. Credentials live in the macOS
keychain under `Claude Safe Storage`; Claude Code owns and refreshes them.
Codepet spawns processes and reads `claude auth status --json`.

`claude auth status --json` returns `loggedIn`, `authMethod`, `apiProvider`,
`email`, `orgId`, `orgName`, `subscriptionType`. `subscriptionType` is how the
model picker knows which models the founder's plan can actually reach, so a
model they cannot use is never offered.

### Signing in without a terminal

`claude auth login` opens the browser itself and runs a **local callback
server**; the browser redirects back to it and login completes. Codepet
therefore spawns `claude auth login` with pipes — no Terminal window, no
clipboard step — and polls `claude auth status --json` until `loggedIn` flips.
The process may print `Login successful` and wait for Enter; Codepet writes a
newline to stdin.

Two fallbacks the UI must carry, because the docs name both:

- **The browser shows a code instead of redirecting.** This happens when it
  cannot reach the local callback server — documented for WSL2, SSH, and
  containers, so rare on a Mac desktop but not impossible. Codepet needs a field
  to paste that code into, written through to the child's stdin.
- **The browser does not open.** Codepet shows the login URL with a copy button.

`claude setup-token` is **rejected**, despite looking like the tidier fit for a
GUI. It prints a one-year OAuth token to stdout and saves it nowhere, so Codepet
would become the holder of a long-lived credential — the thing this design
exists to avoid. It also enforces only `forceLoginMethod` and not
`forceLoginOrgUUID`, so it can mint a token in an organization an enterprise
admin meant to exclude.

### Landmine: an exported `ANTHROPIC_API_KEY` silently wins

Claude Code's credential precedence puts `ANTHROPIC_API_KEY` **above** the
subscription OAuth credential, and the documentation is explicit that in
non-interactive mode — which is every call Codepet makes, since they all pass
`-p` — "the key is always used when present."

Codepet spawns through a **login shell** so the founder's PATH resolves, which
means it also loads their profile. A founder who has `ANTHROPIC_API_KEY`
exported in `.zshrc` would have every Codepet run billed to their API account
instead of the subscription — the precise opposite of this project's purpose,
happening silently and with no error to notice.

Two defences, both required:

1. Every spawn removes `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` from the
   child's environment.
2. The probe reads `apiProvider` from `auth status --json` and surfaces it, so
   the founder can see which account their runs are actually charged to rather
   than having to trust that they know.

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

## Distribution: what a downloaded build needs before it works

Leaving the App Store does not mean leaving Apple's gates. Three of the five
below are **configuration gaps in the repo today**, and each one fails on a
stranger's Mac while working fine on ours.

### 1. Hardened Runtime is not enabled — notarization cannot pass without it

`ENABLE_HARDENED_RUNTIME` appears **zero times** in `codepet.xcodeproj`.
Notarization requires it, and an un-notarized download is effectively unopenable
on current macOS: the right-click → Open bypass is gone, so the founder must
find System Settings → Privacy & Security → Open Anyway. That is not an
onboarding step anyone survives.

Hardened Runtime does not obstruct this design. Library validation restricts
what gets loaded *into* Codepet's process; `claude` is `exec`d as a separate
signed process, which is exactly what terminal emulators do.

### 2. No TCC usage descriptions — the spawned `claude` is denied silently

`codepet/Info.plist` contains exactly one key, `CFBundleURLTypes`. There is no
`NSDocumentsFolderUsageDescription` or any other usage description.

This is the subtlest failure in the whole design. **A child process is attributed
to its parent for TCC purposes** — so when `claude` reads the founder's repo
under `~/Documents`, macOS asks whether *Codepet* may do that. Usage descriptions
do not grant access; they are what makes the dialog possible at all. Without
them there is no prompt and the access is refused — and the founder sees
`claude` reporting missing files, which reads as a Claude Code bug rather than a
Codepet permission gap.

Two ways to fix it, and the choice is real:

- **Usage descriptions** for Documents, Desktop, and Downloads. macOS then
  prompts in Codepet's name. Simple, and the prompt names the app the founder
  just launched.
- **`responsibility_spawnattrs_setdisclaim()`**, which makes the spawned `claude`
  its own responsible process (Qt Creator does this). Attribution becomes
  honest — Claude Code asks for what Claude Code reads — at the cost of a prompt
  naming software the founder may not realise Codepet drives.

Start with usage descriptions; they are required for the fallback path either
way. Revisit disclaiming once there is a real founder to watch hit the prompt.

### 3. Bundle identifier and keychain group disagree

`PRODUCT_BUNDLE_IDENTIFIER` is `app.murror.codepet`. `codepet.entitlements`
declares `keychain-access-groups` as `$(AppIdentifierPrefix)com.murror.codepet`
— `com.`, not `app.`. Whether this matters depends on what the provisioning
profile allows, and it cannot be settled from source: it needs a signed build
that actually reaches the keychain. It is called out here because Firebase auth
uses the keychain and landmine 4 already records that `Auth.auth()` traps rather
than throwing when things are wrong, which turns a signing mismatch into a crash
that mimics the Xcode 26.2 test bug.

### 4. `claude` may exist but be off PATH

Codepet resolves `claude` through a login shell, which loads the founder's
profile, and the native installer puts `~/.local/bin` on PATH there. But a
founder whose profile the installer never touched — an unusual Homebrew setup, a
custom shell, a machine where someone hand-moved the binary — has `claude`
installed and invisible.

The probe therefore falls back to the known install locations before concluding
`.missing`: `~/.local/bin/claude`, `/opt/homebrew/bin/claude`,
`/usr/local/bin/claude`. Telling a founder to install software they already have
is the specific wrong answer this avoids.

### 5. Updates

No self-update mechanism exists today. Not a first-run blocker, but shipping
without one means every fix requires the founder to notice and re-download.

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
