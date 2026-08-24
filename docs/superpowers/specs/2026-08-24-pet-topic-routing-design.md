# Codepet — pet topic routing: the right pet arrives before you name it

**Status:** design approved 24 Aug, nothing built.
**Branch:** `feat/pet-topic-routing`, cut from `origin/main` @ `58777fe`. Not off `feat/two-mode-shell` —
that branch merged (`0b19730`, "the two-mode shell is the default") and is now 100 commits behind main.
The two-mode shell IS main; there is no flag to gate this behind.
**Scope:** Swift only. No `functions/` change, no wire change, no Firestore rule change. The request
already carries `companion_id` and `dept_key`; this spec only decides what goes into them.
**Amends:** nothing. It adds a tier *above* `DepartmentCompanions.mentionedDeptKey` and changes that
function not at all.

---

## 1. Why this exists

Today a pet only arrives when the founder **names its department**. `DepartmentCompanions.mentionedDeptKey`
(`codepet/Models/DepartmentCompanions.swift:73`) requires the department name to appear as a whole word
*and* in an addressing phrase — "ask marketing", "what does finance think", "marketing's take".

Everything else answers as the host. There is a passing test asserting exactly that:

```swift
// codepetTests/DepartmentCompanionsTests.swift:62
XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "how do I price my product?"))
```

A founder asking how to price their product gets no pricing specialist. The department chip is the only
reliable way in, and it sits under the composer, out of the eyeline of someone typing.

That narrowness was bought, not chosen. Two regressions are recorded in the file's own comments:

- **Aug 7** — matching was `lower.contains(dept.name)` over the whole message, so a pasted customer quote
  (*"emails me when something's off instead of using support"*) handed a Sales task to Sage · Support.
  One incidental word inside someone else's sentence changed who answered.
- **Aug 10** — the addressing verb list included `for`, `from`, `with`, `have`, `do`. Measured against
  real-shaped messages, **6 of 12 summoned a pet nobody asked for**: *"we have support from two angel
  investors"* → Sage · Support, *"I'm happy with design so far"* → Luna · Design.

So topical routing is the direction those guards were built to block. This spec earns it back by adding a
**separate, lower-confidence tier** with its own guards, rather than loosening the rule that already works.

## 2. What the founder gets

A tentative department chip that arms itself while they type, which they accept by pressing Send.

```
┌──────────────────────────────────────────┐
│ how should I price the pro tier?         │
│                                          │
│ ┆ 🌙 sage · Finance  ✕ ┆        ┌──────┐ │
│ └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘        │ Send │ │
│   suggested — tap to change    └──────┘ │
└──────────────────────────────────────────┘
```

Decisions locked in the design session (24 Aug):

1. **Suggest, founder confirms.** Never silent auto-routing. A wrong guess costs one glance, never a
   wrong answer.
2. **One pet per turn, strongest signal wins.** A genuinely two-department message is a near-tie, and a
   near-tie stays with byte. Byte hosting an ambiguous question is the correct answer, not a fallback.
3. **On-device recognition.** Zero latency, zero credits, deterministic, unit-testable. A pre-send model
   call would spend credits on messages that are never sent and make the routing rules unprovable.
4. **Sticky until displaced** — in the suggestion layer only. See §5.
5. **Product is out of scope.** It has no pet and `dept-product.png` is a byte-identical copy of
   Engineering's art (`DepartmentCatalog.roster` filters it). Product-shaped questions score nothing and
   stay with byte — which is honest, since byte is the generalist who sequences work. No regression; the
   hole stays exactly as visible as it is today.
6. **English lexicon only.** The `vi` table ships present and empty, so adding Vietnamese later is a data
   fill and not a refactor. A Vietnamese founder sees today's behaviour, which is a no-op rather than a
   regression.

## 3. Architecture

Four files. Three are new and pure; the fourth gains two `@State` properties.

### 3.1 `codepet/Models/TextRelevance.swift` — new, pure

`tokenize`, `overlap`, and the stopword set, lifted **verbatim** from `ChatContext`
(`codepet/Models/ChatContext.swift:16-45`). `ChatContext` then calls it and changes in no other way.

This extraction is in scope because the router needs the same three things, and a duplicated stopword list
is a live trap: fixing one copy leaves the other wrong, silently, in a grounding path. The existing
`ChatContextTests` stand over the move as proof it was clean — if the tokenizer changed behaviour, prior-work
selection changes with it and those tests go red.

Nothing else about `ChatContext` is touched. This is a move, not a refactor.

### 3.2 `codepet/Models/DepartmentTopics.swift` — new, pure

The vocabulary, and no logic beyond lookup:

```swift
enum DepartmentTopics {
    struct Vocabulary { let en: [String]; let vi: [String] }
    static let map: [String: Vocabulary]      // deptKey → words and phrases
}
```

Keyed by `DepartmentCatalog` key. Only the eight departments that have a mapped companion get an entry —
`product` is absent (§2.5), which also means the `map[dept.key] != nil` skip that
`mentionedDeptKey` already performs has an exact analogue here.

Entries are single words (`pricing`, `runway`, `invoice`) and multi-word phrases (`landing page`,
`app store`, `cold email`). Phrases matter because the single most common founder vocabulary is compound.

### 3.3 `codepet/Models/DepartmentRouter.swift` — new, pure

The decision, and the only place confidence exists:

```swift
enum DepartmentRouter {
    enum Tier { case addressed, topical, carryOver }
    struct Suggestion { let deptKey: String; let tier: Tier; let reason: String }

    static func suggest(text: String,
                        tasks: [RoadmapTask],
                        lastActed: String?,
                        language: AppLanguage) -> Suggestion?
}
```

**`host` is deliberately absent.** The router answers *which department*; who speaks for it is already
`DepartmentCompanions.specialistId(for:host:)`, and who signs the reply is already `actingSpecialist`.
Passing the host in here would fuse the third question back into the first two — the exact fusion §3.3
exists to avoid. The view asks `specialistId` whether there is a pet to show, as `DepartmentMenu` already
does (`Models/DepartmentMenu.swift:22`).

`reason` is founder-facing and carries the evidence — `"you mentioned \"pricing\""` — so a wrong guess is
legible instead of spooky (§6).

**Why this is a new file and not a branch inside `DepartmentCompanions`.** Both recorded regressions came
from one function answering two questions at once. That file has already been split once for exactly this
reason: `actingSpecialist` → `actingDeptKey` (`CompanyStore.swift:721`), whose own comment says the fusion
"cost the answer". *Who speaks*, *what they know*, and *how sure we are* are three questions. The third gets
its own file.

### 3.4 `codepet/Views/Copilot/CopilotChatView.swift` — two new `@State`

```swift
@State private var suggestedDept: Department?     // recomputed on draft change
@State private var lastActedDeptKey: String?      // set after a reply lands
```

Both live here rather than in `CompanyStore`, alongside `selectedDept` (line 46) and for the same reason its
comment gives — they are consumed by one send.

Send resolves `selectedDept ?? suggestedDept`. An explicit pick always wins and is never silently
overwritten.

### 3.5 Data flow

```
draft changes
  → DepartmentRouter.suggest(...)
  → suggestedDept
  → ChatComposer renders it tentatively, ONLY when selectedDept == nil
  → Send resolves selectedDept ?? suggestedDept
  → CompanyStore.actingDeptKey / actingSpecialist  ← unchanged
  → companion_id + dept_key on the wire            ← unchanged
  → reply lands → lastActedDeptKey updated
```

Everything downstream of the send already works and is not touched: who signs the reply, what expertise
reaches the model, and the deliberate `companionId`/`deptKey` split
(`Services/CompanyChatClient.swift:157-170`).

## 4. Scoring

Four tiers, checked in order. The first that fires wins.

| Tier | Fires when | Result |
|---|---|---|
| 1 · Addressed | `DepartmentCompanions.mentionedDeptKey` hits | suggest, always |
| 2 · Topical | a department clears both thresholds (§4.2) | suggest |
| 3 · Carry-over | no topical winner **and** `lastActed` is set | suggest `lastActed` |
| 4 · None | everything else | chip empty, byte hosts |

Tier 1 is today's behaviour, called unchanged and placed above everything new. **Today's tests keep passing
because today's code still runs first, on the same inputs, and answers the same way.**

### 4.1 The score, per department

```
lexiconScore = 3 × |draftTokens ∩ DepartmentTopics.map[dept]|
taskScore    = 1 × |draftTokens ∩ tokens(founder's task titles tagged dept)|, capped at 3
total        = lexiconScore + taskScore
```

`taskScore` is what makes this adapt to the founder's actual company rather than to a generic vocabulary:
someone whose roadmap has "Rewrite the pricing page" gets stronger Design/Finance signal on their own words.
It is capped at 3 so a department with many tasks cannot win on volume alone.

**Department prose is deliberately excluded.** `Department.rationale` and `.focus`
(`Models/Department.swift:46-72`) are founder-facing copy — *"the thing you're building"*, *"ship"*,
*"users"*, *"make it easy"*. That vocabulary appears in every department and in most messages. Scoring
against it would put a noise generator inside the one component whose job is not making noise. Curated
lexicon plus the founder's real tasks, nothing else.

### 4.2 Two thresholds

- **Floor** — `total ≥ 3`. One solid lexicon hit, minimum. A stray token cannot route a turn.
- **Margin** — the winner must beat the runner-up by **≥ 2**.

The margin is where "strongest wins, near-ties go to byte" lives. *"the pricing page copy feels off and I'm
not sure $19 is right"* scores Design and Finance close together, fails the margin, and stays with byte —
the honest answer for a genuinely two-topic sentence.

### 4.3 Three guards

1. **Quoted and pasted spans are stripped before scoring.** Text inside `"…"` and lines beginning with `>`
   do not vote. This is aimed directly at the Aug 7 regression, where a founder pasting a customer's words
   changed who answered. Highest-value guard here and the cheapest.
2. **Whole words only.** `TextRelevance.tokenize` splits on non-alphanumerics, so `designed` is the token
   `designed` and can never match `design` — the Aug 7 substring defect cannot recur through this path.
   Multi-word phrases match against the raw lowercased text with the same boundary checks `isAddressed`
   uses.
3. **Suppressed in `.build` mode.** That send does not read the department at all
   (`CopilotChatView.swift:986`), so arming a chip there would promise a handoff that cannot happen.

### 4.4 Worked examples

Scores below are **illustrative** — they show which rule decides, not values to assert against. The real
numbers fall out of the lexicon, which is written during implementation.

```
"how should I price the pro tier?"
   fin high │ runner-up 0 │ floor ✓ margin ✓ → suggest sage · Finance

"the pricing page copy feels off and I'm not sure $19 is right"
   design and fin within 1 of each other │ floor ✓ margin ✗ → no suggestion, byte hosts

"we have support from two angel investors"
   fin 3 ("investors") │ support 0 ("support" is a department NAME, not a fin/support lexicon word)
   floor ✓ margin ✓ → suggest sage · Finance

She said "it emails me when something's off instead of using support"   ← quoted, Aug 7 shape
   quoted span stripped → nothing inside it votes → no suggestion
```

**The third example is a deliberate behaviour change**, approved in the design session. The Aug 10
complaint was that it summoned **Support** — the wrong pet — off the bare word "support". Tier 1 still
refuses that, and `DepartmentAddressingTests` continues to assert it. What tier 2 adds is a *right* answer
where there used to be none: the sentence is about investors and runway, and Finance should hold it.

**What guard 1 does not cover.** The Aug 7 burn was a paste, and a paste does not necessarily arrive
wrapped in quote marks. Stripping quoted spans catches the *quoted* shape only. An unquoted paste is
defended by the floor and the margin and by nothing else, and that is a weaker defence. It is accepted
here because tier 2's failure mode is now a tentative chip the founder can see and dismiss before
sending — not, as in August, an answer already written in the wrong pet's name. If unquoted pastes prove
noisy in practice, the next lever is a length heuristic (a very long draft dilutes rather than concentrates
signal), deliberately not built now.

## 5. Stickiness, and the fix it partially re-opens

`CopilotChatView.swift:986-987` clears the chip on every send, under a comment titled **"One message, one
handoff"**:

> *a founder who asked Marketing one question had Nova answering every later question in the session,
> including the ones about pricing. Nothing on screen said why: the chip sits under the composer, out of
> the eyeline of someone reading replies.*

That is sticky routing, removed on purpose because it went stale invisibly.

**The rule this spec adopts:** explicit picks stay one-message-one-handoff, unchanged. `selectedDept` still
clears on send exactly as today. **Stickiness lives only in the suggestion layer.**

That bug had two halves — the pick was *durable* (never re-derived) and it was *silent* (nothing displaced
it, nothing re-stated it). A suggestion is re-derived from the current draft on every turn and is displaced
the moment another department out-scores it. The re-derivation is what is load-bearing, not the memory.

Carry-over is therefore bounded: it applies only when the current draft produces no tier-2 winner, is
displaced by any winner, and resets on `newChat()` and on thread switch.

Expiring it after N quiet turns was considered and rejected. The chip is visible and re-derived every turn,
so the stale-and-silent condition that made the original bug harmful cannot hold.

## 6. The composer surface

The suggested state is the armed chip's treatment **weakened, not redesigned**. Same capsule, same sprite,
same `pet · Department` string from `DepartmentMenu.armedLabel` — so accepting a suggestion changes nothing
on screen except the chip firming up. A suggestion that read differently from a pick would look like two
different features.

```
  no suggestion                suggested                     picked (today, unchanged)
┌──────────────────┐        ┆ 🌙 luna · Design  ✕ ┆        │ 🌙 luna · Design  ✕ │
│  Departments  ▾  │        └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘        └─────────────────────┘
└──────────────────┘         dashed stroke                  solid stroke
  hairline, body text        fill .07 · text .75            fill .15 · text full
```

The armed treatment is unchanged: `fill(accent.opacity(0.15))` + `stroke(accent)`
(`ChatComposer.swift:383-384`). The suggested treatment is the same two lines at `0.07` with a dashed
`StrokeStyle`.

Three interactions, all on surfaces that already exist:

- **Send as-is** → accept. The suggestion becomes the department for that turn.
- **Tap the chip** → the existing departments menu opens with the suggestion pre-checked. Changing it is a
  normal pick, and a pick outranks a suggestion permanently for that message.
- **Tap ✕** → refuse. Chip empties, byte hosts. The refusal holds for the current draft and clears on send
  or when the draft empties — refusing once must not mean re-refusing after every keystroke.

**Hover states the reason.** `.help("Suggested — you mentioned \"pricing\"")`, or for carry-over,
`.help("Continuing with sage · Finance")`. This is what makes a wrong guess legible: the founder can see it
matched "support" in a sentence about investors and dismiss it knowing why.

Deliberately excluded: no animation on the chip arming (it fires on a typing pause; movement would pull the
eye off the text), and no change to the reply header, which already carries `Nova · Marketing` attribution
via `headerName` (`CopilotChatView.swift:1215`).

## 7. Failure behaviour

Every failure mode lands on **byte hosts the turn**, which is the current behaviour for every message and
therefore cannot be a regression.

| Condition | Result |
|---|---|
| Empty or whitespace draft | no suggestion — a fresh composer is never pre-armed |
| No department clears the floor | no suggestion |
| Two departments within the margin | no suggestion |
| Winner maps to no companion | no suggestion (mirrors `mentionedDeptKey`'s skip) |
| Winner maps to the founder's OWN companion | `deptKey` still resolves, chip stays empty — no handoff to announce, but the expertise still reaches the model. This is the exact case `CompanyChatClient.swift:157-170` exists to protect. |
| Language is `.vi` | `vi` table empty → no lexicon hits → tier 1 and tier 3 still work |
| `.build` mode | suppressed entirely |

There is no network path and no persistence, so there is no error state beyond these.

## 8. Testing

All three new types are pure and fully unit-testable. That is the property that lets us *prove* the two
recorded regressions stay dead, rather than hoping.

**`TextRelevanceTests`** — the extraction is behaviour-preserving. The existing `ChatContextTests` are the
real proof and must stay green untouched; these add direct coverage of `tokenize`/`overlap`/stopwords.

**`DepartmentRouterTests`** — the substance:

- *Tier order.* An addressed message routes via tier 1 even when tier 2 would pick a different department.
- *Floor.* A single weak token yields no suggestion.
- *Margin.* The two-topic pricing-page sentence yields no suggestion.
- *Quoted spans.* The Aug 7 paste yields no suggestion. **Direct regression test.**
- *Substrings.* "designed", "operational", "supporting" yield no suggestion from those words alone.
- *Carry-over.* A keyword-free follow-up returns `lastActed` at tier `.carryOver`; a message with a clear
  winner displaces it; `lastActed == nil` yields nothing.
- *Host collision.* The router returns the `mkt` key regardless of who the host is; that the chip stays
  empty when the host IS Nova is `specialistId`'s existing behaviour and its existing test.
- *Task boost.* A founder with "Rewrite the pricing page" tagged `design` scores Design higher than a
  founder without it, on the same message.
- *Language.* `.vi` returns nothing from tier 2 and still works at tiers 1 and 3.

**`DepartmentCompanionsTests` / `DepartmentAddressingTests` are not modified.** They exercise
`mentionedDeptKey` directly, tier 1 is unchanged, and their answers are unchanged. If either goes red, the
extraction or the tier order is wrong — they are the canary for this whole spec.

**Composer.** `ChatComposer` state is asserted the way `DepartmentMenu` already is: the suggestion is a value
on a pure type, so "the chip shows the pet that will sign the reply" stays provable without rendering a
`Menu`. The *visual* treatment — whether the dashed chip reads as tentative rather than broken — cannot be
verified from here and is a handoff to Mona. Green tests are not a claim about how it looks.

## 9. Out of scope

- Product's missing pet and missing art (§2.5). Separate spec.
- The Vietnamese vocabulary. Structure ships, data does not (§2.6).
- Any model-side classification. Explicitly rejected: cost, latency, and unprovable rules.
- Multi-pet answers, or byte splitting one reply between two departments. Rejected in favour of one voice
  per turn.
- Any change to `functions/`, the wire contract, or Firestore rules.
