# Handoff — Chat redesign + parallel fan-out (feat/chat-redesign)

**Date:** 2026-07-29
**Branch:** `feat/chat-redesign` — pushed, `origin` in sync at `454a4b9` (clean tree)
**Repo:** My-Outcasts/codepet @ native macOS SwiftUI app (scheme `codepet` lowercase, bundle `app.murror.codepet`)
**PR #39** — held (NOT merged), by design.

---

## What shipped this session

1. **Chat spacing** — message spacing 24 + `lineSpacing(4)` to match Claude/ChatGPT breathing room.
2. **Agents-working inline UI** (Codex-inspired) — `AgentsWorkingRow.swift`: `AgentRun` (id/companionId/deptName/taskTitle/steps/status/startedAt, computed stepCounter/currentStepIndex/elapsedString) + `AgentsWorkingRow(runs:now:)`.
3. **Live parallel fan-out engine** — `CompanyStore.fanOutNextMoves(language:)` uses `withTaskGroup` to run up to `maxFanOut = 3` department agents in parallel (real parallel network I/O). `RoadmapEngine.nextMoves(_:limit:)` picks first `codepetCanDo` task per distinct dept (roadmap order, capped). Per-branch `companyId == cid` re-check for account-switch safety.
4. **"Run my next moves" quick-action chip** + typed-phrase routing — `isFanOutPhrase(_:)` matches EN/VI phrase in `send()` and `runQuickAction()`.
5. **Guided one-at-a-time flow (mock)** — `MockChat.route()` branches: summarize → focus (suggest ONE task+dept, preview next) → run → approve → what's next. Script starts "Let's summarize my project" → "What should I focus on now?".
6. **Offline mock testbed (zero API spend)** — `MockChat` wired via `CODEPET_MOCK_CHAT` into RunTaskClient, CompanyChatClient (send/sendStream), CompanyData (fetchRoadmap + load). Dev gallery via `-CODEPET_MOCK_GALLERY YES` → `ChatMocksGalleryView`.

### Fixes
- `20c7223` — typed "Run my next moves" now fans out (was matching single-run "run").
- `d12f89f` — strip `**` bold markers from mock replies (`MockChat.reply/stream`).
- `454a4b9` — **duplication fix**: `produceDraftInline` marks task `drafted=true` on success; `approveDraft` sets source task `done=true` + clears draft, persists via tasksSaver/librarySaver. Chat-run path now advances the roadmap like the board path, so a completed task leaves the "next moves" set (no re-suggest/re-run).

---

## Current runtime state
App is running in mock mode (launched `open --args -CODEPET_MOCK_CHAT YES`).

### Test the guided flow (start a NEW chat)
1. `Let's summarize my project`
2. `What should I focus on now?` → suggests **Design your brand look**
3. `run it` → Design draft card
4. **Approve**
5. `What's next?` → should suggest a **different** task (Write your landing page copy · Marketing), no repeat.

Repeat run → Approve → What's next walks forward one task at a time, no duplicates.

---

## Tests
- `CompanyStoreFanOutTests` — 6/6 PASS (sets `execStepNanos=1000` in setUp).
- `RoadmapEngineNextMovesTests` — 4/4 pass.
- `CompanyStoreChatRunTests` — shows **0 tests executed + TEST FAILED**. This is the **environmental Firebase test-host flake** (running app holds Firestore LevelDB LOCK; Xcode-26 host launch), NOT caused by these changes. To run cleanly: close the app first, then `xcodebuild test`, and count executed tests. See memory `codepet-firestore-lock-blocks-tests`.

---

## Build / launch (standing constraints)
- TEAM-signed only:
  `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates` (adhoc breaks keychain/sign-in).
- Serialize vs sibling session: before `open`, `ps aux | grep codepet.app`; never kill an instance whose parent is Xcode debugserver / a different DerivedData (`CodePet-devppeuyaafhelgjfyfruoyyxewb`). Kill by pid only your own instance.
- Rebase over sibling commits before pushing feat/chat-redesign (push races).
- Mock launch: `open <path>/codepet.app --args -CODEPET_MOCK_CHAT YES` (add `-CODEPET_MOCK_GALLERY YES` for the preview gallery).

---

## Key files
- `codepet/Views/Copilot/CopilotChatView.swift` — chat UI, fan-out wiring, isFanOutPhrase, AgentsWorkingRow render.
- `codepet/Views/Copilot/AgentsWorkingRow.swift` — agents-working component.
- `codepet/Managers/CompanyStore.swift` — activeAgentRuns, isFanningOut, maxFanOut, fanOutNextMoves, runFanOutAgent, produceDraftInline/approveDraft (dup fix).
- `codepet/Models/RoadmapEngine.swift` — nextMoves(_:limit:).
- `codepet/Services/MockChat.swift` — router, canned company/roadmap/deliverable, ** stripping.
- `codepet/Services/CompanyData.swift` — mock load() hook.
- `codepet/Views/Copilot/Mocks/` — ChatMockData, ChatMocksGalleryView, per-section mocks.
- Tests: `codepetTests/CompanyStoreFanOutTests.swift`, `RoadmapEngineNextMovesTests.swift`.
- Specs/plans: `docs/superpowers/specs/`, `docs/superpowers/plans/`.

---

## Open / next candidates (not started)
- Wire the fan-out to the REAL guided-flow product path (currently the one-at-a-time guidance lives in MockChat; live-mode next-step guidance is the follow-on).
- Investigate `CompanyStoreChatRunTests` host-launch flake separately if desired.
- Merge decision for PR #39 (still held).
