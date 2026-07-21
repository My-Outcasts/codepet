# Splash + Onboarding — Faithful Web Port — Design Spec

**Date:** 2026-07-21
**Context:** The native macOS app is now the web product (Stage 1 on `main`, PR #5). Its splash is the old game-framed pixel-cast screen ("Meet Your Pet"), and its first-run onboarding is a bare 6-field text wizard (`CompanyOnboardingView`). The web app (`~/Desktop/Codepet v1.2`) has a dark cinematic splash and a cinematic 8-step onboarding. The user wants the native splash + first-run onboarding to reuse the **exact web design**, replacing the current native versions.
**Goal:** Replace the native splash and first-run onboarding with faithful, English-only ports of the web `Splash` + `Onboarding`, wired to the native `CompanyStore`/`CompanyBrief`. View-layer work only — the data model already matches.

---

## Approved decisions (brainstorming)
1. **Faithful cinematic port**, replacing the current native splash + first-run onboarding.
2. **English-only** — port the web copy verbatim; do NOT add Vietnamese. (Deliberate exception to the app's VI/EN convention; the onboarding is an EN island.)
3. **Exact web splash** — the dark cinematic splash (`#100a26` + `splash.jpg` Ken Burns + scrim + white pixel title + purple pill button). Removes the native bouncing pixel-cast **and** its `SoundManager.playSplashIn()` call.
4. **Step 6/7 fail-open** — the analysis step runs the native fail-open scaffold; with the `scaffoldRoadmap` CF undeployed it returns no tasks, so the reveal falls back to generic value-props. Ship it now.
5. **Cold-open department chips ported exactly** (8 names) though the native Overview is phase-based, not department-based — cosmetic hero copy, accepted minor incongruity.
6. **Settings "edit brief" keeps the existing 6-field `CompanyOnboardingView`** — the cinematic flow is first-run only; the old view survives solely as the Settings brief editor (not deleted, not shown at first run).

## What already exists (no change needed)
- `codepet/Models/CompanyBrief.swift` — already a verbatim port of the web schema: holds `founderName, role, tech, stage, projectName, oneLiner, summary, notes, link, categories, audience`. The web wizard collects a subset of these; all fields are present.
- `CompanyStore` — `finishOnboarding(brief:token:)` (persist + stamp `onboardedAt` + leave onboarding), `skipOnboarding()`, `generateRoadmap()` (fail-open; scaffolds from the **already-persisted** `company.brief`), `isOnboarding`/`needsOnboarding`, `hydrationToken`.
- `ContentView` routing gate: `authed → isOnboarding ? OnboardingView : AppShellView`. The gate condition is unchanged; only the view it presents changes.

---

## Source of truth (web) — port these
- **Splash:** `components/Splash.tsx` + `app/globals.css` `.splash*` (lines ~3122–3305). Dark cinematic: `background:#100a26`; `::before` = `/splash.jpg` Ken Burns (`kenburns 30s alternate`); `::after` = readability scrim (dark linear + radial vignette); `.splash-title` = pixel font 80px `#fff`, letter-spacing 2, layered text-shadow + purple glow; `.splash-sub` = 20px `#fff`; `.splash-btn` = purple pill `#7c3aed`, radius 999, `12px 30px`, white 14px 600; `.splash-hint` = "click anywhere to continue" 11.5px bottom. Copy: title **"Codepet"**, sub **"Let's learn how to run your company with AI."**, button **"Let's go"**. Click anywhere OR the button → continue.
- **Onboarding:** `components/Onboarding.tsx` (569 lines) + `app/globals.css` `.ob*`, `.obopt*`, `.obchip*`, `.stagebar`/`.sb-*`, `.ob-an`, `.val`/`.vrow` blocks. Constants in `lib/data.ts` (`OB_ROLES`, `OB_TECH`, `OB_STAGES`, `OB_NOTES`, `OB_CATEGORIES`, `OB_TOTAL=8`, `DEPTS`). Reveal helper in `lib/onboarding/firstRun.ts` (`buildRevealSummary`).

### Ported constants (exact web values)
- **OB_ROLES** (label, key): Founder building a product/`founder`; Engineer / developer/`eng`; Designer who codes/`design`; Product manager/`product`; Marketing / growth/`mkt`; Operations / business/`ops`; Solo / indie hacker/`solo`; Something else/`other`.
- **OB_TECH:** I write the code myself/`hands`; I direct engineers / build with AI/`direct`; I'm not on the technical side/`non`.
- **OB_STAGES (6):** Just an idea · Prototype · Private beta · Public beta · Launched · Growing. Default index 2 (Private beta).
- **OB_NOTES (6):** one per stage (verbatim from `lib/data.ts`).
- **OB_CATEGORIES (8):** Web app · Mobile app · SaaS · Dev tool · AI / ML · Marketplace · Game · Other.
- **DEPTS (8, cold-open chips):** Engineering(`eng`) · Marketing(`mkt`) · Operations(`ops`) · Finance(`fin`) · Legal(`legal`) · Design(`design`) · Sales(`sales`) · Support(`support`). Per-chip dot colors from web `DEPT_DOT`.
- **STEP_ART (per-step, 7 unique used):** 0 & 7 `ob-team`, 1 `ob-couch`, 2 `ob-chess`, 3 `ob-drummer`, 4 `ob-observatory`, 5 `ob-isometric`, 6 `ob-boardroom`. (`ob-vortex` unused.)
- **AN_LINES (analysis):** "Reading what you told me…" · "Mapping it across 8 departments" · "Cross-checking your space & stage" · "Drafting your roadmap to launch".

---

## Architecture / components (new native files)

- **`codepet/Views/SplashView.swift`** (rewrite) — dark cinematic splash. `ZStack`: `Color(hex:"#100a26")` + `Image("splash")` (`.scaledToFill`, slow Ken-Burns scale/offset via `withAnimation(...repeatForever(autoreverses:true))`, `prefers-reduced-motion` ⇒ static) + dark scrim `LinearGradient`/`RadialGradient` overlay + centered `VStack` (pixel title 80pt white with glow `shadow`, subtitle, purple pill "Let's go") + bottom "click anywhere to continue" hint. Whole surface + button call `onContinue`. No `SoundManager`. Keeps the existing `SplashView(onContinue:)` API so `ContentView` is unchanged.
- **`codepet/Models/OnboardingContent.swift`** — the ported constants above as Swift statics (`OBRole`, `OBTech` as `(label,key)` tuples/structs; `stages`, `stageNotes`, `categories`, `departments` with dot colors, `stepArt`, `analysisLines`, `total = 8`). Pure data, unit-testable for shape.
- **`codepet/Models/OnboardingReveal.swift`** — pure builder **adapted to the native task model**:
  ```
  struct OnboardingReveal { let ok: Bool; let taskCount: Int; let sampleTasks: [String] }
  static func build(tasks: [RoadmapTask]) -> OnboardingReveal
  ```
  `ok = !tasks.isEmpty`; `taskCount = tasks.filter{ !$0.done }.count`; `sampleTasks` = first ≤3 not-done task titles. Empty ⇒ `ok=false` ⇒ view shows the generic 3 value-props. Unit-tested.
- **`codepet/Views/Onboarding/OnboardingView.swift`** — the flow controller. Holds `@State step` (0–7) + a local `ObDraft` (name, role+roleLabel, tech, projName, oneLiner, categories, audience, link, notes, stageIndex) and `@State reveal`. Renders the cold-open (step 0, full-bleed) distinctly; steps 1–7 render inside the two-panel `obcard` (art left / form right) with the "Step N of 8" footer, Back, and a persistent "Skip onboarding →" that calls `skipOnboarding()`. Builds a `CompanyBrief` from `ObDraft` (mirrors web `briefFromData`).
- **Sub-views** (split for size/clarity):
  - `codepet/Views/Onboarding/OnboardingColdOpen.swift` — full-bleed hero: "Let's build your company — **not just your code.**", body copy, "Codepet runs all 8 departments" + dept chips, "Set up my company" → step 1.
  - `codepet/Views/Onboarding/OnboardingOptionList.swift` — numbered option rows (`01/02/03…` + label + selected ✓), used by role (step 2) and tech (step 3).
  - `codepet/Views/Onboarding/OnboardingStageSlider.swift` — custom draggable slider (drag + arrow keys) over 6 stages with major/minor ticks, thumb, and the active-stage note; mirrors web `StageBar`.
  - `codepet/Views/Onboarding/OnboardingAnalysisView.swift` — step 6 streaming lines (checkmark rows, one "live") + "See what I found" gate + "Still building your company…" slow affordance.
  - `codepet/Views/Onboarding/OnboardingRevealView.swift` — step 7 "Here's your company, {name}." + task rows (`✦`) from `OnboardingReveal`, or the 3 generic value-props when `!ok`.
  - The two-panel frame + footer live in `OnboardingView` (or a small `OnboardingCard` helper).
- **Assets:** `codepet/Assets.xcassets/Onboarding/` — imagesets `splash`, `ob-team`, `ob-couch`, `ob-chess`, `ob-drummer`, `ob-observatory`, `ob-isometric`, `ob-boardroom` (copied from web `public/splash.jpg` + `public/onboarding/ob-*.jpg`).
- **`codepet/Managers/CompanyStore.swift`** — add `scaffoldFromOnboarding(brief:token:) async -> OnboardingReveal`:
  ```
  guard token == hydrationToken, let cid = companyId else { return OnboardingReveal.empty }
  _ = await saver(cid, brief)                 // persist brief so generateRoadmap reads it
  guard token == hydrationToken else { return .empty }
  company.brief = brief
  await generateRoadmap()                      // fail-open; no-op on empty
  return OnboardingReveal.build(tasks: company.tasks)
  ```
  Does NOT touch `isOnboarding` (the wizard stays up for the reveal). Token-guarded against account-switch races. Step 7's "See my company" calls the existing `finishOnboarding(brief:token:)` (idempotent re-persist + `onboardedAt` + leave). "Skip" calls `skipOnboarding()`.

## Data flow
`ObDraft` (collected in the view) → `CompanyBrief` → **step 6** `scaffoldFromOnboarding(brief:token:)` persists + scaffolds fail-open, returns `OnboardingReveal` → **step 7** renders reveal → "See my company" `finishOnboarding(brief:token:)` → `isOnboarding=false` → `ContentView` shows `AppShellView`. Token captured before the step-6 await; an account switch mid-scaffold discards (store guards).

## Error handling / fail-open
- Step 6 mirrors the web timing: play `analysisLines` on a fixed cadence AND run the scaffold; "See what I found" unlocks only when BOTH the animation finished and the scaffold resolved. A "Still building…" affordance appears if the scaffold runs long; a hard safety timeout always releases the founder to the reveal. (Native uses async/await + a min-duration `Task.sleep`, not JS timers.)
- Empty/failed scaffold ⇒ `OnboardingReveal.ok == false` ⇒ generic value-props. No error surfaced — matches the app-wide fail-open contract.
- "Skip onboarding →" available on every step (including cold-open) ⇒ `skipOnboarding()`.

## Testing
- **Unit:** `OnboardingReveal.build` (empty ⇒ !ok; N not-done ⇒ taskCount N + ≤3 sample titles; done tasks excluded from samples/count); `OnboardingContent` shape sanity (stages↔notes count parity = 6; 8 departments; 8 categories; step-art indices 0–7 resolve).
- **Build-verified (native convention for SwiftUI views):** SplashView, OnboardingView + sub-views compile and render; `xcodebuild build` green.
- **Store:** `scaffoldFromOnboarding` — persists brief, sets `company.brief`, returns a reveal from resulting tasks, leaves `isOnboarding` untrue-unchanged, and discards on token mismatch (injectable saver/roadmapFetcher like the existing tests).

## Out of scope
- Vietnamese translation of the onboarding/splash (decision 2).
- Deploying `scaffoldRoadmap` (the reveal stays fail-open until then — separate work).
- Departmentizing the native product (Overview stays phase-based; cold-open chips are cosmetic).
- The Settings edit-brief editor (unchanged — keeps `CompanyOnboardingView`).
- `buildFirstRunGreeting` / byte's landing greeting (web `firstRun.ts` also has this; not part of the splash/onboarding surface — defer).

## Constraints
- Don't touch Giang's Build Coach files. Worktree `~/Documents/codepet-rebuild-wt`, new branch off current `origin/main` (`108b240`). Toolchain: scheme `codepet` lowercase, FOREGROUND `xcodebuild`, SourceKit cross-file diagnostics are false positives; iCloud git → `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`, `rm` the worktree `index.lock` on hangs.

## Open decisions
None — fidelity (faithful), language (EN-only), splash (exact dark cinematic), step-6/7 (fail-open), dept chips (exact), Settings editor (kept) all resolved in brainstorming. Ready for implementation planning.
