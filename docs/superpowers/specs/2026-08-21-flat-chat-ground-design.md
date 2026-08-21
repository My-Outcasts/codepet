# Flat chat ground, gradient only on elements

**Date:** 2026-08-21
**Branch:** `feat/composer-controls`
**Status:** approved, not implemented

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

```swift
/// The brand ramp. Purple into pink, top-leading to bottom-trailing — extracted
/// from the composer's send button so every gradient in the product is the same
/// gradient. Both stops are `Color.dyn`, so light and dark need no branch here.
static let brandGradient = LinearGradient(
    gradient: Gradient(colors: [accentPurple, accentPink]),
    startPoint: .topLeading, endPoint: .bottomTrailing)
```

The send button and the composer's container edge consume it directly.

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
| ASK/DEVELOPER active pill | `CopilotChatView.swift:766` | **stays flat**; fill `0.08` → `~0.18` |

`"build"` is one five-letter word at `title2`, roughly 55pt wide. The purple-to-pink
ramp across it resolves to a single warm-shifted violet: a hue change, not a
gradient. And that headline is assembled by `Text` concatenation
(`acc + Text(seg.text)`), where `foregroundStyle` with a gradient resolves its
coordinate space inconsistently across runs and can silently render flat. New
render path, no visible gain, a real silent-failure mode.

The active pill is smaller still, and at `@0.08` fill the ramp has nothing to
show. Raising the flat opacity toward `0.18` is the change that is actually
visible on flat ground, and it carries no risk.

The rule this encodes, for the next person adding a gradient: **gradient where
there is area, stronger flat accent where there is not.**

### The composer edge, in both states

The container today is `focus ? accent.opacity(0.65) : CodepetTokens.cardEdge`.
`cardEdge` is `#ece9e2` in light — against cream `#f8f7f3` that is a hairline of
almost no value, and it was the ambient wash doing the separating. So the resting
state is where this change matters, and leaving it at `cardEdge` would be the
regression this design set out to avoid.

Both states take `brandGradient`, differing only in opacity: **`0.35` at rest,
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
| `codepet/Views/Copilot/CopilotChatView.swift` | drop `.background(ChatBackdrop())` (:173); active pill fill `0.08` → `0.18` (:766) |
| `codepet/Views/CodepetTheme.swift` | add `brandRamp` + `brandGradient` |
| `codepet/Views/Copilot/ChatComposer.swift` | send button onto the token (:634); container edge → `brandGradient` @0.35 rest / 0.9 focus (:178) |
| `codepet/Views/Copilot/ChatEmptyState.swift` | `brandMark` aura → radial `brandRamp`, purple → pink → clear (:122) |
| `codepet/Views/Copilot/MessageCard.swift` | correct the comment at :18 reasoning about "a translucent tint over ChatBackdrop's wash" — false once the wash is gone |
| `codepetTests/BrandMarkRenderTests.swift` | corner-flatness assertions, dark and light |

## Out of scope

- The warm cast of `pageBackground` (`#16130f` is brownish, which can read muddy
  under a purple-pink element). Changing it touches every surface token in the app.
  Noted, not proposed.
- The cinematic entry screens' washes.
- The roster chips' per-department accents.
