# Codepet — Project Instructions

## What is Codepet?
Codepet is an AI coding companion app where users adopt pixel-art characters that guide them through learning to code. 7 characters, 16 skills, one journey. Built by MURROR (murror.app).

## Tech Stack
- **Platform:** macOS (SwiftUI, minimum macOS 13+)
- **Language:** Swift
- **Auth:** Firebase Authentication (Email/Password, Google Sign-In, Anonymous)
- **Database:** Firestore (cloud sync for user progress)
- **Architecture:** MVVM with @EnvironmentObject (AppState, AuthManager)
- **Assets:** Pixel-art sprites and logos, rendered with `.interpolation(.none)` for crisp scaling
- **Bundle ID:** app.murror.codepet (also persists as com.murror.codepet in UserDefaults)

## Project Structure
```
CodePet-Clean/                  # ← Single source of truth (Xcode + Cursor + Git)
├── codepet.xcodeproj           # Xcode project file
├── codepet/                    # All Swift source files
│   ├── App/
│   │   ├── CodePetApp.swift    # @main, Firebase init, environment objects
│   │   └── ContentView.swift   # 4-state router: splash → auth → onboarding → main
│   ├── Models/
│   │   ├── AppState.swift      # All user state, auto-saves to UserDefaults
│   │   ├── AppState+GameSystems.swift  # GameState class (pet care, hearts, coins, cosmetics)
│   │   ├── GameSystems.swift   # Game data models (PetCare, HeartsSystem, Economy, etc.)
│   │   ├── Character.swift     # PetCharacter model, 7 starters, Color(hex:) extension
│   │   ├── SkillData.swift     # Skill tree definitions (4 tiers, 4 kingdoms)
│   │   └── LessonContent.swift # Lesson content data (8 lessons)
│   ├── Managers/
│   │   ├── AuthManager.swift   # Firebase auth (email, Google, anonymous)
│   │   ├── PersistenceManager.swift  # UserDefaults save/load
│   │   ├── GamePersistence.swift     # GameState save/load (cp_game_ keys)
│   │   ├── SoundManager.swift  # Sound effects
│   │   └── ThemeManager.swift  # Theme/appearance (purple palette)
│   ├── Services/
│   │   └── CloudSyncService.swift  # Firestore read/write (full implementation)
│   ├── Views/
│   │   ├── SplashView.swift    # Splash screen (pixel-art logo, character animations)
│   │   ├── MainTabView.swift   # Tab navigation + GameHUDBar (hearts, coins, streak)
│   │   ├── Onboarding/
│   │   │   ├── OnboardingFlow.swift      # Full onboarding (age gate → questions → character select)
│   │   │   └── ReturningSignInView.swift # Sign-in for returning users
│   │   ├── Home/               # Home tab (dashboard, world map, kingdoms, pet care)
│   │   ├── Skills/             # Skills tab (lessons, companion AI panel, compendium)
│   │   ├── Sessions/           # Coding sessions (practice challenges)
│   │   ├── Insights/           # Progress insights (pixel art icons)
│   │   └── Profile/            # Profile & settings (cosmetic shop, sign-out)
│   ├── Notification/           # Local notifications
│   ├── Menu Bar/               # macOS menu bar integration
│   └── Assets.xcassets/        # All image assets including kingdom PNGs
├── codepetTests/               # Unit tests
├── game-systems/               # Game system specs & prototypes (reference only)
├── design-assets/              # Pixel art source PNGs (1280×800 kingdoms)
└── CLAUDE.md                   # This file
```

**IMPORTANT:** CodePet-Clean is the single source of truth. Both Xcode and Cursor work on the same files here. Do NOT edit ~/Desktop/codepet separately — it is deprecated.

## App Flow
1. **Splash** → user taps "Meet Your Pet →"
2. **New user** (`onboardingComplete == false`) → OnboardingFlow:
   - Age Gate (age selection → sign-in/sign-up or skip)
   - 6 onboarding questions (who, drives, goal, experience, daily goal, character recommendation)
   - Interests selection
   - First Words with chosen character
   - → Main App
3. **Returning user, signed out** (`onboardingComplete == true`, `currentUser == nil`) → ReturningSignInView
4. **Returning user, signed in** → Main App directly

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
- Cloud sync saves to Firestore under `users/{uid}`

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

# Current Sprint: 1-Week MVP Push (Apr 7–13, 2026)

## Goal
Ship a polished MVP to **TestFlight + App Store** within one week.

## MVP Scope (Full Game Loop Lite)
- Auth (email, Google, anonymous) + onboarding + character selection
- 8 lessons across 4 kingdom tiers (Molten Forge, Frozen Spire, Eternal Garden, Mystic Grove)
- Pet care system (mood, energy, hunger, feeding)
- Hearts system (5 hearts, lose on wrong answer, regen 1/30min, refill for 20 coins)
- Coin economy (earn on lesson completion, spend on food + heart refill)
- World map with pixel-art kingdom scenes (pre-rendered 1280×800 PNGs)
- Companion AI chat panel (per-character roles and dialogue)

## Cut from MVP (ship in v1.1)
Compendium, Cosmetic Shop, Pet Abilities, Idle XP polish, Dark Mode, Sound Effects, economy balancing

## Day-by-Day Plan
| Day | Theme | Goal |
|-----|-------|------|
| Mon Apr 7 | Build & Integration | Clean build, GameState wired, pet care visible on Home |
| Tue Apr 8 | Hearts & Economy | Hearts in lessons, coins earned, HUD shows both |
| Wed Apr 9 | Auth & Cloud Sync | All 3 auth methods tested, Firestore saves/restores progress |
| Thu Apr 10 | QA & Polish | Full walkthrough passes, bugs fixed, animations smooth |
| Fri Apr 11 | TestFlight Upload | Build uploaded, beta testers can install |
| Sat Apr 12 | App Store Submit | Listing complete, submitted for review |
| Sun Apr 13 | Buffer | Address feedback, fix review rejections |

## Key Integration Tasks
1. Register `GameState` as `@EnvironmentObject` in `CodePetApp.swift`
2. Wire `GamePersistence` save/load into app lifecycle
3. Integrate `PetCareView` into `HomeView`
4. Add `HeartsDisplayView` to `LessonModalView` + wire `loseHeart()` on wrong answers
5. Wire coin earn logic into lesson completion handler
6. Add `WelcomeBackView` overlay to `MainTabView`
7. Test all auth flows end-to-end
8. Cloud sync on every progress change (not just onboarding)

## Game Systems Architecture
- **GameState** (defined in `AppState+GameSystems.swift`): ObservableObject holding pet care, hearts, coins, cosmetics
- **GameSystems.swift**: Data models (PetCare moods, HeartsSystem, Economy rates, PetFood, Compendium entries, Cosmetics)
- **GamePersistence.swift**: Save/load GameState to UserDefaults (keys prefixed `cp_game_`)
- **AppState.swift**: Core user state (completedLessons, streak, level, selectedTab, pendingKingdomId)
- Views use both: `@EnvironmentObject var appState: AppState` + `@EnvironmentObject var gameState: GameState`

## Game Economy Reference
- Hearts: 5 max, lose 1 per wrong answer, regen 1 every 30 min, refill all for 20 coins
- Coins earned: lessons (10), challenges (25), streaks (5/day), boss battles (50), level-ups (20)
- Coins spent: food (5-50), streak freeze (30), heart refill (20), cosmetics (40-120)
- Pet energy decays 2/hr away (min 5), hunger decays 3/hr away (min 0)
- Pet goes asleep after 3 days away

## Detailed Sprint Plan
See `Codepet-MVP-Sprint.xlsx` for full task breakdown with 34 tasks, daily focus, cut list, and ship checklist.

## Recent Changes (Apr 5, 2026)
- Unified project: CodePet-Clean is now single source of truth (was split between CodePet-Clean + Desktop/codepet)
- Restructured to match Xcode layout: source files now in `codepet/` subfolder
- Fixed duplicate `GameState` declaration (`GameState.swift` emptied, definition lives in `AppState+GameSystems.swift`)
- Copied missing assets (AccentColor, codepet-logo, codepet-text-logo, AppIcon)
- CompanionPanelView X button fix (always shows close button)
- Renamed "Storm Summit" → "Mystic Grove" across all files
- Added cross-navigation: Skills tab "View Kingdom" button → World Map (via pendingKingdomId)
- All 4 kingdom pixel art scenes upgraded to 320×200 with fbm noise textures
- Kingdom banners show full aspect ratio with fade gradient in KingdomInteriorView

## Branch
Currently on `feature/game-ui`. All MVP work happens here before merging to `main`.

---

# Pending Tasks (Pre-MVP)
- [ ] Register GameState as @EnvironmentObject in CodePetApp.swift
- [ ] Wire GamePersistence into app lifecycle
- [ ] Integrate PetCareView into HomeView
- [ ] Add HeartsDisplayView to LessonModalView
- [ ] Wire coin earn logic into lesson completion
- [ ] Google Sign-In end-to-end testing
- [ ] Cloud sync on every progress change
- [ ] Full new-user onboarding flow testing
- [ ] TestFlight upload
- [ ] App Store submission





<!-- codepet:references:start -->
## 📚 Project references (added via Codepet)
Resources to draw on when building this project — apply their principles where relevant.

<!-- ref:Human Interface Guidelines -->
- **Human Interface Guidelines** — Apple · Reference · read as needed
  Apply to CodePet-Clean-feat-refactor-core:
  - Use SF Symbols and native SwiftUI controls (buttons, text fields, progress indicators) throughout the Exercise Workspace and Profile dashboard so CodePet feels instantly familiar to iOS users.
  - Follow HIG tab bar conventions for CodePet's main sections (Dictionary, Workspace, Profile, Project Health): use clear, single-concept labels and SF Symbol icons that remain legible at the smallest system tab bar size.
  - Apply Dynamic Type to every text element in CodePet, including code snippets in the Exercise Workspace and term definitions in the Dictionary, so content scales correctly across all accessibility text sizes.
  - Use HIG-recommended touch target minimums (44x44 pt) for all interactive controls in the Exercise Workspace and bonus points reward UI, preventing mis-taps during coding exercises on smaller iPhone screens.
  - Follow HIG loading and feedback patterns by showing inline progress indicators during Firebase data fetches (profile stats, project health scores) rather than blocking the screen with full-page spinners.

<!-- ref:SwiftUI Thinking -->
- **SwiftUI Thinking** — objc.io · Book · 350 pages
  Apply to CodePet-Clean-feat-refactor-core:
  - Model each CodePet screen (Dictionary, Exercise Workspace, Profile, Project Health) as a pure function of state, so that any change in student progress, points, or health score automatically drives the UI without manual view updates.
  - Drive the bonus points rewards system and achievement animations from a single source of truth in SwiftUI state, so Duolingo-style celebrations are triggered declaratively by data changes, not imperative animation calls scattered across views.
  - Decompose the Exercise Workspace into small, focused SwiftUI views each owning only the state they need, keeping the code editor, feedback panel, and run button independently recomposable and testable.
  - Use SwiftUI layout primitives (VStack, HStack, ZStack, GeometryReader) from first principles to size the Dictionary term cards and exercise panels correctly across iPhone screen sizes, rather than hardcoding frames or font sizes.
  - Treat Firebase-backed student progress as async state, using SwiftUI's data-flow tools to show loading, error, and loaded states in the Profile dashboard without blocking the UI or duplicating fetch logic across views.

<!-- codepet:references:end -->
