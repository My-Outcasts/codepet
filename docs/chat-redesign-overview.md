# Chat Redesign — Overview & Workflow

**Branch:** `feat/chat-pr39-parity-dock` (off `main` @ `753de56`) · **tip:** `beec8d7`
**Scope:** bring PR #39's chat experience onto `main`'s **380pt docked copilot**, adapted to the dock, with the first-run interview replaced by a starter-card hero and "Let's build" folded into the composer.
**Status:** all work complete — full deterministic suite **537 tests, 0 failures**; TEAM-signed build clean. 23 commits, 34 files, +2,912 / −233.

Spec: [`docs/superpowers/specs/2026-07-31-chat-pr39-parity-in-dock-design.md`](superpowers/specs/2026-07-31-chat-pr39-parity-in-dock-design.md)
Plan: [`docs/superpowers/plans/2026-07-31-chat-pr39-parity-in-dock.md`](superpowers/plans/2026-07-31-chat-pr39-parity-in-dock.md)

---

## 1. What we built

The copilot dock ("Your team") went from a simple chat list to the full PR #39 experience, **without** changing PR #42's web-parity shell (top nav + Overview main content + the 380pt right dock stay exactly as they were). Everything is legible at dock width.

Headline capabilities now in the dock:

- **A first-run hero** — companion orb + a time-of-day greeting + a purple→pink gradient company question, over **starter cards** (or live roadmap cards when a roadmap exists). The old auto-asked enrichment interview is gone.
- **A unified composer** with an **Ask / Plan / Build** mode menu, department chips, and a `+` quick-actions menu. "Build" routes to the local coding agent; the old full-width "Let's build" button is deleted.
- **A single-run exec-log** — running one task shows a stepped "**{specialist} is doing the work…**" card that reveals each grounded step live, then collapses into the draft.
- **Parallel department fan-out** — "Run my next moves" fans out up to 3 department agents at once, each shown live in an `AgentsWorkingRow` with its own avatar, status, elapsed timer, and step checklist; drafts land as each finishes.
- **Department → companion handoff** — selecting a department chip (or naming a department in text) brings in that specialist; the reply is spoken by the specialist as its own pet sprite + "Name · Dept".
- **Offline mock mode** — `-CODEPET_MOCK_CHAT YES` boots a populated cross-department roadmap and stubs all chat/task/fan-out responses, so the whole experience is demoable with **zero Anthropic spend**.

The coding-agent run card, chat thread history, and account-safety guarantees from earlier work are all preserved.

---

## 2. Architecture (what each piece is)

### Pure models (SwiftUI-free, unit-tested)
| File | Responsibility |
|---|---|
| `Models/ChatMode.swift` | `.ask / .plan / .build`; `shape(_:language:)` wraps the raw message with intent. Ask = identity. |
| `Models/ChatLandingState.swift` | The empty-chat hero state: greeting + question + live roadmap signals (beacon / needs-you / awaiting-approval), deterministic given `now`. |
| `Models/ChatThinkingLabel.swift` | Names the in-flight work ("Drafting {task}…"). |
| `Models/DepartmentCompanions.swift` | Maps each department → specialist companion; finds a department named in free text. |
| `Models/AgentRun.swift` | One department agent's run (companion, dept, task, steps, status, elapsed) for the fan-out. |
| `Models/ChatContext.swift` (extended) | Adds `focusDepartment` grounding to the chat prompt. |
| `Models/RoadmapEngine.swift` (extended) | `nextMoves(_:limit:)` — the parallelizable next task per distinct department with a specialist. |

### Store behaviors (`Managers/CompanyStore.swift`)
- `sendChat(_:language:department:)` — routes an Engineering-chip + linked-project ask to the coding agent (via `EditCodeRouting`), else a grounded chat turn with department focus.
- `actingSpecialist(...)` / `taskSpecialist(for:)` — resolve which specialist speaks a turn / runs a task.
- `produceDraftInline(for:cid:language:)` — the **single-run** exec-log driver: generate grounded steps → reveal live → run → draft.
- `fanOutNextMoves(language:)` + `runFanOutAgent(...)` + `activeAgentRuns` — the **parallel** fan-out.
- `finishOnboarding` — first run now seeds nothing (opens on the hero).
- All run/chat paths guard `companyId == cid` before writes; `reset()` and `hydrate()`'s account-switch branch clear fan-out state.

### Views (`Views/Copilot/`, all dock-adapted to 380pt)
| File | Responsibility |
|---|---|
| `CopilotChatView.swift` | The composition: header + empty-hero-or-message-list + shared composer; routes Ask/Plan/Build; preserves coding-agent card, scroll bridges, and `ThreadListView`. |
| `ChatEmptyState.swift` | The hero (orb + gradient greeting + single-column starter / live cards). |
| `ChatComposer.swift` + `QuickAction.swift` | The one composer used in both hero and active chat: text field, dept chips (2 + overflow), `+` quick-actions, Ask/Plan/Build menu, tinted send. |
| `ChatExecLog.swift` (`ExecLogRow`) | The single-run stepped card ("{specialist} is doing the work…" + honest "N steps"). |
| `AgentsWorkingRow.swift` | The multi-agent live card for a fan-out. |
| `ChatThinkingRow.swift` | Breathing orb + shimmering label while a plain reply streams. |
| `ChatBackdrop.swift` | Ambient purple wash behind the dock chat. |

### Offline harness
- `Services/MockChat.swift` — DEBUG-only keyword router with canned chat/task/fan-out replies + a populated `company()/roadmap()`.
- `Services/CompanyData.swift`, `CompanyChatClient.swift`, `RunTaskClient.swift` — short-circuit to `MockChat` under the flag (all `#if DEBUG`, default off → Release hits the real Cloud Functions).

---

## 3. The chat workflow (how it behaves)

```
┌─────────────────────────── Copilot dock (380pt) ───────────────────────────┐
│ Your team · guiding · {company}                                   History   │
├─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│   chatMessages empty & no active fan-out                                    │
│        → ChatEmptyState hero:                                               │
│            ◍ orb                                                            │
│            "Good morning, {founder}."                                       │
│            "What should we build for {company} today?"  ← gradient          │
│            [ composer ]                                                     │
│            live roadmap cards  (DO THIS NEXT / NEEDS YOU / AWAITING)        │
│              — or —  starter cards (Plan this week / Review my brief / …)   │
│                                                                             │
│   otherwise → message list (user bubbles + un-bubbled companion + orb,      │
│        inline exec-log / agents-row / coding-run card / thinking row)       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────── │
│ [ composer: text · dept chips · (+) · Ask▾ · ↑ ]                            │
└─────────────────────────────────────────────────────────────────────────── ┘
```

### A. Sending a message — the Ask / Plan / Build modes
The composer's mode menu decides what a send does:

- **Ask** → the message goes to the companion as-is → a grounded reply.
- **Plan** → the message is wrapped ("give me the concrete next steps: …") → a planning reply.
- **Build** → routes to the **coding agent** (`startCodeRun`) instead of chat. With no project linked, the run card offers **"Link a project."** (This is what replaced the old "Let's build" button.)

If a **department chip** is selected and a project is linked, an Engineering ask diverts to the coding agent even in Ask mode (an intentional existing seam).

### B. Running one task — the single-run exec-log
When the companion runs a task (you type `run <thing>`, or it decides to), the transcript shows a live card:

```
Write your landing page copy
MARKETING · DOC
┌───────────────────────────────────────────────┐
│ ◍  Nova is doing the work…            3 steps  │
│ ✓ Reading your brief — mission, audience, voice│
│ ✓ Pulling in the Marketing playbook            │
│ ⟳ Drafting "Write your landing page copy" …    │  ← current step spins
│ • Matching your tone and past decisions        │
└───────────────────────────────────────────────┘
```

Steps are **grounded** in the real request (brief fields, the department playbook, prior decisions) — not fabricated. The counter reads an honest **"N steps"**, never the web's "Ran N actions". When the run finishes, the card collapses into the draft card (Approve / Open / Redo).

### C. Running several at once — the parallel fan-out
`+ → "Run my next moves"` picks the next actionable task in up to 3 distinct departments (each with a specialist) and runs them **concurrently**:

```
┌─ Nova · Marketing ·······  Working  0:04   2/4 ┐
│  ✓ reading brief   ⟳ drafting   • …            │
├─ Crash · Engineering ····  Working  0:04   1/4 ┤
│  ⟳ reading brief   • …                         │
├─ Sage · Finance ·········  Done     0:06   4/4 ┤
└────────────────────────────────────────────────┘
```

Each agent reveals its steps live; a draft lands in the transcript as each finishes; a failed agent shows a failure state without stopping the others.

### D. The department → companion handoff
Pick a department chip (or mention a department in text). If that department maps to a specialist that isn't the current host, the reply is **spoken by the specialist** — its pet sprite avatar + a "Name · Dept" header — so it reads as a genuine handoff, matching the web's team feel.

### E. First run
A brand-new company opens on the **hero with starter cards** (no auto-interview). Tapping a starter ("Plan this week", "Review my brief", "Draft my positioning") sends it as a normal ask. Once a roadmap exists, the hero shows **live roadmap cards** instead of the generic starters.

### F. What's preserved
- The **coding-agent run card** (link project → run the local `claude` CLI → review diff → commit) renders inline, anchored to its ask, with live step/diff streaming.
- **Thread history** (New chat / switch / rename) via the header's History toggle.
- **Account safety** — switching accounts mid-run clears in-flight state; nothing leaks across accounts.

---

## 4. Data flow (one send)

```
composer.onSend
  ├─ .ask/.plan → CompanyStore.sendChat(mode.shape(text), department: selectedDept)
  │     → sendMessage: append user msg → grounded CompanyChatRequest (focusDepartment)
  │       → chatStreamer (real CF, or MockChat.stream in mock)
  │       → specialist attribution on the companion placeholder
  │       → on done: handleRunTaskId → produceDraftInline (exec-log) if a task ran
  └─ .build → CompanyStore.startCodeRun(ask:)  → CodeRunCardView (coding agent)

+ "Run my next moves" → fanOutNextMoves → RoadmapEngine.nextMoves
      → seed activeAgentRuns → withTaskGroup { runFanOutAgent × N } → AgentsWorkingRow
```

---

## 5. Running it (offline, zero cost)

```bash
# TEAM-signed build (adhoc breaks keychain/sign-in across rebuilds)
xcodebuild -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates build

# single instance, mock mode (kill any stale instance first — Firestore LevelDB lock)
pkill -x codepet
open -n "<DerivedData>/Build/Products/Debug/codepet.app" --args -CODEPET_MOCK_CHAT YES
```

In mock mode the app boots a populated cross-department roadmap. Try: `run landing` (Nova/Marketing), `run waitlist` (Crash/Engineering), `run pricing` (Sage/Finance); `+ → Run my next moves` for the parallel card; a Design/Engineering chip for the handoff; **New chat** for the empty hero.

---

## 6. Deferred follow-ons (tracked, non-blocking)

- **Dead-but-unreachable code** left defined per plan scope: `FirstRunGreetingBuilder`, `runFirstRunAction`, and the enrichment-interview machinery (nothing seeds them now). Candidate for a cleanup pass.
- **`MockChat.company()/roadmap()`** is DEBUG-only demo scaffolding (now wired into the loader under the flag); not used in Release.
- **Ask-mode + Engineering chip + linked project** still diverts to the coding agent (intended seam, but the always-visible chip makes it reachable) — worth a copy/affordance tweak.
- Three mock router keywords (replan / walkthrough / edit-code) degrade to plain replies (main lacks those action fields).

---

## 7. How it was built (subagent-driven development)

16 planned tasks + 3 QA follow-ons, each: a fresh implementer subagent (TDD → build/test → commit → self-review) → an independent spec+quality reviewer → fixes if needed → ledger entry. A final whole-branch review (top-tier model) verified integration, account-safety, and spec coverage before sign-off. Progress ledger: `.superpowers/sdd/progress.md`. Three defects were caught and fixed mid-flight (an account-switch render leak, a missing current-step spinner, and the empty-hero fan-out gate).
