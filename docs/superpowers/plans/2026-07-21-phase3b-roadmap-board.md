# Phase 3B — Overview Roadmap Board — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native SwiftUI Overview roadmap board that renders the Phase-3A `RoadmapEngine` — five phase columns of status-colored task cards, a "DO THIS NEXT" beacon, and a Project Progress card — reading `CompanyStore.company.tasks`, styled in CodepetTheme, VI/EN.

**Architecture:** All roadmap logic stays in the pure Phase-3A engine; the SwiftUI layer only renders it and forwards a done-toggle. Task 1 adds the last three pure, unit-tested helpers (`orderedColumns`, `TaskStatus.label`, `TaskWho.label`). Tasks 2–4 build the view tree (leaf cards → columns → header → board + shell wiring); those are verified by a successful build (no logic lives in them, so no unit tests).

**Tech Stack:** SwiftUI (macOS 13+). Reuses `RoadmapEngine`/`RoadmapTask`/`TaskStatus`/`TaskWho`/`RoadmapPhase` (3A), `CompanyStore` (generateRoadmap/toggleTaskDone), CodepetTheme (`CodepetCard`, `.pixelSystem`, accent tokens), `@Environment(\.uiLanguage)`. Spec: `docs/superpowers/specs/2026-07-21-phase3b-roadmap-board-design.md`.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; test module **`@testable import codepet`**. **Run all `xcodebuild` in the FOREGROUND.** Unit test (Task 1): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapBoardHelpersTests 2>&1 | tail -20`. Build (Tasks 2–4): `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` (expect `** BUILD SUCCEEDED **`). SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from a file; retry once on timeout — the commit often lands on the retry). Use `ls`/`grep`, not `git status`.
- **Status→color map (exact):** done→`accentTeal`, codepetCanDo→`accentPurple`, needsApproval→`accentGold`, needsYou→`accentOrange`, blocked→`mutedText`.
- **Labels (exact), EN / VI:** status Done/Xong, Codepet can do/Codepet làm được, Needs approval/Cần duyệt, Needs you/Cần bạn, Needs earlier steps/Cần bước trước. who Codepet does/Codepet làm, Codepet drafts/Codepet soạn, You/Bạn. beacon "★ DO THIS NEXT"/"★ LÀM ĐIỀU NÀY TIẾP". progress "{pct}% · {done} of {total} done"/"{pct}% · {done}/{total} xong". progress title "Project progress"/"Tiến độ dự án".
- **Decisions:** dependency lines DEFERRED (blocked cards show "after: <dep>"); empty state HONEST + quiet fail-open `generateRoadmap()` on appear; tap TOGGLES done; HORIZONTAL columns (all 5 phases, headers always shown). Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Modify `codepet/Models/RoadmapTask.swift` (Task 1: `TaskStatus.label`, `TaskWho.label`)
- Modify `codepet/Models/RoadmapEngine.swift` (Task 1: `orderedColumns`)
- Create `codepet/Views/Overview/TaskCardView.swift` (Task 2)
- Create `codepet/Views/Overview/PhaseColumnView.swift` (Task 2)
- Create `codepet/Views/Overview/RoadmapHeaderView.swift` (Task 3)
- Create `codepet/Views/Overview/OverviewBoardView.swift` (Task 4: board + `EmptyRoadmapView`)
- Modify `codepet/Views/Shell/AppShellView.swift` (Task 4: `.overview` router)
- Test `codepetTests/RoadmapBoardHelpersTests.swift` (Task 1)

---

### Task 1: Pure board helpers

**Files:**
- Modify: `codepet/Models/RoadmapTask.swift`, `codepet/Models/RoadmapEngine.swift`
- Test: `codepetTests/RoadmapBoardHelpersTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`/`RoadmapPhase`/`TaskStatus`/`TaskWho`/`RoadmapEngine.tasksByPhase` (3A), `AppLanguage`.
- Produces: `RoadmapEngine.orderedColumns(_:) -> [(phase: RoadmapPhase, tasks: [RoadmapTask])]`; `TaskStatus.label(_ lang: AppLanguage) -> String`; `TaskWho.label(_ lang: AppLanguage) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapBoardHelpersTests.swift
import XCTest
@testable import codepet

final class RoadmapBoardHelpersTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does)
    }

    func testOrderedColumnsAllFivePhasesInOrder() {
        let tasks = [t("a", .build), t("b", .find), t("c", .build)]
        let cols = RoadmapEngine.orderedColumns(tasks)
        XCTAssertEqual(cols.map(\.phase), RoadmapPhase.allCases)   // Find..Launch, all 5
        XCTAssertEqual(cols.map(\.phase.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(cols[0].tasks.map(\.id), ["b"])            // find
        XCTAssertEqual(cols[2].tasks.map(\.id), ["a", "c"])       // build, input order preserved
        XCTAssertTrue(cols[3].tasks.isEmpty)                      // ship — empty phase present
        XCTAssertTrue(cols[4].tasks.isEmpty)                     // launch — empty phase present
    }
    func testOrderedColumnsEmptyInputStillFivePhases() {
        XCTAssertEqual(RoadmapEngine.orderedColumns([]).map(\.phase), RoadmapPhase.allCases)
        XCTAssertTrue(RoadmapEngine.orderedColumns([]).allSatisfy { $0.tasks.isEmpty })
    }
    func testStatusLabelsDistinctNonEmptyBothLanguages() {
        let statuses: [TaskStatus] = [.done, .codepetCanDo, .needsApproval, .needsYou, .blocked]
        for lang in [AppLanguage.en, .vi] {
            let labels = statuses.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 5)                  // all distinct
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
    func testWhoLabelsDistinctNonEmptyBothLanguages() {
        let whos: [TaskWho] = [.does, .draft, .you]
        for lang in [AppLanguage.en, .vi] {
            let labels = whos.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 3)
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapBoardHelpersTests 2>&1 | tail -20`
Expected: FAIL — no `orderedColumns` / `label(_:)`.

- [ ] **Step 3: Add the label helpers to `RoadmapTask.swift`**

Append to `codepet/Models/RoadmapTask.swift` (after `enum TaskStatus`):

```swift
extension TaskWho {
    /// Board chip label — who acts on the task.
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .does:  return lang == .vi ? "Codepet làm" : "Codepet does"
        case .draft: return lang == .vi ? "Codepet soạn" : "Codepet drafts"
        case .you:   return lang == .vi ? "Bạn" : "You"
        }
    }
}

extension TaskStatus {
    /// Board legend label for the derived status.
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .done:          return lang == .vi ? "Xong" : "Done"
        case .codepetCanDo:  return lang == .vi ? "Codepet làm được" : "Codepet can do"
        case .needsApproval: return lang == .vi ? "Cần duyệt" : "Needs approval"
        case .needsYou:      return lang == .vi ? "Cần bạn" : "Needs you"
        case .blocked:       return lang == .vi ? "Cần bước trước" : "Needs earlier steps"
        }
    }
}
```

- [ ] **Step 4: Add `orderedColumns` to `RoadmapEngine.swift`**

Add inside `enum RoadmapEngine` (after `tasksByPhase`):

```swift
    /// All five phases in `RoadmapPhase.allCases` order, each paired with its tasks
    /// (empty array when none) — guarantees the board's column set + order regardless
    /// of which phases currently have tasks.
    static func orderedColumns(_ tasks: [RoadmapTask]) -> [(phase: RoadmapPhase, tasks: [RoadmapTask])] {
        let grouped = tasksByPhase(tasks)
        return RoadmapPhase.allCases.map { (phase: $0, tasks: grouped[$0] ?? []) }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/RoadmapTask.swift codepet/Models/RoadmapEngine.swift codepetTests/RoadmapBoardHelpersTests.swift
# commit via the fsmonitor-off form (see Global Constraints) with message:
# "feat(roadmap): orderedColumns + TaskStatus/TaskWho labels (board helpers)"
```

---

### Task 2: `TaskCardView` + `PhaseColumnView`

**Files:**
- Create: `codepet/Views/Overview/TaskCardView.swift`, `codepet/Views/Overview/PhaseColumnView.swift`
- Verified by: build (no unit tests — these are SwiftUI views with no standalone logic).

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapEngine.status(for:in:)`, `TaskStatus.label`/`TaskWho.label` (Task 1), `CompanyStore.toggleTaskDone` (3A), CodepetTheme (`CodepetCard`, accents, `.pixelSystem`).
- Produces: `TaskCardView(task:allTasks:)`; `PhaseColumnView(phase:tasks:allTasks:)`.

- [ ] **Step 1: Write `TaskCardView.swift`**

```swift
// codepet/Views/Overview/TaskCardView.swift
import SwiftUI

/// One roadmap task card: done toggle, title, detail, who chip, status pill, and
/// (when blocked) an "after: <dep>" hint. Read-only apart from the done toggle.
struct TaskCardView: View {
    let task: RoadmapTask
    let allTasks: [RoadmapTask]        // for status derivation + blocked-dep lookup
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var status: TaskStatus { RoadmapEngine.status(for: task, in: allTasks) }

    var body: some View {
        CodepetCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        Task { await companyStore.toggleTaskDone(id: task.id) }
                    } label: {
                        Image(systemName: task.done ? "checkmark.square.fill" : "square")
                            .foregroundColor(task.done ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    Text(task.title)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .strikethrough(task.done)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    tag(task.who.label(lang), color: CodepetTheme.mutedText)
                    tag(status.label(lang), color: statusTint(status))
                }
                if status == .blocked, let dep = blockedAfter {
                    Text((lang == .vi ? "sau: " : "after: ") + dep)
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Title of the first not-done dependency (nil if none / dangling).
    private var blockedAfter: String? {
        for id in task.dependsOn {
            if let d = allTasks.first(where: { $0.id == id }), !d.done { return d.title }
        }
        return nil
    }

    private func statusTint(_ s: TaskStatus) -> Color {
        switch s {
        case .done:          return CodepetTheme.accentTeal
        case .codepetCanDo:  return CodepetTheme.accentPurple
        case .needsApproval: return CodepetTheme.accentGold
        case .needsYou:      return CodepetTheme.accentOrange
        case .blocked:       return CodepetTheme.mutedText
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.pixelSystem(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
```

- [ ] **Step 2: Write `PhaseColumnView.swift`**

```swift
// codepet/Views/Overview/PhaseColumnView.swift
import SwiftUI

/// One phase column: header (label + count) over its task cards. An empty phase
/// shows a muted placeholder so the column reads as intentionally empty.
struct PhaseColumnView: View {
    let phase: RoadmapPhase
    let tasks: [RoadmapTask]
    let allTasks: [RoadmapTask]
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.label(lang).uppercased())
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.bodyText)
                Spacer()
                Text("\(tasks.count)")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 4)
            if tasks.isEmpty {
                Text("—")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else {
                ForEach(tasks) { t in
                    TaskCardView(task: t, allTasks: allTasks)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 230, alignment: .top)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Overview/TaskCardView.swift codepet/Views/Overview/PhaseColumnView.swift
# commit (fsmonitor-off form): "feat(roadmap): TaskCardView (done toggle + status pill) + PhaseColumnView"
```

---

### Task 3: `RoadmapHeaderView` (progress + beacon)

**Files:**
- Create: `codepet/Views/Overview/RoadmapHeaderView.swift`
- Verified by: build.

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapEngine.progressPercent`/`nextStep` (3A), CodepetTheme (`CodepetCard`, `accentPurple`, `hairline`, `.pixelSystem`).
- Produces: `RoadmapHeaderView(tasks:)`.

- [ ] **Step 1: Write `RoadmapHeaderView.swift`**

```swift
// codepet/Views/Overview/RoadmapHeaderView.swift
import SwiftUI

/// Full-width header above the columns: a Project Progress card and the
/// DO THIS NEXT beacon (hidden when there's no next step).
struct RoadmapHeaderView: View {
    let tasks: [RoadmapTask]
    @Environment(\.uiLanguage) private var lang

    private var total: Int { tasks.count }
    private var doneCount: Int { tasks.filter(\.done).count }
    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var next: RoadmapTask? { RoadmapEngine.nextStep(tasks) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            progressCard
            if let n = next { beaconCard(n) }
        }
    }

    private var progressCard: some View {
        CodepetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(lang == .vi ? "Tiến độ dự án" : "Project progress")
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.mutedText)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CodepetTheme.hairline).frame(height: 8)
                        Capsule().fill(CodepetTheme.accentPurple)
                            .frame(width: geo.size.width * CGFloat(pct) / 100.0, height: 8)
                    }
                }
                .frame(height: 8)
                Text(progressLabel)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressLabel: String {
        lang == .vi ? "\(pct)% · \(doneCount)/\(total) xong"
                    : "\(pct)% · \(doneCount) of \(total) done"
    }

    private func beaconCard(_ n: RoadmapTask) -> some View {
        CodepetCard(fill: CodepetTheme.accentPurple.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang == .vi ? "★ LÀM ĐIỀU NÀY TIẾP" : "★ DO THIS NEXT")
                    .font(.pixelSystem(size: 10, weight: .bold))
                    .foregroundColor(CodepetTheme.accentPurple)
                Text(n.title)
                    .font(.pixelSystem(size: 13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Overview/RoadmapHeaderView.swift
# commit (fsmonitor-off form): "feat(roadmap): RoadmapHeaderView (progress card + DO THIS NEXT beacon)"
```

---

### Task 4: `OverviewBoardView` + shell wiring

**Files:**
- Create: `codepet/Views/Overview/OverviewBoardView.swift` (board + `EmptyRoadmapView`)
- Modify: `codepet/Views/Shell/AppShellView.swift` (route `.overview` to the board)
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `CompanyStore` (`company.tasks`, `generateRoadmap`), `RoadmapEngine.orderedColumns` (Task 1), `RoadmapHeaderView` (Task 3), `PhaseColumnView` (Task 2), CodepetTheme.
- Produces: `OverviewBoardView()`; `EmptyRoadmapView()`.

- [ ] **Step 1: Write `OverviewBoardView.swift`**

```swift
// codepet/Views/Overview/OverviewBoardView.swift
import SwiftUI

/// The Overview = the roadmap board. Renders CompanyStore.company.tasks through
/// the pure RoadmapEngine: a progress + beacon header over five phase columns.
/// Empty → an honest empty card plus a quiet, fail-open generate on appear.
struct OverviewBoardView: View {
    @EnvironmentObject var companyStore: CompanyStore

    private var tasks: [RoadmapTask] { companyStore.company.tasks }

    var body: some View {
        Group {
            if tasks.isEmpty {
                EmptyRoadmapView()
            } else {
                board
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if companyStore.company.tasks.isEmpty { await companyStore.generateRoadmap() }
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoadmapHeaderView(tasks: tasks)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(RoadmapEngine.orderedColumns(tasks), id: \.phase) { col in
                        PhaseColumnView(phase: col.phase, tasks: col.tasks, allTasks: tasks)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Honest empty state — the roadmap hasn't been generated yet.
struct EmptyRoadmapView: View {
    @Environment(\.uiLanguage) private var lang
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 30))
                .foregroundColor(CodepetTheme.mutedText)
            Text(lang == .vi ? "Lộ trình của bạn sẽ xuất hiện ở đây" : "Your roadmap will appear here")
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Khi Codepet vạch ra các bước tiếp theo, chúng sẽ hiện ở đây."
                             : "Once Codepet maps your next steps, they show up here.")
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}
```

- [ ] **Step 2: Wire the router in `AppShellView.swift`**

Replace the content-slot line (currently `ShellPlaceholderView(view: companyStore.view)` at ~line 27, before the `if !copilotCollapsed` block):

```swift
                Group {
                    if companyStore.view == .overview {
                        OverviewBoardView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

(Keep the surrounding `sidebar` / `Divider()` / copilot structure exactly as-is.)

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite to confirm no regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` (all suites, incl. Task 1's `RoadmapBoardHelpersTests`).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Overview/OverviewBoardView.swift codepet/Views/Shell/AppShellView.swift
# commit (fsmonitor-off form): "feat(roadmap): OverviewBoardView + shell router (board, empty state, generate-on-appear)"
```

---

## Final verification

Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. The Overview tab now renders the roadmap board (or the honest empty state when there are no tasks).

---

## Self-Review

**Spec coverage:** pure helpers `orderedColumns`/`TaskStatus.label`/`TaskWho.label` (Task 1 ✓); `TaskCardView` with done toggle + status pill + who chip + blocked "after:" hint + status color map (Task 2 ✓); `PhaseColumnView` all-phase columns w/ count + empty placeholder (Task 2 ✓); `RoadmapHeaderView` progress card + beacon hidden-when-nil (Task 3 ✓); `OverviewBoardView` empty-vs-board + horizontal columns + quiet fail-open generate-on-appear + `EmptyRoadmapView` (Task 4 ✓); `AppShellView` `.overview` router (Task 4 ✓). Decisions honored: lines deferred (blocked "after:" hint), honest empty + generate, toggle done, horizontal columns, exact status/label/color values.

**Placeholder scan:** none — every step contains complete code or an exact command.

**Type consistency:** `orderedColumns(_:) -> [(phase:tasks:)]` produced in Task 1, consumed in Task 4's `ForEach(..., id: \.phase)`. `TaskStatus.label`/`TaskWho.label`/`RoadmapEngine.status`/`progressPercent`/`nextStep` are all existing/Task-1 signatures. `TaskCardView(task:allTasks:)` (Task 2) consumed by `PhaseColumnView` (Task 2) consumed by `OverviewBoardView` (Task 4). `RoadmapHeaderView(tasks:)` (Task 3) consumed by Task 4. `CodepetCard(fill:)` and `.pixelSystem(size:weight:)` match CodepetTheme. `companyStore.toggleTaskDone`/`generateRoadmap` are 3A `@MainActor async` — called inside `Task {}` / `.task {}`.

**Known note for the implementer:** view Tasks 2–4 have no unit tests by design (spec: SwiftUI verified by build); the failing-test-first cycle applies only to Task 1. The `.task` generate-on-appear reruns each time the empty board appears — intentional and harmless (fail-open no-op today).
