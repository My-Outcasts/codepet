# Parallel Department Agents — Live Fan-Out — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One tap ("Run my next moves") fans a prompt out to up to 3 department agents that run in parallel, shown live in chat via the existing `AgentsWorkingRow`, with each agent's draft landing in the transcript as it finishes.

**Architecture:** A pure client-side planner (`RoadmapEngine.nextMoves`) picks the next `codepetCanDo` task per department; `CompanyStore.fanOutNextMoves` seeds a published `[AgentRun]` and fans out concurrent `RunTaskClient` calls via a `TaskGroup` (the network layer is already stateless/parallel-safe); `CopilotChatView` adds the trigger chip and renders `AgentsWorkingRow` live. No Cloud Function changes.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS target/scheme `codepet` (lowercase). `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — so a `TaskGroup` awaiting `taskRunner` yields real parallel network I/O without `Sendable` gymnastics.

## Global Constraints

- Reuse existing symbols — do NOT redefine: `AgentRun`/`AgentRunStatus` (`codepet/Views/Copilot/AgentsWorkingRow.swift`), `RoadmapTask`, `TaskStatus`, `RoadmapEngine.status(for:in:)`, `RoadmapPhase.order`, `DepartmentCompanions.companionId(for:)`, `DepartmentCatalog.find(_:)`, `ExecStep`, `CopilotMessage`, `QuickAction`, `RunTaskClient`.
- `CompanyStore` is `@MainActor`; all `@Published` mutations happen on the main actor. Concurrency is via structured `TaskGroup`; each concurrent branch MUST re-check `companyId == cid` after every `await` (account-switch safety — the existing idiom in `produceDraftInline`).
- Reuse these private `CompanyStore` members verbatim (already exist): `Self.execSteps(task:specialist:decisionCount:language:)`, `runRequest(for:language:)`, `buildDeliverable(from:task:)`, `taskRunner` (`(RunTaskRequest) async -> RunTaskResponse?`), `companyId` (`String?`), `company.decisions.count`, `Self.execStepNanos`, `Self.execDoneBeatNanos`, `flushActiveThread()`.
- Cap: `static let maxFanOut = 3`.
- `AgentRun` mutable fields are `var steps` and `var status` (mutate in place in the `activeAgentRuns` array). `AgentRun.id` is set to the task's id for lookup.
- Localization: every user-facing string has `.vi` and `.en` forms (`lang == .vi ? … : …`), matching the file's existing pattern.
- Preview/dev-only code stays under `#if DEBUG` (not relevant to these tasks, but don't remove existing guards).

---

### Task 1: `RoadmapEngine.nextMoves` planner + tests

**Files:**
- Modify: `codepet/Models/RoadmapEngine.swift` (add one static function)
- Test: `codepetTests/RoadmapEngineNextMovesTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapEngine.status(for:in:)`, `RoadmapPhase.order`, `DepartmentCompanions.companionId(for:)`.
- Produces: `static func RoadmapEngine.nextMoves(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask]`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/RoadmapEngineNextMovesTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapEngineNextMovesTests: XCTestCase {
    // Helper: a codepetCanDo-eligible task by default (who: .does, not done/drafted, no deps).
    private func task(_ id: String, dept: String?, phase: RoadmapPhase,
                      who: TaskWho = .does, done: Bool = false, drafted: Bool = false,
                      dependsOn: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: dependsOn, done: done, drafted: drafted, dept: dept)
    }

    func testPicksFirstCodepetCanDoPerDistinctDeptInRoadmapOrder() {
        let tasks = [
            task("m1", dept: "mkt", phase: .launch),
            task("e1", dept: "eng", phase: .build),
            task("e2", dept: "eng", phase: .build),   // same dept as e1 → skipped
            task("d1", dept: "design", phase: .foundation),
        ]
        let picked = RoadmapEngine.nextMoves(tasks, limit: 3).map(\.id)
        // Ordered by phase: foundation(d1) < build(e1) < launch(m1); one per dept.
        XCTAssertEqual(picked, ["d1", "e1", "m1"])
    }

    func testCapLimitsCount() {
        let tasks = [
            task("d1", dept: "design", phase: .foundation),
            task("e1", dept: "eng", phase: .build),
            task("m1", dept: "mkt", phase: .launch),
            task("f1", dept: "fin", phase: .grow),
        ]
        XCTAssertEqual(RoadmapEngine.nextMoves(tasks, limit: 2).map(\.id), ["d1", "e1"])
    }

    func testSkipsIneligibleTasks() {
        let tasks = [
            task("done1", dept: "eng", phase: .build, done: true),          // done
            task("you1", dept: "design", phase: .build, who: .you),         // needsYou
            task("draft1", dept: "mkt", phase: .build, drafted: true),      // needsApproval
            task("blocked1", dept: "fin", phase: .build, dependsOn: ["x"]), // blocked (dep x not done)
            task("x", dept: "fin", phase: .build, done: false),             // the missing dep target (not done)
            task("nodept", dept: nil, phase: .build),                       // no dept
            task("nomap", dept: "zzz", phase: .build),                      // dept has no companion mapping
            task("ok", dept: "ops", phase: .build),                         // the only eligible one
        ]
        XCTAssertEqual(RoadmapEngine.nextMoves(tasks, limit: 3).map(\.id), ["ok"])
    }

    func testEmptyWhenNothingActionableOrLimitZero() {
        let none = [task("you1", dept: "eng", phase: .build, who: .you)]
        XCTAssertEqual(RoadmapEngine.nextMoves(none, limit: 3).count, 0)
        XCTAssertEqual(RoadmapEngine.nextMoves([], limit: 3).count, 0)
        XCTAssertEqual(RoadmapEngine.nextMoves([task("e1", dept: "eng", phase: .build)], limit: 0).count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -only-testing:codepetTests/RoadmapEngineNextMovesTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — "type 'RoadmapEngine' has no member 'nextMoves'".

- [ ] **Step 3: Implement `nextMoves`**

In `codepet/Models/RoadmapEngine.swift`, add inside `enum RoadmapEngine` (e.g. after `nextStep`):

```swift
    /// Up to `limit` parallelizable "next moves" for the chat fan-out: the first
    /// `codepetCanDo` task in each DISTINCT department that maps to a specialist
    /// companion, in roadmap order (phase order, then array position). Pure.
    static func nextMoves(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask] {
        guard limit > 0 else { return [] }
        let ordered = tasks.enumerated().sorted { a, b in
            a.element.phase.order != b.element.phase.order
                ? a.element.phase.order < b.element.phase.order
                : a.offset < b.offset
        }.map { $0.element }
        var seenDepts = Set<String>()
        var out: [RoadmapTask] = []
        for task in ordered {
            guard let dept = task.dept,
                  DepartmentCompanions.companionId(for: dept) != nil,
                  !seenDepts.contains(dept),
                  status(for: task, in: tasks) == .codepetCanDo else { continue }
            seenDepts.insert(dept)
            out.append(task)
            if out.count == limit { break }
        }
        return out
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -only-testing:codepetTests/RoadmapEngineNextMovesTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS — `Executed 4 tests, with 0 failures`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineNextMovesTests.swift
git commit -F - <<'EOF'
feat(chat): RoadmapEngine.nextMoves planner for parallel fan-out

Pure: first codepetCanDo task per distinct department (with a specialist
companion), roadmap order, capped. Backs the chat fan-out.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: `CompanyStore` fan-out engine

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.nextMoves` (Task 1); existing private members listed in Global Constraints; `AgentRun`, `AgentRunStatus`, `DepartmentCatalog`, `DepartmentCompanions`.
- Produces: `@Published var activeAgentRuns: [AgentRun]`, `@Published private(set) var isFanningOut: Bool`, `static let maxFanOut`, `func fanOutNextMoves(language:)`.

- [ ] **Step 1: Add published state + the cap**

In `codepet/Managers/CompanyStore.swift`, immediately after the `runningTaskIds` declaration (`@Published var runningTaskIds: Set<String> = ...`, ~line 43), add:

```swift
    /// Live parallel department-agent runs (the chat fan-out). Rendered as one
    /// AgentsWorkingRow; empty ⇒ no row. Seeded by `fanOutNextMoves`, cleared when
    /// the whole fan-out completes; each agent's draft lands in `chatMessages`.
    @Published var activeAgentRuns: [AgentRun] = []
    /// True while a fan-out is in flight — serializes it against a normal chat turn
    /// and disables the composer (same busy model as a single run).
    @Published private(set) var isFanningOut: Bool = false
    /// Max concurrent department agents per fan-out (bounds credit spend + latency).
    static let maxFanOut = 3
```

- [ ] **Step 2: Add `fanOutNextMoves` + `runFanOutAgent`**

In `codepet/Managers/CompanyStore.swift`, add these two methods right after `produceDraftInline(...)` (after its closing brace, ~line 777):

```swift
    /// Fan out the next actionable task in up to `maxFanOut` departments as parallel
    /// department-agent runs, shown live via `activeAgentRuns` (AgentsWorkingRow).
    /// Each agent's draft lands in the transcript as it finishes. Account-guarded.
    func fanOutNextMoves(language: AppLanguage) async {
        guard !isFanningOut, !isCompanionTyping, !isStreaming else { return }
        let plan = RoadmapEngine.nextMoves(company.tasks, limit: Self.maxFanOut)
        guard !plan.isEmpty else {
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Bạn đang không có việc nào mình chạy được ngay — lộ trình đã gọn rồi."
                : "You're all caught up — no open tasks I can run right now."))
            flushActiveThread()
            return
        }
        let cid = companyId
        isFanningOut = true

        let now = Date()
        var seeded: [(run: AgentRun, task: RoadmapTask)] = []
        for task in plan {
            let deptName = DepartmentCatalog.find(task.dept)?.name ?? (task.dept ?? "")
            let companionId = task.dept.flatMap { DepartmentCompanions.companionId(for: $0) }
                ?? company.companionId
            let specialist: (companionId: String, deptName: String)? =
                deptName.isEmpty ? nil : (companionId, deptName)
            let steps = Self.execSteps(task: task, specialist: specialist,
                                       decisionCount: company.decisions.count, language: language)
            let run = AgentRun(id: task.id, companionId: companionId, deptName: deptName,
                               taskTitle: task.title, steps: steps, status: .working, startedAt: now)
            seeded.append((run, task))
        }
        activeAgentRuns = seeded.map { $0.run }

        await withTaskGroup(of: Void.self) { group in
            for item in seeded {
                group.addTask {
                    await self.runFanOutAgent(runId: item.run.id, task: item.task,
                                              cid: cid, language: language)
                }
            }
        }

        guard companyId == cid else { activeAgentRuns = []; isFanningOut = false; return }
        try? await Task.sleep(nanoseconds: Self.execDoneBeatNanos)   // let final pills show
        guard companyId == cid else { activeAgentRuns = []; isFanningOut = false; return }
        activeAgentRuns = []
        isFanningOut = false
        flushActiveThread()
    }

    /// One agent's run inside a fan-out: reveal its steps client-side while its
    /// `taskRunner` call runs, then flip its `AgentRun` to done/failed and append
    /// its draft (or an honest failure bubble). Mutations are main-actor; the
    /// `taskRunner` await is where parallelism happens. Account-guarded via `cid`.
    private func runFanOutAgent(runId: String, task: RoadmapTask,
                                cid: String?, language: AppLanguage) async {
        let reveal = Task { [cid] in
            let stepCount = activeAgentRuns.first(where: { $0.id == runId })?.steps.count ?? 0
            for idx in 0..<max(0, stepCount - 1) {
                try? await Task.sleep(nanoseconds: Self.execStepNanos)
                guard companyId == cid,
                      let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) else { return }
                activeAgentRuns[ri].steps[idx].done = true
            }
        }
        let result = await taskRunner(runRequest(for: task, language: language))
        _ = await reveal.value
        guard companyId == cid else { return }

        if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
            for i in activeAgentRuns[ri].steps.indices { activeAgentRuns[ri].steps[i].done = true }
        }
        let companionId = activeAgentRuns.first(where: { $0.id == runId })?.companionId
        let deptName = activeAgentRuns.first(where: { $0.id == runId })?.deptName
        if let draft = buildDeliverable(from: result, task: task) {
            if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
                activeAgentRuns[ri].status = .done
            }
            chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft,
                                               companionId: companionId, deptName: deptName))
        } else {
            if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
                activeAgentRuns[ri].status = .failed
            }
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không hoàn thành được “\(task.title)”. Thử lại nhé."
                : "Couldn't finish “\(task.title)” — try again.",
                companionId: companionId, deptName: deptName))
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.
(If strict-concurrency emits `Sendable` WARNINGS on the `TaskGroup` capture, that is acceptable under Swift 5 mode — the build must still SUCCEED. If it ERRORS, report DONE_WITH_CONCERNS with the exact message.)

- [ ] **Step 4: Commit**

```bash
git add codepet/Managers/CompanyStore.swift
git commit -F - <<'EOF'
feat(chat): CompanyStore fan-out engine (parallel dept agents)

fanOutNextMoves plans next moves, seeds activeAgentRuns, and fans out
concurrent RunTaskClient calls via a TaskGroup; each agent reveals its
steps, flips to done/failed, and appends its draft as it finishes.
Account-guarded per branch; composer serialized via isFanningOut.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: `CopilotChatView` wiring (trigger chip + live row + busy state)

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: `CompanyStore.fanOutNextMoves(language:)`, `activeAgentRuns`, `isFanningOut` (Task 2); `AgentsWorkingRow(runs:)`; `QuickAction`.

- [ ] **Step 1: Fold `isFanningOut` into the busy state**

In `codepet/Views/Copilot/CopilotChatView.swift`, change `isChatBusy` (~line 40):

```swift
    private var isChatBusy: Bool { companyStore.isCompanionTyping || companyStore.isStreaming || companyStore.isFanningOut }
```

And in `canSend` (~line 140-142), add the fan-out flag — change:
```swift
            && !companyStore.isCompanionTyping && !companyStore.isStreaming
```
to:
```swift
            && !companyStore.isCompanionTyping && !companyStore.isStreaming && !companyStore.isFanningOut
```

- [ ] **Step 2: Add the "Run my next moves" quick-action chip**

In `quickActions` (~line 246-267), replace the `return` statement at the end so the fan-out chip is prepended. Change:

```swift
        return (0..<titles.count).map { i in
            QuickAction(title: titles[i], systemImage: icons[i], detail: details[i])
        }
```
to:
```swift
        let base = (0..<titles.count).map { i in
            QuickAction(title: titles[i], systemImage: icons[i], detail: details[i])
        }
        return [QuickAction(title: fanOutTitle, systemImage: "bolt.horizontal.circle",
                            detail: lang == .vi
                                ? "Chạy song song các việc tiếp theo trên nhiều phòng ban."
                                : "Run your next tasks across departments in parallel.")] + base
```

Add this computed property just above `quickActions` (before its doc comment, ~line 244):

```swift
    /// The stable label for the parallel fan-out chip — compared in runQuickAction to
    /// route the tap to fanOutNextMoves instead of the normal chat-send path.
    private var fanOutTitle: String { lang == .vi ? "Chạy các bước tiếp theo" : "Run my next moves" }
```

- [ ] **Step 3: Route the chip tap to the fan-out**

In `runQuickAction(_:)` (~line 271-274), change:

```swift
    private func runQuickAction(_ text: String) {
        guard !companyStore.isCompanionTyping, !companyStore.isStreaming else { return }
        Task { await companyStore.sendChat(text, language: lang, department: selectedDept) }
    }
```
to:
```swift
    private func runQuickAction(_ text: String) {
        guard !companyStore.isCompanionTyping, !companyStore.isStreaming, !companyStore.isFanningOut else { return }
        if text == fanOutTitle {
            Task { await companyStore.fanOutNextMoves(language: lang) }
            return
        }
        Task { await companyStore.sendChat(text, language: lang, department: selectedDept) }
    }
```

- [ ] **Step 4: Render the live `AgentsWorkingRow` in the message list**

In `messageList` (~line 175-199), inside the `VStack`, add the row after the typing-row line. Change:

```swift
                    if companyStore.isCompanionTyping { ChatThinkingRow(taskTitle: nil).id("typing") }
                }
```
to:
```swift
                    if companyStore.isCompanionTyping { ChatThinkingRow(taskTitle: nil).id("typing") }
                    if !companyStore.activeAgentRuns.isEmpty {
                        AgentsWorkingRow(runs: companyStore.activeAgentRuns).id("agents")
                    }
                }
```

Then add an auto-scroll trigger — after the existing `.onChange(of: companyStore.isCompanionTyping) { … }` block (~line 197-199), add:

```swift
            .onChange(of: companyStore.activeAgentRuns.count) { _, count in
                if count > 0 { withAnimation { proxy.scrollTo("agents", anchor: .bottom) } }
            }
```

- [ ] **Step 5: Build to verify**

Run:
```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -F - <<'EOF'
feat(chat): wire the parallel fan-out into the chat UI

Add the "Run my next moves" quick-action chip (routes to fanOutNextMoves),
render the live AgentsWorkingRow in the message list with auto-scroll, and
disable the composer while a fan-out is in flight.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- Planner (client-side, per-dept, cap 3, roadmap order) → Task 1. ✅
- `activeAgentRuns` + `isFanningOut` + `maxFanOut` + `fanOutNextMoves` + concurrent `TaskGroup` + per-branch `cid` re-check + drafts-as-they-finish + clear-at-end → Task 2. ✅
- Trigger chip, live `AgentsWorkingRow`, composer disabled → Task 3. ✅
- Failure honesty (`nil`/429 → `.failed` + honest bubble) → Task 2 `runFanOutAgent` else-branch. ✅
- Empty-plan honest bubble → Task 2 `fanOutNextMoves` guard. ✅
- Out-of-scope (LLM/CF planner, streamed steps, chat-while-running, 429 decode) → not built. ✅

**Placeholder scan:** No TBD/TODO; every step has complete code + exact commands with expected output. ✅

**Type consistency:** `RoadmapEngine.nextMoves(_:limit:)` defined in Task 1, consumed in Task 2. `activeAgentRuns`/`isFanningOut`/`fanOutNextMoves` defined in Task 2, consumed in Task 3. `AgentRun(id:companionId:deptName:taskTitle:steps:status:startedAt:)`, mutable `steps`/`status`, and `AgentsWorkingRow(runs:)` match the shipped component. `runRequest`/`buildDeliverable`/`taskRunner`/`execSteps`/`companyId`/`flushActiveThread` match verified `CompanyStore` signatures. ✅

**Note on concurrency:** Swift 5 mode + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: the `TaskGroup` children call the `@MainActor` `runFanOutAgent`, whose `await taskRunner(...)` suspends the actor so N HTTP requests are in flight concurrently (parallel I/O), while all `@Published` mutations remain main-actor-serial (no data race). Any `Sendable` diagnostics are warnings, not errors, in this mode.
