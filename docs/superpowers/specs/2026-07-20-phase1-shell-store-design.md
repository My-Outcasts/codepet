# Phase 1 — App Shell + Navigation + CompanyStore — Design Spec

**Date:** 2026-07-20
**Phase:** 1 of 8 in the native=web-product rebuild (anchor: `2026-07-20-native-web-product-architecture.md`).
**Goal:** Replace the native app's tab shell with a native port of the web app's `AppRoot` shell — a sidebar + content + Copilot layout driven by a single-company `CompanyStore` hydrated from `companies/{uid}` — as the foundation every later phase hangs off.

---

## Context

The web app (`~/Desktop/Codepet v1.2`) is a 3-column SPA: `components/AppRoot.tsx` renders `Topbar` + a `shell` of `Sidebar · main(active view) · Copilot`, switching a `view` from `lib/store` (`useApp`), with the single company hydrated via `loadCompanyData(companyId)` (companyId == uid). Nav: Overview, Company, Roadmap, Tasks, Library, Environment, Settings (excluding Giang's Summary/Let's-build/Install).

The native app today routes authenticated users to `MainTabView` (`ContentView.swift:45`) — the game/reflection tabs being retired. It already uses Firebase Firestore (`CloudSyncService`: `Firestore.firestore()`, `db.collection("users").document(uid)`). This phase introduces the `companies/{uid}` model natively and the web-style shell, leaving the game/reflection code in place but unreferenced (staged retirement).

## Scope

**In scope:**
- `AppView` enum (the 7 nav destinations).
- `CompanyStore` (`@MainActor ObservableObject`) — view state + single-company state + hydration. Replaces `ProjectStore`'s role as the app's primary store.
- `CompanyData` — Firestore read layer for `companies/{uid}` (+ `departments`, `library` subcollections), mirroring `lib/firebase/companyData.ts`.
- `AppShellView` — the 3-column SwiftUI shell (sidebar + content + Copilot) with **placeholder** views and a **placeholder** Copilot panel.
- Wiring: register `CompanyStore` in `CodePetApp`; route authed users to `AppShellView` instead of `MainTabView`.

**Out of scope (later phases):** real per-view content (Overview/Roadmap/Tasks/etc.), real Copilot chat (Phase 5), onboarding→brief (Phase 2), any Firestore writes/mutations, deletion of game/reflection code (staged, later).

**Non-goals:** do not touch Giang's Build Coach files; do not delete `MainTabView`/game/reflection code this phase (leave unreferenced); do not modify the splash/auth/account-switch logic in `ContentView` beyond the one authed-branch swap.

## Components

### 1. `AppView` (enum, new)
`enum AppView: String, CaseIterable { case overview, company, roadmap, tasks, library, environment, settings }` with a `label(_ lang: AppLanguage) -> String` (L10n vi/en) and an SF Symbol `icon`. Mirrors the web `View` (Giang's `summary`/`build`/`install` excluded).

### 2. `CompanyStore` (`@MainActor ObservableObject`, new)
The native `useApp`. Replaces `ProjectStore` as the app's primary store.
- `@Published var view: AppView = .overview`
- `@Published private(set) var company: CompanyState` — the single company: `brief: CompanyBrief`, `departments: [Department]`, `library: [LibItem]`, `stage: ProjectStage`, `companionId: String`. (Departments/library are typed but empty until later phases populate them; `CompanyBrief` reused from SP1.)
- `@Published private(set) var isHydrating: Bool`
- `func select(_ view: AppView)` — sets `view`.
- `func hydrate(companyId: String) async` — loads via `CompanyData.load`; fail-soft to an empty company.
- `func reset()` — clears on sign-out/account switch (parallels the other stores' reset in `ContentView.reloadAllStores`).

### 3. `CompanyData` (Firestore layer, new)
Mirrors `lib/firebase/companyData.ts`, using the app's existing Firestore SDK pattern.
- `struct CompanyDoc: Codable` — the `companies/{uid}` doc (`brief`, `stage`, `companionId`, env state placeholder).
- `func load(companyId: String) async -> CompanyState` — reads `companies/{uid}` (+ `departments`, `library` subcollections), maps to `CompanyState`. Returns an empty `CompanyState` on missing doc / error (fail-soft).
- Read-only this phase; write methods land when phases mutate.

### 4. `AppShellView` (SwiftUI, new)
The 3-column shell mirroring `AppRoot`:
- **Top bar:** the companion avatar (from the selected pet) + company name (from brief, or a default).
- **Sidebar:** the 7 `AppView` items; selected item tinted with the companion accent (`CodepetTheme` + character color); tap → `store.select(view)`.
- **Content:** switches on `store.view` to a **placeholder** view per destination (a titled stub — real content in later phases).
- **Copilot panel (right):** a **placeholder** panel (collapsible) — real chat = Phase 5.
- Built with a custom `HStack` (sidebar | content | copilot) for web fidelity + macOS 13 support (not `NavigationSplitView`). Styled in `CodepetTheme` + `.pixelSystem`, VI/EN via `uiLanguage`.

### 5. Wiring
- `CodePetApp.swift`: add `@StateObject private var companyStore = CompanyStore()` and `.environmentObject(companyStore)` in the `WindowGroup` chain (mirrors `projectStore`).
- `ContentView.swift:45`: replace the authed-branch `MainTabView()` with `AppShellView()`. Add `companyStore.hydrate(...)` to the sign-in `onReceive` (alongside the existing store activations) and `companyStore.reset()` to `reloadAllStores()`.

## Data flow
Auth resolves `uid` → `CompanyStore.hydrate(uid)` → `CompanyData.load(companies/{uid})` → populates `CompanyState` (empty for a fresh account). Sidebar tap → `store.select(view)` → content swaps. No writes this phase.

## Error handling
Hydration is **fail-soft**: a missing/failed `companies/{uid}` read yields an empty `CompanyState`, and the shell renders normally (empty placeholders) — never a dead end or crash. Sign-out/account-switch calls `reset()`.

## Testing
- `AppViewTests`: `allCases` covers the 7 destinations; `label`/`icon` present for each.
- `CompanyStoreTests` (`@MainActor`): `select` updates `view`; `hydrate` maps a stub `CompanyState` and flips `isHydrating`; `reset` clears.
- `CompanyDataTests`: `CompanyDoc` Codable round-trip; `load`-mapping from a decoded doc → `CompanyState`; empty-on-missing.
- `AppShellView` is thin (store-driven); covered by the full build.

## Reuse / references (web → native)
| Web source | Native target |
|---|---|
| `components/AppRoot.tsx` (shell layout) | `AppShellView` |
| `components/Sidebar.tsx` (nav) | sidebar in `AppShellView` + `AppView` |
| `lib/store.tsx` `useApp` (view + company state) | `CompanyStore` |
| `lib/firebase/companyData.ts` `loadCompanyData` | `CompanyData.load` |
| `lib/firebase/schema.ts` `CompanyDoc` | `CompanyDoc` |
| existing `CompanyBrief` (SP1) | reused in `CompanyState.brief` |

## Open decisions
None — resolved in brainstorming (Copilot placeholder this phase; staged retirement; custom HStack shell). Ready for implementation planning.
