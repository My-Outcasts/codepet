# Two-Tier Memory — Design

**Date:** 2026-08-21
**Status:** Approved design → ready for implementation plan
**Branch:** `feat/two-tier-memory` (to be cut off `main`)
**Target:** `main`
**Prototypes:** an engineering prototype (all eight levers, real token math) and a plain-language explainer were built and reviewed before this document. Neither ships; both informed every number below.
**Revised:** 2026-08-22. Reading the code to write the implementation plan turned up two errors in the first draft, both corrected below and both noted where they were wrong: the prerequisite in §5.2 was already built under a different name, and the scope key in §4.1 was machine-specific, which would have orphaned every repo-tier fact on a second machine.

---

## 1. Goal

The founder's team should stop bringing up facts from a repo the founder is not working in, and should stop forgetting a repo it has not seen in a while.

Codepet already has memory. `companies/{uid}.decisions` holds the facts the team was told, `PetMemory` holds derived coding activity per project path, `CompanyBrief` holds the brief, `FounderPrefs` holds how the team should talk. What is missing is a **second tier** and a way to put each fact in the right one.

This is not new memory. It is a scope on memory that already exists.

## 2. The model, and why it settles the schema

**One founder = one company = many repos.** Confirmed with the founder on 2026-08-21.

That makes the shared tier already correct and already synced: `companies/{uid}`. All the work is in the repo tier, which today is `ProjectStore` writing `cp_detected_projects` into UserDefaults — local only, so a new machine starts empty while the company tier follows the founder across machines.

## 3. Non-goals (v1)

- **Per-repo skill overrides.** `CompanyState.enabledTools` stays one `Set<String>` for the account. With two or three repos the override buys almost nothing, and it adds a block to every prompt.
- **Relevance-ranked eviction.** `ChatContext.selectPriorWork` already ranks deliverables by token overlap and the same mechanism would work on facts, but at the budgets in §7 eviction is rare. Recency stays until a tier actually overflows in the wild.
- **Inferring scope from a deliverable's `dept`.** See §5 — dropped on purpose, not deferred.
- **Attaching a repo to `Deliverable`/`RoadmapTask` at creation.** The correct fix for the `dept` signal's flaw, and unnecessary once that signal is dropped. It touches the roadmap, not memory.
- **Re-keying the derived tier.** `PetMemory` is keyed by project path, which carries the same machine-specificity §4.1 rejects for `scope` — but it lives in UserDefaults and counts session activity on *this* machine, so a machine-local key is the correct one there. It needs nothing.
- **Scoping `CompanyBrief` or `FounderPrefs`.** The brief describes the company and the style describes the founder. Both are shared by nature.

## 4. Data model

### 4.1 `DecisionEntry` gains a scope

```swift
struct DecisionEntry: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
    var updatedAt: Double?
    var scope: String?      // NEW. nil = shared; otherwise a project id (see §4.3).
}
```

**A project id, never a path.** The first draft of this document said "a project path" and it was wrong. An absolute path is machine-specific: the same repo sits at `/Users/a/work/codepet` on one machine and `/Users/b/src/codepet` on another, so a path-keyed scope orphans every repo-tier fact the moment the founder opens their other laptop — silently, which is the exact failure class this design exists to remove. §4.3 defines the identity.

**`nil` means shared, and that is the whole migration story.** Every document already in `companies/{uid}` decodes with `scope == nil`, lands in the shared tier, and behaves exactly as it does today. There is no backfill, no version flag, and no window where a founder's facts are half-migrated.

Decoding follows the pattern `FounderPrefs.init(from:)` established: a hand-written `init(from:)` using `decodeIfPresent`, because Swift's synthesised decoder throws `keyNotFound` on an absent key instead of falling back to the property's default.

`Decisions.identityKey(_:)` stays keyed on the lowercased `topic` alone. Scope is **not** part of a fact's identity: a fact that moves from shared to repo-scoped is the same fact, and `mergeDecisions` must supersede it rather than keep two copies. A merge on an existing topic preserves the stored `scope` unless the incoming entry carries one.

### 4.2 The repo tier gets a home that survives a new machine

`ProjectStore` gains a Firestore mirror at `companies/{uid}/projects/{id}`, holding the fields that are the founder's rather than the machine's: `displayName`, `brief`, `companyBrief`, `stage`, `attestations`, plus the identity hints in §4.3.

Keyed on the minted id. A hash of the path would have been just as machine-specific as the path, which would have defeated the point of syncing at all — sync is worthless if the key that finds the document only exists on one machine.

Machine-local fields — `firstSeenAt`, `lastSeenAt`, `sessionToRoot`, `manualOverrides`, and the local path itself — stay in UserDefaults. They describe this machine and mean nothing on another one.

**This ships with §4.1, not after it.** A repo-scoped fact whose repo tier lives only in UserDefaults is a fact that disappears when the founder opens their laptop instead of their desktop, while the shared tier follows them. Shipping the scope without the sync would create exactly the silent-loss failure this design exists to remove.

### 4.3 Project identity

A project gets an id once, minted by Codepet, and it is that id forever. The id is what `scope` stores and what the cloud document is keyed on. It is opaque — no path, no name, nothing derived from the machine.

Each machine keeps its own map from local path to id, in UserDefaults alongside the security-scoped bookmark `linkProject` already writes. Two founders' machines can hold the same project at different paths and reach the same facts.

The cloud document also stores **matching hints**, so a folder linked on a second machine can be recognised rather than re-minted:

- `gitRemote` — `git remote get-url origin`, when the folder is a git repo with a remote. `GitRunner.run(_:in:)` is already generic, so this needs no new plumbing, and `ProjectLink.isGitRepo` already says when to try.
- `folderName` — the last path component. Weak, and only ever a hint.

When the founder links a folder with no local id, Codepet looks for a cloud project whose `gitRemote` matches. A match is **proposed, not applied**: the founder confirms "this is the same project" or asks for a new one. That is the same propose-and-confirm rule §5.5 applies to a fact's scope, for the same reason — guessing wrong here silently attaches one repo's memory to another.

No git remote and no confirmation means a new id. A duplicate project is visible and mergeable; a wrongly-merged one quietly mixes two repos' facts.

## 5. Detection: which tier a new fact belongs to

### 5.1 Where facts are born

Three paths, all in `CompanyStore`, none of which has a repo in hand today:

| Path | Origin | `source` |
|---|---|---|
| `handleRemember` | the `remember` tool fires mid-chat | `"chat"` |
| `rememberFromApproval` | founder approves a deliverable → `extractDecisions` CF | deliverable |
| `lockInVirtualCompanyDecision` | founder locks in a room's recommendation | run |

### 5.2 Which repo is open — already answered, under another name

The first draft of this section said the chat lane had no repo and named `ProjectStore.activeProjectPath` as the thing to wire. Half right: memory does not use a repo today, but the chat lane already has one, and it is not that property.

`CompanyStore.activeProjectLink: ProjectLink?` already exists. `linkProject(path:bootstrapClaudeMd:)` sets it, it is cleared on sign-out (`CompanyStore.reset()`), four views read it, and it carries `path`, `isGitRepo` and `hasClaudeMd`.

**Corrected 2026-08-22, during the PR 1 fix wave: it does NOT survive relaunch.** This section originally said the link survives relaunch as a security-scoped bookmark under `cp_active_project_bookmark`. `linkProject` does write that bookmark (`URL.bookmarkData(options: [.withSecurityScope], …)`), but nothing in the repo ever resolves it — `grep -rn resolvingBookmarkData codepet/` returns nothing. So `activeProjectLink`, and therefore `activeProjectId`, is `nil` at every cold start until the founder re-links the folder by hand. See **PR 2 preconditions** below for the consequence this has for repo-tier scoping.

It is also the better anchor of the two, and they are different things:

| | What it is | Lane |
|---|---|---|
| `activeProjectLink` | the folder the founder **deliberately linked** | chat, coding |
| `activeProjectPath` | **inferred** from `cwd` in session logs | reflection |

Memory scope keys on the deliberate one. An inferred repo is a guess about what the founder is doing; a linked folder is a statement.

So the prerequisite is not wiring — it is **identity**: resolving `activeProjectLink.path` to a project id per §4.3. That is what ships first, and every signal below is gated on it. `hasClaudeMd` also means §6.1 already has the probe it needs.

### PR 2 preconditions

Added 2026-08-22, during the PR 1 fix wave. Two hard requirements PR 2 must satisfy before it ships, both surfaced by reviewing what PR 1 actually built rather than what this document assumed:

- **A founder-facing affordance for `pendingProjectMatch` must exist before `knownCloudProjects` is ever populated.** PR 1 ships with `knownCloudProjects` always empty, so `ProjectIdentity.match` can only ever return `.mint` in production — the `.propose` branch is exercised by tests only. The moment PR 2's cloud sync starts filling that list, `.propose` becomes reachable for real founders. A proposal with no way to answer it leaves `pendingProjectMatch` set and `activeProjectId` permanently `nil` — the founder's memory for that repo silently stops scoping, with no error and nothing on screen explaining why. The affordance (confirm/reject UI) has to land no later than the cloud sync that makes it necessary, not after.
- **The security-scoped bookmark must be resolved on launch, or the repo tier is empty every cold start.** Per the correction in §5.2, `linkProject` writes `cp_active_project_bookmark` and nothing reads it back — `activeProjectLink` and `activeProjectId` are both `nil` until the founder re-links by hand. Every design decision in §6 through §8 about what reaches a prompt assumes a repo can BE open; if the bookmark is never resolved, the repo tier this whole PR exists to enable is vacant at the start of every session, and a founder who has not yet re-linked gets shared-tier-only behaviour indistinguishable from the feature not existing.

### 5.3 The signals, and the one that was dropped

**Origin — free, deterministic.** A Virtual Company room argues company strategy. It is never about one repo, and the creation path alone says so. No inference.

**LLM scope — near-free.** `extractDecisions` already calls the model and already returns `{topic, statement, source}`. It gains a `scope` field in its output schema and the request gains the founder's repo list. Marginal cost is a few output tokens on a call that already happens. Covers the approval path.

**Token overlap — free, already tested.** `ChatContext.tokenize` and `overlap` exist, are pure, and have tests. Score the statement against each repo's signals — its name, its tech, file names from `ProjectScanner.scanProject` — and require **at least two matching tokens**. One shared word is noise. Covers all three paths.

**Dropped: the deliverable's `dept`.** It looks free, and it is not. `dept` carries no repo, so the signal can only ever assign the fact to whichever repo happens to be open. Approve an `engineering` deliverable belonging to codepet while MurrorMobile is open and the fact is scoped to the wrong repo — the failure mode §5.4 calls unrecoverable. It also covers only the approval path, where the LLM signal already sees the whole deliverable and does the job better. A signal that is dominated on its own path and is the sole source of the worst failure does not earn a place.

### 5.4 The rule everything else follows from

The two ways of guessing wrong are not symmetric.

- **Called shared, actually repo-scoped.** The fact is surplus in other repos' prompts. Wasteful, and *visible* — the founder can see a stray fact in the memory panel.
- **Called repo, actually shared.** The fact silently stops applying everywhere else. "Never commit straight to main" quietly ceases to hold, and nothing says so.

Therefore: **when signals disagree, or when no signal speaks, the fact is shared.** Shared is also today's behaviour, so the fallback is never a regression. This mirrors `DecisionsClient`'s existing convention — `FAIL-OPEN: any error → []`.

Signals pointing at two *different* repos is also disagreement, and also falls back to shared.

### 5.5 Propose, then confirm

Detection never writes a scope silently. It proposes, and the founder confirms or corrects.

The affordance exists: `handleRemember` already appends a `📌 Noted` chip carrying a `RememberedFact`, keyed for idempotency on `messageId`. The chip gains a scope control with the proposal pre-selected. An untouched chip keeps the proposal; one tap corrects it.

## 6. What reaches a prompt

`ChatContext.compose` gains a project id and composes two decision blocks instead of one:

1. shared-tier facts — `scope == nil`
2. facts scoped to the open repo — `scope == <the open project's id>`

Facts scoped to any other repo are not composed at all.

`Decisions.composeDecisions` keeps its wording and its conflict clause; it is called twice with two lists rather than rewritten. When the repo tier is empty the second block is omitted entirely, the way `composeDepartments` and `composePriorWork` already omit themselves.

`memoryEnabled` still gates both blocks. Memory off means memory off, and that stays provable for each store.

### 6.1 Rules from the repo's `CLAUDE.md`

`ClaudeMdBootstrap` writes a seed `CLAUDE.md` into a freshly-linked repo. This adds the read direction: the file's content becomes a repo-tier grounding block.

Bounded, because the file is not ours: at most the first 2 000 characters and only from a file the founder has linked. It is read-only — Codepet never edits a `CLAUDE.md` it did not create, and never clobbers one that already exists, which is the rule `ClaudeMdBootstrap` already follows.

Ships after §4 and §5, in its own PR.

## 7. Budget: what happens when memory outgrows the prompt

`Decisions.MAX_DECISIONS = 30` is one cap over the whole list, evicting by `updatedAt` and dropping in silence.

Add a repo tier under that cap and a busy repo starves the others. Measured on the prototype's 14-fact fixture — codepet facts one to five days old, MurrorMobile's two months old, one shared cap of seven — **seven facts were evicted and MurrorMobile lost every fact it had.** Open that repo and its memory is not filtered out, it is gone. A shared rule 40 days old ("never commit straight to main") went with it.

**Per-tier budgets: 18 shared, 12 per repo.**

The prompt never sees more than 18 + 12 = 30 facts, which is exactly what it sees today — **so this change costs zero prompt tokens** while total storage becomes 18 + 12×N. The reasoning is the one `AIStyle` already documents: bounding each field rather than the join, because a cap on the total removes whichever part the founder did not get to choose.

Selection inside a tier stays recency, per §3.

### 7.1 Eviction says so

`normalizeDecisions` currently just `prefix(max)`. It gains a way to report what it dropped, and the Memory panel says so. A cap that truncates in silence reads as "everything is here" when it is not — the same care `MemoryDigest.codingActivityLine` takes in refusing to report "0 sessions" as a fact.

## 8. The statement ceiling

Nothing bounds a `statement`'s length today. The budget in §7 counts facts, so one 3 000-character statement passes every check. This is the same class of hole as the branch's own `feat(run): bound the deliverable's length — the one field that had no ceiling`.

**Reject at 280 characters.** Over the ceiling, the fact is not stored, and the founder is told.

Clipping was considered and rejected. Ported faithfully, `AIStyle.bounded` truncates on whole graphemes but knows nothing about words, and on the prototype's fixture at an 80-character ceiling, **four statements were over and three came out saying something else.** The worst read:

> "Codepet is a macOS app where a founder runs their company with an AI team, not a…"

The `not` survived; what it negated did not. That is correct behaviour for `customInstructions`, where the tail is advice and losing it costs tone. It is wrong for a fact, where the tail is often the whole point — and a clipped fact still looks like a perfectly good fact.

Restating the fact through the model was also considered — the `BriefContext` pattern, where a distilled `summary` *replaces* the long text rather than being appended. It preserves meaning and costs a call. Held back because rejection is both cheaper and safer, and because a 280-character ceiling makes the case rare. If rejection turns out to annoy founders in practice, that is the evidence for adding restatement.

280 rather than a rounder number: a decision is one sentence, and every statement in the prototype's fixture — drawn from this repo's real `CLAUDE.md` and memory files — fits inside it with room to spare.

## 9. Shipping order

Each step is a PR that stands on its own and leaves the app correct.

1. **Project identity.** §4.3 — mint an id for a linked folder, keep the local path→id map, read `gitRemote` as a hint, and match-with-confirmation on a machine that has no id yet. No change to memory at all, and it is the one thing everything else stands on.
2. **`DecisionEntry.scope` + `ProjectStore` sync + two-block grounding.** §4.1, §4.2, §5, §6. One PR, because §4.2 explains why they cannot be split.
3. **Per-tier budget + eviction notice.** §7.
4. **The statement ceiling.** §8.
5. **Rules from `CLAUDE.md`.** §6.1.

## 10. Testing

Every guard here needs a test that goes red when the guard is deleted. The pure types make that cheap — `Decisions`, `ChatContext`, `MemoryDigest` and the new scope logic are all pure and none of them need a store.

- The same project resolves to the same id from two different local paths. This is the test that fails if identity ever goes back to being path-derived.
- A folder with no local id and a matching `gitRemote` is **proposed**, not silently adopted. Delete the confirmation and this goes red.
- A folder with no git remote and no confirmation mints a new id rather than joining an existing project.
- A fact scoped to repo A is **absent** from repo B's composed context. Delete the scope filter and this goes red.
- A `scope == nil` fact reaches every repo. This is the no-migration guarantee, and it is the test that fails if `nil` ever stops meaning shared.
- A document encoded before `scope` existed decodes with `scope == nil`.
- Disagreeing signals resolve to shared. Two repo-signals naming different repos also resolve to shared.
- No signal, or no open repo, resolves to shared.
- A statement of 281 characters is rejected; 280 is stored.
- Eviction reports what it dropped. Remove the report and this goes red.
- `memoryEnabled == false` composes **neither** decision block.

Run per-suite with `-only-testing:`. The XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates, so a whole-target run exits 65 on a clean checkout and says nothing about this work.

## 11. Open items

- **The 280 ceiling is a judgement, not a measurement.** Nobody has looked at the length distribution of real founder decisions. Worth checking against live data before treating the number as settled.
- **`ProjectScanner`'s output as repo signals.** §5.3 assumes the scan yields usable tokens — dependency names, file names. That needs confirming against a real scan before the token signal is tuned.
- **Whether rejection is tolerable.** §8 bets that a founder shortens a rejected fact rather than giving up on it. If they give up, the fact is lost and nobody notices, which would be the same class of failure this design set out to remove.
- **`gitRemote` as a matching hint is untested against real cases.** A fork, a repo whose remote was re-pointed, and two clones of the same upstream all break it in different directions. The confirmation step in §4.3 is what keeps a bad match from being silent, but nobody has checked how often the hint is simply absent.
- **Nothing migrates a founder who links the same folder twice** before the id map exists. There should be no such founder — the id ships before scope does — but the ordering is the only thing preventing it, and orderings slip.
