# Department Detail Card Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the department detail page's type scale, layout frame, hero framing and task card so the screen is legible, hierarchical, and stops showing a live-looking primary button on a task that cannot run.

**Architecture:** One new pure function (`departmentPulse`) replaces the static companion line, so the only new logic is view-free and unit-tested. Everything else is a rewrite of `DepartmentDetailView.swift` in place: a capped reading column, a grouped spacing rhythm, a taller hero with a neutral scrim and an accent-tinted badge, and a blocked task card that names its blocker using the engine helper the roadmap board already uses (`RoadmapGating.blocker` + `RoadmapBoardCopy.waitingOn`). No new resolution logic, no new copy helpers.

**Tech Stack:** Swift 5 / SwiftUI, macOS 13+, XCTest, Xcode 26.4 (`xcodebuild`, scheme `codepet`, project `codepet.xcodeproj`).

**Spec:** `docs/superpowers/specs/2026-08-04-department-detail-card-design.md`

## Global Constraints

- **A running `codepet.app` holds the Firestore LevelDB lock and aborts the test host.** Run `pkill -x codepet` before every `xcodebuild test`. `** TEST FAILED **` with zero `Failing tests:` lines means the suite never ran — pkill and re-run. Always confirm an `Executed N tests` line appeared.
- Every `xcodebuild` invocation must carry: `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
- **Every `xcodebuild` invocation must also set `dangerouslyDisableSandbox: true` on the Bash tool call.** Sandboxed, `codesign` cannot reach the login keychain and the build dies on the embedded framework dylibs with no `Failing tests:` and no `Executed N tests` line — it mimics the Firestore-lock symptom but is not it. Do not add a standing `xcodebuild` allow rule.
- **This session cannot screenshot the native app** (Screen Recording denied, AX returns 0 windows). Visual claims are never self-verified — Task 6 is a handoff to Mona with specific questions. Green tests are not evidence that the layout looks right.
- `Department.focus` must stay in `codepet/Models/Department.swift` — `ChatContext.swift:95,108` grounds chat with it. It only stops being rendered.
- Do not touch `CompanyView.swift` beyond reading it. Its badge treatment (`CompanyView.swift:137-142`) is the source of truth the hero badge copies.
- Do not edit Giang's Build Coach files (`BuildCoachView`, `InstallView`, `SummaryView`, tracking, `/api/track*`, `/api/build-plan`). None are in scope here.
- Copy strings are always EN + VI, following the existing `lang == .vi ? "…" : "…"` pattern in the file being edited.

---

## File Structure

| Path | Responsibility |
|---|---|
| Create: `codepet/Models/DepartmentPulse.swift` | The one new unit of logic: a pure `departmentPulse(...) -> String?` deriving the companion's line from live task state. View-free so it is testable. |
| Create: `codepetTests/DepartmentPulseTests.swift` | Branch coverage for `departmentPulse`, including the two blocked paths (dependency-gated and phase-gated, both cross-department). |
| Modify: `codepet/Models/Department.swift:7-16` | Adds `coverAnchor: UnitPoint = .center` — the per-department hero crop escape hatch. |
| Modify: `codepet/Views/Company/DepartmentDetailView.swift` (whole file) | Page frame, type scale, section header, pulse wiring, hero, task card. |

Everything view-related stays in the one view file, which lands around 200 lines — in line with the repo's other view files. The pure function goes in `Models/` next to `RoadmapEngine`/`RoadmapGating`, which it calls, following the precedent of the free function `taskStatusTint` in `RoadmapTask.swift:65`.

---

## Task 0: Isolated worktree and a green baseline

**Files:**
- Create: worktree at `/Users/monatruong/Developer/codepet-dept-detail` on new branch `feat/dept-detail-card-design`
- Copy in: `docs/superpowers/specs/2026-08-04-department-detail-card-design.md`, `docs/superpowers/plans/2026-08-04-department-detail-card-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a clean worktree branched off `origin/main` with the spec and plan committed, and a recorded baseline test count every later task compares against.

A worktree is mandatory here: the primary checkout `/Users/monatruong/Developer/codepet` is on `fix/copilot-dock-header`, carries an unrelated modified `codepet/codepet.entitlements`, and may be driven by a concurrent session. A separate worktree also gets its own DerivedData.

- [ ] **Step 1: Fetch, then create the worktree off `origin/main`**

```bash
cd /Users/monatruong/Developer/codepet
git fetch origin
git worktree add -b feat/dept-detail-card-design \
  /Users/monatruong/Developer/codepet-dept-detail origin/main
```

Expected: `Preparing worktree (new branch 'feat/dept-detail-card-design')` then `HEAD is now at <sha> …`.

- [ ] **Step 2: Carry the spec and plan onto the branch**

The docs were committed on `fix/copilot-dock-header`, which is not this branch's ancestor. Copy the two files across rather than cherry-picking, so nothing from that branch's code comes with them.

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
git checkout fix/copilot-dock-header -- \
  docs/superpowers/specs/2026-08-04-department-detail-card-design.md \
  docs/superpowers/plans/2026-08-04-department-detail-card-design.md
git add docs/superpowers
git commit -m "docs: carry department detail spec + plan onto the branch"
git status --porcelain
```

Expected: the commit succeeds and `git status --porcelain` prints nothing.

- [ ] **Step 3: Free the Firestore lock**

```bash
pkill -x codepet; ps aux | grep -c "[c]odepet.app"
```

Expected: `0`.

- [ ] **Step 4: Run the full suite and record the baseline**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Executed [0-9]+ test|\*\* TEST" | tail -3
```

Expected: `** TEST SUCCEEDED **` with an `Executed N tests … 0 failures` line (N is around 698 on recent main). **Record N.** If the baseline is red, or no `Executed` line appears, stop and report — do not start Task 1.

---

## Task 1: `departmentPulse` — the live companion line

**Files:**
- Create: `codepet/Models/DepartmentPulse.swift`
- Test: `codepetTests/DepartmentPulseTests.swift`

**Interfaces:**
- Consumes: `Department` (`Models/Department.swift`), `RoadmapTask`, `TaskStatus`, `AppLanguage`, `RoadmapEngine.status(for:in:)`, `RoadmapGating.blocker(for:in:)`.
- Produces: `func departmentPulse(_ dept: Department, mine: [RoadmapTask], all: [RoadmapTask], lang: AppLanguage) -> String?` — a free function (not a type member). Returns `nil` when no line should render. Task 2 calls it and skips the whole sprite row on `nil`.

Two parameters, not one, on purpose: `mine` is the department's tasks, `all` is the whole board, because both `RoadmapEngine.status` and `RoadmapGating.blocker` depend on tasks in other departments (a dependency, or the founder step holding the phase window shut).

The new file must be added to the `codepet` target and the test file to the `codepetTests` target. The project has no `xcodegen` — if `xcodebuild` reports the symbol as missing after Step 3, the file was created on disk but not added to the target; add it in Xcode (File ▸ Add Files, or drag into the group) and re-run.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/DepartmentPulseTests.swift`:

```swift
import XCTest
@testable import codepet

final class DepartmentPulseTests: XCTestCase {
    private let eng = DepartmentCatalog.find("eng")!

    /// A task in `.find` owned by Codepet: never gates the phase window, never blocked.
    private func canDo(_ id: String, _ title: String = "Do a thing", dept: String? = "eng",
                       done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .find, who: .does,
                    done: done, dept: dept)
    }

    func testNoTasksRendersNoLine() {
        XCTAssertNil(departmentPulse(eng, mine: [], all: [], lang: .en))
    }

    func testEverythingDoneReadsAllClear() {
        let t = canDo("t1", done: true)
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "All clear in Engineering.")
    }

    func testApprovalOutranksEverythingElse() {
        let draft = RoadmapTask(id: "t1", title: "Waitlist", detail: "", phase: .find,
                                who: .does, drafted: true, dept: "eng")
        let other = canDo("t2")
        let all = [draft, other]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "One thing's ready for you to approve.")
    }

    func testTwoApprovalsPluralize() {
        let a = RoadmapTask(id: "t1", title: "A", detail: "", phase: .find, who: .does,
                            drafted: true, dept: "eng")
        let b = RoadmapTask(id: "t2", title: "B", detail: "", phase: .find, who: .does,
                            drafted: true, dept: "eng")
        let all = [a, b]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "2 ready for you to approve.")
    }

    func testOneTaskNeedsYou() {
        let t = RoadmapTask(id: "t1", title: "Pick a name", detail: "", phase: .find,
                            who: .you, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "One here needs you.")
    }

    func testTwoTasksNeedYou() {
        let a = RoadmapTask(id: "t1", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        let b = RoadmapTask(id: "t2", title: "B", detail: "", phase: .find, who: .you, dept: "eng")
        let all = [a, b]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "2 here need you.")
    }

    func testOneRunnableTask() {
        let t = canDo("t1")
        XCTAssertEqual(departmentPulse(eng, mine: [t], all: [t], lang: .en),
                       "Nothing blocked — I can run this one now.")
    }

    func testTwoRunnableTasks() {
        let all = [canDo("t1"), canDo("t2")]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "Nothing blocked — I can run 2 of these now.")
    }

    /// Dependency-gated: the blocker lives in ANOTHER department, proving resolution runs
    /// against the whole board and not the department-filtered list.
    func testDependencyBlockedNamesTheBlockingTaskFromAnotherDepartment() {
        let hosting = canDo("ops1", "Set up hosting", dept: "ops")
        let mine = RoadmapTask(id: "t1", title: "Ship the page", detail: "", phase: .find,
                               who: .does, dependsOn: ["ops1"], dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [mine], all: [mine, hosting], lang: .en),
                       "Everything here is waiting on Set up hosting.")
    }

    /// Phase-gated: nothing in Engineering has an unmet dependency, but its phase is shut
    /// behind a founder-owned step in an earlier phase. `RoadmapGating.blocker` returns that
    /// founder step, which is the useful thing to name.
    func testPhaseBlockedNamesTheFounderStepHoldingTheWindow() {
        let gate = RoadmapTask(id: "f1", title: "Choose your launch date", detail: "",
                               phase: .find, who: .you, dept: "mkt")
        let mine = RoadmapTask(id: "t1", title: "Build the editor", detail: "", phase: .build,
                               who: .does, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [mine], all: [mine, gate], lang: .en),
                       "Everything here is waiting on Choose your launch date.")
    }

    func testDoneTasksAreIgnoredWhenOpenWorkRemains() {
        let finished = canDo("t1", done: true)
        let open = canDo("t2")
        let all = [finished, open]
        XCTAssertEqual(departmentPulse(eng, mine: all, all: all, lang: .en),
                       "Nothing blocked — I can run this one now.")
    }

    func testVietnamese() {
        let done = canDo("t1", done: true)
        XCTAssertEqual(departmentPulse(eng, mine: [done], all: [done], lang: .vi),
                       "Xong hết trong Engineering.")
        let you = RoadmapTask(id: "t2", title: "A", detail: "", phase: .find, who: .you, dept: "eng")
        XCTAssertEqual(departmentPulse(eng, mine: [you], all: [you], lang: .vi),
                       "Một việc ở đây cần bạn.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPulseTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|Executed [0-9]+ test|\*\* TEST" | tail -5
```

Expected: a compile failure — `cannot find 'departmentPulse' in scope`. A *compile* failure is the correct failure here; there is no assertion to fail yet.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/DepartmentPulse.swift`:

```swift
// codepet/Models/DepartmentPulse.swift
import Foundation

/// The companion's one line on a department page, derived from that department's live tasks.
///
/// It replaces the static `Department.focus` render, which restated `rationale` almost verbatim
/// ("Build and ship the product itself…" / "This is where the thing you're building actually
/// gets made."). `focus` itself stays in the catalog — `ChatContext` grounds chat with it.
///
/// `mine` is the department's tasks; `all` is the whole board, because both `RoadmapEngine.status`
/// and `RoadmapGating.blocker` depend on tasks in OTHER departments — a dependency, or the
/// founder step holding the phase window shut.
///
/// Returns nil when NO line should render: a dormant department would otherwise show a sprite
/// next to nothing. Pure — no store, no view types.
func departmentPulse(_ dept: Department, mine: [RoadmapTask], all: [RoadmapTask],
                     lang: AppLanguage) -> String? {
    if mine.isEmpty { return nil }
    let open = mine.filter { !$0.done }
    if open.isEmpty {
        return lang == .vi ? "Xong hết trong \(dept.name)." : "All clear in \(dept.name)."
    }
    let statuses = open.map { (task: $0, status: RoadmapEngine.status(for: $0, in: all)) }

    // Precedence mirrors what the founder can act on soonest: their approval, then their own
    // step, then work Codepet can start, and only then the wait.
    let approving = statuses.filter { $0.status == .needsApproval }.count
    if approving == 1 {
        return lang == .vi ? "Có một bản nháp chờ bạn duyệt."
                           : "One thing's ready for you to approve."
    }
    if approving > 1 {
        return lang == .vi ? "\(approving) bản nháp chờ bạn duyệt."
                           : "\(approving) ready for you to approve."
    }
    let yours = statuses.filter { $0.status == .needsYou }.count
    if yours == 1 {
        return lang == .vi ? "Một việc ở đây cần bạn." : "One here needs you."
    }
    if yours > 1 {
        return lang == .vi ? "\(yours) việc ở đây cần bạn." : "\(yours) here need you."
    }
    let runnable = statuses.filter { $0.status == .codepetCanDo }.count
    if runnable == 1 {
        return lang == .vi ? "Không có gì chặn — tôi chạy được việc này ngay."
                           : "Nothing blocked — I can run this one now."
    }
    if runnable > 1 {
        return lang == .vi ? "Không có gì chặn — tôi chạy được \(runnable) việc ngay."
                           : "Nothing blocked — I can run \(runnable) of these now."
    }
    // Everything left is blocked. Name the one thing in front of it, resolved the same way the
    // roadmap card face does, so the two surfaces never disagree about the blocker.
    //
    // The nil fall-through is defensive only: `.blocked` means either a shut phase (so
    // `founderStep` is non-nil by definition — the phase is unsettled) or an unmet dependency
    // (so a not-done dependency exists). Neither can hand back nil today, which is why there is
    // no copy for it — no line beats an invented sentence.
    if let first = statuses.first(where: { $0.status == .blocked })?.task,
       let blocker = RoadmapGating.blocker(for: first, in: all) {
        return lang == .vi ? "Mọi việc ở đây đang chờ: \(blocker.title)."
                           : "Everything here is waiting on \(blocker.title)."
    }
    return nil
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPulseTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|Executed [0-9]+ test|\*\* TEST" | tail -5
```

Expected: `** TEST SUCCEEDED **`, `Executed 12 tests, with 0 failures`.

If a string assertion fails, fix the *implementation* to match the test, not the reverse — the copy in the tests is the approved copy from the spec.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
git add codepet/Models/DepartmentPulse.swift codepetTests/DepartmentPulseTests.swift \
        codepet.xcodeproj
git commit -m "feat(company): derive the department companion line from live task state"
```

`codepet.xcodeproj` is staged because adding files to the target edits `project.pbxproj`.

---

## Task 2: Page frame, type scale, section header, pulse wiring

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift:14-46` (the `body`, plus two new private members)

**Interfaces:**
- Consumes: `departmentPulse(_:mine:all:lang:)` from Task 1.
- Produces: private `hero(_:)` is still called from `body` with the same signature `(Department) -> some View`, so Task 3 can replace its internals without touching `body`. `DepartmentTaskCard(task:)` keeps its initializer, so Task 4 is likewise isolated.

This task replaces the uniform `spacing: 14` with explicit per-gap padding, caps the reading column, aligns the horizontal padding with the Company list, retunes the type, and swaps the static `d.focus` line for the pulse.

- [ ] **Step 1: Replace `body` and add the two new private members**

In `codepet/Views/Company/DepartmentDetailView.swift`, replace everything from `var body: some View {` through the closing brace of `body` (lines 14-46) with:

```swift
    /// The reading column. The shell hands this view the whole window
    /// (`AppShellView.swift:130`), so uncapped the rationale runs ~150 characters. Follows
    /// `RoadmapView.swift:187`'s capped column, a little wider because task cards live in this one.
    private let column: CGFloat = 800

    private var doneCount: Int { tasks.filter(\.done).count }

    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        return AnyView(ScrollView {
            // Grouped spacing, not a uniform gap: identity / context / work must read as three
            // blocks. With one shared `spacing:` the section header floated midway between the
            // text above it and the list it labels.
            VStack(alignment: .leading, spacing: 0) {
                backLink.padding(.bottom, 16)
                hero(d).padding(.bottom, 18)
                Text(d.rationale)
                    .font(CodepetTheme.inter(16))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                if let pulse = departmentPulse(d, mine: tasks, all: companyStore.company.tasks,
                                               lang: lang) {
                    HStack(alignment: .center, spacing: 8) {
                        CharacterImage(companyStore.company.companionId, size: 22)
                        Text(pulse)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                }
                sectionHeader.padding(.top, 30).padding(.bottom, 10)
                if tasks.isEmpty {
                    Text(lang == .vi ? "Chưa có việc trong phòng ban này."
                                     : "No tasks in this department yet.")
                        .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    VStack(spacing: 10) {
                        ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                    }
                }
            }
            .frame(maxWidth: column, alignment: .leading)
            // 26 matches `CompanyView`'s list padding, so the back link and hero stop shifting
            // 6pt when you navigate in from a card.
            .padding(.horizontal, 26)
            .padding(.top, 22).padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private var backLink: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(lang == .vi ? "Công ty" : "Company").font(CodepetTheme.inter(13))
            }.foregroundColor(CodepetTheme.bodyText)
        }.buttonStyle(.plain)
    }

    /// The count is appended only when it carries information — "1 of 1 left" says nothing until
    /// something is done, so an untouched department just reads "WHAT NEEDS DOING".
    private var sectionHeader: some View {
        Text(headerText)
            .font(CodepetTheme.inter(12, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var headerText: String {
        let base = (lang == .vi ? "Việc cần làm" : "What needs doing").uppercased()
        guard doneCount > 0, doneCount < tasks.count else { return base }
        return base + (lang == .vi ? " · \(doneCount)/\(tasks.count) đã xong"
                                   : " · \(doneCount) of \(tasks.count) done")
    }
```

Also delete the now-unused `private var left: Int { … }` on line 12 — the section header no longer counts what's left.

- [ ] **Step 2: Build to verify it compiles**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|warning: .*DepartmentDetail|\*\* BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **` with no `error:` lines. If it reports `left` as unused-but-declared or as missing, confirm Step 1's deletion landed.

- [ ] **Step 3: Commit**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
git add codepet/Views/Company/DepartmentDetailView.swift
git commit -m "refactor(company): cap the department column, group its spacing, retune its type"
```

---

## Task 3: Hero — taller crop, neutral scrim, accent badge

**Files:**
- Modify: `codepet/Models/Department.swift:7-16` (add `coverAnchor`)
- Modify: `codepet/Views/Company/DepartmentDetailView.swift` (replace `private func hero(_:)`, add `private func badge(_:)`)

**Interfaces:**
- Consumes: `Department.coverAnchor` (added in Step 1 below), `Department.accent`, `Department.ab`, `Department.coverAsset`.
- Produces: `hero(_ d: Department) -> some View` — same signature as before, so Task 2's `body` is untouched.

- [ ] **Step 1: Add the crop anchor to the model**

In `codepet/Models/Department.swift`, insert this stored property immediately after `let focus: String` (line 13), before `var id: String`:

```swift
    /// Where the hero's wide crop anchors. Six covers are 16:9 and centre fine; `dept-fin`
    /// (4:3) and `dept-legal` (1:1) lose more height, so they can pin the crop without
    /// touching the other six. `var` with a default so the memberwise init keeps every
    /// existing catalog entry compiling — declared LAST so it lands last in that init.
    var coverAnchor: UnitPoint = .center
```

Do not set a non-default value for any department yet. Task 6's visual check decides whether `fin` or `legal` needs one.

> **CORRECTION (applied during execution, commit `f828b3f`).** As originally written this
> plan did not compile: `.frame(width:height:alignment:)` takes an `Alignment`, and Step 2
> below passed `d.coverAnchor` (a `UnitPoint`) straight into it. `Alignment` cannot be the
> field's type either — `Department` gets `Hashable` by synthesis and `Alignment` is not
> `Hashable`, while `UnitPoint` is. The field stays `UnitPoint` (the right type for a crop
> anchor) and a file-private conversion is added in `DepartmentDetailView.swift`:
>
> ```swift
> private extension UnitPoint {
>     var frameAlignment: Alignment {
>         let h: HorizontalAlignment = x < 0.5 ? .leading : x > 0.5 ? .trailing : .center
>         let v: VerticalAlignment = y < 0.5 ? .top : y > 0.5 ? .bottom : .center
>         return Alignment(horizontal: h, vertical: v)
>     }
> }
> ```
>
> Step 2's frame call therefore reads `alignment: d.coverAnchor.frameAlignment`. The
> conversion snaps any `UnitPoint` to the nearest of the 9 standard alignments, which covers
> every anchor this feature can use.

- [ ] **Step 2: Replace `hero` and add `badge`**

In `codepet/Views/Company/DepartmentDetailView.swift`, replace the whole `private func hero(_ d: Department) -> some View { … }` function with:

```swift
    /// 190pt in an 800 column is 4.2:1, so a 16:9 cover keeps roughly 76% of its height —
    /// the old 140pt strip was 6.9:1 and kept about 40%, cutting the subject out of every
    /// cover. The scrim is NEUTRAL on purpose: the accent used to flood it at 0.55, which
    /// muddied art it clashes with (Engineering's accent is blue over hot-pink art) and
    /// dimmed the title sitting on it. Identity moves to the badge instead.
    private func hero(_ d: Department) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                Image(d.coverAsset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: 190,
                           alignment: d.coverAnchor.frameAlignment)   // see CORRECTION above
                    .clipped()
            }
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.40),
                .init(color: Color.black.opacity(0.72), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 9) {
                badge(d)
                Text(d.name)
                    .font(CodepetTheme.inter(30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(.white)
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The Company list card's badge treatment (`CompanyView.swift:137-142`), reused verbatim:
    /// with the scrim neutral this chip is the page's only carrier of the department's accent,
    /// and the two surfaces must agree on how a department is coloured.
    private func badge(_ d: Department) -> some View {
        Text(d.ab)
            .font(CodepetTheme.inter(11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "#0b0a12").opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(d.accent.opacity(0.34))))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
```

> **CORRECTION (final code review, 2026-08-04).** The `hero(_:)` doc comment in the code
> block above ("keeps roughly 76% of its height … kept about 40%") is wrong on both
> figures, and this is what actually shipped, so the drift matters. Under
> `contentMode: .fill`, retained height = source aspect ÷ frame aspect: new hero
> 1.778 ÷ (800/190 ≈ 4.21) ≈ **42%**; old hero 1.778 ÷ 6.9 ≈ **26%**. The real change is
> 26% → 42% (≈1.6×), not 40% → 76%, and it is a material reduction, not a fix — `dept-fin`
> (4:3) keeps ≈32%, `dept-legal` (1:1) keeps ≈24%, which is why the fin/legal crop check
> in Task 6 is a real gate. The shipped comment in
> `codepet/Views/Company/DepartmentDetailView.swift` has been corrected to match; this
> plan file is left as originally written (the historical record) with this note
> appended, per the same convention as the `frameAlignment` correction above.

- [ ] **Step 3: Build to verify it compiles**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|\*\* BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If `Color(hex:)` is reported missing, it lives in `codepet/Models/Character.swift` and is already in the target — a missing-symbol error here means the file edit landed in the wrong target, not that the helper is absent.

- [ ] **Step 4: Commit**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
git add codepet/Models/Department.swift codepet/Views/Company/DepartmentDetailView.swift
git commit -m "fix(company): taller hero crop, neutral scrim, accent-tinted department badge"
```

---

## Task 4: Task card — type, padding, and the blocked action

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift` (the `DepartmentTaskCard` struct: `body` and `actionButton`)

**Interfaces:**
- Consumes: `RoadmapEngine.status(for:in:)`, `RoadmapGating.blocker(for:in:)`, `RoadmapBoardCopy.waitingOn(_:lang:)`, `taskStatusTint(_:)`.
- Produces: nothing new — `DepartmentTaskCard(task:)` keeps its initializer.

The substantive change: `.blocked` currently disables the button while still painting it full accent purple with white text, so it reads as the live primary action on a task that cannot run. It becomes a dimmed ghost capsule with the blocker named beside it. `RoadmapGating.blocker` handles both causes of `.blocked` (unmet dependency when the phase is open, else the founder step holding the window shut), and `RoadmapBoardCopy.waitingOn` is the phrasing the roadmap hover peek already uses — EN and VI both come free.

- [ ] **Step 1: Retune the card body and add the blocked reason line**

In `DepartmentTaskCard`, replace the `var body: some View { … }` with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(CodepetTheme.inter(15, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if !task.detail.isEmpty {
                        Text(task.detail).font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !task.done {
                    Text(status.label(lang)).font(CodepetTheme.inter(11, weight: .medium))
                        .foregroundColor(taskStatusTint(status))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(taskStatusTint(status).opacity(0.12)))
                }
            }
            if task.done {
                Button {
                    openDeliverable = RoadmapEngine.deliverable(for: task,
                                                                in: companyStore.company.library)
                } label: {
                    Text(lang == .vi ? "✓ Đã duyệt · đã giao" : "✓ Approved · delivered")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.accentTeal)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    actionButton
                    // A dead button needs a reason next to it. `RoadmapGating.blocker` resolves
                    // both causes of `.blocked` — an unmet dependency, or the founder step
                    // holding the phase window shut — and it resolves against the WHOLE board,
                    // because the blocker usually belongs to another department.
                    if status == .blocked,
                       let blocker = RoadmapGating.blocker(for: task,
                                                           in: companyStore.company.tasks) {
                        Text(RoadmapBoardCopy.waitingOn(blocker.title, lang: lang))
                            .font(CodepetTheme.inter(12))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(item: $previewTask) { TaskDraftPreview(taskId: $0.id) }
    }
```

- [ ] **Step 2: Give the blocked state its own styling**

Replace `@ViewBuilder private var actionButton: some View { … }` with:

```swift
    @ViewBuilder private var actionButton: some View {
        let running = companyStore.runningTaskIds.contains(task.id)
        let blocked = status == .blocked
        Button {
            if status == .needsApproval { previewTask = task }
            else if task.who == .you { Task { await companyStore.walkThroughTask(task, language: lang) } }
            else { Task { await companyStore.runTask(task, language: lang) } }
        } label: {
            HStack(spacing: 5) {
                if running { ProgressView().controlSize(.mini) }
                Text(running ? (lang == .vi ? "Đang chạy…" : "Running…") : buttonLabel)
            }
            .font(CodepetTheme.inter(12.5, weight: .semibold))
            // Blocked must not wear the accent fill: it was disabled but still painted like the
            // live primary action, so the only honest read was "this button is broken".
            .foregroundColor(blocked ? CodepetTheme.mutedText
                                     : (task.who == .you ? CodepetTheme.bodyText : .white))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(blocked || task.who == .you
                ? AnyView(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                : AnyView(Capsule().fill(CodepetTheme.accentPurple)))
            .opacity(blocked ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked || running)
    }
```

`buttonLabel` and the two `@State` properties are unchanged — do not touch them.

- [ ] **Step 3: Build to verify it compiles**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|\*\* BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
git add codepet/Views/Company/DepartmentDetailView.swift
git commit -m "fix(company): a blocked task card names its blocker instead of faking a live CTA"
```

---

## Task 5: Full-suite regression

**Files:** none modified.

**Interfaces:**
- Consumes: the baseline count recorded in Task 0 Step 4.
- Produces: proof that nothing else regressed, before anything is handed to Mona or pushed.

- [ ] **Step 1: Free the Firestore lock**

```bash
pkill -x codepet; ps aux | grep -c "[c]odepet.app"
```

Expected: `0`.

- [ ] **Step 2: Run the whole suite**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Failing tests:|Executed [0-9]+ test|\*\* TEST" | tail -6
```

Expected: `** TEST SUCCEEDED **` with `Executed <baseline + 12> tests … 0 failures`. A count *below* baseline means suites never ran — pkill and re-run rather than reading it as a pass.

- [ ] **Step 3: Report the numbers**

State the baseline count, the new count, and the delta explicitly. Do not describe the work as verified beyond "tests pass" — nothing visual has been checked yet.

---

## Task 6: Signed build and visual handoff

**Files:** possibly `codepet/Models/Department.swift` (a `coverAnchor` value, only if the crop check demands one).

**Interfaces:**
- Consumes: everything above.
- Produces: Mona's answers, and at most one `coverAnchor` follow-up commit.

This session cannot screenshot the native app, so this task ends in questions, not conclusions.

- [ ] **Step 1: Build signed and check nothing else is holding the app**

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
ps aux | grep "[c]odepet.app"
```

If a sibling session's instance is running, **build only and stop** — do not `pkill` or relaunch someone else's app. Otherwise:

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Adhoc signing breaks keychain sign-in across rebuilds — the team-signed flags above are not optional.

- [ ] **Step 2: Launch the fresh build**

```bash
APP=$(xcodebuild -project /Users/monatruong/Developer/codepet-dept-detail/codepet.xcodeproj \
  -scheme codepet -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')
pkill -x codepet; open "$APP/codepet.app"
```

"Still looks the same" almost always means a stale binary — confirm the launched path is the worktree's DerivedData, not the primary checkout's.

- [ ] **Step 3: Ask Mona these questions, one screen at a time**

1. Open **Engineering, Finance and Legal** in turn. Does each hero keep its subject, or is `fin` (4:3 source) or `legal` (1:1 source) cropped to a meaningless band? If one is bad, that department gets `coverAnchor: .top` (or `.bottom`) in `DepartmentCatalog.all` — one line, then rebuild.
2. Is the 30pt white department name legible over every cover, including Marketing (the busiest one)?
3. On a blocked task, does the ghost button now read as unavailable, and is "Waiting on: …" the right phrasing at that size?
4. Does the companion line say something useful, or does it still feel like filler?

- [ ] **Step 4: Apply at most the `coverAnchor` answer, then commit**

Only if Step 3.1 identified a bad crop:

```bash
cd /Users/monatruong/Developer/codepet-dept-detail
# add `coverAnchor: .top` to the offending Department(...) entry in DepartmentCatalog.all
git add codepet/Models/Department.swift
git commit -m "fix(company): anchor the <dept> hero crop"
```

Anything else Mona raises is reported back, not silently implemented — the design was agreed in the spec.

- [ ] **Step 5: Stop before pushing**

Do not push, open a PR, or merge. Report the state of the branch and let Mona decide.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| 1. Page frame (800 column, padding 26, grouped spacing) | Task 2 |
| 2. Hero (190pt, `.interpolation(.high)`, neutral scrim, accent badge, `coverAnchor`) | Task 3 |
| 3. Type scale (all eight rows of the table) | Task 2 (page: 30 / 16 / 13 / 12) + Task 4 (card: 15 / 13 / 11 / 12.5) |
| 4. Task card (padding 14, chip stays, blocked ghost + `waitingOn`, escapeHatch excluded) | Task 4 |
| 5. Live companion line (priority order, sprite 22 centred, omitted when nil) | Task 1 (logic) + Task 2 (wiring, sprite size) |
| 6. Section header (uppercase 12, count only when informative) | Task 2 |
| 7. Hero badge kept | Task 3 |
| Testing (pulse branches, cross-department blockers, no duplicate gating tests) | Task 1 Step 1, Task 5 |
| Visual verification is a handoff | Task 6 |
| Known limits (cover softness, art direction) | Out of scope by the spec; restated nowhere as a task, correctly |

**Placeholder scan:** no TBD/TODO, no "add error handling", no "similar to Task N". Every code step carries full code; every command carries expected output.

**Type consistency:** `departmentPulse(_:mine:all:lang:) -> String?` is defined in Task 1 and called with exactly those labels in Task 2. `hero(_ d: Department) -> some View` keeps its Task 2 call site through Task 3's rewrite. `badge(_:)` is defined and called only inside Task 3. `coverAnchor` is added in Task 3 Step 1 and read in Task 3 Step 2. `DepartmentTaskCard(task:)` is unchanged across Tasks 2 and 4. `RoadmapBoardCopy.waitingOn(_:lang:)` and `RoadmapGating.blocker(for:in:)` match the existing signatures at `RoadmapBoardCopy.swift:73` and `RoadmapGating.swift` respectively. `left` is deleted in Task 2 and referenced nowhere afterward.
