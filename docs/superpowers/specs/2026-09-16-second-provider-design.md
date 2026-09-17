# A second provider: the founder's ChatGPT plan runs the ops

**Phase 2 of the change begun in `2026-09-15-claude-code-only-design.md`.** Phase 1 removed the
hosted AI path and made the founder's own Claude Code the only way Codepet runs a model. This
adds a second one, and stops "the founder's own plan" meaning "Claude".

## The finding

Phase 1 answered "who pays for inference" — the founder does, through a plan she already has.
It did not answer "which plan". Every path assumes Claude Code: `claudeArgs` emits Claude CLI
flags, `spawn` invokes `claude`, the grant is stored at `cp_claude_authorised_<companyId>`, and
25 Swift files name `ClaudeCode` in a type or a view.

So a founder who pays OpenAI rather than Anthropic cannot use Codepet at all. Phase 1's
onboarding gate makes that explicit rather than silent, which is an improvement, but the answer
it gives her is still no.

## What was decided

| Question | Decision |
| --- | --- |
| Which mechanism? | **A second CLI with subscription auth** — OpenAI's Codex CLI, signed in with her ChatGPT account. No API key ever reaches Codepet, which is the property Phase 1 bought. |
| How much does it cover? | **The 12 one-shot ops only.** Chat streaming and the virtual-company meeting stay Claude-only for now. |
| What does a Codex-only founder get? | **In, with two named gaps.** Roadmap, tasks and deliverables run on her plan; chat and meetings show a `BlockReason` naming Claude Code. |
| Who picks, when both are present? | **She does**, per company, in Settings beside the existing grant. One provider active at a time. |

**BYOK stays rejected.** A pasted API key would reintroduce the key handling Phase 1 deleted and
make Codepet the biller again. Subscription auth is the whole point: her plan, her bill, her
consent, and nothing for Codepet to store.

## The part that makes this tractable

The op layer is **already provider-agnostic, by accident of an earlier constraint.** `claude -p`
cannot be forced into a tool call, so `schemaInstruction` asks for the shape in prose —

> Reply with ONLY that JSON object. No prose before or after it, no code fence, no explanation.
> It must satisfy this JSON Schema: …

— and `extractJson` parses whatever comes back, with every op validating or coercing the result
rather than trusting it. None of that is Claude-specific. A second CLI does not need a second
prompt, a second schema, or a second coercion path.

What IS Claude-specific is narrow and lives in one file, `functions/src/local/claudeCli.ts`:
the binary name, the flags, and the shape of the JSON envelope the CLI wraps its answer in.

## Architecture: one adapter, two implementations

```ts
interface CliAdapter {
  /** The binary invoked through the login shell. */
  binary: string;
  /** Flags for one non-streaming run. Prompt goes on stdin, never as an argument. */
  args(opts: { systemPrompt: string; model?: string; effort?: string }): string[];
  /** Pull the model's text out of whatever envelope this CLI emits. */
  resultFrom(stdout: string): string;
}
```

`claudeCli.ts` becomes the first implementation — its `claudeArgs` is already exactly `args`, and
the `envelope?.result` unwrap is already exactly `resultFrom`. `codexCli.ts` is the second.
`runClaudeJson` becomes `runCli(adapter, …)` and everything above it is untouched.

**The spawn stays as it is.** `spawn("/bin/zsh", ["-lc", …])` runs under a login shell so the
CLI resolves from the founder's own `PATH` — the same reason it was written that way for Claude,
and the same requirement for Codex.

**The transport seam records which runner.** `LocalTransportRouter.Transport` is currently
`{ .local, .blocked(BlockReason) }`, and `.local` cannot answer "which plan paid for this". It
becomes `.local(Provider)`. Phase 1 kept this seam deliberately for exactly this change; the
prediction was that a second provider would extend it rather than replace it, and that holds.

## Naming: rename what is neutral, keep what is Claude

25 Swift files name `ClaudeCode`. Renaming all of them would be a larger diff than the feature,
and renaming none of them leaves `ClaudeCodeAuthorisation` deciding whether to spend a ChatGPT
plan — a lie in a filename.

Ten Swift types carry the name. Sorting them by what they are actually about:

| Type | Verdict |
| --- | --- |
| `ClaudeCodeAuthorisation` | **Rename.** It answers "may Codepet spend this plan", which is now a per-provider question. |
| `ClaudeCodeStatus`, `ClaudeCodeLogin` | **Rename.** Installed / signed-in / reachable are questions any CLI answers. |
| `ClaudeCodeRunner`, `ClaudeCodeRunAdapter` | **Rename.** These run a CLI; which one is the adapter's business. |
| `ClaudeCodeEnvironment` | **Rename.** How a CLI is found and invoked. |
| `ClaudeCodeModel`, `ClaudeCodeModelPreference` | **Keep.** A hard-coded list of Claude model ids — `claude-opus-5` and friends. Codex gets its own type; a shared one would be a union of two vendors' catalogues pretending to be a concept. |
| `ClaudeCodeEffort` | **Keep for now.** `--effort` is a Claude flag. If Codex has an equivalent the two converge later; inventing the abstraction before seeing the second case is how it comes out wrong. |
| `ClaudeCodePanel` | **Split.** The grant and install-probe half is neutral; the model picker half is Claude's. |

`LocalTransportRouter`, `BlockReason` and `CloudAIBlock` already carry neutral names and need no
change — which is a small piece of evidence that the Phase 1 seam was drawn in the right place.

**Consent becomes per-provider, and that needs a stored-key migration.** Permission to spend a
Claude plan is not permission to spend a ChatGPT plan. `cp_claude_authorised_<companyId>` stays
as it is, and `cp_codex_authorised_<companyId>` joins it. A founder who granted Claude before
this change keeps that grant untouched and is asked separately about Codex — never migrated into
consent she did not give.

## What the founder sees

She grants either CLI, or both, and picks the active one in Settings beside the grant she already
knows. The picker defaults to whichever is installed and granted, and appears only when there is
a choice to make.

Roadmap, tasks and deliverables run on her choice. Chat and the virtual-company meeting on a
Codex-only setup show a `BlockReason` naming Claude Code as what those need — a working product
with two named gaps, not a locked door. `BlockReason` already exists to say exactly this kind of
thing, and gains cases rather than a mechanism.

**UI is not settled here.** The provider picker and the two new blocked states get proposed and
approved before they are built, per the project's working agreement.

## Codex CLI's flags are UNVERIFIED

**Codex CLI is not installed on the machine this spec was written on, and not one of its flags
was checked.** Nothing here should be read as a description of that binary.

Specifically unverified, and all of it required before `codexCli.ts` can be written:

- whether it has a non-interactive mode equivalent to `claude -p`;
- whether it accepts a prompt on **stdin** rather than as an argument;
- whether it can be given a system prompt separately from the user message;
- what its structured-output flag is, if any, and what envelope it emits — Claude's
  `--output-format json` wrapping the answer at `.result` is a Claude fact, not a convention;
- whether tools/MCP can be disabled for a one-shot run, as `--tools ""` and
  `--strict-mcp-config` do for Claude;
- how model selection is expressed, and whether an "inherit the founder's own default" option
  exists as it does for Claude.

**The first implementation task is to install the CLI and answer these against the real binary.**
If it turns out Codex has no equivalent of `-p` with clean stdout, this design does not survive
contact and should be reconsidered rather than worked around — the adapter is only cheap because
the contract above it is prose.

## Testing

`args` is a pure function from options to argv and `resultFrom` is a pure parser, so both
implementations are unit-testable with no CLI installed and no network. That matters: CI has
neither binary.

1. Each adapter's `args` produces the flags that provider needs, asserted as a literal list —
   not a count, and not a contains-check. This project has already shipped a floor
   (`toBeGreaterThanOrEqual(12)`) where a pinned list was meant, and a rename passed it.
2. Each adapter's `resultFrom` pulls the answer out of a real captured envelope, and fails
   loudly on a malformed one rather than returning empty.
3. The op layer is asserted **unchanged**: the same op, run through both adapters, produces the
   same prompt. That is the claim this whole design rests on — if it ever stops being true, a
   second prompt has been forked and the cost model changes.
4. `transport()` returns `.local(provider)` naming the granted, selected provider, and a founder
   with neither granted is `.blocked`.
5. A Claude grant does not authorise Codex, and the reverse. This is a consent boundary, so it
   gets a test that goes red if the two keys are ever collapsed into one.
6. The three sidecar bundles still build — CI does this now, on every push.

## Out of scope

- **Streaming chat and the virtual-company meeting.** Different protocol risk entirely: event
  framing, and an MCP tool story that Claude's CLI has and another may not. They stay Claude-only
  and say so.
- **BYOK.** Rejected above, and by Phase 1.
- **Per-department or per-task provider choice.** No evidence a founder wants it, and it
  multiplies the surfaces that must explain where work ran.
- **A fallback chain.** Trying a second provider on failure spends a second plan without asking
  and makes "which plan paid for this" unanswerable afterwards.

## This is now coupled to Phase 1's unfinished gate

Phase 1 deferred its onboarding gate (Task 7) pending a design, and it is the thing that closes
that phase's last route to the cloud — `startBuild` with a folder linked and no grant.

**That gate can no longer be designed as "Claude Code required."** It has to accept either CLI,
which means the two designs are one decision. Whichever is drawn first should be drawn knowing
the other exists.
