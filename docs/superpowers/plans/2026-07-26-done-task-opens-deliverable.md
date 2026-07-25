# Done Task Opens Deliverable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make a "done" task card, on all three surfaces where task cards appear, open the `DeliverableDetailView` sheet for the deliverable that task produced — matching the web's done-card-opens-artifact-viewer behavior (not ported pixel-for-pixel). Today all three taps on a done card are dead clicks.

**Architecture:** Confirmed root cause: `TasksView.card(_:)`, `RoadmapMapView.taskCard(_:).onTapGesture`, and `DepartmentDetailView`'s `DepartmentTaskCard` each branch their tap/action on `TaskStatus` (`.needsApproval` / `.codepetCanDo`) but have no branch for `.done` — the department card additionally renders a static, non-interactive `"✓ Approved · delivered"` `Text`. Fix: add a pure resolver `RoadmapEngine.deliverable(for:in:) -> Deliverable?` (the `company.library` item whose `sourceTaskId == task.id`), then in each of the three views add a local `@State private var openDeliverable: Deliverable?` + `.sheet(item:)` presenting the EXISTING `DeliverableDetailView(deliverable:)` (defined in `LibraryView.swift`, already used identically by `LibraryView` and `CopilotChatView`). No deliverable resolves → `openDeliverable` stays/becomes `nil` → `.sheet(item:)` presents nothing (safe no-op by construction, not by manual guard).

**Tech Stack:** Swift, SwiftUI, XCTest. Build: `xcodebuild` scheme `codepet`.

## Global Constraints

- Branch `feat/done-task-opens-deliverable` off `origin/main`. Work in `~/Documents/Murror/codepet`.
- Read-only over company data: this feature only PRESENTS a sheet, it never mutates `companyStore.company` (no new saver calls, no task/library writes).
- Reuse the EXISTING `DeliverableDetailView` (`codepet/Views/Library/LibraryView.swift`) — do NOT build a new viewer or duplicate its markup. Confirm its real init (`DeliverableDetailView(deliverable:)`) before wiring.
- No-op when no deliverable resolves: use `.sheet(item: $openDeliverable)` everywhere (never `.sheet(isPresented:)` for this feature) so assigning `nil` (no match) is inherently a no-op — no crash, no empty sheet.
- Match each view's existing house style: `TasksView`/`RoadmapMapView` already gate their tap action on `status ==`; `DepartmentTaskCard`'s done row becomes a plain `Button` (`.buttonStyle(.plain)`), matching `actionButton`'s style in the same file — do not restyle the "✓ Approved · delivered" text.
- Task 1's test is struct/enum-only (RoadmapEngine + RoadmapTask + Deliverable, no `CompanyStore`) — **no `@MainActor`** (Xcode 26.2 crashes the test host on teardown of `@MainActor` classes; this test has none, so it must run clean).
- **Verify real signatures before writing.** The line numbers and surrounding-code snippets below are approximate; read each file and adapt the insertion points and any initializer labels (`Deliverable(...)`, `RoadmapTask` test helper `t(...)`, `TaskStatus.done`, `RoadmapEngine.status(for:in:)`) to the real source. Do not invent APIs.
- Build/verify: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` (foreground, never background).

---

### Task 1: Add the shared resolver `RoadmapEngine.deliverable(for:in:)`

**Files:**
- Modify: `codepet/Models/RoadmapEngine.swift`
- Test: `codepetTests/RoadmapEngineTests.swift`

**Interfaces:**
- Produces: `RoadmapEngine.deliverable(for task: RoadmapTask, in library: [Deliverable]) -> Deliverable?`. Consumed by Tasks 2, 3, 4.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/RoadmapEngineTests.swift` (reuse the file's existing private `t(...)` helper — confirm its real signature first; the calls below assume `t(_ id:_ phase:done:)`):

```swift
    func testDeliverableResolvesBySourceTaskId() {
        let done = t("a", .build, done: true)
        let lib = [Deliverable(kind: .doc, title: "Doc A", body: "b", sourceTaskId: "a")]
        XCTAssertEqual(RoadmapEngine.deliverable(for: done, in: lib)?.title, "Doc A")
    }

    func testDeliverableNilWhenNoLibraryMatchOrEmptyLibrary() {
        let done = t("a", .build, done: true)
        XCTAssertNil(RoadmapEngine.deliverable(for: done, in: []))
        let other = [Deliverable(kind: .doc, title: "Other", body: "b", sourceTaskId: "z")]
        XCTAssertNil(RoadmapEngine.deliverable(for: done, in: other))
    }
```

(If the real `t(...)` helper or `Deliverable(...)` init labels differ, adapt these calls to the real ones — semantics unchanged.)

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapEngineTests`
Expected: FAIL to compile — `RoadmapEngine` has no member `deliverable`.

- [ ] **Step 3: Add the resolver**

In `codepet/Models/RoadmapEngine.swift`, add next to `status(for:in:)`:

```swift
    /// Resolve the deliverable a done task produced — the library item whose
    /// `sourceTaskId` matches the task's id. `nil` when none is found: legacy tasks
    /// predate `sourceTaskId`, or the task's deliverable was never generated. Pure —
    /// no network, no mutation; callers no-op the tap when this returns nil.
    static func deliverable(for task: RoadmapTask, in library: [Deliverable]) -> Deliverable? {
        library.first { $0.sourceTaskId == task.id }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapEngineTests`
Expected: PASS. `RoadmapEngine` is an `enum` of static funcs; the test touches no `@MainActor` type → runs clean under Xcode 26.2.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: add RoadmapEngine.deliverable(for:in:) resolver

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire the Tasks-tab kanban card (`TasksView.swift`)

**Files:**
- Modify: `codepet/Views/Tasks/TasksView.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.deliverable(for:in:)` (Task 1); existing `DeliverableDetailView`.

Read the real `card(_:)`, `body`, and the existing `@EnvironmentObject`/`@Environment` declarations first; adapt insertion points to the real structure.

- [ ] **Step 1: Add sheet state** — in `TasksView`, alongside the existing `@EnvironmentObject`/`@Environment`:

```swift
    @State private var openDeliverable: Deliverable?
```

- [ ] **Step 2: Branch the card tap on `.done`** — in `card(_ t:)`, add a `.done` branch to the existing status if/else in the Button action:

```swift
            else if st == .done { openDeliverable = RoadmapEngine.deliverable(for: t, in: companyStore.company.library) }
```

- [ ] **Step 3: Present the sheet** — attach to `body`'s root, after the existing `.padding/.frame`:

```swift
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
```

- [ ] **Step 4: Build** — `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. (SwiftUI wiring — no unit test; resolver correctness is Task 1's.)

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Tasks/TasksView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: done Tasks-tab card opens its deliverable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire the Overview roadmap map node (`RoadmapMapView.swift`)

**Files:**
- Modify: `codepet/Views/Overview/RoadmapMapView.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.deliverable(for:in:)` (Task 1); existing `DeliverableDetailView`.

Read the real `taskCard(_:)`, its `.onTapGesture`, and `body` first.

- [ ] **Step 1: Add sheet state** — in `RoadmapMapView`, alongside the existing `@EnvironmentObject`/`@Environment`:

```swift
    @State private var openDeliverable: Deliverable?
```

- [ ] **Step 2: Branch the tap gesture on `.done`** — extend the existing `.onTapGesture` in `taskCard(_ task:)`:

```swift
        .onTapGesture {
            if status == .codepetCanDo { Task { await companyStore.runTask(task, language: lang) } }
            else if status == .done { openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library) }
        }
```

(Adapt to the real existing action for `.codepetCanDo` — keep it, just add the `.done` branch.)

- [ ] **Step 3: Present the sheet** — attach `.sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }` to the `body` view chain (e.g. after the existing `.onAppear`, at the same nesting level).

- [ ] **Step 4: Build** — `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Overview/RoadmapMapView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: done roadmap map node opens its deliverable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the department task card (`DepartmentDetailView.swift`)

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.deliverable(for:in:)` (Task 1); existing `DeliverableDetailView`.

Read the real `DepartmentTaskCard` struct, its `task.done` branch, `body`, and `@EnvironmentObject` declarations first.

- [ ] **Step 1: Add sheet state** — in `DepartmentTaskCard`, alongside its existing `@EnvironmentObject`/`@Environment`:

```swift
    @State private var openDeliverable: Deliverable?
```

- [ ] **Step 2: Make the done row tappable** — wrap the existing static done `Text` in a `Button` (keep the exact text/font/color):

```swift
            if task.done {
                Button {
                    openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
                } label: {
                    Text(lang == .vi ? "✓ Đã duyệt · đã giao" : "✓ Approved · delivered")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.accentTeal)
                }
                .buttonStyle(.plain)
            } else {
                actionButton
            }
```

(Confirm the real done-branch text/font/color and reuse them verbatim; the two branches are mutually exclusive so there's no gesture conflict with `actionButton`.)

- [ ] **Step 3: Present the sheet** — attach `.sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }` to `DepartmentTaskCard.body`'s root (after the existing background/overlay modifiers).

- [ ] **Step 4: Build** — `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Company/DepartmentDetailView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: done department task card opens its deliverable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- **Requirement coverage:** all three surfaces branch a done tap to open `DeliverableDetailView` for the task's produced deliverable; unmatched → `nil` → `.sheet(item:)` presents nothing (no crash, no empty sheet). ✓
- **DRY:** resolver written once (Task 1), consumed identically by all three view tasks. ✓
- **Reuse, not rebuild:** every surface presents the existing `DeliverableDetailView(deliverable:)`. ✓
- **Read-only:** no task mutates `company.tasks`/`company.library`/any saver — sheet-presentation-only. ✓
- **House style:** `TasksView`/`RoadmapMapView` extend their existing `status ==` branch; `DepartmentTaskCard`'s done row becomes a `.plain` `Button`, text unchanged. ✓
- **Independent reviewability:** each of Tasks 2-4 touches exactly one surface and builds standalone. ✓
