# The walkthrough shows one department of eight

**Status:** SUPERSEDED 2026-09-05 by
`2026-09-05-library-shows-all-eight-design.md`. Do not execute this plan.
Showing eight finished artifacts in the Library is strictly more than showing three being made,
and the founder chose it after seeing that this spec had been written and left unbuilt. The
reasoning here about `maxFanOut` being a production cost guard rather than a demo dial is
carried forward into the new spec.
**Date:** 2026-09-04
**Founder decision:** add a fan-out beat showing three departments at once, using the machinery
that already exists.

## The finding

Measured across `MockFlowScript.beats`: the 24-chapter walkthrough contains exactly **one**
`.runBeacon` and **one** `.approveNewestDraft`. The beacon resolves to *Build the Murror landing
page*, so **one** department — Marketing/Nova — produces work on camera.

Chapter 10 convenes the room, which does bring four departments in (design, engineering, legal,
support, verified in `DemoProjectMurrorRoom.swift`) — but a room produces a *decision*, not an
artifact. There are no deliverable kinds in that fixture at all.

Meanwhile the Murror board carries **eight runnable tasks across eight departments**, each with
a real, hand-written deliverable (verified 2026-09-04: no fixture falls through to the
catch-all) across eight distinct kinds — checklist, screens, site, sheet, doc, dms, plan, legal.

So the demo's own claim — *"eight departments, each speaking with its own pet"*, narrated in
chapter 2 — is asserted on screen and then demonstrated once. Reported by the founder as *"has
the flow really included all the outputs from each department yet?"* It has not.

## Design

One new beat: fan out the next moves, so three departments work simultaneously.

**`fanOutNextMoves` already exists and is already tested.** `CompanyStore.swift:2732`, capped at
`maxFanOut = 3`, guarded against overlapping with a stream or another fan-out, covered by
`CompanyStoreFanOutTests` (9 tests). `MockChat` already routes *"Run my next moves"* to it. The
only thing missing is a way for the script to trigger it: `MockFlowScript.Beat` has cases for
`runBeacon`, `approveNewestDraft`, `convene` and nine others, and none for a fan-out.

So this is: **one enum case, one handler line, one chapter.**

- `case fanOut` on `MockFlowScript.Beat`
- `MockFlowPlayer`: `case .fanOut: store.view = .chat; Task { await store.fanOutNextMoves(language: language) }` — the same shape as the existing `.runBeacon` handler at `MockFlowPlayer.swift:148`
- One beat placed **after** the existing run-and-approve pair, so the founder first sees one
  department's work end to end and only then sees the shape of a team. Breadth after depth: three
  parallel agents mean nothing until you have watched one produce something real.

**Placement and caption.** It follows chapter 5 (*"A real deliverable"*) and precedes chapter 6
(*"Work only you can do"*). Caption, in the script's voice — plain about what is on screen and
what it costs:

> Three departments at once, each on the task its own roadmap says is next. Nothing is filed
> until you approve each one.

That last clause matters: a fan-out produces three unapproved drafts, and a founder watching
three things appear at once is exactly the moment to restate that none of them are committed.

**Why not all eight.** `maxFanOut = 3` is a production cost guard, not a demo limit — three
parallel runs against real models is already the most expensive thing this product does
unattended. Raising it for the demo would mean either a prototype-only override (a second code
path in a cost guard, which is the worst place to have one) or raising it for real founders too.
Three shows the shape; eight shows the same shape more slowly.

**The walkthrough grows by roughly 8 seconds** — the fan-out runs in parallel, so it costs about
what one run costs, not three. That is the argument for this option over two more sequential
run-and-approve beats, which would have added about a minute.

## Explicitly out of scope

- **Raising `maxFanOut`.** It is a production cost guard. Not for a demo's benefit.
- **Approving the fan-out's drafts in the script.** Three approvals would be three near-identical
  beats teaching nothing new; chapter 5 already taught approval. The drafts stay unapproved,
  which is also truthful about what a fan-out leaves you with.
- **The remaining five departments.** Three of eight is the deliberate stopping point. The other
  five stay discoverable by asking, which the composer invites.
- **The room.** Unchanged; it is a decision beat and correctly not an artifact beat.

## Tests

| Guard | Why |
| --- | --- |
| `.fanOut` appears exactly once in `beats` | one beat, not a repeated one |
| It is positioned after the approve beat | breadth after depth; a reordering that breaks the teaching order should fail |
| The player dispatches `.fanOut` to `fanOutNextMoves` | the case exists and is wired, not just declared |
| Every `Beat` action case has a handler in `MockFlowPlayer` | the actual hazard: an enum case with no handler is a silent no-op beat, and `MockFlowScriptTests` should own this for all cases, not only the new one |
| The caption mentions approval | the founder-facing reason this beat is safe to show |
| Chapter count and the caption bar's `n/24` label stay consistent | the bar renders a total; adding a beat without it lies about progress |

## Cost

~20 lines plus tests. The last test row — every action case has a handler — is the one worth
more than this change, and covers the twelve cases that already exist.
