# Onboarding Fidelity — Match the Live 9-Step Web Flow — Design Spec

**Date:** 2026-07-22
**Context:** The native cinematic onboarding was ported from a stale local web source (8 steps, top-aligned questions). The **live** web onboarding (codepet-ver-1-2.vercel.app; `OB_TOTAL=9` on origin/HEAD) is a **9-step** flow with **vertically-centered** questions and byte→Codepet copy. Walking the live flow + reading the current source confirmed the exact deltas.
**Goal:** Bring the native onboarding to match the live web: vertically-centered questions, a 9-step counter, byte→Codepet copy, and a new **"Choose your companion"** step before finish. Inherits the just-added dark theming for free.

---

## Approved decisions (brainstorming / live walkthrough)
1. **Include the new "Choose your companion" step** (the genuine 9th step in the current source).
2. Match the live copy ("Codepet is reading", not "byte").
3. Vertically center the question body (top-align only the tall project step).

## Confirmed live/source structure (9 steps, 0-indexed; counter = `step+1` of 9)
0 cold-open · 1 name · 2 role · 3 tech · 4 project(tall) · 5 stage · 6 analysis · 7 reveal · **8 companion picker**. The counter shows "Step 2 of 9" at name … "Step 9 of 9" at the companion step.

## The four changes (native → live)

### 1. Vertically center the question body
Web `.ob-body { justify-content: center }` centers the heading/inputs in the form panel; the **project step is `.tall`** (`justify-content: flex-start`, scrolls). Native currently top-aligns every step.
- Native fix: for non-tall steps, render the step body with `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)` (SwiftUI `.leading` = horizontally-leading + **vertically-centered**). For the tall **project step (4)** and the **companion step (8)** (both content-heavy), keep the current `ScrollView { … }.frame(maxHeight: .infinity, alignment: .topLeading)`.

### 2. Step total 8 → 9
`OnboardingContent.total = 9`. (No screen was removed; the denominator matches the web. The `stepArt` array must cover index 8 — add the companion step's art.)

### 3. Copy: byte → Codepet
- `OnboardingAnalysisView`: `"byte is reading \(projectName)…"` → `"Codepet is reading \(projectName)…"`.
- Reveal step primary button: `"See my company"` → `"Choose your companion"` (now advances to step 8, not finish).

### 4. New step 8 — "Choose your companion" picker
- Heading `"Choose your companion."`; subcopy `"Pick who'll accompany you as you build. You can change this anytime in the sidebar."`.
- A companion picker over the native `PetCharacter.all` (7 characters) — reuse the selection pattern already in `SettingsView` (tap a character, highlight the selected). Selection held in the wizard's draft (`pick: String`, default the current `company.companionId` or `"byte"`).
- Primary button `"Start building"` → set the companion + finish: `await companyStore.setCompanion(pick)` then the existing `finishOnboarding(brief:token:)`, and reconcile `appState.activeChar = pick` (mirrors `ContentView`/Settings).

## Architecture / components
- **`OnboardingContent.swift`** — `total = 9`; extend `stepArt` to 9 entries (index 8 = the companion step's art; reuse an existing onboarding image, e.g. `ob-team`, since the source's per-step art for step 8 isn't ported).
- **`OnboardingView.swift`** — add `pick` to `ObDraft` (default `company.companionId`); add the step-8 branch to `stepBody` (a new `OnboardingCompanionStep` sub-view) and `primaryButton` (case 7 reveal → "Choose your companion" → step 8; default step 8 → "Start building" → setCompanion+finish); change the body wrapper to center non-tall steps (project + companion stay top/scroll).
- **`OnboardingCompanionStep.swift`** (new) — heading + subcopy + a `PetCharacter.all` grid (tap to select, selected highlighted with the accent), bound to a `@Binding var pickedId: String`.
- **`OnboardingRevealView.swift`** — unchanged (its button label lives in `OnboardingView.primaryButton`).
- **`OnboardingAnalysisView.swift`** — the one-word copy change.
- **`CompanyStore.setCompanion`** — already exists (used by Settings); reused, not modified.

## Data flow
Unchanged wizard flow through step 7 (reveal). Reveal "Choose your companion" → step 8 (picker) → "Start building" sets `pick` via `companyStore.setCompanion` + `appState.activeChar`, then `finishOnboarding(brief:token:)` exits to the shell. The brief already carries all fields; the companion is stored separately (companionId), as today.

## Error handling / edges
- Vertical centering must not clip tall steps — project (4) and companion (8) keep the ScrollView/top-align path.
- Companion default = the account's current `company.companionId` (so it's pre-selected), falling back to `"byte"`.
- Skip / Back behave as today; Back from the companion step (8) returns to the reveal (7).

## Testing
- No new pure-logic unit (this is view work) beyond a `stepArt.count == 9` / `total == 9` assertion added to `OnboardingContentTests`.
- SwiftUI views (companion step, centering, copy) build-verified; full existing suite stays green.
- Manual: walk native onboarding — questions vertically centered, "Step N of 9", "Codepet is reading", reveal → "Choose your companion" → picker → "Start building" lands in the shell with the chosen companion; the flow renders correctly in both Light and Dark.

## Out of scope
- The per-step art gradient (`STEP_GRADE`) and multi-image crossfade the newest source added — cosmetic; native keeps its single per-step art.
- The live "Codepet, mapped" in-app first-run modal (post-onboarding) — separate.

## Constraints
Don't touch Giang's Build Coach files or `CLAUDE.md`. Worktree `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port`. Toolchain: scheme `codepet` lowercase, FOREGROUND `xcodebuild build/test` `CODE_SIGNING_ALLOWED=NO` (signed for launch); SourceKit cross-file diagnostics are false positives; iCloud git → `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 --no-verify`, `rm` the worktree `index.lock`, background commits.

## Open decisions
None — companion step included, Codepet copy, vertical centering, total=9 all resolved. Ready for implementation planning.
