# Phase 2 — Onboarding → Per-Account Company Brief — Design Spec

**Date:** 2026-07-20
**Phase:** 2 of 8 in the native=web-product rebuild (anchor: `2026-07-20-native-web-product-architecture.md`; Phase 1 shipped the shell + `CompanyStore`).
**Goal:** A fresh account runs a first-run founder interview → the brief is enriched and written to `companies/{uid}` → the shell shows the company. Re-bases SP1's interview from the retired per-project model onto the per-account `CompanyStore`.

---

## Context

The web app gates onboarding on hydration (`lib/store.tsx`): `onboarded = onboardedAt != nil || brief has fields`; when not onboarded it shows `OnboardingView` before `AppRoot`, and `finishOnboarding` flips it off (scaffold is separate). SP1 built the native interview (`ProjectInterviewModel`: fields founderName/role/projectName/oneLiner/audience/stageIndex, `buildBrief()`, `enrichBrief`) but stored the result per-project in the retiring `ProjectStore`. Phase 1 added `CompanyStore`/`CompanyData` (read-only, no `onboardedAt`, no write). This phase re-bases the interview per-account and adds the **first native `companies/{uid}` write**.

### Approved decisions (brainstorming)
- **(a) Scaffold deferred to Phase 4** — onboarding stops at the brief (enrich + save + stamp), like SP1.
- **(b) New `CompanyOnboarding*`** re-basing SP1's field/`buildBrief`/`enrichBrief` logic — not the `ProjectStore`-bound `ProjectInterviewModel`.

## Scope

**In scope:**
- `onboardedAt` on `CompanyState`/`CompanyDoc` (stored as an ISO-8601 **string** so the Phase-1 `JSONSerialization` load path stays intact).
- `CompanyData.saveBrief(companyId:brief:) async -> Bool` — the first native write to `companies/{uid}` (brief + `onboardedAt`), fail-soft.
- `CompanyStore`: `needsOnboarding`, `@Published isOnboarding`, `finishOnboarding(brief:) async`, `skipOnboarding() async`; set `isOnboarding` after `hydrate`.
- `CompanyOnboardingModel` + `CompanyOnboardingView` — the 6-step interview re-based to drive `CompanyStore`.
- Gate in `ContentView`: authed → `CompanyOnboardingView` when `isOnboarding`, else `AppShellView`.

**Out of scope (later):** scaffold/roadmap generation (Phase 4); the Company view for editing the brief later (Phase 3); companion selection in onboarding (a later polish). Deletion of the retired `ProjectInterviewModel`/`ProjectStore`/reflection (staged). Do not touch Giang's files.

## Components

### 1. `CompanyState` + `CompanyDoc` (extend)
- `CompanyState`: add `var onboardedAt: Date?`. `.empty` has `onboardedAt: nil`.
- `CompanyDoc`: add `var onboardedAt: String?` (ISO-8601, JSON-safe — NOT a Firestore `Timestamp`).
- `CompanyData.state(from:)`: parse `onboardedAt` string → `Date?` via `ISO8601DateFormatter`.

### 2. `CompanyData.saveBrief` (write layer, new)
`static func saveBrief(companyId: String, brief: CompanyBrief) async -> Bool` — writes `companies/{uid}` with `{ brief: <dict>, onboardedAt: <ISO string, now> }`, `merge: true`, via the app's Firestore SDK. Encodes the brief `CompanyBrief → JSONEncoder → JSONSerialization → [String: Any]` (matches the read path's JSON approach, avoids `FirebaseFirestoreSwift`). Returns `false` on error (fail-soft) — a failed write keeps the in-memory brief.

### 3. `CompanyStore` (extend)
- `var needsOnboarding: Bool` — mirrors the web: `company.onboardedAt == nil && BriefContext.compose(company.brief) == nil` (no brief signal).
- `@Published private(set) var isOnboarding: Bool = false`; set `isOnboarding = needsOnboarding` at the end of `hydrate` (respecting the generation-token guard); `reset()` sets it false.
- `func finishOnboarding(brief: CompanyBrief) async` — `saveBrief` (fail-soft); on success update `company.brief` + `company.onboardedAt = now`; always clear `isOnboarding` (the founder finished; a failed cloud write still lets them into the app with the in-memory brief).
- `func skipOnboarding() async` — stamp `onboardedAt` with the current (empty) brief via `saveBrief`, clear `isOnboarding`, so they aren't re-blocked (they fill the Company view later).

### 4. `CompanyOnboardingModel` + `CompanyOnboardingView` (new)
- `CompanyOnboardingModel` (`@MainActor ObservableObject`): the 6 fields (founderName/role/projectName/oneLiner/audience/stageIndex) + `static let stages` + `buildBrief()` (reuse SP1's exact field mapping) + `func submit(store: CompanyStore, api: ReflectionAPIClientProtocol) async` = build → `enrich` (fail-open: `(try? await api.enrichBrief(raw)) ?? raw`) → `store.finishOnboarding(brief: enriched)`.
- `CompanyOnboardingView`: the 6-step flow (mirrors SP1's `ProjectInterviewView` steps, styled in `CodepetTheme` + VI/EN), plus a **Skip** action → `store.skipOnboarding()`.

### 5. Gate (`ContentView`)
In the authed branch: `if companyStore.isOnboarding { CompanyOnboardingView() } else { AppShellView() }`. `isOnboarding` is set by `CompanyStore` after `hydrate`.

## Data flow
Sign-in → `hydrate` → if `needsOnboarding`, `isOnboarding = true` → `CompanyOnboardingView` → Finish → `submit` (enrich fail-open → `finishOnboarding` writes `companies/{uid}` + stamps `onboardedAt`) → `isOnboarding = false` → `AppShellView` shows the company (top-bar name from `brief.projectName`).

## Error handling
- Enrich: **fail-open** (raw answers on failure).
- Write: **fail-soft** — `saveBrief` returns false on failure; `finishOnboarding` still clears `isOnboarding` and keeps the in-memory brief (the user isn't trapped on the onboarding screen by a network blip; the brief re-saves on a later edit).
- Hydration unchanged (Phase 1 fail-soft + generation-token guard).

## Testing
- `CompanyStore`: `needsOnboarding` matrix (onboardedAt set / brief-signal present / neither); `finishOnboarding` (stub-save → brief + onboardedAt set, `isOnboarding` cleared, even on save-failure clears); `skipOnboarding` stamps + clears; `isOnboarding` set true after hydrating a fresh company.
- `CompanyData`: `saveBrief` builds the right `[String:Any]` (brief dict + ISO onboardedAt); `state(from:)` parses `onboardedAt` string → Date; round-trip.
- `CompanyOnboardingModel`: `buildBrief` field mapping (reused, still correct); `submit` (stub api+store) persists via `finishOnboarding`; fail-open enrich still finishes.
- Gate + view build-verified.

## Reuse / references
| Source | Native target |
|---|---|
| web `lib/store.tsx` onboarding gate (`onboarded = onboardedAt || briefFields`) | `CompanyStore.needsOnboarding` / `isOnboarding` |
| SP1 `ProjectInterviewModel.buildBrief` + fields | `CompanyOnboardingModel` |
| SP1 `ProjectInterviewView` (6 steps) | `CompanyOnboardingView` |
| deployed `enrichBrief` fn + `ReflectionAPIClient.enrichBrief` | reused as-is (fail-open) |
| `CompanyData` (Phase 1) | extended with `saveBrief` + `onboardedAt` |

## Open decisions
None — resolved in brainstorming. Ready for implementation planning.
