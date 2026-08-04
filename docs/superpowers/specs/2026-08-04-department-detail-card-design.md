# Department detail — card design pass (type, layout, imagery)

**Date:** 2026-08-04
**Surface:** `codepet/Views/Company/DepartmentDetailView.swift` (native macOS)
**Related:** `codepet/Views/Company/CompanyView.swift` (the list card this page drills in from), `codepet/Models/Department.swift`

## Problem

The department detail page — the screen you land on from a Company list card — is visually
weaker than the card that leads to it. Three things are wrong.

**Type has no anchor and shrinks on drill-in.** Every element on the page sits in an
11–15pt band: hero name 21 (`DepartmentDetailView.swift:54`), rationale 15 (`:26`),
companion line 13 (`:30`), section header 13 semibold (`:35`), card title 14, detail 12,
chip 11, button 12. The 15pt rationale in `primaryText` competes with the 21pt title
directly above it. Meanwhile the list card names the department at 25pt
(`CompanyView.swift:154`) with its task line at 16 — so opening a department makes its
name *smaller*. The detail screen should be the more committed one.

**Layout is unconstrained and undifferentiated.** `AppShellView.swift:130` hands the view
the full window with no max width, so the rationale runs ~150 characters at a normal
window size. Horizontal padding is 20 (`:44`) against the list's 26
(`CompanyView.swift:35`), so the back link and hero shift 6pt on navigation. A single
uniform `spacing: 14` (`:17`) makes the hero, rationale, companion line, section header
and task cards all read as equal siblings — "What needs doing" floats midway between the
text above and the list it labels.

**A blocked task shows a live-looking primary CTA.** On `.blocked` the button is disabled
(`:129`) but still painted full accent purple with white text (`:124-126`). It reads as
the primary action on a task that cannot run, and clicking does nothing. The
"Needs earlier steps" chip that explains this is pinned to the far right of a
full-window-width card (`:83-89`), hundreds of points away from the button it qualifies —
and for a task blocked by the phase window rather than by dependencies, "needs earlier
steps" is not even true of anything the user can see.

**Covers crop badly and fight their accents.** All 8 covers are 640×360 @1x with no @2x
(`dept-fin` is 640×480, `dept-legal` 640×640). The hero draws 16:9 art into a 6.9:1
letterbox, keeping ~40% of the source height — on `dept-eng` the seated figure and the
glow that carry the image are cut. The gradient lays `d.accent` at 0.55 over already
saturated art (`:51`), which muddies rather than identifies: Engineering's accent is
`accentBlue` over hot-pink art, Finance is gold over blue, Legal purple over orange. The
`ab` badge is plain white (`:53`) while the list card at least tints it with the accent
(`CompanyView.swift:137-142`), so per-department colour identity is weakest exactly where
it should be strongest.

> **CORRECTION (final code review, 2026-08-04).** "~40%" above is wrong. Under
> `contentMode: .fill`, retained height = source aspect ÷ frame aspect. A 16:9 cover
> (aspect 1.778) in a 6.9:1 frame retains 1.778 ÷ 6.9 ≈ **26%**, not 40%. The qualitative
> point — `dept-eng`'s subject was cut — still holds; only the percentage was
> miscalculated. See the matching correction under Design §2 for the corrected
> before/after and the two non-16:9 covers' numbers.

**Two lines say the same thing.** `rationale` and `focus` restate each other for several
departments — eng: "Build and ship the product itself…" / "This is where the thing you're
building actually gets made."; ops: "Stand up the machinery…" / "The boring plumbing that
makes everything else possible." And "· 1 of 1 left" (`:33`) carries no information until
something is done.

## Non-goals

- Regenerating or re-arting the 8 cover assets. Considered and deferred; see Known limits.
- Changing the Company list card (`CompanyView.swift`) beyond reading its badge treatment
  as the source of truth for the hero badge.
- Any change to `RoadmapEngine`, task status semantics, or run/approve behaviour.
- Removing `Department.focus` from the catalog — `ChatContext.swift:95,108` reads it for
  chat grounding. It stops being *rendered* on this page; the field stays.

## Design

### 1. Page frame

- Content column capped at **800pt**, left-aligned, following the pattern already in
  `RoadmapView.swift:187` (`.frame(maxWidth: 760, alignment: .leading)`).
- Horizontal padding **26** (was 20) so the back link and hero align with the Company
  list and nothing shifts on navigation.
- The uniform `spacing: 14` is replaced by grouped spacing, so the page reads as three
  blocks (identity / context / work) rather than six equal rows:

  | Gap | Value |
  |---|---|
  | back link → hero | 16 |
  | hero → rationale | 18 |
  | rationale → companion line | 10 |
  | companion line → section header | 30 |
  | section header → first card | 10 |
  | card → card | 10 |

### 2. Hero

- Height **190** (was 140). In an 800pt column that is 4.2:1 rather than 6.9:1, so a 16:9
  cover keeps roughly 76% of its height instead of ~40% and subjects survive the crop.

  > **CORRECTION (final code review, 2026-08-04).** Both percentages above are wrong, and
  > "subjects survive the crop" overstates the result. Under `contentMode: .fill`, retained
  > height = source aspect ÷ frame aspect: new hero 1.778 ÷ (800/190 ≈ 4.21) ≈ **42%**; old
  > hero 1.778 ÷ 6.9 ≈ **26%**. The real change is 26% → 42% (≈1.6×), not 40% → 76%. The
  > two non-16:9 covers retain less than either figure: `dept-fin` (4:3, aspect 1.333) ≈
  > **32%**; `dept-legal` (1:1, aspect 1.0) ≈ **24%**. At 42% the crop is materially
  > reduced, not solved — which is exactly why the `fin`/`legal` visual check in Task 6 is
  > a real gate, not a formality. The separate claim in Known Limits that the hero is
  > "~2.5× upscaled" is unaffected by this correction and remains correct.
- Explicit `.interpolation(.high)`, matching `CompanyView.swift:127`.
- The accent leaves the gradient. The tint becomes a **neutral scrim** — black 0 →
  0.72, starting at 40% down — chosen for text contrast over any cover, however
  saturated.
- Identity moves to the badge: the `ab` chip adopts the list card's exact treatment
  (`CompanyView.swift:137-142`) — `#0b0a12` at 0.82 with the department accent at 0.34
  over it, white 0.25 hairline, radius 8, 11pt semibold — so the two surfaces agree.
- Label row inset 16. Name at **30pt semibold**, tracking −0.5, white.
- `Department` gains `coverAnchor: UnitPoint = .center`, used as the `scaledToFill`
  alignment. Only `fin` (4:3) and `legal` (1:1) are candidates for a non-default value,
  and only if the visual check after implementation shows a bad crop — the field exists
  as a per-department escape hatch, not as a value to set speculatively.

### 3. Type scale

| Element | Now | Proposed |
|---|---|---|
| Hero name | 21 semibold | **30 semibold**, tracking −0.5 |
| Rationale | 15, `primaryText` | **16, `bodyText`** |
| Companion line | 13, `bodyText` | 13, `mutedText` |
| Section header | 13 semibold, muted | **12 semibold, uppercased**, tracking 0.4, muted |
| Card title | 14 semibold (`cardTitle()`) | **15 semibold** |
| Card detail | 12 (`cardDetail()`) | **13** |
| Status chip | 11 medium | 11 medium (unchanged) |
| Action button | 12 semibold | 12.5 semibold |

`cardTitle()` / `cardDetail()` in `CodepetTheme.swift:133-134` are shared with other
surfaces, so this page overrides the sizes locally rather than changing the shared
helpers.

> **CORRECTION (final code review, 2026-08-04).** "Shared with other surfaces" was false:
> `grep -rn "cardTitle\|cardDetail"` across `codepet/` and `codepetTests/` turned up only
> the two definitions themselves — `DepartmentDetailView` was their sole consumer, and
> after this pass it doesn't call them either (the task card sets its type directly with
> `CodepetTheme.inter(...)` at the sizes in the table above). The two helpers were
> therefore dead code and have been deleted from `CodepetTheme.swift`. The real reason
> this page sets its sizes inline is simply that 15/13 are this page's own numbers, not a
> role shared with anything else.

### 4. Task card

- Interior padding 12 → **14**; radius 12 and the surface/hairline chrome unchanged.
- Title 15 semibold, detail 13 `mutedText`, `lineLimit(2)` retained.
- The status chip stays top-right, preserving parity with the web `tstate`; the 800pt
  column removes most of the distance problem on its own.
- **Blocked state, the substantive fix.** When `status == .blocked` the action renders as
  a dimmed ghost capsule — hairline stroke, `mutedText` label, 0.55 opacity, no accent
  fill — accompanied by a reason line in 12pt `mutedText`, so the card states why instead
  of dangling a dead primary button.

  `.blocked` has two causes (`RoadmapEngine.swift:27-28`: a closed phase window, or unmet
  `dependsOn`), and `RoadmapGating.blocker(for:in:)` already resolves both into the one
  task to name — the first unfinished dependency when the phase is open, else the founder
  step holding the window shut. The roadmap card face and hover peek already render it
  (`RoadmapBoardView.swift:213-214,538`), so **no new resolution logic is written**: the
  reason line is `RoadmapBoardCopy.waitingOn(blocker.title, lang:)` → "Waiting on:
  ‹title›" / "Đang chờ: ‹title›". Naming the actual step beats naming a phase, and the
  copy, both languages, and the edge cases are already tested.

  Resolution runs against `companyStore.company.tasks`, not the department-filtered list,
  since a blocker often lives in another department. If `blocker` returns nil the line is
  omitted and only the ghost styling applies.

  `RoadmapGating.escapeHatch(for:in:)` — which would turn the blocked CTA into a jump to
  the blocking task — is deliberately not used. Department cards don't navigate the
  roadmap, and adding that is a separate decision.
- `.needsApproval`, `.needsYou`, `.codepetCanDo` keep their current labels, styling and
  behaviour, including the accent-purple fill. The running state is unchanged.

### 5. Live companion line

The static `d.focus` render is replaced by a derived line, so the companion says something
only it can say.

- New pure function, colocated with the view's model layer:
  `departmentPulse(_ dept: Department, tasks: [RoadmapTask], all: [RoadmapTask], lang: AppLanguage) -> String`
- Branch priority, first match wins:

  | Condition | EN copy |
  |---|---|
  | no tasks in dept | *(line omitted entirely)* |
  | all tasks done | "All clear in ‹Dept›." |
  | any `.needsApproval` | "‹N› ready for you to approve." (singular: "One thing's ready for you to approve.") |
  | any `.needsYou` | "‹N› here need you." (singular: "One here needs you.") |
  | any `.codepetCanDo` | "Nothing blocked — I can run ‹N› of these now." (singular: "Nothing blocked — I can run this one now.") |
  | all remaining `.blocked` | "Everything here is waiting on ‹blocker title›." — blocker from `RoadmapGating.blocker(for:in:)` on the first blocked task; if it returns nil, "Nothing here is unblocked yet." |

> **CORRECTION (final code review, 2026-08-04).** The "Nothing here is unblocked yet."
> fallback in the row above was never implemented, and that omission is correct, not a
> gap. `.blocked` has exactly two causes (`RoadmapEngine.swift:27-28`): a shut phase,
> which by construction means a founder step exists to hold it shut, or an unmet
> `dependsOn`, which by construction means a not-done dependency exists. Either way,
> `RoadmapGating.blocker` always resolves to a task for a `.blocked` task today — it
> cannot return nil on this path. `DepartmentPulse.swift` returns `nil` from the whole
> function in that branch instead of inventing copy for a state that cannot occur:
> returning nil beats inventing a string for dead code. Do not add the string; there is
> nothing that reaches it.

- Vietnamese strings for every branch, following the existing `lang == .vi` pattern in the
  file.
- Sprite drops 28 → **22** and centres against the text (`HStack(alignment: .center)`)
  instead of towering over a single top-aligned line.
- The line is omitted rather than emptied when a department has no tasks, so dormant
  departments don't show an orphan sprite.

### 6. Section header

- "WHAT NEEDS DOING" — 12pt semibold, uppercased, tracking 0.4, `mutedText`.
- The count is appended only when it is informative: "· ‹done› of ‹total› done" when some
  but not all tasks are complete; nothing when zero are done. "1 of 1 left" disappears.
- The empty-department string (`:38`) is unchanged.

### 7. Hero badge vs. name redundancy

The `ab` badge is kept on the hero. With the accent out of the gradient, the badge is the
page's only carrier of department colour, which earns its space; it also keeps the hero
consistent with the list card's cover panel.

## Testing

- `departmentPulse` is pure and view-free, so it takes unit coverage per branch in a new
  `codepetTests/DepartmentPulseTests.swift` — one test per row of the table above plus the
  singular/plural forms and the no-tasks omission. `RoadmapTaskDeptTests.swift` is the
  sibling pattern for constructing dept-tagged `RoadmapTask` fixtures.
- Blocker resolution itself is already covered by `RoadmapGatingTests.swift`, so it gets no
  duplicate tests. What is new and therefore tested here: the all-blocked pulse branch
  names the blocker (including a blocker owned by another department, proving resolution
  runs against all tasks rather than the filtered list).

  > **CORRECTION (final code review, 2026-08-04).** This bullet originally also promised
  > a test that "falls back cleanly when `blocker` returns nil." That test does not exist,
  > correctly — see the correction under §5's table: the nil path is unreachable by
  > construction, so there is no state to build a fixture from, and no test was written
  > for it.
- Type, spacing and hero changes carry no automated test; they are verified visually.
- **Visual verification is a handoff.** This session cannot screenshot the native app.
  After a TEAM-signed build, the checks to run are: all 8 departments for hero crop
  (especially `fin` and `legal`), title legibility over each cover, and one blocked task
  showing the ghost CTA with its "After:" line.

## Known limits

At 190pt in an 800pt column the hero is ~1600 device px drawn from a 640px source — still
about a 2.5× upscale. Removing the horizontal over-stretch improves it materially, but the
covers stay somewhat soft. The real fix is re-exporting the 8 covers at ≥1600px wide (and
normalising `fin`/`legal` to 16:9), which is an art pass deliberately out of scope here.

The covers are also semantically arbitrary — Design is a CD, Finance a galaxy, Legal a
figure with a planet — and each carries a dominant hue unrelated to its department accent.
The neutral scrim and accent badge contain the damage; they do not fix the art direction.
Both items are logged here as the follow-on if the imagery is revisited.
