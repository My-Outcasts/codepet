# Day one: the nine questions a solo founder actually has

**Status:** design, awaiting founder review.
**Date:** 2026-09-05
**Founder decisions:** the chain wins; it runs as its own sequence; two Murror states sharing one
source; the landing page is the bridge, not the finale.

## The finding

Measured, not recalled.

`DemoProjectMurror.swift` seeds **tasks and library entries and zero chat messages** — grep for
`messages`, `ChatMessage` or `conversation` returns nothing. The 24-beat walkthrough contains
**one `.runBeacon`** and **one `.approveNewestDraft`**. So one department produces anything on
camera, and the other seven exist only as rows that were already there.

Worse, the collaborating-departments feature built for this demo **cannot fire in it**.
`offerChainIfNeeded` appears only when a dependency has produced nothing; all three spine tasks
are in `filed`, so `UpstreamWork.firstUnfiled` returns `nil` for every open task. The hand-off
card has never once appeared in the demo it was written for.

And the board is a fan, not a chain: every open task hangs off `mur-brand`, `mur-landscape` or
`mur-interviews`, all done. The six artifacts filed on 2026-09-04 carry **no `dependsOn` at
all**, which is exactly why they surface in the Library and nowhere else.

Reported by the founder as: *"Why are all the outputs only in the Library and not in the chat
flow? Didn't I say to take the Murror project and create a complete flow from A to Z?"*

## What this is for

**A solo founder who does not know where to start.** Not a founder with a brand, a competitive
scan and twelve interviews already behind them — that is where Murror's board begins today, and
it is the wrong starting point for the person this product is for.

So the script is driven by **her questions**, in the order they actually occur, and each answer
raises the next one. The departments are the answer to a question she already has, never a menu
she has to know how to use.

## The script

Opening state: a feeling and nothing else.

> *"I keep thinking people are lonely and don't know how to talk to each other. I want to build
> something. I don't know where to start."*

| # | Her question | Dept · pet | Task | id |
| --- | --- | --- | --- | --- |
| 1 | *"Is this a real problem, or just mine?"* | Marketing · Nova | Talk to 12 people about being lonely | `mur-interviews` |
| 2 | *"Has someone already built this?"* | Marketing · Nova | Scan the journaling and companion apps | `mur-landscape` |
| 3 | *"So who is it not for?"* | Sales · Nova | Write down who this is not for | `mur-notfor` |
| 4 | *"What should it feel like?"* | Design · Luna | Shape the Murror visual direction | `mur-brand` |
| 5 | *"What do I build it on?"* | Engineering · Byte | Choose what the app is built on | `mur-stack` |
| 6 | *"What will this cost me a month?"* | Finance · Crash | Work out what a month of inference costs | `mur-unitcost` |
| 7 | *"What if someone's struggling at 2am?"* | Support · Sage | Decide what happens on a bad night | `mur-crisis` |
| 8 | *"Am I in trouble for holding their words?"* | Legal · Glitch | Write the data-deletion promise | `mur-deletion` |
| 9 | *"How do I ship without breaking it?"* | Operations · Glitch | Set up the weekly release rhythm | `mur-rhythm` |

Nine links, **eight departments**, Marketing at both ends of the opening. Six pets cover eight
departments — Nova is Marketing *and* Sales, Glitch is Operations *and* Legal — which the script
does not hide.

### Link 1 is the founder's own work, and stays that way

`mur-interviews` is `who: .you`. Codepet **cannot run it**, and `handleRunTaskId` refuses a
`.you` task outright. This is the right opening rather than an obstacle: the first thing a
founder has to do is talk to people, and a product that offered to fake twelve interviews would
be lying in its first thirty seconds.

So link 1 is: Codepet prepares the interview guide, says plainly that the conversations are
hers, and records what comes back — the existing `needsYou` → how-to → capture path. The
deliverable is filed from what she records, which is why `mur-interviews` is in mid-flight's
`filed` list despite being founder-only.

`UpstreamWork.firstUnfiled` skips `.you` dependencies, so link 2 is never offered a "run both"
for it. `assemble` has no such clause — it needs only a **filed** deliverable — so once link 1
is recorded, link 2 credits it normally.

## The bridge ending

After link 9 the board is **exactly mid-flight**: nine done and filed, eight runnable, one
founder-only. `RoadmapEngine.nextStep` then lands on *Build the Murror landing page* — which is
where the existing 24-beat tour's `.runBeacon` already starts.

Her tenth question, *"so how do people actually hear about it?"*, is the one the simulation
**hands back rather than answers**. Two demos become one continuous story:

> day one → her nine questions → mid-flight → the tour → the landing page, opened in a browser

The landing page is the only deliverable that opens in a real browser (`SiteExport`, shipped
2026-09-05), which makes it the right thing to leave in front of her.

## Architecture

### One task list, two states

`murrorTasks` stays the single source. The two states differ in **exactly two fields**:

| | `filed` | the nine tasks' `done` |
| --- | --- | --- |
| `murror` (mid-flight) | nine ids | `true` |
| `murrorDayOne` | `[]` | `false` |

Everything else — brief, `deliverables`, `departmentReplies`, `roomFrames`, the other nine tasks
— is shared by reference. **No deliverable content is written for this spec.** `deliverable(for:)`
matches keywords against the title, so identical titles resolve to the nine artifacts that
already exist.

This is what makes "day one run lands on mid-flight" exact rather than approximate.

### A change from the first decision, stated plainly

The founder's first decision was *"restructure Murror's **eight open tasks** into a dependency
line"* — chosen before the from-zero reframe. This spec instead chains the **nine tasks the
simulation runs**, and leaves the eight open ones exactly as they are.

The reason is the bridge: day one must land on mid-flight, and mid-flight's eight open tasks are
part of what it lands on. Chaining those as well would block seven of them and destroy the state
the tour needs. If the earlier reading was the intended one, this is the paragraph to reject.

### The dependency line is the mechanism, not decoration

`UpstreamWork.assemble` reads the **filed** deliverables of `task.dependsOn`. For link N's card
to credit link N-1, link N must depend on link N-1 and link N-1 must be filed. The script
approves each link before running the next, so the existing `runRequest` → `assemble` path
produces the credit line with **no new carry-forward code**.

The nine gain a linear `dependsOn` chain in the shared task list:

```
interviews → landscape → notfor → brand → stack → unitcost → crisis → deletion → rhythm
```

**These edges are safe to add to mid-flight too**, which is why they live in the shared list.
`RoadmapEngine.status` returns `.done` before it consults `depsSatisfied`, so edges among tasks
that are all `done` change no status, no `nextStep`, and no runnable count. Mid-flight's eight
open tasks keep the deps they have.

Two consequences to verify during implementation, not to assume:
- the roadmap **draws** these edges, so mid-flight's map gains a visible spine
- `DemoProjectMurrorTests` may assert exact `dependsOn` arrays

### The sequence

A new `DayOneScript.swift` holding a beat table of the same shape as `MockFlowScript`, played by
the existing `MockFlowPlayer` — not new playback machinery. Nine runs at ~3s plus nine approvals is roughly **40 seconds**.

It does **not** join the 24-beat tour. That tour is 84.1s against a 100s ceiling which
`MockFlowScriptTests` says was twice refused a raise, and nine links do not fit in 16 seconds.
Keeping them separate is what lets each be the right length.

The script performs the taps. The founder watches; the approval gate is shown honestly at every
link without costing her nine clicks.

## Explicitly out of scope

- **Raising the tour's 100s ceiling.** The reason for a separate sequence.
- **Raising `maxFanOut`.** Still a production cost guard, not a demo dial.
- **New deliverable content.** All nine artifacts exist and are reused verbatim.
- **Changing `LibraryView`, `runChained`, `UpstreamWork` or `SiteExport`.** The hand-off works
  through `assemble` on filed work. If it turns out it does not, that is a separate finding.
- **Building the landing page inside the simulation.** It is the bridge; the tour builds it.
- **The `codepet` demo project.** Unchanged. Ten test files name it directly and it is the
  fallback `DemoProject.current` for the rest, so a change there reaches further than it looks.
  (An earlier spec of mine claimed "236 test files depend on it"; measured, the suite has 248
  files in total and 10 reference the fixture by name. The 236 was never counted.)
- **Mid-flight's eight open tasks.** Their deps, order and runnability are untouched.

## Tests

| Guard | Why |
| --- | --- |
| `murrorDayOne` has zero filed and zero done among the nine | the from-zero premise |
| Its board is `murror`'s with exactly those two differences | "one source" is a claim a test should hold, not a comment |
| Running the nine in order yields `murror`'s exact `filed` set | the bridge claim, asserted end to end |
| After the nine, `nextStep` is `mur-site` | the tour picks up where the simulation stops |
| The nine cover all eight roster departments | the claim the whole change exists to make |
| Each link's `assemble` returns its predecessor's filed work | the hand-off, at the mechanism rather than the caption |
| Link 1 is `who: .you` and is never offered as a Codepet run | the honesty the opening depends on |
| Mid-flight's runnable count and `nextStep` are unchanged by the new edges | the 17 suites' premise survives |
| The sequence has exactly nine run beats and nine approve beats | no silent drift into eight or ten |
| No new deliverable resolves to the catch-all | `DemoProjectParityTests` already enforces it |

## Cost

Small, because the expensive part is already written. A second `DemoProject` value, nine
`dependsOn` edges, one scripted sequence, and the tests above. The nine artifacts, the brief and
the department replies are reused unchanged.

The risk is not volume. It is that `DemoProjectMurrorTests` asserts the board's exact shape in
71 assertions, and the new edges run straight through it.
