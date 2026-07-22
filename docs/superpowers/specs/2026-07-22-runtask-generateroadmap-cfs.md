# runTask + generateRoadmap Cloud Functions — Design Spec (2026-07-22)

## Context

The native macOS Codepet app has finished-looking screens that are **hollow** because two
generation Cloud Functions don't exist yet (the audit found only `companyChat` — now
deployed — and the dept-based `scaffoldRoadmap` exist). This spec covers the two backend
unlocks that turn hollow UI into working software:

1. **`runTask`** — produces a deliverable for a roadmap task. Native `RunTaskClient` already
   POSTs to it; the client currently attaches **no auth token** (a gap to fix).
2. **`generateRoadmap`** — produces the phase→task→dependency roadmap the Overview board and
   onboarding reveal render. Native `CompanyData.fetchRoadmap` is a hard `return []` stub.

Both mirror the **companyChat** pattern exactly: a new HTTPS CF on `devpet-8f4b1`, Firebase
ID-token auth (`verifyAuth`), per-user daily limit (`checkAndIncrement`), tool-forced
generation, fail-open, pure logic split into a `*Core.ts` module so it is testable without
loading the firebase-functions tree (the iCloud worktree stalls jest/node-require on that).

## Decision (locked)

- **New `generateRoadmap` CF**, matching native's phase/deps `RoadmapTask`. The existing
  dept-based `scaffoldRoadmap` CF is **left intact** — its shape is what order 3's 8-department
  CompanyView will need.
- Deploy is **scoped** and runs from the **off-iCloud local-disk dir** (`/private/tmp/cc-deploy`),
  the only path that gets past Firebase's source-discovery OOM. Never a bare functions deploy
  (would delete live `distillReference`/`generateDictionary`).
- Model **Opus 4.8** for both (deliverables + roadmap are the quality surface / credit driver).

---

## CF 1 — `runTask`

**Endpoint:** `POST https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask`
**Auth:** `Authorization: Bearer <firebase-id-token>`.

**Request** (snake_case, fixed by Swift `RunTaskRequest`):
```jsonc
{ "company_id": "string|null", "language": "en"|"vi", "companion_id": "byte",
  "context": "string", "task_id": "string", "task_title": "string", "task_detail": "string" }
```

**Response 200** (fixed by Swift `RunTaskResponse`):
```jsonc
{ "kind": "doc", "title": "string", "body": "markdown string" }
```
`kind` ∈ native `DeliverableKind`: `doc, post, email, legal, screens, sheet, site, dms,
calendar, checklist, plan, text, other`. `body` is markdown (native renders via one MarkdownView).

**Flow:** `verifyAuth` → `checkAndIncrement` → build a companion-voiced prompt grounded on
`context` + `task_title` + `task_detail` (+ language) → Opus 4.8 with a forced `record_deliverable`
tool (`{kind, title, body}`) → coerce → respond. Errors → **502** (client fail-opens to an honest
run error; there is no safe empty deliverable to return).

**Pure logic (`runTaskCore.ts`):**
- `buildRunTaskPrompt({companionId, language, context, taskTitle, taskDetail}) → string` — static
  companion/instruction block; picks a fitting `kind` and writes the real deliverable as markdown.
- `coerceDeliverable(raw, taskTitle) → {kind,title,body} | null` — validate `kind` against the
  enum (default `doc`), require non-empty `body`, fall back `title`→`taskTitle`; `null` on empty body.
- `DELIVERABLE_KINDS` set + `companionFor` (reuse the 7-companion voice map — import from
  `companyChatCore.ts` to avoid duplication).

**Swift change:** `RunTaskClient.run` attaches the ID token via `Auth.auth().currentUser?.getIDToken()`
(mirrors the companyChat fix); still fail-open (`nil` when no signed-in user / non-200).

---

## CF 2 — `generateRoadmap`

**Endpoint:** `POST https://us-central1-devpet-8f4b1.cloudfunctions.net/generateRoadmap`
**Auth:** `Authorization: Bearer <firebase-id-token>`.

**Request:**
```jsonc
{ "company_id": "string|null", "language": "en"|"vi", "companion_id": "byte",
  "brief": { "projectName": "...", "oneLiner": "...", "summary": "...", "audience": "...",
             "stage": "...", "categories": ["..."] } }
```

**Response 200** (native decodes into `[RoadmapTask]`):
```jsonc
{ "tasks": [ { "id": "string", "title": "string", "detail": "string",
              "phase": "find"|"foundation"|"build"|"ship"|"launch",
              "who": "does"|"draft"|"you", "dependsOn": ["taskId"],
              "done": false, "drafted": false } ] }
```

**Flow:** `verifyAuth` → `checkAndIncrement` → build a prompt from the brief → Opus 4.8 with a
forced `record_roadmap` tool → coerce into `RoadmapTask[]` → respond `{tasks}`. Fail-open: on
error return **200 `{tasks: []}`** (native treats `[]` as "no change" — never clobbers an existing
board; matches the current stub's contract).

**Generation shape:** 2–4 tasks per phase across all 5 phases (find→foundation→build→ship→launch),
each `{phase, title, detail, who, deps:[titles]}`. `who`: `you` when it needs the founder's judgment/
identity/decisions; `does` when the companion can produce it autonomously; `draft` when the companion
drafts something the founder finalizes.

**Pure logic (`generateRoadmapCore.ts`):**
- `buildRoadmapPrompt({language, brief}) → string`.
- `coerceRoadmap(raw, {language}) → {tasks: RoadmapTask[]}` — validate `phase` ∈ 5 and `who` ∈
  {does,draft,you}; assign **stable ids** (`slug(title)-{index}`); resolve `deps` (task **titles**)
  → `dependsOn` (task **ids**), dropping unknown/self refs; default `done/drafted = false`;
  cap tasks/phase at 4. Never throws — returns `{tasks: []}` on junk.
- `ROADMAP_PHASES` (the 5 keys) + `WHO` set.

**Swift change:** `CompanyData.fetchRoadmap` rewritten from `return []` to POST (with ID token) and
decode `{tasks}` → `[RoadmapTask]`; fail-open to `[]` on any error/non-200. The `roadmapFetcher`
signature gains `language` (threaded from `generateRoadmap(language:)` at the two call sites:
`OverviewBoardView` auto-load and `scaffoldFromOnboarding`).

---

## Files

**Functions repo** (`codepet-scaffoldfn-wt`, branch `feat/company-chat-fn` — stacks on companyChat):
- Create `functions/src/runTaskCore.ts`, `functions/src/runTask.ts`, `functions/src/__tests__/runTask.test.ts`
- Create `functions/src/generateRoadmapCore.ts`, `functions/src/generateRoadmap.ts`, `functions/src/__tests__/generateRoadmap.test.ts`
- Modify `functions/src/index.ts` — export both (`secrets: ["ANTHROPIC_API_KEY"]`, node 22)

**Native repo** (`codepet-rebuild-wt`, branch `feat/company-chat-cf`):
- Modify `codepet/Services/RunTaskClient.swift` — attach ID token
- Modify `codepet/Services/CompanyData.swift` — real `fetchRoadmap`
- Modify `codepet/Managers/CompanyStore.swift` — thread `language` into `generateRoadmap`/`roadmapFetcher`

## Testing & verification

- Pure-logic tests for both cores, verified via **node `--experimental-strip-types`** off iCloud
  (jest can't run in the worktree). Full `tsc` build must pass.
- Scoped deploy of **both** from `/private/tmp/cc-deploy`: `firebase deploy --only
  functions:runTask,generateRoadmap` (extend the local-disk source, `npm ci` already present).
- Live checks: unauthenticated POST → 401 for each. Native signed build → sign in → the Overview
  board populates with a generated roadmap, and running a task yields a real deliverable in Library.

## Out of scope (explicit)

Typed deliverable viewers (order 4), the 8-department CompanyView/scaffold wiring (order 3), chat
tools beyond run_task, and any Build Coach / Second Brain / GitHub / BYOK / billing work.

## Risks

- **runTask no-auth today:** the Swift client change is required for the CF's auth gate to be
  satisfiable — ship them together.
- **Dep resolution:** the model returns dep **titles**; `coerceRoadmap` must resolve to ids and drop
  dangling/self references so the board's dependency graph never contains invalid ids.
- **Language threading:** the `roadmapFetcher` signature change touches two call sites — keep the
  `CompanyStore` default-injection wiring intact.
