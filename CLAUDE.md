# Codepet — Project Instructions

## What is Codepet?

Codepet is a macOS app by MURROR (murror.app) where a founder runs their company with an AI team. The founder describes what they are building, and the app produces a roadmap, runs tasks that generate real deliverables, and convenes departments to argue out decisions.

**Two layers coexist in this repo, and confusing them wastes time.** The virtual-company layer is the live product: departments, roadmap, tasks, library, deliverables, the copilot chat. The older learning-game layer — 7 pixel-art characters, kingdoms, lessons, hearts and coins — is still compiled and still in the tree (`Models/GameSystems.swift`, `Models/SkillData.swift`, `Views/Home`, `Views/Skills`), and the characters are reused as companion avatars. It is not where current work happens. If a request does not say which, assume the company layer.

## Tech Stack

- **Platform:** macOS, SwiftUI. Deployment target **26.2** (not 13 — an older version of this file said 13)
- **Language:** Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (see Landmines)
- **Auth:** Firebase Authentication — email/password, Google, anonymous. Anonymous sign-in is currently disabled in the Firebase console
- **Database:** Firestore under `companies/{uid}` for company state, `users/{uid}` for the older game progress
- **Backend:** Firebase Cloud Functions in `functions/`, TypeScript, Node 22, project `devpet-8f4b1`, region `us-central1`
- **Bundle ID:** app.murror.codepet
- **Signing:** team `YL72VTKBR7`. A build with `CODE_SIGNING_ALLOWED=NO` runs but Firebase auth will not work at runtime — sign it if you need to test anything logged in

## Project Structure

**This repo is the single source of truth.** An older version of this file said `CodePet-Clean` was — it is not, and believing it cost a full consolidation PR. See Landmines.

```
codepet/               Swift sources
├── App/               CodePetApp.swift (@main), ContentView.swift (root router), AppEnvironment.swift
├── Models/            Company state, roadmap, deliverables, chat payloads, the game layer
├── Managers/          CompanyStore (the main store), AccountDataStore, CodingRunCoordinator
├── Services/          One file per Cloud Function it calls, plus SSEParser
├── Views/
│   ├── Shell/         AppShellView — topbar, nav, the docked copilot column
│   ├── Copilot/       The chat dock: CopilotChatView, cards, exec log, agents-at-work
│   ├── Company/       The department roster and department detail
│   ├── Roadmap/  Overview/  Tasks/  Library/  Environment/  SecondBrain/
│   ├── Onboarding/    CompanyOnboardingView and the brief editor it doubles as
│   └── Home/ Skills/ Sessions/ Insights/ Learn/ Dictionary/   ← the older game layer
└── Assets.xcassets/
codepetTests/          Unit tests, one suite per concern
functions/             Cloud Functions — the ONLY deploy source for this project
docs/superpowers/      specs/ (designs + the SSE contract), plans/, and the test runbook
redesign/              A standalone HTML prototype of the OLD game product. Not shipping
```

The root router is `ContentView.swift`: it waits until `companyStore.isOnboarding` is known, then shows `OnboardingView()` or `AppShellView()`. Read it rather than trusting a flow diagram — this file has had a stale one before.

## The Virtual Company

The feature that convenes departments to argue a decision. Backend in `functions/src/company/`, client in `Views/Copilot/VirtualCompanyCards.swift` plus the fan-out in `CompanyStore.sendChat`.

- **`docs/superpowers/specs/virtual-company-sse-contract.md` is the authority.** It outranks any design or plan written later, including anything in `docs/superpowers/plans/`. It has a nine-rule `## Rendering rules the backend depends on` section that a plan's own sample code violated in five places
- Nine departments can be convened — product, finance, engineering, design, marketing, sales, support, operations, legal — capped at **four per room**, enforced in `parseRoutingToolInput`
- `chief_of_staff` routes and synthesises and is deliberately not routable. `devils_advocate` is not a department and takes no seat in the cap
- **Only PLAN mode convenes the room.** A Plan message fans out to `companyChat` and `virtualCompanyRun` in parallel, and the router's escape hatch then decides whether the founder ever sees a room; Ask and Build never fan out at all. It was unconditional until `b42bc10` (Aug 7) — measured ~$0.20 per convened decision against ~$0.005 otherwise, so a casual Ask could cost forty times what it looked like. `ChatMode.convenesRoom` is the gate, and `sendChat`'s `convenesRoom:` defaults to FALSE, which is why a test that means to convene must pass it explicitly — eight interview tests were red for a day for missing exactly that
- **Adding a department means editing the `chief_of_staff` role prompt too.** The roster lives in prose there, and the router acts on that prose, not on the enum. Two tests in `companyRegistry.test.ts` enforce this
- **The ~$0.20 figure predates the effort change.** The position and negotiation phases now run at `POSITION_EFFORT` (`medium`) instead of the API default (`high`), which cuts thinking tokens on the two phases that fan out. Nobody has re-measured since; treat $0.20 as an upper bound until someone does
- Test procedure and every measured number: `docs/superpowers/virtual-company-test-runbook.md`. Read it before re-measuring anything

## Running on the founder's Claude plan, not the API key

The Anthropic API key was deleted from the console on 26 Aug 2026, so every Cloud Function
declaring `ANTHROPIC_API_KEY` answers 401 at runtime. **Every one of them now has a local
path** — all seventeen entries in `CloudAIBlock.blockedPaths`, company layer and learning
layer both. The Cloud Functions are still deployed and still the default for a founder who has
not granted their plan; they simply cannot answer until a key exists again.

- **`CloudAIBlock.blockedPaths` (`codepet/Services/CloudAIBlock.swift`) is the checklist** of
  every endpoint that spends the key. Derive from it, not from memory of which features feel
  AI-ish
- **`ClaudeCodeAuthorisation` is the one switch.** Keyed per company id. It means "Codepet may
  spend my Claude plan" — not "for chat". Every transport reads it, and nothing falls back to
  the Cloud Function when the local path is unavailable: that would spend the key the grant
  exists to stop spending
- Three bundles, built by `scripts/build-sidecar.sh` into `codepet/Resources/` (gitignored) —
  `chatSidecar.js` (streaming chat with MCP tools), `oneShotSidecar.js` (the twelve ops in
  `ONE_SHOT_OPS`), `vcSidecar.js` (the department room). **Run that script after any change
  under `functions/src/`, and before archiving** — without it the routers report
  `localUnavailable` and the founder is told the runner is missing
- Adding a local op means adding it to `ONE_SHOT_OPS` **and** naming it at its Swift call site.
  A test pins the registry's key list for exactly that reason: a rename has to fail in `jest`
  rather than at run time on a founder's machine
- **Prompts are never re-implemented for the local path.** Every op imports the same builder
  the HTTP handler calls and renders the same forced tool's `input_schema`. Where a builder
  lived in a handler it was split into a `*Core.ts` — esbuild inlines the whole import graph,
  and reaching a builder through a handler shipped the Anthropic SDK, express and
  firebase-admin (measured: 7.5 MB of app resource for a prompt and a merge)
- `claude -p` cannot force a tool call, so the schema is asked for in prose and the reply
  parsed (`extractJson`). Every op validates or coerces what it got — that coercion IS the
  safety story on this transport
- Build (`startBuild`) sends a granted founder with a linked folder to `ClaudeCodeRunner`
  instead of the cloud coding agent. A grant is not a folder: without one it still goes cloud,
  because the local run would land in `.noProject`
- **What the local path does not reproduce, per feature:** no server-side caches (the
  narrative cache, the dictionary term cache, prompt caching) — work the cloud would have
  served free is regenerated on the founder's quota; no blackboard write for a meeting; no
  rate limit; no kill switch; and `generatePlan` answers `tier: "full"` because there is no
  entitlement to read on the founder's own machine and the tokens are theirs
- The only call left that can reach the cloud agent by design is `startSessionBuild` with no
  folder linked: a two-mode Developer session already declared its machine on the session bar

## Landmines

Each of these cost real time to learn.

1. **`functions/` is the only deploy source.** A second checkout (`~/Documents/Claude/CodePet-Clean`) used to deploy to the same Firebase codebase, so a deploy from either offered to delete the other's functions. Before deploying, compare the export set against `firebase functions:list` and confirm it is a superset. Prefer `--only functions:<name>`
2. **Never name a local secrets file `.env` inside `functions/`.** `firebase deploy` loads every `.env*` as ordinary env vars, which collides with `secrets: ["ANTHROPIC_API_KEY"]` and fails the deploy with a 400. Use `functions/local.env` (gitignored)
3. **The XCTest host crashes on Xcode 26.2** when a `@MainActor ObservableObject` deallocates. ~27 tests never finish out of ~970, no test actually fails, and `xcodebuild test` exits 65 on a clean checkout. Run per-suite with `-only-testing:` and do not chase it as a regression. `CompanyStore` IS testable through its injected closures
4. **A crash that mimics that bug:** `Auth.auth()` traps rather than throwing when `FirebaseApp` is unconfigured. Rule out an unconfigured Firebase before blaming the toolchain
5. **New `.swift` files need no project-file edit.** `PBXFileSystemSynchronizedRootGroup`: target membership follows the folder on disk
6. **Debug builds put the code in `codepet.debug.dylib`,** not in the `codepet` executable. Grepping the executable for a string finds nothing, including strings that are definitely there

## Design System
- **Background colors:** `#F5F3FA` (pale purple - splash), `#F7F5FC` (onboarding)
- **Primary dark:** `#2D2B26`
- **Accent purple:** `#7B6BD8`, `#534AB7`
- **Logo colors:** K=#2D2664 (outline), S=#1E1848 (shadow), F=#8B7BE8 (fill), L=#A89BF2 (light)
- **Pixel art:** Always use `.interpolation(.none)` and `Image.NEAREST` for scaling
- **App icon:** `codepet-official-logo.png` — C at 55% width × 63% height, white background

## Characters (7 starters)
byte, nova, crash, luna, sage, glitch, null

## Important Files
- `codepet-official-logo.png` — Final app icon (do not modify)
- `codepet-text-original.png` — Original text logo (848x221, do not modify)
- `AppIcon.appiconset/` — All macOS icon sizes generated from official logo

## Key Rules
- Never modify `codepet-official-logo.png` or `codepet-text-original.png` without explicit approval
- Always use NEAREST neighbor scaling for pixel art (never bilinear/bicubic)
- Firebase auth state changes must NOT disrupt the onboarding flow (see `isOnboarding` guard in ContentView)
- UserDefaults keys are prefixed with `cp_` (e.g., `cp_onboardingComplete`)
- Cloud sync has two destinations: company state under `companies/{uid}`, the older game progress under `users/{uid}`

## Prototype mode: two demo companies

Prototype mode runs the whole product on fixtures. **Which company those fixtures describe is a
second switch,** `DemoProject` (`codepet/Demo/`), and there are two:

```
open <path>/codepet.app --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```

- Default is `codepet` — Codepet demoing Codepet, the content the fixtures always had. Every
  suite written against those literals depends on this default, so do not change it.
- `murror` is the second company: 11 tasks, **8 runnable at once — one per roster department**,
  and the only fixture whose run produces a `.site`, i.e. an actual rendered landing page in the
  Library's `WKWebView`. Ask for "the landing page" to see it.
- **Selection is read through `PrototypeMode.store`**, which is redirected to a scratch suite
  under XCTest. That is deliberate and load-bearing: reading `UserDefaults.standard` here would
  re-open issue #117, where the test host sharing the app's defaults domain meant a founder's
  toggle silently changed what the suite exercised.
- A launch argument outranks the stored preference (`NSArgumentDomain`), so the demo cannot be
  left half-selected between the two.
- **All eight Murror tasks are runnable only because each depends solely on `done` tasks.**
  `RoadmapEngine.depsSatisfied` blocks a task whose prerequisite is open, and the roster looks
  identical either way — `DemoProjectMurrorTests` asserts it through the engine for that reason.

---

# Workspaces

This project is managed across 5 separate workspaces. Each workspace has a specific purpose. Never mix concerns across workspaces.

## 1. Codepet macOS app
**Purpose:** All development work on the native macOS SwiftUI app.
**Scope:** SwiftUI views, models, managers, services, assets, Firebase integration, UI/UX changes, bug fixes, and feature development.
**Key files:** Everything under `codepet/` in the Xcode project.
**When to use:** Writing code, fixing bugs, designing screens, adjusting animations, updating assets.

## 2. Codepet macOS app — App Store
**Purpose:** App Store listing, metadata, screenshots, and submission.
**Scope:** App Store Connect configuration, app description, keywords, screenshots, privacy policy, age rating, pricing, and review responses.
**When to use:** Preparing or updating the App Store listing, responding to reviews, updating metadata.

## 3. Codepet macOS app — TestFlight
**Purpose:** Beta testing and distribution.
**Scope:** TestFlight builds, tester management, beta feedback, build versioning, provisioning profiles, and testing notes.
**When to use:** Uploading builds, managing testers, reviewing crash reports, writing test notes.

## 4. Codepet macOS app — GitHub
**Purpose:** Source control, collaboration, and CI/CD.
**Scope:** Git commits, branches, pull requests, issues, GitHub Actions, and code reviews.
**When to use:** Committing code, creating PRs, managing issues, setting up workflows.

## 5. Codepet multi agent
**Purpose:** Multi-agent system design and coordination.
**Scope:** Creating and coordinating AI agents across different roles — Marketing, Business, QA, Backend (BE), and Frontend (FE). Agent definitions, workflows, inter-agent communication, and task delegation.
**When to use:** Designing agent roles, building agent workflows, testing multi-agent coordination, defining agent responsibilities.

---

# Daily Summary Format

When summarizing work at the end of a session, use this format:

**Codepet macOS app**
- [bullet points of work done]

**Codepet macOS app — App Store**
- [bullet points or "No work today"]

**Codepet macOS app — TestFlight**
- [bullet points or "No work today"]

**Codepet macOS app — GitHub**
- [bullet points or "No work today"]

**Codepet multi agent**
- [bullet points or "No work today"]

---

# Where things stand

This section is the one most likely to go stale. Treat it as a pointer, not a fact — check git and the docs before relying on it.

- Work happens on `main` via PRs. There is no long-lived feature branch
- The Virtual Company shipped and is deployed; its remaining items are product decisions, listed at the end of `docs/superpowers/specs/2026-08-03-virtual-company-in-chat-design.md`
- Known and deliberately unfixed: five brief fields (`goal`, `traction`, `problem`, `runway`, `constraints`) are collected by interviews and displayed nowhere; `detectConflicts` reports a false `BLOCKER` when two departments block the same way; `dept-product` has placeholder art so Product is kept off the roster
- The older game layer (kingdoms, lessons, hearts, coins) is compiled but not being developed
- Every model call runs on the founder's own Claude Code when they grant it — see the section
  above. Nothing is left that only the API key can answer

# Working agreements

- **Verify, do not infer.** Several expensive detours here came from reading fallback code and concluding a Cloud Function was undeployed. `curl` the endpoint (401 means alive, 404 means absent) and read `firebase functions:log`
- **Do not commit to `main` directly** unless asked. Branch, PR, and say what you verified
- Commit messages carry the reasoning — the why, the measurement, the rejected alternative. They are the only durable record once scratch files are gone
- When a guard exists, there should be a test that goes red if the guard is deleted. If a test passes with and without the code it protects, it is not protecting anything
