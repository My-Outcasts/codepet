# Flat chat ground, gradient only on elements

**Date:** 2026-08-21
**Branch:** `feat/composer-controls`
**Status:** approved, not implemented
**Amended:** 2026-08-22 — three addresses in the first draft were wrong. Corrections
are marked **[A1]**, **[A2]**, **[A3]** below and were found while writing the
implementation plan, by reading each site instead of trusting the grep that found it.

## The problem

The chat surface carries an ambient purple radial wash. On screen it reads as a
violet blob in the middle of a near-black pane — a decoration competing with the
hero it sits behind, and the founder's own read of it was that the background
should just be the background.

It is also unconditional. `ChatBackdrop` has no `colorScheme` check, so it paints
`accentPurple @0.16` over the cream `pageBackground` (`#f8f7f3`) in light mode
too. That is not a light-mode bug to fix separately; it is the same view.

## Decision

The ground goes flat in both modes. Purple survives only on **elements**, where
it does the job of making a control findable rather than the job of decorating a
pane.

The corollary that makes this safe: a flat ground gives elements *less* help, so
the elements that matter have to get louder in the same change. Removing the wash
without that is a legibility regression, not a cleanup — most of all in light
mode, where cream offers a card almost no separation.

## Two purple sources, not one

Worth stating because they are easy to conflate on screen:

| | Site | Values | Fate |
|---|---|---|---|
| Page wash | `ChatBackdrop.swift:13`, applied at `CopilotChatView.swift:173` | `accentPurple @0.16`, radius 420, blur 60 | **deleted** |
| Mark aura | `ChatEmptyState.swift:122` (`brandMark`) | `accentPurple @0.34`, radius 46, blur 18 | **kept**, becomes a gradient |

The aura stays because it is an element glow, not ambience. Its own code comment
records why it exists: the hero draws no white disc under the mark, so the bloom
is what keeps the glyph from sitting flat and stands in for the bloom the orb used
to cast. Killing the wash and the aura together would take the mark's only ground
with it.

## Scope

`ChatBackdrop` is the only ambient purple wash on a working product surface. The
other five `RadialGradient` washes are deliberately out of scope:

- `SplashView`, `OnboardingColdOpen`, `ReturningSignInView`, `PortalTransitionView`
  — cinematic entry screens. The wash there is the art direction, not a leak of it.
- `SessionsView`, `KingdomInteriorView` — legacy kingdom screens, tinted by
  `kingdom.accentColor`, not brand purple.

## Architecture: one gradient device

A brand gradient already exists, inline on the composer's send button
(`ChatComposer.swift:634-641`): `LinearGradient([accent, accent2],
.topLeading → .bottomTrailing)`, purple to pink. This change extends that one
device rather than inventing a second.

It is lifted to a token beside the accent colors:

**[A1] The composer's two sites cannot consume a hard-coded brand ramp.**
`ChatComposer` already receives `accent` and `accent2` as parameters, and
`CopilotChatView.swift:277` passes `accent: companionColor` —
`PetCharacter.all[companionId]?.color ?? accentPurple` (`:92-94`). The composer's
ramp is the **active companion's** hue, purple only as a fallback. Hard-coding
brand purple there would erase a deliberate personalization: precisely the mistake
this spec refuses for the roster chips, one file away.

So the shared thing is not a fixed gradient but a **constructor**, with the hue
pair injected:

```swift
/// The house ramp. Any two-stop brand gradient in the product is this function —
/// one geometry, one direction, hues supplied by the caller, so a companion-tinted
/// ramp and the brand ramp can never disagree about anything but their colors.
static func ramp(_ a: Color, _ b: Color) -> LinearGradient {
    LinearGradient(gradient: Gradient(colors: [a, b]),
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}
```

The send button and composer edge call `ramp(accent, accent2)` — companion-aware.
The hero mark is Codepet's logo rather than any companion, so it alone uses the
brand pair.

**The aura cannot.** `brandGradient` is a `LinearGradient`, and the mark's bloom
is radial — filling a radial bloom with a linear ramp would change its shape, not
its color. So the ramp is exposed as a hue pair the two forms share, and the aura
builds its own radial from it:

```swift
/// The two stops the brand ramp is made of. Exposed separately because a radial
/// bloom must stay radial — a `LinearGradient` cannot fill one without changing
/// its shape — so both forms of the ramp read from one pair of colors.
static let brandRamp: [Color] = [accentPurple, accentPink]
```

A `brandGradient` constant is deliberately **not** added: after [A1] every linear
consumer injects its own pair, so a fixed one would ship with zero call sites.

The aura becomes `RadialGradient([accentPurple.opacity(0.34),
accentPink.opacity(0.18), .clear], startRadius: 0, endRadius: 46)` — same hue
pair, same reading order, radial geometry preserved. Its existing opacity, radius,
and blur are unchanged; only the middle stop is new.

Rejected alternative: defining a
gradient at each of the four sites. Four independent definitions drifting apart
is exactly what produced the roadmap accent collision — red text on violet fill,
still on main — because three token systems disagreed with no single source.

Also rejected: keeping `ChatBackdrop` as a flat base fill. `TwoModeShellView.swift:57`
already fills `pageBackground`, so that is redundant chrome wearing the name of
the thing it replaced.

## Gradients go where there is area

A gradient needs distance to resolve. This is the one place the design does not
apply the device uniformly, and the reason is measurable, not aesthetic:

| Target | Site | Treatment |
|---|---|---|
| C mark aura | `ChatEmptyState.swift:122` | radial form of the ramp (see below) — 92pt of blurred area traverses it |
| Composer edge | `ChatComposer.swift:178` | `brandGradient` stroke, both states (see below) — a long path traverses the full ramp |
| Send button | `ChatComposer.swift:634` | already the ramp; refactored onto the token |
| `"build"` | `ChatEmptyState.swift:155` | **stays flat** `accentPurple` |
| ASK/DEVELOPER active pill | `TwoModeSidebar.swift:153-181` **[A2]** | **stays flat**; gains a purple fill tint + purple edge |

`"build"` is one five-letter word at `title2`, roughly 55pt wide. The purple-to-pink
ramp across it resolves to a single warm-shifted violet: a hue change, not a
gradient. And that headline is assembled by `Text` concatenation
(`acc + Text(seg.text)`), where `foregroundStyle` with a gradient resolves its
coordinate space inconsistently across runs and can silently render flat. New
render path, no visible gain, a real silent-failure mode.

The active pill is smaller still, so the ramp has nothing to show there either.

**[A2] The pill's address and its current state were both wrong in the first
draft.** `CopilotChatView.swift:766` is a *thread row* in the history list, not the
mode switch; it keeps its `0.08` and is out of scope. The real control is
`modeSwitch` in `TwoModeSidebar.swift:153-181`, and it has no purple fill to raise:
the active segment is `CodepetTokens.cardRaised` filled, `CodepetTokens.cardEdge`
stroked, with `accentPurple` **text**. The purple is already at full strength and
already the only purple there.

So "strengthen the flat purple" means giving the active segment purple *body*
rather than raising a number that does not exist:

- fill: `cardRaised`, overlaid with `accentPurple.opacity(0.10)`
- stroke: `accentPurple.opacity(0.45)` in place of `cardEdge`
- text: `accentPurple`, unchanged

The inactive segment is untouched. This keeps the "raised card in a well" pairing
the code comment defends — the card is still raised, it is now tinted.

The rule this encodes, for the next person adding a gradient: **gradient where
there is area, stronger flat accent where there is not.**

### The composer edge, in both states

The container today is `focus ? accent.opacity(0.65) : CodepetTokens.cardEdge`.
`cardEdge` is `#ece9e2` in light — against cream `#f8f7f3` that is a hairline of
almost no value, and it was the ambient wash doing the separating. So the resting
state is where this change matters, and leaving it at `cardEdge` would be the
regression this design set out to avoid.

Both states take the ramp, differing only in opacity: **`0.35` at rest,
`0.9` focused.** One stroke definition, one number changing — not two treatments
that could drift into reading as two different controls.

## What the roster chips do NOT get

The eight department chips (`DepartmentRoster.swift:95-97`) are colored by
`dep.accent` — a different hue per department. That per-department hue *is* the
"each department speaks with its own voice" signal the block exists to state.
Painting them brand purple would flatten the one thing they are there to say.
They keep their accents and are untouched.

## Verification

The native app cannot be screenshotted from this machine (Screen Recording
denied), so "the purple is gone" cannot be an eyeball claim. It is a pixel
assertion instead.

**[A3] The guard renders `CopilotChatView`, not the bare hero.** The wash is
applied at `CopilotChatView.swift:173`, so a test that renders `ChatEmptyState`
alone would have flat corners *before* the change and pass without proving
anything. `CopilotChatView` needs only `CompanyStore` and `AppState` (both already
constructed in `AccountSwitchingTests.swift:106`), and its two `ScrollView`s sit on
the transcript and history paths — the empty-hero path has neither, which is what
makes it renderable at all. Asserting on the real composition also means the guard
keeps working: it fails again if anyone re-adds an ambient wash.

`BrandMarkRenderTests.swift` already renders the hero offscreen through
`ImageRenderer` and samples for the violet fill. It gains:

1. **Corner samples equal flat `pageBackground`.** This test fails before the
   change — the corners carry the wash today — and passes after. That ordering is
   the point: it is falsifiable, not decorative.
2. **The mark's aura is still violet.** The existing assertion, unchanged,
   guarding that deleting the wash did not take the bloom with it.

Both run in dark and light. `ImageRenderer` draws nothing inside a `ScrollView`;
the hero is not in one, which is the only reason any of this is measurable.

Light mode gets its own corner assertion rather than being assumed to follow, since
light mode is where the wash was least intended and least reviewed.

## Files

| File | Change |
|---|---|
| `codepet/Views/Copilot/ChatBackdrop.swift` | deleted |
| `codepet/Views/Copilot/CopilotChatView.swift` | drop `.background(ChatBackdrop())` (:173) only — :766 is a thread row, out of scope |
| `codepet/Views/Shell/TwoModeSidebar.swift` | active mode segment: purple fill tint + purple edge (:166-175) |
| `codepet/Views/CodepetTheme.swift` | add `brandRamp` + `ramp(_:_:)` |
| `codepet/Views/Copilot/ChatComposer.swift` | send button onto `ramp(accent, accent2)` (:634); container edge → `ramp(accent, accent2)` @0.35 rest / 0.9 focus (:178) |
| `codepet/Views/Copilot/ChatEmptyState.swift` | `brandMark` aura → radial `brandRamp`, purple → pink → clear (:122) |
| `codepet/Views/Copilot/MessageCard.swift` | correct the comment at :18 reasoning about "a translucent tint over ChatBackdrop's wash" — false once the wash is gone |
| `codepetTests/BrandMarkRenderTests.swift` | corner-flatness assertions, dark and light |

## Out of scope

- The warm cast of `pageBackground` (`#16130f` is brownish, which can read muddy
  under a purple-pink element). Changing it touches every surface token in the app.
  Noted, not proposed.
- The cinematic entry screens' washes.
- The roster chips' per-department accents.
