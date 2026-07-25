# Onboarding — Correctness & Clean Data (Design)

_Date: 2026-07-24 · Branch: `feat/onboarding-correctness`_

## Context

The native SwiftUI onboarding (`Views/Onboarding/OnboardingView.swift`, driven by
`Managers/CompanyStore.swift`) is a faithful step-by-step port of the web
reference (`components/Onboarding.tsx` on `develop`). A web↔native audit found
that the **client shells match**, but the first-run path has two correctness/data
divergences from the source-of-truth web app, plus one dead file. This spec covers
only those — it deliberately excludes visual/interaction polish.

Backend note: the AI Cloud Functions are deployed and live on `devpet-8f4b1`
(`enrichBrief`, `generateRoadmap`, etc.). `enrichBrief` is already wired in the
Swift client (`Services/ReflectionAPIClient.swift`) and used by the Settings
edit-brief form — it is simply **not called on the first-run path**.

## Goals

Make the first-run onboarding write **correct, enriched company state** and stop
it from **re-triggering for users the web considers onboarded**, and remove dead
onboarding code.

## Non-goals (explicitly deferred)

- Companion-step reconciliation (native renders a real "Choose your companion"
  step; web `develop` dropped it — a **product decision**, not a bug).
- Visual/interaction polish: name-field autofocus + Enter-to-advance, cold-open
  Starfield/parallax, per-step color-grade overlay.
- Reveal being task-based (native) vs department-based (web) — intentional model
  difference.
- Any change to the deployed Cloud Functions / functions repo.

## Design

### Change 1 — Enrich the brief before roadmap generation (data correctness)

**Problem:** `CompanyStore.scaffoldFromOnboarding` (`CompanyStore.swift:152`)
persists the **raw** brief and calls `generateRoadmap` directly.
`generateRoadmapCore.ts` only *consumes* `summary`/`audience`/`categories` if
present — it does not create them. Web enriches first (web `/api/scaffold` calls
`enrichBrief` before planning). So a native founder who skips the optional project
fields gets a thinner roadmap than the equivalent web user.

**Fix:** In `scaffoldFromOnboarding`, before calling `generateRoadmap`:
1. Call `ReflectionAPIClient.enrichBrief` on the collected brief.
2. **Persist the enriched brief** as the company brief (so downstream generation
   and the Settings editor see the enriched fields).
3. Then call `generateRoadmap` with the enriched brief.

**Fail-open** (match web): if `enrichBrief` throws / times out, proceed with the
raw brief — never block or fail onboarding on enrichment. Preserve the existing
account-switch token guards.

Also fix the now-stale comment in `finishOnboarding` (`CompanyStore.swift:96–100`,
"Enrich already happened in the model") — it was true for the legacy
`CompanyOnboardingModel` path but false for the live `OnboardingView` path.

### Change 2 — Align the onboarding-complete gating predicate (correctness)

**Problem:** `needsOnboarding` (`CompanyStore.swift:69–71`) is:
```
company.onboardedAt == nil && BriefContext.compose(company.brief) == nil
```
`BriefContext.compose` returns nil unless `projectName || oneLiner || summary ||
notes` is non-empty (`BriefContext.swift:15–22`) — it **ignores** `founderName`,
`role`, `tech`, `stage`, `categories`, `audience`, `link`. The web predicate
(`store.tsx:815`) is `Boolean(onboardedAt) || Object.keys(brief).length > 0` —
i.e. **any** brief field present. Consequence: a user with a partial/legacy brief
(e.g. only `role`/`stage`) but no `onboardedAt` stamp is treated as **onboarded on
web but re-onboarded on native**.

**Fix (chosen: match web semantics):** treat a company as onboarded when
`onboardedAt != nil` **OR the brief has any non-empty field**. Introduce a helper
(e.g. `CompanyBrief.hasAnySignal` / `isEmpty`) that returns true when **any** of
`founderName, role, tech, stage, projectName, oneLiner, summary, notes, link,
audience, categories` is non-nil and non-blank (strings trimmed; arrays
non-empty). `needsOnboarding` becomes:
```
company.onboardedAt == nil && company.brief.hasAnySignal == false
```

Edge case to encode explicitly: `stage` receives a default during onboarding.
Matching web (which counts any present key) means a brief carrying only a stage
counts as onboarded. This matches the chosen "match web" semantics; the helper
counts `stage` when non-nil. (Because completed onboarding now also stamps
`onboardedAt`, this fallback matters only for legacy/partial briefs — the exact
case web already lets through.)

### Change 3 — Remove dead onboarding code

- **Delete `Views/Onboarding/OnboardingFlow.swift`.** Confirmed dead: its only
  reference is its own `#Preview { OnboardingFlow() }` (line ~1297); no app or
  test code instantiates it.
- **Keep** `Views/Onboarding/CompanyOnboardingView.swift` and
  `CompanyOnboardingModel.swift` — they are the Settings "edit company brief"
  editor (`SettingsView.swift:32`), not dead. No change.

## Data flow (after changes)

```
OnboardingView (steps 0–8 collect brief)
  -> CompanyStore.scaffoldFromOnboarding(brief)
       -> enrichBrief(brief)            [NEW, fail-open]
       -> persist enriched brief         [NEW]
       -> generateRoadmap(enriched)      [existing]
       -> OnboardingReveal.build(tasks)  [existing]
  -> finishOnboarding: save + stamp onboardedAt + seedFirstRunGreeting  [existing]

Gate: ContentView shows OnboardingView when companyStore.isOnboarding,
      where needsOnboarding = onboardedAt == nil && brief.hasAnySignal == false  [CHANGED]
```

## Testing

- **`CompanyBrief.hasAnySignal` unit tests:** empty brief → false; each single
  non-empty field (incl. `stage`, `role`, `categories`) → true; all-blank strings
  / empty arrays → false.
- **Gating tests (`AppStateProgressGate`/`CompanyStore` style):** onboardedAt set →
  not onboarding; onboardedAt nil + brief with only `role` → not onboarding
  (regression guard for the bug); onboardedAt nil + fully empty brief → onboarding.
- **`scaffoldFromOnboarding` tests (stubbed clients, per existing injectable-closure
  pattern):** enrich success → enriched brief persisted before generateRoadmap is
  called with enriched fields; enrich failure → raw brief used, onboarding still
  completes (fail-open); account-switch token guard still honored.
- ⚠️ Hosted test-suite crashes under Xcode 26.2 (isolated-deinit toolchain bug) are
  a known separate issue — new tests are still authored; runnability tracked apart.

## Files touched

- `codepet/Managers/CompanyStore.swift` — enrich wiring in `scaffoldFromOnboarding`;
  `needsOnboarding` predicate; fix stale comment.
- `codepet/Models/CompanyBrief.swift` — add `hasAnySignal` (or `isEmpty`) helper.
- `codepet/Views/Onboarding/OnboardingFlow.swift` — delete.
- `codepetTests/` — new/updated tests as above.

## Out of scope / follow-ups

- Companion-step product decision (keep native's vs match web) — separate ticket.
- Onboarding visual polish — separate ticket.
