# Phase 3A — Roadmap Data + Engine + Generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native roadmap data model, a pure engine (status / next-step / progress), and fail-open generation, per company — the data the Overview board (Phase 3B) will render.

**Architecture:** `RoadmapPhase`/`TaskWho`/`RoadmapTask`/`TaskStatus` model the phase-column board. A pure `RoadmapEngine` derives per-task status, the next-step beacon, and progress. `CompanyState.tasks` persists via `CompanyData` (JSON-safe, like the brief). `CompanyStore` generates the roadmap through an injectable fail-open `roadmapFetcher` (the `scaffoldRoadmap` function alignment + node-22 deploy is the follow-through), token-guarded like Phase 2.

**Tech Stack:** Swift (macOS 13+), Firebase Firestore. Reuses `CompanyBrief`, `AppLanguage`, `CompanyState`/`CompanyData`/`CompanyStore` (P1/P2). Spec: `docs/superpowers/specs/2026-07-20-phase3a-roadmap-data-design.md`.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; test module **`@testable import codepet`**. **Run all `xcodebuild` in the FOREGROUND.** Test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`. SourceKit cross-file diagnostics are FALSE POSITIVES — trust xcodebuild. `git diff`/`status`/commit HANG on this iCloud worktree — `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then retry; use `ls`/`grep` not `git status`.
- **`RoadmapTask` fields are JSON-safe** (strings/enums-as-string/bools/arrays) — so `CompanyDoc.tasks: [RoadmapTask]?` decodes via the existing `JSONSerialization` load path; `onboardedAt` stays the only Date, kept as ISO string.
- **Generation fail-open:** `roadmapFetcher` returns `[]` on failure/undeployed; `generateRoadmap` treats `[]` as "no change". Persistence fail-soft. Token-guard (`hydrationToken`) so an account switch mid-fetch discards.
- **Status precedence (exact):** `done` → `needsApproval` (`drafted && !done`) → `blocked` (any `dependsOn` id maps to a not-done task) → `needsYou` (`who == .you`) → `codepetCanDo`.
- Do NOT touch Giang's files or `CLAUDE.md`. Staged retirement continues (SP3's `RoadmapTask` etc. are on later `main`, NOT this branch — this phase defines fresh types; no conflict).

---

## File Structure
- Create `codepet/Models/RoadmapTask.swift` (Task 1: RoadmapPhase, TaskWho, RoadmapTask, TaskStatus)
- Create `codepet/Models/RoadmapEngine.swift` (Task 2)
- Modify `codepet/Models/CompanyState.swift` + `codepet/Services/CompanyData.swift` (Task 3)
- Modify `codepet/Managers/CompanyStore.swift` (Task 4)
- Tests under `codepetTests/`

---

### Task 1: Roadmap models

**Files:**
- Create: `codepet/Models/RoadmapTask.swift`
- Test: `codepetTests/RoadmapTaskModelTests.swift`

**Interfaces:**
- Produces: `enum RoadmapPhase` (find/foundation/build/ship/launch, `order`, `label(_:)`); `enum TaskWho { does, draft, you }`; `struct RoadmapTask` (id/title/detail/phase/who/dependsOn/done/drafted); `enum TaskStatus { done, needsApproval, blocked, needsYou, codepetCanDo }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapTaskModelTests.swift
import XCTest
@testable import codepet

final class RoadmapTaskModelTests: XCTestCase {
    func testPhaseOrderAndLabels() {
        XCTAssertEqual(RoadmapPhase.allCases.map(\.rawValue),
                       ["find", "foundation", "build", "ship", "launch"])
        XCTAssertEqual(RoadmapPhase.find.order, 0)
        XCTAssertEqual(RoadmapPhase.launch.order, 4)
        for p in RoadmapPhase.allCases {
            XCTAssertFalse(p.label(.en).isEmpty); XCTAssertFalse(p.label(.vi).isEmpty)
        }
    }
    func testTaskRoundTripsCodableWithDefaults() throws {
        let t = RoadmapTask(id: "t1", title: "Ship auth", detail: "wire sign-in", phase: .build, who: .does)
        XCTAssertEqual(t.dependsOn, []); XCTAssertFalse(t.done); XCTAssertFalse(t.drafted)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapTaskModelTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'RoadmapPhase'/'RoadmapTask' in scope`.

- [ ] **Step 3: Write the models**

```swift
// codepet/Models/RoadmapTask.swift
import Foundation

/// The roadmap board's columns, in order. Mirrors the web Overview board
/// (Find → Foundation → Build → Ship → Launch).
enum RoadmapPhase: String, Codable, CaseIterable, Identifiable {
    case find, foundation, build, ship, launch
    var id: String { rawValue }
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .find:       return lang == .vi ? "Tìm hiểu" : "Find"
        case .foundation: return lang == .vi ? "Nền tảng" : "Foundation"
        case .build:      return lang == .vi ? "Xây dựng" : "Build"
        case .ship:       return lang == .vi ? "Phát hành" : "Ship"
        case .launch:     return lang == .vi ? "Ra mắt" : "Launch"
        }
    }
}

/// Who acts on a task — mirrors the web `Who`: companion does it / drafts it /
/// the founder must.
enum TaskWho: String, Codable, Hashable { case does, draft, you }

/// One roadmap task under a phase. Fields are JSON-safe so it persists via the
/// companies/{uid} JSONSerialization path.
struct RoadmapTask: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var phase: RoadmapPhase
    var who: TaskWho
    var dependsOn: [String]
    var done: Bool
    var drafted: Bool

    init(id: String, title: String, detail: String, phase: RoadmapPhase, who: TaskWho,
         dependsOn: [String] = [], done: Bool = false, drafted: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.phase = phase
        self.who = who; self.dependsOn = dependsOn; self.done = done; self.drafted = drafted
    }
}

/// Derived per-task status (the board legend) — computed by RoadmapEngine, not stored.
enum TaskStatus { case done, needsApproval, blocked, needsYou, codepetCanDo }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/RoadmapTask.swift codepetTests/RoadmapTaskModelTests.swift
git commit -m "feat(roadmap): RoadmapPhase/TaskWho/RoadmapTask/TaskStatus models"
```

---

### Task 2: `RoadmapEngine` (pure)

**Files:**
- Create: `codepet/Models/RoadmapEngine.swift`
- Test: `codepetTests/RoadmapEngineTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`/`RoadmapPhase`/`TaskStatus`/`TaskWho` (Task 1).
- Produces: `enum RoadmapEngine { static func status(for:in:); static func nextStep(_:); static func progressPercent(_:); static func tasksByPhase(_:) }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapEngineTests.swift
import XCTest
@testable import codepet

final class RoadmapEngineTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who, dependsOn: deps, done: done, drafted: drafted)
    }

    func testStatusPrecedence() {
        let a = t("a", .build, done: true)
        let b = t("b", .build, drafted: true)                 // needsApproval
        let c = t("c", .build, deps: ["z"])                   // z not-done → blocked
        let z = t("z", .find)                                 // z is not done
        let y = t("y", .build, who: .you)                     // needsYou
        let d = t("d", .build, who: .does)                    // codepetCanDo
        let all = [a, b, c, z, y, d]
        XCTAssertEqual(RoadmapEngine.status(for: a, in: all), .done)
        XCTAssertEqual(RoadmapEngine.status(for: b, in: all), .needsApproval)
        XCTAssertEqual(RoadmapEngine.status(for: c, in: all), .blocked)
        XCTAssertEqual(RoadmapEngine.status(for: y, in: all), .needsYou)
        XCTAssertEqual(RoadmapEngine.status(for: d, in: all), .codepetCanDo)
    }

    func testNextStepPicksFirstUnblockedByPhaseOrder() {
        // build-phase task is ready; a ship-phase task is also ready but later phase.
        let all = [t("s", .ship), t("f", .find, done: true), t("b", .build, deps: ["f"])]
        XCTAssertEqual(RoadmapEngine.nextStep(all)?.id, "b")   // build(1) before ship(3)
    }
    func testNextStepNilWhenAllDoneOrBlocked() {
        XCTAssertNil(RoadmapEngine.nextStep([]))
        XCTAssertNil(RoadmapEngine.nextStep([t("a", .build, done: true)]))
        XCTAssertNil(RoadmapEngine.nextStep([t("a", .build, deps: ["z"]), t("z", .find)]))  // blocked
    }
    func testProgressAndGrouping() {
        let all = [t("a", .find, done: true), t("b", .build), t("c", .build, done: true)]
        XCTAssertEqual(RoadmapEngine.progressPercent(all), 67)
        XCTAssertEqual(RoadmapEngine.progressPercent([]), 0)
        XCTAssertEqual(RoadmapEngine.tasksByPhase(all)[.build]?.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapEngineTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'RoadmapEngine' in scope`.

- [ ] **Step 3: Write the engine**

```swift
// codepet/Models/RoadmapEngine.swift
import Foundation

/// Pure derivations over a company's roadmap tasks — status, the next-step
/// beacon, progress, and phase grouping. No network, no mutation.
enum RoadmapEngine {
    private static func byId(_ tasks: [RoadmapTask]) -> [String: RoadmapTask] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A task's dependencies are all satisfied (a missing dep id is treated as satisfied).
    private static func depsSatisfied(_ task: RoadmapTask, _ index: [String: RoadmapTask]) -> Bool {
        !task.dependsOn.contains { index[$0]?.done == false }
    }

    /// Legend status. Precedence: done → needsApproval → blocked → needsYou → codepetCanDo.
    static func status(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskStatus {
        if task.done { return .done }
        if task.drafted { return .needsApproval }
        if !depsSatisfied(task, byId(tasks)) { return .blocked }
        return task.who == .you ? .needsYou : .codepetCanDo
    }

    /// The beacon: the first not-done, dependency-satisfied task by phase order then position.
    static func nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask? {
        let index = byId(tasks)
        return tasks.enumerated()
            .filter { !$0.element.done && depsSatisfied($0.element, index) }
            .min(by: { a, b in
                a.element.phase.order != b.element.phase.order
                    ? a.element.phase.order < b.element.phase.order
                    : a.offset < b.offset
            })?.element
    }

    static func progressPercent(_ tasks: [RoadmapTask]) -> Int {
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter { $0.done }.count
        return Int((Double(done) / Double(tasks.count) * 100).rounded())
    }

    static func tasksByPhase(_ tasks: [RoadmapTask]) -> [RoadmapPhase: [RoadmapTask]] {
        Dictionary(grouping: tasks, by: { $0.phase })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift
git commit -m "feat(roadmap): pure RoadmapEngine (status/next-step/progress/group)"
```

---

### Task 3: `CompanyState.tasks` + `CompanyData` persistence

**Files:**
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataTasksTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask` (Task 1).
- Produces: `CompanyState.tasks: [RoadmapTask]`; `CompanyDoc.tasks: [RoadmapTask]?`; `CompanyData.tasksPayload(_:) -> [String: Any]`; `CompanyData.saveTasks(companyId:tasks:) async -> Bool`; `CompanyData.fetchRoadmap(brief:) async -> [RoadmapTask]` (fail-open `[]`); `state(from:)` maps `tasks`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyDataTasksTests.swift
import XCTest
@testable import codepet

final class CompanyDataTasksTests: XCTestCase {
    func testStateMapsTasks() {
        let task = RoadmapTask(id: "t1", title: "Ship", detail: "d", phase: .build, who: .does)
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(), stage: nil,
                                                   companionId: nil, onboardedAt: nil, tasks: [task]))
        XCTAssertEqual(s.tasks.map(\.id), ["t1"])
        XCTAssertEqual(CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil, onboardedAt: nil, tasks: nil)).tasks, [])
    }
    func testTasksPayloadShape() {
        let payload = CompanyData.tasksPayload([RoadmapTask(id: "t1", title: "Ship", detail: "d", phase: .build, who: .does)])
        let arr = payload["tasks"] as? [[String: Any]]
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["id"] as? String, "t1")
        XCTAssertEqual(arr?.first?["phase"] as? String, "build")
    }
    func testFetchRoadmapFailsOpenEmpty() async {
        let out = await CompanyData.fetchRoadmap(brief: CompanyBrief(projectName: "X"))
        XCTAssertEqual(out, [])   // undeployed placeholder → fail-open empty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataTasksTests 2>&1 | tail -25`
Expected: FAIL — extra `tasks:` arg / no `tasksPayload`/`saveTasks`/`fetchRoadmap`.

- [ ] **Step 3: Add `tasks` to the models**

In `codepet/Models/CompanyState.swift`, add to `CompanyState` (after `var onboardedAt: Date?`):

```swift
    var tasks: [RoadmapTask]
```

Update `.empty`:

```swift
    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea,
        companionId: "byte", onboardedAt: nil, tasks: [])
```

- [ ] **Step 4: Extend `CompanyData`**

In `codepet/Services/CompanyData.swift`:

1. Add to `CompanyDoc` (after `onboardedAt`):

```swift
    var tasks: [RoadmapTask]?
```

2. In `state(from:)`, map tasks into the returned `CompanyState` (add the field):

```swift
            onboardedAt: doc.onboardedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            tasks: doc.tasks ?? []
```

3. Add the payload builder, the write, and the fail-open fetcher (inside `enum CompanyData`):

```swift
    /// Pure Firestore payload for a tasks write — testable without Firestore.
    static func tasksPayload(_ tasks: [RoadmapTask]) -> [String: Any] {
        if let data = try? JSONEncoder().encode(tasks),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["tasks": arr]
        }
        return ["tasks": []]
    }

    /// Write companies/{uid}.tasks, merge. Fail-soft: false on error.
    static func saveTasks(companyId: String, tasks: [RoadmapTask]) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(tasksPayload(tasks), merge: true)
            return true
        } catch {
            return false
        }
    }

    /// Fetch the generated roadmap for a company. FAIL-OPEN placeholder: returns `[]`
    /// until the `scaffoldRoadmap` Cloud Function is aligned to the RoadmapTask shape
    /// (phase/dependencies) and deployed (needs node 22). `generateRoadmap` treats `[]`
    /// as "no change", so the board stays empty rather than clearing existing tasks.
    static func fetchRoadmap(brief: CompanyBrief) async -> [RoadmapTask] {
        []
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepetTests/CompanyDataTasksTests.swift
git commit -m "feat(roadmap): CompanyState.tasks + CompanyData saveTasks/fetchRoadmap (fail-open)"
```

---

### Task 4: `CompanyStore` generation + toggle

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreRoadmapTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `CompanyData.fetchRoadmap`/`saveTasks` (Tasks 1/3).
- Produces: injectable `roadmapFetcher: (CompanyBrief) async -> [RoadmapTask]` + `tasksSaver: (String, [RoadmapTask]) async -> Bool` on `init`; `func generateRoadmap() async` (token-guarded, fail-open); `func toggleTaskDone(id:) async`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreRoadmapTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRoadmapTests: XCTestCase {
    private func task(_ id: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .build, who: .does, done: done)
    }

    func testGeneratePersistsFetchedTasks() async {
        var saved: [RoadmapTask] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             roadmapFetcher: { _ in [self.task("t1")] },
                             tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["t1"])
        XCTAssertEqual(saved.map(\.id), ["t1"])
    }
    func testGenerateFailOpenKeepsExisting() async {
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("keep")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _ in [] }, tasksSaver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["keep"])   // empty fetch → no change
    }
    func testToggleTaskDoneFlipsAndPersists() async {
        var saved: [RoadmapTask] = []
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("t1")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _ in [] }, tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.toggleTaskDone(id: "t1")
        XCTAssertTrue(s.company.tasks[0].done)
        XCTAssertTrue(saved.first?.done ?? false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreRoadmapTests 2>&1 | tail -25`
Expected: FAIL — no `roadmapFetcher`/`tasksSaver` init params, no `generateRoadmap`/`toggleTaskDone`.

- [ ] **Step 3: Extend `CompanyStore`**

Add the stored dependencies (near `loader`/`saver`):

```swift
    private let roadmapFetcher: (CompanyBrief) async -> [RoadmapTask]
    private let tasksSaver: (String, [RoadmapTask]) async -> Bool
```

Extend `init` (keep the existing `loader`/`saver` defaults):

```swift
    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief,
         roadmapFetcher: @escaping (CompanyBrief) async -> [RoadmapTask] = CompanyData.fetchRoadmap,
         tasksSaver: @escaping (String, [RoadmapTask]) async -> Bool = CompanyData.saveTasks) {
        self.loader = loader
        self.saver = saver
        self.roadmapFetcher = roadmapFetcher
        self.tasksSaver = tasksSaver
    }
```

Add generation + toggle (inside the class):

```swift
    /// Generate the roadmap (fail-open). Token-guarded: an account switch during the
    /// fetch discards. An empty result is "no change" (keeps existing tasks).
    func generateRoadmap() async {
        let token = hydrationToken
        let fetched = await roadmapFetcher(company.brief)
        guard token == hydrationToken, !fetched.isEmpty else { return }
        company.tasks = fetched
        if let cid = companyId { _ = await tasksSaver(cid, fetched) }
    }

    /// Flip a task's done state and persist (fail-soft).
    func toggleTaskDone(id: String) async {
        guard let i = company.tasks.firstIndex(where: { $0.id == id }) else { return }
        company.tasks[i].done.toggle()
        if let cid = companyId { _ = await tasksSaver(cid, company.tasks) }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests). (Existing `CompanyStore` tests use the defaulted `init`, so they keep compiling.)

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreRoadmapTests.swift
git commit -m "feat(roadmap): CompanyStore generateRoadmap (fail-open, token-guarded) + toggleTaskDone"
```

---

## Final verification

Run the Phase-3A suite (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapTaskModelTests -only-testing:codepetTests/RoadmapEngineTests -only-testing:codepetTests/CompanyDataTasksTests -only-testing:codepetTests/CompanyStoreRoadmapTests 2>&1 | tail -20` — all pass. (No app-target UI change this phase; the models compile into the target.)

---

## Self-Review

**Spec coverage:** models RoadmapPhase/TaskWho/RoadmapTask/TaskStatus (Task 1 ✓), pure engine status/next-step/progress/group (Task 2 ✓), CompanyState.tasks + CompanyDoc.tasks + saveTasks/fetchRoadmap + state mapping (Task 3 ✓), CompanyStore generateRoadmap(token-guarded, fail-open) + toggleTaskDone + injectable fetcher/saver (Task 4 ✓). Status precedence exact ✓; fail-open generation ✓; JSON-safe persistence ✓.

**Type consistency:** `RoadmapTask`/`RoadmapPhase`/`TaskWho`/`TaskStatus` defined Task 1, consumed Tasks 2/3/4. `CompanyState.tasks`/`CompanyDoc.tasks` Task 3, consumed Task 4. `roadmapFetcher: (CompanyBrief) async -> [RoadmapTask]` = `CompanyData.fetchRoadmap`; `tasksSaver: (String, [RoadmapTask]) async -> Bool` = `CompanyData.saveTasks` — signatures match init defaults. `.empty` gains `tasks: []` consistently (Task 3), used by Task 4's loaders.

**Known verification gaps for the implementer (resolve inline):** (a) the existing `CompanyStoreOnboardingTests`/`CompanyOnboardingModelTests` construct `CompanyStore(loader:saver:)` — the new `init` params are defaulted, so those keep compiling unchanged; confirm at build. (b) `CompanyState`'s memberwise init is used in several tests with positional/labeled args — adding `tasks` last with no default means those call sites must pass `tasks: []`; update any that break (the loaders in Task 4 already do). (c) `does` is a valid Swift enum case name (not a keyword) — no backticks needed.
