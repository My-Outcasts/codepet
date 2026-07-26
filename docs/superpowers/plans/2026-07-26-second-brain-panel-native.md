# Second Brain Panel (Native) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Overview tab's "Second Brain — coming soon" placeholder with a real, read-only data panel (Status / Brain / Do-this-next / Topics) derived entirely client-side from `CompanyState`.

**Architecture:** A pure, non-@MainActor `SecondBrainData` struct aggregates the panel's numbers from `CompanyState` (mirroring the `RoadmapEngine` / `DepartmentCatalog` derivation pattern), unit-tested in isolation. A stateless `SecondBrainPanel` SwiftUI view renders that struct in the house style (`CodepetTheme` tokens, `.inter`/`.pixelSystem`, EN+VI). `OverviewView` builds the struct from `companyStore.company` and swaps it in where the placeholder text lived — no new tab, no new store, no network.

**Tech Stack:** Swift, SwiftUI, XCTest. Xcode 26.2, macOS target. Project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77) — new files under `codepet/` and `codepetTests/` are auto-included; NO project.pbxproj edits required.

## Global Constraints

- **Client-only.** No Cloud Function, no network, no new store. All data comes from `CompanyState` in `CompanyStore`.
- **No `LedgerEvent` model, no tracking subsystem.** Do not introduce either.
- **Read-only over company data.** The panel derives and displays; it never mutates `companyStore.company`.
- **Usage section OMITTED** (build sessions / commits / PRs / lines / hours-saved) — deferred, backed by tracking data native lacks. Never stub fake numbers.
- **Decisions & Milestones rows DROPPED** — no native decisions/facts model and no stage-history to count. Deferred.
- **Reuse the house style:** `CodepetTheme` tokens + `CodepetTheme.inter(_:weight:)` / `.pixelSystem`. Match `OverviewView`'s existing cards. **VERIFY every token exists** (`surface`, `hairline`, `primaryText`, `bodyText`, `mutedText`, and the accent token used — the plan uses `accentBlue`; if it does not exist, substitute the accent token OverviewView/CodepetTheme actually uses, e.g. `accentPurple`/`accentTeal`). Do NOT invent tokens or use ad-hoc `Color(hex:)`.
- **Mirror the pure-aggregation + non-@MainActor-test pattern** of `RoadmapEngine`/`DepartmentCatalog` + `DepartmentCatalogTests`. The aggregation test MUST be a plain `final class ...: XCTestCase` with NO `@MainActor` (Xcode 26.2 teardown bug).
- **EN + VI** everywhere via `lang == .vi ? "…" : "…"` using `@Environment(\.uiLanguage)`.
- **The panel REPLACES the placeholder** inside `OverviewView` (the `showSecondBrain` branch). Do NOT add a new tab.
- **Verify real signatures before writing** — `CompanyState` init, `RoadmapTask` init (esp. whether `dependsOn:` is a real param), `Department.key`/`.name`, `DepartmentCatalog.all`/`.find(_:)`, `PetCharacter.all`/`.name`, `RoadmapEngine.nextStep`. Adapt to reality; no invented APIs.
- **Branch:** `feat/second-brain-panel-native`, base `origin/main`.
- **Per-task build verify:** `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` must end in `** BUILD SUCCEEDED **`.

---

### Task 1: `SecondBrainData` pure aggregation struct + XCTest

**Files:**
- Create: `codepet/Models/SecondBrainData.swift`
- Test: `codepetTests/SecondBrainDataTests.swift`

**Interfaces:**
- Consumes: `CompanyState` (`library`, `tasks`, `companionId`), `RoadmapTask` (`done`, `dept`), `RoadmapEngine.nextStep(_:)`, `DepartmentCatalog.all` / `.find(_:)`, `PetCharacter.all`, `Department`.
- Produces: `SecondBrainData(company: CompanyState)`; `deliverables/tasksTotal/tasksDone: Int`, `topics: [Topic]`, `nextTask: RoadmapTask?`, `nextDeptName: String?`, `companionName: String`; static `modelLabel: String`; nested `Topic { department: Department; count: Int; id: String }`.

- [ ] **Step 1: Write the failing test** — `codepetTests/SecondBrainDataTests.swift` (confirm the real `RoadmapTask`/`CompanyState`/`Deliverable` inits and `TaskWho`/`RoadmapPhase` cases first; adapt the fixture calls if labels differ):

```swift
import XCTest
@testable import codepet

// NON-@MainActor by design (Xcode 26.2 bug): SecondBrainData is a pure struct.
final class SecondBrainDataTests: XCTestCase {

    private func task(_ id: String, dept: String?, who: TaskWho = .does,
                      done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, done: done, dept: dept)
    }

    private func company(tasks: [RoadmapTask] = [], library: [Deliverable] = [],
                         companionId: String = "byte") -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: library,
                     stage: .idea, companionId: companionId, tasks: tasks)
    }

    func testCountsAndTopics() {
        let tasks = [
            task("a", dept: "eng", who: .you),
            task("b", dept: "eng", who: .does, done: true),
            task("c", dept: "mkt", who: .does),
            task("d", dept: nil,   who: .does),   // untagged → excluded from topics
        ]
        let lib = [Deliverable(kind: .doc, title: "X", body: "")]
        let data = SecondBrainData(company: company(tasks: tasks, library: lib))
        XCTAssertEqual(data.deliverables, 1)
        XCTAssertEqual(data.tasksTotal, 4)
        XCTAssertEqual(data.tasksDone, 1)
        XCTAssertEqual(data.topics.map(\.department.key), ["eng", "mkt"]) // desc by count
        XCTAssertEqual(data.topics.first?.count, 2)
    }

    func testNextStepAndDeptName() {
        let data = SecondBrainData(company: company(tasks: [task("a", dept: "design")]))
        XCTAssertEqual(data.nextTask?.id, "a")
        XCTAssertEqual(data.nextDeptName, "Design")
    }

    func testCompanionNameResolves() {
        XCTAssertEqual(SecondBrainData(company: company(companionId: "byte")).companionName,
                       PetCharacter.all["byte"]?.name ?? "Codepet")
        XCTAssertEqual(SecondBrainData(company: company(companionId: "nope")).companionName,
                       "Codepet")
    }

    func testEmptyCompanyIsCalm() {
        let data = SecondBrainData(company: company())
        XCTAssertEqual(data.deliverables, 0)
        XCTAssertEqual(data.tasksTotal, 0)
        XCTAssertTrue(data.topics.isEmpty)
        XCTAssertNil(data.nextTask)
        XCTAssertNil(data.nextDeptName)
    }
}
```

(If `DepartmentCatalog.find("eng")?.name` / `"design"` don't return `"Engineering"`/`"Design"`, adjust the fixture keys + expectations together to real catalog values.)

- [ ] **Step 2: Run to verify it fails** — `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` → FAIL, `cannot find 'SecondBrainData' in scope`.

- [ ] **Step 3: Write the implementation** — `codepet/Models/SecondBrainData.swift`:

```swift
// codepet/Models/SecondBrainData.swift
import Foundation

/// Pure, view-agnostic aggregation for the Overview "Second Brain" panel — derives the
/// panel's numbers straight from CompanyState. No network, no mutation, NOT @MainActor:
/// mirrors the RoadmapEngine / DepartmentCatalog pure-derivation pattern.
///
/// The web panel's Usage section (sessions/commits/PRs/hours-saved) and its
/// Decisions/Milestones rows are intentionally omitted — native has no LedgerEvent or
/// tracking subsystem to back them, and this struct never fabricates counts.
struct SecondBrainData {

    /// One department's topic tally (native analogue of the web `topicCounts` row).
    struct Topic: Identifiable, Equatable {
        let department: Department
        let count: Int
        var id: String { department.key }
    }

    let deliverables: Int        // company.library.count
    let tasksTotal: Int          // company.tasks.count
    let tasksDone: Int           // done tasks
    let topics: [Topic]          // per-dept task counts, count>0, desc then catalog order
    let nextTask: RoadmapTask?   // RoadmapEngine.nextStep
    let nextDeptName: String?    // department name for nextTask.dept
    let companionName: String    // companionId → PetCharacter name

    /// The active model label, matching the web panel's static MODEL_LABEL. A constant,
    /// not a tracked value.
    static let modelLabel = "claude-opus-4-8"

    init(company: CompanyState) {
        self.deliverables = company.library.count
        self.tasksTotal = company.tasks.count
        self.tasksDone = company.tasks.filter { $0.done }.count

        // Per-department task counts (native analogue of web topicCounts): tally the
        // dept-tagged tasks, drop empties, sort by count desc then catalog order.
        var byKey: [String: Int] = [:]
        for t in company.tasks { if let k = t.dept { byKey[k, default: 0] += 1 } }
        self.topics = DepartmentCatalog.all.enumerated()
            .compactMap { idx, dep -> (Int, Topic)? in
                let n = byKey[dep.key] ?? 0
                return n > 0 ? (idx, Topic(department: dep, count: n)) : nil
            }
            .sorted { $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0 }
            .map(\.1)

        let next = RoadmapEngine.nextStep(company.tasks)
        self.nextTask = next
        self.nextDeptName = DepartmentCatalog.find(next?.dept)?.name
        self.companionName = PetCharacter.all[company.companionId]?.name ?? "Codepet"
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `xcodebuild test ... -only-testing:codepetTests/SecondBrainDataTests CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/SecondBrainData.swift codepetTests/SecondBrainDataTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: SecondBrainData pure aggregation for Overview panel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `SecondBrainPanel` SwiftUI view

**Files:**
- Create: `codepet/Views/Overview/SecondBrainPanel.swift`

**Interfaces:**
- Consumes: `SecondBrainData` (Task 1), `SecondBrainData.Topic`, `AppLanguage`, `CodepetTheme` tokens, `Department.name`.
- Produces: `SecondBrainPanel(data: SecondBrainData, lang: AppLanguage)` — a stateless `View`.

Read `codepet/Views/CodepetTheme.swift` + `codepet/Views/Overview/OverviewView.swift` FIRST and confirm every token used below exists (`surface`, `hairline`, `primaryText`, `bodyText`, `mutedText`, and the accent — plan uses `accentBlue`; substitute the real accent if absent) and the `CodepetTheme.inter(_:weight:)` signature. Adapt any mismatch; do not invent tokens.

- [ ] **Step 1: Write the view** — `codepet/Views/Overview/SecondBrainPanel.swift`:

```swift
// codepet/Views/Overview/SecondBrainPanel.swift
import SwiftUI

/// The Overview "Second Brain" info rail — a read-only panel of real Codepet data
/// (deliverables/tasks counts, active model + companion, the next move, per-department
/// topic counts), ported from the web SecondBrainPanel and fed by the pure SecondBrainData
/// aggregation. The web Usage section and the Decisions/Milestones rows are omitted:
/// native has no tracking/LedgerEvent, decisions, or stage-history to back them.
struct SecondBrainPanel: View {
    let data: SecondBrainData
    let lang: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                brainSection
                nextSection
                topicsSection
            }
            .padding(16)
            .frame(maxWidth: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
        }
    }

    private var statusSection: some View {
        section(lang == .vi ? "Trạng thái" : "Status") {
            row(lang == .vi ? "Sản phẩm" : "Deliverables", "\(data.deliverables)")
            row(lang == .vi ? "Việc đã xong" : "Tasks done", "\(data.tasksDone)")
            row(lang == .vi ? "Tổng số việc" : "Total tasks", "\(data.tasksTotal)")
        }
    }

    private var brainSection: some View {
        section(lang == .vi ? "Bộ não" : "Brain") {
            row(lang == .vi ? "Mô hình" : "Model", SecondBrainData.modelLabel)
            row(lang == .vi ? "Bạn đồng hành" : "Companion", data.companionName)
        }
    }

    private var nextSection: some View {
        section(lang == .vi ? "Làm điều này tiếp" : "Do this next") {
            if let t = data.nextTask {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let dept = data.nextDeptName {
                        Text(dept)
                            .font(CodepetTheme.inter(11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(CodepetTheme.accentBlue.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CodepetTheme.accentBlue.opacity(0.3), lineWidth: 1))
            } else {
                Text(lang == .vi ? "Bạn đã theo kịp mọi thứ." : "You're all caught up.")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            }
        }
    }

    private var topicsSection: some View {
        section(lang == .vi ? "Chủ đề" : "Topics") {
            if data.topics.isEmpty {
                Text(lang == .vi ? "Chưa có gì." : "Nothing yet.")
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            } else {
                ForEach(data.topics) { t in
                    HStack {
                        Text(t.department.name)
                            .font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.bodyText)
                        Spacer()
                        Text("\(t.count)")
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentBlue)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.surface))
                }
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(CodepetTheme.inter(10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(CodepetTheme.mutedText)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.bodyText)
            Spacer()
            Text(v).font(CodepetTheme.inter(12.5, weight: .semibold))
                .foregroundColor(CodepetTheme.accentBlue)
        }
        .padding(.vertical, 3)
    }
}
```

- [ ] **Step 2: Build** — `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Overview/SecondBrainPanel.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: SecondBrainPanel view (Status/Brain/Do-next/Topics)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire `SecondBrainPanel` into `OverviewView`

**Files:**
- Modify: `codepet/Views/Overview/OverviewView.swift`

**Interfaces:** consumes `SecondBrainData(company:)` (T1), `SecondBrainPanel(data:lang:)` (T2), existing `companyStore.company`, `lang`.

Read the real `OverviewView.body` first — find the `if showSecondBrain { … "coming soon" … }` branch and confirm the exact surrounding structure before replacing.

- [ ] **Step 1: Replace the placeholder branch** — swap the `showSecondBrain` branch's "coming soon" content for:

```swift
            if showSecondBrain {
                SecondBrainPanel(data: SecondBrainData(company: companyStore.company), lang: lang)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 24).padding(.top, 14)
            } else {
```

Leave the `else` branch (RoadmapMapView etc.) and everything else unchanged. Adapt to the real branch shape (the exact modifiers may differ — keep the layout coherent with the surrounding view).

- [ ] **Step 2: Build** — `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Full test run (no regressions)** — `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **` (or, if the hosted @MainActor suites hit the known Xcode 26.2 teardown crash, confirm the struct-only suites incl. `SecondBrainDataTests` are green and the build succeeds).

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Overview/OverviewView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: show SecondBrainPanel in Overview, replacing coming-soon placeholder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- **Coverage:** Status (deliverables/done/total), Brain (model+companion), Do-next (nextStep+dept), Topics (per-dept counts) — all real `CompanyState` data. Usage/Decisions/Milestones deferred (no native data), no fake numbers.
- **Pattern reuse:** `SecondBrainData` mirrors `RoadmapEngine`/`DepartmentCatalog` pure-derivation; tested non-@MainActor like `DepartmentCatalogTests`.
- **Read-only / client-only / theme-only** enforced in Global Constraints.
- **Replaces placeholder in existing Overview surface** — no new tab.
- **Verify-before-write** flagged for theme tokens (`accentBlue`/`bodyText`), `RoadmapTask` init, and catalog names.
