# Engineering Mode — Design

**Date:** 2026-08-11
**Status:** Approved design → ready for implementation plan
**Target:** `main`
**Supersedes:** the execution half of `2026-07-31-coding-agent-in-copilot-design.md` (that design shipped; its local `claude`-CLI runner becomes the fallback path, not the primary one)

---

## 1. Goal

Give the founder a coding agent that behaves like ChatGPT Codex or Claude Code, inside the chat dock they already use: describe an engineering change in plain language, watch it run in a cloud sandbox against their own repo, iterate on it with follow-up turns, review the real diff, and end at **a preview they can click** — not an artifact they can't evaluate.

## 2. What exists today, and why it isn't enough

`2026-07-31-coding-agent-in-copilot-design.md` shipped. Selecting **Build** calls `CompanyStore.startCodeRun(ask:)`, which spawns the founder's own `claude` CLI headless against a linked folder and renders `CodeRunCardView` — seven phases, live `ExecStep` rows, real per-file diffs with accept toggles, and a safe commit to a throwaway `codepet/<slug>` branch. `GitRunner`, `CodeCommitService`, `MockCodeRunner`, `ProjectLinker` and `CodingRunCoordinator` are all in the tree and tested.

Five gaps separate that from the Codex experience:

| | Codepet today | Codex |
|---|---|---|
| **Turns** | One shot. `claude -p --max-turns N` (`ClaudeCodeRunner.swift:137`); no session id captured, no `--resume`. "No, do it differently" means re-asking from zero | Persistent thread; every follow-up sees the prior turn |
| **Ask vs. do** | Two universes. Eng chat → cloud `companyChat`, which knows nothing about the repo; Build → local `claude`, which knows nothing about the company. `byte`-initiated `edit_code` is explicitly deferred (2026-07-31 spec §9) | One thread reads the repo, answers, *and* edits |
| **Review** | Diffs inline in a chat card, scoped to that run only | A dedicated pane: Unstaged / Staged / Commit / Branch / **Last turn**, stage-or-revert per hunk, inline line comments that feed back to the agent |
| **Permission** | Fixed: preview if >1 file or bash, else auto-run; always a diff gate | Sandbox × approval matrix — on-request / auto-review / never |
| **Landing the work** | Local throwaway branch. Never pushes | Worktrees, setup scripts, stage → commit → push → PR, parallel cloud tasks |

And one gap that is Codepet's alone: the local runner **requires the founder to have Claude Code installed and a repo on disk**, which is a wall for exactly the non-technical founder the product is sold to.

## 3. Decisions

| Decision | Choice |
|---|---|
| Where code runs | **Anthropic Managed Agents** — a cloud sandbox Anthropic hosts |
| Repo origin | **Connect-or-create** at first run: connect an existing GitHub repo, or let Codepet create and scaffold one |
| Surface | **A mode in the existing chat**, which can expand to a full-width workspace with a Review pane |
| Definition of done | **A clickable preview URL.** The branch and PR are plumbing underneath |
| Preview host | **Vercel's GitHub app**, wired at repo-create time for Codepet-created repos |

### Why Managed Agents over building on Cloud Run

Rejected alternatives, for the record:

- **Cloud Run Jobs + Claude Agent SDK.** GCP-native, no vendor beta. But Cloud Run Jobs are ephemeral, so multi-turn requires building workspace snapshotting; plus log streaming, spend enforcement and sandbox hardening. Weeks of work landing on top of Stripe before the same freeze.
- **Managed Agents with a self-hosted sandbox.** Founder code never leaves our infra — the better story for a security-conscious buyer. But `github_repository` resource mounting and vault-injected credentials are not supported on self-hosted, so we would hand-roll precisely the parts that make the hosted option cheap, and still carry the beta.

What Managed Agents gives us that we would otherwise build:

- **Repo mounting with proxy-injected credentials.** A `github_repository` session resource clones the repo; the token never enters the container — `git push` and GitHub REST are routed through an Anthropic-side proxy that injects it *after* the request leaves the sandbox. Code running in the container, including code the agent writes, cannot read or exfiltrate it. Our sealed per-uid tokens in `functions/src/oauth/` plug straight in.
- **Stateful multi-turn sessions.** The container and its working tree persist between turns. This is the single thing the current architecture cannot do at all.
- **A platform-enforced dollar cap per session.** `budget: {type: "limit", max_list_cost: {amount, currency}}`. The session pauses at `stop_reason: budget_reached` rather than overspending, and raising or removing the budget resumes it. For a credits product with an expiring trial, this is spend enforcement we do not have to write and cannot get wrong.
- **Per-tool permission policies** (`always_allow` / `always_ask`), which is Codex's approval model for free.
- **An SSE event stream** in a shape `SSEParser.swift` and `CodeExecSteps.swift` already read.

**The cost:** it is a beta API on the launch critical path. §9 covers the fallback.

---

## 4. Architecture

The native app never talks to Anthropic. Everything goes through `functions/`, because the API key lives in Secret Manager and credit enforcement has to be server-side or it is not enforcement.

```
codepet (macOS)                functions/            Anthropic CMA          GitHub / Vercel
──────────────────             ──────────            ─────────────          ───────────────
EngineeringClient  ──POST──▶  engStartRun  ──create session──▶  container
  (SSE)            ◀─stream──  engStream    ◀────SSE events─────  (repo mounted)
EngineeringRunStore ─POST──▶  engSendTurn  ──user.message───▶       │
  @Published                                                        └─push branch─▶ PR
                              engWebhook   ◀──session.status_idle──┘        │
                                   │                                        └─▶ preview
                              Firestore ◀──durable run record
```

### 4.1 Cloud Functions (three, following the `companyChat` pattern)

- **`engStartRun`** — resolves the founder's repo and sealed GitHub token, converts their remaining credits into a session `budget`, creates the CMA session with the repo mounted, writes the run record, returns `runId`.
- **`engStream`** — SSE relay while the app is foregrounded. **Reconnect-safe:** on connect it fetches `sessions.events.list` and dedupes by event id before tailing the live stream, so a dropped connection loses nothing. Cloud Functions v2 caps an HTTP request at 60 minutes; a longer run survives because of the webhook below.
- **`engWebhook`** — the durable backstop. CMA posts `session.status_idled` / `session.status_terminated`; the function verifies the HMAC signature, fetches the finished session, and writes the result to Firestore. **This is what lets a run outlive the app being closed** — the whole point of a cloud sandbox, and something the local runner can never do.

### 4.2 The agent object

`agents.create()` runs **once**, at deploy, and the id goes in config. It is not called per request — that would accumulate orphaned agents and pay create latency on every run.

Per-founder context (brief, stack, conventions) rides in as an `agent_with_overrides` on each session's `system` field, so we get company-specific grounding without versioning an agent per user. The reusable definition lives as version-controlled YAML in `functions/agents/engineering.agent.yaml`, applied with the `ant` CLI, matching how the rest of the repo treats deployable config.

### 4.3 Session = thread, not turn

One CMA session backs one Codepet engineering thread, mapping onto the existing `ChatThread`. Follow-ups are `user.message` events into the live session.

### 4.4 Where the diff comes from

**Not** from parsing container output. The agent pushes its branch; Codepet reads `GET /repos/{owner}/{repo}/compare/{base}...{head}` with the founder's token. That returns per-file patches with real add/delete counts, and it is what makes the Review pane's scope selector honest:

- **Branch** = `base...head`
- **Last turn** = `shaAtTurnStart...head`
- **Commit** = a single sha

No new plumbing, and it is accurate by construction rather than by parsing.

### 4.5 Firestore

`companies/{uid}/engRuns/{runId}`: `sessionId`, `repo`, `branch`, `baseSha`, `turnStartShas[]`, `status`, `prUrl`, `previewUrl`, `diffStat`, `creditsSpent`, `createdAt`, `endedAt`.

### 4.6 Swift

Mirroring the existing shape rather than inventing one:

- `Models/EngineeringRun.swift` — `EngineeringPhase { preparing, running, awaitingApproval, reviewing, shipping, shipped, budgetReached, failed(String) }`, plus `ReviewScope` and `FileDiff`.
- `Managers/EngineeringRunStore.swift` — `@MainActor ObservableObject`, the cloud twin of `CodingRunCoordinator`. `@Published run`, `@Published steps`, `@Published diffs`.
- `Services/EngineeringClient.swift` — SSE over `SSEParser`, behind a `protocol EngineeringRunning` seam so a mock can drive the whole flow offline (same pattern as `CodeRunning` / `MockCodeRunner`).

`CodingRunCoordinator` and the local `claude` path are **untouched** and keep serving `.build` until Engineering ships. Then `.build` folds into Engineering and the local runner becomes a power-user option in Environment — and the outage fallback (§9).

---

## 5. UI

### 5.1 The mode

`ChatMode` gains `.engineering`. `ChatComposer`'s menu already renders `ChatMode.allCases`, so the control costs nothing. The mode carries **Engineering's own accent** — `CodepetTheme.accentBlue`, the department's colour in `DepartmentCatalog` — so an eng turn reads as distinct from the purple copilot chrome without inventing a palette.

### 5.2 The collapsed turn, in the dock

```
┌─ Your team ──────────────────┐
│   add stripe checkout        │
│                              │
│ ▸ Worked for 41s             │
│                              │
│ ┌──────────────────────────┐ │
│ │ ±  Changed 3 files       │ │
│ │    +87 −14               │ │
│ │              [Review]    │ │
│ └──────────────────────────┘ │
│ ✓ Preview ready  ↗           │
└──────────────────────────────┘
```

Expanding `Worked for 41s` reveals the existing `ExecStep` rows in `.mono` — one per tool call, real filenames, real counts.

Two deliberate divergences from Codex:

- **Filenames are one tap away, not two.** Codex's collapsed view hides edited filenames behind an aggregate summary and its users filed a bug about it (openai/codex#19891). We show `Changed 3 files` collapsed, filenames on first expand.
- **No Undo button.** Codex has one and it is unreliable; `6982df0` already removed a dead Undo from `CodeRunCardView` once. The branch *is* the undo — nothing touched the founder's default branch, so discarding is deleting a branch, and that belongs in the review pane next to the diff, not behind a button that implies local file surgery.

### 5.3 The expanded workspace

**Review** swaps `AppShellView`'s content area — not a sheet, not a new nav destination. Same thread, more room.

```
┌─ Engineering ─────────────────────┬─ Review ──────────────────────────┐
│  add stripe checkout              │  Last turn ▾        +87 −14       │
│                                   │  ─────────────────────────────────│
│  ▾ Worked for 41s                 │  ▾ api/billing.ts          +62 −0 │
│    ⬚ read billing.ts              │   1 + import Stripe from 'stripe' │
│    ⬚ ran npm test  ✓ 14 passed    │   2 + const sk = process.env...   │
│    ✎ edited 3 files               │   3 +                             │
│                                   │  ▸ web/Checkout.tsx        +21 −14│
│  Wants to run:                    │  ▸ .env.example             +4 −0 │
│  ┌─────────────────────────────┐  │                                   │
│  │ npm install stripe          │  │                                   │
│  │      [Allow]  [Not this]    │  │                                   │
│  └─────────────────────────────┘  │                                   │
│                                   │  ─────────────────────────────────│
│  ┌─────────────────────────────┐  │  ✓ Preview ready ↗                │
│  │ follow up…              ↑   │  │  [Ship this]      [Open PR]       │
│  └─────────────────────────────┘  │  ~12 credits used                 │
└───────────────────────────────────┴───────────────────────────────────┘
```

Four things earn their place:

- **Scope selector** — `Last turn` / `Branch` / `Commit`, all three from one compare call. "Last turn" is what a founder wants after a follow-up; "Branch" is what they want before shipping.
- **Inline line comments** *(designed now, deferred to v1.1 — see §10)* — hovering a line reveals `+`; the comment attaches to `file:line` and becomes the next follow-up turn, pre-scoped. The highest-leverage thing Codex does: it turns "this is wrong" into a precise instruction without the founder having to describe where. The pane must be built so this drops in without a rewrite: the diff renderer owns per-line hit targets from day one, even though nothing is wired to them at freeze.
- **The approval card is inline in the transcript, not a modal.** It is a `tool_confirmation` on an `always_ask` tool. A modal that blocks the app for an `npm install` is disproportionate, and modal dialogs are already a known hazard in this codebase.
- **"Ship this", not "Merge PR".** Primary action, plain language; `Open PR` sits secondary for anyone technical. The credits line is always visible — a founder spending real money on a run should never have to go looking for the number.

### 5.4 First run: connect or create

One sheet, once, on the first Engineering send:

> **Where should Codepet build?**
> `[ Connect a GitHub repo ]` — pick from your repos
> `[ Create one for me ]` — Codepet scaffolds `<company-slug>` from your brief and wires up preview deploys

Path two also installs the Vercel GitHub app, which is what makes the preview URL possible. Path one gets previews only if the repo already has them; where it doesn't, the card says so rather than showing a dead chip.

---

## 6. Credits and cost

CMA prices a session's **list cost** as model tokens + **$0.08/hour** container runtime + $10 per 1,000 web searches, and enforces the cap before each model request.

Worked example for a ten-minute run on Claude Opus 5 ($5/$25 per MTok), assuming ~300K mostly-cached input and ~30K output:

| Component | Cost |
|---|---|
| Container runtime (10 min @ $0.08/hr) | ~$0.013 |
| Cached input reads | ~$0.15 |
| Output | ~$0.75 |
| **≈ per run** | **~$0.9** |

At the $0.05/credit overage rate that is ~18 credits, so a Pro founder's 800 included credits are roughly 40 engineering runs a month if they did nothing else. **Proposed default per-run cap: 40 credits ($2.00 list)** — generous headroom, and the session pauses rather than running away.

**Two numbers need a decision, not a guess:**

1. **Model.** Opus 5 is the default and the strongest on agentic coding. Claude Sonnet 5 ($3/$15, with a $2/$10 introductory rate through 2026-08-31 that covers launch) is roughly 3× cheaper per run and is specifically strong on coding and agentic work. That is a margin decision, not a technical one, and it is Mona and Giang's to make.
2. **Credit conversion.** The existing model targets a blended ~$0.045–0.05 per generation; an engineering run is an order of magnitude more expensive than a chat turn, so eng runs must be metered by measured list cost rather than counted as one generation. The conversion rate needs real-usage calibration during the closed beta, exactly like the trial credit amount already flagged in the PRD.

---

## 7. Error handling and honest degradation

| Condition | Behaviour |
|---|---|
| No repo connected | First-run sheet (§5.4). Never a dead-end. |
| Session hits its budget | Card reads "This run hit its spending cap" with the amount spent, and offers **Raise cap** / **Stop here**. Not an error — the session is paused and resumable. |
| App closed mid-run | The webhook writes the result. The run appears finished on next launch. This is a feature, and the card should say when it completed. |
| Stream drops | Reconnect re-lists events and dedupes; nothing is lost. |
| Push rejected (protected branch, revoked token) | Reported plainly with the GitHub message. The work is still in the container and the session is still live, so a retry after fixing permissions does not re-run the agent. |
| Preview deploy fails | Chip reads "Preview failed ↗ logs". The diff and PR are still valid; the run is not marked failed. |
| CMA unavailable | §9. |

Every one of these renders as a phase of `EngineeringRun`, not as a toast — the card stays truthful about where the run actually stopped, which is the same principle `CodingRunCoordinator` already applies to `nothingToCommit` vs. a real commit failure.

---

## 8. Testing

Following the repo's existing split — pure cores in jest, coordinator phases in XCTest, no live services in CI.

**`functions/` (jest, no Firebase):**
- Credits → `max_list_cost` conversion, including the floor and the "must exceed consumed cost" rule on a raise.
- CMA event → `ExecStep` mapping.
- GitHub compare payload → `[FileDiff]`, including renames, binary files, and truncated patches.
- Webhook HMAC verification, including a replayed delivery (dedupe on event id).

**Swift (XCTest, per-suite via `-only-testing:`):**
- `EngineeringRunStore` phase transitions across the full lifecycle, driven by a `MockEngineeringClient` — start → step → approval → review → ship, plus budget-reached, stream-drop-and-resume, and push-rejected.
- `ReviewScope` → compare-range derivation.

Per the working agreement in `CLAUDE.md`: each guard gets a test that goes red if the guard is deleted. Specifically — the budget cap, the "token never enters the container" assumption (asserted at the request-construction layer, since we cannot assert it in the container), and the reconnect dedupe.

**Not in CI:** any test that creates a real CMA session. One manual smoke run against a scratch repo is part of the release checklist instead.

---

## 9. Risk: this is a beta API on the critical path

Managed Agents is in beta. The mitigation is already in the tree: **the local `claude`-CLI runner stays shipped**. If CMA is unavailable or its beta shape shifts before freeze, Engineering mode degrades to the existing local path for founders who have Claude Code and a linked folder, and to an honest plan for those who don't.

That is the same shape as the go/no-go the launch plan already carries for the build agent, one rung better: the fallback is no longer "an honest plan", it is "a working local agent".

**Go / no-go on ~Aug 15**, unchanged from the launch plan. The decision is whether the CMA path is trustworthy end to end, not whether code execution works at all — that question is already answered by the shipped local runner.

---

## 10. Scope

**Ships by the Aug 22 freeze:**
- `.engineering` mode and the collapsed result bar
- Cloud session with the repo mounted; multi-turn follow-ups
- Live streaming with reconnect; webhook durability
- Expanded workspace with the Review pane and scope selector
- Inline approval cards
- Branch push, PR, and preview for Codepet-created repos
- Budget enforcement and the credits line

**Deferred, in order:**
1. **Inline line comments** — the highest-value deferral and the first thing after freeze. Everything else in the Review pane works without it.
2. Roadmap-task → engineering-run dispatch (`RoadmapDispatch` already exists; cheap, but not P0).
3. Parallel runs across threads.
4. Multi-repo projects.
5. `byte`-initiated engineering runs from an ordinary chat turn — still deferred, as in the 2026-07-31 spec §9.

---

## 11. Open questions

**RESOLVED 2026-08-11 — Managed Agents access confirmed.** The blocking question
("does our account have CMA access at closed-beta volume?") is answered yes for
access; volume is untested. Evidence from the spike, so nobody re-runs it:

- The pinned `@anthropic-ai/sdk` already exposes `client.beta.{agents, sessions,
  environments, webhooks}` — **no SDK upgrade was needed**, `package.json` untouched.
- A cloud environment, an agent on `claude-opus-5`, and a session with a private
  GitHub repo mounted at `/workspace/repo` all created successfully.
- The event stream delivered `session.status_running` → `span.model_request_start`
  → `agent.tool_use` → `agent.tool_result` → `agent.message` → `session.usage` →
  `session.status_idle`, and the agent correctly read the repo tree. The stream
  shapes this plan's `engEvents` mapping targets are real.
- Spike resources, left behind and safe to archive from the Console once Task 10
  provisions the production pair: `env_01XwpiRn4tzZeP1ejpKJQdN4`,
  `agent_01FZf9TJEjZHiFwVccj2gApS` (v1).

Still unknown: whether rate limits hold at 10–20 concurrent beta founders. That is
a load question, not an access question, and it belongs in the closed beta.

- Model tier for engineering runs (§6) — Opus 5 vs. Sonnet 5. Margin decision.
- Credit conversion rate for engineering runs (§6) — needs closed-beta calibration.
- What Codepet scaffolds into a created repo: an empty repo with a README, or a stack chosen from the brief. The latter makes the first preview meaningful; the former is faster to build and harder to get wrong.
