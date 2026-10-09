# Suggest the Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A department answering in Ask can offer "Bring Finance + Sales in →". Pressing the offer convenes the room with exactly those departments.

**Architecture:** A new chat tool, `suggest_room`, is coerced into `roomOffer` on the `done` frame. Swift renders `roomOffer` as a card. Pressing the card calls `sendChat(convenesRoom: true, requestedAgents:)`, which threads the agents through to `VirtualCompanyRequest.agents`. `orchestrate.ts` applies `applyRequestedAgents` after intake, so a founder-picked room never escapes.

**Tech Stack:** TypeScript (functions/, jest, esbuild sidecars), Swift/SwiftUI (XCTest).

**Spec:** `docs/superpowers/specs/2026-10-09-suggest-room-design.md`

## Global Constraints
- Native chat keys: `eng design mkt sales support fin ops legal`. Room ids: `engineering design marketing sales support finance operations legal`. The map is `ROOM_AGENT_FOR` in `companyChatCore.ts`.
- An offer needs 2–4 departments. `question` is capped at 300 characters and `why` at 160. A bad offer becomes null and never fails the turn.
- `MAX_ROOM_AGENTS` (4) is the cap. `devils_advocate` takes no seat.
- A payload without `agents` must behave byte-identically to today.
- Run `./scripts/build-sidecar.sh` after any change under `functions/src/`.
- Swift suites run per suite (landmine 3).

## Review Focus
1. **An offer that names only the answering department plus unknown keys.** Expected: null, so no card appears. Pinned in Task 1.
2. **`agents` that includes `chief_of_staff`, `devils_advocate` or `product`.** Expected: those are dropped, and if fewer than 2 remain the room escapes as today. Pinned in Task 2.
3. **Pressing the card twice, or pressing it while a reply is streaming.** Expected: it convenes once and is disabled while streaming. Pinned in Task 4.
4. **A non-department turn where the model calls `suggest_room` anyway.** Expected: the tool is not offered on such a turn, so this cannot happen. Pinned in Task 1 by the tool-list test.
5. **The room's `routing` event after an override.** Expected: it says `multi_agent` with the forced agents, so the UI opens those columns. Pinned in Task 2.

---

### Task 1: `suggest_room` tool → `room_offer` on the done frame
**Files:**
- Modify `functions/src/companyChatCore.ts`: tool const, `coerceRoomOffer`, `ResolvedActions.roomOffer`, `resolveActions`, and the tools list (offered only when `deptKey` maps to a department).
- Modify `functions/src/local/chatSidecar.ts`: `doneFrame` sets `room_offer`.
- Test: `functions/src/__tests__/suggestRoom.test.ts` (create).

**Interfaces — Produces:** `RoomOfferIntent { departments: string[]; question: string; why: string }` with native keys. `coerceRoomOffer(input: unknown): RoomOfferIntent | null`. The done-frame key is `room_offer`.

- [ ] Write failing tests:
  - `coerceRoomOffer` with a valid input;
  - fewer than 2 known keys → null;
  - unknown keys and duplicates removed;
  - more than 4 departments capped to 4;
  - empty `why` → null;
  - clipping to 300 and 160 characters;
  - `resolveActions` returns `roomOffer` alongside `remember`;
  - `doneFrame` includes `room_offer` only when set;
  - the turn assembly lists `suggest_room` only when `dept_key` is a known department (for the last one, find the exported function that builds `tools` and call it with and without `dept_key`).
- [ ] Run `npx jest src/__tests__/suggestRoom.test.ts`. Expected: FAIL (not defined).
- [ ] Implement:

```ts
export interface RoomOfferIntent { departments: string[]; question: string; why: string }
export const SUGGEST_ROOM_TOOL = {
  name: "suggest_room",
  description:
    "Offer to bring other departments into the room on this question. Use ONLY while answering as a department, and only when the question pulls another department's interest the opposite way (price vs. pipeline, speed vs. safety). A one-dimensional question you answer yourself. This is an offer: nothing convenes until the founder presses it, so still give your own answer in the reply.",
  input_schema: {
    type: "object" as const,
    properties: {
      departments: { type: "array", items: { type: "string", enum: Object.keys(ROOM_AGENT_FOR) },
        description: "2-4 department keys, including your own." },
      question: { type: "string", description: "The question for the room, one sentence." },
      why: { type: "string", description: "Why it needs more than you, one short line the founder reads." },
    },
    required: ["departments", "question", "why"],
  },
};
export function coerceRoomOffer(input: unknown): RoomOfferIntent | null {
  const o = (input ?? {}) as Record<string, unknown>;
  const raw = Array.isArray(o.departments) ? o.departments : [];
  const departments = [...new Set(raw.filter((k): k is string => typeof k === "string" && k in ROOM_AGENT_FOR))].slice(0, 4);
  const question = clip(o.question, 300), why = clip(o.why, 160);
  if (departments.length < 2 || !question || !why) return null;
  return { departments, question, why };
}
```

  In `resolveActions`, find the `suggest_room` use and set `roomOffer: use ? coerceRoomOffer(use.input) : null`, independently of the other actions. In the tools list, add `...(deptKey && ROOM_AGENT_FOR[deptKey] ? [SUGGEST_ROOM_TOOL] : [])`. In `doneFrame`, add `if (r.roomOffer) done.room_offer = r.roomOffer;`.
- [ ] Run `npx jest`. Expected: all pass.
- [ ] Commit: `Chat can offer the room: suggest_room on department turns`.

### Task 2: The room honours `agents`
**Files:**
- Modify `functions/src/company/router.ts`: `applyRequestedAgents`.
- Modify `functions/src/company/orchestrate.ts`: `RunPayload.agents?`, `validateRunPayload`, apply after intake.
- Modify `docs/superpowers/specs/virtual-company-sse-contract.md`: the Request table and the escape-hatch sentence.
- Test: `functions/src/__tests__/requestedAgents.test.ts` (create).

**Interfaces — Produces:** `applyRequestedAgents(routing: RoutingDecision, requested: unknown): RoutingDecision`. The payload field is `agents?: string[]`, holding room agent ids.

- [ ] Write failing tests:
  - a `single_agent` routing plus `["finance","sales"]` gives `decision: "multi_agent"` with agents `["finance","sales"]`, and `real_question` is kept;
  - with `devils_advocate` in the router's agents, it is kept and does not count toward the cap;
  - `["finance"]` returns the input unchanged;
  - `["chief_of_staff","devils_advocate","product","finance"]` is unchanged, because only finance is routable;
  - more than 4 is capped;
  - `undefined` is unchanged;
  - `validateRunPayload({...valid, agents: "finance"})` returns an error, and `agents: ["finance"]` returns null;
  - orchestration: `runVirtualCompany` with a fake `call` whose first answer is a `single_agent` routing and whose later calls throw, plus `agents: ["finance","sales"]`. The emitted `routing` has `decision === "multi_agent"`, there are two `agent_start` events, and no `done` with `skipped: "single_agent"`.
- [ ] Run. Expected: FAIL.
- [ ] Implement:

```ts
export function applyRequestedAgents(routing: RoutingDecision, requested: unknown): RoutingDecision {
  if (!Array.isArray(requested)) return routing;
  const picked = [...new Set(requested.filter((a): a is AgentId =>
    typeof a === "string" && (ROUTABLE_AGENTS as readonly string[]).includes(a) && a !== "devils_advocate"))]
    .slice(0, MAX_ROOM_AGENTS);
  if (picked.length < 2) return routing;
  const keepRed = routing.agents.includes("devils_advocate") ? ["devils_advocate" as AgentId] : [];
  return { ...routing, decision: "multi_agent", agents: [...picked, ...keepRed] };
}
```

  Check that `ROUTABLE_AGENTS` excludes product and `chief_of_staff`, and match the real names in `router.ts`. In `orchestrate.ts`, call `const routing = applyRequestedAgents(intake.routing, payload.agents)` right after intake, and use `routing` everywhere `intake.routing` is used below that point. In `validateRunPayload`, add: `agents` not undefined and not a string array → `"agents must be an array of strings"`.
- [ ] Run `npx jest`. Expected: all pass. Update the contract doc.
- [ ] Commit: `A founder-picked room never escapes: agents on the run payload`.

### Task 3: Swift wire — decode `room_offer`, send `agents`
**Files:**
- `codepet/Services/CompanyChatClient.swift`: `RoomOfferDTO`, `ChatDoneAction.roomOffer`, both decoders.
- `codepet/Models/VirtualCompanyRun.swift`: `VirtualCompanyRequest.agents: [String]?`, omitted when nil.
- Test: `codepetTests/RoomOfferWireTests.swift` (create).

**Interfaces — Produces:** `struct RoomOfferDTO: Codable, Equatable { let departments: [String]; let question: String; let why: String }`. `ChatDoneAction.roomOffer: RoomOfferDTO?` with default nil. `VirtualCompanyRequest(request:language:founder:stressTest:agents:)` with `agents: [String]? = nil`.

- [ ] Write failing tests:
  - a `done` JSON with `room_offer` decodes through the stream parser's `DonePayload` path (use whatever the neighbouring suites use to feed an SSE frame);
  - a `VirtualCompanyRequest` with nil `agents` encodes without an `agents` key, and one with `["finance","sales"]` encodes the key.
- [ ] Implement. Add `roomOffer` to `ChatDoneAction.init` with a default of nil, and add the `room_offer` coding key in both decoders. For `VirtualCompanyRequest`, write a custom `encode(to:)` that uses `encodeIfPresent` for `agents`, or rely on the synthesized `encodeIfPresent` for optionals, which `JSONEncoder` already does.
- [ ] Run the suite and the existing `VirtualCompany*` and `CompanyChat*` suites. Expected: all pass.
- [ ] Commit: `Wire: room_offer in, agents out`.

### Task 4: The card and the press
**Files:**
- `codepet/Models/CopilotMessage.swift`: `var roomOffer: RoomOfferDTO?` and `var roomOfferUsed: Bool = false`, declared outside the memberwise init like `tourOffer`.
- `codepet/Managers/CompanyStore.swift`:
  - `handleDoneAction` attaches `roomOffer` to `inlineActionTarget()`;
  - `sendChat(..., requestedAgents: [String] = [])` passes it through `sendMessage` to `startVirtualCompanyRun(..., agents:)` and then to `VirtualCompanyRequest`;
  - add `func acceptRoomOffer(messageId:language:) async`.
- `codepet/Views/Copilot/CopilotChatView.swift`: a card in the inline-actions area under the reply, beside the Noted chip. The label is "Bring Finance + Sales in →", plus the `why` line. It is disabled while `isStreaming || isCompanionTyping`, and shows a used state after it is pressed.
- Test: `codepetTests/RoomOfferTests.swift` (create).

**Interfaces — Consumes:** the Task 3 types. **Produces:** `acceptRoomOffer(messageId:language:)`.

- [ ] Write failing tests:
  - a streamed done with a `roomOffer` puts it on the reply;
  - `acceptRoomOffer` sends a room request whose `agents == ["finance","sales"]` (native keys mapped to room ids) and whose `request` is the offer's question. Inject the VC streamer the way `CompanyStoreVirtualCompanyTests` does;
  - a second `acceptRoomOffer` sends nothing;
  - `roomOfferUsed` is true after the press.
- [ ] Implement. The native→room map lives in Swift as `RoomOffer.roomAgentId(for:)`, mirroring `ROOM_AGENT_FOR`. A test asserts all 8 keys map. `acceptRoomOffer` calls `sendChat(offer.question, language:, convenesRoom: true, requestedAgents: ids)`.
- [ ] Run `RoomOfferTests`, `CompanyStoreChatTests`, `CompanyStoreVirtualCompanyTests` and `ApprovalParityTests`. Expected: all pass. Build Debug.
- [ ] Commit: `Card: bring the departments in, one press`.

### Task 5: Verify in the app, PR
- [ ] Run `./scripts/build-sidecar.sh`, build, and launch. Ask: "Ask Finance: should we discount the Pro plan to close more sales this month?" Check that the card appears, press it, and check that the room convenes with Finance and Sales columns.
- [ ] Push `feat/suggest-room` and open a PR against `main`.
