# Coding Agent in the Copilot Column — Design

**Date:** 2026-07-31
**Status:** Approved design → ready for implementation plan
**Branch:** `feat/coding-agent-copilot` (off `main` @ `4141d1d`)
**Target:** `main` (the web-parity native app). The chat-first redesign (PR #39) is NOT shipping; this brings one capability from it — the local Coding Agent — into `main`'s existing "Your team" copilot column, styled to match `main`.

---

## 1. Goal

Let a founder run the **local Coding Agent** from `main`'s "Your team" copilot column: describe an engineering change, watch it run against a linked local repo (live step checklist + real file diffs), and approve it into a safe throwaway git commit — all rendered inside the existing copilot chat, in `main`'s web-parity design.

## 2. Non-goals (v1)

- **`byte` (cloud) auto-initiating a code run.** `main`'s `CompanyChatClient` does not decode an `edit_code` action and the `companyChat` Cloud Function has no such path. Adding it is deferred to a later pass.
- **Push / merge / deploy.** The agent only commits to a throwaway local branch. It never pushes.
- Re-theming `main` or importing any other part of the chat-first redesign.
- Converting `main`'s message model from the fat-struct/if-chain to an enum (out of scope; we follow the existing pattern).

## 3. Why this is a clean port

`main` already ships the execution engine and project infra; the redesign's coding-agent code is a UI-free layer on top of it.

| Piece | On `main` today | Action |
|---|---|---|
| `ClaudeCodeRunner` (spawns `claude` CLI, streams tool events, computes real file diffs) | **Yes** (used by Skills screens) | Reconcile ~13-line diff from redesign |
| `ProjectStore` + `Project` model | **Yes** | Reuse (note: the agent's linked repo is a *separate* `ProjectLink`, not `ProjectStore`) |
| `CodingRunCoordinator`, `CodeCommitService`, `GitRunner`, `CodeRunning`, `MockCodeRunner` | No | Port unchanged (pure / UI-free) |
| Models: `EditCodeRun`, `EditCodeRouting`, `CodeExecSteps`, `ProjectLink`, `ClaudeMdBootstrap`, `RoadmapDispatch` | No | Port unchanged |
| `ExecStep` type | No (lived in redesign's `CopilotMessage`) | Add to `main` as its own small file |
| Run card view + copilot wiring | No | **New**, built on `main`'s card chrome |

**Chosen approach:** port the UI-free layer wholesale, reuse `main`'s runner, and build a thin card + three triggers on top. *(Rejected alternative: reuse the runner but hand-roll a simpler coordinator/commit flow — the safe-commit state machine is the valuable, already-tested part; rebuilding it is pure risk.)*

---

## 4. Architecture

### 4.1 Layer to port (unchanged unless noted)

**Services** (`codepet/Services/`):
- `GitRunner.swift` — synchronous `/usr/bin/git` wrapper (drains stderr to avoid pipe deadlock) + `CommitSlug`.
- `CodeCommitService.swift` — safe-commit engine. Two backends: **git** (stash dirty work → create throwaway `codepet/<slug>` branch, collision-avoid `-2/-3` → commit; never deletes a branch carrying commits) and **shadow** (backup-copy for non-git dirs). Never pushes/merges.
- `CodeRunning.swift` — `protocol CodeRunning` (the testable async seam) + `ClaudeCodeRunAdapter` (bridges `main`'s Combine `ClaudeCodeRunner` to the async seam; builds a fresh runner per call; maps `$events` → `ExecStep` via `CodeExecSteps`) + `CodeRunOutcome`.
- `MockCodeRunner.swift` — `CodeRunning` conformer; fakes the AI (no `claude`, zero cost) but makes a **real** on-disk edit so the commit engine is still exercised.

**Coordinator** (`codepet/Managers/`):
- `CodingRunCoordinator.swift` — `@MainActor ObservableObject`. `@Published run: EditCodeRun?`, `@Published steps: [ExecStep]`. Methods: `propose(ask:plannedFiles:needsBash:link:)`, `execute()`, `approve(acceptedPaths:)`, `reject()`, `cancel()`. Owns the live `gitSession`/`shadowSession`.

**Models** (`codepet/Models/`):
- `EditCodeRun.swift` — `EditCodeRun`, `EditCodePhase` (`noProject, previewing, readyToRun, running, reviewing, committed, discarded, failed`), `CodeBackend`, `EditCodePlanner`.
- `EditCodeRouting.swift` — `shouldRoute(department:projectLinked:)` (eng + linked).
- `CodeExecSteps.swift` — `StreamEvent` → `ExecStep` mapping.
- `ProjectLink.swift` — `ProjectLink` + `ProjectProbe`.
- `ClaudeMdBootstrap.swift` — CLAUDE.md seed composer.
- `RoadmapDispatch.swift` — `RoadmapAction.editCode` + `editCodeAsk(for:)`.
- `ExecStep.swift` — **new file** on `main` (extract the `ExecStep` struct the redesign kept in its `CopilotMessage`).

### 4.2 Reconciliation

- **`ClaudeCodeRunner.swift`:** merge the redesign's ~13-line change into `main`'s copy. Verify the diff is additive/compatible with the Skills consumers (`ExerciseWorkspaceView`, `RunForRealSection`) so we don't regress them.
- **`CompanyStore` (`main`):** add `@Published`/lazy `codingRun: CodingRunCoordinator` (built with `MockCodeRunner()` under a mock env flag, else `ClaudeCodeRunAdapter()`), `codingRunAnchorId: String?`, `activeProjectLink: ProjectLink?`, and `linkProject(path:bootstrapClaudeMd:)`. Re-publish the coordinator's `objectWillChange` through the store (as the redesign does).

### 4.3 Run card + copilot integration (the only UI-coupled part)

- **`CodeRunCardView.swift` — new, on `main`'s chrome.** Phase-routed single card: `.previewing` (plan + Run/Cancel), `.running` (live step checklist + spinner), `.reviewing` (branch chip + per-file diff cards with accept toggles + "Open full diff" sheet + Approve/Reject), `.committed`/`.discarded`/`.failed`, `.noProject` (Link-a-project offer). Built with `main`'s `CopilotCard`/`CodepetTheme` and `main`'s companion avatar — **not** the redesign's `MessageCard`/`CompanionOrb`. Card body is width-agnostic, so it reflows into the narrower column.
- **Message-kind hook (`main`'s 3-touch pattern):**
  1. `CopilotMessage.swift` — add `var codeRun: CodeRunRef?` optional field (+ init default). `CodeRunRef` is a lightweight anchor (the card observes `companyStore.codingRun` directly for live state).
  2. `CopilotChatView.swift` `CopilotBubble.body` — add one `else if message.codeRun != nil` branch rendering `CodeRunCardView`.
  3. `CompanyStore` — a handler that appends a `.companion` message carrying `codeRun` and sets `codingRunAnchorId`.
- **Live updates:** port the two `.onReceive(codingRun.$run / .$steps)` bridges (with the one-runloop deferred re-render + auto-scroll) into `main`'s `CopilotChatView`, OR have `CodeRunCardView` observe the coordinator as `@ObservedObject`. Without this the card sticks on "running" — this is required.

### 4.4 The three triggers (all feed `codingRun.propose(...)`)

1. **"Let's build" button** (`main`'s `CopilotChatView.swift:78`, currently an empty stub): on tap, take the current composer text as the ask and `propose(ask: text, plannedFiles: 2, needsBash: false, link: activeProjectLink)`; anchor the card to the last message.
2. **Engineering toggle in the composer:** add a slim Chat/Engineering segmented control to `main`'s `inputBar`. When Engineering is selected and a project is linked, `send()` routes to a code run (via `EditCodeRouting.shouldRoute`) instead of `sendChat`; otherwise it's a normal reply.
3. **Engineering task Start:** port `RoadmapDispatch`; `TasksView`/`RoadmapView` compute `.editCode` for eng tasks with a linked project, set `codingRunAnchorId = nil` (card falls to transcript bottom), navigate to the copilot, and `propose(ask: RoadmapDispatch.editCodeAsk(for: task), ...)`.

### 4.5 Project linking

- Port `ProjectLink` + `ProjectLinker` (folder picker + CLAUDE.md consent, security-scoped bookmark).
- **Environment surface:** add a "Linked project" section to `main`'s `EnvironmentView.swift` (link / change / unlink; probe summary).
- **In-card offer:** when a run is triggered with nothing linked, the card renders `.noProject` with a "Link a project" button that calls `ProjectLinker.pickAndLink(into: companyStore)`.

---

## 5. End-to-end data flow

1. Trigger (button / toggle-send / task Start) → `companyStore.codingRun.propose(ask:…, link: activeProjectLink)`.
2. `propose` picks backend (git if repo, else shadow) and phase (`.previewing` if multi-file/bash, else `.readyToRun`; `.noProject` if no link).
3. Card appears in the copilot column (anchored or at bottom). `.readyToRun` auto-executes; `.previewing` waits for **Run**.
4. `execute()` → `CodeCommitService.begin{Git,Shadow}` → `runner.run(...)`. `ClaudeCodeRunner` spawns the user's `claude` CLI headless; tool events stream → `ExecStep`s append live; on finish it computes real before/after diffs → phase `.reviewing`.
5. Founder toggles accepted files → **Approve** → `approve(acceptedPaths:)` → `CodeCommitService.commit{Git,Shadow}` commits `codepet/<slug>` with message `codepet: <ask>`. **Reject** → abort/restore → `.discarded`.

## 6. Safety (confirmed)

- Runs the founder's own `claude` binary on the linked repo (app is non-sandboxed; no Codepet API key/billing).
- On approve, commits to a **throwaway local `codepet/<slug>` branch only** — never pushes, merges, or deploys. Reject aborts and restores stashed/original work. This behavior is kept exactly as-is.

## 7. Testing

- **`MockCodeRunner`** (no `claude`, zero cost, real on-disk edit) behind a mock env flag so the whole flow — propose → run → review → commit — is exercisable offline.
- **`CodingRunCoordinator` phase tests** (propose/execute/approve/reject transitions; git vs shadow; nothing-to-commit; already-on-branch).
- **`CodeCommitService`/`GitRunner`** exercised via the mock-run commit path.
- Build TEAM-signed and verify the Skills consumers of `ClaudeCodeRunner` still work after reconciliation.

## 8. File change summary

**Port unchanged:** `GitRunner`, `CodeCommitService`, `CodeRunning`, `MockCodeRunner`, `CodingRunCoordinator`, `EditCodeRun`, `EditCodeRouting`, `CodeExecSteps`, `ProjectLink`, `ClaudeMdBootstrap`, `RoadmapDispatch`, `ProjectLinker`.
**New on `main`:** `ExecStep.swift`, `CodeRunCardView.swift` (main-chrome), coordinator tests.
**Modify on `main`:** `ClaudeCodeRunner.swift` (reconcile), `CompanyStore.swift` (coordinator + link + handler), `CopilotMessage.swift` (`codeRun` field), `Views/Copilot/CopilotChatView.swift` (render branch, live bridges, "Let's build" wiring, Engineering toggle), `EnvironmentView.swift` (Linked project surface), `TasksView.swift`/`RoadmapView.swift` (Engineering-task dispatch).

## 9. Deferred / future

- `byte`-initiated `edit_code` (Cloud Function + `CompanyChatClient` decode + a `handleDoneAction` arm).
