# Native Decisions-Memory Client (Design)

_Date: 2026-07-25 · Repo: My-Outcasts/codepet (native) · Branch: `feat/decisions-client` (off main) · Sub-project 2 of "decisions memory"_

## Context

Sub-project 1 deployed the stateless `extractDecisions` CF (live on `devpet-8f4b1`): given an approved deliverable + decisions on record, it returns the new/changed durable decisions. This sub-project builds the **native side**: the model, the merge/normalize/compose logic (ported from web `lib/ai/decisions.ts` + `projectModel.ts`), Firestore persistence, injection of decisions into chat + run-task grounding, and the fire-and-forget extraction call on approval. This reproduces web's Phase-2 loop (approve → extract → merge → persist → ground) for the two surfaces whose CFs already accept a free `context` string (chat, run-task) — **no generation-CF change**.

## Goal

When the founder approves a deliverable, byte extracts durable decisions and remembers them; those decisions then ground future chat replies and run-task generations ("honor these decisions").

## Non-goals

- No roadmap/scaffold decision-grounding (their CFs have no context channel — a later increment + CF change).
- No chat `remember_fact` tool parity (deferred).
- No new UI (decisions are invisible plumbing this round; a "decisions" surface is future work).

## Design

### 1. Model + pure logic — `codepet/Models/Decisions.swift` (new)

- `struct DecisionEntry: Codable, Hashable { var topic: String; var statement: String; var source: String?; var updatedAt: Double? }` — `updatedAt` is epoch **milliseconds** (matches web's `number`; JSON-safe).
- `struct ExtractedDecision: Codable { var topic: String; var statement: String; var source: String? }` — the CF's output shape.
- `enum Decisions` with pure static funcs (ports of web, unit-tested with parity):
  - `normalizeDecisions(_ raw: [DecisionEntry], max: Int = 30) -> [DecisionEntry]` — drop empty topic/statement, cap keeping most-recent (`updatedAt` desc; nil sorts oldest).
  - `mergeDecisions(existing: [DecisionEntry], extracted: [ExtractedDecision], now: Double, max: Int = 30) -> [DecisionEntry]` — topic-keyed (lowercased) supersede + stamp `updatedAt = now`; preserve untouched; over cap keep most-recent.
  - `composeDecisions(_ decisions: [DecisionEntry]) -> String` — the "Decisions the founder has locked in — honor these…" block verbatim from web `composeDecisions` (empty string when none).
  - `MAX_DECISIONS = 30`.

(These are structs/enums → tests run clean under Xcode 26.2.)

### 2. Persistence — `CompanyState` + `CompanyData`

- Add `var decisions: [DecisionEntry] = []` to `CompanyState` (memberwise init default, so existing call sites compile).
- Add `decisions: [DecisionEntry]?` to `CompanyData.CompanyDoc`; map `doc.decisions ?? []` (through `normalizeDecisions`) in `load`.
- Add `decisionsPayload(_:)` + `saveDecisions(companyId:decisions:)` to `CompanyData`, mirroring `tasksPayload`/`saveTasks` (JSONEncoder → JSONSerialization → `setData(merge:true)` under `decisions`).

### 3. Store wiring — `CompanyStore`

- Inject two closures (mirroring the existing injectable pattern), defaulting to the real impls:
  - `decisionsSaver: (String, [DecisionEntry]) async -> Bool = CompanyData.saveDecisions`
  - `decisionExtractor: (ApprovedDeliverableDTO, [DecisionEntry]) async -> [ExtractedDecision] = DecisionsClient.extract`
- `func rememberFromApproval(_ deliverable: Deliverable) async` (private): build the DTO from the `Deliverable` (title, dept from source task, type=kind.rawValue, out=body), send `company.decisions` as existing, get extracted, `mergeDecisions` into `company.decisions`, persist via `decisionsSaver`. **Account/token-guarded + fail-open** (a failed extraction leaves decisions unchanged; approval already happened).

### 4. Extraction call on approve

- In `approveTask(id:)` (board) and `approveDraft(messageId:)` (chat): after the library append + saves, kick off `Task { await rememberFromApproval(draft) }` — fire-and-forget, non-blocking, does not delay or gate the approval.

### 5. Grounding injection (no CF change — both CFs accept `context`)

- `ChatContext.compose(brief:tasks:decisions:)` — add a `decisions` parameter; append `Decisions.composeDecisions(decisions)` (when non-empty) to the parts. Update the two call sites in `CompanyStore` (`sendChat`) to pass `company.decisions`.
- Run-task context (`runRequest(for:language:)` builder in `CompanyStore`): fold `composeDecisions(company.decisions)` into the run-task `context` string.

### 6. New client — `codepet/Services/DecisionsClient.swift` (new)

Mirror `RunTaskClient`/`CompanyChatClient`: request DTO `{ deliverable: {title,dept,type,out}, existing_decisions: [{topic,statement}] }`, POST to `https://us-central1-devpet-8f4b1.cloudfunctions.net/extractDecisions` with Firebase ID-token auth, decode `{decisions: [ExtractedDecision]}`. Fail-open: any error → `[]`. Expose `static func extract(_ deliverable: ApprovedDeliverableDTO, existing: [DecisionEntry]) async -> [ExtractedDecision]`.

## Testing

- `DecisionsTests` (struct-only, runs clean): `normalizeDecisions` (drop/cap/sort), `mergeDecisions` (supersede same topic case-insensitive, preserve others, cap keep-recent, stamp updatedAt), `composeDecisions` (empty → ""; renders header + lines). Parity with web `decisions.test.ts`/`projectModel.test.ts` cases.
- `CompanyData` decisions round-trip (payload encode + doc decode) — struct-level.
- `CompanyStore` tests (Xcode 26.2 teardown caveat): `rememberFromApproval` merges + persists (stub extractor + decisionsSaver); approve fires the extraction (stub extractor called with the approved deliverable + existing); fail-open (extractor returns [] → decisions unchanged, approval still completed); grounding — `ChatContext.compose` includes the decisions block when present.

## Files

- Create: `codepet/Models/Decisions.swift`, `codepet/Services/DecisionsClient.swift`, `codepetTests/DecisionsTests.swift` (+ CompanyData/CompanyStore test additions)
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`, `codepet/Models/ChatContext.swift`, `codepet/Managers/CompanyStore.swift`

## Notes

- Live end-to-end works now (`extractDecisions` is deployed). The loop is invisible until decisions accumulate; grounding then shapes chat + run-task output.
- Xcode 26.2 hosted-test teardown crash applies to CompanyStore tests (verify via assertion-green + build); struct-only tests run clean.
