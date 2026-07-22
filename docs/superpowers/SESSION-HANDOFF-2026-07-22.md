# Codepet Native Port — Session Handoff (2026-07-22)

Self-contained resume doc. Read this first, then `git log` / the specs+plans under `docs/superpowers/`.

## TL;DR
The native macOS Swift app is being made into a faithful port of the web product (codepet-ver-1-2.vercel.app). All 8 rebuild phases + reconciliation Stage 1 are **on `main`** (PR #4, #5 merged). This session added the whole **web-faithful pre-app flow + theming** on branch `feat/splash-onboarding-web-port` → **PR #6 open to `main`** (user reviewing/merging).

## Repos / topology (verify before assuming — learned the hard way)
- **Native Swift app** = `My-Outcasts/codepet`. Working copy is a git **worktree**: `~/Documents/codepet-rebuild-wt` (branch `feat/splash-onboarding-web-port`). Scheme `codepet` (lowercase), no xcodegen, `@testable import codepet`.
- **Web product** (reference) = `~/Desktop/Codepet v1.2` (repo `My-Outcasts/Codepet-ver-1.2`), live at codepet-ver-1-2.vercel.app. **Its git hangs on iCloud** — read files directly; `git fetch`/`status` can deadlock. Local checkout was STALE vs the live deploy (live onboarding is newer/9-step).
- **Gen backend** = Firebase Functions `devpet-8f4b1` (the 3 gen CFs live here, UNDEPLOYED — node-22 gate).
- Don't touch Giang's Build Coach (`BuildCoachView`/`InstallView`/`SummaryView`, `/api/track*`, `/api/build-plan`) or `CLAUDE.md`.

## What's DONE (on main)
All 8 phases: shell+CompanyStore · onboarding/brief · roadmap board (3A/3B, phase-column, simplified from web's node-graph) · Copilot chat · deliverables+Library · Environment/toolkit · Settings. Reconciliation Stage 1 (retired old SP3 roadmap, kept enrichBrief) merged via PR #5.

## What this session added → PR #6 (branch `feat/splash-onboarding-web-port`, off origin/main 108b240)
Each piece: brainstorm→spec→plan→subagent-driven (controller-transcribes-verbatim pattern)→reviews. Specs+plans under `docs/superpowers/{specs,plans}/2026-07-2*`.
1. **Splash + 8→9-step cinematic onboarding** (dark #100a26 + splash.jpg; OnboardingContent / OnboardingReveal(task-based) / OnboardingView + coldopen/optionlist/stageslider/analysis/reveal / OnboardingCompanionStep; `CompanyStore.scaffoldFromOnboarding` persist+fail-open+no-exit).
2. **Sign-in** ReturningSignInView → web dark card (auth.jpg + light card). **View-layer only — ALL AuthManager wiring preserved.**
3. **Google Sans Flex** app-wide — 4 static latin TTFs bundled in `Resources/Fonts` + registered (`FontRegistrar`), `CodepetTheme.inter`→GSF (Inter fallback), fixed onboarding headings that used SF Pro `.system`, `ChipFlowLayout`. Pixel "Codepet" brand kept.
3b. **Onboarding 9-step fidelity** (browser-walked the LIVE web, all 9 steps): added **"Choose your companion"** step 8, `total`=9, vertical centering (`.frame(maxHeight:.infinity, alignment:.leading)` = vertically centered; project+companion top/scroll), copy "byte is reading"→"Codepet is reading", reveal btn→"Choose your companion".
4. **DARK MODE** — `CodepetTheme`(12)+`OnboardingContent.Palette`(6) tokens → dynamic `Color.dyn(lightHex,darkHex)` (NSColor dynamicProvider + `NSColor(hex:)`); exact web `[data-theme=dark]` palette (page #16130f / surface #221d17 / text #f4f1ea / accent #9d6bf5). `AppTheme{system,light,dark}` on `appState.appTheme` (persist `cp_appTheme`, default system) drives `CodePetApp.preferredColorScheme`; de-forced `ThemedBackgroundModifier`; Settings Theme cycle row. Splash/sign-in/cold-open stay dark (`coldBg` static).

## AUDIT — % transferred vs web (this session's answer)
- **~65–70% of the UI surface.** DONE: splash, sign-in, onboarding, shell, copilot, overview(simplified), library, environment, settings, dark mode, GSF font.
- **~55–60% functionally LIVE** — because the **3 gen Cloud Functions are UNDEPLOYED** (fail-open), so chat/roadmap-gen/deliverable-gen produce nothing; the "done" screens are hollow until deploy.
- **Placeholders / missing** (native sidebar `AppView` = overview/company/roadmap/tasks/library/environment/settings; only overview/library/environment/settings are REAL, rest → `ShellPlaceholderView`):
  1. **Company** view (departments/company overview) — placeholder.
  2. **Tasks** view — placeholder.
  3. **Roadmap** view (full node-graph map) — placeholder (native folds a simplified phase board into Overview).
  4. **Overview parity** — native = phase-column board; web = node-graph map + Roadmap/Second-Brain toggle + "how to read this map" + first-run spotlight (web OverviewView.tsx = 709 lines).
  5. **Department Detail** — missing; **typed deliverable viewers** (native has one MarkdownView vs web's typed artifact viewers) — smaller.
  6. Minor: Toast system, Topbar parity, LoadingScreen.

## KEY DECISION owed before Company/Roadmap/Tasks work
The native rebuild **simplified the web's 8-department model into 5 phases** (Find/Foundation/Build/Ship/Launch). Company/Roadmap/DepartmentDetail don't map 1:1 → decide: **rebuild on departments (exact web match)** vs **on the native phase/task model**. This changes the scope of items 1–5 above.

## RECOMMENDED next order
1. **Deploy the 3 gen CFs** (`scaffoldRoadmap` [carries generateRoadmap in-flight-guard], `companyChat` + `runTask` [auth-header gate]) — node-22. Biggest unlock; turns the shell into a working app. NOT UI work.
2. **Stage 2 reconciliation** — delete the still-dead game/reflection stack (`MainTabView`/`ReflectionTab`/`ProjectStore`/`Project` + ~15 old stores + `CodePetApp`/`ContentView` untangle, ~100+ files). Compiles off the live path today. (Note `ChipFlowLayout` was named to avoid the dead `FlowLayout` in `MentorQADetailView` — that dies in Stage 2.)
3. Company / Tasks / Roadmap views (per the department-vs-phase decision).

## GOTCHAs (all reconfirmed this session)
- **Signed build required for Firebase keychain/sign-in**: build WITHOUT `CODE_SIGNING_ALLOWED=NO` (team `YL72VTKBR7`, "Apple Development") → `open` the .app. Unsigned `open`-launch = "keychain error", Google/email sign-in can't complete. For UI-only checks, guest ("Continue without signing in") avoids keychain. Or run from **Xcode ⌘R**.
- **xcodebuild FOREGROUND only** (`-destination 'platform=macOS'`); implementer subagents STALL on backgrounded xcodebuild → controller transcribes verbatim + verifies foreground + commits; reviewers are the gate.
- **SourceKit cross-file diagnostics are FALSE POSITIVES** ("Cannot find type X", "No such module XCTest/FirebaseCore", "Extraneous argument label hex:"). `xcodebuild` output is authoritative.
- **iCloud git on the worktree hangs**: `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` before writes; commit via **background** job + confirm HEAD advanced; `merge --abort` fails on stat-cache → `git reset --hard HEAD`.
- **DISK LOW ~10GB / 95%** (`/System/Volumes/Data`) → "unable to write index" + slow push; free space.
- **Can't screenshot the native app** — the user visually verifies; the controller drives build/launch.
- Dynamic dark tokens: `Color(nsColor: dynamicNSColor)` DOES re-render on `preferredColorScheme` change (verified). Fallback if it ever snapshots = Asset-Catalog color sets.
- English-only pre-app flow (deliberate); assets live in `Assets.xcassets/Onboarding/` (synchronized group — drop files, no pbxproj edit).

## Related memory
[[codepet-web-to-native-port]] (the running log) · [[codepet-swift-port-topology]] · [[codepet-nextjs-app]]. This doc = the fuller snapshot behind the memory line.
