# Part 1C — Handoff Rule + Context-Model Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Part 1's implementation by closing the one real handoff gap (the Tasks board doesn't route work to chat) and completing Layer 1's read-surface migration (the run-task grounding site still calls `ChatContext.compose` directly).

**Architecture:** Two small, additive changes. Task 1 makes the Tasks board obey the same "work-producing actions land in chat" rule the roadmap already uses (`RoadmapDispatch.navigatesToChat`). Task 2 routes the last direct `ChatContext.compose` caller (run-task) through the typed `CompanyContext` read-surface via a new byte-parity `runTaskGroundingString` projection — after which `ChatContext.compose` is called only inside `CompanyContext`.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild. No new dependencies.

## Scope

This is the whole of Part 1C. **Layer 3 (the unified `proposed→running→result→review→committed` lifecycle abstraction) is deliberately deferred to Part 2** — there is only one execution backend today (cloud); the second (the local coding agent) arrives in Part 2, and a two-backend unification built now would be speculative (engine-ahead-of-plays). The existing status models (`AgentRunStatus`, `runningTaskIds`, `task.drafted/done`, `RoadmapEngine.status`) already serve the single cloud path. When Part 2 adds the local backend, that is when the shared lifecycle type earns its place.

With 1C done, Part 1 is implemented through Layers 1, 2, and 4; Layer 3 is deferred by design.

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest.
- **Additive / no behavior regression.** Task 2 must keep the run-task grounding string byte-identical (run-task does NOT gain library/prior-work grounding in this plan — that would change the run-task payload and is a separate, deliberate follow-up).
- **One handoff rule.** The Tasks board must use the SAME `RoadmapDispatch.navigatesToChat` decision the roadmap uses — do not invent a second rule.
- Build/test signing: `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`.
- **Before `xcodebuild test`, close any running `codepet.app`** (Firestore lock). `CompanyContextTests` and `RoadmapDispatchTests` are pure and run cleanly; `CompanyStoreChatTests`/run-task suites boot Firestore and may not run in the Xcode-26 host (documented flake) — don't block on them.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Modify** `codepet/Views/Tasks/TasksView.swift` — the `card(_:)` tap handler routes run/walkThrough to chat via `RoadmapDispatch.navigatesToChat` (Task 1).
- **Modify** `codepetTests/RoadmapDispatchTests.swift` — lock the `navigatesToChat` mapping if not already asserted (Task 1).
- **Modify** `codepet/Models/CompanyContext.swift` — add `runTaskGroundingString` (Task 2).
- **Modify** `codepet/Managers/CompanyStore.swift` — run-task site (~line 1062) uses `CompanyContext(...).runTaskGroundingString` (Task 2).
- **Modify** `codepetTests/CompanyContextTests.swift` — parity test for `runTaskGroundingString` (Task 2).

---

## Task 1: Tasks board obeys the "work lands in chat" handoff rule

**Files:**
- Modify: `codepet/Views/Tasks/TasksView.swift` (the `card(_:)` Button action, ~lines 89-96)
- Test: `codepetTests/RoadmapDispatchTests.swift`

**Interfaces:**
- Consumes: `RoadmapDispatch.action(for:)` and `RoadmapDispatch.navigatesToChat(_:)` (exist in `codepet/Models/RoadmapDispatch.swift`); `companyStore.select(.chat)`.
- Produces: no new symbols — the Tasks board now calls `companyStore.select(.chat)` after dispatching a run/walkThrough, exactly as `RoadmapView.dispatch` does.

- [ ] **Step 1: Lock the shared handoff rule (test)**

Ensure `codepetTests/RoadmapDispatchTests.swift` asserts the mapping the Tasks board will rely on. If these exact assertions aren't already present, add them (inside the existing test type):

```swift
    func test_navigatesToChat_onlyForRunAndWalkThrough() {
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.run))
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.walkThrough))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.approve))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.openDeliverable))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.none))
    }
```

- [ ] **Step 2: Run the rule test (green — it's pure)**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapDispatchTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS. (If the assertion already existed, this simply confirms it.)

- [ ] **Step 3: Route the Tasks board tap through the rule**

In `codepet/Views/Tasks/TasksView.swift`, replace the `card(_:)` Button action:

```swift
        Button {
            let st = RoadmapEngine.status(for: t, in: companyStore.company.tasks)
            if st == .needsApproval { previewTask = t }
            else if st == .codepetCanDo { Task { await companyStore.runTask(t, language: lang) } }
            else if st == .needsYou { Task { await companyStore.walkThroughTask(t, language: lang) } }
            else if st == .done { openDeliverable = RoadmapEngine.deliverable(for: t, in: companyStore.company.library) }
        } label: {
```

with (adds the shared handoff decision — run/walkThrough now follow their result to chat, matching the roadmap; approve keeps its in-place preview sheet, done keeps its in-place deliverable sheet):

```swift
        Button {
            let st = RoadmapEngine.status(for: t, in: companyStore.company.tasks)
            if st == .needsApproval { previewTask = t }
            else if st == .codepetCanDo { Task { await companyStore.runTask(t, language: lang) } }
            else if st == .needsYou { Task { await companyStore.walkThroughTask(t, language: lang) } }
            else if st == .done { openDeliverable = RoadmapEngine.deliverable(for: t, in: companyStore.company.library) }
            // Same handoff rule as the roadmap: work-producing taps land in chat,
            // where the run/walkthrough streams; approve + open stay in place.
            if RoadmapDispatch.navigatesToChat(RoadmapDispatch.action(for: st)) {
                companyStore.select(.chat)
            }
        } label: {
```

- [ ] **Step 4: Build to verify the wiring compiles**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (`RoadmapDispatch` is already imported-in-module; no new import needed.)

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Tasks/TasksView.swift codepetTests/RoadmapDispatchTests.swift
git commit -F - <<'EOF'
fix(tasks): Tasks board follows run/walkthrough to chat (Bus Layer 4)

The board dispatched runTask/walkThroughTask without navigating, so the
founder watched nothing happen while the work streamed into chat. Now it
uses the same RoadmapDispatch.navigatesToChat rule the roadmap uses:
work-producing taps land in chat; approve + open stay in place.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: Route the run-task grounding through `CompanyContext`

**Files:**
- Modify: `codepet/Models/CompanyContext.swift`
- Modify: `codepet/Managers/CompanyStore.swift` (run-task `runRequest`, ~line 1062)
- Test: `codepetTests/CompanyContextTests.swift`

**Interfaces:**
- Consumes: `CompanyContext.init(company:)`, `ChatContext.compose(...)`.
- Produces: `var runTaskGroundingString: String` on `CompanyContext` — the leaner projection run-task uses (brief + tasks + decisions; no library/query/focus), byte-identical to the run-task site's current inline `ChatContext.compose(brief:tasks:decisions:)`.

- [ ] **Step 1: Write the failing parity test**

Add to `codepetTests/CompanyContextTests.swift` (inside the class):

```swift
    func test_runTaskGroundingString_matchesLeanCompose() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        // Byte-identical to the run-task site's pre-migration inline call:
        // brief + tasks + decisions only — no library/query/focus.
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions)
        XCTAssertEqual(ctx.runTaskGroundingString, expected)
    }

    func test_runTaskGroundingString_excludesLibraryPriorWork() {
        // Even with a rich fixture (non-empty library), the run-task projection must
        // NOT include the prior-work/library block that the chat groundingString has.
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        XCTAssertFalse(ctx.runTaskGroundingString.contains("Landing page draft"),
                       "run-task grounding must stay lean — no library prior-work block")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `runTaskGroundingString` is not a member of `CompanyContext`.

- [ ] **Step 3: Add the projection**

In `codepet/Models/CompanyContext.swift`, add after the `groundingString` computed property:

```swift
    /// The leaner grounding string the run-task backend uses: brief + roadmap +
    /// decisions, WITHOUT the library/prior-work block that `groundingString`
    /// carries for chat. Byte-identical to the run-task site's previous inline
    /// `ChatContext.compose(brief:tasks:decisions:)` call — a structural migration
    /// (the run-task payload is unchanged). Never references `project` (client-only).
    var runTaskGroundingString: String {
        ChatContext.compose(brief: brief, tasks: tasks, decisions: decisions)
    }
```

- [ ] **Step 4: Route the run-task site through it**

In `codepet/Managers/CompanyStore.swift`, in the run-task `runRequest(...)` builder (~line 1062), replace:

```swift
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions),
```

with:

```swift
            context: CompanyContext(company: company).runTaskGroundingString,
```

- [ ] **Step 5: Run tests to verify green**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — all `CompanyContextTests` including the two new ones.

- [ ] **Step 6: Build + confirm no direct `ChatContext.compose` callers remain outside `CompanyContext`**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
grep -rn "ChatContext.compose(" codepet/ | grep -v "CompanyContext.swift"
```
Expected: `** BUILD SUCCEEDED **`, and the grep returns only comment lines (no remaining call site) — `ChatContext.compose` is now invoked exclusively inside `CompanyContext`.

- [ ] **Step 7: Commit**

```bash
git add codepet/Models/CompanyContext.swift codepet/Managers/CompanyStore.swift codepetTests/CompanyContextTests.swift
git commit -F - <<'EOF'
refactor(context): route run-task grounding through CompanyContext (Bus Layer 1)

Adds runTaskGroundingString (brief+tasks+decisions, byte-identical to the
old inline call — no library grounding, no payload change) and migrates the
run-task site to it. ChatContext.compose is now called only inside
CompanyContext — the single Layer-1 read-surface.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (Part 1 completion):**
- Layer 4 handoff rule generalized to the Tasks board → Task 1. ✅
- Layer 1 read-surface migration completed (run-task now via `CompanyContext`; `ChatContext.compose` called only inside it) → Task 2. ✅
- Layer 3 unified lifecycle → explicitly deferred to Part 2 (see Scope) — a conscious decision, not a gap. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code + expected output.

**3. Type consistency:** `RoadmapDispatch.action(for:)`/`navigatesToChat(_:)` match `RoadmapDispatch.swift`. `runTaskGroundingString` is named identically in the projection, the run-task site, and the tests. `fixtureCompany()` already exists in `CompanyContextTests` (from 1A/1B) with a non-empty `library` containing "Landing page draft" (used by the exclusion test).

**Deferred (not this plan):** the Layer-3 lifecycle type (Part 2, when the local backend exists); enabling library/prior-work grounding for run-task (a deliberate output change, separate from this structural migration); shipping the held app branch.
