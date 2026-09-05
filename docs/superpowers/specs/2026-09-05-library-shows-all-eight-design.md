# The demo shows one department of eight

**Status:** design, awaiting founder review.
**Date:** 2026-09-05
**Founder decisions:** show eight *finished artifacts they can open*; grow the board to carry
finished AND next work; draft all six new deliverables from Murror's brief.

## The finding

Measured, not recalled. The 24-chapter walkthrough contains exactly **one** `runBeacon`, **one**
`approveNewestDraft` and **one** `convene`. So one department — Marketing — produces work on
camera. The room brings four departments in, but a room produces a *decision*, not an artifact.

Meanwhile the board carries eight runnable tasks across eight departments, each with a real
authored deliverable across eight distinct kinds. All built. All reachable by asking. **None
shown by the flow.** Chapter 2 narrates *"eight departments, each speaking with its own pet"*
and the tour then demonstrates one.

Reported by the founder twice — and the second time was after this had already been specced as
a three-department fan-out beat and not built.

## The surface already exists

`LibraryView` groups deliverables **by department**, in `DepartmentCatalog` order, emitting one
group per department **that has work** (`LibraryView.swift:131-145`). It renders all thirteen
deliverable kinds through their real viewers. It is exactly the "what your company has made"
screen this needs.

It is nearly empty because the fixture gives it almost nothing: three filed artifacts
(`DemoProject.filed`), belonging to two departments and all of kind `doc`. So the Library today
shows **two groups**, not eight.

**This is why no new surface is being built.** A gallery would compete with the place finished
work already lives.

## The tension, and how it resolves

Eight *finished* artifacts and eight *runnable* tasks pull against each other: a task cannot be
both `done` with a deliverable behind it and open for Codepet to run. Today only three tasks are
done, and they cover two departments.

**Resolution: the board carries both halves.** One done-and-filed task per department, plus the
eight runnable ones. That is what a real mid-flight company looks like — work behind you and
work in front of you — and it is the only option that keeps the demo's existing headline claim
("all eight pets runnable at once", asserted through the engine by `DemoProjectMurrorTests`)
while making breadth browsable in seconds.

**Six new done tasks, not five.** The roster is eight — `eng, design, mkt, sales, support, fin,
ops, legal` — and existing done tasks cover `mkt` (twice) and `design`. The gap is **eng, sales,
support, fin, ops, legal**. An earlier count of five in conversation was wrong.

Board: **12 → 18 tasks** (9 done, 8 runnable, 1 founder-only).

## The six new deliverables

Each is real work Murror would plausibly have behind it, in a kind that suits the department.
Kinds are chosen to widen what the Library demonstrates rather than to repeat: the eight
runnable already produce `checklist, screens, site, sheet, doc, dms, plan, legal`.

| Dept | Task | Kind | What it is |
| --- | --- | --- | --- |
| eng | Choose what the app is built on | `doc` | The stack decision and what it rules out — on-device vs server inference, and why entries never leave with a name attached |
| fin | Work out what a month of inference costs | `sheet` | Cost per active user at the current model, the number the pricing task depends on |
| sales | Write down who this is not for | `doc` | The disqualifier list from the interviews — the person who found the framing insulting |
| support | Decide what happens on a bad night | `doc` | The crisis path as a written policy: what the app says, when, and what it refuses to handle |
| ops | Set up the weekly release rhythm | `checklist` | The cadence the launch checklist later assumes |
| legal | Write the data-deletion promise | `legal` | One tap, permanent, no email — the promise the privacy policy formalises |

**They must be genuinely good.** `DemoProjectParityTests` already fails on filler that reaches
the catch-all, and a Library full of obvious placeholder is worse than one with three real
things. Drafted from Murror's brief — loneliness, journaling, "AI that brings people closer",
private by design, the crisis path, no streaks — and consistent with the interview findings and
competitive scan already in the fixture.

## The walkthrough beat

Without this, breadth exists and the flow still never shows it — the exact failure being fixed.

One new beat after the existing run-and-approve pair: `go(.library)`, held long enough to read,
captioned to the effect of *eight departments, eight finished artifacts, each one openable —
and every one of them traces back to a task on the roadmap.* Breadth after depth: the founder
first watches one piece of work get made and approved, then sees the shape of a company that has
been doing that for a while.

Placed as a beat rather than a new chapter name if the surrounding chapter still fits; the
caption bar's total is `beats.count`, so nothing hard-codes a chapter count.

## Explicitly out of scope

- **A new gallery surface.** The Library is already it.
- **Raising `maxFanOut`.** Still a production cost guard, not a demo dial.
- **The three-department fan-out beat** (spec of 2026-09-04). This supersedes it: showing eight
  finished artifacts is strictly more than showing three being made. That spec should be marked
  superseded rather than executed.
- **Any change to `LibraryView`.** It already does what is needed. If it turns out not to, that
  is a separate finding, not part of this.
- **The `codepet` demo project.** Unchanged; every suite written against it depends on that.

## Tests

| Guard | Why |
| --- | --- |
| Every roster department has at least one FILED deliverable | the claim this whole change exists to make |
| Every roster department still has exactly one Codepet-runnable task | the existing headline claim must survive |
| The Library's grouping yields eight department groups for Murror | asserts the SURFACE, not just the data |
| No new deliverable resolves to the catch-all | `DemoProjectParityTests` already enforces this; the six must not weaken it |
| No new deliverable body leaks a `{{token}}` | same suite |
| `.find` stays complete | the board must remain the mid-flight state the fixture exists to show |
| The walkthrough contains exactly one `.library` beat, after the approve beat | breadth after depth |
| `codepet`'s board and Library are byte-for-byte unchanged | 236 test files depend on it |

## Cost

The largest of the three demo changes, and the code is the small part: six tasks, six authored
artifacts of real substance, fixture wiring, one walkthrough beat, and revisions to
`DemoProjectMurrorTests`, which asserts the board's exact shape and counts.

Roughly a day, mostly writing.
