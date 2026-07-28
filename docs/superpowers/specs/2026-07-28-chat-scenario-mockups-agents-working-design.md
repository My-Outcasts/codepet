# Chat scenario mockups + parallel "agents working" UI — design

**Date:** 2026-07-28
**Owner:** Mona
**Branch:** `feat/chat-redesign` (view-layer only; no engine changes)
**Status:** Approved design → spec

## Goal

Two things:

1. **Scenario mockups** — real SwiftUI preview screens that show the chat in each
   of its main working modes, so we can review the chat UX as complete states
   (not one bubble at a time). Four scenarios: working with the **user**, with the
   **roadmap**, with **tasks**, and **setting up the environment**.
2. **A more specific "which agents are currently working" UI** — today the chat
   shows a single agent working (`ExecLogRow`). We want the inline, in-chat view
   for **multiple department agents working in parallel**, modeled on OpenAI
   Codex's run list (per-run status pill, elapsed time, step counter, live step
   checklist). This is the one genuinely new component.

## Non-goals

- **No engine parallelism.** Actually running multiple department agents at once
  is a separate follow-on. This spec delivers the **view + data model**, driven by
  mock/fixture data. The mock proves the UI so the run engine can be wired to it
  later.
- **No new persistence.** `CopilotMessage` is session-only today; mocks use
  in-memory fixtures.
- **No production entry point yet** beyond `#Preview`. The mocks are dev-only
  (Xcode previews). Wiring `AgentsWorkingRow` into the live chat stream is called
  out as follow-on, not built here.
- No changes to `RoadmapView`, `TasksView`, `EnvironmentView` themselves — the
  scenarios are about the *chat's* view of those surfaces.

## Design principle: mocks drive real components

`CopilotBubble` already renders every chat state we need — `textBubble`,
`navChip`, `setupCard`, `notedChip`, `draftCard`, `firstRunAction` — and
`ExecLogRow` renders the single-agent run. The mock views therefore **feed
fixture `[CopilotMessage]` into the real components**, so the mockups look exactly
like production and cannot drift from it. The only bespoke UI is the new
`AgentsWorkingRow`, which is written as a **production-shaped component**, not a
throwaway.

## Files

```
codepet/Views/Copilot/Mocks/
  ChatMockData.swift        // fixtures: a mock Company + [CopilotMessage] per scenario + [AgentRun]
  ChatUserMock.swift        // #Preview — working with the user
  ChatRoadmapMock.swift     // #Preview — working with the roadmap
  ChatTasksMock.swift       // #Preview — working with tasks
  ChatEnvMock.swift         // #Preview — setting up the environment
  AgentsWorkingMock.swift   // #Preview — parallel agents working
codepet/Views/Copilot/
  AgentsWorkingRow.swift    // NEW real component + AgentRun model
codepetTests/
  AgentsWorkingRowTests.swift   // pure-logic tests (status/elapsed/step math)
```

### Shared mock harness

`ChatMockData` exposes a small helper that renders a fixture conversation the same
way `CopilotChatView.messageList` does — a `ScrollView` of `CopilotBubble`s inside
the chat column width (`760`) with the gutter (`24`), the top/bottom padding
(`40`/`24`), and inter-message spacing (`24`) matching the just-shipped spacing
pass. Each mock view is a thin wrapper: build the fixture array, hand it to the
harness, inject a mock `CompanyStore` via `.environmentObject`. This keeps all
five previews consistent and avoids each one re-deriving layout.

Fixtures use **real companion ids and department names** so avatars/tints resolve:
companions `byte` (displays "Codepet"), `nova`, `crash`, `luna`, `sage`, `glitch`,
`null`; departments `eng` Engineering, `design` Design, `mkt` Marketing,
`sales` Sales, `support` Support, `fin` Finance, `ops` Operations, `legal` Legal.

## The four scenario mocks

Each is a realistic short transcript, not a single bubble.

### 1. Working with the user (`ChatUserMock`)
- `me`: "Which task should I run right now?"
- `companion` (host, byte): a guidance answer, with the copy / regenerate / 👍👎
  action bar (present because `text` is non-empty).
- `me`: "draft it"
- `companion`: a follow-up carrying a `firstRunAction` ("Do it with me: …") so the
  action button state is exercised.

### 2. Working with the roadmap (`ChatRoadmapMock`)
- `me`: "What's next on the roadmap?"
- `companion`: summarizes the current phase + what's blocking launch (plain text).
- `companion`: a `navChip` message → "Go to Roadmap" (exercises the tap-to-navigate
  chip; in the mock the tap is a no-op via the mock store).

### 3. Working with tasks (`ChatTasksMock`)
- `me`: "Run the landing page copy task."
- `companion`: a `producing` message with `execSteps` mid-run (some `done`, one
  in-flight) → renders the single-agent `ExecLogRow`.
- `companion`: a resolved `draft` (`Deliverable`, kind with an icon) → `draftCard`
  with Approve / Redo / Revise chips.
- A second `draft` message with `draftApproved = true` → the "Added to Library"
  state.

### 4. Setting up the environment (`ChatEnvMock`)
- `me`: "Help me set up my tools."
- `companion`: a `setupSuggestion` (`SetupAction` resolving to a real `Toolkit`
  item) → `setupCard` with the category enable verb.
- `companion`: a `noted` message (`[RememberedFact]`) → the "Noted" chip, shown
  after a tool is enabled.

## The new component: `AgentsWorkingRow`

The inline, in-chat view of **multiple agents working at once**. Stacks one row per
active agent; visually a sibling of `ExecLogRow` but multi-agent and Codex-shaped.

### Data model

```swift
enum AgentRunStatus: Equatable { case working, reviewing, done, failed }

struct AgentRun: Identifiable, Equatable {
    let id: String
    let companionId: String      // resolves avatar + accent via PetCharacter.all
    let deptName: String         // "Engineering", "Design", …
    let taskTitle: String        // "Building the waitlist API"
    var steps: [ExecStep]        // reuses the existing ExecStep type
    var status: AgentRunStatus
    let startedAt: Date          // for elapsed display
}
```

Derived (pure, testable) values live in an `AgentRunMath`/computed helpers, not in
the view:
- `stepCounter` → "4/7" (done count / total).
- `currentStepIndex` → first not-`done` step (the spinning one).
- `elapsedString(now:)` → "2:14" from `startedAt` (injected `now` so it's testable
  and preview-stable — no `Date()` inside the view).
- `status` drives the pill label + color: Working (accent), Reviewing (gold),
  Done (teal), Failed (red).

### Layout (per agent row)

```
🟣 Codepet · Engineering        ◐ Working · 2:14        4/7
   Building the waitlist API
   ✓ Scaffold route  ✓ Schema  ◐ Handler  · Tests …
🔵 Luna · Design                ◐ Working · 0:48        2/5
   Landing hero visual pass
   ✓ Moodboard  ◐ Layout  · Type  · Export …
🟢 Sage · Legal                 ✓ Done · 1:02           5/5
   Privacy policy draft
```

- **Avatar**: `CompanionAvatar(companionId:size:28,isWorking:)` — animated only when
  `status == .working`, matching `ExecLogRow`.
- **Header**: `Name · Department` in the companion's accent (reuses the existing
  persona name/color lookup).
- **Status pill**: small capsule, `AgentRunStatus`-tinted.
- **Elapsed** + **step counter** right-aligned, like Codex.
- **Step checklist**: compact — done steps get a teal check, current spins, pending
  sit dim. Reuses the `ExecLog` step visual language so it reads as the same family.
- Container: one `MessageCard` (or a light group) holding the stacked rows, so it
  reads as a single "agents at work" block in the transcript, left-aligned like a
  companion message. Respects Reduce Motion (static avatar + no spin).

### `AgentsWorkingMock`
A `#Preview` feeding 3 `AgentRun`s — two `.working` (different depts, different
step progress) and one `.done` — with a fixed injected `now` so elapsed times are
stable across preview reloads.

## Testing

`AgentsWorkingRowTests` (pure logic, no UI):
- `stepCounter` for 0/N, partial, all-done.
- `currentStepIndex` picks the first not-done step; nil when all done.
- `elapsedString(now:)` formats mm:ss correctly (e.g. 134s → "2:14", 8s → "0:08").
- `status`→pill (label + which color token) mapping is exhaustive over the enum.

The four scenario mocks are `#Preview`-only (visual review), not unit-tested — they
carry no logic beyond fixture construction.

## Follow-on (out of scope, noted for the plan)

1. Wire `AgentsWorkingRow` into the live chat: a source of truth for concurrent
   `AgentRun`s on `CompanyStore`, appended/updated as real runs start/step/finish.
2. Engine support for actually running department agents in parallel.
3. Optional: promote the mock harness into a shared dev "Chat mocks" gallery if we
   want them reachable in a running debug build (today they're Xcode previews).
