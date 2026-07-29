# Part 2C-2 — edit_code Chat Card UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a coding run in the chat transcript — the agreed "one evolving card": streamed tool-use steps → collapse → inline per-file diff review → Reject/Approve — driven by the 2C-1 `CodingRunCoordinator`, with honest "0 credits" / branch / undo labeling and a plan-preview gate.

**Architecture:** The card is a top-level transcript row observing `companyStore.codingRun` (a `CodingRunCoordinator`, `ObservableObject`) — mirroring how `AgentsWorkingRow` renders from `activeAgentRuns`. It's a sibling of `ExecLogRow`: `CompanionAvatar` + a tinted `MessageCard`. 2C-1 surfaced only the run's terminal outcome, so 2C-2 extends the `CodeRunning` seam with a per-step callback and republishes it as `@Published steps: [ExecStep]` (reusing the existing `ExecStep` model). The step-mapping is pure/testable; the SwiftUI views are build-verified + visually checked (views aren't unit-testable in this host — per the project convention, visual verification is the founder's).

**Tech Stack:** Swift, SwiftUI (`codepet`), XCTest, xcodebuild. Reuses `ExecStep`, `MessageCard`, `CompanionAvatar`, `ClaudeCodeRunner.FileDiff`, `CodingRunCoordinator`/`EditCodeRun` (2C-1). No new dependencies.

## Scope

**Part 2C-2** — the coding-run card UI + live-step surfacing. In: extend the runner seam to stream steps (+ pure mapping, testable), `CodeRunCardView` (the evolving card: preview / running / reviewing / committed / failed / noProject), and wiring it into the chat transcript.

**Explicitly deferred:**
- **2C-3:** the Environment "Linked project" surface + the inline "link your project" chat offer + composer chip. (Here, `.noProject` just shows a "link a project first" line in the card; the full link UI is 2C-3.)
- **2C-server:** the CF `edit_code` tool. Until it ships, the card is exercised via `MockChat` emitting `edit_code` + manual runs.
- **"Open full diff" sheet:** a stub button in 2C-2 (opens nothing yet / a placeholder); the full-screen diff viewer is a follow-on.

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest.
- Follow the existing chat-card language: `MessageCard(hue:)`, `CompanionAvatar`, `ExecStep` checklist (teal check / spinning current / dim pending), `CodepetTheme` tokens — no new hardcoded colors, no decorative icons (per project design memory).
- Honest labels (spec §5): the card shows **"ran on your Claude subscription · 0 credits"**; git → a branch chip; shadow → **"applied · Undo"** after approve. Keep the billing/trust distinction visible.
- The card renders one active coding run (`companyStore.codingRun.run`); it observes the coordinator directly (`@ObservedObject`) since nested ObservableObjects don't auto-propagate through `CompanyStore`.
- Views are build-verified here; **the founder does the visual pass** (the agent host has no Screen Recording permission — same as the chat-first-shell plan).
- Build/test signing + close-app-before-test as in prior plans. Only Task 1 adds unit tests.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Modify** `codepet/Services/CodeRunning.swift` — add an `onStep` callback to `CodeRunning.run(...)`; `ClaudeCodeRunAdapter` forwards `ClaudeCodeRunner` tool-use events as steps.
- **Create** `codepet/Models/CodeExecSteps.swift` — pure mapping `ClaudeCodeRunner.StreamEvent → ExecStep?` (+ a running-list reducer).
- **Modify** `codepet/Managers/CodingRunCoordinator.swift` — `@Published private(set) var steps: [ExecStep]`; feed it via the seam's `onStep` during `execute`.
- **Create** `codepet/Views/Copilot/CodeRunCardView.swift` — the evolving card (all phases).
- **Modify** `codepet/Views/Copilot/CopilotChatView.swift` — render `CodeRunCardView(coordinator: companyStore.codingRun)` in the transcript when a run is active (near the `AgentsWorkingRow` render).
- **Modify** `codepet/Services/MockChat.swift` — a `"code"`/`"edit"` route emitting an `edit_code` action, so the card is exercisable offline.
- **Create test** `codepetTests/CodeExecStepsTests.swift`.

---

## Task 1: Stream live steps (seam + pure mapping)

**Files:**
- Modify: `codepet/Services/CodeRunning.swift`
- Create: `codepet/Models/CodeExecSteps.swift`
- Modify: `codepet/Managers/CodingRunCoordinator.swift`
- Test: `codepetTests/CodeExecStepsTests.swift` + extend `codepetTests/CodingRunCoordinatorTests.swift`

**Interfaces:**
- Changed: `protocol CodeRunning { func run(prompt: String, workingDir: String, onStep: @escaping (ExecStep) -> Void) async -> CodeRunOutcome }` (existing callers pass `onStep`; the coordinator supplies one that appends to `steps`).
- Produces: `enum CodeExecSteps { static func step(for event: ClaudeCodeRunner.StreamEvent) -> ExecStep? }` — maps a tool-use event to a done `ExecStep` (e.g. "Edited SignupForm.swift", "Ran: swift build"); returns nil for non-actionable events (system/plain assistant text/final result).
- `CodingRunCoordinator` gains `@Published private(set) var steps: [ExecStep]` (reset per `propose`, appended during `execute`).

- [ ] **Step 1: Write the failing mapping tests**

Create `codepetTests/CodeExecStepsTests.swift`:

```swift
import XCTest
@testable import codepet

final class CodeExecStepsTests: XCTestCase {
    private func ev(_ kind: ClaudeCodeRunner.StreamEvent.Kind, tool: String? = nil, path: String? = nil, text: String) -> ClaudeCodeRunner.StreamEvent {
        ClaudeCodeRunner.StreamEvent(kind: kind, toolName: tool, filePath: path, text: text)
    }

    func test_toolUse_becomesADoneStep() {
        let s = CodeExecSteps.step(for: ev(.toolUse, tool: "Edit", path: "/p/App.swift", text: "Edited App.swift"))
        XCTAssertEqual(s?.label, "Edited App.swift")
        XCTAssertEqual(s?.done, true)
    }

    func test_nonActionableEvents_mapToNil() {
        XCTAssertNil(CodeExecSteps.step(for: ev(.system, text: "init")))
        XCTAssertNil(CodeExecSteps.step(for: ev(.assistantText, text: "Sure, on it.")))
        XCTAssertNil(CodeExecSteps.step(for: ev(.result, text: "Run complete.")))
    }
}
```

(Confirm `ClaudeCodeRunner.StreamEvent`'s memberwise init/`Kind` cases at implementation — `.system`/`.assistantText`/`.toolUse`/`.toolResult`/`.result` per the runner; the mapping is the only place that reads them.)

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeExecStepsTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `CodeExecSteps` not found.

- [ ] **Step 3: Implement the mapping**

Create `codepet/Models/CodeExecSteps.swift`:

```swift
import Foundation

/// Maps the coding runner's stream events to display steps for the run card.
/// Only tool-use events (Edit/Write/Bash/Read/…) become steps; system meta,
/// plain assistant prose, tool results, and the final summary are not shown as
/// checklist rows. Each surfaced step is already `done` (the tool call completed).
enum CodeExecSteps {
    static func step(for event: ClaudeCodeRunner.StreamEvent) -> ExecStep? {
        switch event.kind {
        case .toolUse:
            let label = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : ExecStep(label: label, done: true)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Extend the seam + coordinator to stream steps**

4a. In `codepet/Services/CodeRunning.swift`, change the protocol + adapter:

```swift
protocol CodeRunning {
    func run(prompt: String, workingDir: String, onStep: @escaping (ExecStep) -> Void) async -> CodeRunOutcome
}
```

In `ClaudeCodeRunAdapter.run`, also observe `runner.$events` and forward newly-appended tool-use events through `CodeExecSteps.step(for:)` to `onStep` (dedupe by the count already forwarded). Keep the terminal-outcome resume unchanged. (Build-verified glue; the `$events` array is append-only during a run.)

4b. In `codepet/Managers/CodingRunCoordinator.swift`:
- add `@Published private(set) var steps: [ExecStep] = []`;
- clear `steps = []` in `propose`;
- in `execute`, pass `onStep: { [weak self] step in self?.steps.append(step) }` to `runner.run(...)`.

Update the existing `FakeRunner` in `CodingRunCoordinatorTests` to the new signature (it can invoke `onStep` for each simulated edit) and add:

```swift
    func test_execute_collectsLiveSteps() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"], stepLabels: ["Edited app.txt"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.steps.map(\.label), ["Edited app.txt"])
    }
```

(Extend `FakeRunner` with `stepLabels: [String] = []`; in `run`, call `onStep(ExecStep(label:done:true))` for each before returning the outcome.)

- [ ] **Step 5: Run to verify green**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodeExecStepsTests \
  -only-testing:codepetTests/CodingRunCoordinatorTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: PASS — mapping tests + all coordinator tests (updated `FakeRunner` signature) incl. the new step-collection test.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/CodeRunning.swift codepet/Models/CodeExecSteps.swift codepet/Managers/CodingRunCoordinator.swift codepetTests/CodeExecStepsTests.swift codepetTests/CodingRunCoordinatorTests.swift
git commit -m "feat(coding-agent): stream live run steps (Part 2C-2 Task 1)" -m "CodeRunning seam gains an onStep callback; ClaudeCodeRunAdapter forwards tool-use events via a pure CodeExecSteps mapping; CodingRunCoordinator republishes them as @Published steps for the card." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `CodeRunCardView` (the evolving card)

**Files:**
- Create: `codepet/Views/Copilot/CodeRunCardView.swift`
- (Build-verified; no unit test — SwiftUI view.)

**Interfaces:**
- Consumes: `@ObservedObject var coordinator: CodingRunCoordinator` (`.run`, `.steps`); calls `coordinator.execute()/approve(acceptedPaths:)/reject()`; `EditCodePhase`, `CodeBackend`, `ClaudeCodeRunner.FileDiff`; `MessageCard`, `CompanionAvatar`, `ExecStep` rendering, `CodepetTheme`.
- Produces: `struct CodeRunCardView: View` rendering per `coordinator.run?.phase`:
  - `.noProject` → a one-line "Link a project so I can make real changes" (full link UI is 2C-3).
  - `.previewing` → plan-preview: the ask + a "may run terminal commands" note + **Run / Cancel** (Run → `execute()`, Cancel → `reject()`-equivalent clear).
  - `.readyToRun`/`.running` → `CompanionAvatar` + `MessageCard`: title (the ask) + `ENGINEERING` kicker + "ran on your Claude subscription · 0 credits" + the `steps` checklist (reuse the `ExecLogRow` step style).
  - `.reviewing` → the steps collapse to a summary; an inline **"N files changed"** section with per-file **accept toggles** (`@State var accepted: Set<String>`, seeded from `run.acceptedPaths`) + unified `FileDiff.Line` rows (context/added/removed, `CodepetTheme` add/remove tints) + a git **branch chip** (`⑂ codepet/…`) + an **"Open full diff"** stub button + **Reject / Approve** (Approve → `approve(acceptedPaths: accepted)`, Reject → `reject()`).
  - `.committed` → a done state: git shows the branch; shadow shows **"applied · Undo"** (Undo wired in a follow-on; stub in 2C-2).
  - `.failed(reason)` → the reason + (if it's a CLI-missing reason) an honest "here's how to enable real code changes" line — the spec's honest-plan fallback surface.

- [ ] **Step 1: Implement the view** following the agreed ASCII design (one evolving `MessageCard`; per-file accept + Approve inline; honest labels). Keep to `CodepetTheme` tokens and the `ExecLogRow` step-row style; no new colors/icons.

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Add a `#Preview` with a fixture `CodingRunCoordinator` in each phase for the founder's visual pass.

- [ ] **Step 3: Commit** (`feat(coding-agent): CodeRunCardView — evolving run+diff card (Part 2C-2 Task 2)`).

---

## Task 3: Wire the card into the transcript + MockChat exercise

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`
- Modify: `codepet/Services/MockChat.swift`

- [ ] **Step 1: Render the card.** Near the `AgentsWorkingRow(runs:)` render (`CopilotChatView.swift:181`), add — when `companyStore.codingRun.run != nil` — `CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")`. It lives at the transcript level (one active run), consistent with `AgentsWorkingRow`. "Work lands in chat" (Part 1 Layer 4) is already satisfied: the verb dispatched from a chat turn.

- [ ] **Step 2: MockChat exercise.** In `MockChat.route(_:)`, add a branch (before the fallback) so a message containing `"edit code"` / `"change the code"` / `"code:"` emits `ChatDoneAction(editCode: EditCodeAction(ask: <message>, plannedFiles: 1, needsBash: false))` — lets `-CODEPET_MOCK_CHAT YES` stage a run and show the card. (Choose a trigger phrase distinct from other routes, as with the `walkthrough` token.)

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Founder visual pass (manual).** Launch mock mode (`open <app> --args -CODEPET_MOCK_CHAT YES`), type a code trigger, confirm the card renders across phases. (Agent can't screenshot; the founder verifies — a real `claude`-linked run is the end-to-end smoke test once a project is linked.)

- [ ] **Step 5: Commit** (`feat(coding-agent): render the coding-run card in chat + MockChat exercise (Part 2C-2 Task 3)`).

---

## Self-Review

**1. Spec/UI coverage:** live streamed steps (Task 1) → the agreed evolving card with per-file accept + Approve/Reject, honest "0 credits"/branch/undo labels, plan-preview, `.failed` honest surface (Task 2) → wired into the transcript + mock-exercisable (Task 3). ✅ Matches the 2C UI decisions.
**2. Placeholder scan:** Task 1 has complete code + tests. Tasks 2–3 are views (build-verified + a `#Preview` + the founder's visual pass) — deliberately not over-specified as exact SwiftUI, since the founder visually iterates; the *contract* (phases, actions, labels) is precise.
**3. Type consistency:** `CodeExecSteps.step(for:)`, the `CodeRunning.run(prompt:workingDir:onStep:)` signature, `CodingRunCoordinator.steps`, and `CodeRunCardView(coordinator:)` are named consistently; reuses `ExecStep(label:done:)`, `MessageCard(hue:)`, `CompanionAvatar`, `ClaudeCodeRunner.FileDiff`/`StreamEvent` as they exist.
**Confirm at implementation:** `ClaudeCodeRunner.StreamEvent` memberwise init + `.Kind` cases (Task 1 mapping) and `$events` being observable for step-forwarding (Task 1 Step 4a) — both in `ClaudeCodeRunner`, the only consumers.
**Deferred:** 2C-3 (Environment link UI + inline offer + composer chip), 2C-server (CF `edit_code` tool), the full-screen "Open full diff" viewer, and the shadow-path "Undo" action wiring.
