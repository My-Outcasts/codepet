# Chat section — PR #39 design parity, in the docked copilot

**Status:** design approved via brainstorming (2026-07-31). Ready for implementation plan.

## Goal

Bring the PR #39 (`feat/chat-redesign`) chat *experience* onto `main`'s docked
copilot column, with three deliberate adaptations the founder chose:

1. **Build folds into the composer** as an `Ask / Plan / Build` mode menu — the
   separate full-width "Let's build" button is removed.
2. **The first-run enrichment interview is dropped**, replaced by the PR #39
   empty-state hero with starter cards ("Plan this week" / "Review my brief" /
   "Draft my positioning").
3. **Everything is adapted to the 380pt dock** — PR #42's web-parity shell (top
   nav + Overview main content + right dock) is kept; chat does NOT become a
   full-width surface.

Scope is the **full** PR #39 chat, not just the visual shell: parallel
department fan-out, the streaming execute-log, and the department→companion
handoff all come over.

## Decisions locked

| Decision | Choice |
|---|---|
| Scope | Design **+ deeper behaviors** (parallel agents, exec-log, dept handoff) |
| "Let's build" | Composer **mode menu** — Ask / Plan / Build (`ChatMode.shape`) |
| First-run interview | **Dropped**; starter cards instead. Onboarding tests that assert interview-seeding are updated deliberately. |
| Placement | **Inside the 380pt dock**; PR #42 shell unchanged |
| Language | EN + VI parity throughout (every user-facing string bilingual, matching PR #39) |

## What is already on `main` (do NOT re-port)

`CompanionOrb`, `MessageCard`, `MessageCardStyle`, `CompanionAvatar`,
`CodeRunCardView` + the whole coding-agent layer (`ClaudeCodeRunner`,
`CodingRunCoordinator`, `startCodeRun`, `activeProjectLink`, `linkProject`), and
a session thread layer (`switchThread`, `ThreadListView`). `CopilotChatView`
exists but is `main`'s simpler version and will be **rewritten**.

These are reconciliation points: the plan MUST diff `main`'s copy against PR
#39's before porting, and prefer `main`'s already-shipped version where they
overlap (e.g. `MessageCard`), extending it rather than overwriting.

## Components to port (delta from PR #39 → `main`)

**Pure models (SwiftUI-free, unit-tested):**
- `ChatMode` — `.ask/.plan/.build`; `shape(_:language:)` wraps the raw message.
  `.build` ALSO routes to the coding agent when a project is linked (see Build
  routing below) — this is the one behavioral extension beyond PR #39's copy.
- `ChatLandingState` — greeting + question + `beacon` / `needsYouCount` /
  `awaitingApprovalCount` / `isEmpty`, deterministic given `now`.
- `ChatThinkingLabel` — names the in-flight work ("Drafting {task}…").
- `DepartmentCompanions` — deptKey → companionId map + `mentionedDeptKey(in:)`.
- `ChatContext` (focus grounding) — `focusDepartment` threaded through `sendChat`.
- `QuickAction` — title/systemImage/detail value type.

**Views (adapted to the 380pt dock):**
- `ChatEmptyState` — the hero: orb + greeting + injected composer + card grid.
  **Dock adaptation:** orb 78→~56pt; greeting 31→~22pt; card grid 2-col→**1-col**;
  drop the fixed 760 column and fill the dock width with a sensible min.
- `ChatComposer` — one composer for hero + active chat; text field, dept chips,
  `+` quick-actions, **mode menu**, tinted send. **Dock adaptation:** dept chips
  may wrap or show first-2 + overflow at 380pt; keep the active-project chip.
- `ChatBackdrop` — ambient purple wash behind both states.
- `ChatThinkingRow` — breathing orb + shimmering "naming the work" label.
- `AgentsWorkingRow` — the parallel-agents component (per-agent avatar, Name·Dept,
  status pill, elapsed, step counter, live checklist). **Dock adaptation:** stacks
  vertically; each agent row fits 380pt.
- `ChatExecLog` — the streaming execute-log card (titled, "N steps" checklist).
- `CopilotChatView` — **rewritten** to compose the above: empty state when the
  thread is empty, else the message list with un-bubbled assistant messages +
  orb + inline exec-log / agents rows / run card; `ChatComposer` at the bottom.

**Store / services (behavior):**
- `CompanyStore` additions: `activeAgentRuns`, `fanOutNextMoves`,
  `produceDraftInline` (one path for typed-run AND starter/quick-action), the
  dept-focus grounding on `sendChat`, and the dept→companion handoff (host posts
  a one-line handoff, specialist speaks as its sprite via `CompanionAvatar`).
- `RoadmapEngine.nextMoves` — the client-side planner (first `codepetCanDo` task
  per distinct dept with a specialist, roadmap order, cap 3).
- `MockChat` — extend so mock mode exercises fan-out + exec-log + handoff offline.

## Build routing (the one extension over PR #39)

`ChatComposer`'s mode menu carries `.ask / .plan / .build`. On Send:
- `.ask` / `.plan` → `ChatMode.shape` then `CompanyStore.sendChat` (chat path).
- `.build` → route to the **coding agent**: `CompanyStore.startCodeRun(ask:)`
  (which already anchors a `CodeRunCardView` and lands in `.noProject` offering
  "Link a project" when nothing is linked). This is what "streamline Let's build
  into the composer" means concretely — the old `letsBuild` button is deleted and
  its one call site becomes the Build mode branch.

The Engineering composer toggle and Tasks-board `editCode` triggers are
unchanged; Build mode is a third entry into the same `startCodeRun` seam.

## First-run: starter cards replace the interview

- `finishOnboarding` stops calling `startEnrichInterviewIfNeeded`; first run
  seeds nothing and the dock opens on `ChatEmptyState` (hero + starter cards).
- Starter tap → fills/sends the composer with that starter's text
  (`onStarter`), routing through the normal chat path — "Review my brief" and
  "Plan this week" become ordinary grounded asks, not a pinned interview.
- **Test impact (deliberate):** `CompanyStoreFirstRunGreetingTests` (the suite
  that asserts a sparse brief seeds the interview — the same tests reverted
  earlier this session) are rewritten to assert the new contract: sparse brief
  → empty chat opening on the landing hero, no interview message seeded. The
  enrichment machinery (`EnrichInterview`, `pendingInterview`) is left in the
  store for now but is no longer auto-triggered; removing it entirely is out of
  scope.

## Data flow

1. Dock opens → `CopilotChatView` reads `companyStore.chatMessages`. Empty →
   `ChatEmptyState(state: ChatLandingState(company:now:language:))`.
2. Founder types → `ChatComposer` (draft/mode owned by `CopilotChatView`).
3. Send: mode `.ask/.plan` → `sendChat(shaped, department: selectedDept?)`;
   mode `.build` → `startCodeRun(ask:)`.
4. A dept in focus (chip / text mention / dept-owned task) → host posts a
   handoff line; the reply is attributed to the specialist (`CompanionAvatar` +
   "Name · Dept").
5. "Run my next moves" quick-action → `fanOutNextMoves` seeds `activeAgentRuns`
   and fans out concurrent runs via `withTaskGroup`; `AgentsWorkingRow` renders
   them live; each draft lands as it finishes.
6. A single run streams its `ChatExecLog` (grounded "N steps" checklist) then
   collapses into the draft card.

## Honesty constraints (carried from PR #39)

- The `+` menu is quick-actions, NOT a file picker (no attachments exist).
- Exec-log steps are GROUNDED in real request inputs (brief/decisions/dept), not
  fabricated tool calls; step timing is client-side (the run-task CF returns one
  payload, not a live stream) — no fake "Ran N actions".
- Mode control shapes the message only; there is no backend "mode" or build
  session. `.build` copy stays modest.

## Error handling

- Empty plan (no `codepetCanDo` task with a specialist) → honest bubble, no
  empty `AgentsWorkingRow`.
- Per-agent failure in a fan-out → that agent's row shows a failure state; the
  others continue (matches PR #39's per-branch account guard).
- Account switch mid-run → runs are cancelled and `activeAgentRuns` cleared
  (mirror `reset()`'s existing coding-run cleanup).
- `.build` with no linked project → `.noProject` card with "Link a project"
  (already implemented).

## Testing

- Pure types get unit tests ported/adapted from PR #39: `ChatModeTests`,
  `ChatLandingStateTests`, `ChatThinkingLabelTests`, `AgentsWorkingRowTests`
  (the `AgentRun` math), `RoadmapEngine.nextMoves` planner tests,
  `ChatContext` focus/decisions tests.
- `CompanyStoreFirstRunGreetingTests` rewritten to the new first-run contract.
- Full deterministic suite must stay green (close the app first — Firestore
  LevelDB lock, the "test-host flake").
- Manual: build TEAM-signed, single instance, `-CODEPET_MOCK_CHAT YES`; verify
  hero + starters, Build-mode run, a fan-out, an exec-log, a dept handoff — all
  legible at 380pt.

## Out of scope

- Full-width / focused chat layout (placement decision: dock only).
- Removing the enrichment machinery from the store.
- Real streamed backend phases (needs a Cloud Function change).
- Chat persistence changes beyond what `main` already has.

## Reconciliation risks

- `MessageCard` / `CompanionOrb` / `CompanionAvatar` on `main` may differ from PR
  #39's; extend `main`'s, don't overwrite.
- PR #39 view sizes assume a wide surface; every ported view needs a 380pt pass.
- The dock's `CopilotChatView` rewrite must preserve `main`'s coding-agent
  wiring (anchored `CodeRunCardView`, `codingRunAnchorId`) and thread layer.
