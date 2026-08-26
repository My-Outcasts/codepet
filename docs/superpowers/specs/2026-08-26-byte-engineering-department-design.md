# Byte takes Engineering: the host is the product, the pets are departments

**Date:** 2026-08-26
**Status:** approved, not implemented
**Amended:** 2026-08-26 — §5 originally listed three blast-radius sites. Writing the plan
changed the set in both directions: `DepartmentMenu.anyoneLabel` is a fourth and the only
*user-facing string* among them (**[A1]**), and `SecondBrainData.companionName` was listed
wrongly and is withdrawn (**[A2]**).
**Surface:** `codepet/Models/DepartmentCompanions.swift`, `codepet/Models/Character.swift`,
`codepet/Managers/CompanyStore.swift`, `codepet/Views/Copilot/DepartmentRoster.swift`,
`codepet/Views/Copilot/ChatComposer.swift`, `codepet/Views/Copilot/ChatEmptyState.swift`,
`codepet/Views/Copilot/CopilotChatView.swift`, `codepet/Models/SecondBrainData.swift`

## Why

The founder, looking at the roster on the empty hero: *"I remember that we still have Byte as
a pet."*

Byte is on screen nowhere in that grid, and the reasons are worth separating because only one
of them is the thing being fixed.

`DepartmentCompanions.swift` says outright that `byte` is the host/generalist and is
*intentionally* unassigned, so it has somebody to hand off **to**. That was a coherent design
when the founder's companion was a choice made at onboarding. It is no longer: the picker was
removed on 14 Aug (`OnboardingView.finish`, and its own comment says why — companions differ
in identity and voice only, so asking at the door made it look like a decision that shaped the
product). Since then every founder's `company.companionId` is `byte` unless they go into
Settings and change it.

So the host slot costs a character and buys nothing. Meanwhile Engineering — the busiest
department in a product whose whole subject is building software — is voiced by Crash, and
Byte, whose `lensGuide` is data flow, state management, algorithm choices and what could be
automated, speaks for nothing.

The decision: **Byte takes Engineering. Crash takes Finance. Codepet is the host.**

## 0. The model, stated once

> Codepet represents the host when the founder is in general conversation. The individual pets
> represent each department.

This is not new. `CopilotChatView.headerName` already implements exactly it, and its doc
comment records the day it was settled (5 Aug): a general reply signs `CodepetBrand.name` —
`"Codepet"` — and a pet's name appears *only* when that pet is doing the work, carried on
`message.companionId`. What is new is that the rest of the codebase will agree with it.

Three places currently disagree, and each is a section below.

## 1. The cast

`DepartmentCompanions.map`, two entries:

| Dept key | Now | After |
|---|---|---|
| `eng` | `crash` | **`byte`** |
| `fin` | `sage` | **`crash`** |

Unchanged: `design`→`luna`, `mkt`/`sales`→`nova`, `support`→`sage`, `ops`/`legal`→`glitch`.

Six voices across eight roster departments. Nova still covers Marketing and Sales, Glitch still
covers Operations and Legal; Sage drops to Support alone. The repeat remains deliberate —
`DepartmentRoster.chip`'s doc comment calls it "a fact about the cast worth showing rather than
hiding," and that stays true at six.

**A flag, recorded because it was raised and overruled rather than missed.** Crash is "The
Brawler Bug" — ships now, doesn't overthink. The `fin` line in the map today reads *"analytical
— real data, not vibes,"* which is lifted from Sage's own persona copy in `Character.swift`.
Crash on Finance is a weak persona fit on its face. The founder's call; implement it. But the
inline rationale must be **rewritten**, not carried over — leaving Sage's reasoning attached to
Crash's entry would make the map lie about why the cast is what it is, which is the one thing
that file is for.

## 2. Byte gets its name back

`Character.swift:36` — `name: "Codepet"` becomes `name: "Byte"`.

The `id` stays `"byte"`. Nothing in Firestore moves: `actor:'byte'`, `companionId`,
`PetCharacter.starters`, `imageName` → `char-byte` are all keyed on the id and are untouched.

This reverses the July display-name rename for this character only. The reason the rename
happened — the product should say "Codepet" when it addresses the founder — is *preserved*, and
in fact strengthened: §5 makes the host surfaces say Codepet on purpose instead of by accident.

Without this rename, a handed-off Engineering reply would render `"Codepet · Engineering"`
while a general reply renders `"Codepet"`, making the product's own voice and one department
indistinguishable by name. That is precisely the failure `headerName`'s comment describes and
reverses.

## 3. The host rule comes out

Delete `DepartmentCompanions.specialistId(for:host:)`. Callers use `companionId(for:)`.

The rule returns nil whenever a department's pet **is** the founder's own companion. With
`byte` mapped to `eng` and every founder hosting `byte`, Engineering would become the single
department that shows the orb and never signs a reply — the exact opposite of this change's
purpose, arriving through it.

The rule's stated premise does not hold and never did: *"announcing a handoff to yourself says
nothing"* assumes the host signs replies with the pet's name. It does not. `headerName` returns
`CodepetBrand.name` whenever `message.companionId` is nil, which is every general turn. There is
no self-handoff to look silly.

Nothing downstream depended on the suppression. `companyChatCore.ChatRequestBody` already
splits `companion_id` (who speaks) from `dept_key` (what they know), and its comment names this
very case: *"They come apart when a department's pet IS the founder's own companion — no handoff
to announce, but still a question that needs that department's expertise."* `CompanyStore` was
already split to match (`actingDeptKey` is separate from `actingSpecialist`, after the bug where
a Nova-hosting founder asked Marketing a question and the model was told nothing about
marketing). So suppression only ever hid **attribution**, never expertise.

Three call sites: `CompanyStore.actingSpecialist`, `DepartmentRoster.chip`, `ChatComposer`'s
department chip.

**Consequence, stated plainly.** A founder who picks Nova in Settings will now see
`"Nova · Marketing"` sign a Marketing reply, where today the turn stays with the host. Under the
model in §0 that is correct: Nova speaks for Marketing regardless of who the founder's own
companion is. The department is the new information in that header, and it is information the
suppressed version threw away.

`DepartmentRoster`'s `CompanionOrb` fallback stays. Every roster department now maps to a pet,
so the branch is unreachable from the roster today — but it is the correct rendering for a
department with no pet, and Product is exactly that the moment it is unfiltered.

## 4. The invariant that must survive

`DepartmentCompanions.swift` states it and it is the reason `specialistId` existed as one
function rather than two call-site conditionals:

> A chip promising a pet that the send then declines to hand off to is a lie the founder can see
> in one tap.

Deleting the host parameter keeps this invariant — it does not weaken it. Both the chip and the
send now read the same unconditional `companionId(for:)`, so they cannot disagree at all. The
rejected alternative was to split display from handoff (roster always shows the pet, chat keeps
suppressing), which would have broken this invariant outright.

## 5. The rename's blast radius

Three surfaces render the *companion's* name and say `"Codepet"` today only because `byte`
happens to be named that. Renaming `byte` flips all three to `"Byte"` unless they are fixed in
the same change. Each becomes `CodepetBrand.name` unconditionally:

- `ChatEmptyState.swift:150` — `hostName`, the empty-state greeting. Named `hostName` already;
  it just wasn't reading the host.
- `CopilotChatView.swift:2029` — `whatItDid`, which falls back to `company.companionId` when a
  run carries no specialist. A hostless run is the product's own work, so it reads "Codepet".
**[A2] `SecondBrainData.swift:55` — withdrawn. It was never a host surface.**
`SecondBrainPanel.swift:45` renders it under the label **"Companion"** / *"Bạn đồng hành"*. That
is `company.companionId` doing its own job — the founder's chosen companion, the same axis as the
menu-bar pet and the tips persona — not the product's voice. It stays as it is.

The rename does change what that row says for a default founder, from "Codepet" to "Byte", and
that is the correction, not the damage: the row is supposed to name their companion, and their
companion is the Byte character. It also makes `SecondBrainDataTests.testCompanionNameResolves`
better than it was — its comment currently excludes byte as a test case *because* its name "literally
IS 'Codepet'", indistinguishable from the `?? "Codepet"` fallback. After the rename it is
distinguishable. Only that comment needs updating; both assertions still hold.

The general rule this mistake illustrates, worth stating since the same call shape appears at
five sites: `PetCharacter.all[company.companionId]?.name` is **correct** wherever the surface
means "the founder's companion" and **wrong** wherever it means "who is speaking to the founder
right now". Read the label above the value before deciding which one a site is.

**[A1] `DepartmentMenu.swift:50` — `anyoneLabel`, and this one is worse than the other three.**
It is not a name resolved from data; it is a hardcoded user-facing string naming the host in
prose: `"Anyone — byte routes it"` (vi: `"Ai cũng được — byte tự chọn"`). It is the composer
menu's "no department" row. After this change "byte" names Engineering's pet, so the row would
tell the founder that the Engineering character routes everything — the opposite of what it
means. It becomes `"Anyone — Codepet routes it"` / `"Ai cũng được — Codepet tự chọn"`.

The adjacent `anyoneDetail` already reads *"Let Codepet pick who answers"* — so these two lines
about the same control already disagree today, and this change is what makes the disagreement
visible. (`anyoneDetail` has no callers; it is left alone rather than deleted, since removing it
is unrelated to this work.)

Not affected: `ChatExecLog.swift:27` and `AgentsWorkingRow.swift:44` read `persona?.name`, where
`persona` is the specialist. Their `?? "Codepet"` fallback is already the host case and is
already right.

Also not affected, verified rather than assumed: the voice recognizer's `contextualStrings`
(`CopilotChatView.swift:570`, `:652`) is
`DepartmentCatalog.roster.map(\.name) + PetCharacter.all.values.map(\.name) + ["Codepet"]`.
The rename swaps `"Codepet"` for `"Byte"` inside the pet names, but `"Codepet"` is appended
explicitly, so the recognizer still receives both words. No change needed.

`PetVoice.profile` keeps byte on the `default` branch, which is also the unknown-pet fallback, so
Byte's speaking voice is unchanged. Only its comment ("byte, the host") goes stale and is
corrected.

**Dead code removed in passing:** `CopilotChatView.swift:1203` `companionName` has no readers —
only the adjacent `companionAccent` is used. It is one of the sites that would silently flip to
"Byte", and deleting it is cheaper and safer than fixing something nothing renders.

## Testing

Existing tests assert the old cast and must move with it:

- `DepartmentCompanionsTests.swift:9–22` — `specialistId` assertions, including
  `specialistId(for: "mkt", host: "nova")` being nil, which is the rule being deleted, and
  `companionId(for: "eng") == "crash"`.
- `TwoModeHeroTests.testEveryRosterDepartmentHasAPetToSpeakForIt` — drops the `host` argument.
- `TwoModeHeroTests.testTheCastIsSmallerThanTheRoster` — the expected set becomes
  `["byte", "luna", "nova", "sage", "crash", "glitch"]`, six. Its doc comment says "Four pets"
  while the assertion says five; fix the comment to six so it stops drifting.
- `PetMenuIconTests.swift:27` — `private let pets = ["crash", "luna", "nova", "sage",
  "glitch"]`, a hardcoded list whose comment claims it is "every pet the roster can summon, per
  `DepartmentCompanions`." It is not, and after this change it would be wrong by one. Derive it
  from `Set(DepartmentCatalog.roster.compactMap { DepartmentCompanions.companionId(for: $0.key) })`
  so the comment becomes true and the list cannot drift again. `char-byte.imageset` already
  exists, so Byte's sprite needs no new asset.

New coverage, both regression-shaped:

1. **Engineering resolves to Byte for the default founder.**
   `companionId(for: "eng") == "byte"`, and the roster chip for `eng` renders a pet rather than
   the orb with `company.companionId == "byte"`. This is the whole reason §3 exists; without it
   the next person to reintroduce a host rule breaks Engineering silently.
2. **The host is still called Codepet after the rename.**
   `ChatEmptyState.hostName == "Codepet"` and a general (`companionId == nil`) message's
   `headerName == "Codepet"`, with `company.companionId == "byte"` and
   `PetCharacter.all["byte"]!.name == "Byte"`. This is the assertion that catches §5 being
   half-applied — the failure mode where the greeting starts saying "Byte".
3. **`PetCharacter.all["byte"]!.id == "byte"`** after the rename, guarding the schema.

Verification runs the full suite, not `-only-testing:` — a `-only-testing:` branch is an
untested branch, and this change touches the chat header, the empty state, the composer, the
roster and the run receipt.

## Out of scope

**Product still has no pet, and its art is still a placeholder.** `dept-product.png` is
md5-identical to `dept-eng.png` (`2884fd62d49260f46effc8074aa60841`, verified 26 Aug), which is
why `DepartmentCatalog.roster` filters Product out and why the roster shows eight of nine
departments. That remains the launch-blocking gap and this change does not touch it. It is
mentioned here only so the six-voices-over-eight-departments count in §1 is not mistaken for
full coverage of the catalog.

**The Settings companion picker keeps its current meaning.** `company.companionId` still drives
`appState.activeChar` — the menu-bar pet, tips, and the guidance persona. What it no longer does
is decide who speaks for a department. Those are separate axes, and this change is what
separates them.

**No backend change.** The pet↔department map lives only in the Swift client.
`functions/src/departments.ts` expertise is keyed by department and is pet-agnostic;
`companyChatCore` takes `companion_id` and `dept_key` as independent fields it already handles.
