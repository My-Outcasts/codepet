# Phase 5 — Copilot Chat — Design Spec

**Date:** 2026-07-21
**Phase:** 5 of the native=web-product rebuild. Replaces the placeholder Copilot column with a native company-grounded chat. Anchor: `2026-07-20-native-web-product-architecture.md`. Consumes `CompanyStore` (brief/tasks/companionId), `BriefContext.compose`, `RoadmapEngine`, CodepetTheme.
**Goal:** A native SwiftUI Copilot chat: the founder talks to their company's AI companion, grounded on the company brief + roadmap. Conversational only — running tasks / producing deliverables is Phase 6.

---

## Approved decisions (brainstorming)
1. **Backend: native-only, fail-open.** Build the native chat + a fail-open `CompanyChatClient.send` that POSTs to a planned `companyChat` Cloud Function. The CF (port of web `/api/chat` minus the run_task tool) is authored + deployed **separately** (bundled with the node-22 `scaffoldRoadmap` deploy), like roadmap. Until it deploys, the client returns nil and the chat shows an honest offline message.
2. **Reply mode: single reply / await** (typing indicator while waiting). Streaming deferred.
3. **Persistence: session-only, in-memory** on `CompanyStore`; cleared on relaunch / account switch.

## Scope
**In:** `CopilotMessage`/`CopilotRole`; `ChatContext.compose` (pure grounding); `CompanyChatClient` (DTOs + fail-open `send`); `CompanyStore` chat state + `sendChat` (token-guarded, fail-open, injectable sender); `CopilotChatView` (+ bubble) replacing the Copilot placeholder in `AppShellView`.
**Out (later):** the `companyChat` Cloud Function itself (separate authoring + node-22 deploy); streaming; run_task/deliverables (Phase 6); persisted chat threads; navigate/setup tool chips.

## Components

### 1. `CopilotMessage` (`codepet/Models/CopilotMessage.swift`)
`enum CopilotRole { case me, companion }`. `struct CopilotMessage: Identifiable, Equatable { let id: String; let role: CopilotRole; let text: String }` (id = `UUID().uuidString` at creation). Named to avoid the reflection `ChatMessage`.

### 2. `ChatContext.compose` (`codepet/Models/ChatContext.swift`, pure)
`static func compose(brief: CompanyBrief, tasks: [RoadmapTask]) -> String` — assembles the grounding string sent to the CF:
- brief via `BriefContext.compose(brief)` (or a "No brief yet." line when nil),
- a roadmap summary: `RoadmapEngine.nextStep(tasks)?.title` (next step), `RoadmapEngine.progressPercent(tasks)` (progress), and up to the first ~6 not-done task titles.
Pure → unit-tested. Returns a non-empty string even when brief/tasks are empty.

### 3. `CompanyChatClient` (`codepet/Services/CompanyChatClient.swift`)
DTOs (Codable, snake_case CodingKeys mirroring the existing client convention):
- `ChatTurnDTO { role: String; text: String }` (role = "me" | "companion").
- `CompanyChatRequest { companyId: String?; language: String; companionId: String; context: String; history: [ChatTurnDTO]; userMessage: String }`.
- `CompanyChatResponse { reply: String }`.
`enum CompanyChatClient { static func send(_ req: CompanyChatRequest) async -> String? }` — POSTs to `companyChatEndpoint` (`https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat`); returns `reply` on 200, **nil on any error / non-200 / unreachable** (fail-open at the client boundary, so callers never handle throws). Mirrors the `enrichBrief` transport.

### 4. `CompanyStore` chat state
- `@Published private(set) var chatMessages: [CopilotMessage] = []`; `@Published private(set) var isCompanionTyping = false`.
- Injectable `chatSender: (CompanyChatRequest) async -> String?` (init default `CompanyChatClient.send`).
- `func sendChat(_ raw: String, language: AppLanguage) async`:
  1. `text = raw.trimmed`; guard non-empty and not already typing.
  2. Append `CopilotMessage(.me, text)`; `isCompanionTyping = true`.
  3. Build `CompanyChatRequest` (companyId, language.rawValue, `company.companionId`, `ChatContext.compose(brief: company.brief, tasks: company.tasks)`, history = prior `chatMessages` mapped to `ChatTurnDTO` capped to last 20, userMessage = text).
  4. Capture `token = hydrationToken`; `reply = await chatSender(req)`.
  5. Guard `token == hydrationToken` else return (account switch superseded → discard; reset already cleared state).
  6. Append `CopilotMessage(.companion, reply)` if non-nil, else the honest offline message ("I can't reach my brain right now — try again in a bit." / VI "Mình không kết nối được lúc này — thử lại sau nhé."). `isCompanionTyping = false`.
- `reset()` also clears `chatMessages` + `isCompanionTyping`.

### 5. `CopilotChatView` (`codepet/Views/Copilot/CopilotChatView.swift`) + wiring
- Reads `@EnvironmentObject companyStore`, `@EnvironmentObject appState` (active char image optional), `@Environment(\.uiLanguage)`.
- **Message list**: `ScrollViewReader` + `ScrollView` of `CopilotBubble` per `companyStore.chatMessages` (me = accentPurple fill, white text, right-aligned; companion = surface fill, primary text, left-aligned), auto-scrolls to the last message; a typing indicator row when `isCompanionTyping`.
- **Empty state**: a companion greeting using `PetCharacter.all[company.companionId]?.name ?? "Codepet"` ("Hi, I'm {name}. Ask me anything about your company." / VI).
- **Input**: `TextField(axis: .vertical)` + send button; `onSubmit`/tap → `Task { await companyStore.sendChat(draft, language: lang) }`, then clear `draft`; disabled while `isCompanionTyping`.
- **Wiring**: `AppShellView`'s `copilot` column renders `CopilotChatView()` (keep the `!copilotCollapsed` toggle + `width: 300`).

### 6. Error handling
Fail-open end-to-end: the client returns nil on any failure; `sendChat` appends one honest companion message and always clears `isCompanionTyping`; input never locks (beyond the in-flight guard). Token-guarded so an account switch mid-reply can't append A's reply into B's chat.

## Testing
- `CompanyStore.sendChat` (stub sender): success → user + companion messages appended, typing cleared; nil sender → honest offline message appended (fail-open); token-guard discards a superseded reply; empty/whitespace input is a no-op; a second send while typing is ignored.
- `ChatContext.compose`: includes brief signal + next-step + progress; empty brief/tasks → still a non-empty string.
- `CompanyChatClient` DTOs: Codable round-trip (snake_case keys). `CopilotMessage` Equatable/Identifiable.
- `CopilotChatView` verified by build (no logic lives in it).

## Reuse / references
| Source | Native target |
|---|---|
| web `/api/chat` route (company grounding, minus tools) | `companyChat` CF contract → `CompanyChatRequest`/`Response` |
| existing `ChatMessageDTO {role,text}` + reflection chat panel/bubble/input | `ChatTurnDTO` + `CopilotChatView`/`CopilotBubble` patterns |
| `ReflectionAPIClient` endpoint-per-CF + enrichBrief transport | `CompanyChatClient.send` |
| `BriefContext.compose`, `RoadmapEngine.nextStep`/`progressPercent`, `PetCharacter.all` | `ChatContext.compose`, greeting |

## Open decisions
None — resolved in brainstorming (native-only fail-open; single reply; session-only; honest offline message; clear on account switch). Ready for implementation planning.
