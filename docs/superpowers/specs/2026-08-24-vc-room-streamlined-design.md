# The room, streamlined: one call, and departments that stay quiet until asked

**Date:** 2026-08-24
**Status:** approved, not implemented
**Amended:** 2026-08-24 — §1 originally merged the two summary cards. Reading `theCall`'s own
doc comment showed that split was a *deliberate* decision with a rationale that speaks to the
founder's own complaint, so the merge is withdrawn. Marked **[A1]** below.
**Surface:** `codepet/Views/Copilot/VirtualCompanyCards.swift` (1018 lines)

## Why

The founder's read, from three screenshots of a landed room: "too cluttered and broken up
into too many different sections … not optimized for information presentation."

That is right about what they were looking at, and it is worth being precise about *what*
they were looking at, because it changes the fix.

## What is actually on screen, and what is not

`Disclosure` defaults to `open = false` (`VirtualCompanyCards.swift:510`). So the **resting**
landed state is two cards and four one-line rows:

```
THE CALL                              ← card
THE REAL DISAGREEMENT                 ← card
› What each department said · 4        ← collapsed
› Who was in the room, and why · 3     ← collapsed
› How they negotiated · N              ← collapsed
› What could make this wrong           ← collapsed
```

The wall in the screenshots is the **expanded** state. Progressive disclosure is already the
pattern here; a code comment records an earlier pass that merged two disagreement cards for
the same reason ("founder, Aug 7: why are there so many separate cards?").

Two claims made while diagnosing this were wrong and are recorded so they are not repeated:

- **"Six equally-weighted cards are always visible."** No — two are.
- **"The narrative runs backwards; `THE REAL QUESTION` lands after the answer."** No. It is
  inside `routingCard`, the content of the *"Who was in the room"* disclosure, so it is
  already behind a click.

What survives: the **expanded** department list is dense, and the two always-visible cards
should be one.

## The contract constrains this, and it is not a style guide

`docs/superpowers/specs/virtual-company-sse-contract.md` §"display rules" opens: *"These are
not style preferences. They are the reasons the feature exists (spec §4.3), and several are
already enforced server-side."* Four bind this redesign:

| Rule | What it forbids here |
|---|---|
| 1. Never collapse the process into a spinner plus an answer | The whole room may not go behind one click. This is why the scope stops at the department list rather than hiding everything. |
| 2. Never summarise the positions into one "we agree" paragraph | Each department keeps its own voice. `runSynthesis` throws server-side on a brief that buries dissent. |
| 3. Show `the_real_disagreement` verbatim | The narrative moves into the merged card unchanged — no paraphrase, no softening, no truncation. |
| 5. End on the either/or (`tradeoff_founder_must_own`) | **Fixes the merged card's internal order**: the disagreement must sit *before* the trade-off, so the card still ends on the choice. |
| 7. Confidence as dots, never a number | Dots stay. |

Rule 5 is the non-obvious one. The intuitive order — decision, trade-off, then the conflict
that caused it — is forbidden, because the card would then end on conflict rather than on the
founder's choice.

## 1. One border, two blocks — the merge is withdrawn **[A1]**

`theCall(brief)` and `landedDisagreement(brief)` stay **separate blocks**. `theCall` keeps its
`MessageCard`; the disagreement block loses its border and tint and sits directly beneath as a
continuation.

**Why the merge was withdrawn.** `theCall`'s doc comment records the split as deliberate:

> `the_real_disagreement` deliberately does NOT live here — it has its own always-visible block
> (rule 3) so this card stays the size of a decision rather than a document.

Three things make that decision right, and all three were missed when this spec was first
approved:

1. **The rationale is the founder's own complaint.** Merging makes one document-sized card out
   of two moderate ones. "Too cluttered" is not answered by a bigger card.
2. **Both blocks carry a long unclamped paragraph.** `tradeoffFounderMustOwn` runs ~100 words
   and is deliberately never clamped — a note records the founder's Aug 7 ruling that clamping
   it "cuts before the 'or'", which is the "it's up to you" rule 5 forbids. `theRealDisagreement`
   is verbatim under rule 3, also unclamped. One card would carry both.
3. **The disagreement block is polymorphic.** Its label flips to `WHERE THEY AGREE` and its hue
   from orange to **teal** when `state.conflicts` has no non-ALIGNED pairs. Folding it into a
   purple card destroys that signal and means `THE CALL` sometimes contains an agreement.

**What actually changes**, since the founder's complaint was competing panels rather than card
count: the second panel stops competing. It keeps its position and its content and loses only
its border and fill.

```
┌─ THE CALL ──────────────────────────────────────┐
│ Put the price on the page at launch and switch   │
│ billing on two weeks later.                      │
│                                                  │
│ ●●●○○   UNRESOLVED — YOUR CALL                   │
│                                                  │
│ Either you launch with a number you may have to  │
│ change, or you launch without one and give up    │
│ the only day the product gets free attention.    │
│                                                  │
│ [ Lock this decision in ]    Read the full call  │
└──────────────────────────────────────────────────┘
  Finance ↔ Marketing · blocker
  Engineering ↔ Marketing · tension
  Whether a price is a promise you must be able to
  keep, or a positioning statement you are allowed
  to revise.                             (verbatim)
```

The trade-off still sits last inside the card — rule 5. The disagreement follows *outside* it,
which does not violate rule 5 because the rule governs where the presentation of the **call**
ends, and the call is the card.

**Colour carries the polymorphism now that the border is gone.** Orange text for a
disagreement, teal for `WHERE THEY AGREE`.

**⚠️ The one risk this introduces.** Dropping both the border *and* the label leaves the block
identified only by its pairs line and its hue. `Finance ↔ Marketing · blocker` reads
unambiguously as disagreement; the ALIGNED case — `agreedLine(agreed)` — may not read as
agreement without its `WHERE THEY AGREE` label. **If it does not, restore the label for that
case only.** This is a handoff question, not an assumption to ship: the aligned outcome is
documented in the contract as a normal flow, not an edge case.

**One eyebrow, not three.** Today `THE CALL`, `THE TRADE-OFF ONLY YOU CAN MAKE` and
`THE REAL DISAGREEMENT` compete as three ALL-CAPS labels across two cards. Only `THE CALL`
survives. The disagreement and the trade-off are separated by weight and spacing instead.

This is most of the decluttering, and it is worth saying why: the labels were fighting each
other harder than the content was. An eyebrow orients you inside one dense region; five of
them stop orienting anyone.

**The action row stops inverting itself.** `Read the full call` is currently a full-width
ghost button sitting *above* the primary `Lock this decision in`. It becomes a text link
beside it.

## 2. The department list becomes rows

`departmentsSaid` currently renders one `MessageCard(hue:)` per department — a tinted,
bordered panel carrying a name, a stance pill, confidence dots, the position, a
"Costs their department" line, and an optional 🔒 blocker. Three of those stacked is denser
than the summary they sit beneath.

```
› Finance      do not proceed    ●●●●○
› Marketing    proceed           ●●●●○
› Engineering  with conditions   ●●●○○

  opened ─────────────────────────────────
  Ship the paywall after launch, not before it.
  Costs them: a delayed revenue start, which is recoverable.
  🔒 No price can be set before anyone has used the thing.
```

Borderless, hairline-separated, one row per department. Position, cost and blocker live
behind each row.

**This serves rule 2 better than the current layout, not worse.** The three stances now sit
adjacent instead of separated by paragraphs, so the split is legible at a glance rather than
after reading three cards. Dissent becomes *more* visible, which is the rule's purpose.

**Colour stops doing two jobs.** Today purple means both "the call" and "the real question";
orange means both "disagreement" and Marketing. After this, department hue appears only on
department rows, and the merged card carries the one accent it needs.

## Known duplication, deliberately not fixed here

Open both *"What each department said"* and *"Who was in the room, and why"* and each
department's reasoning appears twice in different words — once as its position, once as a
`✓ Finance — It changes when revenue starts` line inside `THE REAL QUESTION`.

Left alone. Removing either copy touches what the backend sends and which rule covers it
(rule 2 protects the positions; the routing rationale is separate data), and that is a
content decision rather than a layout one. Named so it is not mistaken for an oversight.

## Verification

Layout is measurable offscreen. The native app cannot be screenshotted on this machine
(Screen Recording denied), so appearance is a handoff — but structure is assertable via
`ImageRenderer` in an XCTest, the pattern `BrandMarkRenderTests` and `ComposerEdgeRenderTests`
already use. `ImageRenderer` renders **nothing** inside a `ScrollView`, so any test must
render the cards directly rather than the transcript that hosts them.

Every threshold must come from a measured RED/GREEN pair with both numbers beside it, and
each guard must be watched failing before it ships. Two guards earlier this week passed with
the bug present — one compared against an ideal hex instead of a render, one asserted a
property the change did not affect.

What to assert:

1. **The resting landed state renders exactly one bordered region.** Count bordered regions in
   a render of the landed room with all disclosures closed. Fails before this change (two —
   `theCall` and `landedDisagreement` are both `MessageCard`s), passes after (one). This proves
   the second panel stopped competing without proving anything about a merge, which no longer
   happens.
2. **The department list renders no per-department card border.** Sample the region a
   department row occupies and assert it is the pane surface, not a tinted fill.
3. **Rule 3 is not violated by the merge** — `the_real_disagreement` text appears in full in
   the merged card. A string containment check on the rendered view hierarchy, not a pixel test.

Then the handoff, in both light and dark: *does the room now read as one decision with the
room's work available, rather than as a stack of competing panels?*

## Out of scope

- The in-flight (`state.brief == nil`) rendering. It is one card already.
- The other three disclosures — routing, negotiation rounds, verdict.
- The duplication described above.
- Any change to what the backend sends. This is presentation only.
