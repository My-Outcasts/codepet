# Chat Scenario Mockups + Parallel Agents-Working UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five SwiftUI `#Preview` mock screens of the chat (with the user, the roadmap, tasks, and environment setup) plus a new production-shaped `AgentsWorkingRow` component that shows multiple department agents working in parallel.

**Architecture:** The four scenario mocks feed fixture `[CopilotMessage]` arrays into the *real* `CopilotBubble` component through one shared `ChatMockData` harness, so they can't drift from production. The one new component, `AgentsWorkingRow`, is a multi-agent sibling of the existing single-agent `ExecLogRow`, backed by a small `AgentRun` value type with pure, unit-tested math. View-layer only — no engine or persistence changes.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS app target `codepet` (lowercase scheme), tests via `@testable import codepet`.

## Global Constraints

- Target/scheme: `codepet` (lowercase). Xcode project: `CodePet.xcodeproj`.
- All mock/preview code is dev-only: wrap in `#if DEBUG … #endif`.
- Reuse existing types verbatim — do NOT redefine: `CopilotMessage`, `ExecStep`, `Deliverable`, `DeliverableKind`, `NavAction(destination:target:)`, `SetupAction(category:name:)`, `RememberedFact(topic:statement:)`, `FirstRunAction(taskId:taskTitle:)`, `PetCharacter.all`, `CompanyStore`, `CodepetTheme`, `CompanionAvatar(companionId:size:isWorking:)`, `MessageCard(hue:) { content }`, `ChatBackdrop`.
- Companion ids: `byte` (display name "Codepet"), `nova`, `crash`, `luna`, `sage`, `glitch`, `null`. Departments by display name: Engineering, Design, Marketing, Sales, Support, Finance, Operations, Legal.
- `AppLanguage` cases are `.vi` and `.en`.
- Chat layout constants (match the shipped spacing pass): column `maxWidth: 760`, gutter `padding(.horizontal, 24)`, list `padding(.top, 40).padding(.bottom, 24)`, inter-message `spacing: 24`.
- Follow TDD for the one logic-bearing unit (`AgentRun`). The pure scenario/preview files carry no logic and are verified by a successful Debug build, not unit tests.

---

### Task 1: `AgentRun` model + pure math + tests

**Files:**
- Create: `codepet/Views/Copilot/AgentsWorkingRow.swift` (model + math only in this task; the view is added in Task 2)
- Test: `codepetTests/AgentsWorkingRowTests.swift`

**Interfaces:**
- Consumes: `ExecStep` (existing: `ExecStep(label:done:)`, property `done: Bool`, `id: String`), `AppLanguage`.
- Produces:
  - `enum AgentRunStatus: String, Equatable, Codable, CaseIterable { case working, reviewing, done, failed }` with `func label(_ lang: AppLanguage) -> String`.
  - `struct AgentRun: Identifiable, Equatable` with init `AgentRun(id:companionId:deptName:taskTitle:steps:status:startedAt:)` and members: `var stepCounter: String`, `var currentStepIndex: Int?`, `func elapsedString(now: Date) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/AgentsWorkingRowTests.swift`:

```swift
import XCTest
@testable import codepet

final class AgentsWorkingRowTests: XCTestCase {
    private func makeRun(steps: [ExecStep],
                         status: AgentRunStatus = .working,
                         startedAt: Date = Date(timeIntervalSince1970: 0)) -> AgentRun {
        AgentRun(companionId: "byte", deptName: "Engineering",
                 taskTitle: "Build the API", steps: steps,
                 status: status, startedAt: startedAt)
    }

    func testStepCounterCountsDoneOverTotal() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true),
                                ExecStep(label: "b", done: true),
                                ExecStep(label: "c", done: false)])
        XCTAssertEqual(r.stepCounter, "2/3")
    }

    func testStepCounterNoneDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: false),
                                ExecStep(label: "b", done: false)])
        XCTAssertEqual(r.stepCounter, "0/2")
    }

    func testCurrentStepIndexIsFirstNotDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true),
                                ExecStep(label: "b", done: false),
                                ExecStep(label: "c", done: false)])
        XCTAssertEqual(r.currentStepIndex, 1)
    }

    func testCurrentStepIndexNilWhenAllDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true)])
        XCTAssertNil(r.currentStepIndex)
    }

    func testElapsedStringFormatsMinutesSeconds() {
        let r = makeRun(steps: [])
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 134)), "2:14")
    }

    func testElapsedStringPadsSeconds() {
        let r = makeRun(steps: [])
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 8)), "0:08")
    }

    func testElapsedStringNeverNegative() {
        let r = makeRun(steps: [], startedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 40)), "0:00")
    }

    func testStatusLabelExhaustiveEnglish() {
        XCTAssertEqual(AgentRunStatus.working.label(.en), "Working")
        XCTAssertEqual(AgentRunStatus.reviewing.label(.en), "Reviewing")
        XCTAssertEqual(AgentRunStatus.done.label(.en), "Done")
        XCTAssertEqual(AgentRunStatus.failed.label(.en), "Failed")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -only-testing:codepetTests/AgentsWorkingRowTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — compile error "cannot find 'AgentRun' / 'AgentRunStatus' in scope".

- [ ] **Step 3: Write the model + math**

Create `codepet/Views/Copilot/AgentsWorkingRow.swift`:

```swift
import SwiftUI

/// Status of one concurrent department-agent run.
enum AgentRunStatus: String, Equatable, Codable, CaseIterable {
    case working, reviewing, done, failed

    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.working, .vi):   return "Đang làm"
        case (.working, _):     return "Working"
        case (.reviewing, .vi): return "Đang duyệt"
        case (.reviewing, _):   return "Reviewing"
        case (.done, .vi):      return "Xong"
        case (.done, _):        return "Done"
        case (.failed, .vi):    return "Lỗi"
        case (.failed, _):      return "Failed"
        }
    }
}

/// One department agent working on a task, for the inline multi-agent exec-log.
/// A multi-agent analogue of what `ExecLogRow` shows for a single run.
struct AgentRun: Identifiable, Equatable {
    let id: String
    let companionId: String   // resolves avatar + accent via PetCharacter.all
    let deptName: String      // "Engineering", "Design", …
    let taskTitle: String
    var steps: [ExecStep]     // reuses the existing ExecStep type
    var status: AgentRunStatus
    let startedAt: Date       // for elapsed display

    init(id: String = UUID().uuidString, companionId: String, deptName: String,
         taskTitle: String, steps: [ExecStep], status: AgentRunStatus, startedAt: Date) {
        self.id = id
        self.companionId = companionId
        self.deptName = deptName
        self.taskTitle = taskTitle
        self.steps = steps
        self.status = status
        self.startedAt = startedAt
    }

    /// "4/7" — done steps over total.
    var stepCounter: String { "\(steps.filter { $0.done }.count)/\(steps.count)" }

    /// The first not-done step (the spinning one); nil when all are done.
    var currentStepIndex: Int? { steps.firstIndex { !$0.done } }

    /// "m:ss" elapsed since `startedAt`. `now` is injected so it is testable and
    /// preview-stable (no `Date()` read inside the view).
    func elapsedString(now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -only-testing:codepetTests/AgentsWorkingRowTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS — `Executed 8 tests, with 0 failures`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/AgentsWorkingRow.swift codepetTests/AgentsWorkingRowTests.swift
git commit -F - <<'EOF'
feat(chat): AgentRun model + math for parallel agents-working UI

Value type for one concurrent department-agent run, with pure
step-counter / current-step / elapsed / status-label helpers, unit-tested.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: `AgentsWorkingRow` view + `AgentsWorkingMock` preview

**Files:**
- Modify: `codepet/Views/Copilot/AgentsWorkingRow.swift` (append the view + a `#Preview`)
- Create: `codepet/Views/Copilot/Mocks/AgentsWorkingMock.swift`

**Interfaces:**
- Consumes: `AgentRun`, `AgentRunStatus` (Task 1); `MessageCard(hue:)`, `CompanionAvatar(companionId:size:isWorking:)`, `PetCharacter.all`, `CodepetTheme`, `ExecStep`.
- Produces: `struct AgentsWorkingRow: View` with init `AgentsWorkingRow(runs: [AgentRun], now: Date = Date())`.

- [ ] **Step 1: Append the view to `AgentsWorkingRow.swift`**

Add below the `AgentRun` struct in `codepet/Views/Copilot/AgentsWorkingRow.swift`:

```swift
/// Inline, in-chat view of MULTIPLE department agents working at once — a
/// multi-agent sibling of `ExecLogRow`, modeled on Codex's run list. One card
/// holds a stacked row per active agent; left-aligned like a companion message.
struct AgentsWorkingRow: View {
    let runs: [AgentRun]
    /// Injected clock for elapsed display — stable in previews/tests.
    var now: Date = Date()

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        HStack {
            MessageCard(hue: CodepetTheme.accentPurple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text((lang == .vi ? "Đang làm việc" : "Agents at work")
                            + " · \(runs.count)")
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(CodepetTheme.mutedText)
                    ForEach(Array(runs.enumerated()), id: \.element.id) { idx, run in
                        if idx > 0 { Divider().overlay(CodepetTheme.hairline) }
                        agentRow(run)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func agentRow(_ run: AgentRun) -> some View {
        let persona = PetCharacter.all[run.companionId]
        let accent = persona?.color ?? CodepetTheme.accentPurple
        let name = persona?.name ?? "Codepet"
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                CompanionAvatar(companionId: run.companionId, size: 22,
                                isWorking: run.status == .working)
                Text("\(name) · \(run.deptName)")
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(accent)
                Spacer(minLength: 8)
                statusPill(run.status)
                Text(run.elapsedString(now: now))
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                Text(run.stepCounter)
                    .font(CodepetTheme.inter(11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Text(run.taskTitle)
                .font(CodepetTheme.inter(14))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(run.steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 8) {
                    stepIcon(done: step.done, isCurrent: idx == run.currentStepIndex)
                        .frame(width: 15, height: 15)
                    Text(step.label)
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(step.done ? CodepetTheme.bodyText
                            : (idx == run.currentStepIndex ? CodepetTheme.primaryText
                                                           : CodepetTheme.mutedText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusPill(_ status: AgentRunStatus) -> some View {
        let fg: Color
        let bg: Color
        switch status {
        case .working:   fg = CodepetTheme.accentPurple; bg = CodepetTheme.accentPurple.opacity(0.14)
        case .reviewing: fg = CodepetTheme.accentGold;   bg = CodepetTheme.accentGold.opacity(0.16)
        case .done:      fg = CodepetTheme.accentTeal;   bg = CodepetTheme.accentTeal.opacity(0.16)
        case .failed:    fg = Color.red;                 bg = Color.red.opacity(0.14)
        }
        return Text(status.label(lang))
            .font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }

    // Mirrors ExecLogRow's step icon: done → teal check, current → spinner, else dim ring.
    @ViewBuilder private func stepIcon(done: Bool, isCurrent: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13)).foregroundColor(CodepetTheme.accentTeal)
        } else if isCurrent {
            ProgressView().controlSize(.small).scaleEffect(0.7)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 12)).foregroundColor(CodepetTheme.mutedText.opacity(0.45))
        }
    }
}
```

- [ ] **Step 2: Create the mock preview**

Create `codepet/Views/Copilot/Mocks/AgentsWorkingMock.swift`:

```swift
import SwiftUI

#if DEBUG
#Preview("Agents · working in parallel") {
    let base = Date(timeIntervalSince1970: 0)
    let runs = [
        AgentRun(companionId: "byte", deptName: "Engineering",
                 taskTitle: "Building the waitlist API",
                 steps: [
                    ExecStep(label: "Scaffold the route", done: true),
                    ExecStep(label: "Define the schema", done: true),
                    ExecStep(label: "Write the handler", done: false),
                    ExecStep(label: "Add tests", done: false),
                 ],
                 status: .working, startedAt: base),
        AgentRun(companionId: "luna", deptName: "Design",
                 taskTitle: "Landing hero visual pass",
                 steps: [
                    ExecStep(label: "Moodboard", done: true),
                    ExecStep(label: "Layout", done: false),
                    ExecStep(label: "Typography", done: false),
                 ],
                 status: .working, startedAt: base),
        AgentRun(companionId: "sage", deptName: "Legal",
                 taskTitle: "Privacy policy draft",
                 steps: [ExecStep(label: "Draft clauses", done: true)],
                 status: .done, startedAt: base),
    ]
    return ScrollView {
        AgentsWorkingRow(runs: runs, now: Date(timeIntervalSince1970: 134))
            .frame(maxWidth: 760)
            .padding(.horizontal, 24).padding(.vertical, 40)
    }
    .frame(width: 900, height: 700)
    .background(ChatBackdrop())
    .environmentObject(CompanyStore())
    .environment(\.uiLanguage, .en)
}
#endif
```

- [ ] **Step 3: Build to verify it compiles and previews resolve**

Run:
```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **` (Debug build compiles the `#if DEBUG` `#Preview` blocks).

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/AgentsWorkingRow.swift codepet/Views/Copilot/Mocks/AgentsWorkingMock.swift
git commit -F - <<'EOF'
feat(chat): AgentsWorkingRow — inline parallel agents view + preview

Codex-style multi-agent exec-log: per-agent avatar, Name·Dept, status pill,
elapsed, step counter, and live checklist. Reuses ExecLogRow's step visuals.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: `ChatMockData` harness + `ChatUserMock` scenario

**Files:**
- Create: `codepet/Views/Copilot/Mocks/ChatMockData.swift`
- Create: `codepet/Views/Copilot/Mocks/ChatUserMock.swift`

**Interfaces:**
- Consumes: `CopilotMessage`, `CopilotBubble`, `ChatBackdrop`, `CompanyStore`, `FirstRunAction`.
- Produces: `enum ChatMockData` with `static func conversation(_ messages: [CopilotMessage]) -> some View`.

- [ ] **Step 1: Create the shared harness**

Create `codepet/Views/Copilot/Mocks/ChatMockData.swift`:

```swift
import SwiftUI

#if DEBUG
/// Shared renderer for the chat-scenario preview mocks. Feeds fixture messages
/// through the REAL `CopilotBubble` exactly like `CopilotChatView.messageList`,
/// so the mocks match production and cannot drift. Layout constants mirror the
/// shipped spacing pass (column 760, gutter 24, top 40 / bottom 24, spacing 24).
enum ChatMockData {
    static func conversation(_ messages: [CopilotMessage]) -> some View {
        ZStack {
            ChatBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(messages) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 900, height: 720)
        .environmentObject(CompanyStore())
        .environment(\.uiLanguage, .en)
    }
}
#endif
```

- [ ] **Step 2: Create the "with the user" scenario**

Create `codepet/Views/Copilot/Mocks/ChatUserMock.swift`:

```swift
import SwiftUI

#if DEBUG
#Preview("Chat · with the user") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "Which task should I run right now?"),
        CopilotMessage(role: .companion,
            text: "Your leverage right now is momentum, not polish. Ship the smallest thing a real user can touch this week: write your positioning in one sentence, book five short calls, and put a rough landing page in front of them. Want me to draft the positioning line?"),
        CopilotMessage(role: .me, text: "draft it"),
        CopilotMessage(role: .companion,
            text: "On it — I can start this as a task and do the work with you.",
            firstRunAction: FirstRunAction(taskId: "t1",
                                           taskTitle: "Write your positioning statement")),
    ])
}
#endif
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/Mocks/ChatMockData.swift codepet/Views/Copilot/Mocks/ChatUserMock.swift
git commit -F - <<'EOF'
feat(chat): mock harness + "with the user" scenario preview

ChatMockData renders fixture messages through the real CopilotBubble; the
first scenario preview exercises text bubbles + the first-run action button.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: Roadmap, Tasks, and Environment scenario previews

**Files:**
- Create: `codepet/Views/Copilot/Mocks/ChatRoadmapMock.swift`
- Create: `codepet/Views/Copilot/Mocks/ChatTasksMock.swift`
- Create: `codepet/Views/Copilot/Mocks/ChatEnvMock.swift`

**Interfaces:**
- Consumes: `ChatMockData.conversation(_:)` (Task 3); `CopilotMessage`, `NavAction`, `Deliverable`, `DeliverableKind`, `ExecStep`, `SetupAction`, `RememberedFact`.

- [ ] **Step 1: Create the roadmap scenario**

Create `codepet/Views/Copilot/Mocks/ChatRoadmapMock.swift`:

```swift
import SwiftUI

#if DEBUG
#Preview("Chat · with the roadmap") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "What's next on the roadmap?"),
        CopilotMessage(role: .companion,
            text: "You're in Validation. The one thing between you and launch is a working sign-up that captures real interest — everything else can wait. After that: pricing, then a small paid pilot."),
        CopilotMessage(role: .companion, text: "",
            navChip: NavAction(destination: "roadmap", target: nil)),
    ])
}
#endif
```

- [ ] **Step 2: Create the tasks scenario**

Create `codepet/Views/Copilot/Mocks/ChatTasksMock.swift`:

```swift
import SwiftUI

#if DEBUG
#Preview("Chat · with tasks") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "Run the landing page copy task."),
        CopilotMessage(role: .companion, text: "Write your landing page copy",
            producing: true, companionId: "nova", deptName: "Marketing",
            execSteps: [
                ExecStep(label: "Reading your brief — mission, audience, voice", done: true),
                ExecStep(label: "Pulling in the Marketing playbook", done: true),
                ExecStep(label: "Drafting the headline and subhead", done: false),
                ExecStep(label: "Matching your tone and past decisions", done: false),
            ]),
        CopilotMessage(role: .companion, text: "",
            draft: Deliverable(kind: .post, title: "Landing page copy",
                body: "Headline — Your AI cofounder, not another chatbot.\n\nSubhead — Codepet plans your next move, does the work with you, and remembers every decision — grounded in your actual company.")),
        CopilotMessage(role: .companion, text: "",
            draft: Deliverable(kind: .post, title: "Positioning statement",
                body: "For solo founders who can code but stall on everything else, Codepet is the AI cofounder that runs the whole company with you."),
            draftApproved: true),
    ])
}
#endif
```

- [ ] **Step 3: Create the environment scenario**

Create `codepet/Views/Copilot/Mocks/ChatEnvMock.swift`:

```swift
import SwiftUI

#if DEBUG
#Preview("Chat · setting up the environment") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "Help me set up my tools."),
        CopilotMessage(role: .companion,
            text: "You'll want your code and your notes connected so I can act on them. Start with GitHub — it lets me open PRs and read your repo."),
        CopilotMessage(role: .companion, text: "",
            setupSuggestion: SetupAction(category: "connectors", name: "GitHub")),
        CopilotMessage(role: .companion, text: "",
            noted: [RememberedFact(topic: "Stack",
                                   statement: "Ships a native macOS app in Swift")]),
    ])
}
#endif
```

- [ ] **Step 4: Build to verify all three compile**

Run:
```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/Mocks/ChatRoadmapMock.swift \
        codepet/Views/Copilot/Mocks/ChatTasksMock.swift \
        codepet/Views/Copilot/Mocks/ChatEnvMock.swift
git commit -F - <<'EOF'
feat(chat): roadmap / tasks / environment scenario previews

Three fixture-driven chat mocks exercising the nav chip, the run exec-log +
draft cards (with an approved state), and the setup card + noted chip.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- 5 mock views → Tasks 2 (`AgentsWorkingMock`), 3 (`ChatUserMock`), 4 (roadmap/tasks/env). ✅
- Mocks drive real `CopilotBubble` → `ChatMockData` harness (Task 3). ✅
- `AgentsWorkingRow` + `AgentRun` model → Tasks 1–2. ✅
- Four scenarios cover user / roadmap / tasks / environment with the exact states named in the spec (text + action, nav chip, exec-log + draft + approved, setup card + noted chip). ✅
- Pure-logic tests for step/elapsed/status math → Task 1. ✅ (Color mapping is view-side and not unit-tested; the spec's "status→pill" check is realized as the exhaustive `label` test — an intentional, documented simplification since asserting `Color` equality is brittle.)
- View-layer only / no engine / no persistence → no engine files touched. ✅
- Follow-on (live wiring, engine parallelism, dev gallery) → out of scope, recorded in the spec. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has expected output. ✅

**Type consistency:** `AgentRun` init and members (`stepCounter`, `currentStepIndex`, `elapsedString(now:)`, `AgentRunStatus.label(_:)`) are defined in Task 1 and consumed unchanged in Task 2; `ChatMockData.conversation(_:)` defined in Task 3 and consumed in Task 4; all existing-type initializers match the verified signatures in Global Constraints. ✅
