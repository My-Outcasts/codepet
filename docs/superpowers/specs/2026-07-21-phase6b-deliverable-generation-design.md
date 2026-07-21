# Phase 6B — Deliverable Generation — Design Spec

**Date:** 2026-07-21
**Phase:** 6B of the native=web-product rebuild (Phase 6 = deliverables; 6A model+view shipped, 6B = generation, 6C = inline chat cards). Anchor: `2026-07-20-native-web-product-architecture.md`. Builds on 6A (`Deliverable`/`DeliverableKind`, `CompanyState.library`, `LibraryView`) + roadmap (3A/3B: `RoadmapTask`, `RoadmapEngine`, `TaskCardView`, `OverviewBoardView`).
**Goal:** Run a `codepetCanDo` roadmap task → produce a `Deliverable` → append to the Library and persist. Native-only + fail-open (the `runTask` Cloud Function ships separately). No chat integration or draft/approve (6C).

---

## Approved decisions (brainstorming)
1. **Native-only, fail-open** — build the Run trigger + `CompanyStore.runTask` + an injectable fail-open `RunTaskClient.run`. The `runTask` CF is authored + deployed separately (node-22 bundle). Full loop testable via an injected stub.
2. **Task left as-is on success** — the deliverable lands in the Library; the source task is unchanged (draft→Approve→complete is 6C).
3. **Run only on `codepetCanDo` cards** — companion does/drafts + unblocked. Not on needsYou / blocked / done.
4. **Honest `runError` line** on failure (not silent); **append each run** (no dedup this slice).

## Scope
**In:** `RunTaskClient` (DTOs + fail-open `run`); `ISOTime.utc` (canonical UTC timestamp); `CompanyData.deliverablesPayload` + `saveLibrary` (the 6A-deferred save path); `CompanyStore` `runningTaskIds`/`runError` + injectable `taskRunner`/`librarySaver` + `runTask`; the Run affordance on `TaskCardView` + the `runError` line on `OverviewBoardView`.
**Out (later):** the `runTask` CF itself (node-22 deploy); inline chat run_task cards + Approve/Redo + status/drafts (6C); dedup/replace on re-run; per-kind structured payloads; export.

## Components

### 1. `RunTaskClient` (`codepet/Services/RunTaskClient.swift`)
- `RunTaskRequest` (Codable, snake_case): `companyId: String?`, `language: String`, `companionId: String`, `context: String`, `taskId: String`, `taskTitle: String`, `taskDetail: String`.
- `RunTaskResponse` (Codable): `kind: String`, `title: String`, `body: String` (markdown; the CF picks the kind — `RoadmapTask` carries none).
- `enum RunTaskClient { static func run(_ req:) async -> RunTaskResponse? }` — POSTs to `runTaskEndpoint` (`https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask`); returns the decoded response on 200, **nil on any error / non-200 / unreachable** (fail-open, mirrors `CompanyChatClient`).

### 2. `ISOTime.utc` (`codepet/Models/ISOTime.swift`, pure)
`enum ISOTime { static func utc(_ date: Date) -> String }` — one canonical UTC ISO-8601 (`ISO8601DateFormatter`, default options = UTC `Z`, no fractional seconds), e.g. `1970-01-01T00:00:00Z`. Guarantees the lexicographic newest-first sort in `LibraryView`. Pure → tested with a fixed date.

### 3. Persistence (`CompanyData`, the 6A-deferred save path)
- `static func deliverablesPayload(_ library: [Deliverable]) -> [String: Any]` — `["library": <array of dicts>]` via `JSONEncoder → JSONSerialization` (mirrors `tasksPayload`).
- `static func saveLibrary(companyId:library:) async -> Bool` — writes `companies/{uid}` `{ library: … }`, merge, fail-soft.

### 4. `CompanyStore.runTask` (the loop — honors all three 6A gates)
- `@Published private(set) var runningTaskIds: Set<String> = []`; `@Published private(set) var runError: String? = nil`.
- Injectable `taskRunner: (RunTaskRequest) async -> RunTaskResponse?` (default `RunTaskClient.run`) + `librarySaver: (String, [Deliverable]) async -> Bool` (default `CompanyData.saveLibrary`).
- `func runTask(_ task: RoadmapTask, language: AppLanguage) async`:
  1. Guard `!runningTaskIds.contains(task.id)`; `runningTaskIds.insert(task.id)`; `runError = nil`.
  2. Build `RunTaskRequest` (companyId, language.rawValue, `company.companionId`, `ChatContext.compose(brief: company.brief, tasks: company.tasks)`, task.id, task.title, task.detail).
  3. `cid = companyId`; `result = await taskRunner(req)`; **always** `runningTaskIds.remove(task.id)`.
  4. Guard `companyId == cid` else return (account switch discards, like `sendChat`).
  5. Build the deliverable IFF valid — `title` = a non-empty `result.title` else `task.title`; `body` = `result.body` trimmed; **guard `!body.isEmpty`** (required-fields gate) else fall to the failure branch. `Deliverable(id: UUID().uuidString` (**unique**), `kind: DeliverableKind(raw: result.kind)`, `title:`, `body:`, `createdAt: ISOTime.utc(Date())` (**canonical**), `sourceTaskId: task.id)`. Append to `company.library`; `if let cid { _ = await librarySaver(cid, company.library) }`.
  6. On nil result or empty body: `runError = language == .vi ? "Không tạo được \"\(task.title)\" — thử lại nhé." : "Couldn't generate \"\(task.title)\" — try again."`. No deliverable; task unchanged.
- `reset()` also clears `runningTaskIds` + `runError`.

### 5. Trigger UI
- **`TaskCardView`** (3B): when `status == .codepetCanDo`, add a small **Run** button (accent-tinted) after the who/status tags. While `companyStore.runningTaskIds.contains(task.id)` → a `ProgressView` spinner + the button disabled. Tap → `Task { await companyStore.runTask(task, language: lang) }`. Label "Run" / "Chạy".
- **`OverviewBoardView`**: when `companyStore.runError != nil`, a dismissible tinted line above the header ("×" clears it; starting another run also clears it).

## Data flow
Run tap → `runTask` → `taskRunner` (fail-open) → on valid result a `Deliverable` (unique id / canonical createdAt / required title+body / sourceTaskId) → `company.library` (@Published) → persist + `LibraryView` shows it. On failure → `runError` line. `runningTaskIds` drives the per-card spinner.

## Error handling
Fail-open end-to-end: the client returns nil on any failure; `runTask` never throws/blocks; `runningTaskIds` is always cleared (even on discard); a nil/empty result surfaces one honest `runError` and **never** appends a malformed deliverable (guards title+body). Account-switch guarded via `companyId`. Persistence fail-soft.

## Testing
- `CompanyStore.runTask` (stub `taskRunner`): success → exactly one deliverable appended with unique id, `sourceTaskId == task.id`, `createdAt` non-nil + canonical, `kind` from the response, persisted via `librarySaver`; source task unchanged (not done); `runError` nil; `runningTaskIds` cleared. Empty-body result → no deliverable + `runError` set. Nil result → no deliverable + `runError` set. Account switch mid-run (companyId change) → no append. Already-running task → no-op (single insert). `reset()` clears `runningTaskIds`/`runError`.
- `ISOTime.utc(Date(timeIntervalSince1970: 0))` → `"1970-01-01T00:00:00Z"`.
- `CompanyData.deliverablesPayload` shape (array of dicts, id/kind/title present).
- `RunTaskClient` DTO round-trip (snake_case keys).
- `TaskCardView` Run affordance + board `runError` line verified by build.

## Reuse / references
| Source | Native target |
|---|---|
| web `lib/ai/runTask.ts` (`runByteTask` → RunResult) | `RunTaskClient.run` (collapsed to kind+title+markdown) |
| web `lib/ai/applyResult.ts` (result → stored deliverable) | `CompanyStore.runTask` build+persist |
| `CompanyChatClient` (fail-open POST) | `RunTaskClient` |
| `CompanyData.tasksPayload`/`saveTasks` | `deliverablesPayload`/`saveLibrary` |
| `ChatContext.compose` (brief+roadmap grounding) | `runTask` request `context` |
| `TaskCardView` (3B) | Run affordance |

## Open decisions
None — resolved in brainstorming (native-only fail-open; task left as-is; Run on codepetCanDo; honest runError; append each run). Ready for implementation planning.
