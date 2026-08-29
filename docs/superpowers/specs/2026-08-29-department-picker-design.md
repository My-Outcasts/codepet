# The department picker — one row per pet

**Status:** design, approved 29 Aug 2026. No implementation plan yet.
**Scope:** the composer's department control only. Two follow-on specs are named at
the end and are deliberately not designed here.

## The problem

The composer's department control is a SwiftUI `Menu` whose rows are built from
`DepartmentMenu.rosterOrder` — one row per **department**. There are eight
departments and six pets, because `DepartmentCompanions.map` casts `nova` to both
Marketing and Sales and `glitch` to both Operations and Legal. So the menu renders
Nova twice and Glitch twice, each time with the same sprite and the same name.

Three defects follow, and the third is the one that misleads.

**1. The duplicate rows read as a bug.** Nothing in a row says *this pet has two
departments*. The repetition looks like a double-render or a data error, and eight
rows are spent expressing six characters.

**2. A selected row loses its portrait.** `ChatComposer.deptRow` renders the
selected row as `Label(title, systemImage: "checkmark")`. The checkmark takes the
**image slot**, so the sprite is dropped — on the one row where identity matters
most, because that pet is about to speak. The portrait column breaks with it: seven
faces and one glyph. The composer chip below simultaneously shows the sprite, so the
two controls disagree about whether the selected pet has a face.

This is not an oversight. A `Menu`'s rows flatten to `(title, image)`, as
`ChatComposer:390` already documents. Inside a native `Menu` a row cannot carry both
a sprite and a checkmark. That single constraint caps what the current control can
be, and it is the reason this design replaces the control rather than patching it.

**3. A guess and a pick render identically.** `shown = armed ?? suggestedDept`
(`ChatComposer:357`) and `deptRow` checkmarks on `shown`. The composer chip is
careful to distinguish the two — a dashed stroke for a suggestion,
`ChatComposer:463` — but the menu is not. When Codepet has merely guessed
Marketing, the chip says "guess" and the menu says "you chose this", about the same
department, eighteen points apart.

Findings 1 and 2 both require a row to carry a portrait *and* structure the native
`Menu` cannot express. That is what makes this a replacement.

## The design

### Rows come from pets, not departments

The structural change. The picker iterates **pets**, each carrying the departments
it covers, in first-appearance order from `DepartmentCatalog.roster` so today's
visual order is preserved:

| Pet | Departments |
|---|---|
| Byte | Engineering |
| Luna | Design |
| Nova | Marketing, Sales |
| Sage | Support |
| Crash | Finance |
| Glitch | Operations, Legal |

Six rows. Nova appears once. "One pet, two departments" stops being an accident of
iteration and becomes the structure of the list.

### The row

`CharacterImage` at 20pt, the pet's name, then one chip per department on the
trailing edge. Row 32pt, chip 24pt, popover 326pt wide. The
`Anyone — Codepet routes it` row and its `anyoneDetail` line stay above the divider,
unchanged in wording and behaviour.

**Every pet carries chips, including the five with one department.** The rejected
alternative gave chips only to Nova and Glitch, which left the list with two row
grammars and gave the four plain rows no signal that they were targets in the same
way. One grammar — face, name, beats — also means a pet gaining or losing a
department changes no layout rule.

`CharacterImage`, not `PetMenuIcon`. That helper exists solely to defeat
`Menu`-label flattening (it presizes an `NSImage` because the label ignores
`.frame`). Both its call sites are in the control this spec deletes, so
`PetMenuIcon` and `PetMenuIconTests` become dead and should be deleted with it. The
roster chips already use `CharacterImage` and are fine, for the reason
`ChatComposer:390` gives: they are plain Buttons, not `Menu` labels.

### Three chip states

| State | Rendering |
|---|---|
| Idle | outlined, muted |
| Suggested | dashed border, tinted fill |
| Picked | filled in the pet's colour |

This is finding 3's fix. Outlined / dashed / filled differ in **shape**, not only in
colour, so the distinction survives colour-blindness without adding glyphs. The
dashed treatment is deliberately the same language the composer chip already uses
for a suggestion, so one visual grammar now covers both controls instead of the two
contradicting each other.

### Keyboard

`Menu` supplied traversal for free; the popover must implement it.

- ↑ / ↓ — move between pet rows
- ← / → — move between a pet's chips
- Return — pick the focused chip
- Esc — dismiss

Traversal is a **pure function over the grouped rows** — `next(from:)` / `prev(from:)`
returning a `(petIndex, chipIndex)` — not logic embedded in the view. A SwiftUI row
cannot be asserted on from a test; a function can. This is the same reasoning that
made `DepartmentMenu` a type rather than view code, and it is what makes the
traversal tests below possible at all.

## What must not change

**`DepartmentMenu.rowTitle` stays the single source of truth.** The row now
*displays* the pet's name and the department separately, but each chip's
**accessibility label** is `rowTitle(dept)` — `"Nova · Marketing"`. The invariant
that a row and the reply it summons read alike therefore survives, at the layer
where a screen-reader user actually encounters it. `CopilotChatView.headerName`
renders the same string on the reply, and `DepartmentMenu.armedLabel` on the chip.

Also unchanged:

- `DepartmentCompanions.map` — the cast is not part of this change
- the `selectedDept` binding and `onDismissSuggestion`
- the ✕'s split between clearing a **pick** and refusing a **guess**, and the
  matching split on the `Anyone` row (`ChatComposer:374`)
- Product stays off the roster: it has no pet, and `dept-product.png` is a
  byte-identical copy of `dept-eng.png`, so a row for it would wear Engineering's
  face. Surfacing Product is a separate, known, launch-blocking decision

## Tests

Following the repo agreement — a guard with no test that goes red when it is deleted
is not a guard.

1. **`DepartmentMenuTests`** — keeps the pet-signs-the-reply invariant unchanged.
2. **Grouping is total.** The pet→departments grouping covers exactly
   `DepartmentCatalog.roster`: no duplicates, no omissions. Adding a department with
   no pet, or giving Nova a third, turns this red.
3. **A guess renders unlike a pick.** Collapse the two states and this goes red.
   This is the regression that finding 3 describes, so it gets a named test.
4. **Traversal.** ← / → walks Nova's two chips and stops at both ends; ↑ / ↓ crosses
   rows. Asserted against the pure traversal function.

## Deliberately not in this spec

The picker shows **who** and **what they cover**. It does not show badges ("The
Firestarter"), voice, or remit copy: a remit line doubles the popover's height to
put flavour in front of a routing decision, and a character is better felt when it
answers than when it is chosen.

Two follow-on gaps were identified alongside this one and are **not** designed here.
Both depend on the visual language above, which is why they come after:

- **The department conversation** — how a reply reads as coming from that
  specialist, and what a mid-thread department switch looks like in the transcript.
  `MockChat.departmentReply` already has in-character copy for all eight
  departments, so the fixtures exist and the presentation does not.
- **A Prototype Mode fixture** — a canned scenario walking pick → ask → department
  answer, so the flow can be demonstrated without live spend. This can only
  demonstrate what the two specs above establish.
