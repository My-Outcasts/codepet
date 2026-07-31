# Chat PR#39 Parity in the Docked Copilot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring PR #39's full chat experience (empty-state hero, unified composer, parallel agents, streaming exec-log, dept→companion handoff) onto `main`'s 380pt docked copilot, with Build folded into an Ask/Plan/Build composer mode and the first-run interview replaced by starter cards.

**Architecture:** Most chat logic already exists, tested, on `origin/feat/chat-redesign` (PR #39). `main` carries a compatible coding-agent seam (`EditCodeRouting`, `startCodeRun`, `CodeRunCardView`) and a session thread layer that PR #39 shares. So this is a **reconciled port**: port PR #39's pure models + store methods + views, prefer `main`'s already-shipped copies where they overlap, and add two new things — Build-mode routing and the dropped-interview first-run contract. Every ported view gets a 380pt-dock sizing pass.

**Tech Stack:** Swift 5 / SwiftUI / macOS; XCTest; Xcode project `codepet.xcodeproj`, scheme `codepet` (lowercase), bundle `app.murror.codepet`. New `.swift` files auto-join the target via `PBXFileSystemSynchronizedRootGroup` (no pbxproj edits).

## Global Constraints

- **Source of truth for ports:** `origin/feat/chat-redesign` (PR #39). A task that says "PORT `<file>`" means `git show origin/feat/chat-redesign:<path>` is the complete starting content; apply only the adaptations the task lists. Read `main`'s copy first if one exists and reconcile (prefer `main`'s shipped version, extend it).
- **Placement:** chat stays in the **380pt dock** (`AppShellView` dock, `dockWidth = 380`). No full-width chat surface. Every ported view must be legible at 380pt.
- **Bilingual:** every user-facing string has EN + VI, matching PR #39.
- **Honesty (carried from #39):** exec-log steps are grounded in real request inputs, never fabricated tool calls; the composer `+` is quick-actions, not a file picker; `ChatMode` only shapes the outgoing message (no backend mode); `.build` copy stays modest.
- **Coding-agent wiring is load-bearing:** the `CopilotChatView` rewrite MUST preserve `main`'s anchored `CodeRunCardView` rendering (`codingRun.run != nil` + `codingRunAnchorId`) and the thread layer (`ThreadListView`, `switchThread`).
- **Firestore test-host lock:** before running any `CompanyStore*` XCTest suite, kill the running app (`pkill -x codepet`) — a live app holds the LevelDB lock and aborts the test host ("test-host flake"). Pure-model suites are unaffected.
- **Test command (pure suites):** `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/<Suite> CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`. Do NOT reuse that unsigned build to launch the app for manual QA — build TEAM-signed separately (see [[codepet-native-build-verify-loop]]).
- **Commit per task** at the end of its final step.

---

## Phase A — Pure models & planner (SwiftUI-free, unit-tested)

### Task 1: `ChatMode`

**Files:**
- Create: `codepet/Models/ChatMode.swift`
- Test: `codepetTests/ChatModeTests.swift`

**Interfaces:**
- Produces: `enum ChatMode: CaseIterable, Identifiable { case ask, plan, build }`; `func label(_ lang: AppLanguage) -> String`; `func shape(_ text: String, language: AppLanguage) -> String` (`.ask` = identity; `.plan`/`.build` wrap with intent copy).

- [ ] **Step 1: Port the test.** `git show origin/feat/chat-redesign:codepetTests/ChatModeTests.swift` → write verbatim. (If PR#39 has no such file, write: `.ask.shape("x") == "x"`; `.plan.shape("x")` contains "next steps"/"các bước"; `.build.shape("x")` contains "run"/"chạy"; `label` returns Ask/Plan/Build EN and Hỏi/Lập kế hoạch/Bắt tay làm VI.)
- [ ] **Step 2: Run test, verify it fails.** `-only-testing:codepetTests/ChatModeTests`. Expected: FAIL (ChatMode undefined).
- [ ] **Step 3: Port the source.** `git show origin/feat/chat-redesign:codepet/Models/ChatMode.swift` → write verbatim (no adaptation).
- [ ] **Step 4: Run test, verify it passes.**
- [ ] **Step 5: Commit** — `feat(chat): port ChatMode (Ask/Plan/Build message shaping)`.

### Task 2: `ChatLandingState`

**Files:**
- Create: `codepet/Models/ChatLandingState.swift`
- Test: `codepetTests/ChatLandingStateTests.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.nextStep(_:)`, `RoadmapEngine.status(for:in:)`, `CompanyState`, `RoadmapTask` (all exist on `main`).
- Produces: `struct ChatLandingState { let greeting: String; let question: String; let beacon: RoadmapTask?; let needsYouCount: Int; let awaitingApprovalCount: Int; let isEmpty: Bool; init(company: CompanyState, now: Date, language: AppLanguage) }`.

- [ ] **Step 1: Port the test** from `origin/feat/chat-redesign:codepetTests/ChatLandingStateTests.swift`. Verify it covers hour→greeting boundaries (11:59 morning, 12:00 afternoon, 18:00 evening), beacon-excluded-from-needsYou, and empty-tasks → `isEmpty`.
- [ ] **Step 2: Run test, verify it fails.**
- [ ] **Step 3: Port the source** `codepet/Models/ChatLandingState.swift` verbatim.
- [ ] **Step 4: Run test, verify it passes.**
- [ ] **Step 5: Commit** — `feat(chat): port ChatLandingState`.

### Task 3: `ChatThinkingLabel`

**Files:**
- Create: `codepet/Models/ChatThinkingLabel.swift`
- Test: `codepetTests/ChatThinkingLabelTests.swift`

**Interfaces:**
- Produces: the pure "names the in-flight work" label (e.g. `ChatThinkingLabel.text(forTask:language:)` → "Drafting {task}…" / "Working on it…" for a plain reply). Match PR#39's exact API.

- [ ] **Step 1: Port the test** from PR#39 verbatim.
- [ ] **Step 2: Run test, verify it fails.**
- [ ] **Step 3: Port the source** verbatim.
- [ ] **Step 4: Run test, verify it passes.**
- [ ] **Step 5: Commit** — `feat(chat): port ChatThinkingLabel`.

### Task 4: `DepartmentCompanions`

**Files:**
- Create: `codepet/Models/DepartmentCompanions.swift`
- Test: `codepetTests/DepartmentCompanionsTests.swift` (create if PR#39 has none)

**Interfaces:**
- Consumes: `DepartmentCatalog.all`, `PetCharacter.all` (exist on `main`).
- Produces: `enum DepartmentCompanions { static let map: [String:String]; static func companionId(for:) -> String?; static func mentionedDeptKey(in:) -> String? }`.

- [ ] **Step 1: Write the test.** Port PR#39's if present, else: `companionId(for: "eng") == "crash"`; `companionId(for: "byte") == nil`; `mentionedDeptKey(in: "help me with marketing")` returns the marketing dept key; `mentionedDeptKey(in: "hello")` == nil.
- [ ] **Step 2: Run test, verify it fails.**
- [ ] **Step 3: Port the source** `codepet/Models/DepartmentCompanions.swift` verbatim.
- [ ] **Step 4: Run test, verify it passes.**
- [ ] **Step 5: Commit** — `feat(chat): port DepartmentCompanions handoff map`.

### Task 5: `ChatContext` focus grounding

**Files:**
- Create/Modify: `codepet/Models/ChatContext.swift` (create; if a `ChatContext` already exists on `main`, extend it)
- Test: `codepetTests/ChatContextFocusTests.swift`, `codepetTests/ChatContextDecisionsTests.swift`

**Interfaces:**
- Produces: `ChatContext` with a `focusDepartment` that injects the selected department's grounding into the chat prompt string (the value threaded through `sendChat(department:)`). Match PR#39's exact API so Task 7 can consume it.

- [ ] **Step 1: Port both tests** from PR#39 verbatim.
- [ ] **Step 2: Run tests, verify they fail.**
- [ ] **Step 3: Port `ChatContext.swift`** verbatim; reconcile with any existing `main` type (prefer `main`'s fields, add the focus method).
- [ ] **Step 4: Run tests, verify they pass.**
- [ ] **Step 5: Commit** — `feat(chat): ChatContext department-focus grounding`.

### Task 6: `RoadmapEngine.nextMoves` planner

**Files:**
- Modify: `codepet/Managers/RoadmapEngine.swift` (add `static func nextMoves(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask]`)
- Test: `codepetTests/RoadmapEngineNextMovesTests.swift`

**Interfaces:**
- Produces: `nextMoves` = first `codepetCanDo` task per DISTINCT department that has a specialist (`DepartmentCompanions.companionId(for:) != nil`), in roadmap order, capped at `limit`.
- Consumes: `DepartmentCompanions` (Task 4), `RoadmapEngine.status`.

- [ ] **Step 1: Port the test** from PR#39 (`git show origin/feat/chat-redesign` — locate the nextMoves test). Verify it asserts: distinct-dept dedupe, specialist-only, cap respected, roadmap order.
- [ ] **Step 2: Run test, verify it fails.**
- [ ] **Step 3: Port the `nextMoves` implementation** into `main`'s `RoadmapEngine`.
- [ ] **Step 4: Run test, verify it passes.**
- [ ] **Step 5: Commit** — `feat(chat): RoadmapEngine.nextMoves planner`.

---

## Phase B — Store behaviors

### Task 7: `sendChat(department:)` + dept→companion handoff

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreChatTests.swift` (extend), plus any PR#39 handoff test

**Interfaces:**
- Consumes: `ChatMode` (T1), `ChatContext` (T5), `DepartmentCompanions` (T4), `EditCodeRouting` + `startCodeRun` (exist on `main`).
- Produces: `func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil) async` (new `department:` param); private `actingSpecialist(text:department:) -> (companionId: String, deptName: String)?` and `sendMessage(_:language:department:)`. A specialist-led turn attributes the reply to the specialist companion (its `CompanionAvatar` + "Name · Dept" header).

**Reconciliation note:** `main`'s `sendChat(_:language:)` (CompanyStore.swift:322) lacks `department:`. PR#39's version (line 465) adds it and, at the top, routes to the coding agent when `EditCodeRouting.shouldRoute(department:projectLinked:)` is true. Port PR#39's `sendChat`/`sendMessage`/`actingSpecialist` bodies, keeping `main`'s existing chat-client call and account-guard. Keep the old `sendChat(_:language:)` as a thin overload calling `sendChat(_:language:department: nil)` so existing call sites compile.

- [ ] **Step 1: Write/port the tests** — a specialist-led send (dept chip) sets the reply's companionId to the mapped specialist; a plain send stays on the host; `sendChat(department:)` with a linked project + eng dept routes to `startCodeRun` (assert `codingRun.run != nil`), not the chat client.
- [ ] **Step 2: Run tests, verify they fail.** (Close the app first — Firestore lock.)
- [ ] **Step 3: Port the methods** and reconcile with `main`'s chat client + guards.
- [ ] **Step 4: Run tests, verify they pass.**
- [ ] **Step 5: Commit** — `feat(chat): sendChat department focus + specialist handoff`.

### Task 8: `activeAgentRuns` + `fanOutNextMoves` (parallel)

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreFanOutTests.swift` (port from PR#39)

**Interfaces:**
- Consumes: `RoadmapEngine.nextMoves` (T6), `AgentRun` (T12 defines the type — see note), `RunTaskClient` (exists on `main`), `withTaskGroup`.
- Produces: `@Published var activeAgentRuns: [AgentRun]`; `func fanOutNextMoves(language: AppLanguage) async` — seeds `activeAgentRuns` from `nextMoves` (cap `Self.maxFanOut`), fans out concurrent `RunTaskClient` calls, marks steps/status live, per-branch account guard, clears on account switch. Empty plan → honest bubble, no empty row.

**Type-ordering note:** `AgentRun`/`AgentRunStatus`/`ExecStep` are defined in `AgentsWorkingRow.swift`. To keep this store task compilable before the view task, **extract `AgentRun` + `AgentRunStatus` into their own file** `codepet/Models/AgentRun.swift` as the FIRST step here (port those decls out of PR#39's `AgentsWorkingRow.swift`); Task 12 then ports only the view. `ExecStep` already exists on `main` (coding-agent port).

- [ ] **Step 1: Extract `AgentRun`/`AgentRunStatus`** into `codepet/Models/AgentRun.swift` (verbatim decls from PR#39's `AgentsWorkingRow.swift`, incl. `stepCounter`, `currentStepIndex`, `elapsedString(now:)`).
- [ ] **Step 2: Port the fan-out test** from PR#39; add an empty-plan → no-row assertion and a mid-run account-switch → cleared assertion.
- [ ] **Step 3: Run test, verify it fails.** (App closed.)
- [ ] **Step 4: Port `activeAgentRuns` + `fanOutNextMoves`** and `maxFanOut`; reconcile with `main`'s `RunTaskClient` + `reset()` (add `activeAgentRuns = []` to `reset()`).
- [ ] **Step 5: Run test, verify it passes.**
- [ ] **Step 6: Commit** — `feat(chat): parallel department fan-out (activeAgentRuns)`.

### Task 9: Drop first-run interview → starter-card contract

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (`finishOnboarding`)
- Test: `codepetTests/CompanyStoreFirstRunGreetingTests.swift` (rewrite)

**Interfaces:**
- Changes: `finishOnboarding` no longer calls `startEnrichInterviewIfNeeded`/`seedFirstRunGreeting` to seed an interview; a fresh account opens with an **empty** `chatMessages` so `CopilotChatView` shows `ChatEmptyState`. `startEnrichInterviewIfNeeded`, `pendingInterview`, `EnrichInterview` remain defined but unreferenced by first-run (removing them is out of scope).

- [ ] **Step 1: Rewrite the tests.** Replace the assertions that a sparse brief seeds an interview message with the new contract: after `finishOnboarding` with a sparse brief, `chatMessages.isEmpty == true` (dock will render the landing hero). Keep any test that a *rich* brief also seeds nothing. Delete/rewrite `testSparseBriefStartsInterviewInsteadOfGreeting` to `testSparseBriefOpensEmptyForLandingHero`.
- [ ] **Step 2: Run tests, verify they fail** against current `main` (interview still seeded). (App closed.)
- [ ] **Step 3: Edit `finishOnboarding`** — remove the interview/greeting seeding branch; leave `chatMessages` empty on first run.
- [ ] **Step 4: Run tests, verify they pass.**
- [ ] **Step 5: Commit** — `feat(chat): first-run opens on the landing hero (drop auto-interview)`.

### Task 10: `MockChat` — fan-out / exec-log / handoff offline

**Files:**
- Modify/Create: `codepet/Services/MockChat.swift` (or `main`'s mock equivalent)
- Test: none required (dev harness); build-only verification

**Interfaces:**
- Consumes: the mock path already gated by `-CODEPET_MOCK_CHAT`.
- Produces: mock responses that exercise a fan-out (multiple `activeAgentRuns` completing), a single exec-log run, and a dept handoff, so the whole redesign is demoable offline.

- [ ] **Step 1: Port/extend `MockChat`** from PR#39 so `fanOutNextMoves` + `produceDraftInline` return canned, realistic content under the mock flag; reconcile with `main`'s existing mock.
- [ ] **Step 2: Build** (Debug, unsigned) — `xcodebuild build ... CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`. Expected: `BUILD SUCCEEDED`.
- [ ] **Step 3: Commit** — `feat(chat): mock fan-out + exec-log + handoff for offline demo`.

---

## Phase C — Views (adapted to the 380pt dock)

### Task 11: `ChatBackdrop` + `ChatThinkingRow`

**Files:**
- Create: `codepet/Views/Copilot/ChatBackdrop.swift`, `codepet/Views/Copilot/ChatThinkingRow.swift`
- Test: none (visual); build-only

**Interfaces:**
- Consumes: `CompanionOrb` (exists on `main`), `ChatThinkingLabel` (T3).
- Produces: `ChatBackdrop` (ambient purple wash) and `ChatThinkingRow` (breathing orb + shimmering label).

**Dock adaptation:** `ChatThinkingRow` orb ≤ 22pt; label truncates at 380pt; reduce-motion safe (keep PR#39's guard).

- [ ] **Step 1: Port `ChatBackdrop.swift`** verbatim.
- [ ] **Step 2: Port `ChatThinkingRow.swift`**; apply the dock sizing.
- [ ] **Step 3: Build (unsigned), verify `BUILD SUCCEEDED`.**
- [ ] **Step 4: Commit** — `feat(chat): ChatBackdrop + ChatThinkingRow (dock-sized)`.

### Task 12: `AgentsWorkingRow` (view)

**Files:**
- Create: `codepet/Views/Copilot/AgentsWorkingRow.swift` (view only; `AgentRun` already extracted in Task 8)
- Test: `codepetTests/AgentsWorkingRowTests.swift` (if not already added in Task 8; the `AgentRun` math tests belong wherever `AgentRun` landed — put them in Task 8's step if they test the model, here if they test view helpers)

**Interfaces:**
- Consumes: `AgentRun`/`AgentRunStatus` (T8), `PetCharacter.all`, `CompanionAvatar`.
- Produces: `struct AgentsWorkingRow: View { let runs: [AgentRun]; var now: Date }`.

**Dock adaptation:** rows stack vertically (they already do); each `agentRow` must fit 380pt — avatar + Name·Dept + status pill on one line, elapsed + step counter on the next; truncate long task titles.

- [ ] **Step 1: Port `AgentsWorkingRow`** view (drop the `AgentRun`/`AgentRunStatus` decls now living in `AgentRun.swift`).
- [ ] **Step 2: Apply the 380pt layout pass.**
- [ ] **Step 3: Build (unsigned), verify `BUILD SUCCEEDED`.**
- [ ] **Step 4: Commit** — `feat(chat): AgentsWorkingRow (dock-sized)`.

### Task 13: `ChatExecLog`

**Files:**
- Create: `codepet/Views/Copilot/ChatExecLog.swift`
- Test: none (visual); build-only

**Interfaces:**
- Consumes: `ExecStep` (exists), `CompanionAvatar`.
- Produces: the titled streaming execute-log card ("{Specialist} is doing the work…" + honest "N steps" checklist, last step spinning, collapses into the draft).

**Dock adaptation:** card fills dock width; step rows wrap/truncate at 380pt.

- [ ] **Step 1: Port `ChatExecLog.swift`**; apply dock sizing.
- [ ] **Step 2: Build (unsigned), verify `BUILD SUCCEEDED`.**
- [ ] **Step 3: Commit** — `feat(chat): ChatExecLog streaming card (dock-sized)`.

### Task 14: `QuickAction` + `ChatComposer` (with Build routing)

**Files:**
- Create: `codepet/Views/Copilot/QuickAction.swift`, `codepet/Views/Copilot/ChatComposer.swift`
- Test: none (visual); build-only

**Interfaces:**
- Consumes: `ChatMode` (T1), `Department`/`DepartmentCatalog`, `companyStore.activeProjectLink`.
- Produces: `struct QuickAction { let id; let title; let systemImage; let detail }`; `struct ChatComposer: View` with bindings `draft`, `mode: ChatMode`, `selectedDept: Department?`, callbacks `onSend`, `onQuickAction`, and inputs `canSend`, `focus`, `placeholder`, `quickActions`, `accent`, `accent2`, `isBusy`.

**Dock adaptation:** at 380pt show the first **2** dept chips + `•••` overflow (not 3) so the row + active-project chip fit; text field `lineLimit(1...6)`; keep the focus-glow.

**New — the mode menu (this is the "streamline Let's build in" change):** the composer's mode control is `Menu` over `ChatMode.allCases` showing `Ask / Plan / Build`, bound to `$mode`. It replaces PR#39's identical control (port as-is). The Build *routing* lives in `CopilotChatView.onSend` (Task 16), not here — the composer only owns the selected mode.

- [ ] **Step 1: Port `QuickAction.swift`** verbatim.
- [ ] **Step 2: Port `ChatComposer.swift`**; change `deptChips` to `prefix(2)` + overflow; verify the mode menu is present and bound to `$mode`.
- [ ] **Step 3: Build (unsigned), verify `BUILD SUCCEEDED`.**
- [ ] **Step 4: Commit** — `feat(chat): ChatComposer with Ask/Plan/Build mode (dock-sized)`.

### Task 15: `ChatEmptyState` (hero + starter cards)

**Files:**
- Create: `codepet/Views/Copilot/ChatEmptyState.swift`
- Test: none (visual); build-only

**Interfaces:**
- Consumes: `ChatLandingState` (T2), `CompanionOrb`, `ChatComposer` (T14, injected).
- Produces: `struct ChatEmptyState<Composer: View>: View { let state; let onOpenRoadmap; let onStarter; var columnWidth; @ViewBuilder var composer }`.

**Dock adaptation (concrete):** `CompanionOrb(size: 78)` → `56`; greeting font `inter(31)` → `inter(22)`; the card grid `LazyVGrid(columns: [.flexible(), .flexible()])` (2-col) → **single column** (`[GridItem(.flexible())]`); drop `columnWidth = 760` default to `.infinity`/dock width; outer `.padding(.horizontal, 40)` → `20`; keep the gradient greeting, the live-vs-starter card switch, and the exact EN/VI starter strings ("Plan this week" / "Review my brief" / "Draft my positioning").

- [ ] **Step 1: Port `ChatEmptyState.swift`.**
- [ ] **Step 2: Apply every dock adaptation above.**
- [ ] **Step 3: Build (unsigned), verify `BUILD SUCCEEDED`.**
- [ ] **Step 4: Commit** — `feat(chat): ChatEmptyState hero + starter cards (dock-sized)`.

### Task 16: Rewrite `CopilotChatView` to compose the redesign

**Files:**
- Modify (rewrite): `codepet/Views/Copilot/CopilotChatView.swift`
- Test: `codepetTests/CompanyStoreChatTests.swift` (adjust any view-contract assertions), build-only for the view

**Interfaces:**
- Consumes: everything above + `main`'s coding-agent wiring (`companyStore.codingRun`, `codingRunAnchorId`, `CodeRunCardView`) and thread layer (`ThreadListView`, `switchThread`).
- Produces: the composed dock chat.

**Body contract:**
- Header (`Your team` + `guiding · {company}` + History toggle) — keep `main`'s.
- Backdrop: `ChatBackdrop` behind content.
- If `chatMessages.isEmpty` → `ChatEmptyState(state:onOpenRoadmap:onStarter:) { composer }` (composer injected).
- Else → message list: un-bubbled assistant messages beside `CompanionOrb`/`CompanionAvatar`; inline `ChatExecLog` for a producing run; `AgentsWorkingRow(runs: companyStore.activeAgentRuns)` when non-empty; the anchored `CodeRunCardView` (preserve the `codingRun.run != nil` + `codingRunAnchorId` gates exactly as they are now); `ChatThinkingRow` while typing.
- Composer at the bottom in both states (shared `ChatComposer` instance).
- **`onSend` routing (the Build change):** `switch mode { case .ask,.plan: Task { await companyStore.sendChat(mode.shape(draft, language: lang), language: lang, department: selectedDept) }; case .build: companyStore.startCodeRun(ask: draft) }`. Clear `draft` after.
- **Delete** the old full-width `letsBuild` button and `canBuild` (its behavior now lives in `.build` mode).
- `onStarter(text)` → set `draft = text` then trigger `onSend` in `.ask` mode.
- Quick-actions include "Run my next moves" → `Task { await companyStore.fanOutNextMoves(language: lang) }`.

- [ ] **Step 1: Adjust tests** — remove/repoint any assertion tied to the deleted `letsBuild`/`canBuild` or the old greeting; assert first-run empty → landing (covered in Task 9) and that a `.build` send calls `startCodeRun`.
- [ ] **Step 2: Run adjusted tests, verify the new ones fail** (view not rewritten yet). (App closed.)
- [ ] **Step 3: Rewrite `CopilotChatView`** per the body contract; preserve the coding-agent scroll bridges (`onReceive(codingRun.$run/$steps)`).
- [ ] **Step 4: Run tests, verify they pass.**
- [ ] **Step 5: Build TEAM-signed** (per [[codepet-native-build-verify-loop]]): `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`. Expected `BUILD SUCCEEDED`, `TeamIdentifier=YL72VTKBR7`.
- [ ] **Step 6: Commit** — `feat(chat): rewrite CopilotChatView — PR#39 dock redesign`.

---

## Final verification (after all tasks)

- [ ] Full deterministic suite green (close the app first; count executed tests — a `** TEST FAILED **` with no `Failing tests:` = suites never ran, the Firestore lock).
- [ ] Manual QA: kill stale, launch one TEAM-signed instance `-CODEPET_MOCK_CHAT YES`; verify at 380pt — landing hero + single-column starter cards; a starter tap sends; Ask/Plan/Build mode menu; a `.build` send shows the anchored run card; "Run my next moves" shows `AgentsWorkingRow` with agents completing; a single run streams `ChatExecLog`; a dept chip produces a specialist-attributed reply. Everything legible in the dock.
- [ ] Whole-branch review (superpowers:requesting-code-review) on the most capable model.
- [ ] superpowers:finishing-a-development-branch → PR against `main`.

## Self-review notes

- **Spec coverage:** empty-state hero (T15), composer + mode menu (T14), Build routing (T16), starters replace interview (T9, T15), parallel agents (T6/T8/T12), exec-log (T13), dept handoff (T4/T5/T7), dock adaptation (every Phase-C task). ✅
- **Type ordering:** `AgentRun` extracted in T8 before its view (T12) and store use; `ChatMode`/`ChatLandingState`/`ChatContext`/`nextMoves` (Phase A) precede their consumers (Phase B/C). ✅
- **Reconciliation:** T7 keeps a no-arg `sendChat` overload; T16 preserves coding-agent gates + thread layer; ports prefer `main`'s shipped `MessageCard`/`CompanionOrb`. ✅
