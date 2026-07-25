# Fix: Run → Approve Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the web's run→approve state machine so a run produces a draft on the task (→ "Awaiting approval"), approve copies it to the library exactly once (→ Done), and re-running never duplicates deliverables.

**Architecture:** Root cause (confirmed): `CompanyStore.runTask` appends a `Deliverable` to `company.library` at run time and never sets `task.drafted`/`done` nor persists tasks, so the task stays in "Up next", "Awaiting approval" (`drafted && !done`) is unreachable, and repeat taps duplicate library entries. Fix: (1) store the generated deliverable as a persisted `draft` on `RoadmapTask` and set `drafted=true` on run — no library write; (2) a new `approveTask` moves the draft to the library once and sets `done`; (3) dedupe re-runs of an already-drafted task; (4) add an "Approve" affordance to the board/columns. Draft lives on the task (Codable → persists via the existing `companies/{uid}` JSON path; survives relaunch). Web parity: `persistTaskDraft` (drafted on run) + `approveTask` (library on approve) + "you already have a draft" dedupe.

**Tech Stack:** Swift, SwiftUI, XCTest. Build: `xcodebuild` scheme `codepet`.

## Global Constraints

- Branch `fix/run-approve-loop` (off `origin/main`; independent of PR #12). Work in `~/Documents/Murror/codepet`.
- Draft persists via `RoadmapTask` Codable — `CompanyData` needs NO change (it round-trips tasks with `JSONEncoder().encode(tasks)`).
- On run: set `draft` + `drafted=true`, persist via `tasksSaver`, DO NOT append to `library`. On approve: append draft to `library` once, set `done=true`, `drafted=false`, `draft=nil`, persist BOTH `librarySaver` + `tasksSaver`.
- Dedupe: `runTask` on a task that is `drafted && !done` is a no-op (don't regenerate). `approveTask` on a task with no `draft` or already `done` is a no-op (no duplicate library entry).
- The chat-side draft/approve path (`runFirstRunAction`/`approveDraft`, `sendChat`'s inline draft) is OUT OF SCOPE — do not change it.
- **Xcode 26.2 test caveat:** hosted XCTest crashes on teardown of `@MainActor` classes (known toolchain bug, NOT code). `RoadmapTask` tests (Task 1) are struct-only → run clean. `CompanyStore` tests (Task 2) compile but the host may crash on teardown → "verify" = assertions ran green + `xcodebuild build … CODE_SIGNING_ALLOWED=NO` succeeds. Do NOT treat the teardown crash as failure.
- Build/verify: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` (foreground, never background).

---

### Task 1: Add a persisted `draft` to `RoadmapTask`

**Files:**
- Modify: `codepet/Models/RoadmapTask.swift`
- Test: `codepetTests/RoadmapTaskModelTests.swift`

**Interfaces:**
- Produces: `RoadmapTask.draft: Deliverable?` (nil default). Consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/RoadmapTaskModelTests.swift`:

```swift
func testDraftRoundTripsThroughCodable() throws {
    let d = Deliverable(kind: .doc, title: "Draft", body: "body", sourceTaskId: "t1")
    let t = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .draft, drafted: true, draft: d)
    let data = try JSONEncoder().encode(t)
    let back = try JSONDecoder().decode(RoadmapTask.self, from: data)
    XCTAssertEqual(back.draft?.title, "Draft")
    XCTAssertEqual(back.draft?.sourceTaskId, "t1")
    XCTAssertTrue(back.drafted)
}
func testDraftDefaultsNilAndDecodesFromLegacyTaskWithoutField() throws {
    XCTAssertNil(RoadmapTask(id: "x", title: "T", detail: "", phase: .find, who: .does).draft)
    // legacy stored task (no `draft` key) still decodes (optional field)
    let legacy = #"{"id":"x","title":"T","detail":"","phase":"find","who":"does","dependsOn":[],"done":false,"drafted":false}"#
    let back = try JSONDecoder().decode(RoadmapTask.self, from: Data(legacy.utf8))
    XCTAssertNil(back.draft)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapTaskModelTests`
Expected: FAIL to compile — `RoadmapTask` has no `draft` parameter/member.

- [ ] **Step 3: Add the field**

In `codepet/Models/RoadmapTask.swift`, add the stored property after `dept` (~line 40):

```swift
    /// A generated-but-unapproved deliverable awaiting the founder's approval. Set by
    /// runTask (moves the task to "Awaiting approval"); moved into the library and
    /// cleared on approve. OPTIONAL: legacy tasks predate it and decode to nil.
    var draft: Deliverable?
```

Add `draft` to the initializer — new last parameter with a default and its assignment:

```swift
    init(id: String, title: String, detail: String, phase: RoadmapPhase, who: TaskWho,
         dependsOn: [String] = [], done: Bool = false, drafted: Bool = false, dept: String? = nil,
         draft: Deliverable? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.phase = phase
        self.who = who; self.dependsOn = dependsOn; self.done = done; self.drafted = drafted
        self.dept = dept
        self.draft = draft
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapTaskModelTests`
Expected: PASS (RoadmapTask is a struct → runs clean under Xcode 26.2).

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/RoadmapTask.swift codepetTests/RoadmapTaskModelTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: add persisted draft to RoadmapTask

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rework `runTask` + add `approveTask` in `CompanyStore`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (`runTask`; add `approveTask`)
- Test: `codepetTests/CompanyStoreRunTaskTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask.draft` (Task 1); existing `buildDeliverable`, `tasksSaver`, `librarySaver`, `runRequest`, `runningTaskIds`.
- Produces: new `func approveTask(id: String) async`; changed `runTask` semantics (draft-on-task, no library write).

- [ ] **Step 1: Write the failing tests**

Read `codepetTests/CompanyStoreRunTaskTests.swift` for the existing `CompanyStore(...)` stub pattern (injected `loader`, `taskRunner`, `tasksSaver`, `librarySaver`). Add:

```swift
func testRunTaskStashesDraftAndMarksDraftedWithoutTouchingLibrary() async {
    var tasksSaved = false, librarySaved = false
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(),
                            tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
    let s = CompanyStore(
        loader: { _ in seed },
        tasksSaver: { _, _ in tasksSaved = true; return true },
        librarySaver: { _, _ in librarySaved = true; return true },
        taskRunner: { _ in RunTaskResponse(title: "Out", body: "the body", kind: "doc") })
    await s.hydrate(companyId: "u")
    await s.runTask(s.company.tasks[0], language: .en)
    XCTAssertNotNil(s.company.tasks[0].draft)        // draft stashed on task
    XCTAssertTrue(s.company.tasks[0].drafted)        // → Awaiting approval
    XCTAssertFalse(s.company.tasks[0].done)
    XCTAssertTrue(s.company.library.isEmpty)         // NOT added to library on run
    XCTAssertTrue(tasksSaved)                        // tasks persisted
    XCTAssertFalse(librarySaved)                     // library not persisted on run
}

func testRunTaskDedupesWhenAlreadyDrafted() async {
    var runs = 0
    let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                              drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: [drafted])
    let s = CompanyStore(loader: { _ in seed },
                         taskRunner: { _ in runs += 1; return RunTaskResponse(title: "X", body: "y", kind: "doc") })
    await s.hydrate(companyId: "u")
    await s.runTask(s.company.tasks[0], language: .en)
    XCTAssertEqual(runs, 0)                           // already drafted → not re-run
    XCTAssertEqual(s.company.library.count, 0)
}

func testApproveTaskMovesDraftToLibraryOnceAndMarksDone() async {
    let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                              drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: [drafted])
    let s = CompanyStore(loader: { _ in seed })
    await s.hydrate(companyId: "u")
    await s.approveTask(id: "t1")
    XCTAssertEqual(s.company.library.count, 1)        // moved to library once
    XCTAssertEqual(s.company.library[0].title, "D")
    XCTAssertTrue(s.company.tasks[0].done)
    XCTAssertFalse(s.company.tasks[0].drafted)
    XCTAssertNil(s.company.tasks[0].draft)            // consumed
    await s.approveTask(id: "t1")                     // idempotent
    XCTAssertEqual(s.company.library.count, 1)        // no duplicate
}

func testApproveTaskNoOpWithoutDraft() async {
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(),
                            tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
    let s = CompanyStore(loader: { _ in seed })
    await s.hydrate(companyId: "u")
    await s.approveTask(id: "t1")
    XCTAssertTrue(s.company.library.isEmpty)
    XCTAssertFalse(s.company.tasks[0].done)
}
```

(If `CompanyState`'s memberwise init differs, match the existing tests' construction — read a sibling test first. `RunTaskResponse`'s init field names must match its definition — check `Services/RunTaskClient.swift`.)

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreRunTaskTests`
Expected: FAIL — `approveTask` undefined; `runTask` still appends to library / doesn't set draft. (Host may also crash on teardown — the assertion failures are the signal.)

- [ ] **Step 3: Replace `runTask`**

In `codepet/Managers/CompanyStore.swift`, replace the whole `runTask(_:language:)` function with:

```swift
    /// Run a codepetCanDo task → produce a Deliverable → stash it as the task's `draft`
    /// and mark the task `drafted` (moves it to "Awaiting approval"). Does NOT write the
    /// library — the deliverable is copied there only on approve. Dedupe: a task already
    /// drafted & awaiting approval is not re-run (mirrors web's "you already have a
    /// draft"), so repeat taps never duplicate work. Fail-open + account-guarded.
    func runTask(_ task: RoadmapTask, language: AppLanguage) async {
        guard !runningTaskIds.contains(task.id) else { return }
        if let i = company.tasks.firstIndex(where: { $0.id == task.id }),
           company.tasks[i].drafted, !company.tasks[i].done { return }   // already drafted → no regen
        runningTaskIds.insert(task.id)
        runError = nil
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        guard let deliverable = buildDeliverable(from: result, task: task) else {
            runError = language == .vi
                ? "Không tạo được \"\(task.title)\" — thử lại nhé."
                : "Couldn't generate \"\(task.title)\" — try again."
            return
        }
        guard let i = company.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        company.tasks[i].draft = deliverable
        company.tasks[i].drafted = true
        if let cid { _ = await tasksSaver(cid, company.tasks) }
    }

    /// Approve a task's draft: copy it into the library exactly once, mark the task done,
    /// and clear the draft/drafted state. Persists both tasks + library. Idempotent — a
    /// task with no pending draft, or already done, is a no-op (no duplicate library entry).
    func approveTask(id: String) async {
        guard let i = company.tasks.firstIndex(where: { $0.id == id }),
              let draft = company.tasks[i].draft, !company.tasks[i].done else { return }
        company.library.append(draft)
        company.tasks[i].done = true
        company.tasks[i].drafted = false
        company.tasks[i].draft = nil
        if let cid = companyId {
            _ = await librarySaver(cid, company.library)
            _ = await tasksSaver(cid, company.tasks)
        }
    }
```

- [ ] **Step 4: Run to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreRunTaskTests`
Expected: the four new tests' assertions pass. (Xcode 26.2: if the host crashes on teardown, confirm the assertions ran green + `xcodebuild build …` succeeds.)

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreRunTaskTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "fix: run stashes a task draft; approve moves it to the library once

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Approve affordance in the board + columns

**Files:**
- Modify: `codepet/Views/Overview/TaskCardView.swift`
- Modify: `codepet/Views/Tasks/TasksView.swift`

**Interfaces:**
- Consumes: `CompanyStore.approveTask(id:)` (Task 2); existing `RoadmapEngine.status`.

- [ ] **Step 1: Add an Approve button to `TaskCardView`**

In `codepet/Views/Overview/TaskCardView.swift`, immediately AFTER the `if status == .codepetCanDo { … }` Run-button block (ends ~line 62), add:

```swift
                if status == .needsApproval {
                    Button {
                        Task { await companyStore.approveTask(id: task.id) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: 9))
                            Text(lang == .vi ? "Duyệt" : "Approve")
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                    }
                    .buttonStyle(.plain)
                }
```

- [ ] **Step 2: Branch the Tasks-tab card tap on status**

In `codepet/Views/Tasks/TasksView.swift`, in the `card(_ t:)` builder, replace the button action:

```swift
        Button {
            if !t.done { Task { await companyStore.runTask(t, language: lang) } }
        } label: {
```

with a status branch (run when runnable, approve when awaiting):

```swift
        Button {
            let st = RoadmapEngine.status(for: t, in: companyStore.company.tasks)
            if st == .needsApproval { Task { await companyStore.approveTask(id: t.id) } }
            else if st == .codepetCanDo { Task { await companyStore.runTask(t, language: lang) } }
        } label: {
```

- [ ] **Step 3: Audit other run call sites (no silent gap)**

Run: `grep -rn "runTask(" codepet/Views`
Expected sites: `TaskCardView.swift`, `TasksView.swift`, and any Overview run entry. For each, confirm a `.needsApproval` task now has a reachable approve action (either this card's new button, or it routes through `TaskCardView`). If a run site has NO approve path for awaiting tasks, add the same Approve button pattern there. Note what you found in the commit body. (The store-level dedupe already prevents duplicate drafts regardless of call site — this step is about the approve affordance being reachable.)

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`. (SwiftUI view actions aren't unit-tested here; correctness of `approveTask`/`runTask` is covered by Task 2. This task is wiring + build-verify.)

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Overview/TaskCardView.swift codepet/Views/Tasks/TasksView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: add Approve affordance for awaiting tasks (board + columns)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Root-cause coverage:** task stuck in Up next → Task 2 sets `drafted` (→ Awaiting); duplicate library → Task 2 writes library only on approve + dedupes re-runs; Awaiting unreachable → Task 3 adds the approve affordance that produces `done`. ✓
**Placeholder scan:** every step shows full code. Test construction notes point to reading sibling tests for exact init shapes (real risk, not a placeholder). ✓
**Type consistency:** `draft: Deliverable?` defined in Task 1, consumed in Task 2 (`company.tasks[i].draft`) and persisted via existing `tasksSaver`. `approveTask(id:)` defined in Task 2, called in Task 3. `RoadmapEngine.status` unchanged. ✓
**Scope:** chat-side draft/approve untouched; `CompanyData` untouched (Codable round-trip); no `RoadmapEngine`/`TaskColumn` predicate change. ✓
