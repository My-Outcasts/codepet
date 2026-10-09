# Suggest the room — design

Status: approved in chat 2026-10-09. Step 3 of "one founder runs the whole company". Step 1
(#247) made a department answer as itself, and step 2 (#248) gave it a notebook. This step lets
a department say "this one needs Sales too" and gives the founder a button that does it.

## Problem

Since #247 a department in Ask is told that the lines in its role about other departments mean
it should say "this one needs Marketing too". It says so, and the founder can do nothing
with that. The room convenes only in Plan mode, and even there `chief_of_staff` picks the
departments. If it decides `single_agent`, the room is discarded (`orchestrate.ts`, escape
hatch).

## Design

### 1. Chat tool `suggest_room` (`companyChatCore.ts`)
- Input: `{ departments: string[], question: string, why: string }`.
- `departments` uses native keys (`eng design mkt sales support fin ops legal`), 2–4 of them,
  and should include the department that is answering.
- The description says to use it only while answering as a department, when the question
  pulls another department's interest the other way. A one-dimensional question is answered,
  not escalated.
- `coerceRoomOffer`:
  - keeps only known keys and de-duplicates them;
  - caps at 4 departments;
  - returns null under 2 departments, an empty `question`, or an empty `why`;
  - clips `question` to 300 characters and `why` to 160.

  A bad offer is dropped. It never fails the turn.
- Resolved independently of the run/nav/setup chain, like `remember_fact`.
- It is an **offer**. Nothing convenes, and nothing costs the ~$0.20 of a room, until the
  founder presses it.

### 2. The card (Swift)
- `ChatDoneAction.roomOffer: RoomOfferDTO?` becomes `CopilotMessage.roomOffer`.
- The card under the reply reads "Bring Finance + Sales in →" with the `why` line.
- Pressing it calls
  `sendChat(question, language:, convenesRoom: true, requestedAgents: [room agent ids])` and
  marks the offer used. A used offer cannot be pressed twice.
- The card is not offered in prototype mode unless the mock streams one. That is the existing
  behaviour for every chat tool.

### 3. The room honours the founder's pick (`orchestrate.ts`)
- The run payload gains an optional `agents: string[]` holding room agent ids
  (`finance`, `sales`, …).
- `validateRunPayload` returns 400 if `agents` is present and not an array of strings.
- After intake, `requestedAgents(payload.agents)` keeps the routable departments,
  de-duplicates them and caps them at `MAX_ROOM_AGENTS`.
- If at least 2 survive, routing becomes `decision: "multi_agent"` with those agents. If the
  router named `devils_advocate`, it is kept too, because it takes no seat in the cap.
- The router's `real_question` and `request_type` are kept.
- The `routing` event carries the overridden decision, so the client renders the room it is
  about to get.
- Fewer than 2 surviving agents, or no `agents` at all, leaves today's behaviour unchanged.
- `docs/superpowers/specs/virtual-company-sse-contract.md` is the authority. It gets the new
  field in its Request table, plus one sentence under the escape hatch: a founder-picked room
  never escapes.

### 4. Not touched
Plan-mode fan-out, the four-seat cap, `devils_advocate` routing, the cost of an Ask turn, and
`chief_of_staff`'s prompt.

## Tests
- jest:
  - `coerceRoomOffer`: valid offers, too few departments, unknown keys, de-duplication, the
    cap, empty `why`, and clipping;
  - the tool is listed in the chat tools;
  - `resolveActions` surfaces `roomOffer` alongside `remember`;
  - `validateRunPayload` rejects a non-array `agents`;
  - orchestration with a router that returns `single_agent`: with 2 valid `agents` it runs the
    room with exactly those, without them it escapes, and with 1 valid agent it escapes;
  - the cap and keeping `devils_advocate`.
- Swift:
  - `ChatDoneAction` decodes `room_offer`;
  - pressing the card sends `agents` and the question, and convenes;
  - the card can be used once.
- In the app: ask Finance "should we discount to drive sales?", check that the card appears,
  press it, and check that the room convenes with Finance and Sales.
