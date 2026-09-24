# Revisions update the work they revise — they don't mint new tasks and Library entries

**Status:** spec, not built · **Found:** 24 Sep 2026, testing prod build 3 (`v1.0-build3`) · **Owner:** Mona
**Still true on main** at `0d73cf0` — neither `CompanyStore.swift` nor `companyChatCore.ts` changed since build 3.

## The problem

The founder asked Codepet to redesign the landing page, then asked for several revisions of it.
Every revision ended up as its own roadmap task **and** its own Library entry:

- **Roadmap** — "Redesign the landing page for higher waitl…" (Done), "Rework landing page with
  editorial type s…" (Done), "Rework landing page in the joinswsh.com…" (Review).
- **Library** — four separate `Site` items for the same page: *Codepet Landing Page — Second Pass
  (Editorial Type Scale)*, *Codepet Landing Page — Hero, Proof, Single CTA*, *Codepet Waitlist Page
  Copy*, *Private Beta Waitlist — One-Page Site Copy*.

At 10–20 revisions that is 10–20 tasks and 10–20 near-identical Library items. The roadmap stops
describing the company's progress (one piece of work reads as many finished steps, and inflates
Project Progress), and the Library stops answering "what is the current landing page?"

Nothing is fully automatic — each task needs a press of the add-to-roadmap offer, and each Library
entry needs a press of Approve. But the product offers both on every revision, and there is no
path that does the right thing, so a founder who accepts what they are offered gets the pile-up.

## Why it happens (three causes, all needed for the bug)

1. **The chat model cannot see finished work.** The chat prompt lists only `OPEN TASKS` and
   `RUNNABLE TASKS` (`companyChatCore.ts:827`). A done task and the Library are invisible to it, so
   `add_task`'s own rule — *"Do NOT call this for work already on the roadmap"*
   (`companyChatCore.ts:742`) — cannot be followed: to the model, "make it more editorial" is new
   work.
2. **The add-task guard only dedupes offers, not tasks.** `handleRoadmapProposal`
   (`CompanyStore.swift:2746`) refuses a second *identical, unanswered offer in the chat*. It never
   compares against tasks already on the roadmap, and titles differ per revision anyway
   ("Redesign…" / "Rework…").
3. **Approve always appends.** `fileApproval` (`CompanyStore.swift:2943`) does
   `company.library.append(draft)`. A `Deliverable` (`Deliverable.swift:293`) has an `id`, `title`,
   `body`, `sourceTaskId` — no notion of being a newer version of another item.

**What already works, and must keep working:** revising a draft *before* approving it. The revise
chips call `redoDraft(reviseNote:)` (`CompanyStore.swift:3008`), and the server revises in place
(`runTaskCore.ts:154-160`, `reviseNote` + `current`). No new task, no new Library entry. The gap
is only *after* approval.

## What we want

- A revision of approved work produces **a new version of the same Library item**, not a new item.
- It **adds no roadmap task** and does not re-open or re-complete the original one.
- The previous versions are **kept, not lost** — the founder can see and restore them.
- Genuinely new work (a pricing page, a second landing page for another product) still goes
  through `add_task` exactly as today.

## Design

### 1. Tell the model what's already been delivered — server (`companyChatCore.ts`)

Add a `DELIVERED WORK` block beside `OPEN TASKS`: the most recent Library items, each as
`- <library_id> · <kind> · <title> (from task <task_id>)`. Capped (≈15 newest) so the prompt stays
small; it sits in the uncached tail, not the cached prefix.

Tighten `add_task`'s description: do not call it for another pass, rework, redesign or revision of
anything in `DELIVERED WORK` — call `revise_work` instead.

### 2. A `revise_work` verb — server + native

New chat tool:

```
revise_work { library_id: string, note: string }
```

"Offer to produce a new version of something the founder already approved, when they ask to
change, rework, redo or take another pass at it." `library_id` must come from `DELIVERED WORK`;
ambiguous → ask a one-line question, same rule as `run_task`.

Native (`handleDoneAction` → new `handleReviseWork`): like the existing proposals, it **attaches an
offer to the reply** ("Make a new version of *Codepet Landing Page*?") — never runs on its own,
because a revise costs credits. On press, it runs the item's source task through the existing
revise path (`reviseNote` = the note, `current` = the Library item's body) and shows the result as
a normal draft card, carrying `supersedes = <library_id>`.

### 3. Approve a revision = replace in place, keep history — native (`fileApproval`)

`Deliverable` gains two optional fields (both absent on every existing item, so no migration):

- `supersedes: String?` — on a draft, the Library item it will replace.
- `versions: [DeliverableVersion]?` — on a Library item, earlier bodies, newest first:
  `{ body, title, createdAt }`. Capped at 20; oldest dropped.

`fileApproval` branches on `draft.supersedes`:

- **Found in the Library** → move the current body/title into `versions`, write the draft's body/
  title/createdAt into the **same item (same `id`)**, persist. No task write — the source task is
  already done and stays done.
- **Not found** (item deleted meanwhile) → fall back to today's append. Never drop an approval.
- **nil** → today's behaviour, unchanged.

### 4. Library UI

- The item shows **`v4`** beside its kind chip when `versions` is non-empty, and its date is the
  newest version's.
- The detail sheet gets a **Versions** disclosure listing earlier versions (date + first line);
  opening one previews it, with **Restore this version** — which is itself a replace-in-place, so
  the current body goes into history rather than being lost.

*UI details to be confirmed with the founder before building (standing rule: discuss UI first).*

## Out of scope

- **Merging the duplicates already in accounts.** Existing items stay as they are; the fix stops
  new pile-up. A manual "merge into…" action can follow if wanted.
- Versioning for non-Library surfaces (message drafts, decisions).
- Changing the pre-approval revise chips — they already do the right thing.

## Tests (test-first, each must be seen failing before the fix)

1. `fileApproval` with `supersedes` of an existing item: library **count unchanged**, same `id`,
   new body, old body at `versions[0]`, no task mutation.
2. `supersedes` pointing at a missing item → appended (count +1), approval not dropped.
3. `supersedes` nil → today's behaviour (count +1) — guards against the branch leaking.
4. History cap: 21st revision keeps 20 versions, drops the oldest.
5. `Deliverable` decodes an existing item with neither field (back-compat), and round-trips both.
6. Restore: current body moves to `versions`, restored body becomes current, count unchanged.
7. `handleReviseWork` attaches exactly one offer; a second identical unanswered offer is refused
   (same guard shape as `handleRoadmapProposal`); pressing consumes it before the run (no double
   credit spend on a double-press).
8. Server: the prompt contains `DELIVERED WORK` with the capped list; `add_task` description names
   `revise_work`; a `revise_work` tool use parses into the done frame with `library_id` + `note`.
9. **End-to-end in the running app** (not just unit tests): approve a landing page, ask "make it
   more editorial", accept, approve → Roadmap task count unchanged, Library count unchanged, item
   shows `v2`.

## Rollout

Server and native ship together: an old app receiving `revise_work` ignores the unknown action
(the done-frame decoder skips unknown keys — verify this before shipping), so the server change is
safe to deploy first, but the add-task tightening means an old app would get *neither* an add nor a
revise offer on a revision. Deploy functions and release the app in the same window, or gate the
tightening on the client's build number.
