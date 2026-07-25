# Native Summary View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the web app's Summary "shipped digest" view to the native macOS SwiftUI app as a new tab, composed entirely client-side from the company's existing roadmap + library data.

**Architecture:** A pure, testable `SummaryData` struct aggregates `CompanyState` into the numbers/rows the view renders (hero counts, autopilot split, stat chips, recent wins). A read-only SwiftUI `SummaryView` renders those sections using `CodepetTheme`, and a small wiring change registers it as an `AppView` tab in the existing `AppShellView` shell. No Cloud Function, no store mutation.

**Tech Stack:** Swift, SwiftUI (macOS), XCTest, existing `CompanyStore`/`CompanyState`/`RoadmapEngine`/`DepartmentCatalog`/`CodepetTheme`.

## Global Constraints

- **Client-only.** No new Cloud Function, no `CompanyData`/network calls, no deploy. Everything is derived in-process from `companyStore.company`.
- **Read-only over company data.** Never mutate the store; `SummaryData` takes a `CompanyState` value and returns computed values only.
- **Theme exclusively.** Use `CodepetTheme` tokens (`primaryText`, `mutedText`, `accentTeal`, `accentGold`, `accentPurple`, `surface`), `CodepetCard`, and `.pixelSystem(size:weight:)`. No ad-hoc `Color(hex:)` or `Font.system`.
- **Graceful empty states.** No roadmap tasks -> hero shows "All clear", autopilot shows `100%`, chips show `0`; no library items -> "Nothing shipped yet" wins placeholder. No crashes, no force-unwraps.
- **Autopilot split uses the raw `who` field** (`.does` = Byte-handled; `.you`/`.draft` = needs-you), mirroring the web source of truth.
- **Recent-win department** is resolved via `sourceTaskId -> task.dept -> DepartmentCatalog`, falling back to the deliverable's `kind.label(lang)`.
- **Build verification per task:** `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` must print `BUILD SUCCEEDED`. SwiftUI views have no unit tests; only the pure `SummaryData` helper is XCTest-covered. Keep `SummaryData` a plain (non-`@MainActor`) struct to avoid the Xcode 26.2 `@MainActor` test crash.
- **Branch:** `feat/native-summary-view`, based on `origin/main`.
- **IMPORTANT — verify real signatures.** The code below was written from a read of the repo but the initializers/enums (`RoadmapTask(...)`, `CompanyState(...)`, `Deliverable(...)`, `CompanyBrief()`, `TaskWho`, `ProjectStage`, `DepartmentCatalog.find`, `Department.name`, `DeliverableKind.label`, `RoadmapEngine.progressPercent`) MUST be confirmed against the actual source before/while implementing. If a signature differs, adapt the call to the real one — do not invent APIs, do not change the model layer to fit this plan.

---

### Task 1: `SummaryData` pure aggregation helper

**Files:**
- Create: `codepet/Models/SummaryData.swift`
- Test: `codepetTests/SummaryDataTests.swift`

**Interfaces:**
- Consumes: `CompanyState` (`.tasks: [RoadmapTask]`, `.library: [Deliverable]`), `RoadmapTask.who: TaskWho`, `RoadmapTask.dept: String?`, `Deliverable.createdAt/sourceTaskId/kind`, `DepartmentCatalog.find(_:)`, `AppLanguage`.
- Produces: `struct SummaryWin { let id: String; let title: String; let meta: String }` and `struct SummaryData` with `byteHandled/needsYou/doneCount/totalCount/departmentCount/shippedCount/autopilotPct: Int`, `recentWins: [SummaryWin]`, `var isAllClear: Bool`, `init(company: CompanyState, language: AppLanguage)`. Consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/SummaryDataTests.swift`:

```swift
// codepetTests/SummaryDataTests.swift
import XCTest
@testable import codepet

final class SummaryDataTests: XCTestCase {
    private func company(tasks: [RoadmapTask] = [], library: [Deliverable] = []) -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: library,
                     stage: .idea, companionId: "byte", tasks: tasks)
    }

    func testEmptyCompanyIsAllClear() {
        let d = SummaryData(company: company(), language: .en)
        XCTAssertEqual(d.totalCount, 0)
        XCTAssertEqual(d.doneCount, 0)
        XCTAssertEqual(d.byteHandled, 0)
        XCTAssertEqual(d.needsYou, 0)
        XCTAssertEqual(d.autopilotPct, 100)   // idle -> "100% on autopilot"
        XCTAssertEqual(d.departmentCount, 0)
        XCTAssertEqual(d.shippedCount, 0)
        XCTAssertTrue(d.recentWins.isEmpty)
        XCTAssertTrue(d.isAllClear)
    }

    func testAutopilotSplitAndCounts() {
        let tasks = [
            RoadmapTask(id: "1", title: "A", detail: "", phase: .build, who: .does, dept: "eng"),
            RoadmapTask(id: "2", title: "B", detail: "", phase: .build, who: .does, dept: "eng"),
            RoadmapTask(id: "3", title: "C", detail: "", phase: .build, who: .does, dept: "design"),
            RoadmapTask(id: "4", title: "D", detail: "", phase: .find, who: .you, dept: "mkt"),
            RoadmapTask(id: "5", title: "E", detail: "", phase: .find, who: .does, done: true, dept: "eng"),
        ]
        let d = SummaryData(company: company(tasks: tasks), language: .en)
        XCTAssertEqual(d.totalCount, 5)
        XCTAssertEqual(d.doneCount, 1)
        XCTAssertEqual(d.byteHandled, 3)      // 3 open .does
        XCTAssertEqual(d.needsYou, 1)         // 1 open .you
        XCTAssertEqual(d.autopilotPct, 75)    // 3 / 4
        XCTAssertEqual(d.departmentCount, 3)  // eng, design, mkt
        XCTAssertFalse(d.isAllClear)
    }

    func testRecentWinsNewestFirstCappedAndMeta() {
        let tasks = [
            RoadmapTask(id: "t-eng", title: "T", detail: "", phase: .build, who: .does, dept: "eng"),
        ]
        let lib = [
            Deliverable(id: "d1", kind: .doc,   title: "Old",    body: "b", createdAt: "2026-01-01T00:00:00Z", sourceTaskId: "t-eng"),
            Deliverable(id: "d2", kind: .post,  title: "Mid",    body: "b", createdAt: "2026-02-01T00:00:00Z", sourceTaskId: nil),
            Deliverable(id: "d3", kind: .email, title: "New",    body: "b", createdAt: "2026-03-01T00:00:00Z", sourceTaskId: "missing"),
            Deliverable(id: "d4", kind: .plan,  title: "Newest", body: "b", createdAt: "2026-04-01T00:00:00Z", sourceTaskId: "t-eng"),
        ]
        let d = SummaryData(company: company(tasks: tasks, library: lib), language: .en)
        XCTAssertEqual(d.shippedCount, 4)
        XCTAssertEqual(d.recentWins.count, 3)                                  // capped at 3
        XCTAssertEqual(d.recentWins.map(\.title), ["Newest", "New", "Mid"])   // newest-first
        XCTAssertEqual(d.recentWins[0].meta, "Engineering")                    // resolved via source task dept
        XCTAssertEqual(d.recentWins[2].meta, DeliverableKind.post.label(.en))  // fallback to kind label
    }
}
```

Note: the exact `RoadmapTask`/`CompanyState`/`Deliverable`/`CompanyBrief` initializer argument labels and the `TaskWho`/`DepartmentCatalog`/`Department.name` names MUST be confirmed against the real source; if the memberwise labels differ, fix the test calls to match the real ones (the assertions/semantics stay the same). The `"Engineering"` expectation assumes `DepartmentCatalog.find("eng")?.name == "Engineering"` — confirm the real key/name and adjust the fixture key + expectation together if different.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/SummaryDataTests`
Expected: FAIL — compile error, `cannot find 'SummaryData' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/SummaryData.swift`:

```swift
// codepet/Models/SummaryData.swift
import Foundation

/// One "recent win" row on the Summary digest — a recently shipped (approved)
/// Library deliverable, with a resolved department/kind meta line.
struct SummaryWin: Identifiable, Hashable {
    let id: String     // the deliverable's id
    let title: String
    let meta: String   // owning department name, else the deliverable kind label
}

/// Pure, client-side aggregation of the company's delivered work + roadmap into
/// the numbers/rows the Summary view renders. No network, no mutation, no
/// @MainActor — value-in / value-out so it's trivially unit-testable. Mirrors the
/// web SummaryView's fallback (non-tracking) path.
struct SummaryData {
    let byteHandled: Int      // open tasks Codepet handles (who == .does)
    let needsYou: Int         // open tasks needing the founder (who == .you || .draft)
    let doneCount: Int        // tasks marked done
    let totalCount: Int       // all roadmap tasks
    let departmentCount: Int  // distinct departments with at least one task
    let shippedCount: Int     // approved Library deliverables
    let autopilotPct: Int     // byteHandled / (byteHandled + needsYou); 100 when idle
    let recentWins: [SummaryWin]  // 3 most-recent approved deliverables, newest-first

    /// True when Codepet has nothing open — drives the "All clear" hero copy.
    var isAllClear: Bool { byteHandled == 0 }

    init(company: CompanyState, language: AppLanguage) {
        let tasks = company.tasks
        self.totalCount = tasks.count
        self.doneCount = tasks.filter { $0.done }.count
        self.byteHandled = tasks.filter { !$0.done && $0.who == .does }.count
        self.needsYou = tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count
        let active = byteHandled + needsYou
        self.autopilotPct = active > 0
            ? Int((Double(byteHandled) / Double(active) * 100).rounded())
            : 100
        self.departmentCount = Set(tasks.compactMap { $0.dept }).count
        self.shippedCount = company.library.count

        // Newest-first (matches LibraryView), take 3. Native Deliverable has no
        // department, so resolve it from the source task; fall back to the kind
        // label when the task/dept can't be resolved.
        self.recentWins = company.library
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .prefix(3)
            .map { d in
                let task = d.sourceTaskId.flatMap { id in tasks.first { $0.id == id } }
                let deptName = task?.dept.flatMap { DepartmentCatalog.find($0)?.name }
                return SummaryWin(id: d.id, title: d.title,
                                  meta: deptName ?? d.kind.label(language))
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/SummaryDataTests`
Expected: PASS (3 tests). (If the hosted test run hits the known Xcode 26.2 @MainActor teardown crash, note it — but `SummaryData`/`SummaryWin` are plain structs with no @MainActor, so these tests must run and pass cleanly.)

- [ ] **Step 5: Build the whole app**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/SummaryData.swift codepetTests/SummaryDataTests.swift
git commit -m "feat: add SummaryData digest aggregation helper"
```

---

### Task 2: `SummaryView` SwiftUI sections

**Files:**
- Create: `codepet/Views/Summary/SummaryView.swift`

**Interfaces:**
- Consumes: `SummaryData(company:language:)` from Task 1; `@EnvironmentObject var companyStore: CompanyStore`; `@Environment(\.uiLanguage)`; `CodepetTheme`, `CodepetCard`.
- Produces: `struct SummaryView: View`. Rendered by Task 3.

Confirm the real names before writing: how `LibraryView` reads the store (`@EnvironmentObject var companyStore: CompanyStore` + `companyStore.company`), the language environment key (`@Environment(\.uiLanguage)`), and that `CodepetCard`, `CodepetTheme.accentTeal/accentGold/accentPurple/primaryText/mutedText`, and `.pixelSystem(size:weight:)` exist as used. Adapt to the real API where different.

- [ ] **Step 1: Create the view**

Create `codepet/Views/Summary/SummaryView.swift`:

```swift
// codepet/Views/Summary/SummaryView.swift
import SwiftUI

/// The Summary digest — a value-first recap of what Codepet has done for the
/// founder, composed CLIENT-SIDE from `company` (roadmap + library). Read-only:
/// never mutates the store. Mirrors the web SummaryView's fallback path (hero,
/// autopilot bar, stat chips, recent wins). Live Claude-Code session/commit
/// tracking is a separate subsystem and intentionally out of scope.
struct SummaryView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var data: SummaryData { SummaryData(company: companyStore.company, language: lang) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                autopilotBar
                statChips
                recentWins
            }
            .padding(18)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hero
    private var hero: some View {
        let d = data
        return CodepetCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(d.isAllClear
                     ? (lang == .vi ? "Mọi thứ ổn — Byte đang rảnh ✨"
                                    : "All clear — Byte has nothing on its plate right now ✨")
                     : (lang == .vi ? "Byte đang chạy \(d.byteHandled) việc cho bạn 🙌"
                                    : "Byte's on a roll — running \(d.byteHandled) \(d.byteHandled == 1 ? "task" : "tasks") for you 🙌"))
                    .font(.pixelSystem(size: 18, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi
                     ? "\(d.doneCount)/\(d.totalCount) việc · \(d.departmentCount) phòng ban"
                     : "\(d.doneCount)/\(d.totalCount) tasks moved · \(d.departmentCount) departments")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Autopilot bar
    private var autopilotBar: some View {
        let d = data
        let active = max(1, d.byteHandled + d.needsYou)
        let tealFrac = (d.byteHandled == 0 && d.needsYou == 0) ? 1.0 : Double(d.byteHandled) / Double(active)
        return CodepetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(d.autopilotPct)%")
                            .font(.pixelSystem(size: 22, weight: .bold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(lang == .vi ? "tự động" : "on autopilot")
                            .font(.pixelSystem(size: 11, weight: .medium))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        legendRow(color: CodepetTheme.accentTeal,
                                  text: lang == .vi ? "Byte lo \(d.byteHandled)" : "Byte handles \(d.byteHandled)")
                        legendRow(color: CodepetTheme.accentGold,
                                  text: lang == .vi ? "bạn tham gia \(d.needsYou)" : "you weigh in on \(d.needsYou)")
                    }
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(CodepetTheme.accentTeal)
                            .frame(width: geo.size.width * tealFrac)
                        Rectangle().fill(CodepetTheme.accentGold)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.pixelSystem(size: 11, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
        }
    }

    // MARK: Stat chips
    private var statChips: some View {
        let d = data
        return HStack(spacing: 10) {
            statChip(value: "\(d.departmentCount)", label: lang == .vi ? "phòng ban" : "departments")
            statChip(value: "\(d.doneCount)", emphasis: "/\(d.totalCount)", label: lang == .vi ? "việc xong" : "tasks done")
            statChip(value: "\(d.shippedCount)", label: lang == .vi ? "đã giao" : "shipped & saved")
        }
    }

    private func statChip(value: String, emphasis: String? = nil, label: String) -> some View {
        CodepetCard {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value).font(.pixelSystem(size: 20, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                    if let emphasis {
                        Text(emphasis).font(.pixelSystem(size: 12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                    }
                }
                Text(label).font(.pixelSystem(size: 10, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Recent wins
    private var recentWins: some View {
        let d = data
        return CodepetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(lang == .vi ? "Thành quả gần đây" : "Recent wins")
                        .font(.pixelSystem(size: 14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if d.shippedCount > 0 {
                        Text("\(d.shippedCount)")
                            .font(.pixelSystem(size: 10, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(CodepetTheme.accentGold))
                    }
                }
                if d.recentWins.isEmpty {
                    Text(lang == .vi
                         ? "Chưa có gì được giao — duyệt một bản nháp và thành quả sẽ xuất hiện ở đây."
                         : "Nothing shipped yet — approve a draft and your wins land here.")
                        .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    ForEach(d.recentWins) { w in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(CodepetTheme.accentTeal)
                            Text(w.title).font(.pixelSystem(size: 13, weight: .medium)).foregroundColor(CodepetTheme.primaryText)
                            Spacer()
                            Text(w.meta).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
Expected: `BUILD SUCCEEDED` (view compiles but is not yet reachable in the UI).

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Summary/SummaryView.swift
git commit -m "feat: add native SummaryView digest sections"
```

---

### Task 3: Wire Summary into the app shell navigation

**Files:**
- Modify: `codepet/Models/AppView.swift` (add `.summary` case + `title`/`icon` + `navTabs`)
- Modify: `codepet/Views/Shell/AppShellView.swift` (add `.summary` content branch)

**Interfaces:**
- Consumes: `SummaryView` (Task 2), existing `AppView` enum, `companyStore.view`.
- Produces: a reachable "Summary" top-bar tab that renders `SummaryView`.

Read `AppView.swift` and `AppShellView.swift` first and match their real structure (the enum case list, the `title`/`icon` switches, `navTabs`, and the content dispatch — whether if/else chain or switch). The snippets below are the intended shape; adapt to the real file.

- [ ] **Step 1: Add the enum case, title, icon, and nav tab**

In `codepet/Models/AppView.swift`, add `summary` to the case list, place it in `navTabs` (first, before `.overview`), and add its `title`/`icon` branches (both switches are exhaustive — a missing branch fails the build, which is the safety net):

```swift
enum AppView: String, CaseIterable, Identifiable {
    case overview, summary, company, roadmap, tasks, library, environment, settings, billing, support
    // ... keep the real existing cases; just add `summary`

    static let navTabs: [AppView] = [.summary, .overview, .company, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        // ... existing cases unchanged ...
        case .summary: return lang == .vi ? "Tóm tắt" : "Summary"
        }
    }

    var icon: String {
        switch self {
        // ... existing cases unchanged ...
        case .summary: return "sparkles"
        }
    }
}
```

- [ ] **Step 2: Render `SummaryView` from the shell**

In `codepet/Views/Shell/AppShellView.swift`, add a `.summary` branch to the `content` dispatch (before `.overview`):

```swift
    @ViewBuilder private var content: some View {
        if companyStore.view == .summary {
            SummaryView()
        } else if companyStore.view == .overview {
            OverviewView()
        }
        // ... rest of the chain unchanged ...
    }
```

Leave the rest of the chain unchanged. If a tab-count `switch` exists, confirm it has a `default` (no change needed) or add `.summary`. `CompanyStore.view` still defaults to `.overview` (unchanged landing).

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
Expected: `BUILD SUCCEEDED`. The exhaustive `title`/`icon` switches now cover `.summary`.

- [ ] **Step 4: Commit**

```bash
git add codepet/Models/AppView.swift codepet/Views/Shell/AppShellView.swift
git commit -m "feat: register Summary tab in the app shell"
```

---

### Task 4 (OPTIONAL STRETCH): "You are here" stage progress + achievements strip

Deferred; implement only if cheap and after Tasks 1–3 are green. Native has no per-stage node-progress subsystem (the web `NODES`/`stageProgress` model), so this maps to `company.stage: ProjectStage` plus overall `RoadmapEngine.progressPercent(company.tasks)`. Achievements are static playful copy, exactly as in web. Confirm `ProjectStage`'s cases, `.label`, `.order`, `allCases`, and `RoadmapEngine.progressPercent` signatures before writing; if any differ or don't exist, either adapt or SKIP this stretch (it is optional). Do NOT introduce a new flow-layout dependency — use a plain `HStack` if no wrapping helper exists (grep `FlowLayout|WrapHStack|FlowRow` in `codepet` first).

**Files:**
- Modify: `codepet/Views/Summary/SummaryView.swift` (append two sections to the `body` VStack)

Render a "You are here ->" card (stage label + `stage.order+1`/count + an `accentPurple` progress capsule at `RoadmapEngine.progressPercent(company.tasks)`), and an achievements strip of static momentum badges. Keep both read-only and theme-only. Commit:

```bash
git add codepet/Views/Summary/SummaryView.swift
git commit -m "feat: add stage progress + achievements to Summary (stretch)"
```

---

## Self-Review

- **Spec coverage:** Hero (Task 2 `hero`), autopilot bar (Task 2 `autopilotBar`, math in Task 1), stat chips (Task 2 `statChips`), recent wins (Task 1 `recentWins` + Task 2 `recentWins`), nav wiring (Task 3), stage/achievements stretch (Task 4). Live tracking is explicitly out of scope per Global Constraints.
- **Type consistency:** `SummaryData`/`SummaryWin` field names used identically in Tasks 1–2; `AppView.summary`, `navTabs`, `title`, `icon` consistent in Task 3; `companyStore`/`lang` names match `LibraryView`.
- **Empty states:** verified by `testEmptyCompanyIsAllClear` and the `recentWins.isEmpty` branch.
- **Adjudicated mapping choices** (controller): autopilot uses raw `who`; win department resolved via source task with kind-label fallback; department count = distinct dept keys in tasks; stage/achievements are the optional Task 4 stretch; level badge + live tracking dropped.
