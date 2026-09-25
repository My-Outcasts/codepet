# Team Build — one request, the whole company, a real project

**Status:** design approved in conversation 2026-09-24, awaiting spec review
**Authority:** `virtual-company-sse-contract.md` still outranks this document. Nothing here changes the room's wire format.

## Why

A founder asked Codepet to "build a landing page selling pants" and saw one agent answer. That is what the code does today:

- The two-mode pane's composer is always `.ask` (`CopilotChatView.swift:43`) and has no mode pill. Ask never convenes the room.
- The room is reachable only through the composer's `+` menu ("Convene the room · ~10 credits"). Even then it ends in one `DecisionBrief` with a single `next_action`. It produces no work.
- Nothing turns a room result into tasks. Chained runs go one level deep (`runChained` runs only the first unfiled dependency, and that dependency's own upstream comes from the library only).
- The Build path writes code only into a folder the founder linked by hand.

The product promise is the opposite: someone who knows nothing gets a whole team that discusses the request, then builds the final product together. This spec connects the three existing pieces (room, task runs, Claude Code) into that flow, and makes every step visible.

## Decisions (founder, 2026-09-24)

| # | Question | Decision |
|---|---|---|
| 1 | What does the founder end up holding? | **A real project folder with code and a `CLAUDE.md`.** An HTML file in the app is not enough. An in-app preview is secondary. |
| 2 | Where does the founder approve? | **Once, after the room**, on the plan. The chain then runs unattended. The finished project needs approval before it is filed. |
| 3 | How does the flow start? | **An explicit "Team build" button** in the composer. No auto-detection or offer from the companion. |
| 4 | Which requests? | **Any product the app knows how to make**, not only landing pages. The plan decides the departments and the project type. |
| 5 | Where is the project created? | **The app creates `~/Codepet Projects/<slug>/` automatically** and asks nothing. |
| 6 | Orchestration approach | **In-app orchestration reusing existing pieces**, not a single long Claude Code session. The single-session approach would hide the departments, which is the complaint this feature answers. |
| 7 | Visibility | **A compact live card in chat plus a detail panel** that opens when a department is clicked (side-by-side in the pane, a sheet in the 380pt dock). |
| 8 | Roadmap | **A Team Build does not add tasks to the roadmap.** It is its own record. |
| 9 | Claude Code permissions | **Read and write files only.** No shell commands (no `npm install`, no deploy) in v1. |

## The flow

```
[Team build] button
   │  founder's request
   ▼
1. Room (existing)            vcSidecar → DecisionBrief
   │
   ▼
2. Plan (new op planTeamWork) → WorkPlan (validated + coerced)
   │
   ▼  founder taps [Go]                       ← the only approval before work
3. TeamRun (new coordinator)  steps run in dependency order via runTask,
   │                          each fed its direct deps' drafts
   ▼
4. Project assembly (new)     create folder → write docs/ → Claude Code
   │                          builds project + CLAUDE.md → fallback CLAUDE.md
   ▼                          → first commit
5. Handoff                    [Approve] files project + department work
                              [Open in Finder] [Open with Claude Code] [View in browser]
```

### 0. Entry point

- A **Team build** button sits beside Send in `ChatComposer`, on both surfaces (two-mode pane and dock). It is disabled while the draft is empty, while chat is busy, and while another TeamRun is active for this company.
- The button's help text states what it does and that it runs on the founder's Claude plan.
- The button goes through the same authorisation checks as every local path. With no `ClaudeCodeAuthorisation` grant it stages `.blocked(.notGranted)`, which shows the reason on screen. It never falls back to a Cloud Function.
- The founder's message appears in the transcript as usual. The room is convened by calling `sendChat(..., convenesRoom: true)` exactly as the `+`-menu path does (`CopilotChatView.swift:814`). This spec adds no second way to convene.

### 1. Room (existing, unchanged)

- The room runs as today, with the same cards and the same 240s client deadline.
- When the room ends:
  - **`brief` arrives:** go to planning with the `DecisionBrief`.
  - **Router ends with `single_agent`:** go to planning with the request alone (`brief = nil`).
  - **Router ends with `needs_clarification`:** stop. The clarifying question is shown as today and no plan is made. The founder answers and taps Team build again.
  - **The room fails or times out:** show the error on the Team Build card with [Retry] and no plan.

### 2. Planning — `planTeamWork`

A new one-shot op, `planTeamWork`, added to `ONE_SHOT_OPS` and named at its Swift call site. Its prompt builder lives in `functions/src/planTeamWorkCore.ts`, so the local op and any future HTTP handler share one prompt. This follows the "prompts are never re-implemented" rule.

**Input**
- The founder's request, verbatim.
- The `DecisionBrief` or `null`.
- The company brief.
- The department roster (keys that exist on this company's roster) and each department's allowed deliverable kinds from `departments.ts`.

**Output** (asked for in prose, then parsed with `extractJson`):

```ts
interface WorkPlan {
  title: string            // "Landing page for stretch office trousers"
  slug: string             // folder name, kebab-case ASCII
  summary: string          // one sentence: what the team decided
  projectType: string      // "static landing page", "email sequence (docs)", …
  steps: WorkStep[]
}
interface WorkStep {
  id: string               // "s1", "s2", …
  dept: DepartmentKey      // one of the nine roster departments
  title: string            // short, shown on the card
  instruction: string      // what this department must produce
  kind: DeliverableKind    // from runTaskCore's list
  dependsOn: string[]      // ids of earlier steps
}
```

**Validation and coercion** (`coerceWorkPlan`, the safety layer on a transport that cannot force a tool call):

1. Drop steps whose `dept` is not a routable roster department. `chief_of_staff` and `devils_advocate` are never steps.
2. A `kind` outside the department's contract becomes `doc`, using the same rule as `runTaskCore` (`departments.ts:341`).
3. Drop `dependsOn` ids that do not exist. Break cycles by removing the edge that closes each cycle, visiting steps in array order.
4. Cap department steps at **6**, keeping the earliest. Cap each step's `dependsOn` at **3**, which matches `UpstreamWork`'s cap. Steps whose dependencies were cut become roots.
5. **Exactly one final build step:** `{ id: "build", dept: "engineering", kind: "other", title: "Build the project", dependsOn: <every other step id> }`. Any engineering step the model marked as the build step is folded into it, and the model's instruction for it is kept as the build instruction.
6. Slug: lowercase ASCII kebab-case with diacritics stripped, at most 40 characters, and `project` if empty. Collisions are resolved at folder creation, not here.
7. Zero valid department steps is allowed; the build step then works from the decision alone. A plan that fails to parse at all is an error with [Retry].

The client re-validates the plan it receives (Swift mirror of rules 1, 3, 4, 5) and does not trust the op's output. This is the same belt-and-braces approach `parseUpstream` takes.

### 3. TeamRun — orchestration

A new record and a new coordinator:

```swift
struct TeamRun: Codable, Identifiable {
  let id: String
  let request: String
  let createdAt: Date
  var brief: DecisionBrief?           // nil when the router went single_agent
  var plan: WorkPlan
  var steps: [TeamStepState]          // one per plan step, same order
  var projectPath: String?            // set once the folder exists
  var phase: Phase                    // planned, running, assembling, ready, filed, cancelled, failed
}
struct TeamStepState: Codable {
  let stepId: String
  var status: Status                  // waiting, running, done, failed(reason), blocked, cancelled, interrupted
  var startedAt: Date?
  var finishedAt: Date?
  var draft: Deliverable?             // a department step's output (unapproved)
}
```

- Persisted under `companies/{uid}` as `teamRuns`, saved after every status transition. Saving is gated on `PrototypeMode.allowsCloudWrites` like every other saver.
- **`TeamRunCoordinator`** (`Managers/`, modelled on `CodingRunCoordinator`) owns scheduling. Everything it touches is injected: the task runner, the project assembler, the clock and the saver. It is fully testable without Claude or Firestore.

**Scheduling**
- A step starts when all its `dependsOn` are `done`. At most **3** steps run at once, the same as `maxFanOut`.
- Only **one active TeamRun per company**.
- A department step calls the existing `taskRunner` with a `RunTaskRequest` for its dept, title, instruction and kind. Its `upstream` is built from its **direct** dependencies' drafts via `UpstreamWork.fromDraft` with `unapproved: true`, capped at 3 items of 1500 characters each by the existing type.
  - Direct deps only is what makes the chain multi-level. A dependency's draft already absorbed its own upstream.
- The build step runs the project assembler (§4), not `taskRunner`.

**Timeouts**
- `LocalOneShotRunner` gets a per-call timeout, **180s** by default, which kills the child process tree. This benefits every local op; today a hung CLI call is unbounded.
- The build step's Claude Code run gets **15 minutes**.
- A timeout is `failed("Timed out after N min")`.

**Failure, retry, stop**
- If a step fails, its transitive dependents become `blocked`. Independent branches keep running.
- [Retry] on a failed step re-runs it. On success, its blocked dependents return to `waiting` and scheduling continues.
- [Stop] terminates running processes. Every step not yet `done` becomes `cancelled`, and the run becomes `cancelled`.
- **App quit mid-run:** on hydrate, steps persisted as `running` become `interrupted` and the card offers [Continue], which re-runs them. `done` steps are never re-run.

**Honest progress:** `runTask` does not stream, so a running department row shows its title and elapsed time and nothing else. There are no fake step counters. Only the build step has a real log (§4).

### 4. Project assembly

A `ProjectAssembler` (injected into the coordinator) does five things in order:

1. **Create the folder** at `~/Codepet Projects/<slug>/`. It creates `~/Codepet Projects/` if missing, and on a collision appends `-2`, `-3`, and so on. Then it runs `git init`. The app runs `git`; the model never does.
2. **Write the team's work to files:**
   - `docs/00-decision.md` renders the `DecisionBrief`: recommendation, confidence and reason, the trade-off the founder must own, kill criteria, what we don't know. If there was no brief, it contains the request and the plan summary.
   - `docs/NN-<dept>-<step-slug>.md` has one file per completed department step, in plan order. Structured payloads (site, email, sheet, and so on) are rendered to Markdown by a new pure `DeliverableMarkdown.render(_:)`.
3. **Run Claude Code** through the existing `CLIRunner` (`claude -p --output-format stream-json`, `currentDirectoryURL` set to the project folder).
   - The prompt comes from a builder in the functions tree, so it is shared and testable. It includes the request, `projectType`, the build step's instruction, the list of files in `docs/`, and the required `CLAUDE.md` sections.
   - **Allowed tools:** `Read`, `Write`, `Edit`, `Glob`, `Grep`. No `Bash`, no web.
   - The stream's tool events drive the Engineering detail panel's file log ("read docs/…", "wrote index.html").
4. **Guarantee `CLAUDE.md`:** if the file is missing or empty after the run, write a fallback from a fixed template. The template has the same sections and is filled from the TeamRun: request, decision, department list with links to `docs/`, "How to run" stating that nothing was installed, and next steps.
5. **Commit:** `git add -A && git commit -m "Initial project from Codepet Team Build"`. A commit failure is logged but does not fail the run, because the files are what matter.

**Required `CLAUDE.md` sections:**
- What this is, and who it is for.
- What the team decided, and why.
- Who did what, with links to `docs/`.
- How to run it.
- Next steps.

For non-software requests, the prompt tells Claude Code to produce a structured document project (folders plus `README.md`) with the same `CLAUDE.md`.

### 5. Handoff and approval

- When assembly finishes the run is `ready`. The result card lists the department contributions (their `docs/` files) and the files Claude Code wrote.
- It carries [Open in Finder], [Open with Claude Code] (opens Terminal at the folder), and [View in browser] (only if `index.html` exists at the project root).
- **[Approve]** goes through `CompanyStore.fileApproval`, the one path both existing approve flows use (see `ApprovalParityTests`). It files:
  - one Library entry for the project, pointing at the folder path. This is a `Deliverable` of kind `other` whose body is the project's `CLAUDE.md` "What this is" section. It uses a new optional `projectPath: String?` on `Deliverable`, which is client-only and never sent to `runTask`. `LibraryView` shows [Open in Finder] for any deliverable that has one;
  - one entry per department draft, so the Library's department grouping shows the whole team.

  It sets `firstApprovalAt` as usual, and the run becomes `filed`.
- Until approval, every department draft is unapproved and nothing is in the Library. The card says so, reusing the "Not saved yet" wording pattern from `DraftCardCopy`.

### 6. UI

Mockups from the session are in `.superpowers/brainstorm/` (gitignored). The states are:

1. **Plan card** after the room: the one-line decision summary, one row per step (avatar, department, title) with a "waits for …" line under dependent steps, "N steps · runs on your Claude plan", and [Go] and [Cancel].
2. **Team card** while running: one row per step with its status pill (Waiting, a running elapsed timer, Done, Failed, Blocked, Cancelled, Interrupted), an `n/N` counter, and [Stop].
3. **Detail panel** when a row is clicked. It shows the department, avatar, status, the step's instruction, "Receives from: …", and a short excerpt of each upstream draft. For a finished step it shows its draft through the existing `DraftPayloadPreview`. For Engineering during the build it shows the live file log (an `ExecLogRow`-style list). In the pane it opens side-by-side; in the 380pt dock it opens as a sheet.
4. **Failure** states inline on the row: the reason, [Retry <dept>], and blocked rows naming what they wait for.
5. **Result card** as described in §5.

Cards are built from the existing `MessageCard`, `AgentsWorkingRow` and `ExecLogRow` so they match the rest of chat. All copy is in both English and Vietnamese, following the `lang == .vi ? … : …` pattern.

## Testing

Tests are written first. Every guard gets a test that goes red when the guard is removed.

**jest (functions)**
- `coerceWorkPlan`: unknown dept dropped; out-of-contract kind becomes `doc`; dangling deps dropped; cycle broken; step and dependency caps; exactly one build step, and a model-marked build step is folded in; slug normalisation, including Vietnamese diacritics; unparseable input is an error.
- `ONE_SHOT_OPS` key-list test updated to include `planTeamWork`.
- The build prompt builder includes every `docs/` file name and every required `CLAUDE.md` section.

**XCTest (client), run per suite with `-only-testing:`** (landmine 3)
- `TeamRunCoordinatorTests` (fake runner, fake clock):
  - A→B→C runs in order, and C receives B's draft, not A's;
  - never more than 3 concurrent steps;
  - failure blocks only dependents, and retry resumes them;
  - a timeout becomes a failure;
  - stop cancels everything;
  - hydrate turns `running` into `interrupted`, and continue re-runs only those steps;
  - a second TeamRun is refused while one is active.
- `WorkPlanValidationTests`: the Swift mirror of the coercion rules.
- `ProjectAssemblerTests` (temp directory, fake Claude runner):
  - folder collision suffix;
  - `docs/` files and their names;
  - fallback `CLAUDE.md` written when missing and left alone when present;
  - allowed tools exclude `Bash`;
  - `git init` and commit are invoked.
- `DeliverableMarkdownTests`: every structured kind renders its fields.
- `ApprovalParityTests`: approving a TeamRun files the project plus every department draft and sets `firstApprovalAt`. Every new saver is injected, because the real savers trap under an unconfigured `FirebaseApp` (the "adding any new saver" warning in `CLAUDE.md`).
- `TeamBuildButtonTests`: disabled on an empty draft, while busy, and while a run is active; a founder with no grant stages `.blocked(.notGranted)` and never reaches a Cloud Function.

**End-to-end, by hand, on the real Claude plan:** "Build me a landing page selling stretch office trousers." Pass criteria:
- the room convenes and the plan card appears;
- after [Go], every department row moves through its states;
- the Engineering panel shows real file writes;
- `~/Codepet Projects/<slug>/` contains `CLAUDE.md`, `docs/`, one commit, and an `index.html` that opens;
- [Approve] shows the project and the department work in the Library.

Run `scripts/build-sidecar.sh` before this check, since `functions/src` changes.

## Out of scope for v1

- Claude Code running shell commands: installing dependencies, running a dev server, deploying.
- Auto-offering Team Build from ordinary chat.
- Re-running downstream steps after the founder edits a department's draft.
- Linking TeamRuns to the roadmap.
- Parallel TeamRuns.
- Prototype-mode fixtures for Team Build. Until they exist, the button is hidden while prototype mode is on.
- Re-measuring cost. A TeamRun is one room plus N+2 local calls on the founder's plan; measure after v1 ships, per `virtual-company-test-runbook.md`.

## Risks

- **`claude -p` may return a plan that ignores the format.** Coercion plus the client-side re-validation are the answer, and an unparseable plan is an honest error with [Retry].
- **Long wall-clock.** A 4-step plan is roughly 1–2 minutes of department work (20–40s per `runTask`, three in parallel) plus several minutes of building. The live card is what makes that wait acceptable; the timeouts are what bound it.
- **Quota spend.** It is bounded by the single [Go] approval, the step cap of 6 plus the build step, the room's existing per-run ceilings (`budget.ts`), and one TeamRun at a time.
