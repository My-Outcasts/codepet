# First-run: the draft says it isn't filed yet

**Status:** design, awaiting founder review. No implementation plan written.
**Date:** 2026-09-04
**Founder decisions recorded:** 3 (below)

## The question this answers

*"What is the first thing new users need to know when they first open the app?"* — founder,
2026-09-03.

Answer, chosen from four candidate risks: **that nothing is committed until they approve it.**
Not what Codepet is (the cold open sells that), not what to do first (the beacon names one real
task), and not credits — which is a real gap but a separate conversation, and partly blocked on
the trial credit amount still being an open pricing decision.

## What the app already says, verified in code

The rule is stated **before** and confirmed **after**. Only the middle is silent.

| When | Surface | Copy | State |
| --- | --- | --- | --- |
| Before the first run | beacon card (`BeaconOffer.swift:95`) | "\(dept) can draft this now — you approve before it is filed." | ✅ exists |
| Before, on a waiting draft | beacon card (`BeaconOffer.swift:80`) | "A draft is waiting on you — approve it before it is filed in Library." | ✅ exists |
| **At the draft** | **chat draft card** | **nothing** | ❌ **the gap** |
| After approving | chat draft card | "Added to Library" / "Đã thêm vào Thư viện" | ✅ exists |

So the founder is told the rule on the card they press first, and told it landed once they act.
In between they are looking at a finished-*looking* deliverable — a rendered landing page, a
working four-input pricing model — beside a button labelled **Approve**, with nothing saying it
is not saved. That is the moment the promise either becomes concrete or is forgotten.

There is also a once-per-account briefing (`RoadmapView`, gated on `introSeenAt` and a resolved
roadmap) that explains how to read the map. **It only fires on the Roadmap surface**, and a new
founder lands in Chat — so it may never be seen. That is a separate finding, not fixed here.

## Founder decisions

1. **The risk to address is the approval model**, over credits, over "what is this", over
   blank-page paralysis.
2. **Say it at the moment of consequence**, not upfront — the before-half already exists, so
   this scopes to the draft card alone.
3. **A line that retires after their first approval**, over a permanent line and over renaming
   the Approve button to `Approve & file`. It should disappear because the rule was learned,
   not because a counter ran out.

## Design

One line on the chat draft card, between the deliverable and the Approve/Redo row:

```
┌─ Decide what free and paid mean ─────────┐
│  Price    $6    ──●─────                 │
│  Signups  400   ●───────                 │
│                                          │
│  Not saved yet — approving files it      │
│  in your Library.                        │
│                                          │
│  [ Approve ]   [ Redo ]                  │
└──────────────────────────────────────────┘
```

- **en:** `Not saved yet — approving files it in your Library.`
- **vi:** `Chưa lưu — duyệt để đưa vào Thư viện.`

Styling follows `UpstreamCredit`: ~11.5pt, muted rather than accented — this is a status note,
not a call to action, and the Approve button beside it is already carrying the emphasis.

### The retirement signal

`firstApprovalAt: Date?` on `CompanyState`, mirroring `introSeenAt` exactly: same optional-Date
shape, same epoch-millis persistence under `companies/{uid}`, same dedicated saver closure, same
fail-soft posture — a lost write costs one extra showing of a teaching line and never a broken
card.

**Rejected: deriving it from `company.library.isEmpty`.** Approving is the only thing that files
to the Library, so an empty Library *looks* like a perfect proxy for "has never approved", with
no new state and no migration. It is wrong twice:

- The Murror demo now pre-files three research artifacts (`DemoProject.filed`, added 2026-09-03
  so departments can build on each other). A derived signal would silence this line in prototype
  mode — the one place the rule is most worth teaching, and the surface used to demo the product.
- Any account whose Library was populated another way would silently lose the note.

**Set by both approve paths** — `approveDraft(messageId:)` and `approveTask(id:)`. Learning the
rule on the board must retire the line in chat; it is the same lesson, and a founder who approved
from Tasks does not need teaching in Chat.

### The decision is a pure function

```swift
static func shouldShowNotFiledNote(hasApproved: Bool, draftApproved: Bool) -> Bool
```

Not a condition buried in the view body. Same reasoning as `DraftPayloadPreview.hasStructuredPreview`:
the bug worth guarding lives in the decision, not the layout, and a decision inside a `View`'s
body is only testable by rendering it.

## Explicitly out of scope

- **The beacon copy.** Already correct. Do not touch it.
- **The Tasks draft-preview sheet.** A first-run founder reaches their first draft through the
  beacon into Chat. That sheet is a later-discovery surface where the rule is no longer news.
- **Onboarding and the cold open.** Decision 2 chose at-the-moment over upfront.
- **Credits and the 7-day trial.** A real gap — `Plan.swift` has `Free · 7 days · ~150 credits`
  and it is surfaced only in Settings — but it is its own conversation and partly blocked.
- **The Roadmap briefing never firing in Chat.** Recorded above as a finding; not fixed here.

## Tests

| Guard | Why it exists |
| --- | --- |
| Present on a fresh account's first draft | the whole point |
| Absent once `firstApprovalAt` is set | it retires on learning |
| Absent on an already-approved card | that card says "Added to Library"; two answers to one question |
| Absent when a draft is approved mid-session, without a reload | the note reads live state, not a snapshot taken when the card was built |
| `approveTask` sets the flag, not just `approveDraft` | the board is a real path to the lesson |
| A nil `companyId` does not crash the write | fail-soft, matching `markIntroSeen` |
| The Murror demo shows the note on its first draft | the derived-from-Library trap, pinned so it cannot be reintroduced |

## Cost

~60 lines plus tests: one field on `CompanyState`, its encode/decode and saver, two call sites in
`CompanyStore`, one pure static, one `Text` in `CopilotChatView`.

## Open, not decided here

- Credits/trial messaging at first run — needs the trial credit amount settled first.
- The Roadmap briefing is unreachable for a founder who stays in Chat.
- Product still has no pet and no task; the roster ships 8 of 9 departments.
