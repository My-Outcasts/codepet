# Reconcile `feat/chat-redesign` onto post-#37 `main` — execution guide

**Branch:** `reconcile/redesign-onto-main` (a copy of `feat/chat-redesign` @ `e68ffcd`). **Merging in:** `origin/main` @ `4141d1d`. Merge-base `e9de8e0`.
**Direction (founder-approved):** the SidebarView redesign + this session's chat features WIN, re-seated on main's post-#37 foundation; ALIGN to main (adopt `Views/Roadmap` + `Views/SecondBrain`; keep Overview & Summary DELETED); rewire the composer draft to `companyStore.chatDraft`.

## Do it in this order

1. `git merge origin/main --no-edit` (expect conflicts in 6 files + Overview/Roadmap location conflicts). Do NOT abort.

2. **Resolve the 6 content conflicts** per the table below.

3. **Adopt main's directory layout:** ensure `Views/Roadmap/RoadmapView.swift`, `Views/Roadmap/RoadmapMapView.swift`, `Views/SecondBrain/SecondBrainView.swift`, `Views/SecondBrain/SecondBrainPanel.swift` are main's versions; **delete the entire `codepet/Views/Overview/` directory** (all 8 files: `RoadmapView`, `RoadmapMapView`, `SecondBrainView`, `SecondBrainPanel`, `OverviewBoardView`, `PhaseColumnView`, `RoadmapHeaderView`, `TaskCardView`). (Synchronized folder groups → no `project.pbxproj` edit needed; deleting from disk syncs.)

4. **Delete `SummaryView`** to align with main's Summary removal: remove `codepet/Views/**/SummaryView.swift` if present on feat, and every `.summary` reference (AppView case, AppShellView branch). Grep `SummaryView` and `\.summary` to confirm none remain.

5. Build (foreground) → fix any dangling refs → full suite → commit the merge (NO push).

## Per-file resolutions

### `codepet/Models/AppView.swift`
Take **main's** enum (cases: `chat, roadmap, secondBrain, tasks, library, environment, company, settings, billing, support` — NO `.summary`, NO `.overview`; keep main's icons/titles). Set `navTabs = [.roadmap, .secondBrain, .company, .tasks, .library, .environment]` (main's list **minus `.chat`** — chat is the wordmark home, not a tab). `from(navDestination:)` is identical on both — keep it.

### `codepet/Views/Shell/AppShellView.swift`
Take **feat's** version (the `SidebarView(collapsed:)` shell + collapse toggle + full-width content). Make ONE edit: **remove the `else if companyStore.view == .summary { SummaryView() }` branch** from `content`. Everything else in feat's file stays (SidebarView already provides Wake→`.environment` + Upgrade→`.billing`). Confirm it compiles without `appState`/`accent` (SidebarView owns accent).

### `codepet/Views/Copilot/CopilotChatView.swift`
Take **feat's** redesigned file wholesale (orb, ChatComposer, cards, ChatLandingState, feedback, dept-focus — all of it). THEN apply the **draft → `companyStore.chatDraft` rewire** (main's intent: a roadmap-card tap navigates to chat with the draft intact):
- Remove `@State private var draft = ""`.
- Everywhere the view read/wrote `draft`, use `companyStore.chatDraft` instead:
  - the composer binding: pass `draft: $companyStore.chatDraft` into `ChatComposer(...)`.
  - `onStarter = { companyStore.chatDraft = $0; inputFocused = true }`.
  - `send()`: read `companyStore.chatDraft`, and clear via `companyStore.chatDraft = ""` (keep the existing `mode.shape(...)` + `sendChat(..., department: selectedDept)` + refocus logic).
  - `canSend` reads `companyStore.chatDraft`.
- `companyStore.chatDraft` exists post-merge (from main's CompanyStore, which auto-merges) and is `@Published var chatDraft: String`. Verify that exact name in the merged `CompanyStore.swift`; if main named it differently, use the real name.

### `codepet/Views/Roadmap/RoadmapView.swift`
Take **main's** version (title "Roadmap"; task tap → `RoadmapDispatch.action(for:)` + `if RoadmapDispatch.navigatesToChat(action) { companyStore.select(.chat) }`). Discard feat's `Views/Overview/RoadmapView.swift`. (Optional: port feat's `#Preview` onto main's file — skip if it adds risk.)

### `codepet/Views/SecondBrain/SecondBrainView.swift`
Take **main's** thin wrapper (header + `SecondBrainPanel`). Discard feat's `Views/Overview/SecondBrainView.swift` (its duplicated roadmap chrome).

### `codepetTests/AppViewTests.swift`
Rewrite to match the resolved `AppView`: `allCases` == main's 10 cases (no `.summary`); `navTabs == [.roadmap, .secondBrain, .company, .tasks, .library, .environment]`; keep the assertion `XCTAssertFalse(AppView.navTabs.contains(.chat))` (chat is home, not a tab); keep `from(navDestination: "roadmap") == .roadmap`. Do not assert `.summary`/`.overview`.

## Auto-merge (no action — verify only)
- `codepet/Managers/CompanyStore.swift` — union of main's `chatDraft` (+ resets) and feat's `reactToMessage`/`sendChat(department:)`/`sendMessage(department:)`/Firebase imports. Both default `view = .chat`.
- `codepet/Views/CodepetTheme.swift` — feat's `chatCanvas`/`chatOrbCore` + main's `navTab()` removal (unused).
- All ~19 new redesign files + new test files — additive, no conflict.

## Verify + commit
- `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **`. Fix any dangling reference to `.summary`/`SummaryView`/`OverviewView`/deleted Overview files.
- `xcodebuild test … CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3` → `codepetTests.xctest` 0 real failures (known Firebase flake wobbles the count).
- Commit the merge (keep the merge commit; do NOT squash; do NOT push):
```
git add -A
git commit --no-edit   # or a clear message if git didn't stage a merge message
```
Message should read: `merge: reconcile chat redesign onto post-#37 main (SidebarView wins; adopt Views/Roadmap; drop Summary; draft→chatDraft)`.

## Constraints
- FOREGROUND xcodebuild only. Do NOT push. Do NOT touch `project.pbxproj`. SourceKit "Cannot find … in scope" = false positives; xcodebuild is authoritative.
