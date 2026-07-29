# The Coding Agent — Engineering does real code changes (Design)

_Date: 2026-07-29 · Repo: My-Outcasts/codepet (native macOS SwiftUI) · Part 2 of 2_
_Depends on Part 1: `2026-07-29-chat-system-integration-map-design.md` — this spec_
_fills the `edit_code` verb + `project` slice seam that map defines._

## Context

Part 1 placed the Coding Agent as a feature node and defined its seam: the
`edit_code` verb, the client-only `project` context slice, and its passage through
the one work lifecycle with a diff-based review. This spec details its internals.

The foundation already exists in the codebase:

- **`ClaudeCodeRunner`** (`codepet/Services/ClaudeCodeRunner.swift`) spawns the
  user's own `claude` CLI headless (`claude -p --output-format stream-json …`) via a
  login shell, streams structured tool-use events (Edit/Write/Bash/Read/Glob/Grep),
  and computes **real before/after `FileDiff`s** by snapshotting the project dir and
  diffing against disk after the run. It runs on the **user's own Claude subscription**
  — Codepet adds no API key and no billing. It already surfaces friendly errors when
  `claude` is missing or logged out, and has `cancel()` (Stop) and a `maxTurns` cap.
- **`ProjectStore`** (`codepet/Managers/ProjectStore.swift`) already knows project
  identity: it auto-detects roots from Claude Code `cwd` events (walking up for
  `.git`) and persists metadata to UserDefaults.
- **`PracticeSandbox`** is the *learning*-flow safety model: hand `claude` a
  throwaway copy, never the user's real project. The product coding agent **inverts
  this** — it targets the real linked project — so safety moves from "throwaway copy"
  to "branch / shadow-copy + diff review."
- The app is **not sandboxed** (`CodePet.entitlements`: `app-sandbox = false`), so it
  can spawn `claude`, read/write the real project dir, and run `git`.

Today `ClaudeCodeRunner` is wired **only** into the Skills/Exercise flow
(`ExerciseWorkspaceView`, `RunForRealSection`), paired with `PracticeSandbox`. This
spec promotes it into the main product as the Engineering department's execution
backend.

## Goal

Let the companion — or an engineering task — make **real edits to the user's actual
project**, running on the user's own `claude` CLI, streaming into chat, and
committing only after the user approves a **diff**. Code never leaves the machine.

## Non-goals

- **No cloud code-awareness.** Per Part 1 (resolved Q3), the `project` slice is
  client-only; the cloud companion never receives the user's source, not even a
  redacted summary. It can *propose* `edit_code` from the `brief`/`decisions` slices,
  but only the local agent reads and writes source.
- **No unattended real-tree writes in v1.** Overnight/autonomous (§5.5) ships as
  *foundation only* — the lifecycle and rails are built so it can layer on later.
- **No PR creation in v1.** The git path stops at commit-to-branch; PR is a
  fast-follow (see Open Questions).
- **No per-hunk diff staging in v1.** Review is per-file accept + overall Approve;
  per-hunk is deferred.
- No new pricing. Local runs cost 0 Codepet credits by construction.

## Scope

**In v1**
- Link a real project folder (explicit picker + auto-detect suggestions).
- Propose → adaptive plan preview → run (streamed) → diff result → review → commit.
- Adaptive commit: git branch (if `.git`) or shadow-copy apply (if not), with undo.
- Triggers: user asks in chat · engineering roadmap task · companion proposes.
- Honest-plan fallback when `claude` is unavailable.

**Foundation only (built, not shipped as behavior)**
- Overnight/autonomous §5.5 Level 1 (observe & prepare). No unattended writes.

**Out of scope** — PR creation, per-hunk staging, multi-repo orchestration,
cloud code-awareness.

## Design

### 1. Project linking — `ProjectLink` + the linked-project picker

The v1 primitive is an **explicit folder link**. A new `ProjectLink` model holds the
absolute path, a **security-scoped bookmark** (so access survives relaunch), the
detected `isGitRepo` flag, and the resolved `CLAUDE.md` path.

- **"Link a project folder"** opens `NSOpenPanel` (directory, single). Consent-first;
  works for non-devs with no hooks installed.
- **Auto-detect suggestions.** `ProjectStore`'s already-detected roots surface as
  one-tap chips ("We've seen you working in `~/foo` — link it?"). Linking one just
  promotes it to a `ProjectLink`.
- **On link:**
  1. Detect `.git` at the root → `isGitRepo`.
  2. Read `CLAUDE.md`. If absent, offer to create one **seeded from the `brief` +
     `decisions` slices** — this becomes the agent's standing context and unifies
     with the existing project-references feature (reading cards → CLAUDE.md).
  3. Register the slice: the `project` context slice is populated from this link and
     is the only slice the local agent reads/writes.

One project is "active" at a time (mirrors `ProjectStore.activeProjectPath`).

### 2. The `edit_code` lifecycle

```
proposed ─▶ [adaptive plan preview] ─▶ running ─▶ diff result ─▶ review ─▶ commit
                                          │(claude CLI, streamed, Stop)      │
                                          ▼                                  ▼
                                        failed ─▶ honest-plan fallback   git: branch / no-git: shadow apply
```

**proposed.** The companion (or a task) proposes an `edit_code` run against the
active `ProjectLink`, carrying a scope estimate: `plannedFiles` and `needsBash`.

**adaptive plan preview.** A gate, not a second model call:
- **Skip** the preview and run immediately when the estimate is *small & low-risk* —
  `plannedFiles ≤ 1` **and** `needsBash == false`.
- **Show** a short "here's what I'll change" the user confirms otherwise —
  multi-file, or any run that may invoke `Bash`.
- The estimate is a courtesy; the **diff review is the real gate**. If a run touches
  more than estimated, nothing commits without the diff approval anyway.

**running.** Extends `ClaudeCodeRunner` against the **real linked dir** (not
`PracticeSandbox`): same streamed tool-use events, `cancel()` wired to a **Stop**
control, a `maxTurns` cap so a stuck run can't chew the user's plan.

**diff result.** The real `FileDiff`s the runner already computes
(`unifiedDiff(before:after:)`), grouped per file.

**review.** Per-file accept toggles + an overall **Approve** / **Reject**.

**commit — adaptive:**

| Condition | Mechanism | Undo |
|---|---|---|
| `.git` present | run on branch `codepet/<slug>`; **Approve** commits to the branch (never merge/deploy); **Reject** discards + deletes the branch | branch is revertible; never touched `main` |
| no git | run on a **shadow copy** (project copied to temp); **Approve** applies accepted files to the real tree with a **backup** kept; **Reject** discards the shadow | **Undo** restores the backup |

**Honest safety nuance (stated plainly).** On the **shadow path** the real tree is
literally untouched until Approve. On the **git path** the working tree *is* written
during the run — but only on a throwaway `codepet/<slug>` branch that never touches
`main`, so the change is always instantly revertible. The rail is "never a change you
can't instantly undo," realized two ways.

### 3. Triggers

| Trigger | Mechanism | v1 |
|---|---|---|
| User asks in chat | companion emits `edit_code` (Part 1 verb) with a scope estimate | ✅ core |
| Engineering roadmap task | a task of an `engineering` kind dispatches `edit_code` → chat, parallel to how `run_task` dispatches to the cloud today | ✅ |
| Companion proposes proactively | notices code-shaped work in conversation, offers `edit_code` (still user-approved) | ✅ |
| Overnight / autonomous | §5.5 Level 1 observe & prepare | ⚠️ foundation only |

All three v1 triggers converge on the same lifecycle and the same chat surface.

### 4. Safety & trust rails (non-negotiable)

- **Never a change you can't instantly undo** — branch (git) or shadow+backup (no-git).
- **Never merges, deploys, or deletes unattended** — the §5.5 hard ceiling.
- **Honest fallback, never faked.** `ClaudeCodeRunner` already detects "not installed"
  and "not logged in"; on either, the agent produces an **honest code-change plan**
  (what it *would* do, and how to enable real execution) instead of pretending — the
  PRD's stated fallback, mirroring how `plan` is the honest reframe of `pr` on the
  deliverable side.
- **Turn cap + Stop** — `maxTurns` and `cancel()`.
- **Explicit link + one active project** — the agent can only touch a folder the user
  deliberately linked.

### 5. UI surface in chat

Resolves Part 1's open Q4 (one transcript vs. collapsed card):

- A run collapses into **one expandable exec-log card**, reusing the existing
  `ChatExecLog` / `AgentsWorkingRow` components — not dozens of raw tool-use lines.
- The **diff review** expands from the result card: per-file sections rendered from
  `FileDiff.Line` (context/added/removed), per-file accept + overall Approve.
- The card carries the honest label **"ran on your Claude subscription — 0 credits"**
  and, on the git path, the branch name. This keeps the Part 1 billing/trust tension
  visible.

### 6. Engineering as a department

Engineering becomes the 8th department whose **deliverable is a real code change**
rather than a document. It is the *only* department on the **local backend** and the
`project` slice; the other seven stay cloud/credits. The department pill in the
composer selecting "Engineering" routes an ask to `edit_code` instead of `run_task`.

### 7. Reuse map — mostly extend, little new

**Extend**
- `ClaudeCodeRunner` — target the real linked dir; add git-branch mode and
  shadow-copy mode; make `maxTurns`/`allowedTools` product-configurable; drop the
  `PracticeSandbox` pairing assumption. Its stream parsing, `FileDiff`, and
  `unifiedDiff` are reused unchanged.
- `ProjectStore` — source of auto-detect suggestions and the active-project notion.

**Reuse**
- `FileDiff` / `unifiedDiff` for the review UI.
- `ChatExecLog` / `AgentsWorkingRow` for the streamed exec log.
- `ProjectScanner` for cheap repo awareness if the plan preview wants file context.

**New**
- `ProjectLink` model + security-scoped bookmark persistence.
- The link picker UI + auto-detect suggestion chips.
- The git branch / shadow-copy + backup **commit layer** (a `CodeCommitService`).
- The diff-review UI (per-file accept + Approve).
- Wiring `edit_code` into the chat contract (the companion reply carrying the verb +
  scope estimate; app-side dispatch to the runner).

## Testing

- **Adaptive-preview gate (pure).** `plannedFiles`/`needsBash` → show/skip decision,
  at the boundaries (0/1/2 files; Bash true/false). Unit-testable with no view.
- **`unifiedDiff`** — already covered; add cases for new-file and delete.
- **Commit layer.** Git path: branch created, commit lands on branch, `main`
  untouched, Reject deletes the branch. No-git path: shadow apply writes accepted
  files, backup restores on Undo, Reject leaves the real tree byte-identical.
- **Honest fallback.** Simulated "not installed" / "not logged in" → plan, not a fake
  edit (reuse the runner's existing `friendlyError` detection).
- **Firestore test-host flake.** Per memory `codepet-firestore-lock-blocks-tests`,
  close the running app before `xcodebuild test` and count executed tests.

## Files

**New**
- `codepet/Models/ProjectLink.swift`
- `codepet/Services/CodeCommitService.swift` (git branch / shadow + backup)
- `codepet/Views/Chat/CodeRunCardView.swift` (exec-log collapse + diff review)
- `codepet/Views/.../ProjectLinkPicker.swift`
- `codepetTests/AdaptivePreviewGateTests.swift`, `CodeCommitServiceTests.swift`

**Modified / extended**
- `codepet/Services/ClaudeCodeRunner.swift` — real-dir target, branch + shadow modes,
  configurable caps
- `codepet/Services/CompanyChatClient.swift` + the companyChat CF — carry the
  `edit_code` verb + scope estimate in the reply contract
- `codepet/Managers/CompanyStore.swift` — dispatch `edit_code`, hold active
  `ProjectLink`, run/commit orchestration
- `codepet/Managers/ProjectStore.swift` — expose detected roots as link suggestions

## Open questions

1. **PR fast-follow shape.** Commit-to-branch is v1. When PR lands, is it `gh` CLI,
   a token, or a "copy the branch, open a PR yourself" nudge? Decide with the
   git-integration follow-on.
2. **Scope-estimate source.** The `plannedFiles`/`needsBash` estimate comes from the
   proposing companion. Is that good enough, or does the plan preview warrant a quick
   read-only planning pass (extra tokens) for accuracy? v1 uses the estimate; the
   diff gate makes a wrong estimate harmless.
3. **CLAUDE.md write-back.** When a run establishes a new decision/convention, does
   the agent write it back to `CLAUDE.md` (Persistent-Context play) automatically, or
   propose it as a `remember`? Ties into the §7.1 seed-play #4.
4. **Multiple linked projects.** v1 keeps one active project. When a user links
   several, how does chat disambiguate which the current `edit_code` targets — the
   active one, or an explicit per-run choice?
