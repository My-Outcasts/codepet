# Sidebar Restructure — Implementation Plan

**Goal:** Replace the top bar with a left **SidebarView** (brand → New chat → Recent/History → Workspace nav → Upgrade/account), optimize History into the sidebar's "Recent" section, and remove the "Your team · guiding · {company}" chat header. Chat stays the full-width home to the right of the sidebar. Branch `feat/chat-redesign`. Reference mock: `scratchpad/chat-v4-sidebar.png` (purple brand).

## Global constraints
Native SwiftUI; CodepetTheme tokens; bilingual vi/en; reduce-transparency-safe glows. `xcodebuild` FOREGROUND only. Known `CompanyStoreScaffordOnboardingTests` Firebase flake may crash-retry; nothing else new may fail. Commit trailer required.

## Reuse (exact)
- `AccountMenuView()` (no-arg, `codepet/Views/Shell/AccountMenuView.swift`).
- `TopbarCounts.tasks(company.tasks)`, `.library(company.library)`, `.envPending(enabled: company.enabledTools)`.
- Threads: `companyStore.threads: [ChatThread]` (`ChatThread{ id, title:String?, updatedAt:Date }`), `sortThreadsByRecent(_)`, `relativeTime(_:now:)`, and `companyStore.newChat()/switchThread(_)/renameThread(_:title:)/deleteThread(_)/activeThreadId`.
- Nav: `AppView.navTabs` = [summary, roadmap, secondBrain, company, tasks, library, environment]; `companyStore.select(_)`, `companyStore.view`, `.chat` for home.

---

### Task SB-1: `SidebarView` (new, not wired)
**Create** `codepet/Views/Shell/SidebarView.swift`. A ~250pt-wide column (`CodepetTheme` surface, right hairline border):
- **Brand row:** "Codepet" wordmark (`CodepetTheme.pixel(16)`) as a `Button { companyStore.selectedDeptKey = nil; companyStore.select(.chat) }` (home), + a collapse chevron button taking a `@Binding var collapsed` (SB-2 supplies it; for SB-1 use a local `@State` default so it previews).
- **New chat:** purple-gradient pill `Button { companyStore.newChat(); companyStore.select(.chat) }` (guard: no-op while `isCompanionTyping`/`isStreaming` — mirror ThreadListView's isChatBusy).
- **RECENT (optimized History):** section label; rows from `sortThreadsByRecent(companyStore.threads)` grouped by date bucket using `relativeTime` (Today / Yesterday / Earlier — bucket by comparing `Calendar` day of `updatedAt` vs `Date()`). Each row: title (or "New chat") + faint relative time; active row (`thread.id == activeThreadId`) highlighted (accentPurple tint); tap → `companyStore.switchThread(thread.id); companyStore.select(.chat)`; a right-click/hover `Menu` (ellipsis) with Rename (inline TextField) + Delete (`deleteThread`). Reuse ThreadListView's rename/delete logic (you may move it here and delete ThreadListView in SB-3, or keep both for now — SB-1 just builds the sidebar version). Cap the list with a scroll.
- **WORKSPACE nav:** section label; one row per `AppView.navTabs` — icon (`v.icon`) + `v.title(lang)` + optional count badge (Tasks/Library/Environment via `TopbarCounts`); active row (`companyStore.view == v`) highlighted; tap → `companyStore.selectedDeptKey = nil; companyStore.select(v)`.
- **Bottom (pinned):** an "Upgrade to Pro" card → `Button { companyStore.select(.billing) }`; an account row = `AccountMenuView()` (it already renders the avatar/name/menu) + a small ⚡ Wake affordance → `companyStore.select(.environment)`.
- `#if DEBUG #Preview`.
**Verify:** build SUCCEEDED. Commit `feat(nav): add SidebarView (brand, New chat, Recent, Workspace, account)`.

---

### Task SB-2: Wire SidebarView into `AppShellView`; remove the top bar
**Modify** `codepet/Views/Shell/AppShellView.swift`:
- Add `@State private var sidebarCollapsed = false`.
- `body`: replace the `VStack { topBar; Divider; content }` with `HStack(spacing: 0) { if !sidebarCollapsed { SidebarView(collapsed: $sidebarCollapsed); Divider() }; content.frame(maxWidth:.infinity, maxHeight:.infinity) }` (+ a small floating "expand" affordance when collapsed, or let the sidebar's own chevron toggle it — pass the binding in).
- Delete `topBar`, `navTab`, `tabCount`, `wakePill`, and the in-topbar Upgrade button (all moved to the sidebar). Keep `content` and its branches unchanged.
- Keep `.background(CodepetTheme.pageBackground)`.
**Verify:** build SUCCEEDED; grep shows no leftover `topBar`/`navTab`/`wakePill` refs. Commit `feat(nav): replace top bar with SidebarView`.

---

### Task SB-3: Remove chat header + in-chat History from `CopilotChatView`
**Modify** `codepet/Views/Copilot/CopilotChatView.swift`:
- Delete the `header` computed var (the "Your team / guiding · {company}" + History toggle) and stop rendering it in `body`.
- Remove `showHistory` state and the `if showHistory { ThreadListView(...) }` branch — history now lives in the sidebar. `body` becomes: `VStack(spacing:0){ if chatMessages.isEmpty { ChatEmptyState{composer} } else { messageList; Divider(); composerView.padding(10) } }` (drop the header/divider). Keep the empty-state, message list, composer, send/focus behavior.
- `send()`/`runQuickAction`: remove the now-dead `showHistory = false` lines.
- If `ThreadListView` is now unused anywhere, delete it (grep first).
**Verify:** build SUCCEEDED; full suite green except known flake. Commit `feat(chat): drop the Your-team header + in-chat History (moved to sidebar)`.

## Self-review
- Top bar → sidebar (SB-1 + SB-2) ✓; History optimized into Recent (SB-1) ✓; "Your team" header removed (SB-3) ✓; chat full-width beside sidebar (SB-2 content) ✓; onboarding untouched (no task edits ContentView/OnboardingView) ✓.
- Green boundaries: SB-1 additive; SB-2 swaps shell layout; SB-3 strips redundant chat chrome.
- Types: `SidebarView(collapsed:)` used by SB-2 matches SB-1; thread/nav/counts APIs verified above.
