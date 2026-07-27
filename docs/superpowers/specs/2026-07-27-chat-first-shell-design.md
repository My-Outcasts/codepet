# Chat-First Shell (Design)

_Date: 2026-07-27 · Repo: My-Outcasts/codepet (native) · Branch: `feat/chat-first-shell` (off `fix/starfield-typecheck-timeout`, i.e. main + four build fixes)_

## Context

The shell today is a native port of the web `AppRoot`: a top bar with brand, account menu and centred nav tabs; a content area switching on `CompanyStore.view`; and a Copilot chat panel docked at 50% of the window width, collapsible via a bottom-right FAB. `Overview` is the default-feeling destination and is really two screens behind a segmented toggle — `RoadmapMapView` and `SecondBrainPanel` — wrapped in header, progress, beacon and legend chrome.

Chat is where the product's value actually lands: run-task output streams there, approvals happen there, and `nav` chips route from there. It is currently a side panel.

This redesign makes chat the primary surface, dissolves Overview into two first-class destinations, and replaces the top-bar tab row with a left rail. Visual direction is adapted from five references the founder supplied (Opera Neon, LIX, a DeepThink composer, Axora, and a light ChatGPT-style layout): full-canvas chat, left icon rail, centred avatar, time-aware greeting, hero composer, starter cards beneath.

## Goal

Opening Codepet lands the founder in chat, with their companion, a greeting, a composer, and the work actually waiting on them — and Roadmap and Second Brain become their own pages reached from a rail.

## Non-goals

- **Onboarding is not touched.** Splash, sign-in, the hydrating gate and the 9-step cinematic onboarding stay exactly as they are. This design applies only after `companyStore.isOnboarding == false`.
- No change to any Cloud Function, to `RoadmapEngine`, `SecondBrainData`, `TopbarCounts`, or to Firestore schema.
- No depth/effort selector in the composer (see §4).
- No new dependencies, and no new hardcoded colours — everything goes through `CodepetTheme` tokens.

## Design

### 1. Navigation model — `codepet/Models/AppView.swift`

Cases become:

```
chat, roadmap, secondBrain, tasks, library, environment, company, settings, billing, support
```

- **Added:** `chat`, `secondBrain`.
- **Removed:** `overview`, `summary`.
- `navTabs` → `[.chat, .roadmap, .secondBrain, .company, .tasks, .library, .environment]` — the seven rail destinations, in that order.
- `settings`, `billing`, `support` are off-rail, reached from the account menu.

An earlier draft of this spec put Company off-rail on the assumption that Second Brain's department rows reached it. They do not — those rows always set a department key and open that department's detail view, never the Departments index, which holds the only manual "Re-plan for my stage" trigger. A whole-branch review caught it.
- `from(navDestination:)` currently maps `"roadmap"` → `.overview` deliberately ("Roadmap is folded into Overview"). It now maps `"roadmap"` → `.roadmap`. `"department"` continues to resolve to `.company`.
- `icon` and `title(_:)` gain `chat` (`"bubble.left"`, "Chat" / "Trò chuyện") and `secondBrain` (`"brain"`, "Second Brain" / "Bộ não"); the `overview` and `summary` entries are deleted.

`CompanyStore.view` defaults to `.chat`.

### 2. Shell — `codepet/Views/Shell/AppShellView.swift` + `AppRailView.swift` (new)

`AppShellView` loses the docked Copilot panel, the `copilotCollapsed` state, the `chatToggle` FAB, and the centred tab row. It becomes: rail on the left, content to the right of it, slim top bar above the content.

`AppRailView` (new, ~80 LOC) renders the brand mark, the six `navTabs` destinations as icon buttons with the active one tinted by the companion accent (`PetCharacter.all[appState.activeChar]?.color`, already computed in the shell), and the account avatar pinned to the bottom opening the existing `AccountMenuView`.

The slim top bar holds two things: a `Chat ⌵` menu listing recent threads grouped by date (from the existing `ChatThreads`), and `+ New chat`. Thread history deliberately does not get a rail slot — six items matches the reference density, eight does not.

`content` switches on `companyStore.view` to `ChatView`, `RoadmapView`, `SecondBrainView`, `TasksView`, `LibraryView`, `EnvironmentView`, `CompanyView`/`DepartmentDetailView`, `SettingsView`, `BillingView`, `SupportView`, falling through to `ShellPlaceholderView` as today.

Pages replace chat entirely — one surface at a time. See §5 for the one flow that navigates back.

### 3. Chat landing — `codepet/Models/ChatLandingState.swift` (new) + `Views/Chat/ChatLandingView.swift` (new)

`ChatLandingState` is **pure and SwiftUI-free**, following the existing `RoadmapEngine` / `SecondBrainData` / `TopbarCounts` pattern so it unit-tests without a view:

```swift
struct ChatLandingState {
    init(company: CompanyState, now: Date, language: AppLanguage)
    let greeting: String          // "Good evening, Mona" — time-of-day + brief.founderName
    let question: String          // "What are we building?"
    let beacon: RoadmapTask?      // RoadmapEngine.nextStep(tasks)
    let needsYouCount: Int        // status == .needsYou, excluding beacon
    let awaitingApprovalCount: Int// status == .needsApproval
    let isEmpty: Bool             // tasks.isEmpty → show prompt starters instead
}
```

Time-of-day boundaries: `< 12` morning, `< 18` afternoon, otherwise evening, on the user's current calendar. When `brief.founderName` is blank the greeting drops the name ("Good evening").

`ChatLandingView` (~140 LOC) renders, centred and vertically stacked: the companion sprite at `.interpolation(.none)` over an aurora bloom tinted by the companion accent; the greeting (muted) and question (bold); the composer; then the card row.

**Cards** are live state, not copy. Three cards maximum:

| Card | Source | Tap action |
|---|---|---|
| `DO THIS NEXT` + task title | `state.beacon` | `dispatch(beacon)` (§5) |
| `NEEDS YOU` + count | `state.needsYouCount` | select `.roadmap` |
| `AWAITING APPROVAL` + count | `state.awaitingApprovalCount` | select `.roadmap` |

A card is omitted when its count is zero or its beacon is nil. When `state.isEmpty`, the row instead shows three fixed prompt starters ("Draft my positioning", "Plan this week", "Review my brief") which insert their text into the composer.

**Two states, one view.** Once the active thread has at least one message, the hero collapses: the sprite shrinks into the top bar, greeting and cards are removed, and the composer moves to the bottom with the transcript above it.

**Roadmap generation.** `OverviewView` currently owns `.task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }`. That moves to `ChatLandingView`, which is now the guaranteed-visited surface; without this move a new founder would never get a roadmap unless they happened to open the Roadmap page.

### 4. Composer — `codepet/Views/Chat/ChatComposerView.swift` (new)

A rounded card containing the text field and one control row: `⊕` attach, a department pill, and a circular send tinted with the companion accent.

- **Attach** offers the brief, a deliverable from Library, or a file.
- **Department pill** defaults to "Any dept" and lists the departments from `DepartmentCatalog.all` (`codepet/Models/Department.swift`); `DepartmentCatalog.find(_:)` resolves the selected key. The selection is passed to `companyChat` as the department key, which is where the server-side per-department expertise is applied. "Any dept" sends nothing extra, so existing behaviour is unchanged and this is purely additive.
- **No depth/effort selector**, despite the DeepThink reference. The pricing spec fixes chat at ~0.25 credit per message so it feels unlimited; a research mode changes per-message cost and would need its own credit price. Revisit separately.

### 5. Roadmap page — `codepet/Views/Roadmap/RoadmapView.swift` (new)

Header: "Roadmap" + `projectName — oneLiner` subtitle, the `?` "How to read this map" popover carrying `mapIntroBriefing` unchanged, the relocated `progressCard`, and the `legend` beside it. Body: `RoadmapMapView(tasks:)`, unmodified — it consumes the engine and is indifferent to its container. No segment toggle.

Task dispatch reuses `OverviewView.dispatch(_:)` with one addition:

| Status | Action | Navigates? |
|---|---|---|
| `.codepetCanDo` | `companyStore.runTask` | **yes** → `.chat` |
| `.needsYou` | `companyStore.walkThroughTask` | **yes** → `.chat` |
| `.needsApproval` | `companyStore.approveTask` | no |
| `.done` | open deliverable sheet | no |

The two statuses whose output streams into chat navigate there, so pressing Start lands the founder where the result appears. This is the mitigation for the single drawback of "pages replace chat".

### 6. Second Brain page — `codepet/Views/SecondBrain/SecondBrainView.swift` (new)

A thin wrapper (~40 LOC): header, then the existing `SecondBrainPanel(data:lang:onOpenDept:)` unchanged. `onOpenDept` keeps setting `companyStore.selectedDeptKey` and selecting `.company` — this is how Company stays reachable with no rail slot of its own.

### 7. Theming — `codepet/Views/CodepetTheme.swift`

Two new `Color.dyn` tokens for the landing backdrop, so both themes are first-class:

- `chatCanvas` — dark `#16130f` (matching `pageBackground`), light `#f8f7f3`
- `chatBloom` — the aurora wash behind the sprite, composited at low opacity over the companion accent so it re-tints when the companion changes

No view introduces a literal hex. The root `preferredColorScheme(appState.appTheme.colorScheme)` and the Settings theme picker keep working untouched.

### 8. Existing chat view

`CopilotChatView` (612 LOC, written for a 50%-wide panel) has its landing/empty state extracted into `ChatLandingView` and its composer into `ChatComposerView`, leaving it as the transcript host. It is renamed `ChatView` and restyled for full width. This is the largest single piece of work in the change.

`FirstRunGreeting` continues to seed the first companion message, so a brand-new founder sees the hero with their companion already speaking rather than an empty canvas.

## Testing

- **`ChatLandingStateTests` (new).** Greeting at hour boundaries (11:59/12:00, 17:59/18:00); greeting with and without `founderName`; card counts derived from a fixture `[RoadmapTask]`; `isEmpty` true when tasks are empty; beacon excluded from `needsYouCount`.
- **Four references to the removed `.overview` case must be updated.** `AppViewTests.swift:7` asserts the case list; `CompanyStore.swift:842` sets `view = .overview` inside `reset()`; and `CompanyStoreTests.swift:25`, `CompanyStoreTests.swift:53` and `CompanyStoreChatTests.swift:168` assert the store's default destination. All become `.chat`. (An earlier draft of this spec claimed `AppViewTests.swift:7` was the only coupled site — that came from a truncated grep and was wrong; the missing `CompanyStore.swift:842` broke the build during implementation.)
- **New case** in the same file for `AppView.from(navDestination: "roadmap") == .roadmap`.
- **Unaffected:** `RoadmapEngineTests`, `RoadmapMapLayoutTests`, `TopbarCountsTests`, `SecondBrainDataTests`, `ChatThreadsTests`, `FirstRunGreetingTests` — no engine or pure model changes.
- **Removed:** `SummaryDataTests`, together with the type it covers (see Files). `SummaryData` is referenced only by `SummaryView` and that test, so nothing else breaks.
- **Manual click-through:** launch lands on chat with greeting and cards → department dropdown populates → tapping the beacon card dispatches and stays in chat → rail switches to Roadmap → `?` shows the legend → a Second Brain department row opens Company → theme picker still flips the canvas.

Visual verification is the founder's: the agent shell has no Screen Recording permission and cannot screenshot the running app.

## Files

**New**
- `codepet/Models/ChatLandingState.swift`
- `codepet/Views/Shell/AppRailView.swift`
- `codepet/Views/Chat/ChatLandingView.swift`
- `codepet/Views/Chat/ChatComposerView.swift`
- `codepet/Views/Roadmap/RoadmapView.swift`
- `codepet/Views/SecondBrain/SecondBrainView.swift`
- `codepetTests/ChatLandingStateTests.swift`

**Modified**
- `codepet/Models/AppView.swift` — cases, `navTabs`, `icon`, `title`, `from(navDestination:)`
- `codepet/Managers/CompanyStore.swift` — default `view` is `.chat`
- `codepet/Views/Shell/AppShellView.swift` — rail + slim top bar, docked panel removed
- `codepet/Views/CodepetTheme.swift` — `chatCanvas`, `chatBloom`
- `codepet/Views/Copilot/CopilotChatView.swift` → `codepet/Views/Chat/ChatView.swift`
- `codepetTests/AppViewTests.swift`, `codepetTests/CompanyStoreTests.swift`, `codepetTests/CompanyStoreChatTests.swift` — the `.overview` assertions become `.chat`
- `CodePet.xcodeproj/xcshareddata/xcschemes/codepet.xcscheme` — drop the empty `<TestPlans>` element, which made Xcode ignore `<Testables>` and left the scheme with no working test action

**Moved**
- `Views/Overview/RoadmapMapView.swift`, `TaskCardView.swift` → `Views/Roadmap/`
- `Views/Overview/SecondBrainPanel.swift` → `Views/SecondBrain/`

**Deleted**
- `codepet/Views/Overview/OverviewView.swift`
- `codepet/Views/Overview/OverviewBoardView.swift`, `RoadmapHeaderView.swift`, `PhaseColumnView.swift` — already unreachable from the shipping shell today (185 LOC of pre-existing dead code in the folder being dismantled)
- `codepet/Views/Summary/SummaryView.swift`, `codepet/Models/SummaryData.swift`, `codepetTests/SummaryDataTests.swift`

`Views/Overview/` and `Views/Summary/` cease to exist.

## Notes

- **Why Summary is retired.** `SummaryView` is a read-only recap — "what Codepet has done for you" (hero, autopilot bar, stat chips, recent wins). The new chat landing answers the adjacent question, "what is waiting for you", and both were competing to be the first screen. Retiring Summary is reversible: restoring the view, its data model and its test, plus a `summary` case and rail entry, is a contained change.
- **Xcode project membership.** The project uses `PBXFileSystemSynchronizedRootGroup` (`objectVersion = 77`), so files are included by folder membership. New directories under `codepet/` are picked up with no `project.pbxproj` edit; deletions likewise need none.
- **`project.yml`** lists source directories explicitly and must be updated when `Views/Overview` and `Views/Summary` disappear and `Views/Chat`, `Views/Roadmap`, `Views/SecondBrain` appear. It is descriptive only and cannot regenerate the project (see its header), but it should not be allowed to drift again.
- **Branch base.** This branch sits on the four build fixes in PR #35 rather than bare `main`, because `main` does not compile on Xcode 26.4 (`Starfield.swift` type-check timeout). Once #35 merges, those commits become ancestors of `main` and the history is linear.
- **Deferred, not designed here:** a depth/effort selector with a credit price; surfacing thread history in the rail rather than the top-bar menu; live Claude-Code session tracking, which was already out of scope for Summary.
