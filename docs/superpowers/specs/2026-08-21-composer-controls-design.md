# Codepet — composer controls: a departments button and a real `+` menu

**Status:** designed, approved by the founder 21 Aug 2026. Amended the same day to bring attachments
and the web-search toggle into scope (§7), which slips the code freeze — founder's call, made with the
cost stated. Not built.
**Branch:** `feat/composer-controls`, off `feat/two-mode-shell` — the composer this changes lives there,
not on `main`.
**Scope:** Swift **and** `functions/` (§7.3, §7.5). Measured: `functions/` on this branch is 0 commits
behind `origin/main`, so the deploy-from-a-stale-branch hazard does not bite today — re-measure before
deploying anyway.
**Amends:** `2026-08-17-codepet-two-mode-product-design.md` §4 (the cast) and §8.2 (the tier lives in the
composer). It does not amend the SSE contract.

---

## 1. Why this exists

The control row under the composer had four controls doing three jobs, and one of them changed shape
depending on what was selected:

```
[Engineering] [Design] [Marketing]  [＋]  [◔ Ask me ▾]                        (↑)
   three chips (two in the 380pt dock) + a ••• overflow + a promoted chip
```

Three specific costs, all of them already written down in the code that does it:

- **The chip set is not a fixed width.** `deptChips` shows `surface.visibleDeptChips` of the roster, and
  a department armed from the overflow menu is *promoted to its own extra chip* — a patch that exists
  only because a selection made inside a menu was otherwise invisible. So the row is 3 chips, or 4, and
  the founder cannot learn its shape.
- **Eight departments, three doors.** The visible chips, the dock's `•••`, and (on the two-mode surface)
  a `Departments` section inside `+`. `deptOverflowItems` was extracted precisely so two of those three
  could not drift apart, which is the smell, not the fix.
- **`+` was a junk drawer.** It held three prompt starters (`Run a task`, `What should I focus on
  first?`, `Summarize where my company is`) that are *already* cards on the empty hero, plus the room,
  plus the department leftovers. Its own doc comment defends it as "a quick-actions menu (NOT a file
  picker — the app has no attachments)", which is an accurate description of a control with no idea what
  it is for.

The founder supplied Claude's `+` as the reference on 21 Aug. What is worth taking from it is not the row
list — it is that the `+` answers exactly one question: **what does this turn get to see, and how hard
should it work?** Codepet's answer to "what does it see" is not files. It is the company: the Library,
the roadmap, what Codepet knows, the linked repo.

## 2. What was decided, and by whom

Founder, 21 Aug 2026, in order:

| # | Decision |
|---|---|
| 1 | Departments collapse into **one separate button**, not a chip row and not a section inside `+` |
| 2 | At rest it reads `Departments ▾`; **armed, it becomes the chip** — pet sprite, `crash · Engineering`, department accent, and a `✕` |
| 3 | The picker is a **native menu of cast-signed rows**, one flat list, not a popover grid |
| 4 | `+` is organised as **bring something in / go deeper**, with Toolkit management as a single footer link |
| 5 | ~~`📎 Attach` and `🌐 Web search` are **omitted, not greyed** — they ship as their own PRs after launch~~ — **SUPERSEDED by decision 7** |
| 6 | `🧠 What Codepet knows` is a **toggle over the boolean that already gates memory**, not the fact-picker the mockup drew (raised as a correction before approval; see §5) |
| 7 | **Both come into scope and the freeze slips** — decided later the same day, after the menu was compared against ChatGPT's and Claude's, which both lead with a file row. See §7 |
| 8 | **Every row carries a description line**, ChatGPT-style rather than Claude's bare labels. See §7.7 |

**Why decision 5 was right when made, and why 7 overrides it.** Decision 5 departed from this branch's
own `ApprovalTier.isHonoured` precedent — list every option, disable the unhonoured one with its reason —
and the departure was correct: a founder who wrongly believes a run will prompt her before acting faces a
safety failure, so the tier must show its gap, whereas a missing paperclip only *looks* unfinished.

Decision 7 does not overturn that reasoning. It removes the premise. Greying a row you cannot honour and
building the row are different answers to "we can't do this yet", and the founder chose the second once
the deferral's real cost was visible: the one door both competitors put first, absent from ours. The
freeze cost was stated before the decision, not after.

## 3. What retires

| Retires | Why |
|---|---|
| `ChatComposer.deptChips` — both surfaces | Replaced by one control |
| `ChatSurface.visibleDeptChips` and its two assertions in `TwoModeHeroTests` | No chip count left to configure |
| The `overflowSelected` promotion branch | It existed because a menu selection was invisible. An armed *button* is visible |
| The dock's `•••` menu | Same control, same reason |
| `quickActions` inside `+` | Unchanged as hero cards. `+` was their second home, and `CopilotChatView` keeps building them for the hero |
| The `Departments` section inside `+` | Becomes decision 1 |

**Explicitly kept.** `DepartmentRoster` on the empty hero — two-mode §4 puts the cast on the first
screen, and that is where the founder *learns* the eight; the composer button is where she *picks* one.
Also kept: the approval-tier pill, the dock's mode pill (`ChatSurface.showsModePill`), and the dock's
active-project chip, which moves onto its own row now that the chip row it shared is gone.

## 4. The departments control

One capsule, **two hit targets** — `HStack { Menu(…); Button(✕) }` sharing a single background — because
the approved shape has a `✕` and a `✕` that only decorates is worse than none.

| State | Reads | Treatment |
|---|---|---|
| Rest | `Departments ▾` | `CodepetTokens.cardEdge` border, no fill, **no `✕`** |
| Armed | `CharacterImage(pet, 16)` + `crash · Engineering` + `✕` | `dep.accent.opacity(0.15)` fill, `dep.accent` border |

The armed treatment is the *existing* chip's treatment, unchanged. This is one control moved, not a new
one, and two treatments would read as two features.

Menu contents, in `DepartmentCatalog.roster` order (8 rows — `product` is filtered out of the roster and
stays out; it has no pet and placeholder art, which two-mode §4 already calls a launch blocker):

```
◍  Anyone — byte routes it          ✓ when selectedDept == nil
────────────────────────────────
🐾 crash  · Engineering
🐾 luna   · Design
🐾 nova   · Marketing
🐾 nova   · Sales
🐾 sage   · Support
🐾 sage   · Finance
🐾 glitch · Operations
🐾 glitch · Legal
```

Three notes on the rows:

- **The pet name leads, then the department.** Same order the reply is signed in
  (`CopilotChatView.headerName` renders `Nova · Marketing`), and the same order `DepartmentRoster`
  already uses. The chip, the menu row, and the answer read alike.
- **The repeats are shown, not hidden.** Three pets cover six departments. Two-mode §4 decided that
  reads as one person wearing two hats, which is what happens in a small company.
- **`Anyone` is the off state made nameable.** Deselecting today means `selectedDept = nil`, which was
  only reachable by clicking the armed chip a second time. It is a real choice — *let byte route it* —
  and it should be a row you can pick, with a checkmark that says it is what you have.

The pet on each row goes through **`DepartmentCompanions.specialistId(for:host:)`** — the same function
`CompanyStore.actingSpecialist` calls on send. That is the invariant `chipPet` protects today and it must
survive the move: the menu can never name a pet the reply then doesn't sign.

**The risk in this section.** macOS menus control their own icon rendering, and `CharacterImage` is
pixel-art (`.interpolation(.none)`) rather than an SF Symbol. Whether the sprite draws at menu-icon size
only settles on screen. **Named fallback: the row degrades to text-only `crash · Engineering`** — still
cast-signed, still the right reading order. It does *not* fall back to a custom popover; that shape was
considered and rejected on 21 Aug for costing its own keyboard and dismiss handling.

Also replaced while here: `deptOverflowItems` renders selection as
`Label(dep.name, systemImage: on ? "checkmark" : "")` — an empty symbol name as a spacer. Two explicit
branches instead.

## 5. The `+` menu

```
BRING SOMETHING IN
  📎  Attach a file or image          ⌘U
      Screenshots, PDFs, notes
  📚  From your Library                ›
      Ground this answer in work you've shipped
  🗺  A roadmap task                   ›
      Pin what you're working on
  🧠  What Codepet knows               ✓
      Let it use your saved decisions
  📁  Linked folder — codepet          ›
      The folder the agent may touch
GO DEEPER
  👥  Convene the room · ~10 credits
      4 departments argue this and hand you a recommendation
  🌐  Web search                       ✓
      Let it look things up as it answers
──────────────────────────────────────
  Set up skills & connectors…                  → Environment
```

Every row carries a second line (§7.7). macOS menus render two-line items; the
description comes from the same `PlusMenu` type as the label, and the room's comes
from the `RoomOffer.detail()` that already exists.

Row by row, and what each one actually reaches:

| Row | Wiring | Note |
|---|---|---|
| `From your Library` | submenu of the 8 most recent `company.library` entries by `createdAt` descending, then `Browse Library…` → `.library` | Pins a deliverable. See §6 |
| `A roadmap task` | submenu of `company.tasks` where `!done`, roadmap order, then `Open Roadmap…` → `.roadmap` | Pins a task. See §6 |
| `What Codepet knows` | **toggles `FounderPrefs.memoryEnabled`** | Already the real gate on the decisions block in `ChatContext.compose` — see `CompanyStore`'s comment, "a fact the founder forgot in the Memory panel must not come back through grounding" |
| `Linked folder — codepet` | submenu: `Change…` → `ProjectLinker.pickAndLink` (`NSOpenPanel`), `Unlink`, `Open Environment` | Names the folder in the label. In the dock this duplicates the project chip; that is fine — the chip is a standing reminder, the row is an action |
| `Convene the room` | `onConveneRoom()`, label from `RoomOffer.label(lang)`, help from `RoomOffer.detail(lang)`, disabled per `RoomOffer.canConvene(draft:)` \|\| `isBusy` | **Price comes from `RoomOffer.credits = 10`**, never hardcoded in the view. The room is a priced act and the label already says so |
| `Set up skills & connectors…` | `companyStore.select(.environment)` | Codepet's answer to Claude's three separate `Skills` / `Connectors` / `Add plugins` doors. `Toolkit.swift` already has all three categories (`skills`, `connectors`, `agents`) with real `ConnectorAuth`. Turning a connector on mid-sentence is a trip to a settings page; it should look like one |

**Why 🧠 is a toggle and not the picker the mockup showed.** A fact-picker needs a store of individually
selectable facts, which does not exist — the Second Brain is *derived* from company state, and the only
real control over whether it reaches the model is one boolean that already ships. A picker here would be
new machinery in front of an existing switch.

## 6. The data path — `ContextPin`

Everything the `+` brings in funnels through one chokepoint already:

```
ChatContext.compose(brief:tasks:decisions:library:query:focusDepartment:memoryEnabled:)
        → CompanyChatRequest.context   (CompanyStore.sendMessage)
```

So pinning is one new value type, one new parameter, and one new block.

**`ContextPin`** — a pure value type beside `ApprovalTier` and `RoomOffer`:

```swift
enum ContextPin: Identifiable, Equatable {
    case deliverable(id: String, title: String)
    case task(id: String, title: String)
}
```

- **Capped at 3.** Matches `selectPriorWork`'s own `max: 3`, and keeps the pill row to one line at the
  380pt dock width.
- **De-duped by case *and* id.** `.deliverable` and `.task` ids come from different collections and could
  collide; picking the same deliverable twice is a no-op, not two pills.
- **Owned by `CopilotChatView`, cleared on send.** A pin is context for the *next* turn, exactly as the
  approval tier is rope for the *next* instruction (two-mode §8.2). Pins that survived a send would
  silently re-bill the founder for the same grounding on every subsequent message.

**In the composer.** `@Binding var pins: [ContextPin]`, drawn as removable pills *above* the field:

```
 (📚 pricing-page.md  ✕) (🗺 Ship billing  ✕)
 ┌──────────────────────────────────────┐
 │ Ask anything about your company…     │
 └──────────────────────────────────────┘
  [ Departments ▾ ]  [＋]  [◔ Ask me ▾]      (↑)
```

**In the grounding.** `ChatContext.compose(…, pinned: [ContextPin] = [])` gains one section:

> `The founder pinned this for this question — use it directly:`

at a **1200-character body cap**, against the 240 (`excerptCap`) the automatic prior-work block uses. A
choice deserves more room than a guess.

### The trap this creates, and the guard for it

`ChatContext.selectPriorWork` **already** ranks up to 3 Library deliverables into grounding by
token-overlap against the founder's message (`titleWeight` 3, `bodyWeight` 1, over the first 600 chars).
Pin one of those and it lands **twice** — once at 240 characters and once at 1200 — which does not
emphasise it, it teaches the model there are two different documents with the same title.

**`selectPriorWork` must exclude pinned ids.** That is the one real correctness defect in this design and
it gets its own test.

### What this feature honestly is

"From your Library" is **not** a new capability. Relevant prior work already reaches the model on every
turn; this replaces the ranker's guess with the founder's choice, and gives the chosen item more room.
Saying it any other way oversells it.

## 7. Attachments and web search — IN SCOPE (amended 21 Aug)

**Founder call, 21 Aug, after comparing the menu against both ChatGPT's and Claude's.** Both competitors
lead with a file row; Codepet had nothing. The two items this spec originally deferred are now in scope,
and the code freeze slips to accommodate them. The founder was shown the freeze cost and chose this.

Every fact below was verified against the code, not assumed.

### 7.1 The model is better than the deferral assumed

`CHAT_MODEL` in `functions/src/companyChat.ts` is **`claude-sonnet-5`** — not the `claude-haiku-4-5`
that `anthropic.ts` exports as `MODEL` (that one serves other callers). Sonnet 5 changes the calculus:

| | Sonnet 5 |
|---|---|
| Images | **High-resolution tier** — 2576px long edge, up to ~4784 image tokens. The first Sonnet with it |
| PDFs | **600 pages** — the 100-page cap applies only to 200K-context models, and Sonnet 5 is 1M |
| Beta headers | **None.** `image` and `document` base64 blocks are GA |
| Cost | A full-res image ≈ 4784 input tokens ≈ **2–3× an ordinary turn's input** |

So a founder attaching a UI screenshot or a chart gets a real read, not a downgraded one.

### 7.2 Transport: inline base64, downscaled client-side

**The client has no Anthropic key** — deployed functions read it from Secret Manager — so the client can
never call the Files API directly. Every path goes through a function, which collapses the choice to two:
inline base64, or Storage + a Files-API-uploading function.

**Decided: inline base64.** The Swift side reads the file, downscales images to the 2576px tier, and
base64s it into the existing request. No Storage bucket, no new function, no `file_id` lifecycle, no beta
header. The cost lever — how far to downscale — lives entirely client-side and needs no deploy to tune.

Its real cost, stated rather than discovered later: **an inlined image re-uploads on every turn it stays
in history.** Storage + the Files API is the correct long-term answer (upload once, reference by id
forever) and becomes worth building when someone attaches a 40-page PDF and asks ten questions about it.
Until then, history replay is capped (§7.4).

### 7.3 The landmine — `ClaudeMessage.content` is a `string`

This is the defect the whole section turns on. In `functions/src/companyChatCore.ts`:

```ts
export interface ClaudeMessage {
  role: "user" | "assistant";
  content: string;                 // not a content-block array
}
```

and in `buildMessages`, the turn-coalescing step:

```ts
last.content = `${last.content}\n\n${msg.content}`;   // string concatenation
```

Widen `content` to accept blocks without touching that line and it silently produces `"[object Object]"`
— no error, no type complaint at runtime, just a prompt with a corrupted turn in it.

**And the wire DTO has the same shape.** `ChatTurn { role: string; text: string }` carries plain strings,
so an attachment sent on turn 1 is **absent from history on turn 2**: "what's in this screenshot?" works,
and the follow-up "what about the top left?" reaches a model that can no longer see it. A one-shot
attachment is not worth shipping — the second question is the one founders ask.

Three edits, therefore, and all three are required together:

1. `ClaudeMessage.content` widens to `string | ContentBlock[]`
2. coalescing becomes block-aware (concatenate text-to-text; otherwise append blocks)
3. `ChatTurn` gains optional attachments so they replay

### 7.4 What ships

- **Swift:** `ChatAttachment` — a value type beside `ContextPin`, carrying kind, filename, media type,
  and base64 data. Images downscaled to a 2576px long edge before encoding; text files inlined as text
  (no block needed); PDFs sent as `document` blocks.
- **Caps, all stated in the type:** 3 attachments per message (matching `ContextPin.max`), 8MB per file
  before encoding (well inside the 32MB request ceiling), and **history replay capped at the 3 most
  recent turns that carry one** — after that the attachment drops out of the replayed history and the
  transcript says so, rather than silently re-billing it forever.
- **The pills are shared.** An attachment renders in the same removable pill row as a `ContextPin`,
  because to the founder they are the same gesture: *this goes with my next message*.

### 7.5 Web search becomes a real toggle

`companyChatCore.ts` registers `web_search_20260209` and instructs the model to "use it only when" — so
search happens today at the model's discretion with no founder control. The toggle adds a `webSearch`
flag to `CompanyChatRequest` that, when off, **actually strips the tool from the request**. A checkbox
that doesn't change behaviour is worse than no checkbox.

Folded in here rather than deferred because `functions/` is already open for §7.3; it is ~20 lines.

### 7.6 One deploy note, measured

`functions/` on this branch is **0 commits behind `origin/main`** (`git rev-list --count HEAD..origin/main
-- functions/`). The standing rule — a `firebase deploy` uploads the working tree, so deploying from a
branch behind `main` deletes `main`'s functions from prod — still holds and must be re-measured before
any deploy. It simply does not bite today.

### 7.7 Every row gets a description

**Founder call, 21 Aug.** ChatGPT captions every row (`Deep research → Get a detailed report`); Claude
captions none. ChatGPT is right, and this spec has direct evidence: the founder had to ask what
`Convene the room · ~10 credits` meant. `RoomOffer.detail()` already holds the sentence that would have
answered it — *"4 departments argue this question and hand you a recommendation"* — wasted as a hover
tooltip nobody reads before spending 10 credits.

## 8. Testing

| Suite | Asserts |
|---|---|
| `ContextPinTests` | de-dupe by id; cap at 3; cleared after send |
| `ChatContextPinTests` | a pinned deliverable appears **exactly once**, at the 1200 cap; `selectPriorWork` excludes pinned ids; **empty `pinned:` produces byte-identical grounding to today** (the regression guard — this parameter must be additive) |
| `DepartmentMenuTests` | 8 rows in `DepartmentCatalog.roster` order, `product` absent; `Anyone` sets `selectedDept = nil`; each row's pet equals `DepartmentCompanions.specialistId(for:host:)` for that key |
| `ComposerControlRowTests` | `ImageRenderer` at 380pt and at pane width — the row does not wrap and the pill row stays one line at 3 pins |
| `TwoModeHeroTests` | **delete** the two `visibleDeptChips` assertions |

Per the standing rule in `CLAUDE.md`: if a guard has no test that goes red when the guard is deleted, it
is not protecting anything. The pinned-id exclusion in §6 is the guard that most needs one.

## 9. Risks

1. **The sprite in a native menu (§4).** Only settles on screen. Fallback named; no popover.
2. **Verification is a handoff.** Screen Recording is denied in this environment, so layout is measured
   offscreen with `ImageRenderer` and the *look* is confirmed by the founder. A green suite is not a
   screenshot.
3. **Freeze is 22 Aug.** Swift-only keeps this off the `functions/` deploy path, where deploying from a
   branch behind `main` deletes `main`'s functions from prod. Nothing here touches that.
4. **`ChatSurface` loses a member.** `visibleDeptChips` is read in exactly two places (the composer and
   its two assertions). `OnboardingColdOpen` has its own unrelated `deptChips` — leave it alone.

## 10. Open

Nothing blocking. Two decisions deliberately deferred to §7, and one pre-existing launch blocker this
touches but does not fix: **Product still has no pet and placeholder art**, so it stays filtered out of
`roster` and therefore out of this menu.
