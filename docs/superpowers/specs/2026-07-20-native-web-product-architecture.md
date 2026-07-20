# Native = Web Product — Architecture Spec (anchor doc)

**Date:** 2026-07-20
**Type:** Top-level architecture / decomposition anchor for the whole-app rebuild. Each phase below gets its own spec → plan → build.
**Goal:** Replace the current native macOS Codepet app with a faithful native port of the **web browser app** (`~/Desktop/Codepet v1.2`, live at codepet-ver-1-2.vercel.app) — its **design and its functionality** — keeping the pet mascots as the companion.

---

## Decision record (from the user, Jul 20)

The earlier "port features into the existing native app" framing is **superseded**. The native app is being **replaced** by the web product:
1. **Remove the learn-to-code game** entirely (kingdoms, hearts/coins, lessons, skill tree) — pure web product.
2. **Drop the session-reflection / Project-Health system** (watching Claude Code sessions, narrative, ProjectScanner, Dictionary/Tips-as-reflection) — match the web exactly.
3. **Keep the pet mascots** as the companion (the 7 characters → the Copilot/companion persona).
4. **Fresh product spec first** (this doc), then execute phase by phase.

The web app is the single source of truth for **both** design and functionality.

## The web product (what native must become)

**Shell** (`components/AppRoot.tsx`): a `Sidebar` (nav) switches a `view`, with a persistent **`Copilot`** chat/companion panel. Views:
`overview` · `company` · `roadmap` · `tasks` · `library` · `environment` · `settings`.
(Excluded: `BuildCoachView` / `InstallView` / `SummaryView` — Giang's Build Coach; do NOT port or touch.)

**Data model** (Firestore, one company per account — `companyId == uid`):
- `companies/{uid}` → `CompanyDoc` (`brief: CompanyBrief`, roadmap stage, environment state, companionId, usage).
- `companies/{uid}/departments/{k}` → `DepartmentDoc` (one per department key; holds its tasks).
- `companies/{uid}/library/{itemId}` → `LibraryDoc` (approved deliverables).

**Design:** the web tokens (`app/globals.css`) are, by the web's own comment, *"matched to the Swift app `CodepetTheme.swift`"* — so the native `CodepetTheme` already IS the web palette/type. The shell is built directly in it (+ `pixelBox` tinted cards, `.pixelSystem` type, VI/EN via `uiLanguage`/L10n).

## Target native architecture

- **Window shell:** a macOS SwiftUI shell mirroring `AppRoot` — a **sidebar** (Overview / Company / Roadmap / Tasks / Library / Environment / Settings) + a **Copilot companion panel** (chat). Replaces the current `MainTabView` tabs.
- **Store:** one `CompanyStore` (`@MainActor ObservableObject`) mirroring the web `lib/store` — holds the single company (`companies/{uid}`): brief, departments+tasks, library, stage, env, companionId. Replaces `ProjectStore`'s multi-project model.
- **Firestore:** `companies/{uid}` (+ `departments`, `library` subcollections), via a native `CompanyData` layer (mirrors `lib/firebase/companyData.ts`). Cloud-synced.
- **AI backend:** the existing Cloud Functions on `devpet-8f4b1` (enrichBrief live; scaffoldRoadmap pending deploy) + new functions per feature, per the locked "port web routes → Firebase Functions" decision.
- **Companion:** the 7 pets remain as the selectable companion persona feeding the Copilot voice (native already has the richer persona model).

## Retired (delete or hide behind the rebuild)

Game: `Views/Home`, `Views/Skills`, `Views/Sessions`, `Views/Insights` (game dashboard), `GameState`/`GameSystems`/`GamePersistence`, kingdoms/hearts/coins/lessons/skill-tree.
Reflection: `ReflectionTab`, `ProjectScanner`, `ProjectStore` (multi-project), `ProjectHealthEngine`/`ProjectHealthCheck`, narrative/session-summary reflection surfaces, `Dictionary`/`Tips` as reflection.
(Retirement is staged — surfaces are replaced as their web equivalent lands, not deleted big-bang, to keep the app building.)

## What's reusable from work already done (SP1 + SP3)

- **`CompanyBrief` + `enrichBrief`** (SP1, merged #1) — reused; **re-based per-account** (the company brief, not per-detected-project). The onboarding interview stays; its storage moves from `ProjectStore` → `CompanyStore` (`companies/{uid}.brief`).
- **`RoadmapTask` / `RoadmapEngine.nextStep` / `scaffoldRoadmap`** (SP3, PR #3) — reused; **re-based** off Project Health onto the web's `departments/{k}` model, surfaced in the new `RoadmapView`/`TasksView`, not the reflection folder card.
- **`CodepetTheme`** — the design foundation (already = web).

## Phased plan (each phase = its own spec → plan → build)

1. **Shell + navigation + `CompanyStore`** — the sidebar/Copilot window, the single-company store + `companies/{uid}` Firestore layer, routing between placeholder views. Retire the tab shell. *(Foundation — everything hangs off this.)*
2. **Onboarding → company brief (per-account)** — re-base SP1's interview onto `CompanyStore`; first-run flow like the web.
3. **Overview** — the company overview/map view.
4. **Roadmap + Tasks + Departments** — re-base SP3 onto `departments/{k}`; the `RoadmapView`/`TasksView`/`DepartmentDetail` equivalents; next-step beacon.
5. **Copilot (chat) + tools + threads** — the companion chat with run_task/offer_build/etc.
6. **Deliverables + Library** — the ~12 deliverable types, approve/redo, `library/{itemId}`.
7. **Environment (toolkit)** — capabilities/setup.
8. **Settings + Billing/credits** — usage, plan, companion picker.

Ordering rationale: the shell + store + company data model must exist first (Phase 1); brief seeds everything; overview/roadmap are the spine; chat/deliverables are the interaction core; environment/settings/billing layer on.

## Constraints (carry into every phase)

- Native Swift app repo: `My-Outcasts/codepet`, branch off `origin/main`, worktree. Scheme `codepet` (lowercase), no `xcodegen`, `@testable import codepet`, `xcodebuild -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. SourceKit cross-file diagnostics are false positives.
- Functions: `Murror/CodePet-Clean` @ `feat/project-health-reflection-sync` → `devpet-8f4b1`; deploy **scoped + human-gated**. NOTE: local **node is v24** but functions target **node 22** — deploys currently fail (discovery timeout / heap OOM); **node 22 is required to deploy** (or deploy from CI).
- Do NOT touch Giang's Build Coach files/PRs (`BuildCoachView`/`InstallView`/`SummaryView`, tracking, toolkit/hooks, `/api/track*`, `/api/build-plan`, build-brainstorm).
- Design in `CodepetTheme` + `pixelBox` + `.pixelSystem`, VI/EN via `uiLanguage`.

## Open decisions

- Whether to preserve any native-only value (session reflection) was resolved: **dropped**. If that reverses, Phase 1's store model would need to re-admit projects.
- Exact retirement sequencing (which game/reflection files delete in which phase) is decided per-phase to keep the build green.
