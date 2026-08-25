# The surfaces go cool: a purple ground for both modes

**Date:** 2026-08-22
**Status:** approved, not implemented
**Prototype:** `https://claude.ai/code/artifact/2f47addb-f056-4684-bc47-4c553f43b63d`

## Why

The app's surface family is **warm** — every dark value is brown-based (`#16130f`,
`#221d17`, `#2f2820`, `#26201a`, `#3c352b`) over cream lights. The prototype's ground is
a **cool near-black purple** (`#121019`). The founder's read, looking at the two side by
side: the prototype's theme colour is the one the product should have.

This also resolves something left open by the flat-chat-ground work. That change put
purple and purple→pink elements — the hero bloom, the composer edge, the active mode
segment — directly onto `pageBackground`. A saturated violet over a brown-black ground
reads muddy, and it was flagged then as the one judgement no pixel assertion reaches.
Cooling the ground is the fix.

## The prototype says the app is dark-only. We are not following that part.

Its palette carries an explicit comment:

```css
/* App tokens — fixed. The product is dark on either page ground. */
```

So the reference has **no light-mode app palette**. Its light values
(`--ground: #f5f3fa`, `--panel: #ffffff`, `--accent: #6a56cf`) belong to the *document
chrome around* the prototype, not the product UI.

The founder wants both modes. Rather than invent a light purple family, light mode takes
**the prototype's own light `:root` values** — same author, same hue family, so the two
modes stay siblings rather than cousins. This is a deliberate divergence from the
reference, recorded here so nobody later "corrects" the app back to dark-only.

## Scope: surfaces and text. Not accents.

**In:** the ground/panel/hairline/text family — the warm neutrals that make purple look
muddy.

**Out, deliberately:** `accentPurple`, `accentPink`, `accentGold`, `accentTeal`,
`accentOrange`, `accentBlue`, `accentGreen`, and all six per-department tint/line triads
(`violet`/`gold`/`blue`/`teal`/`clay`/`rose` × base/tint/line).

Those accents carry **meaning**, not decoration: each department answers in its own hue,
and `DepartmentRoster` keeps `dep.accent` for exactly that reason. Two earlier tasks
refused to overwrite a companion's colour with brand purple; retinting the whole accent
system now would undo the same principle wholesale. If the accents need work, that is its
own spec with its own reasoning.

**Consequence to accept, not hide:** `accentPurple` stays `#7c3aed`/`#9d6bf5` against the
new `#121019` ground, where the prototype pairs its ground with `#a89bf2`. The result
should read far better than it does on brown, but it will not be pixel-identical to the
screenshot. Judge it on screen before deciding whether the accent needs a follow-up.

## The mapping

`✓` = verbatim from the prototype. **derived** = interpolated, because the prototype
defines 6 dark levels and the app has 11 surface and line tokens.

### Dark

| Token | From | To | Source |
|---|---|---|---|
| `CodepetTheme.pageBackground`, `CodepetTokens.page` | `#16130f` | `#121019` | `--app-ground` ✓ |
| `CodepetTokens.surface2` | `#1b1712` | `#171420` | `--app-rail` ✓ |
| `CodepetTheme.surface` | `#221d17` | `#1d1928` | `--app-panel` ✓ |
| `CodepetTokens.cardRaised` | `#26201a` | `#1d1928` | `--app-panel` ✓ |
| `CodepetTheme.hairline` | `#2f2820` | `#2a2438` | `--app-line` ✓ |
| `CodepetTokens.cardEdge` | `#3c352b` | `#3a3350` | `--app-line-2` ✓ |
| `CodepetTheme.primaryText` | `#f4f1ea` | `#f2eefb` | `--app-ink` ✓ |
| `CodepetTheme.bodyText` | `#d8d2c7` | `#cec7e0` | `--app-ink-2` ✓ |
| `CodepetTheme.mutedText` | `#9e9789` | `#8f88a3` | `--app-muted` ✓ |
| `CodepetTokens.faint` | `#6f685c` | `#6b6480` | `--app-faint` ✓ |
| `CodepetTokens.well` | `#26211a` | `#121019` | `--app-ground` ✓ — **inverts**, see below |
| `CodepetTokens.railFill` | `#3a3228` | `#2a2438` | derived — reuses `--app-line` |
| `CodepetTokens.railBorder` | `#574c3f` | `#3a3350` | derived — reuses `--app-line-2` |
| `CodepetTokens.railFillHover` | `#483f33` | `#332c4a` | derived — one step above `line` |
| `CodepetTokens.railBorderHover` | `#6d604f` | `#4a4268` | derived — one step above `line-2` |

### Light

| Token | From | To | Source |
|---|---|---|---|
| `pageBackground`, `page` | `#f8f7f3` | `#f5f3fa` | `--ground` ✓ |
| `well` | `#f1efe9` | `#efecf7` | `--ground-2` ✓ |
| `surface`, `cardRaised` | `#ffffff` | `#ffffff` | unchanged |
| `hairline` | `#ece9e2` | `#e0dced` | `--hairline` ✓ |
| `cardEdge` | `#ece9e2` | `#cdc6e2` | `--hairline-2` ✓ |
| `primaryText` | `#1f1b15` | `#2d2b26` | `--ink` ✓ |
| `bodyText` | `#332e27` | `#4d4859` | `--ink-2` ✓ |
| `mutedText` | `#776f65` | `#746d87` | `--muted` ✓ |
| `faint` | `#a79e92` | `#9a93ab` | `--faint` ✓ |
| `surface2` | `#fcfbf8` | `#faf9fd` | derived — between `ground` and `panel` |
| `railFill` | `#e0dbcf` | `#cdc6e2` | derived — `--hairline-2` |
| `railBorder` | `#bdb5a2` | `#a79ec4` | derived — one step below `hairline-2` |
| `railFillHover` | `#d3ccbc` | `#bcb3d6` | derived |
| `railBorderHover` | `#a89e88` | `#9188b0` | derived |

## The one structural change

Today the app insets by going **lighter**: `well` (`#26211a`) is brighter than `surface`
(`#221d17`), and `cardRaised` (`#26201a`) is within one hex digit of `well` — so the
"raised card in a well" pairing that `TwoModeSidebar.modeSwitch` relies on has almost no
contrast to work with. That is part of why the active mode segment needed purple *body*
added to read as selected at all.

The prototype does the conventional thing: the track is darker (`--app-ground`), the
lifted card is lighter (`--app-panel`). This spec follows it — `well` → `#121019`,
`cardRaised` → `#1d1928` — which gives the mode switch real separation for the first time.

Code comments in `CodepetTokens.swift` and `TwoModeSidebar.swift` currently defend the old
direction ("the pairing main uses wherever something is lifted out of a track"). They are
corrected, not deleted: the conclusion still holds, the direction reverses.

## The rail level the app does not have

Following the mapping literally produces a collision, found in self-review rather than on
screen. `TwoModeSidebar.swift:78` fills the sidebar with `CodepetTheme.surface`, its mode
switch fills the track with `CodepetTokens.well` (`:199`), and the selected segment uses
`cardRaised`. With `surface` and `cardRaised` both landing on `--app-panel`:

```
sidebar   surface     #1d1928
track     well        #121019   ✓ darker, visible
card      cardRaised  #1d1928   ✗ identical to the sidebar
```

The switch would gain a visible track and lose its visible card. The prototype avoids this
with **three** levels — rail `#171420`, track `#121019`, card `#1d1928` — while the app
collapses "sidebar" and "card" into the single `surface` token, so there is no rail level
between them.

**Resolution: give the sidebar its own level.** `TwoModeSidebar.swift:78` changes from
`CodepetTheme.surface` to `CodepetTokens.surface2`, which this spec maps to `--app-rail`.

```
sidebar   surface2    #171420   rail
track     well        #121019   darker than the rail
card      cardRaised  #1d1928   lighter than the rail
```

Three distinct levels, every value verbatim from the prototype, one line changed.

This makes the change **not purely a retint** — it is one deliberate view edit, and the
sidebar will visibly separate from cards where today it shares their colour. That is the
prototype's structure and the reason its mode switch reads correctly without needing purple
body added to it. The rejected alternative was keeping the sidebar on `surface` and pushing
`cardRaised` to a derived `#252036`: no view change, but the sidebar keeps sharing its
colour with every card and `cardRaised` stops being verbatim.

In light mode there is no collision to fix — `surface`/`cardRaised` stay `#ffffff` and
`surface2` becomes `#faf9fd`, so the sidebar sits a shade off white and the card is white.

## Every site that must change

The token files are not the only source of truth. Both of these were found by grepping for
the warm hexes, not by reading the token files:

| File | What | Why it matters |
|---|---|---|
| `codepet/Views/CodepetTheme.swift` | 5 pairs: `pageBackground`, `surface`, `hairline`, `primaryText`, `bodyText`, `mutedText` | primary |
| `codepet/Views/CodepetTokens.swift` | `well`, `surface2`, `faint`, `page`, `cardRaised`, `cardEdge`, `railFill`, `railBorder`, `railFillHover`, `railBorderHover` | primary |
| `codepet/Models/OnboardingContent.swift:82-84` | **duplicate** `surface2`, `well`, `faint` — byte-identical warm hexes | A SECOND source of truth, under a comment claiming these are vars "CodepetTheme doesn't already expose". They are exposed, in `CodepetTokens`. Retint one and not the other and the palette splits. **Collapse them to read from `CodepetTokens`** rather than retinting both — the duplication is the defect. `accentDeep`/`accentTint`/`accentLine` there are also duplicates but are accents, so out of scope; leave them and note it. `coldBg` (`#100a26`) already IS a deep purple and stays. |
| `codepet/Views/Shell/TwoModeSidebar.swift:78` | `CodepetTheme.surface` → `CodepetTokens.surface2` | The one view edit. Gives the sidebar the rail level so the mode switch has three distinct surfaces instead of two. See above. |
| `codepet/Views/CodepetTokens.swift:319-321` | `cardBGHex`, `chipBGHex`, `chipBorderHex` | Roadmap surfaces defined **relative** to the app's: its own comment says the board card is deliberately LIGHTER than both `surface` and `cardRaised`, so cards keep a visible edge. Retinting the app's without these inverts that. New dark values must stay above `#1d1928`: `cardBG` → `#252036`, `chipBG` → `#2f2846`, `chipBorder` → `#403858` (derived). Light: `cardBG` `#ffffff` unchanged, `chipBG` → `#efecf7`, `chipBorder` → `#e0dced`. |

**Out of scope:** `codepet/Views/Home/WorldMapView.swift:243` hardcodes `#F8F7F3` on a
legacy kingdom screen, consistent with those screens being excluded from earlier work.
The web app is a separate repository.

## Verification

Four test files assert against the old palette. All four fail loudly on this change, which
is correct — none of them can drift silently.

| Test | Breaks how | What to do |
|---|---|---|
| `RoadmapPaletteTests.swift:24-33` | Asserts `chipBGHex.light == "#f1efe9"`, `chipBorderHex.light == "#ece9e2"`, `cardBGHex.dark != "#26201a"` | Update the literals. **Keep the relationship assertion** — the board card being lighter than the app surface is the invariant worth testing; the specific hex is not. Prefer strengthening it into a computed-luminance comparison over a new hardcoded value. |
| `BrandMarkRenderTests.swift` | Compares corners against `#16130f` / `#f8f7f3` as literals, and its measured noise floors (dark `0.0597`, light `0.0214`) were taken against those exact colours | Re-measure both floors on the new grounds, then reset the dark threshold to the midpoint of the new floor and the wash distance. **Do not carry `0.072` across** — it was derived from the old pair. |
| `BrandMarkRenderTests.testTheBloomCarriesTheBrandsSecondStop` | Its background-exclusion epsilon (`0.08`) and warm thresholds (RED 8,329 / GREEN 18,285 / threshold 13,300) were all measured against `#16130f`. `#121019` is COOL — blue above red — so the "warm pixel" baseline changes fundamentally, likely dropping sharply | Re-measure RED and GREEN from scratch by real revert/restore. Expect a *larger* separation, since a cool ground no longer registers as warm. If it inverts, say so rather than flipping a comparison to make it pass. |
| `ComposerEdgeRenderTests.swift` | Comments cite `#ece9e2` on `#f8f7f3`; the `cardEdge` saturation claim (`~0.04`) and the resting-edge measurement (`0.199`) were taken on cream. The brightness floor (`>0.5`) is documented as depending on `cardRaised` being `#ffffff` — which **stays** `#ffffff`, so that dependency survives | Re-measure the resting saturation and the `cardEdge` baseline. Confirm the documented brightness-floor assumption still holds and update the comment with the new numbers. |

**No pixel threshold in the implementation plan may be written by hand.** Six were during
the flat-chat-ground work and all six were wrong — the causes were, in order: an unmeasured
noise floor, a background-dominated metric, a full-saturation `Menu` glyph, a dark icon
fill, a crop containing the wrong view, and persisted user state changing the crop. Every
threshold here comes from a measured RED/GREEN pair with both numbers written beside it.

**Then a human looks at it.** The native app cannot be screenshotted from this machine
(Screen Recording denied), so appearance is a handoff. Ask, in both modes:

> Does the ground read purple rather than brown, and is anything now too dark to read?

The second half matters: `bodyText` light moves from `#332e27` to `#4d4859`, which is
*lighter*, and `mutedText` light from `#776f65` to `#746d87`. Contrast on cream could drop.

## Out of scope, and named so it is not smuggled in

- Every accent and every department tint triad.
- `accentPurple` specifically, even though it is the hue most affected by the new ground.
- The legacy kingdom screens and `WorldMapView`'s hardcoded cream.
- The web app (separate repository).
- Making the app dark-only, which is what the prototype actually specifies.
