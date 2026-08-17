# Codepet — two-mode product design (Ask / Developer)

**Date:** 2026-08-17
**Status:** design agreed with the founder over one session. Nothing built in the app; no implementation branch.
**Prototype:** https://claude.ai/code/artifact/2f47addb-f056-4684-bc47-4c553f43b63d — driveable, and it
self-tests on load (78 assertions at time of writing). Where this document and the prototype disagree,
the prototype is the newer artefact and this document is wrong.

**Builds on**, and note where each lives — two of them are **not on `main`**:

| Document | Where |
|---|---|
| `virtual-company-sse-contract.md` — **outranks this document wherever they touch** | `main` |
| `2026-07-31-coding-agent-in-copilot-design.md` — the local runner as shipped | `main` |
| `2026-08-11-engineering-mode-design.md` — the cloud Engineering backend | `main` |
| `2026-08-03-virtual-company-in-chat-design.md` — the room in chat | `main` |
| `2026-07-29-chat-system-integration-map-design.md` — **the Capability Bus** | only on `origin/feat/chat-redesign` (`c19715a`) |
| `2026-07-29-coding-agent-design.md` — the original safety rails | only on `origin/feat/chat-redesign` |

The Capability Bus vocabulary this design leans on has **no copy on `main`**: it went down with closed
PR #39 and survives only on the kept branch. The first implementation PR should cherry-pick those two
documents onto `main`.

---

## 1. Why this exists

Three things were true at once, and the shell reflected none of them.

**Chat is the product's spine, and the shell said otherwise.** `main` opens on Overview with a top nav
and chat in a docked column. The dock *is* the product; a column is the wrong container for it.

**Modes were per-message intents that leaked our infrastructure.** `ChatMode` offered
`ask / plan / build`, and until 14 Aug also `engineering`, shown as "Developer". Its own header records
why that was wrong: Build and Developer "both meant *change my code* and differed only in WHERE the
work executed… asking a founder to pick it per message made them understand our deployment before they
could send a sentence."

**Engineering has two working backends and no home.** The local `claude` CLI (`ClaudeCodeRunner`, real
diffs, 0 credits) ships in the docked copilot; the cloud Engineering agent on Anthropic Managed Agents
is provisioned and deployed. Neither has a workspace a founder can sit in.

---

## 2. Use cases

### 2.1 Who this is for

**A solo founder, or a two-person team, shipping software with AI.** They can build. What they do not
have is anyone to argue strategy with, anyone to write the document they have been avoiding, or anyone
who remembers what was decided three weeks ago.

**Who it is not for**, stated so scope stays honest:

- Teams that already employ a head of marketing or a finance lead. The departments would compete with
  real colleagues, and a real colleague wins.
- Non-technical founders with no repo — Developer stays dormant for them, and roughly half the product
  is unreachable. Ask alone may still be worth the price; that is a positioning question, not a
  product one.
- Anything with seats. v1 is single-founder: one account, one company, no shared inbox, no review
  queues for other people.

### 2.2 The five moments Codepet is for

Use cases stated as the founder's own sentence, because that is how they will recognise them:

1. *"I am about to make a call I will live with for months, and there is nobody to check it."*
2. *"I know this document should exist. I have been avoiding it for two weeks."*
3. *"I have forty things to do and no idea which one is first."*
4. *"This change is small and I know roughly what it is — I do not want to lose an hour to it."*
5. *"I did the user interviews. The insight is in my head and nowhere else."*

### 2.3 The eight use cases

Each one names what the founder would otherwise do, what Codepet produces, and what it costs. Cost is
the honest column — a use case nobody can afford is not a use case.

| # | Use case | Without Codepet | Produces | Where | Cost |
|---|---|---|---|---|---|
| 1 | **Argue a decision out** — pricing, launch timing, scope cut, hire-or-not | decide alone at midnight, or crowdsource from strangers | a recorded decision every department reads afterwards | Ask · the room | ~10 credits |
| 2 | **Write the document that should exist** — twelve deliverable types already ship, from positioning and ICP to a launch checklist, runway model and support macros | a blank page, avoided | a deliverable in Library, grounded in the brief and prior decisions | Ask · `run_task` | ~3 credits |
| 3 | **Know what is next** — an ordered plan that moves | a list that rots | a stage-aware roadmap with one live next step | Ask · `re_plan` + the beacon | included in a turn |
| 4 | **Make a small code change** — a fix you can specify but do not want to hand-hold | context-switch, lose forty minutes | a branch and a reviewed diff | Developer · `edit_code` | **0 credits** local, credits in the cloud |
| 5 | **Capture what only you can learn** — user interviews, a call with an accountant | an insight that dies in your head | a durable fact in `decisions` | Ask · `walkthrough` + `remember` | free |
| 6 | **Stay consistent over weeks** — every answer built on the same brief, decisions and receipts | re-explaining your company to a chatbot daily | context that compounds instead of resetting | the whole context model | free |
| 7 | **Trust the thing enough to let it act** — see the steps, the diff, the price | either blind faith or doing it yourself | streamed exec logs, per-file diffs, a credit ledger | both modes | free |
| 8 | **Learn the function you do not have** — what does positioning even mean, what does a runway model contain | a blog post of unknown quality | the department's own expertise, in context, next to the work it produced | `Company → Learn` | free |

**Use case 1 in full, as the shape of the rest.** The founder types *"should we ship the paywall before
launch?"* An ordinary turn answers first, cheaply. Then — because the router's classification says this
warrants a room — the companion **offers** four departments, with the price on the button. The founder
taps. Finance argues from runway, Engineering from the billing critical path, Design from what users
can judge; Chief of Staff synthesises one answer. The founder approves, and only then does it reach
`decisions`, add a roadmap task, and start being cited by future work. Refusing it costs nothing more,
and refusing the *conclusion* after paying for the argument is also allowed — the room ran, the write
did not happen.

### 2.4 Anti-cases

What Codepet is deliberately not for. These belong in the spec because each one is a request we will
receive and should decline:

- **Not an autonomous shipper.** It never merges, deploys, deletes or force-pushes — at any approval
  tier. The worst case it can produce is a branch you delete.
- **Not an IDE.** The file viewer is read-only on purpose; the founder's editor stays open on the other
  monitor.
- **Not a general chatbot.** Every turn is grounded in this company's brief, roadmap and decisions.
  Ungrounded questions are a worse experience *and* a waste of credits.
- **Not an analytics product.** It cites connected tools; it does not become one.
- **Not HR.** Departments are functions with voices, not people to manage.
- **Not a team tool.** See §2.1.

### 2.5 How we would know each one works

Success signals, so this is falsifiable rather than aspirational:

| Use case | The signal |
|---|---|
| Argue a decision | the decision is **cited** in later work, not just recorded |
| Write the document | approved on the first pass, not regenerated |
| Know what is next | the beacon is followed rather than ignored |
| Small code change | the branch gets **merged by the founder** |
| Capture learning | a captured fact changes a later answer |
| Stay consistent | week-two answers do not contradict week-one decisions |
| Trust | the founder moves off `Ask me` to a permissive tier and stays there |
| Learn | a founder opens `Learn` from a deliverable, rather than never at all |

---

## 3. The model

> **Codepet is a chat with two destinations.** *Ask* is where you talk to your company. *Developer* is
> where your company touches your code. Everything else is state you browse.

**The mode is a place, not an intent.** Intent is inferred from what the founder typed. The place
decides which agents may act and on which backend. One door per agent.

### 3.1 The five invariants

1. **Chat is the only place work happens.** Pages browse and manage state; a `Start` on Roadmap
   dispatches into whichever mode owns that verb.
2. **The mode gates the backend, never the sentence.**
3. **Both modes share one lifecycle and one card grammar** — `proposed → running → result → review →
   committed`, and only `committed` writes to context.
4. **Tabs are for outputs, not for runs** (§5).
5. **The founder's approval is the only thing that writes.** Every use case in §2.3 ends at a gate.

### 3.2 The shell

Three columns: rail, conversation, inspector.

| | Ask | Developer |
|---|---|---|
| Create | `+ New` — quiet, outlined; the gradient belongs to `Upgrade` alone | `+ New` — same label |
| Above the divider | `RECENT` — threads grouped Today / Yesterday / Earlier | `REPO`, then `SESSIONS` with `●` running, `✓` committed, `☁` running in the cloud |
| Company surfaces | `WORKSPACE`, open: Roadmap · Company · Tasks · Library · Environment | the same five, **collapsed to one row** |
| Conversation | orb, greeting, department chips, the beacon | the run: exec log, and an *Edited N files* summary card |
| Inspector tabs | the drafts being read · Preview | **Files** (read-only) · **Review** (the diff) · Preview |

**Second Brain** stops being a destination and becomes `Company → Departments │ Learn`. Nothing is
deleted; `SecondBrainData`, `LessonContent` and `SkillData` keep their reader — and use case 8 is the
reason it earns its place rather than being retired: the founder is missing the *function*, not just the
output, and the explanation belongs next to the department that produced the work.

---

## 4. The cast — pets are the voice of each department

**Decided by the founder, 17 Aug.** A department is a *function*; the pet is *who speaks for it*. This
resolves the pets-vs-roles question that had been open since the Virtual Company shipped.

Consequences, all three of which are now built in the prototype:

- the cast appears on the **first screen**, not for the first time mid-run;
- the specialist **signs the work it writes** (`nova · Marketing` on the draft it drafted);
- **the room is cast, not labelled** — `crash` makes Engineering's objection, and Chief of Staff's
  synthesis says "crash's objection binds", not "Engineering's".

This is `DepartmentCompanions.map` as it already exists on the kept branch, which means it is **not a
clean 1:1**:

| Pet | Speaks for | Note |
|---|---|---|
| `crash` | Engineering | builds and ships |
| `luna` | Design | UX / UI |
| `nova` | Marketing · Sales | one voice, two rooms |
| `sage` | Finance · Support | "real data, not vibes" |
| `glitch` | Operations · Legal | automation, and edges |
| `byte` | host · Chief of Staff | deliberately unassigned — which is what lets it hand off, and why it synthesises |
| `null` | *nothing* | the spare voice |
| — | **Product** | **no pet, no art** |

**Two costs this decision creates.** Three pets doing two jobs reads acceptably — one person wearing two
hats is what happens in a small company. But **Product has no voice**, and `null` is unused. Casting
`null → Product` and drawing it is the cheap fix; the alternative is deciding Product is not a
department in this product. Either way, `dept-product`'s placeholder art moves from a backlog item to a
**launch blocker**, because a department that cannot speak is now visibly broken rather than merely
absent.

---

## 5. The inspector — tabs for outputs

Adopted from the reference the founder supplied (Codex desktop: chat left, `Review` and a live preview
as tabs right).

**One tab per output you are inspecting** — a draft, a diff, a preview. Not one tab per run.

- **The conversation is never replaced by the thing it produced.** The first prototype had to *overlay*
  the pane to show a deliverable, which destroyed the transcript and its live controls; an assertion now
  pins that opening a draft keeps the conversation alive.
- **Developer's file tree stops being a third column** and becomes a `Files` tab; the conversation keeps
  an `Edited 2 files · +15 −4 · [Review]` summary card and the diff opens in `Review`, which comes
  forward by itself when a run finishes.
- **Tabs belong to the thread or session**, not to the app — each mode restores its own set. A diff you
  were reading is not global state.
- **The inspector takes 47% of the pane** and must collapse below ~900px, reusing
  `ShellLayout.dockCollapsed(forWidth:manual:)` rather than inventing a second rule. **Not yet drawn.**

---

## 6. Running more than one thing

One fact decides the concurrency model: **text deliverables are independent; code is not.** Three
departments drafting three documents touch nothing shared. Two code runs in one folder fight over a
working tree — the collision this repo already solves with worktrees.

- **Ask: parallel is native.** N runs are N cards in one transcript, department attribution telling them
  apart. Comparing their results is what the inspector's tabs are for. No new container, and nothing
  competing with `RECENT`/`SESSIONS` for the identity of the work.
- **Developer: one active run per session.** A session owns a branch. Concurrency means more sessions —
  **Local needs a worktree-or-queue rule**, Cloud parallelises naturally in its own sandbox.
- **A cap and a live total.** Three simultaneous department runs is 3× spend with no extra thought
  required from the founder. Cap concurrent runs (3 proposed) and show committed credits while they run.
- **Warn on a dependency.** The roadmap has `dependsOn`; launching "write the pricing page" while
  "decide pricing" is still running should say so. **Proposed, not decided.**

---

## 7. Ask — where Plan went

`.plan` was never "write me a plan"; it was the money gate. `ChatMode.convenesRoom` is true only for
Plan because a convened decision measures **~$0.20 against ~$0.005** for an ordinary turn, so a casual
Ask could cost forty times what it looked like. Deleting the pill deletes that brake, so the brake moves
rather than vanishing.

**The companion proposes; the founder pays.** An ordinary turn's reply can carry a `convene` proposal
card:

```
THIS LOOKS LIKE A DECISION
Convene Engineering, Finance and Design?
Four departments argue it out, then Chief of Staff synthesises one answer.
[ Convene · ~10 credits ]   [ Just answer me ]
```

- **Priced in credits, never dollars.** Pricing is locked to credits with chat at ~0.25 so it *feels*
  unlimited; a USD figure would publish our cost of goods, and `~$0.20` is an internal runbook
  measurement.
- **`~10 credits` is derived** (0.25 × the measured ~40×), not decided. The pricing spec owns the number.
- **The cheap path shows no number** — it is the price the founder already assumes.
- **A manual door lives in the `+` menu** for when the founder already knows.
- `convenesRoom` survives unchanged as the permission flag; only its *source* changes, from a persistent
  pill to a per-message tap.

**Who decides an offer is warranted — an implementation choice.** The router
(`single_agent` / `multi_agent` / `convene_everyone` / `needs_clarification`, capped at
`MAX_ROOM_AGENTS = 4`) lives **inside `virtualCompanyRun`**, and `index.ts` exports no classify-only
endpoint, so nothing classifies an Ask message today. Either (a) a routing-only call, or (b) the
companion proposes it as a tool in its ordinary `companyChat` turn. **Recommendation: (b)** — no new
endpoint, and it fits the Bus. If it over-offers, (a) is the fix. Either way the offer must cost an
ordinary turn, **never** a room the founder did not tap.

### 7.1 Card grammar

One tinted card, hue at 12% with a stepped same-hue edge. The hue encodes the kind of ask: **gold** you
owe a decision · **violet** the companion suggests · **blue** you are being asked · **teal** a
capability · **green** committed · **muted** a receipt.

---

## 8. Developer

### 8.1 Two backends, one review

| | ▣ Local | ☁ Cloud |
|---|---|---|
| Where the code is | a folder on this Mac, uncommitted work included | a connected repo at a base branch |
| Runner | the founder's own `claude` CLI (`ClaudeCodeRunner`) | the deployed Managed Agent |
| Who pays | **0 credits** — their Claude subscription | **credits**, metered per run |
| App closed | the run stops with the app | keeps working; results wait |
| Approve does | commit to `codepet/<task>`; no `.git` → shadow copy with a backup | commit to a branch, then optionally open a PR |

Chosen once per session as a chip, never asked mid-sentence. The exec log, diff review and approve
gesture are **backend-agnostic** — a requirement on the implementation, not a coincidence.

### 8.2 Approval tiers

Three gates get conflated, and only the first is friction: **step approvals** during a run, **the commit
gate** (a reading, not an interruption), and **the ceiling** (never automatic).

**The tier lives in the composer**, beside `+`, where Codex puts it — the session bar carries facts set
once, the composer carries controls for the next instruction.

| Tier | Steps | Commit | Boundary |
|---|---|---|---|
| ✋ **Ask me** | every file edit and command prompts | prompts | linked folder |
| ▶ **Work on its own** — **default** | edits and test runs inside the folder proceed silently; stops for anything outside it and for network installs | **prompts** | linked folder |
| ⚡ **Let it run** | no step prompts | **commits to the session branch itself** | linked folder |

**Never, at any tier:** merge · deploy · delete · force-push · touch a file outside the linked folder.

- **Default is the permissive middle**, because defaulting to `Ask me` ships the complaint as the
  default.
- **Per-session, not global** — permissive on your own repo, cautious on a client's.
- **Narrower than Codex's top tier on purpose.** Codex separates `sandbox_mode`
  (`read-only` / `workspace-write` / `danger-full-access`) from `approval_policy`
  (`untrusted` / `on-request` / `never` / `granular`), and its top setting drops the sandbox entirely.
  Ours collapses both axes into three named tiers and never leaves the linked folder.
- **Cloud barely needs the setting** — the agent is in a managed sandbox on a branch, and the PR is the
  real gate. This control is about Local.

### 8.3 This amends a written rail

The coding-agent design states Codepet "never writes the real tree without approval". **`Let it run`
softens that by the founder's explicit choice.** Amended:

> Codepet never writes the real tree without approval, **unless the founder has selected `Let it run`
> for this session** — in which case it commits only to the session branch, and the ceiling (no merge,
> deploy, delete, force-push, or write outside the linked folder) still holds absolutely.

---

## 9. First run

**Don't teach the UI; hand them a first win.** Onboarding already takes the brief and scaffolds a
roadmap, so the first screen can be specific instead of welcoming.

1. **The hero is never empty** — the beacon names a real task from the founder's own brief. *Run it*,
   not *Get started*.
2. **The first run is the tutorial** — trial-funded, log shown in full, and it involves a department
   handoff, so within a minute they have met a second character and learned they have a company.
3. **The inspector opens itself, once.**
4. **One sentence per first occurrence** — the first gold card, the first room offer, the first commit
   each get one line, then never again. **No modal tour**; guidance is in-context, which is already the
   rule.
5. **Developer stays dormant** until it has a repo: one honest offer to link a folder or connect a repo,
   and it refuses to pretend a run happened without one.
6. **Empty states carry the instruction** — "Your conversations appear here."

### 9.1 Orientation — what the first screen must answer

The empty state has to answer three questions with content, not chrome: *what is my company, what is my
project, what happens next.*

- **The brief, mirrored back, and correctable** — *"Codepet — a macOS AI companion for solo founders.
  Launching 28 Aug. 5 tasks on your roadmap"* with a `not right?` link. Every department reads the brief
  before it answers, so a misunderstanding here poisons everything downstream.
- **The cast** — the roster from §4, each chip starting a scoped conversation.
- **The beacon's provenance** — `Step 1 of 5 · Positioning · see the roadmap`.
- **The loop, before it runs** — *"Marketing drafts it → you review → it is filed in Library. ~3
  credits."* One line that teaches the product.
- **The switch, named** — "Ask talks to your company. Developer touches your code," retired once
  Developer has been used.
- **What a credit buys** — "a chat ~0.25 · a task ~3 · a room ~10", first run only.

### 9.2 Two openings, one still open

| | Task waiting | First task already ran |
|---|---|---|
| What they see | byte, and one named task | a finished draft, inspector already open |
| Spent on arrival | **nothing** | **3 credits** of the trial, unasked |
| First impression | "it understood my brief" | "it already did the work" |
| Risk | they still have to press something | spending someone's money unasked, and being wrong in public |

**Recommendation: task waiting** — a founder's first experience of Codepet spending their money should
be a decision they made. Worth A/B-ing at launch rather than arguing about now.

---

## 10. Data model

**One thread collection, one new field.** `ChatThread` gains `kind: ask | dev`. Ask's `RECENT` and
Developer's `SESSIONS` are two filters over `companies/{uid}/threads/{id}` — whose deployed Firestore
rules already cover this, so **no rules change ships with this design**.

A `kind: dev` thread additionally carries:

| Field | Meaning |
|---|---|
| `backend` | `local` \| `cloud` |
| `repoRef` | a local folder path (client-only, never uploaded) or a remote `owner/name` |
| `baseBranch` / `workBranch` | `main` → `codepet/fix-signup` |
| `approvalTier` | `askMe` \| `worksOnItsOwn` \| `letItRun`, default `worksOnItsOwn` |
| `runState` | the shared lifecycle value |

Both kinds carry `inspectorTabs: [{ id, kind, title }]` and `activeTab`, so a conversation restores what
it had open. `WorkspaceMode { ask, developer }` replaces `ChatMode`, persists per account under a `cp_`
key, and is restored on launch. First-run state is account-scoped (`introSeenAt` already exists) and must
include *which* first-occurrence hints have been shown, so they never repeat.

---

## 11. What retires, and what replaces it

| Retires | Becomes |
|---|---|
| `TopNavView` and the docked copilot column | `SidebarView` + conversation + inspector |
| `ChatMode` and its `ask / plan / build` pill | `WorkspaceMode` + the `convene` verb |
| Second Brain as a destination | `Company → Departments │ Learn` |
| per-message "Developer" intent | a per-session `Local │ Cloud` chip |
| a full-pane deliverable viewer | an **inspector tab** |
| Developer's file-tree column | a **Files** tab, read-only |
| department nameplates in the room | the **cast** — pets speak (§4) |

`SidebarView` is not new work from zero: it exists on `origin/feat/chat-redesign` (tip `c19715a`,
deliberately kept as a cherry-pick source) with the brand row, `+ New`, grouped Recent, the Workspace
nav, Upgrade and the account row already built.

**Tests are rewritten, not deleted.** `RoomGatingTests` and `ChatModeEngineeringTests` encode decisions
that survive this change — the room needs permission; there must be one door to the coding agent. Repoint
them at `WorkspaceMode` and the `convene` verb, and they must still go red if those guards are removed.

---

## 12. Testing

Unit-testable without the app host wherever possible, because the XCTest host on Xcode 26.2 crashes when
a `@MainActor ObservableObject` deallocates (~27 tests never finish; run per-suite with `-only-testing:`).

- **Mode**: `WorkspaceMode` persists and restores; the sidebar's mode-specific groups are mutually
  exclusive — a test that fails if both `RECENT` and `SESSIONS` can be visible at once.
- **Convene**: an offer appears only when a room is warranted and permission is absent; tapping
  `Convene` is the only path that sets `convenesRoom: true`.
- **Tiers**: for each tier, the exact allowed action set.
- **The ceiling**: merge, deploy, delete, force-push and any write outside the folder are refused **at
  every tier, including `letItRun`** — and per the working agreement, this guard gets a test that goes
  red if the guard is deleted.
- **Backend agnosticism**: the same exec-log and diff views render from a Local run and a Cloud run.
- **Inspector**: opening a draft does not destroy the conversation; a second output opens a second tab;
  tabs restore per thread.
- **Layout, asserted.** The prototype carries three layout assertions — the composer, the beacon's
  primary button and the deliverable's footer must each be fully inside their container. Two real
  clipping bugs shipped before those existed, both caused by a CSS grid with an **auto row** refusing to
  shrink below its content (`grid-template-rows: minmax(0, 1fr)` is the fix). The SwiftUI equivalent is
  worth an `ImageRenderer` test, since layout is measurable offscreen even when screenshots are not
  available.
- **A first-hour end-to-end test.** The prototype plays its whole story and asserts each beat's outcome:
  draft → tab → filed → capability → captured → offer → room → verdict → decision → dev → diff →
  committed. This is the test that catches a UI which *narrates* an approval it never performed.
  **Two lessons worth carrying into the Swift suite:** wait on outcomes rather than fixed delays (a
  backgrounded frame gets its timers throttled, which looked exactly like a logic failure), and print a
  trace of what was reached, so a failure names the beat instead of only the total.

---

## 13. Open decisions

1. **Overview's fate — the founder's call, still unresolved.** The living progress dashboard, the
   centre-framed company map, the project briefing and the first-run spotlight all ship on `main`, and
   this shape has no slot for them. Either (a) Overview retires and the Ask hero plus the beacon carry
   "where am I," or (b) the Codepet wordmark clicks through to it as the one page above the five.
   **Recommendation: (b)** — one route, zero sidebar space, and (a) deletes shipped work to solve a
   problem we have not measured.
2. **Product's voice** (§4) — cast `null → Product` and draw it, or drop Product as a department.
   Now launch-blocking.
3. **The credit price of a convened room, and the trial amount.** Both belong to the pricing spec.
4. **The dependency warning** (§6) — proposed, not decided.
5. **Whether the Developer composer's right side gets a model / effort control**, as Codex has. Under
   our pricing that is a credit-priced choice, not a free toggle.

## 14. Non-goals for v1

- Hand-editing code inside Codepet.
- Any access outside the linked folder, at any tier — including network installs without a prompt.
- Unattended merge, deploy or delete. The ceiling is not negotiable by a setting.
- Rebuilding the Virtual Company room UI. Only its *entry point* and its *casting* change.
- New Firestore rules. If the implementation needs them, a premise in §10 is wrong.
- Multi-user anything (§2.1).
