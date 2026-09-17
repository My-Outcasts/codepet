# Which plan paid for this: provider choice on the surface

**The UI half of `2026-09-16-second-provider-design.md`.** That spec built the adapter, the
per-provider consent store and the transport vocabulary, and deliberately deferred every screen.
This is those screens.

## The finding

Phase 2's TypeScript side runs the twelve one-shot ops on OpenAI's Codex CLI, verified against
the real binary. **The app cannot reach it.** Nothing in Swift sets `CODEPET_CLI_PROVIDER`, and
`transport()` still asks `isAuthorised(.claudeCode, …)`.

So there is a working second provider that no founder can select, and a consent key
(`cp_codex_authorised_<companyId>`) that nothing can write. This spec is what makes the work
reachable.

## What was decided

| Question | Decision |
| --- | --- |
| Where does the founder choose a provider? | **On the run card**, not in Settings. |
| When is consent asked for? | **At first use** — the moment she asks for the thing that spends the plan. |
| Which surface asks? | **The blocked state**, for a founder with nothing granted yet. |
| What does onboarding do? | **Detects installation only.** It never asks to spend anything. |

## The pattern this follows, rather than inventing one

`EngineeringResultBar.swift:62` already carries "run metadata: how long, and on which machine.
Grey and quiet." And `CopilotChatView.swift:1025` already offers `onRunLocally` — **only when
`localBuildAvailable`**.

That is the whole design: *state where the work ran, and offer the alternative only when it is
genuinely available.* The existing `startBuild` doc says it outright — "the run says where it is
running, and offers the other one when it is actually available". A provider picker is the same
sentence with a different noun.

## 1. The run card says where it ran, and offers the other

One grey line in the run metadata, and one offer:

```
Ran on Claude Code · 17s                    [Re-run on Codex]
```

**The provenance is already honest.** `OneShotMeta.model` was made truthful in the previous
phase: Claude reports what actually answered (`claude-opus-5[1m]`), and Codex — which reports no
model at all — reads `codex-local (requested …, not confirmed)`. Never a Claude id on a Codex
run. The card renders what the meta says; it does not re-derive it.

**The offer appears only when the other CLI is installed.** Same discipline as
`localBuildAvailable`: an offer that changes nothing is worse than no offer. Not installed, no
offer.

This makes "which plan paid for this" answerable **per deliverable** rather than per account,
which is the right granularity — it is the question a founder asks about a specific piece of
work, not about her configuration.

## 2. Consent is asked where it is spent

Tapping **Re-run on Codex** when Codex is not granted **is** the consent prompt. She is asked to
spend a plan at the moment she asks for the thing that spends it, with the work in front of her.

> Re-running here uses your ChatGPT plan. Allow Codepet to spend it?
> **[Allow]** [Not now]

Allow writes `cp_codex_authorised_<companyId>` and runs. "Not now" leaves the card as it was.

**This is why onboarding does not ask.** Installation is a fact and can be detected; consent is a
decision and needs a reason. Asking to spend a plan before the founder has seen the product do
anything is a bad trade for both sides.

## 3. The blocked state offers the grant

This closes the gap the run-card picker cannot: **a founder's FIRST task has no card to choose
from.**

Today a Codex-only founder hits `.blocked(.notGranted)`, whose copy reads "Codepet needs
permission to use your Claude plan. Turn it on in Settings." That is wrong for her twice over —
she has a plan, just not that one, and there is no Settings control for it.

The blocked state therefore does double duty: it explains, and it offers the grant for **whichever
CLI is actually installed**. Not a generic "go to Settings", but the specific permission that
would unblock this founder on this Mac.

### This needs a probe that does not exist yet

That requires the blocked state to know **which** CLI is installed, and today nothing can answer
that. `CLIStatus` was renamed in Phase 2 but not generalised: it is still one struct describing
one CLI, and `CLIEnvironment` probes three hard-coded paths — `~/.local/bin/claude`,
`/opt/homebrew/bin/claude`, `/usr/local/bin/claude`.

So "is Codex installed" is **unanswerable in Swift right now.** Every screen in this spec depends
on it: the run card's offer, the blocked state's grant, and the onboarding step all branch on
per-provider installation.

The probe therefore becomes part of this work, not an assumption of it: `CLIStatus` gains the
provider it describes, and the path list becomes per-provider rather than a constant. The
existing comment on that list states the reason it must be a list at all — a founder with "the
binary installed and invisible" must not be told to install software she already has — and that
reasoning applies unchanged to a second binary with its own install locations.

**Codex's install paths are unverified.** The Phase 2 findings recorded the CLI's flags against
the real binary; they did not record where npm, Homebrew and the native installer each put it.
That gets answered against the real machine before the list is written — the same
verify-then-write discipline Phase 2 used for the flags, and for the same reason: a guessed path
fails silently as "not installed".

## 4. Onboarding checks installation, nothing more

The step passes when **at least one** provider is installed. It shows both rows — Claude Code and
Codex — each in the states `ClaudeCodePanel` already models: not installed (with its copyable
install command), installed but not signed in (with sign-in), signed in.

It does not ask for a grant, and it does not require both.

## 5. Settings keeps the grants, and loses nothing else

`ClaudeCodePanel` grows a second grant row so Codex can be **reviewed and revoked** — consent
needs a durable home even when it is given somewhere else. Revocation especially: a founder who
wants to stop Codepet spending a plan must not have to find a run card to do it.

**There is no Settings picker.** The choice lives on the card.

## What this does NOT solve

**Re-running spends a second plan to answer the same question.** That is the honest cost of
putting choice on the card, and it is the right trade for comparison — "what would Codex have
said?" — but it is the wrong ergonomics for a founder who simply wants Codex as her default.
Every task would be run twice.

No per-company default is specified here, deliberately: there is no evidence yet that a founder
wants one, and the cheapest way to find out is to ship the card and see whether anyone re-runs
the same ask repeatedly. If they do, the default belongs beside the grant in Settings, and the
card's offer becomes the way to deviate from it.

**Chat and meetings stay Claude-only** and say so, via `BlockReason.needsClaudeCode`. The copy
names two exits — install Claude Code, or switch this company to it — because the other four
`BlockReason` cases all name an action the founder can take, and one that only states a fact
would be the odd one out.

## Testing

1. The run card shows the provider the meta reports, and **never re-derives it** — a Codex run
   must not render a Claude model id. This is the founder-facing half of a guard the previous
   phase built structurally.
2. The offer is absent when the other CLI is not installed, present when it is. Both directions.
3. Tapping the offer on an ungranted provider asks before running, and **does not run** if she
   declines. A consent prompt that runs anyway is worse than none.
4. Allowing writes only that provider's key. A Codex grant must not touch
   `cp_claude_authorised_<companyId>`, and the reverse — consent is not transitive, and the
   previous phase's tests prove that at the store; this proves it at the surface.
5. The blocked state offers the grant for the installed CLI, and offers nothing when neither is
   installed.
6. Onboarding passes with exactly one provider installed, and never writes a grant key.
7. The probe reports each provider independently: Claude present and Codex absent must not read
   as both present, and the reverse. This is the fact every screen above branches on, so it gets
   a test that does not go through a view.

## Out of scope

- A per-company default provider (see above — ship the card first).
- Chat and meetings on Codex.
- Any change to the adapter, the consent store, or the transport seam. They are done, and this
  spec adds no requirement to them. **`CLIStatus` and `CLIEnvironment` are the exception** — they
  are in scope, per "This needs a probe that does not exist yet" above.
