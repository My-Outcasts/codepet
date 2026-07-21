# Phase 8 — Settings (Account + Billing) — Design Spec

**Date:** 2026-07-21
**Phase:** 8 of the native=web-product rebuild — the **last** phase. Replaces the `.settings` placeholder. Anchor: `2026-07-20-native-web-product-architecture.md`.
**Goal:** A sectioned Settings view — companion, language, edit-brief, and sign out under Account; a static plan/credits card under Plan; app info under About. CF-free; real payment out of scope.

---

## Approved decisions (brainstorming)
1. **Static plan card** — Trial (current) + Pro (upgrade) cards from the pricing memory; "Manage plan" is a no-op placeholder. **No live usage counter** (nothing tracks credits natively; gen CFs undeployed).
2. **All four account controls** — companion picker (+ persist), language toggle, sign out, edit company brief.
3. The companion picker sets **both** `company.companionId` (persisted) **and** `appState.activeChar` (visible sprite).

## Scope
**In:** `CompanyStore.setCompanion` + `CompanyData.saveCompanionId`/`companionIdPayload`; `CompanyOnboardingModel.prefill(from:)` + `CompanyOnboardingView.onDone`; `Plan` (static copy); `SettingsView` (Account + Plan + About) + `.settings` route.
**Out (later):** Stripe/payment + real plan changes; live credit-usage tracking (a CF-coupled subsystem); theme toggle (native dark-mode support unconfirmed); account deletion; the Company/Roadmap/Tasks placeholder destinations.

## Components

### 1. Companion setter (`CompanyStore` + `CompanyData`)
- `CompanyStore.setCompanion(id: String) async` — `company.companionId = id`; capture `cid = companyId`; persist via injectable `companionSaver: (String, String) async -> Bool` (default `CompanyData.saveCompanionId`); guard `companyId == cid` around the await (account-switch discard); fail-soft.
- `CompanyData.companionIdPayload(_ id: String) -> [String: Any]` (`["companionId": id]`); `saveCompanionId(companyId:companionId:) async -> Bool` (merge, fail-soft).
- The Settings picker calls `setCompanion` **and** sets `appState.activeChar = id` so the shell sprite/topbar stay in sync.

### 2. Edit-brief prefill (`CompanyOnboardingModel` + `CompanyOnboardingView`)
- `CompanyOnboardingModel.prefill(from brief: CompanyBrief)` — set `founderName`/`role`/`projectName`/`oneLiner`/`audience` from the brief (empty string when nil) and `stageIndex` = the index of `brief.stage` in `Self.stages` (default 2 when absent/unknown).
- `CompanyOnboardingView` gains an optional `var onDone: (() -> Void)? = nil`, called after a successful `submit`. First-run leaves it nil (the `isOnboarding` flip drives the transition); the edit sheet passes `dismiss`.
- Settings presents `CompanyOnboardingView` in a `.sheet` with a model `prefill`ed from `company.brief` and `onDone = dismiss`. Submit re-persists the brief via the existing `finishOnboarding`.

### 3. `Plan` (static billing copy)
- `enum Plan: CaseIterable { case trial, pro }` with `title(_ lang)`, `priceLine(_ lang)`, `creditsLine(_ lang)`:
  - **Trial** — 7 days · ~150 credits (the honest current default; no billing backend).
  - **Pro** — $20/mo · 800 credits/mo · overage $0.05/credit.

### 4. `SettingsView` + wiring (`codepet/Views/Settings/SettingsView.swift`)
- Reads `@EnvironmentObject companyStore`, `@EnvironmentObject appState`, `@EnvironmentObject authManager`, `@Environment(\.uiLanguage)`.
- **Account** section: a **companion picker** (`PetCharacter.all` values, current = `company.companionId`; tap → `Task { await companyStore.setCompanion(id:) }` + `appState.activeChar = id`); a **Language** control (VI/EN, sets `appState.uiLanguage`); an **Edit company brief** row (opens the edit sheet); a **Sign out** button (`authManager.signOut()`).
- **Plan** section: the current-plan card (Trial) + a Pro upgrade card with a disabled/placeholder "Manage plan".
- **About** section: app name + version (from `Bundle.main`).
- `AppShellView` routes `.settings` → `SettingsView` (mirroring the other destinations).

## Data flow
Companion: picker → `setCompanion` (persist `company.companionId`) + `appState.activeChar`. Language: control → `appState.uiLanguage` (already app-wide + auto-saved). Edit brief: sheet → prefilled onboarding → `finishOnboarding` (re-persist). Sign out: `authManager.signOut()` → ContentView routes to auth. Plan: static display.

## Error handling
No CF. `setCompanion` persistence fail-soft + account-guarded (mirrors `toggleTool`). Sign out + language go through existing, tested managers. The edit sheet's submit is the existing fail-open `finishOnboarding`.

## Testing
- `CompanyStore.setCompanion`: sets `company.companionId` + persists via a stub `companionSaver`; an account switch mid-save discards (guarded).
- `CompanyData.companionIdPayload` shape.
- `CompanyOnboardingModel.prefill(from:)`: fields + `stageIndex` set from a brief (incl. a nil-stage → default index; a known stage → its index).
- `Plan`: `title`/`priceLine`/`creditsLine` non-empty for both cases in both languages.
- `SettingsView` + the edit sheet verified by build.

## Reuse / references
| Source | Native target |
|---|---|
| web Settings/account menu + BillingView (usage vs cap) | `SettingsView` (credits-pricing plan card, not 30/day) |
| pricing memory (Trial/Pro credits) | `Plan` static copy |
| `AuthManager.signOut` / `appState.uiLanguage` / `appState.activeChar` / `PetCharacter.all` | surfaced controls |
| `CompanyOnboardingModel`/`View` (Phase 2) | edit-brief prefill + sheet |
| `CompanyData` field-save pattern | `saveCompanionId` |
| `AppShellView` `.overview`/`.library`/`.environment` router | `.settings` route |

## Open decisions
None — resolved in brainstorming (static plan card, no usage counter; all four controls; companion sets both companionId + activeChar). Ready for implementation planning.
