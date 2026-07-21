# Phase 6C — Inline Chat Deliverable Cards — Design Spec

**Date:** 2026-07-21
**Phase:** 6C of the native=web-product rebuild (Phase 6 = deliverables; 6A model+view + 6B board-generation shipped; 6C = inline chat run + draft/Approve). Anchor: `2026-07-20-native-web-product-architecture.md`. Ties Phase 5 chat + 6A/6B deliverables together.
**Goal:** The Copilot chat can run a task inline — byte says a lead-in line, produces a **draft** deliverable card in the chat with **Approve / Redo**, and Approve promotes it to the Library. Native-only + fail-open (companyChat + runTask CFs ship separately).

---

## Approved decisions (brainstorming)
1. **AI decides, via an extended reply** — the chat reply optionally carries a `runTaskId` (the companyChat CF returns it when byte chooses to run, per the web `run_task` tool). `chatSender` return type changes `String?` → `CompanyChatReply?`. Fail-open: no action → plain chat.
2. **Ephemeral chat-attached draft** — a chat-produced deliverable is a draft on its `CopilotMessage` (session-only). Approve → append to `company.library` + persist. **No `status` field** on `Deliverable` (library = approved work only).
3. Redo **re-runs** the task (not just discard).

## Scope
**In:** the chat contract extension (`CompanyChatReply` + `CompanyChatResponse.runTaskId` + `chatSender` type change); `CopilotMessage.draft`/`draftApproved`; a shared `buildDeliverable` helper (centralizes the 6A gates, used by both `runTask` and the chat-run); `sendChat` run-integration; `CompanyStore.approveDraft`/`redoDraft`; the inline deliverable card in `CopilotBubble` (Approve/Redo + open detail).
**Out (later):** the CFs themselves (node-22); byte's streaming lead-in (single-reply stays); a "navigate" chip / other tools; persisting drafts across relaunch; dedup.

## Components

### 1. Chat contract extension (`CompanyChatClient.swift`, Phase-5 seam)
- `struct CompanyChatReply { let text: String; let runTaskId: String? }`.
- `CompanyChatResponse` gains `runTaskId: String?` (CodingKey `run_task_id`).
- `CompanyChatClient.send(_:) async -> CompanyChatReply?` (was `-> String?`) — returns `CompanyChatReply(text:, runTaskId:)` on a 200 with non-empty reply, else nil (fail-open unchanged).
- **`chatSender` type changes** `(CompanyChatRequest) async -> String?` → `(CompanyChatRequest) async -> CompanyChatReply?` on `CompanyStore` (the Phase-5 chat test stubs update to return `CompanyChatReply`).

### 2. Draft model (`CopilotMessage.swift`)
`CopilotMessage` gains `var draft: Deliverable?` (nil) + `var draftApproved: Bool` (false); the init defaults both. Stays `Identifiable, Equatable` (`Deliverable` is Equatable). A companion message with `draft != nil` renders the inline card.

### 3. Shared `buildDeliverable` + `runTask` refactor (`CompanyStore.swift`)
`private func buildDeliverable(from result: RunTaskResponse?, task: RoadmapTask) -> Deliverable?` — the 6A gates in one place: returns nil if `result` is nil or the trimmed body is empty; else `Deliverable(id: UUID().uuidString`, `kind: DeliverableKind(raw: result.kind)`, `title:` non-empty `result.title` else `task.title`, `body:` trimmed, `createdAt: ISOTime.utc(Date())`, `sourceTaskId: task.id)`. **6B's `runTask` is refactored to call this** (behavior unchanged; the gates now live once).

### 4. `sendChat` run-integration (`CompanyStore.swift`)
`sendChat` keeps `isCompanionTyping = true` through the whole exchange:
1. append user msg; `isCompanionTyping = true`.
2. `reply = await chatSender(req)`; capture `cid`; guard `companyId == cid`.
3. append the companion **lead-in** bubble (`reply?.text` or the offline message).
4. if `reply?.runTaskId` names a **runnable** task (`company.tasks.first(where: id)` with `RoadmapEngine.status(for:in:) == .codepetCanDo`): build its `RunTaskRequest`, `result = await taskRunner(req)`, guard `companyId == cid` again; append a companion message with `draft = buildDeliverable(...)` when non-nil, else an honest companion bubble ("Couldn't generate that — try again." / VI).
5. `isCompanionTyping = false`.

### 5. Approve / Redo (`CompanyStore.swift`)
- `func approveDraft(messageId: String) async` — find the message; guard it has an un-approved `draft`; append the draft to `company.library`; set `draftApproved = true`; persist via `librarySaver` (6B).
- `func redoDraft(messageId: String, language: AppLanguage) async` — find the message + its un-approved draft + the task by `draft.sourceTaskId`; re-run via `taskRunner`; `companyId`-guard; on a valid rebuild, replace the message's `draft` (else leave it). No-op if the task is gone.

### 6. Inline card (`CopilotChatView.swift` → `CopilotBubble`)
`CopilotBubble` gains `@EnvironmentObject companyStore`, `@Environment(\.uiLanguage)`, and a `@State` sheet flag. When `message.draft != nil`: render a `CodepetCard` (kind icon + title + a short body preview) with **Approve** / **Redo** buttons; when `draftApproved` → "Added to Library ✓" (no actions). Tapping the card opens `DeliverableDetailView(deliverable:)` (reuse 6A) in a `.sheet`. Approve → `Task { await companyStore.approveDraft(messageId:) }`; Redo → `Task { await companyStore.redoDraft(messageId:language:) }`.

## Data flow
User message → `chatSender` → `CompanyChatReply(text, runTaskId?)` → lead-in bubble; if `runTaskId` is runnable → `taskRunner` → draft `Deliverable` on a companion message → inline card. Approve → `company.library` (@Published, persisted) → shows in `LibraryView`. Redo → re-run → replace draft.

## Error handling
Fail-open: `chatSender`/`taskRunner` nil → honest companion bubbles, never a throw/block/malformed draft (the `buildDeliverable` body-guard). Drafts session-only until Approve; `reset()`/account-switch already clear `chatMessages` (drafts ride along); the run-integration re-checks `companyId == cid` after each await.

## Testing
- `sendChat` (stub `chatSender` returning `CompanyChatReply(text, runTaskId)` + stub `taskRunner`): a matching **runnable** `runTaskId` → a companion draft message appears (draft **not** in `company.library`, unique id, canonical `createdAt`, `sourceTaskId == task.id`); a non-runnable / unknown `runTaskId` → lead-in only, no draft; `taskRunner` nil/empty → honest bubble, no draft; account switch mid-run → discarded.
- `approveDraft` → draft appended to `company.library` + persisted (librarySaver) + `draftApproved == true`; a second approve is a no-op.
- `redoDraft` → the message's draft is replaced (new id/body); no-op if the task is gone.
- Contract: `CompanyChatReply`/`CompanyChatResponse` round-trip incl. `run_task_id`; the Phase-5 chat tests updated to the new stub return type still pass.
- `CopilotBubble` card + `DeliverableDetailView` sheet verified by build.

## Reuse / references
| Source | Native target |
|---|---|
| web `/api/chat` `run_task` tool (lead-in + inline deliverable + Approve/Open/Redo) | `sendChat` run-integration + `CopilotBubble` card |
| `CompanyChatClient` (Phase 5) | extended reply contract |
| `RunTaskClient`/`taskRunner` + the 6A gates (6B) | shared `buildDeliverable`, chat-run |
| `CompanyData.saveLibrary` (6B) | Approve persistence |
| `DeliverableDetailView`/`MarkdownView` (6A) | card detail sheet |

## Open decisions
None — resolved in brainstorming (AI-decides via extended reply; ephemeral chat-attached drafts; Approve→Library; Redo re-runs). Ready for implementation planning.
