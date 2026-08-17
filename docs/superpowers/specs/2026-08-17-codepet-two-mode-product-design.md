# Codepet — two-mode product design (Ask / Developer)

**Date:** 2026-08-17
**Status:** design agreed in conversation with the founder. Nothing built; no implementation branch.
**Sketch:** https://claude.ai/code/artifact/2f47addb-f056-4684-bc47-4c553f43b63d
**Builds on**, and note where each lives — two of them are **not on `main`**:

| Document | Where |
|---|---|
| `virtual-company-sse-contract.md` — **outranks this document wherever they touch** | `main` |
| `2026-07-31-coding-agent-in-copilot-design.md` — the local runner as shipped | `main` |
| `2026-08-11-engineering-mode-design.md` — the cloud Engineering backend | `main` |
| `2026-08-03-virtual-company-in-chat-design.md` — the room in chat | `main` |
| `2026-07-29-chat-system-integration-map-design.md` — **the Capability Bus** | only on `origin/feat/chat-redesign` (`c19715a`) |
| `2026-07-29-coding-agent-design.md` — the original safety rails | only on `origin/feat/chat-redesign` |

The Capability Bus vocabulary this design leans on therefore has **no copy on `main`**: it went down
with PR #39 and survives only on the kept branch. Anyone implementing from this spec should read it
there, and it is worth cherry-picking those two documents onto `main` as part of the first PR.

---

## 1. Why this exists

Three things were true at once, and the shell reflected none of them.

**Chat is the product's spine, and the shell said otherwise.** `main` opens on Overview with a top nav
and chat in a docked column. The dock *is* the product; a column is the wrong container for it.

**Modes were per-message intents that leaked our infrastructure.** `ChatMode` offered
`ask / plan / build`, and until 14 Aug also `engineering`, shown as "Developer". Its own header
records why that was wrong: Build and Developer "both meant *change my code* and differed only in
WHERE the work executed… asking a founder to pick it per message made them understand our deployment
before they could send a sentence." Folding `engineering` into `build` fixed half of it. The other
half is that a *place* — not a message prefix — is what should carry that distinction.

**Engineering has two working backends and no home.** The local `claude` CLI (`ClaudeCodeRunner`,
real diffs, 0 credits) ships in the docked copilot; the cloud Engineering agent on Anthropic Managed
Agents is provisioned and deployed. Neither has a workspace a founder can sit in.

---

## 2. The model

> **Codepet is a chat with two destinations.** *Ask* is where you talk to your company. *Developer*
> is where your company touches your code. Everything else is state you browse.

**The mode is a place, not an intent.** Intent is inferred from what the founder typed, exactly as
it always was. The place decides which agents may act and on which backend. One door per agent.

### 2.1 The four invariants

1. **Chat is the only place work happens.** Unchanged from the Capability Bus. The sub-features feed
   context slices and expose verbs; pages browse and manage state. A `Start` on Roadmap dispatches
   into whichever mode owns that verb — an Engineering task to Developer, everything else to Ask.
2. **The mode gates the backend, never the sentence.** Ask reaches the nine cloud departments
   (credits). Developer reaches code (Local: the founder's own CLI, 0 credits; Cloud: the Managed
   Agent, credits). Where a run executes is a property of the session.
3. **Both modes share one lifecycle and one card grammar.** `proposed → running → result → review →
   committed`; only `committed` writes to context. Exec log, Stop, approve gesture and card hues
   (gold = you owe a decision) are identical on both sides. This is what keeps it one product.
4. **The room is an act, not a mode.** `.plan` retires; convening is proposed as a card the founder
   taps, priced in credits.

### 2.2 The sidebar (hybrid)

The mode-specific group changes; the five company surfaces never move, because a roadmap task and
the code that satisfies it belong one click apart.

| | Ask | Developer |
|---|---|---|
| Create | `+ New` | `+ New` |
| Above the divider | `RECENT` — threads, grouped Today / Yesterday / Earlier | `REPO` (name · branch), then `SESSIONS` with state glyphs: `●` running, `✓` committed, `☁` still running in the cloud |
| Company surfaces | `WORKSPACE`, open: Roadmap · Company · Tasks · Library · Environment | the same five, **collapsed to one `Workspace ⌄` row** |
| Foot | Upgrade to Pro · account · credit meter | identical |

**`+ New` is one label in both modes** and is deliberately quiet — an outlined row, not a gradient.
The gradient belongs to `Upgrade` alone, which is the only button in the sidebar that should sell
something. What `+ New` creates is named by the switch above it and the list below it.

**Second Brain** stops being a destination and becomes a tab: `Company → Departments │ Learn`. It
already reads roadmap + departments, so it belongs beside the departments it explains. Nothing is
deleted — `SecondBrainData`, `LessonContent` and `SkillData` keep their reader.

---

## 3. The Ask workspace

The founder-facing surface is what `main` and the kept `feat/chat-redesign` branch already describe:
`CompanionOrb` over a greeting, a composer whose department chips ground the question, `DO THIS NEXT`
carrying the beacon, and the message list at `chatColumnWidth`.

**There is no mode pill in the composer.** The shell toggle replaced it.

### 3.1 Where Plan went

`.plan` was never "write me a plan" — it was the money gate. `ChatMode.convenesRoom` is true only
for Plan because a convened decision measures **~$0.20 against ~$0.005** for an ordinary turn
(`b42bc10`, 7 Aug), so a casual Ask could cost forty times what it looked like. Deleting the pill
deletes that brake, so the brake has to move, not vanish.

**The companion proposes; the founder pays.** The reply to an ordinary turn can carry a `convene`
proposal card:

```
THIS LOOKS LIKE A DECISION
Convene Engineering, Finance and Design?
Four departments argue it out, then Chief of Staff synthesises.
[ Convene · ~10 credits ]   [ Just answer me ]
```

- **Priced in credits, never dollars.** Pricing is locked to credits with chat at ~0.25 credit per
  message so it *feels* unlimited. A USD figure would publish our cost of goods and break that
  abstraction; `~$0.20` is an internal runbook measurement and stays internal.
- **`~10 credits` is derived, not decided** — 0.25 × the measured ~40×. The pricing spec owns the
  real number (see §8).
- **The cheap path shows no number.** It is the price the founder already assumes.
- **A manual entry lives in the composer's `+` menu** — "Convene the company" — for when the founder
  already knows the question deserves a room.
- `convene` joins the verb set as a Capability Bus verb whose approval is the founder's tap.
  `convenesRoom` survives unchanged as the permission flag; only its *source* changes, from a
  persistent pill to a per-message tap.

**Who decides an offer is warranted — an implementation choice, and the earlier assumption was wrong.**
The router (`single_agent` / `multi_agent` / `convene_everyone` / `needs_clarification`, capped at
`MAX_ROOM_AGENTS = 4`) lives **inside `virtualCompanyRun`**, and there is no classify-only endpoint:
`index.ts` exports `companyChat` and `virtualCompanyRun`, nothing between them. Since Ask never fans
out, nothing classifies an Ask message today. Two ways to close that:

- **(a) A routing-only call** — invoke the routing tool alone, then offer. Uses the same judgment
  that will actually convene the room, at the cost of one extra small call per turn.
- **(b) The companion proposes it as a tool** in its ordinary `companyChat` turn — no new endpoint,
  no extra call, and it fits the Bus exactly: a verb the companion requests and the founder approves.

**Recommendation: (b)**, and measure how often it offers. If it over-offers, (a) is the fix, because
the router is stricter than a companion's judgment. Either way the offer must cost an ordinary turn —
**never** a room the founder did not tap.

### 3.2 Card grammar

Unchanged, and now shared with Developer: one tinted card (hue at 12% with a stepped same-hue edge),
hue encoding the kind of ask — gold *you owe a decision*, violet *the companion suggests*, blue
*you are being asked*, teal *capability*, muted *receipt*, hairline *pure navigation*.

---

## 4. The Developer workspace

**A session is the unit.** It owns a repo, a base branch, a backend, an approval tier, and the diff
currently under review. A chat thread owns messages; a session owns all of that as well.

### 4.1 Two backends, one review

| | ▣ Local | ☁ Cloud |
|---|---|---|
| Where the code is | a folder on this Mac, uncommitted work included | a connected repo at a base branch |
| Runner | the founder's own `claude` CLI (`ClaudeCodeRunner`) | the deployed Managed Agent |
| Who pays | **0 credits** — their Claude subscription | **credits**, metered per run |
| App closed | the run stops with the app | keeps working; results wait |
| Approve does | commit to `codepet/<task>`; if there is no `.git`, apply a shadow copy and keep a backup | commit to a branch, then optionally open a PR |

Chosen once per session as a chip, never asked mid-sentence. The exec log, the diff review and the
approve gesture are **backend-agnostic** — that is a requirement on the implementation, not a
coincidence.

### 4.2 The surface

Three columns of information, no editor:

- **Files** — a tree, plus a `CHANGED · n` list with per-file `+/−`. Clicking a file **scopes the
  next instruction to it**, shown as a `scoped to <file>` chip in the composer.
- **Viewer** — syntax-highlighted and **read-only on purpose.** Codepet should not compete with the
  editor already open on the founder's other monitor.
- **Work** — the session title, the run state (`running · step 3 of 5`), the honest N-step exec log,
  then the unified diff per file with `Approve this file` / `Approve all · commit to <branch>` / `Stop`.

Hand-editing a buffer is a **non-goal** for v1 (§9): making a buffer editable is a change to one
view, not to the model, so it can wait for evidence founders want it.

The composer additionally accepts a file or pasted snippet via `+`, so a founder with no repo linked
can still get code reviewed.

### 4.3 Approval tiers

The complaint this answers: every command needs manual approval, so "approve" stops being a decision
and becomes a reflex. Three gates get conflated, and only the first is friction:

1. **step approvals** during a run — may I read this, run the tests, edit this line;
2. **the commit gate** — the diff review, which is a reading, not an interruption;
3. **the ceiling** — merge, deploy, delete, force-push. Never automatic, at any tier.

**The tier lives in the composer**, beside `+`, not in the session bar. The session bar carries facts
set once (repo, branch, backend); the composer carries controls for the *next instruction*, and the
tier is that kind of thing — loosened for a step the founder trusts, tightened for one they don't.
This is where Codex puts it, next to its model picker.

| Tier | Steps | Commit | Boundary |
|---|---|---|---|
| ✋ **Ask me** | every file edit and command prompts | prompts | linked folder |
| ▶ **Work on its own** — **default** | edits and test runs inside the linked folder proceed silently; stops for anything outside it and for network installs | **prompts** | linked folder |
| ⚡ **Let it run** | no step prompts | **commits to the session branch itself** | linked folder |

**Never, at any tier:** merge · deploy · delete · force-push · touch a file outside the linked folder.

Design notes that matter:

- **Default is `Work on its own`, not `Ask me`.** Defaulting to the safest tier means every founder
  meets the nagging first and has to go hunting for the fix — the reported problem, shipped as the
  default.
- **The tier is per-session, not global.** Permissive on your own repo, cautious on a client's, and
  a tier can never silently follow you into another project.
- **Our top tier is narrower than Codex's on purpose.** Codex separates `sandbox_mode`
  (`read-only` / `workspace-write` / `danger-full-access`) from `approval_policy`
  (`untrusted` / `on-request` / `never` / `granular`), and its top setting drops the sandbox
  entirely — network plus any file on the machine. Ours collapses both axes into three named tiers,
  and the linked folder stays a wall no tier can climb, so the worst case remains a branch you can
  delete.
- **Cloud sessions barely need the setting.** The agent works in a managed sandbox on a branch, not
  on the founder's Mac, so per-step prompts there are theatre and the PR is the real gate. The tier
  control is about **Local**.

### 4.4 This amends a written rail

The coding-agent design states that Codepet "never writes the real tree without approval" — written
on the kept branch (`2026-07-29-coding-agent-design.md`, with the run/commit engine plan restating it)
and carried into the shipped `2026-07-31-coding-agent-in-copilot-design.md`.
**`Let it run` softens that by the founder's explicit choice.** The amended rail:

> Codepet never writes the real tree without approval, **unless the founder has selected `Let it
> run` for this session** — in which case it commits only to the session branch, and the ceiling
> (no merge, deploy, delete, force-push, or write outside the linked folder) still holds absolutely.

Recorded here rather than left to quietly stop being true.

---

## 5. Data model

**One thread collection, one new field.** `ChatThread` gains `kind: ask | dev`. Ask's `RECENT` and
Developer's `SESSIONS` are two filters over `companies/{uid}/threads/{id}` — the subcollection whose
**deployed Firestore rules already cover this**, so no rules change ships with this design.

A `kind: dev` thread additionally carries:

| Field | Meaning |
|---|---|
| `backend` | `local` \| `cloud` |
| `repoRef` | a local folder path (client-only, never uploaded) or a remote `owner/name` |
| `baseBranch` / `workBranch` | e.g. `main` → `codepet/fix-signup` |
| `approvalTier` | `askMe` \| `worksOnItsOwn` \| `letItRun`, defaulting to `worksOnItsOwn` |
| `runState` | the shared lifecycle value |

`WorkspaceMode { ask, developer }` replaces `ChatMode`, persists per account under a `cp_`-prefixed
key, and is restored on launch. The `project · code` context slice stays **client-only for Local**,
as already specified.

---

## 6. What retires, and what replaces it

| Retires | Becomes |
|---|---|
| `TopNavView` and the docked copilot column (`ShellLayout.dockCollapsed(forWidth:manual:)`) | `SidebarView` + a full-width pane. The dock *was* the chat, so it stops being a column. |
| `ChatMode` and the composer's `ask / plan / build` pill | `WorkspaceMode` + the `convene` verb |
| Second Brain as a destination | `Company → Departments │ Learn` |
| per-message "Developer" intent | a per-session `Local │ Cloud` chip |

`SidebarView` is not new work from zero: it exists on `origin/feat/chat-redesign` (tip `c19715a`,
deliberately kept as a cherry-pick source after PR #39 was closed) with the brand row, `+ New`,
grouped Recent, the Workspace nav, Upgrade and the account row already built.

**Tests are rewritten, not deleted.** `RoomGatingTests` and `ChatModeEngineeringTests` encode
decisions that survive this change — the room needs permission; there must be one door to the coding
agent. They must be re-pointed at `WorkspaceMode` and the `convene` verb, and must still go red if
those guards are removed.

---

## 7. Testing

Unit-testable without the app host wherever possible, because the XCTest host on Xcode 26.2 crashes
when a `@MainActor ObservableObject` deallocates (~27 tests never finish; run per-suite with
`-only-testing:` and do not chase it as a regression).

- **Mode**: `WorkspaceMode` persists and restores; the sidebar's mode-specific groups are mutually
  exclusive — a test that fails if both `RECENT` and `SESSIONS` can be visible at once. *(The sketch
  shipped exactly that bug: a class setting `display` outranked `[hidden]`. The SwiftUI equivalent is
  a stale `if` on the wrong state, and it deserves a test rather than a glance.)*
- **Convene**: an offer card appears only when the router's classification warrants a room and
  permission is absent; tapping `Convene` is the only path that sets `convenesRoom: true`; the
  ordinary path never fans out.
- **Tiers**: for each tier, the exact allowed action set — `askMe` prompts on the first edit,
  `worksOnItsOwn` proceeds in-folder but prompts at commit, `letItRun` commits to the work branch.
- **The ceiling**: merge, deploy, delete, force-push and any write outside the linked folder are
  refused **at every tier, including `letItRun`.** Per the working agreement, this guard gets a test
  that goes red if the guard is deleted.
- **Backend agnosticism**: the same exec-log and diff-review views render from a Local run and a
  Cloud run.

---

## 8. Open decisions

1. **Overview's fate — the founder's call, deliberately unresolved.** The living progress dashboard,
   the centre-framed company map, the project briefing and the first-run spotlight all ship on
   `main`, and this shape has no slot for them. Either (a) Overview retires and the Ask hero plus
   the `DO THIS NEXT` beacon carry "where am I," or (b) the Codepet wordmark clicks through to it as
   the one page above the five. **Recommendation: (b)** — it costs one route and zero sidebar space,
   and (a) deletes shipped work to solve a problem we have not measured.
2. **The credit price of a convened room.** `~10` here is derived. The pricing spec owns it, and the
   trial credit amount is still open there.
3. **Whether the Developer composer's right side gets a model / effort control**, as Codex has. Under
   our pricing that is a credit-priced choice, not a free toggle — the same objection that kept a
   DeepThink-style depth selector out of the Phase 2 chat design.

## 9. Non-goals for v1

- Hand-editing code inside Codepet.
- Any access outside the linked folder, at any tier — including network installs without a prompt.
- Unattended merge, deploy or delete. The §5.5 ceiling is not negotiable by a setting.
- Rebuilding the Virtual Company room UI. Only its *entry point* changes.
- New Firestore rules. If the implementation needs them, a premise in §5 is wrong.
