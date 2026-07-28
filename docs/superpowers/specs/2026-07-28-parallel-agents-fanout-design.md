# Parallel department agents — live fan-out — design

**Date:** 2026-07-28
**Owner:** Mona
**Branch:** `feat/chat-redesign`
**Status:** Approved design → spec
**Builds on:** [[codepet-chat-mockups-agents-ui]] — the `AgentsWorkingRow` + `AgentRun` view layer already shipped; this wires it live and adds the concurrency engine.

## Goal

One tap fans a single prompt out to several department agents that run **in
parallel**, shown live in the chat via the existing `AgentsWorkingRow`, with each
agent's draft landing in the transcript as it finishes.

## What the user sees

1. Founder taps the **"Run my next moves"** quick-action chip in the composer.
2. The client planner picks the next actionable task in each of up to **3**
   departments and seeds one `AgentRun` per task (status `.working`).
3. A single `AgentsWorkingRow` renders below the messages, showing all agents
   working concurrently (per-agent avatar, `Name · Dept`, status pill, elapsed,
   step counter, live checklist).
4. Each agent's `runTask` runs concurrently; as each completes, its row flips to
   `.done` (or `.failed`) and its **draft `Deliverable` message** is appended to
   the transcript.
5. When all finish, the `AgentsWorkingRow` clears; the drafts remain in the chat.

## Scope / non-goals

- **Client-side planner only.** Tasks are chosen from the existing roadmap; no
  LLM and **no Cloud Function changes** (CF lives in the separate
  `Murror/CodePet-Clean` repo — out of scope).
- **No real streamed steps.** Per-agent step progress reuses the existing
  client-side reveal animation (the backend `RunTaskResponse` carries no steps).
- **No chat-while-fanning-out.** The composer is disabled during a fan-out (same
  "busy" model as a single run today), just parallelized. Concurrent chat turns +
  runs are out of scope.
- **Cap = 3** concurrent agents per fan-out (a named constant), to bound credit
  spend and latency — each run counts separately against the server daily cap.

## Architecture

Everything lives in `CompanyStore` (`@MainActor`) + `CopilotChatView`. The
network layer (`RunTaskClient`) is already stateless and parallel-safe (one HTTP
POST per run); the only single-run constraints today are the scalar
`isCompanionTyping`/`isStreaming` flags and the single-`producingId` model in
`produceDraftInline`. We add a run *collection* alongside them rather than
touching that single-run path.

### 1. State (new, on `CompanyStore`)
- `@Published var activeAgentRuns: [AgentRun] = []` — the live source for one
  `AgentsWorkingRow`. Empty ⇒ no row shown.
- `@Published private(set) var isFanningOut: Bool = false` — serializes a fan-out
  against the normal single chat turn.
- `static let maxFanOut = 3` — the cap.

### 2. Planner (pure, testable)
`nextMovesPlan(limit: Int) -> [RoadmapTask]`:
- Walk `company.tasks` in roadmap order (phase order, then array position — the
  same ordering `RoadmapEngine.nextStep` uses).
- Keep a task only if `RoadmapEngine.status(for:in: company.tasks) == .codepetCanDo`
  **and** it has a `dept` that maps to a specialist via
  `DepartmentCompanions.companionId(for:)`.
- Take the **first** such task **per distinct department** (one agent per dept),
  stop at `limit`.
- Pure over `(tasks)` → unit-testable with fixtures. Returns `[]` when nothing is
  actionable.

### 3. Engine (`fanOutNextMoves(language:)`)
- Guard `!isFanningOut && !isCompanionTyping && !isStreaming` (don't start during
  another turn).
- `let plan = nextMovesPlan(limit: Self.maxFanOut)`. If empty → append an honest
  companion bubble ("You're all caught up — no open tasks I can run right now.")
  and return.
- Capture `cid = company.id`. Set `isFanningOut = true`.
- Seed `activeAgentRuns`: for each planned task build an `AgentRun`
  (`companionId`/`deptName` from `taskSpecialist(for:)`, falling back to the host
  companion + dept display name; `steps` from the existing
  `execSteps(task:specialist:decisionCount:language:)`; `status: .working`;
  `startedAt: Date()`; a stable `id`).
- **Fan out with a `TaskGroup`** — one child per run:
  - Kick off the existing client-side **step-reveal** for that run's `AgentRun`
    (mark its steps `.done` one by one on the main actor).
  - `await taskRunner(runRequest(for: task, language:))` concurrently.
  - After the await, **re-check `cid == company.id`** (account-switch safety); if
    changed, abort this branch silently.
  - On success: set that `AgentRun.status = .done`, mark all its steps done, and
    append the draft `Deliverable` message (reuse `buildDeliverable(from:task:)`
    and the existing draft-message append shape). On `nil`: set `.failed` and
    append one honest "couldn't finish <task>" bubble.
- When the group completes: clear `activeAgentRuns`, set `isFanningOut = false`,
  `flushActiveThread()`.
- All published mutations happen on the main actor (CompanyStore is `@MainActor`);
  concurrency is via structured `TaskGroup`.

### 4. UI wiring (`CopilotChatView`)
- **Chip:** add a **"Run my next moves"** entry to `quickActions`; its tap calls
  `companyStore.fanOutNextMoves(language:)` (a new branch in `runQuickAction`, not
  the text-send path).
- **Live view:** in `messageList`, after the `ForEach(chatMessages)` and the
  existing typing row, render `AgentsWorkingRow(runs: companyStore.activeAgentRuns)`
  when `!activeAgentRuns.isEmpty`. Auto-scroll on `activeAgentRuns` change (mirror
  the existing `isCompanionTyping` scroll trigger).
- **Composer:** fold `isFanningOut` into `isChatBusy` / `canSend` so the composer
  disables during a fan-out, consistent with a single run today.

### 5. Cost & failure honesty
- The cap (`maxFanOut = 3`) bounds concurrent runs.
- A `nil` result (offline, error, or a server `429` daily-limit — `RunTaskClient`
  fail-opens all of these to `nil`) → that agent's row goes `.failed` + an honest
  bubble, instead of the current silent drop.

## Testing
- **Planner** (`CompanyStoreFanOutTests` or a pure helper test): given fixture
  `[RoadmapTask]`, `nextMovesPlan(limit:)` returns the first `codepetCanDo` task
  per distinct dept, ordered by phase then position, capped at `limit`; skips
  done/needsYou/blocked/needsApproval/unassigned-dept tasks; returns `[]` when
  none actionable. If the planner needs company state, extract it as a pure static
  over `(tasks, limit)` so it tests without the store.
- `AgentRun` status transitions already have math tests; add a check that a
  `.failed` run still carries its (partial) steps.
- Engine orchestration (TaskGroup, appends, clearing) is exercised manually via
  the running app + the existing mock gallery; not unit-tested (it's `@MainActor`
  I/O orchestration).

## Follow-on (out of scope)
1. LLM planner via a new CF endpoint (smarter, free-form fan-out).
2. Real streamed per-agent steps from the backend.
3. Chat-while-running (concurrent chat turn alongside live agents).
4. Surfacing the specific `429 daily_limit_reached` shape (needs `RunTaskClient`
   to decode 429 rather than fail-open to `nil`).
