# Second Provider (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a founder run Codepet's twelve one-shot ops on her own ChatGPT plan via OpenAI's Codex CLI, alongside Claude Code.

**Architecture:** One `CliAdapter` interface with two implementations. Everything above it — the prose schema instruction, `extractJson`, every op's coercion — is already provider-agnostic and must not change. The transport seam gains the provider it selected so a run can say which plan paid for it.

**Tech Stack:** TypeScript Cloud Functions bundled by esbuild into the app (Node 22, jest); Swift 5 / SwiftUI (macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, XCTest).

**Spec:** `docs/superpowers/specs/2026-09-16-second-provider-design.md` — read it first. It outranks this plan.

## Global Constraints

- **Never commit to `main`.** Branch, PR, and state what was verified.
- **Run `./scripts/build-sidecar.sh` after ANY change under `functions/src/`.** The bundles are gitignored; CI now builds all three, but a local run catches it sooner.
- **Never delete a `*Core.ts` builder, and never delete from `company/` without checking the bundle closure.** `local/vcSidecar.ts` inlines `../company/orchestrate` and `../company/router`, whose files carry ordinary names.
- **Swift tests run with `-only-testing:`.** The XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates; a whole-suite run exiting 65 is NOT a regression.
- **No `codepet.app` may be running** during `xcodebuild test` — it kills the test host. Quit with `osascript`, never `pkill`.
- Build signed: `DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates`.
- **A guard needs a test that goes red when the guard is deleted — prove it by deleting the guard and showing red, then restoring.** Every task below that adds a guard owes this evidence.
- **Assert pinned lists, never floors.** `toBeGreaterThanOrEqual(n)` passes a rename. This project shipped exactly that bug.
- **Before removing or re-homing a test, read its replacement and confirm it asserts the same BEHAVIOUR.** On the previous phase a deleted test's replacement covered only half of what it asserted, and the other half silently lost its only assertion.
- **`Firestore.firestore()` traps rather than throwing** under an unconfigured `FirebaseApp`, killing the test host with a message that looks like an assertion failure. Injected closures only.
- **Do not deploy.** Nothing in this phase touches production.

## The dependency that governs everything

**Task 1 is a verification spike with a go/no-go gate, and Tasks 3-9 are blocked on it.** Codex CLI was not installed on the machine this plan was written on, and none of its flags were checked. This plan deliberately contains **no invented Codex flags** — Task 3 consumes Task 1's recorded findings.

If Task 1 finds Codex has no non-interactive mode with clean stdout, **stop and re-open the design**. The adapter is only cheap because the contract above it is prose; working around a missing `-p` equivalent would mean a second prompt path, which is the cost model this design exists to avoid.

## File Structure

| File | Responsibility |
| --- | --- |
| `functions/src/local/cliAdapter.ts` | **New.** The `CliAdapter` interface and `runCli(adapter, opts)`. |
| `functions/src/local/claudeCli.ts` | Becomes the Claude `CliAdapter`. Keeps `ClaudeCliError`, `usageFrom`, `quote`. |
| `functions/src/local/codexCli.ts` | **New.** The Codex `CliAdapter`, written from Task 1's findings. |
| `functions/src/local/oneShotSidecar.ts` | Selects an adapter from its request; otherwise unchanged. |
| `functions/src/local/vcSidecar.ts` | **Claude only.** Passes the Claude adapter explicitly. Behaviour must not change. |
| `functions/src/local/chatSidecar.ts` | **Untouched.** It has its own separate `claudeArgs` for streaming; unifying them is out of scope. |
| `codepet/Models/AIProvider.swift` | **New.** `enum AIProvider { case claudeCode, codex }` plus its display names. |
| `codepet/Managers/ProviderAuthorisation.swift` | Renamed from `ClaudeCodeAuthorisation`; keyed per provider. |
| `codepet/Services/LocalTransportRouter.swift` | `.local` becomes `.local(AIProvider)`. |

---

### Task 1: Verify Codex CLI against the real binary — GO/NO-GO

**No code. The deliverable is recorded findings and a verdict.** Everything after this depends on it, and guessing here poisons every later task.

**Files:**
- Create: `.superpowers/sdd/codex-cli-findings.md`

**Interfaces:**
- Produces: a findings document Task 3 reads as its source of truth for every Codex flag.

- [ ] **Step 1: Install it**

```bash
npm install -g @openai/codex || brew install codex
which codex && codex --version
```

If neither works, record what failed and STOP — report to the human rather than substituting a different tool.

- [ ] **Step 2: Answer each question below against the binary, recording the exact command and its output**

For each, paste what you ran and what came back. "Appears to" is not an answer; show the output.

1. **Is there a non-interactive mode?** The Claude equivalent is `claude -p`. Check `codex --help` and any `exec`/`run` subcommand.
2. **Does it take the prompt on stdin?** Codepet never passes prompts as arguments — a flag could swallow one, and prompts contain arbitrary founder text.
3. **Can a system prompt be supplied separately** from the user message?
4. **What does clean stdout look like?** Is there a structured-output flag? What is the envelope, and where does the model's text sit? Claude's `--output-format json` puts it at `.result`; that is a Claude fact, not a convention. **Capture one real envelope verbatim** — Task 3's parser test needs it.
5. **Can tools/MCP be disabled** for a one-shot run, as `--tools ""` and `--strict-mcp-config` do for Claude? If not, does the run still answer with JSON only?
6. **How is the model selected**, and is there an "inherit the founder's own default" option (Claude's is to pass no `--model` at all)?
7. **What does it do on failure** — exit code, and is the error on stderr or in the envelope?

- [ ] **Step 3: Run the actual contract end to end**

Take a real prompt from the repo and confirm Codex can satisfy it:

```bash
cd ~/Developer/codepet-dept-outputs/functions
node -e '
const { ONE_SHOT_OPS, schemaInstruction } = require("./lib/local/oneShotOps");
const p = ONE_SHOT_OPS.runTask.plan({ task_title: "Cost of a month of inference", dept_key: "fin" });
process.stdout.write(p.prompt + "\n\n" + schemaInstruction(p.schema));
' > /tmp/codex-probe.txt 2>/dev/null || echo "build lib/ first with npx tsc, or render the prompt another way"
```

Feed that to Codex non-interactively and record whether the reply is a single JSON object that `extractJson` can parse. **This is the real test of the design.**

- [ ] **Step 4: Write the verdict**

End the findings file with one of:
- **GO** — the six answers are known and the contract holds; Task 3 can be written.
- **NO-GO** — say precisely which requirement fails. Do not propose a workaround; the design is re-opened by a human.

- [ ] **Step 5: Commit the findings**

```bash
git add .superpowers/sdd/codex-cli-findings.md 2>/dev/null || true
git commit -m "Findings: what Codex CLI actually does"
```

(`.superpowers/` is gitignored; if the add fails, say so and leave the file on disk.)

---

### Task 2: Extract `CliAdapter` — a pure refactor, no behaviour change

Do this WHILE Task 1 runs; it depends only on the Claude side.

**Files:**
- Create: `functions/src/local/cliAdapter.ts`
- Modify: `functions/src/local/claudeCli.ts`
- Modify: `functions/src/local/oneShotSidecar.ts:22,97`, `functions/src/local/vcSidecar.ts:35,69`
- Test: `functions/src/__tests__/cliAdapter.test.ts` (new)

**Interfaces:**
- Produces:
  ```ts
  export interface CliAdapter {
    binary: string;
    args(opts: { systemPrompt: string; model?: string; effort?: string }): string[];
    /** The model's text, plus whatever token counts this CLI reports (zeros if none). */
    resultFrom(stdout: string): { text: string; usage: { input: number; output: number; cache_read: number } };
  }
  export const claudeAdapter: CliAdapter;
  export async function runCli(adapter: CliAdapter, opts: {
    systemPrompt: string; prompt: string; model?: string; effort?: string;
  }): Promise<any>;
  ```
- `ClaudeCliError`, `usageFrom` and `quote` keep their names and exports — callers import them today.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/cliAdapter.test.ts`:

```typescript
import { claudeAdapter } from "../local/cliAdapter";

/**
 * The adapter is the ONLY provider-specific thing in the one-shot path. Everything above it —
 * the prose schema instruction, `extractJson`, each op's coercion — is shared, and this test
 * exists to keep the boundary where it is.
 */
describe("the Claude adapter", () => {
  test("emits exactly the flags the CLI is run under", () => {
    expect(claudeAdapter.args({ systemPrompt: "SYS" })).toEqual([
      "-p",
      "--system-prompt", "SYS",
      "--strict-mcp-config",
      "--setting-sources", "",
      "--output-format", "json",
      "--tools", "",
    ]);
  });

  /** Passing no `--model` is the default on purpose: a founder who chose one in her own CLI
   *  already answered this, and overriding it would be Codepet deciding something she decided. */
  test("omits --model and --effort unless asked", () => {
    const a = claudeAdapter.args({ systemPrompt: "S" });
    expect(a).not.toContain("--model");
    expect(a).not.toContain("--effort");
    expect(claudeAdapter.args({ systemPrompt: "S", model: "claude-opus-5" }))
      .toEqual(expect.arrayContaining(["--model", "claude-opus-5"]));
  });

  test("pulls the answer out of the envelope", () => {
    expect(claudeAdapter.resultFrom('{"result":"hello"}').text).toBe("hello");
  });

  /** **Usage rides with the text, and this is why.** `usageFrom` is consumed by `vcSidecar`
   *  alone — the meeting's run ceiling, the only guard against a runaway loop on the founder's
   *  own plan. Returning bare text would strand it. Cache WRITES count as input: a real meeting
   *  reported `input_tokens: 2` for a prompt of thousands, because the prefix was cached and
   *  billed as `cache_creation_input_tokens`. */
  test("carries the token counts the meeting's ceiling depends on", () => {
    const r = claudeAdapter.resultFrom(
      '{"result":"hi","usage":{"input_tokens":2,"cache_creation_input_tokens":3000,"output_tokens":7}}');
    expect(r.usage).toEqual({ input: 3002, output: 7, cache_read: 0 });
  });

  test("is the claude binary", () => {
    expect(claudeAdapter.binary).toBe("claude");
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ~/Developer/codepet-dept-outputs/functions && npx jest src/__tests__/cliAdapter.test.ts
```

Expected: FAIL — `Cannot find module '../local/cliAdapter'`.

**The constraint that shapes `resultFrom`.** `usageFrom` has exactly one consumer: `vcSidecar`,
which is Claude-only and stays that way — but the refactor still touches it and it must keep
working identically. A `resultFrom` returning bare text would silently drop the meeting's token
accounting, and that ceiling is the only guard against a runaway loop on the founder's own plan.
So the adapter returns text AND usage; Codex reports none on its default path and returns zeros,
which is honest rather than invented.

`oneShotSidecar` uses only the text. `vcSidecar` uses both.

- [ ] **Step 3: Create the interface and move the Claude implementation behind it**

`cliAdapter.ts` holds the interface and `runCli`. `claudeCli.ts` exports `claudeAdapter` built from its existing `claudeArgs` and envelope unwrap. **`runCli` is `runClaudeJson`'s body with `claudeArgs(opts)` replaced by `adapter.args(opts)` and `claude` replaced by `adapter.binary`** — no other change. Keep `runClaudeJson` as a thin wrapper calling `runCli(claudeAdapter, opts)` so no caller has to move in this task.

- [ ] **Step 4: Run it green, then prove nothing moved**

```bash
npx jest && npx tsc --noEmit
cd ~/Developer/codepet-dept-outputs && ./scripts/build-sidecar.sh
for f in chatSidecar oneShotSidecar vcSidecar; do echo "$f $(stat -f%z codepet/Resources/$f.js)"; done
```

This is a pure refactor, so **the bundles should be near-identical in size**. A large change means behaviour moved — investigate before committing. Record the sizes either way.

- [ ] **Step 5: Commit**

```bash
git add functions/src/local/cliAdapter.ts functions/src/local/claudeCli.ts \
        functions/src/__tests__/cliAdapter.test.ts
git commit -m "One adapter interface, with Claude as its first implementation"
```

---

### Task 3 precondition, found while reviewing Task 2

Two things Task 2 surfaced that Task 3 must handle rather than discover.

**1. `runCli` is currently dead, and Task 3 is what makes the seam load-bearing.**
Task 2 kept `runClaudeJson` over an internal envelope-returning helper, because both callers read
fields `resultFrom` does not carry. `runCli` compiles and is tree-shaken out. **Task 3 must route
`oneShotSidecar` through the adapter for real** — otherwise this phase ships an interface nothing
uses, and the second provider is wired to nothing.

**2. `OneShotMeta.model` means different things on the two providers, and that must be visible.**
`oneShotSidecar.ts:116` sets `model: pickModel(envelope)`, whose doc says "what actually answered,
as Claude Code reported it" — read off `modelUsage` in Claude's envelope. **Codex's default stdout
has no envelope**, so nothing reports what answered.

Do NOT paper over this by reporting the requested model as though it were the answering one. The
field is consumed by ops that put it in front of the founder. Options, in order of preference:

- report what Codex *does* tell us, if `--json` (JSONL, text at `.item.text`) carries a model id
  cheaply enough — verify against the binary, do not assume;
- otherwise report the model Codepet asked for, **clearly marked as requested rather than
  answering**, and say so in the field's doc comment;
- never report a Claude model id for a Codex run.

So the adapter contract gains a third value:

```ts
resultFrom(stdout: string): {
  text: string;
  usage: { input: number; output: number; cache_read: number };
  /** What answered, when the CLI says. `undefined` when it does not — never a guess. */
  model?: string;
};
```

Claude fills it from `modelUsage` via the existing `pickModel`. Codex fills it only if verified.

---

### Task 3: `codexCli.ts` — BLOCKED on Task 1

**Do not start this until `.superpowers/sdd/codex-cli-findings.md` exists and says GO.**

**This task's flags come from that file, not from this plan.** Any Codex flag written here would be invention; the plan's author never ran the binary.

**Files:**
- Create: `functions/src/local/codexCli.ts`
- Test: `functions/src/__tests__/codexCli.test.ts`

**Interfaces:**
- Consumes: `CliAdapter` from Task 2; the findings from Task 1.
- Produces: `export const codexAdapter: CliAdapter`.

- [ ] **Step 1: Read the findings file.** If it says NO-GO, stop and report.
- [ ] **Step 2: Write the failing test** — `args` asserted as a literal list (pinned, never a count or a contains-check), and `resultFrom` against **the real envelope captured in Task 1 Step 2.4**, not an invented one.
- [ ] **Step 3: Run it, watch it fail.**
- [ ] **Step 4: Implement `codexAdapter`** from the findings.
- [ ] **Step 5: Run green**, then add the cross-provider test that is the point of the whole design:

```typescript
/** The claim this design rests on: one op, two adapters, ONE prompt. If this ever fails, a
 *  second prompt path has been forked and the cost model changed. */
test("the same op produces the same prompt whichever adapter runs it", () => {
  const plan = ONE_SHOT_OPS.runTask.plan({ task_title: "X", dept_key: "fin" });
  expect(plan.prompt).toContain("This function produces sheet, doc.");
  // the adapters differ in argv and envelope ONLY
  expect(claudeAdapter.args({ systemPrompt: "S" }))
    .not.toEqual(codexAdapter.args({ systemPrompt: "S" }));
});
```

- [ ] **Step 6: Rebuild the sidecars, commit.**

---

### Task 4: `AIProvider`, and the seam records which one ran

**Files:**
- Create: `codepet/Models/AIProvider.swift`
- Modify: `codepet/Services/LocalTransportRouter.swift:30-36` and every `case .local` site
- Test: `codepetTests/AIProviderTests.swift`, `codepetTests/LocalTransportRouterTests.swift`

**Interfaces:**
- Produces: `enum AIProvider: String, CaseIterable { case claudeCode, codex }` with `displayName`; `LocalTransportRouter.Transport` becomes `{ case local(AIProvider); case blocked(BlockReason) }`.

- [ ] **Step 1: Write the failing tests** — `transport()` returns `.local(.claudeCode)` for a Claude-granted company and `.local(.codex)` for a Codex-granted one; a company with neither is `.blocked(.notGranted)`. Include the totality check that no third case can be added silently:

```swift
func testTransportIsOnlyEverLocalOrBlocked() {
    let cases: [LocalTransportRouter.Transport] = [.local(.claudeCode), .blocked(.notGranted)]
    for c in cases { switch c { case .local, .blocked: continue } }
}
```

- [ ] **Step 2: Run, watch fail** (`.local` takes no argument yet).
- [ ] **Step 3: Add `AIProvider` and thread it through `transport()`.**
- [ ] **Step 4: Update every `case .local` site.** Find them: `grep -rn "case .local" codepet | grep -v Tests`. Each becomes `case .local(let provider)`; a site that ignores the provider uses `.local`. **Do not change what any of them DO** — this task records the provider, it does not act on it.
- [ ] **Step 5: Run the affected suites green; commit.**

---

### Task 5: Consent is per provider, and is never inherited

**Files:**
- Modify: `codepet/Managers/ClaudeCodeAuthorisation.swift`
- Test: `codepetTests/ProviderAuthorisationTests.swift`

**Interfaces:**
- Produces: `key(_ provider: AIProvider, _ companyId: String) -> String`, yielding `cp_claude_authorised_<id>` for `.claudeCode` (**unchanged — founders have this stored today**) and `cp_codex_authorised_<id>` for `.codex`.

- [ ] **Step 1: Write the failing tests.** The load-bearing one:

```swift
/// **Consent is not transitive.** Permission to spend a Claude plan is not permission to spend
/// a ChatGPT plan. A founder who granted Claude before this change must be ASKED about Codex,
/// never migrated into consent she did not give.
func testAClaudeGrantDoesNotAuthoriseCodex() {
    var auth = ProviderAuthorisation()
    auth.setAuthorised(.claudeCode, "c1", true)
    XCTAssertTrue(auth.isAuthorised(.claudeCode, "c1"))
    XCTAssertFalse(auth.isAuthorised(.codex, "c1"), "a Claude grant leaked into Codex")
}

/// The existing key must not move, or every founder silently loses the grant she gave.
func testTheClaudeKeyIsUnchanged() {
    XCTAssertEqual(ProviderAuthorisation.key(.claudeCode, "c1"), "cp_claude_authorised_c1")
}
```

- [ ] **Step 2: Run, watch fail.**
- [ ] **Step 3: Implement**, keying by provider.
- [ ] **Step 4: Prove the consent boundary can fail** — make both providers share one key, confirm `testAClaudeGrantDoesNotAuthoriseCodex` goes red, restore. Record both runs.
- [ ] **Step 5: Commit.**

---

### Task 6: Rename the six neutral types

Mechanical, and worth its own task so a rename never hides a behaviour change.

**Files:** `ClaudeCodeAuthorisation` → `ProviderAuthorisation`; `ClaudeCodeStatus` → `CLIStatus`; `ClaudeCodeLogin` → `CLILogin`; `ClaudeCodeRunner` → `CLIRunner`; `ClaudeCodeRunAdapter` → `CLIRunAdapter`; `ClaudeCodeEnvironment` → `CLIEnvironment`.

**KEEP unchanged:** `ClaudeCodeModel`, `ClaudeCodeModelPreference`, `ClaudeCodeEffort` — those are Claude facts, and the spec explains why.

- [ ] **Step 1:** Rename one type at a time, building between each. New `.swift` files need no project-file edit (`PBXFileSystemSynchronizedRootGroup`).
- [ ] **Step 2:** After each, run the affected suites.
- [ ] **Step 3:** Confirm no stored-defaults key changed — `grep -rn "cp_claude" codepet | grep -v Tests`. A renamed type must not rename a key a founder has on disk.
- [ ] **Step 4: Commit** as one rename commit, with the kept types and the reason in the message.

---

### Task 7: The two gaps say what they need

**Files:**
- Modify: `codepet/Services/BlockReason.swift`
- Test: `codepetTests/BlockReasonTests.swift`

**Interfaces:**
- Produces: `BlockReason.needsClaudeCode`, with `founderText` and `founderTextVi`.

- [ ] **Step 1: Write the failing test.** Extend the existing uniqueness test — every reason has its own words, in both languages, and the Vietnamese differs from the English. That last assertion exists because this codebase has a recorded `lang == .vi ? why : why` defect where a language ternary returns the same string both ways.
- [ ] **Step 2: Run, watch fail.**
- [ ] **Step 3: Add the case.** The copy names what the founder can do — this is Codex-only chat and meetings, so the fix is installing Claude Code, not a setting.
- [ ] **Step 4: Route chat and the meeting to it** when the selected provider is `.codex`. Do NOT change what they do on Claude.
- [ ] **Step 5: Run green; commit.**

---

### Task 8: The provider picker — DEFERRED, needs its own plan

**Not implementable from this document, and deliberately not written as steps.** UI gets proposed and approved before it is built; writing view code here would be guessing at a screen nobody has agreed. Steps without code are how a plan lies about being ready.

What it will need when planned: a per-company picker beside the existing grant in `ClaudeCodePanel`'s neutral half, defaulting to whichever provider is installed and granted, appearing only when there is a choice. The decision belongs in a testable static beside a thin view, as `PrototypeMode.isLocked` and `DraftCardCopy.shouldShowNotFiledNote` already are.

**It is also entangled with Phase 1's deferred onboarding gate**, which can no longer be designed as "Claude Code required". Draw them together.

---

### Task 9: Verification and PR

- [ ] **Step 1:** `cd functions && npx tsc --noEmit && npx jest` — clean and green.
- [ ] **Step 2:** Quit the app, then run the affected Swift suites with `-only-testing:`.
- [ ] **Step 3:** `./scripts/build-sidecar.sh`; confirm all three build and record sizes.
- [ ] **Step 4:** Build the app signed.
- [ ] **Step 5:** Push and open a PR so CI runs the whole Swift suite — the only place it runs. CI also builds all three bundles now.
- [ ] **Step 6:** Wait for both jobs green before requesting review.

## Not in this plan

- Streaming chat and the virtual-company meeting on Codex. `chatSidecar.ts` has its own separate `claudeArgs`; unifying it is a later decision.
- BYOK, per-department provider choice, and any fallback chain — all rejected in the spec.
- Phase 1's onboarding gate, which remains open and is now entangled with Task 8.
