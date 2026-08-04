# Virtual Company in the Copilot Chat — Design

**Date:** 2026-08-03
**Status:** Approved design → ready for implementation plan
**Branch:** `feat/virtual-company-in-chat` (off `main` @ `3ba4c0c`)
**Target:** `main`
**Backend:** already live. `virtualCompanyRun` deployed to `us-central1`, tier 3 verified end to end (`docs/superpowers/virtual-company-test-runbook.md`). This document covers the client only.
**Contract:** `docs/superpowers/specs/virtual-company-sse-contract.md` — build against that document, not against `functions/src/company/`.

---

## 1. Goal

When the founder types a decision into the copilot chat, the company convenes **on its own**. No mode to select, no screen to open, no button. Product and finance answer independently, their disagreement surfaces, and a brief lands in the same conversation the founder was already having.

Ordinary chat must be untouched. A founder who types "hi" should never learn that a routing decision happened.

## 2. Non-goals (v1)

- **A separate meeting-room screen.** The dock is 380pt wide, so positions stack vertically rather than sitting in columns. Columns would need a new full-width destination; not now.
- **Founder-initiated convening.** No "ask the company" button. If the router's escape hatch turns out to be wrong too often, that is the evidence for adding one — not a guess up front.
- **Persisting runs.** The blackboard already persists server-side (`saveBlackboard`). Client-side history of past runs is out of scope; chat threads are session-only today and this follows that.
- **Rendering `negotiation_round` turn by turn as it streams.** Rounds arrive as whole events; they render as they arrive.
- **Touching onboarding.** Another engineer owns it.

## 3. Trigger: the router's escape hatch, not a heuristic

`CompanyStore.sendChat` fans out to two endpoints at once:

```
message ─┬─→ companyChat        (existing; streams immediately, always completes)
         └─→ virtualCompanyRun  (new; Haiku intake, ~2s)
                   │
       ┌───────────┴────────────┐
  single_agent /           multi_agent
  needs_clarification           │
       │                   the room APPENDS its own companion
  run discarded,           message under byte's reply and fills
  chat unaffected          it in as the frames arrive
```

**Why parallel rather than sequential.** Intake costs about $0.005 and takes ~2s. Running it first would put that 2s in front of *every* message, including "hi", before the first character appears. Running both means ordinary chat keeps its current latency exactly. The price is that a decision message pays for a `companyChat` reply that gets superseded.

**Why no client-side gate.** A heuristic on length or on words like "hay"/"or" misses real decisions ("mình đang lo runway") and cannot reframe. The router already does this job better — measured: it turned "tăng giá hay ship team feature" into "do you have product-market fit, or are you optimizing packaging before validating that anyone will pay". Tier 2 confirmed both escape-hatch branches fire correctly on real questions.

**Handoff copy.** On `routing` with `decision == "multi_agent"`, byte's reply is left to finish normally and the room arrives as a **new appended companion message**, opening with one line in byte's voice — "Thật ra cái này cần cả phòng — để mình gọi product với finance vào" — followed by the room cards, which fill in as later frames arrive. The founder sees a companion escalating, not a UI mode switch.

**Appended, not written into byte's message.** The first implementation replaced byte's in-flight reply, and every serious defect in the first review traced back to that one decision:

- The transcript scrolls on `chatMessages.count` (`CopilotChatView:184`). A run rendered inside an already-appended message never changes the count, so 30–60s of cards grew below the viewport and the founder watched a static handoff line — then the interview's appended message finally moved the count and scrolled *past* the whole room.
- byte's turn could not end, so `isCompanionTyping` stayed up and the typing dots sat pinned under the room's cards for the whole run.
- byte's `done` side effects (`drafted = true`, `tasksSaver`, auto-merged `remember` decisions) still fired on a turn the founder had been told was superseded, and could contradict the brief they were about to lock in.
- `virtualCompanyRun` cold-starts in 5–10s while byte's stream can finish in 4, so on the first decision of a session the routing frame usually arrived *after* the founder had read the answer. Rewriting it then was a defect, which needed a closed-turn guard, which in turn meant the room did not convene at all on a cold start.

A separate message retires all four: the append is the count change the scroll already listens for, byte's turn is real and owns its own effects, and a late-arriving room is a new message rather than a rewrite. The run is therefore not awaited — it does not hold `isStreaming`, so Send, New chat and the thread switcher stay live throughout.

The room is still bound to the conversation it was asked in: `publishRunProgress` refuses to write unless byte's message for that turn is still in the buffer, so a run that lands after New chat / a thread switch / a delete is dropped rather than appearing under an unrelated question. It also carries a client-side deadline (`CompanyStore.vcRunDeadlineNanos`), because `SSEParser` drops `:` keep-alive comments and a warm-but-silent connection would otherwise leave the agent columns spinning forever; the deadline cancels into the same seal a dropped stream reaches.

The price of letting byte answer is that the founder reads a general reply and then a better one. Cheaper than the alternative: byte's answer *is* what the founder has if the room fails, is killed (503) or is capped (429).

## 4. Architecture

### 4.1 New files

| File | Responsibility |
|---|---|
| `codepet/Services/VirtualCompanyClient.swift` | The only thing that talks to `virtualCompanyRun`. Same shape as `CompanyChatClient.sendStream`: `URLSession.bytes(for:)`, bytes fed through the existing `SSEParser`, `AsyncThrowingStream` of typed events, typed throw on non-200. `session` and `authTokenProvider` injectable so tests exercise decoding with no network. |
| `codepet/Models/VirtualCompanyRun.swift` | `Codable` DTOs mirroring `functions/src/company/types.ts` field for field, plus `VirtualCompanyRunState` — the observable the cards bind to. |
| `codepet/Models/FounderContextMapper.swift` | `CompanyBrief` → the request's `founder` object. Pure and unit-testable; no store, no network. |
| `codepet/Views/Copilot/VirtualCompanyCards.swift` | `RoutingCard`, `PositionCard`, `ConflictCard`, `BriefCard`, built on the existing `MessageCard` chrome. |

### 4.2 Changed files

| File | Change |
|---|---|
| `codepet/Managers/CompanyStore.swift` | Fan-out in `sendChat` (typed founder text only — never `walkThroughTask`'s synthesised ask); the room's appended message on `routing`; the constraints interview gate. |
| `codepet/Models/CopilotMessage.swift` | One new optional payload field for a run, following the existing fat-struct/if-chain pattern. The chat-first redesign's enum refactor is explicitly out of scope (`2026-07-31-coding-agent-in-copilot-design.md` §2). |
| `codepet/Views/Copilot/CopilotChatView.swift` | Render the new cards when a message carries a run. |
| `codepet/Models/Department.swift` | Add a `product` entry. The SSE contract (line 161) already asks for this: the backend emits `department_key: "product"` and `Department.all` has no such key, so the column would render with no cover, name or accent. |

### 4.3 Event → UI mapping

Phase 2 reuses `AgentsWorkingRow` unchanged. It already renders N concurrent department agents with avatar, name·dept, status pill and elapsed time, driven today by `runTask` fan-out. The contract's guarantee that every `agent_start` arrives before any `agent_position` is what makes the row open all its columns at once.

| Event | UI |
|---|---|
| `run_started` | Nothing visible; state moves to running |
| `routing` | `RoutingCard` — **content, not a spinner.** Shows `real_question` alongside what was asked, and per-agent include/exclude reasons |
| `agent_start` × N | One `AgentsWorkingRow` with all agents at `.working` |
| `agent_position` | That agent flips to `.done`; a `PositionCard` appends (stance, confidence, cost to their dept, hard blocker) |
| `agent_error` | That agent flips to `.failed` with its message. The run continues |
| `conflicts` | `ConflictCard`. Not collapsed, not in an accordion — the contract calls this the highest-value view in the feature |
| `negotiation_round` | Appended under the conflict, one block per round |
| `devils_advocate` | Its own card with a distinct visual identity — **no department colour.** It is not a department |
| `brief` | `BriefCard`, with the "Chốt quyết định này" action (§6) |
| `run_stopped` | Reason shown **verbatim**; a `done` still follows |
| `telemetry` | Cost line on the brief card |
| `done` | State moves to finished |
| `error` | §7 |

### 4.4 Where the founder context comes from

`CompanyBrief` carries `role`, `tech`, `stage`, `oneLiner`, `goal`, `traction`, `problem`, `audience`. It carries **no runway and no constraints**.

That gap is not cosmetic. Measured at tier 2: with constraints present, departments produce concrete hard blockers ("do not build seats before one pricing test"); with `constraints: []` the same question yields noticeably vaguer positions.

Mapping:

| Request field | Source |
|---|---|
| `founder.profile` | `role`, `tech`, `founderName` |
| `founder.stage` | `stage`, `traction`, `oneLiner`, `goal` |
| `founder.constraints` | The interview below |
| `language` | `uiLanguage` |

**The interview cannot interrupt a run.** All five phases happen inside one HTTP request, so there is no point at which the client can stop after intake, ask a question, and resume. Aborting mid-stream would not help either: the function keeps working after a client disconnect, so we would pay for the whole run and throw it away.

So the first decision runs with whatever the brief holds, and the interview comes **after** it:

1. Run proceeds with `constraints: []`. The backend is honest about thin input — `what_we_dont_know` says what it was missing rather than inventing numbers.
2. When that brief lands, byte follows it with the interview card: the brief was thin on the founder's own numbers, two questions will sharpen the next one.
3. Two `InterviewGap` questions, reusing `CompanyStore.askInterviewGap` / `answerInterview` (already a queue with its own card):
   - Runway — how long the current money lasts.
   - Hard constraints — anything the company must not propose (no hiring, a ship date, no outside investment).
4. Answers persist into the brief. Asked once, never again; skipping is allowed and only means later briefs stay as thin as the first.

This trades a vaguer first brief for never blocking the founder mid-thought. The alternative — interrogating them before they get anything — is worse for a feature whose whole promise is that it convenes on its own.

## 5. What is NOT rebuilt

The point of putting this in chat is that the hard parts already exist on `main`:

| Piece | Status |
|---|---|
| SSE frame parsing (`SSEParser`) | Exists, used by `CompanyChatClient` and `ReflectionAPIClient` |
| Streaming client shape, injectable session + token provider | Exists, copy the shape |
| Concurrent multi-agent row | Exists (`AgentsWorkingRow`, 148 lines) |
| Card chrome | Exists (`MessageCard`) |
| Interview gap ask/answer queue | Exists in `CompanyStore` |
| Decisions store and its chat grounding | Exists (`Decisions.swift`, `ChatContext.swift:84`) |
| Department covers, accents, status pills | Exists (`Department.swift`) |

## 6. The brief feeds Decisions — but only when the founder says so

`BriefCard` carries one action: **Chốt quyết định này** →

```
Decisions.upsert(topic: routing.real_question,
                 statement: brief.recommendation,
                 source: "virtual-company/\(runId)")
```

`Decisions` already grounds both chat and `runTask` (`ChatContext.swift:84` — "Do not contradict the naming, pricing, positioning, or decisions already delivered"), so a locked-in decision stops the rest of the app from arguing against a call the founder has made.

**Not automatic**, for two reasons. The app's own pattern is approve-then-record: `DecisionsClient.extract` takes an `ApprovedDeliverableDTO`, never a draft. And the brief exists precisely to hand the founder a trade-off nobody else can make — recording it as decided before they decide would put words in their mouth.

## 7. Failure behaviour

| Case | Behaviour |
|---|---|
| `event: error` (terminal, no `done` follows) | Keep the `companyChat` reply if one arrived; otherwise byte's existing offline line. Never a raw error string |
| HTTP 503 `feature_disabled` | Kill switch. Discard the run silently; chat is untouched and the founder sees nothing |
| HTTP 429 `daily_limit_reached` | Same: chat unaffected |
| HTTP 400 `invalid_payload` | A client bug, not a founder-facing state. Log the `detail`, discard the run |
| `agent_error` mid-run | That column only; the run and the brief still complete |
| `run_stopped` | Budget ceiling. Show `reason` verbatim, then the partial result |

The rule: **a failed run must never damage the chat.** Ordinary chat worked before this feature and must keep working when the feature is unavailable.

## 8. Testing

No network in tests. Following `CompanyChatClient`'s existing pattern:

- `FounderContextMapper` — brief-with-everything, brief-with-nothing, brief-with-constraints-only.
- Event decoding — a fixture byte stream per contract shape, including the escape-hatch stream (`run_started → routing → telemetry → done`), the terminal-`error` stream, and a `run_stopped` stream.
- Handoff logic — `multi_agent` cancels the chat placeholder; `single_agent` leaves it alone.
- The constraints gate — fires once with empty constraints, never again once answered, and proceeds on skip.
- Degradation — 503/429/400 leave `chatMessages` byte-identical to a no-feature run.

## 9. Cost

| Message kind | Added cost |
|---|---|
| Ordinary chat | +$0.005 (Haiku intake) |
| Decision | ~$0.20 for the run, plus byte's own `companyChat` reply — which is kept, not superseded, and is the whole answer if the run fails or is killed |

Per-run server ceilings already exist: 200k tokens / $1.50, emitting `run_stopped` rather than truncating silently.

## 10. Open, deliberately not solved here

- **`detectConflicts` reports a false `BLOCKER`** when both departments file hard blockers pointing the same way. Negotiation then runs on a disagreement that does not exist — two wasted Sonnet calls. Synthesis notices and says so in the brief, so this is a cost problem, not a correctness one. Fixing it means comparing free-text intent.
- **Roster is 4 agents against the UI's 8 departments.** Product call, not an engineering one.
- **Devil's advocate visual identity.** The contract forbids giving it a department colour but does not say what it should look like. Needs a design answer before that card is more than a plain panel.
