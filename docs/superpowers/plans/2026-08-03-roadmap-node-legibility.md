# Roadmap Node Legibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every roadmap card explain itself — what it moves forward, how to act on it, what counts as done, and exactly what is blocking it — and give the founder a way to record work they did outside the app.

**Architecture:** All new decisions land in pure model files (`RoadmapNodeDetail`, `RoadmapEngine.suggestedNext`, copy in `RoadmapBoardCopy`) that are unit-tested without a host app; the views stay thin. This mirrors how `RoadmapGating`/`RoadmapFocus` were built in the predecessor branch.

**Tech Stack:** Swift 5 / SwiftUI, macOS 13+, XCTest, Xcode 26.4 (`xcodebuild`, scheme `codepet`).

**Spec:** `docs/superpowers/specs/2026-08-03-roadmap-node-legibility-design.md`

## Global Constraints

- Work in `/Users/monatruong/Developer/codepet-node-legibility` on branch `feat/roadmap-node-legibility` (branched off `feat/overview-roadmap-focus`, which is PR #52). Never touch `/Users/monatruong/Developer/codepet` (concurrent session) or `/Users/monatruong/Developer/codepet-roadmap-focus` (PR #52's worktree, holds an uncommitted CLAUDE.md trim).
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`: new `.swift` files under `codepet/` and `codepetTests/` are picked up automatically. **Never edit `project.pbxproj`.**
- **A running `codepet.app` holds the Firestore LevelDB lock and aborts the test host.** Run `pkill -x codepet` before every `xcodebuild test`. `** TEST FAILED **` with zero `Failing tests:` lines means the suite never ran — pkill and re-run.
- Every `xcodebuild` invocation must carry: `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
- Every user-visible string is bilingual: added to `RoadmapBoardCopy` as a function taking `lang: AppLanguage` (or `_ lang: AppLanguage`) and returning distinct English and Vietnamese text. **Never inline a new EN/VI literal in a view.**
- `TaskStatus` must stay a pure derivation of persisted fields. "Running" is ephemeral and must NOT become a `TaskStatus` case — that would change `status(for:in:)`'s meaning for ~18 call sites.
- Do not change `RoadmapEngine.nextMoves` — it is the chat fan-out and its `codepetCanDo`-only filter is correct for that job.
- Do not weaken `RoadmapGating.openPhases`, `settled`, `needsFounder`, `founderStep`, or `RoadmapEngine.status`'s precedence (`done → needsApproval → blocked → needsYou → codepetCanDo`). `needsFounder` must stay structural and must never call `RoadmapEngine.status` (it consults gating — that would recurse).
- Baseline: **629 tests, 0 failures.**

## Existing API this plan builds on (verified by reading the code)

- `RoadmapEngine.status(for:in:) -> TaskStatus`, `nextStep(_:) -> RoadmapTask?`, `nextMoves(_:limit:)`
- `RoadmapGating.openPhases(_:) -> Set<RoadmapPhase>`, `settled(_:in:) -> Bool`, `founderStep(in:) -> RoadmapTask?`, `blocker(for:in:) -> RoadmapTask?`
- `TaskStatus.label(_ lang:) -> String` (extension in `codepet/Models/RoadmapTask.swift`) — "Done", "Needs earlier steps", "Needs you", …
- `RoadmapPhase.label(_ lang:) -> String`, `RoadmapPhase.order`, `RoadmapPhase.allCases` = `find, foundation, build, ship, launch, grow`
- `DepartmentCatalog.find(_ key: String?) -> Department?` with `.name`
- `RoadmapBoardCopy.verb(for:_:)`, `.quietLabel(for:lang:)`, `.waitingOn(_:lang:)`, `.notPlannedYet(_:)`, `.herePhrase(founderName:lang:)`, `.showsTrayMarker(_:)`
- `CompanyStore.toggleTaskDone(id:) async` (line ~330), `runTask(_:language:) async`, `walkThroughTask(_:language:) async`, `approveTask(id:) async`
- **`CompanyStore.runningTaskIds: Set<String>`** — already exists as `@Published private(set)`; inserted/removed by `runTask` and `runFirstRunAction`, cleared on reset/hydrate. **No store change is needed for in-progress.**
- `DepartmentDetailView.swift:111` already consumes `runningTaskIds` (mini `ProgressView` + "Running…" + `.disabled`). Task 6 mirrors that pattern; do not invent a second one.
- `RoadmapTask` is `Identifiable`, so `.sheet(item:)` works with it directly (see `RoadmapView.swift:72`).

**Note for Task 6:** `walkThroughTask` deliberately does NOT enter `runningTaskIds` — it is an ordinary chat send, not a task run, so a `.needsYou` walk-through will not show "In progress". That is correct; do not "fix" it.

---

### Task 0: Baseline

**Files:** none (verification only)

**Interfaces:**
- Consumes: nothing
- Produces: the known-good starting point every later task is measured against

- [ ] **Step 1: Confirm the worktree and branch**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git branch --show-current    # expect: feat/roadmap-node-legibility
git status --short             # expect: clean
git log --oneline -1          # expect: edd5899 docs(overview): spec — roadmap node legibility…
```

- [ ] **Step 2: Free the Firestore lock**

```bash
pkill -x codepet; ps aux | grep -c "[c]odepet.app"
```

Expected: `0`.

- [ ] **Step 3: Run the full suite and record the baseline**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Executed [0-9]+ test|\*\* TEST" | tail -3
```

Expected: `** TEST SUCCEEDED **`, 629 tests, 0 failures. **If the baseline is red, stop and report** — do not start Task 1.

---

### Task 1: Copy for the panel, the lock and the suggestions

**Files:**
- Modify: `codepet/Models/RoadmapBoardCopy.swift` (append inside the enum)
- Test: `codepetTests/RoadmapBoardCopyTests.swift` (append inside the existing class)

**Interfaces:**
- Consumes: `RoadmapPhase`, `TaskStatus`, `TaskWho`, `AppLanguage`
- Produces:
  - `RoadmapBoardCopy.becomesTrue(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.toComplete(for who: TaskWho, _ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.howToFallback(for status: TaskStatus, _ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.phaseMustSettle(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.panelActionLabel(for status: TaskStatus, _ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.markComplete(_ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.markNotDone(_ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.inProgress(_ lang: AppLanguage) -> String`
  - `RoadmapBoardCopy.suggestionReason(dept: String?, unlockCount: Int, lang: AppLanguage) -> String`

- [ ] **Step 1: Write the failing tests**

Append inside `final class RoadmapBoardCopyTests` in `codepetTests/RoadmapBoardCopyTests.swift`:

```swift
    // MARK: node panel copy

    /// Every phase gets its own sentence, and the sentence names the phase — so the panel can
    /// never show a Foundation contract on a Build card.
    func testBecomesTrueIsDistinctPerPhaseAndNamesThePhase() {
        var seen = Set<String>()
        for phase in RoadmapPhase.allCases {
            let en = RoadmapBoardCopy.becomesTrue(phase, .en)
            XCTAssertFalse(en.isEmpty)
            XCTAssertTrue(en.contains(phase.label(.en)), "\(phase) sentence must name its phase")
            XCTAssertTrue(seen.insert(en).inserted, "\(phase) reuses another phase's sentence")
            XCTAssertNotEqual(en, RoadmapBoardCopy.becomesTrue(phase, .vi))
        }
    }

    func testToCompleteIsDistinctPerWho() {
        let does = RoadmapBoardCopy.toComplete(for: .does, .en)
        let draft = RoadmapBoardCopy.toComplete(for: .draft, .en)
        let you = RoadmapBoardCopy.toComplete(for: .you, .en)
        XCTAssertEqual(Set([does, draft, you]).count, 3)
        for w in [TaskWho.does, .draft, .you] {
            XCTAssertNotEqual(RoadmapBoardCopy.toComplete(for: w, .en),
                              RoadmapBoardCopy.toComplete(for: w, .vi))
        }
    }

    func testHowToFallbackCoversEveryStatus() {
        for s in [TaskStatus.done, .needsApproval, .blocked, .needsYou, .codepetCanDo] {
            XCTAssertFalse(RoadmapBoardCopy.howToFallback(for: s, .en).isEmpty)
            XCTAssertNotEqual(RoadmapBoardCopy.howToFallback(for: s, .en),
                              RoadmapBoardCopy.howToFallback(for: s, .vi))
        }
    }

    func testPhaseMustSettleNamesThePhase() {
        XCTAssertTrue(RoadmapBoardCopy.phaseMustSettle(.find, .en).contains(RoadmapPhase.find.label(.en)))
        XCTAssertNotEqual(RoadmapBoardCopy.phaseMustSettle(.find, .en),
                          RoadmapBoardCopy.phaseMustSettle(.find, .vi))
    }

    /// The panel's primary button has a label for EVERY status — including the two the card
    /// deliberately leaves chip-less (done, blocked), which is exactly why `verb(for:)` can't
    /// serve the panel on its own.
    func testPanelActionLabelCoversEveryStatusIncludingDoneAndBlocked() {
        for s in [TaskStatus.done, .needsApproval, .blocked, .needsYou, .codepetCanDo] {
            XCTAssertFalse(RoadmapBoardCopy.panelActionLabel(for: s, .en).isEmpty)
            XCTAssertNotEqual(RoadmapBoardCopy.panelActionLabel(for: s, .en),
                              RoadmapBoardCopy.panelActionLabel(for: s, .vi))
        }
        XCTAssertNil(RoadmapBoardCopy.verb(for: .blocked, .en))   // the gap being covered
        XCTAssertNil(RoadmapBoardCopy.verb(for: .done, .en))
    }

    func testMarkCompleteAndInProgressStringsAreBilingual() {
        for pair in [(RoadmapBoardCopy.markComplete(.en), RoadmapBoardCopy.markComplete(.vi)),
                     (RoadmapBoardCopy.markNotDone(.en), RoadmapBoardCopy.markNotDone(.vi)),
                     (RoadmapBoardCopy.inProgress(.en), RoadmapBoardCopy.inProgress(.vi))] {
            XCTAssertFalse(pair.0.isEmpty)
            XCTAssertFalse(pair.1.isEmpty)
            XCTAssertNotEqual(pair.0, pair.1)
        }
        XCTAssertNotEqual(RoadmapBoardCopy.markComplete(.en), RoadmapBoardCopy.markNotDone(.en))
    }

    /// The reason is a leverage signal, so the unlock count has to appear — and zero gets its
    /// own phrasing rather than "unlocks 0 later steps".
    func testSuggestionReasonCarriesDeptAndUnlockCount() {
        let two = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 2, lang: .en)
        XCTAssertTrue(two.contains("Design"))
        XCTAssertTrue(two.contains("2"))
        let one = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 1, lang: .en)
        XCTAssertTrue(one.contains("1"))
        XCTAssertFalse(one.contains("steps"), "singular for one unlock")
        let none = RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 0, lang: .en)
        XCTAssertFalse(none.contains("0"))
        // A dept-less legacy task still gets a readable prefix.
        XCTAssertFalse(RoadmapBoardCopy.suggestionReason(dept: nil, unlockCount: 1, lang: .en).isEmpty)
        XCTAssertNotEqual(two, RoadmapBoardCopy.suggestionReason(dept: "Design", unlockCount: 2, lang: .vi))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapBoardCopyTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `type 'RoadmapBoardCopy' has no member 'becomesTrue'`.

- [ ] **Step 3: Write the implementation**

Append inside `enum RoadmapBoardCopy` in `codepet/Models/RoadmapBoardCopy.swift`:

```swift
    // MARK: node panel

    /// What finishing this node moves forward. Deliberately a PER-PHASE contract, not a
    /// per-task one: without authored per-node fields we cannot honestly say what one task
    /// makes true, and a truthful phase-level statement beats an invented task-level one. The
    /// sentence always names its phase so the panel can't read as generic filler.
    static func becomesTrue(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String {
        let s: String
        switch phase {
        case .find:
            s = lang == .vi ? "bạn biết ai cần cái này và vì sao" : "you know who wants this and why"
        case .foundation:
            s = lang == .vi ? "những mảnh mà giai đoạn Xây dựng phụ thuộc vào đã có"
                            : "the pieces Build depends on exist"
        case .build:
            s = lang == .vi ? "sản phẩm tồn tại và chạy được" : "the product exists and runs"
        case .ship:
            s = lang == .vi ? "nó triển khai được, có tài liệu và bảo vệ được"
                            : "it's deployable, documented and defensible"
        case .launch:
            s = lang == .vi ? "nó đã công khai và tiếp cận được" : "it's public and reachable"
        case .grow:
            s = lang == .vi ? "nó lớn lên mà không cần bạn cầm tay từng bước"
                            : "it keeps growing without you steering every step"
        }
        let p = phase.label(lang)
        return lang == .vi ? "Hoàn thành việc này đẩy \(p) tiến lên: \(s)."
                           : "Finishing this moves \(p) forward: \(s)."
    }

    /// What "done" means for this node, from who owns it.
    static func toComplete(for who: TaskWho, _ lang: AppLanguage) -> String {
        switch who {
        case .does:  return lang == .vi ? "Codepet làm, bạn duyệt kết quả."
                                        : "Codepet runs it; you approve the result."
        case .draft: return lang == .vi ? "Codepet soạn bản nháp, bạn hoàn thiện."
                                        : "Codepet drafts it; you finalise."
        case .you:   return lang == .vi ? "Việc này bạn làm — Codepet sẽ hướng dẫn từng bước."
                                        : "You do this one — Codepet will walk you through it."
        }
    }

    /// Stand-in for "how to move this forward" when the generated task has no `detail`.
    static func howToFallback(for status: TaskStatus, _ lang: AppLanguage) -> String {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Codepet chạy được ngay bây giờ."
                                                : "Codepet can run this now."
        case .needsYou:      return lang == .vi ? "Cần bạn quyết — mở chat để được hướng dẫn."
                                                : "This needs your judgment — open chat to be walked through it."
        case .needsApproval: return lang == .vi ? "Bản nháp đã sẵn sàng để bạn xem lại."
                                                : "A draft is ready for your review."
        case .done:          return lang == .vi ? "Đã xong." : "Already done."
        case .blocked:       return lang == .vi ? "Xong các bước bên dưới trước."
                                                : "Clear the steps below first."
        }
    }

    /// The phase-window requirement's label — which phase has to settle before this node opens.
    static func phaseMustSettle(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String {
        lang == .vi ? "\(phase.label(lang)) phải xong trước"
                    : "\(phase.label(lang)) must be settled first"
    }

    /// The panel's primary button. Unlike `verb(for:)` this covers EVERY status: the card leaves
    /// done and blocked chip-less on purpose, but the panel always offers a way forward.
    static func panelActionLabel(for status: TaskStatus, _ lang: AppLanguage) -> String {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Bắt đầu" : "Start"
        case .needsYou:      return lang == .vi ? "Thêm ý của bạn" : "Add your input"
        case .needsApproval: return lang == .vi ? "Xem & duyệt" : "Review"
        case .done:          return lang == .vi ? "Mở kết quả" : "Open the result"
        case .blocked:       return lang == .vi ? "Làm bước đang chặn" : "Start what's blocking this"
        }
    }

    static func markComplete(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mình đã làm việc này rồi" : "I already did this"
    }

    /// The undo for `markComplete` — without it, marking a task done by mistake is a one-way
    /// door, since the mark-complete button hides itself once the task is done.
    static func markNotDone(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chưa xong — mở lại" : "Not done after all"
    }

    static func inProgress(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang chạy" : "In progress"
    }

    /// Why a suggestion is worth doing next. Derived, not authored: the unlock count is a
    /// structural leverage signal, which is honest in a way invented prose wouldn't be.
    static func suggestionReason(dept: String?, unlockCount: Int, lang: AppLanguage) -> String {
        let d = dept ?? (lang == .vi ? "Chung" : "General")
        if unlockCount == 0 {
            return lang == .vi ? "\(d) · chưa có bước nào chờ nó"
                               : "\(d) · nothing else waits on it yet"
        }
        if unlockCount == 1 {
            return lang == .vi ? "\(d) · mở khoá 1 bước sau" : "\(d) · unlocks 1 later step"
        }
        return lang == .vi ? "\(d) · mở khoá \(unlockCount) bước sau"
                           : "\(d) · unlocks \(unlockCount) later steps"
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapBoardCopyTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|\*\* TEST" | tail -10
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Models/RoadmapBoardCopy.swift codepetTests/RoadmapBoardCopyTests.swift
git commit -F - <<'EOF'
feat(roadmap): copy for the node panel, the lock and the suggestions

Per-phase "what becomes true" sentences, per-owner "to complete" lines, a
panel action label for every status (including the two the card leaves
chip-less), mark-complete plus its undo, in-progress, and the derived
suggestion reason. All EN + VI.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Split strict `blocker` from `escapeHatch`

**Files:**
- Modify: `codepet/Models/RoadmapGating.swift` (the `blocker` doc comment + body, ~lines 70-92; `actionable` stays)
- Modify: `codepet/Views/Roadmap/RoadmapView.swift` (the `.showBlocker` case in `dispatch`)
- Test: `codepetTests/RoadmapGatingTests.swift`

**Interfaces:**
- Consumes: `RoadmapGating.openPhases`, `founderStep`, `settled`; `RoadmapEngine.status`, `nextStep`
- Produces:
  - `RoadmapGating.blocker(for:in:) -> RoadmapTask?` — **strict**: the first unfinished dependency, or `founderStep` when phase-gated. No walk, no fallback. For DISPLAY.
  - `RoadmapGating.escapeHatch(for:in:) -> RoadmapTask?` — today's walked-forward behaviour. For DISPATCH only.

**Why:** `blocker` currently walks toward an actionable task and falls back to `nextStep`, so on a cyclic or dangling graph it can return a task with no dependency relationship to the tapped card. Harmless as a redirect target; a lie on the card face, which Task 6 puts it on. PR #52's final review logged this with exactly this fix.

- [ ] **Step 1: Write the failing tests**

In `codepetTests/RoadmapGatingTests.swift`, find the tests that currently assert the walked-forward behaviour of `blocker` (they mention walking to an actionable task, and the cycle case) and **rename their subject to `escapeHatch`** — the assertions and fixtures stay identical, only the function called changes. Then append:

```swift
    // MARK: strict blocker (display) vs escapeHatch (dispatch)

    /// The card face shows this string, so it must never name a task the tapped card has no
    /// dependency relationship with. On a cycle the strict blocker reports nothing rather than
    /// pointing somewhere misleading.
    func testStrictBlockerReturnsNilOnACycleRatherThanAnUnrelatedTask() {
        let a = t("a", .find, who: .you, deps: ["b"])
        let b = t("b", .find, who: .you, deps: ["a"])
        let elsewhere = t("z", .find)                     // actionable, unrelated to a/b
        let all = [a, b, elsewhere]
        // `a`'s only dependency is `b`, which is not done → strict blocker is `b`, full stop.
        XCTAssertEqual(RoadmapGating.blocker(for: a, in: all)?.id, "b")
        // The escape hatch may legitimately walk past the cycle to something actionable.
        XCTAssertNotNil(RoadmapGating.escapeHatch(for: a, in: all))
    }

    func testStrictBlockerOfAPhaseGatedTaskIsTheFounderStepItself() {
        // FIND's founder step is itself dependency-blocked, so the escape hatch walks past it
        // while the strict blocker still names it — that IS what's holding the window shut.
        let gate = t("y", .find, who: .you, deps: ["p"])
        let pre = t("p", .find)
        let later = t("b", .build)
        let all = [gate, pre, later]
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: all)?.id, "y")
        XCTAssertEqual(RoadmapGating.escapeHatch(for: later, in: all)?.id, "p")
    }

    func testStrictBlockerIsNilWhenNothingBlocks() {
        let a = t("a", .find)
        XCTAssertNil(RoadmapGating.blocker(for: a, in: [a]))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapGatingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `type 'RoadmapGating' has no member 'escapeHatch'`.

- [ ] **Step 3: Write the implementation**

In `codepet/Models/RoadmapGating.swift`, replace the existing `blocker(for:in:)` (its doc comment and body) with these two functions. Leave `actionable(_:in:avoiding:)` exactly as it is.

```swift
    /// The one thing standing in front of `task`, for DISPLAY — the card face and the node
    /// panel both render this by name, so it is strict: the first unfinished dependency, or the
    /// founder step holding the rolling window shut. No walk and no fallback, because a
    /// fallback would let a cyclic graph put an unrelated task's name on the card.
    ///
    /// NOT always the beacon: `RoadmapEngine.nextStep` minimises over the whole open window, so
    /// once the prefix spans more than one populated phase the beacon can sit in an EARLIER
    /// phase than this blocker (the earliest unsettled one). Both are legitimate.
    static func blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        openPhases(tasks).contains(task.phase)
            ? task.dependsOn.compactMap { id in tasks.first { $0.id == id && !$0.done } }.first
            : founderStep(in: tasks)
    }

    /// Where a locked card's tap should GO — the blocker walked forward to something the founder
    /// can act on today. A founder-owned step can itself be dependency-blocked, and handing the
    /// founder a second dead end defeats the escape hatch. Terminates on cyclic and
    /// self-referencing graphs (see `actionable`) and falls back to the beacon, which is nil only
    /// when nothing in the roadmap is actionable at all.
    static func escapeHatch(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        guard let candidate = blocker(for: task, in: tasks) else { return nil }
        return actionable(candidate, in: tasks, avoiding: [task.id])
    }
```

In `codepet/Views/Roadmap/RoadmapView.swift`, change the `.showBlocker` case of `dispatch` from `RoadmapGating.blocker` to `RoadmapGating.escapeHatch`:

```swift
        case .showBlocker:
            guard depth == 0, let blocker = RoadmapGating.escapeHatch(for: task, in: tasks) else { break }
            dispatch(blocker, depth: 1)
```

- [ ] **Step 4: Run the gating tests, then the full suite**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapGatingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|\*\* TEST" | tail -10
```

Expected: `** TEST SUCCEEDED **`. Then run the full suite (same command without `-only-testing`) and confirm no other test regressed — `RoadmapBoardView.peekText` also calls `blocker`, and under the strict version a cyclic-graph peek now omits the "Waiting on" line instead of naming an unrelated task. That is the intended improvement; if a test asserts the old behaviour, report it rather than reverting.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Models/RoadmapGating.swift codepet/Views/Roadmap/RoadmapView.swift codepetTests/RoadmapGatingTests.swift
git commit -F - <<'EOF'
refactor(roadmap): split strict blocker (display) from escapeHatch (dispatch)

blocker() served two masters: explaining why a card is locked, and choosing
where its tap should go. The walk-forward that makes the second job useful
makes the first one wrong — on a cyclic graph it can name a task with no
relationship to the card. Display now gets the strict answer; only dispatch
walks.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: `RoadmapEngine.suggestedNext`

**Files:**
- Modify: `codepet/Models/RoadmapEngine.swift` (add after `nextMoves`)
- Test: `codepetTests/RoadmapEngineSuggestedNextTests.swift` (create)

**Interfaces:**
- Consumes: `RoadmapEngine.status(for:in:)`, `nextStep(_:)`, `RoadmapGating.openPhases` (transitively, via `status`)
- Produces: `RoadmapEngine.suggestedNext(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask]`

**Why a new function:** `nextMoves` filters to `status == .codepetCanDo` AND departments that map to a specialist companion, so it excludes every `needsYou` task — including the beacon on most real boards. Reusing it would drop the founder's own next step from their suggestions. `nextMoves` is the chat fan-out and must not change.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/RoadmapEngineSuggestedNextTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapEngineSuggestedNextTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String?, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: dept)
    }

    func testEmptyWhenNothingIsActionable() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([], limit: 3).isEmpty)
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng", done: true)], limit: 3).isEmpty)
    }

    func testLimitZeroReturnsNothing() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng")], limit: 0).isEmpty)
    }

    /// The beacon and the suggestion list must never disagree, so nextStep is always first.
    func testBeaconIsAlwaysFirst() {
        let tasks = [t("d", .foundation, dept: "design"), t("f", .find, dept: "mkt")]
        let picked = RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id)
        XCTAssertEqual(picked.first, RoadmapEngine.nextStep(tasks)?.id)
        XCTAssertEqual(picked.first, "f")     // find(0) precedes foundation(1)
    }

    /// The gap that rules out nextMoves: a founder-owned task must be suggestible.
    func testIncludesNeedsYouAndNeedsApproval() {
        let you = t("y", .find, dept: "mkt", who: .you)
        let draft = t("dr", .find, dept: "design", drafted: true)
        let picked = RoadmapEngine.suggestedNext([you, draft], limit: 3).map(\.id)
        XCTAssertTrue(picked.contains("y"))
        XCTAssertTrue(picked.contains("dr"))
    }

    func testOneSuggestionPerDepartment() {
        let tasks = [t("e1", .find, dept: "eng"), t("e2", .find, dept: "eng"),
                     t("m1", .find, dept: "mkt")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["e1", "m1"])
    }

    func testRespectsLimit() {
        let tasks = [t("a", .find, dept: "eng"), t("b", .find, dept: "mkt"),
                     t("c", .find, dept: "design"), t("d", .find, dept: "sales")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 2).count, 2)
    }

    /// Confined to the open phase window, exactly like the beacon.
    func testConfinedToTheOpenWindow() {
        let gate = t("y", .find, dept: "mkt", who: .you)   // holds FIND shut
        let later = t("b", .build, dept: "eng")            // would otherwise be suggestible
        XCTAssertEqual(RoadmapEngine.suggestedNext([gate, later], limit: 3).map(\.id), ["y"])
    }

    /// Legacy dept-less tasks are eligible and don't collapse into one shared slot.
    func testDeptLessTasksEachTakeASlot() {
        let tasks = [t("a", .find, dept: nil), t("b", .find, dept: nil)]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["a", "b"])
    }

    func testBlockedTasksAreNeverSuggested() {
        let a = t("a", .find, dept: "eng")
        let b = t("b", .find, dept: "mkt", deps: ["a"])     // a not done → blocked
        XCTAssertEqual(RoadmapEngine.suggestedNext([a, b], limit: 3).map(\.id), ["a"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapEngineSuggestedNextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `type 'RoadmapEngine' has no member 'suggestedNext'`.

- [ ] **Step 3: Write the implementation**

Add to `enum RoadmapEngine` in `codepet/Models/RoadmapEngine.swift`, directly after `nextMoves`:

```swift
    /// Up to `limit` suggestions for the founder's next moves: the beacon first, then one
    /// actionable task per DISTINCT department, in roadmap order, all inside the open window.
    ///
    /// Deliberately NOT `nextMoves`. That one is the chat fan-out: it keeps only `codepetCanDo`
    /// tasks whose department maps to a specialist companion, which excludes every `needsYou`
    /// task — including the beacon on most real boards. Suggesting the founder's own next step
    /// is the whole point here, so this one admits `needsYou` and `needsApproval` too.
    ///
    /// `nextStep`'s result is forced into first place so the beacon card and this list can never
    /// disagree about what comes next. Legacy dept-less tasks each occupy their own slot rather
    /// than collapsing into one.
    static func suggestedNext(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask] {
        guard limit > 0 else { return [] }
        let actionable: Set<TaskStatus> = [.codepetCanDo, .needsYou, .needsApproval]
        let ordered = tasks.enumerated().sorted { a, b in
            a.element.phase.order != b.element.phase.order
                ? a.element.phase.order < b.element.phase.order
                : a.offset < b.offset
        }.map { $0.element }

        var out: [RoadmapTask] = []
        var seenDepts = Set<String>()
        func slot(_ task: RoadmapTask) -> String { task.dept ?? "__none__\(task.id)" }

        if let beacon = nextStep(tasks) {
            out.append(beacon)
            seenDepts.insert(slot(beacon))
        }
        for task in ordered where out.count < limit {
            guard !out.contains(where: { $0.id == task.id }),
                  actionable.contains(status(for: task, in: tasks)),
                  !seenDepts.contains(slot(task)) else { continue }
            seenDepts.insert(slot(task))
            out.append(task)
        }
        return Array(out.prefix(limit))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapEngineSuggestedNextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|\*\* TEST" | tail -10
```

Expected: `** TEST SUCCEEDED **`, 9 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineSuggestedNextTests.swift
git commit -F - <<'EOF'
feat(roadmap): suggestedNext — the beacon plus one move per department

nextMoves can't back the founder-facing suggestion list: it keeps only
codepetCanDo tasks in departments with a specialist companion, so it drops
every needsYou task — including the beacon on a real board. suggestedNext
admits needsYou and needsApproval, forces nextStep into first place so the
beacon and the list can't disagree, and leaves nextMoves untouched for chat.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: `RoadmapNodeDetail`

**Files:**
- Create: `codepet/Models/RoadmapNodeDetail.swift`
- Test: `codepetTests/RoadmapNodeDetailTests.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.status(for:in:)`; `RoadmapGating.openPhases`, `settled`, `founderStep`; all the `RoadmapBoardCopy` functions from Task 1; `DepartmentCatalog.find(_:)`; `TaskStatus.label(_:)`; `RoadmapPhase.label(_:)`
- Produces:
  - `struct NodeRequirement: Identifiable, Equatable` with `enum Kind { case task(String), phaseWindow(RoadmapPhase) }`, `kind`, `label: String`, `statusNote: String?`, `satisfied: Bool`, `id: String`
  - `struct RoadmapNodeDetail: Equatable` with `phaseLabel`, `deptName: String?`, `title`, `status`, `becomesTrue`, `howToMoveForward`, `toComplete`, `requiredFirst: [NodeRequirement]`, `unlocks: [String]`
  - `RoadmapNodeDetail.maxUnlocks: Int = 4`
  - `RoadmapNodeDetail.build(for task: RoadmapTask, in tasks: [RoadmapTask], lang: AppLanguage) -> RoadmapNodeDetail`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/RoadmapNodeDetailTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapNodeDetailTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does, dept: String? = "design",
                   detail: String = "", deps: [String] = [], done: Bool = false,
                   drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: detail, phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: dept)
    }

    func testHeaderFieldsComeFromTheTask() {
        let a = t("a", .foundation, dept: "design")
        let d = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        XCTAssertEqual(d.title, "a")
        XCTAssertEqual(d.phaseLabel, RoadmapPhase.foundation.label(.en).uppercased())
        XCTAssertEqual(d.deptName, DepartmentCatalog.find("design")?.name)
        XCTAssertEqual(d.status, RoadmapEngine.status(for: a, in: [a]))
    }

    /// A legacy task with no department must still build a panel.
    func testDeptLessTaskHasNilDeptName() {
        let a = t("a", .find, dept: nil)
        XCTAssertNil(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).deptName)
    }

    func testBecomesTrueIsThePhasesSentence() {
        let a = t("a", .build)
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).becomesTrue,
                       RoadmapBoardCopy.becomesTrue(.build, .en))
    }

    func testHowToMoveForwardUsesTheTaskDetailWhenPresent() {
        let a = t("a", .find, detail: "Ask five founders what they use today.")
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).howToMoveForward,
                       "Ask five founders what they use today.")
    }

    func testHowToMoveForwardFallsBackWhenDetailIsBlank() {
        let a = t("a", .find, detail: "   ")
        let d = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        XCTAssertEqual(d.howToMoveForward, RoadmapBoardCopy.howToFallback(for: d.status, .en))
    }

    func testToCompleteComesFromWho() {
        let a = t("a", .find, who: .you)
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).toComplete,
                       RoadmapBoardCopy.toComplete(for: .you, .en))
    }

    // MARK: requiredFirst

    /// Dependencies render whether or not they're met, so the panel shows progress rather than
    /// only obstacles — and each carries its own live status.
    func testDependenciesRenderWithLiveStatusAndSatisfaction() {
        let doneDep = t("d1", .find, done: true)
        let openDep = t("d2", .find, who: .you)
        let target = t("x", .find, deps: ["d1", "d2"])
        let all = [doneDep, openDep, target]
        let reqs = RoadmapNodeDetail.build(for: target, in: all, lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].kind, .task("d1"))
        XCTAssertTrue(reqs[0].satisfied)
        XCTAssertEqual(reqs[1].kind, .task("d2"))
        XCTAssertFalse(reqs[1].satisfied)
        XCTAssertEqual(reqs[1].statusNote, RoadmapEngine.status(for: openDep, in: all).label(.en))
    }

    func testDanglingDependencyIdsAreSkipped() {
        let a = t("a", .find, deps: ["ghost"])
        XCTAssertTrue(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).requiredFirst.isEmpty)
    }

    /// The phase window is a requirement too — and it names the phase that has to settle plus
    /// the step holding it shut, which is the one thing Cofounder's panel can't show.
    func testPhaseGatedTaskGetsAPhaseWindowRequirement() {
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        let all = [gate, later]
        let reqs = RoadmapNodeDetail.build(for: later, in: all, lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].kind, .phaseWindow(.find))
        XCTAssertFalse(reqs[0].satisfied)
        XCTAssertEqual(reqs[0].label, RoadmapBoardCopy.phaseMustSettle(.find, .en))
        XCTAssertEqual(reqs[0].statusNote, RoadmapBoardCopy.waitingOn("y", lang: .en))
    }

    /// The phase named is the earliest UNSETTLED phase, not the task's own phase.
    func testPhaseWindowRequirementNamesTheEarliestUnsettledPhase() {
        let f = t("f", .find)                      // Codepet-owned → FIND settles
        let gate = t("y", .foundation, who: .you)  // FOUNDATION is what's unsettled
        let later = t("s", .ship)
        let reqs = RoadmapNodeDetail.build(for: later, in: [f, gate, later], lang: .en).requiredFirst
        XCTAssertEqual(reqs.first?.kind, .phaseWindow(.foundation))
    }

    func testInWindowTaskGetsNoPhaseWindowRequirement() {
        let a = t("a", .find)
        let b = t("b", .find, deps: ["a"])
        let reqs = RoadmapNodeDetail.build(for: b, in: [a, b], lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].kind, .task("a"))
    }

    // MARK: unlocks

    func testUnlocksReadsReverseEdgesAndCaps() {
        let src = t("src", .find)
        let dependents = (1...6).map { t("u\($0)", .foundation, deps: ["src"]) }
        let d = RoadmapNodeDetail.build(for: src, in: [src] + dependents, lang: .en)
        XCTAssertEqual(d.unlocks.count, RoadmapNodeDetail.maxUnlocks)
        XCTAssertEqual(d.unlocks.first, "u1")
    }

    func testUnlocksEmptyWhenNothingDependsOnIt() {
        let a = t("a", .find)
        XCTAssertTrue(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).unlocks.isEmpty)
    }

    func testBuildsInVietnameseToo() {
        let a = t("a", .find, who: .you)
        let en = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        let vi = RoadmapNodeDetail.build(for: a, in: [a], lang: .vi)
        XCTAssertNotEqual(en.becomesTrue, vi.becomesTrue)
        XCTAssertNotEqual(en.toComplete, vi.toComplete)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapNodeDetailTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'RoadmapNodeDetail' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/RoadmapNodeDetail.swift`:

```swift
// codepet/Models/RoadmapNodeDetail.swift
import Foundation

/// One thing standing in front of a node: an unmet (or met) dependency, or the rolling phase
/// window itself. Met requirements are kept deliberately — the panel shows progress, not just
/// obstacles.
struct NodeRequirement: Identifiable, Equatable {
    enum Kind: Equatable {
        case task(String)                 // the dependency's task id
        case phaseWindow(RoadmapPhase)    // the earliest unsettled phase
    }
    let kind: Kind
    let label: String
    /// The requirement's own live state — a dependency's status label, or the step holding the
    /// window shut. nil when there is nothing more to say.
    let statusNote: String?
    let satisfied: Bool

    var id: String {
        switch kind {
        case .task(let id):      return "task:\(id)"
        case .phaseWindow(let p): return "phase:\(p.rawValue)"
        }
    }
}

/// Everything the node panel shows about one roadmap task, derived entirely from the task set —
/// no authored per-node fields, no network, no view types. Adapted from Cofounder's tech-tree
/// node view: what becomes true, how to move it, what counts as done, what's required first,
/// what it unlocks.
struct RoadmapNodeDetail: Equatable {
    let phaseLabel: String
    /// nil for legacy tasks saved before `dept` existed.
    let deptName: String?
    let title: String
    let status: TaskStatus
    let becomesTrue: String
    let howToMoveForward: String
    let toComplete: String
    let requiredFirst: [NodeRequirement]
    let unlocks: [String]

    /// Enough to show the shape of what this unblocks without turning the panel into a list.
    static let maxUnlocks = 4

    static func build(for task: RoadmapTask, in tasks: [RoadmapTask],
                      lang: AppLanguage) -> RoadmapNodeDetail {
        let status = RoadmapEngine.status(for: task, in: tasks)

        // Dependencies in their declared order. A dangling id is skipped rather than shown as a
        // phantom requirement — `RoadmapEngine.depsSatisfied` treats it as satisfied (fail-open),
        // so listing it would contradict the status.
        var requirements: [NodeRequirement] = task.dependsOn.compactMap { depId in
            guard let dep = tasks.first(where: { $0.id == depId }) else { return nil }
            return NodeRequirement(
                kind: .task(dep.id),
                label: dep.title,
                statusNote: RoadmapEngine.status(for: dep, in: tasks).label(lang),
                satisfied: dep.done)
        }

        // The window itself, when THAT is what's holding this node shut. The phase named is the
        // earliest unsettled one — not the task's own phase, which is merely downstream of it.
        if !RoadmapGating.openPhases(tasks).contains(task.phase),
           let blocking = RoadmapPhase.allCases.first(where: { !RoadmapGating.settled($0, in: tasks) }) {
            let step = RoadmapGating.founderStep(in: tasks)
            requirements.append(NodeRequirement(
                kind: .phaseWindow(blocking),
                label: RoadmapBoardCopy.phaseMustSettle(blocking, lang),
                statusNote: step.map { RoadmapBoardCopy.waitingOn($0.title, lang: lang) },
                satisfied: false))
        }

        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoadmapNodeDetail(
            phaseLabel: task.phase.label(lang).uppercased(),
            deptName: DepartmentCatalog.find(task.dept)?.name,
            title: task.title,
            status: status,
            becomesTrue: RoadmapBoardCopy.becomesTrue(task.phase, lang),
            howToMoveForward: detail.isEmpty
                ? RoadmapBoardCopy.howToFallback(for: status, lang)
                : detail,
            toComplete: RoadmapBoardCopy.toComplete(for: task.who, lang),
            requiredFirst: requirements,
            unlocks: tasks.filter { $0.dependsOn.contains(task.id) }
                .prefix(maxUnlocks).map(\.title))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapNodeDetailTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|\*\* TEST" | tail -10
```

Expected: `** TEST SUCCEEDED **`, 14 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Models/RoadmapNodeDetail.swift codepetTests/RoadmapNodeDetailTests.swift
git commit -F - <<'EOF'
feat(roadmap): RoadmapNodeDetail — what a node means, derived

Everything the node panel shows, derived from the task set alone: the phase's
contract, how to move the task forward (its own detail, or a status-shaped
fallback), what completion means for its owner, the dependencies WITH their
live status, and what it unlocks. Adds the one thing Cofounder's panel can't
show — the phase window as an explicit requirement, naming the step holding
it shut.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: The node panel, and tap opens it

**Files:**
- Create: `codepet/Views/Overview/TaskNodePanel.swift`
- Modify: `codepet/Views/Roadmap/RoadmapView.swift` (state, the sheet, `roadmapBody`'s `onTaskTap`)

**Interfaces:**
- Consumes: `RoadmapNodeDetail.build(for:in:lang:)` and `NodeRequirement` (Task 4); `RoadmapBoardCopy.panelActionLabel/markComplete/markNotDone/inProgress` (Task 1); `CompanyStore.runningTaskIds`, `toggleTaskDone(id:)`
- Produces: `TaskNodePanel(task:accent:onAction:onMarkDoneToggle:)`

SwiftUI views have no unit tests here; verification is that the suite still builds and passes, plus Task 8's visual pass.

- [ ] **Step 1: Create the panel**

Create `codepet/Views/Overview/TaskNodePanel.swift`:

```swift
// codepet/Views/Overview/TaskNodePanel.swift
import SwiftUI

/// What a roadmap node MEANS — adapted from Cofounder's tech-tree node view. Content is derived
/// by `RoadmapNodeDetail`; this view only lays it out, so the wording stays unit-tested.
struct TaskNodePanel: View {
    let task: RoadmapTask
    let accent: Color
    /// Run the node's primary action (the caller routes it through `RoadmapDispatch`).
    let onAction: (RoadmapTask) -> Void
    /// Flip the task's done flag — "I already did this", and its undo.
    let onMarkDoneToggle: (RoadmapTask) -> Void

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    /// Rebuilt from the live task set, so approving or marking done updates the open panel.
    private var detail: RoadmapNodeDetail {
        RoadmapNodeDetail.build(for: liveTask, in: tasks, lang: lang)
    }
    /// The task as it currently exists in the store — the value passed in can go stale while the
    /// panel is open (a run finishes, a draft lands).
    private var liveTask: RoadmapTask { tasks.first { $0.id == task.id } ?? task }
    private var isRunning: Bool { companyStore.runningTaskIds.contains(task.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(lang == .vi ? "ĐIỀU GÌ THÀNH THẬT" : "WHAT BECOMES TRUE") {
                        Text(detail.becomesTrue)
                    }
                    section(lang == .vi ? "LÀM SAO ĐỂ TIẾN LÊN" : "HOW TO MOVE THIS FORWARD") {
                        Text(detail.howToMoveForward)
                    }
                    section(lang == .vi ? "THẾ NÀO LÀ XONG" : "TO COMPLETE") {
                        Text(detail.toComplete)
                    }
                    if !detail.requiredFirst.isEmpty {
                        section(lang == .vi ? "CẦN TRƯỚC" : "REQUIRED FIRST") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(detail.requiredFirst) { requirementRow($0) }
                            }
                        }
                    }
                    if !detail.unlocks.isEmpty {
                        section(lang == .vi ? "MỞ KHOÁ" : "UNLOCKS") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(detail.unlocks, id: \.self) { title in
                                    Text("• \(title)")
                                }
                            }
                        }
                    }
                }
                .font(CodepetTheme.inter(12.5))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.vertical, 18)
            }
            footer
        }
        .frame(width: 460, height: 560)
        .background(CodepetTheme.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(detail.phaseLabel)
                    .font(CodepetTheme.inter(10)).tracking(1.4)
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(CodepetTokens.well))
                if let dept = detail.deptName {
                    Text(dept).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                Spacer()
                statusPill
            }
            Text(detail.title)
                .font(CodepetTheme.inter(19, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            if isRunning { ProgressView().controlSize(.mini) }
            if detail.status == .blocked && !isRunning {
                Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
            }
            Text(isRunning ? RoadmapBoardCopy.inProgress(lang) : detail.status.label(lang))
        }
        .font(CodepetTheme.inter(11, weight: .medium))
        .foregroundColor(taskStatusTint(detail.status))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(taskStatusTint(detail.status).opacity(0.12)))
    }

    @ViewBuilder
    private func requirementRow(_ r: NodeRequirement) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(r.satisfied ? RoadmapPalette.done : CodepetTheme.mutedText)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).foregroundColor(CodepetTheme.primaryText)
                if let note = r.statusNote {
                    Text(note).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                onAction(liveTask)
            } label: {
                Text(RoadmapBoardCopy.panelActionLabel(for: detail.status, lang))
                    .font(CodepetTheme.inter(12.5, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(accent))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(accent))
            }
            .buttonStyle(.plain)
            .disabled(isRunning)

            // A drafted task's correct action is Approve; marking it done here would silently
            // discard generated work, so the affordance hides itself.
            if !liveTask.drafted {
                Button {
                    onMarkDoneToggle(liveTask)
                } label: {
                    Text(liveTask.done ? RoadmapBoardCopy.markNotDone(lang)
                                       : RoadmapBoardCopy.markComplete(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .stroke(CodepetTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(CodepetTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1.2)
                .foregroundColor(CodepetTheme.mutedText)
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Wire it into `RoadmapView`**

In `codepet/Views/Roadmap/RoadmapView.swift`:

Add next to the other `@State` properties:

```swift
    /// The node whose panel is open. Tapping a card opens this rather than firing the action —
    /// a card should be readable before it starts an agent.
    @State private var panelTask: RoadmapTask?
```

Add the sheet next to the existing `.sheet(item: $openDeliverable)`:

```swift
        .sheet(item: $panelTask) { node in
            TaskNodePanel(task: node, accent: accent,
                          onAction: { dispatch($0) },
                          onMarkDoneToggle: { t in
                              panelTask = nil
                              Task { await companyStore.toggleTaskDone(id: t.id) }
                          })
        }
```

In `roadmapBody`, change the board's tap handler from dispatching to opening the panel — leave `OverviewChromeRow`'s `onStart`/`onOpenTask` dispatching directly, which keeps the beacon a one-click Start:

```swift
            RoadmapBoardView(tasks: tasks, companionName: companionName,
                             founderName: founderName,
                             projectName: displayProjectName,
                             tagline: oneLiner,
                             accent: accent,
                             onTaskTap: { panelTask = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: Build**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. If the compiler reports the panel `body` is too complex to type-check, extract `header`, `footer` or the section list into further computed properties — do not simplify away any section.

- [ ] **Step 4: Run the full suite**

Same command as Task 0 Step 3. Expected: `** TEST SUCCEEDED **` with the count unchanged from Task 4 (this task adds no tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Views/Overview/TaskNodePanel.swift codepet/Views/Roadmap/RoadmapView.swift
git commit -F - <<'EOF'
feat(overview): the node panel, opened by tapping a card

Tapping a card now opens a panel that explains the node — what it moves
forward, how to act on it, what done means, what's required first (each
dependency with its live status, plus the phase window when that's the
blocker), and what it unlocks — with the action inside it. Previously a
mis-click started an agent run and nothing anywhere explained a task.

The chrome row's DO THIS NEXT keeps its direct Start, so the fast path for
the current move is unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Lock glyph, named blocker, and In progress on the card

**Files:**
- Modify: `codepet/Views/Overview/RoadmapCardView.swift` (two new inputs; the label block inside `body`)
- Modify: `codepet/Views/Overview/RoadmapBoardView.swift` (pass the two new inputs)

**Interfaces:**
- Consumes: `RoadmapGating.blocker(for:in:)` (strict, Task 2); `RoadmapBoardCopy.inProgress` (Task 1); `CompanyStore.runningTaskIds`
- Produces: `RoadmapCardView(task:status:isCurrent:herePhrase:pulsing:accent:blockerTitle:isRunning:onTap:)`

- [ ] **Step 1: Add the two inputs to the card**

In `codepet/Views/Overview/RoadmapCardView.swift`, add after `let accent: Color`:

```swift
    /// The strict blocker's title, shown on a locked card's face so it explains itself without
    /// a hover. nil when nothing resolves (a dangling dependency, or a cycle).
    let blockerTitle: String?
    /// This task's agent run is in flight — `CompanyStore.runningTaskIds`.
    let isRunning: Bool
```

- [ ] **Step 2: Replace the label block inside `body`**

Replace the `if let verb = … else if let quiet = …` block (immediately after the title `Text`) with:

```swift
                if isRunning {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(RoadmapBoardCopy.inProgress(lang))
                    }
                    .font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                } else if let verb = RoadmapBoardCopy.verb(for: status, lang) {
                    chip(verb)
                } else if isLocked, let blockerTitle {
                    // The blocker's bare title, not "Waiting on: <title>" — at 10pt in the
                    // card's ~150pt text column the prefix would eat the name it exists to
                    // show. The full phrasing lives in the hover peek and the node panel.
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
                        Text(blockerTitle).lineLimit(1).truncationMode(.tail)
                    }
                    .font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(maxWidth: 150, alignment: .leading)
                } else if let quiet = RoadmapBoardCopy.quietLabel(for: status, lang: lang) {
                    Text(quiet)
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                }
```

- [ ] **Step 3: Pass the inputs from the board**

In `codepet/Views/Overview/RoadmapBoardView.swift`, add the store so the running set is reachable — put it with the other environment properties:

```swift
    @EnvironmentObject var companyStore: CompanyStore
```

Then in `diagram(_:)`, extend the `RoadmapCardView(...)` construction inside `ForEach(l.nodes)`:

```swift
                RoadmapCardView(task: n.task, status: status, isCurrent: isCurrent,
                                herePhrase: herePhrase,
                                pulsing: pulseIds.contains(n.task.id),
                                accent: accent,
                                blockerTitle: status == .blocked
                                    ? RoadmapGating.blocker(for: n.task, in: tasks)?.title
                                    : nil,
                                isRunning: companyStore.runningTaskIds.contains(n.task.id),
                                onTap: { onTaskTap(n.task) })
```

`RoadmapBoardView.swift:206` is the **only** `RoadmapCardView(` call site in the repo — verified with `grep -rn "RoadmapCardView(" codepet codepetTests`, which returns exactly that one line. There are no `#Preview` blocks to update, so no other construction needs the two new arguments.

- [ ] **Step 4: Build and run the full suite**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -8
```

Expected `** BUILD SUCCEEDED **`, then the full suite from Task 0 Step 3, count unchanged.

- [ ] **Step 5: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Views/Overview/RoadmapCardView.swift codepet/Views/Overview/RoadmapBoardView.swift
git commit -F - <<'EOF'
feat(overview): locked cards name their blocker; running cards say so

A locked card carries a lock glyph and the blocking step's name instead of the
generic "Needs earlier steps", using the STRICT blocker so it can never name an
unrelated task. A card whose run is in flight shows a spinner and "In progress",
matching what DepartmentDetailView already does with the same
CompanyStore.runningTaskIds set.

Note: walkThroughTask is a chat send, not a task run, so it deliberately does
not enter runningTaskIds — a needsYou walk-through shows no spinner.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: Suggested Next ×3 in the chrome row

**Files:**
- Modify: `codepet/Views/Overview/OverviewChromeRow.swift` (`beacon`, remove `alsoNeedsYou`, add the suggestion rows)

**Interfaces:**
- Consumes: `RoadmapEngine.suggestedNext(_:limit:)` (Task 3); `RoadmapBoardCopy.suggestionReason(dept:unlockCount:lang:)` (Task 1); `DepartmentCatalog.find(_:)`
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Swap the beacon source and drop `alsoNeedsYou`**

In `codepet/Views/Overview/OverviewChromeRow.swift`, replace the `beacon` computed property and the `alsoNeedsYou` computed property with:

```swift
    /// The beacon plus up to two more moves, one per department. `suggestedNext` guarantees
    /// `nextStep` first, so the hero card and the list below it can never disagree.
    private var suggestions: [RoadmapTask] { RoadmapEngine.suggestedNext(tasks, limit: 3) }
    private var beacon: RoadmapTask? { suggestions.first }
```

Every other use of `beacon` (the `currentPhase` chip, the beacon card) keeps working unchanged.

- [ ] **Step 2: Replace the `alsoNeedsYou` block in `beaconCard`**

In `beaconCard(_:)`, replace the `if let also = alsoNeedsYou { … }` block with:

```swift
            ForEach(suggestions.dropFirst(), id: \.id) { s in
                Button { onOpenTask(s) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title)
                            .font(CodepetTheme.inter(11.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                            .lineLimit(1)
                        Text(RoadmapBoardCopy.suggestionReason(
                                dept: DepartmentCatalog.find(s.dept)?.name,
                                unlockCount: tasks.filter { $0.dependsOn.contains(s.id) }.count,
                                lang: lang))
                            .font(CodepetTheme.inter(10))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(s.title)
            }
```

- [ ] **Step 3: Build and run the full suite**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -8
```

Expected `** BUILD SUCCEEDED **`, then the full suite, count unchanged.

`alsoNeedsYou` has exactly two references — its definition at `OverviewChromeRow.swift:35` and its single use at `:145` inside `beaconCard` — verified with `grep -rn "alsoNeedsYou" codepet`. Both go. The progress card's `needsYou` **count** at `:30` is independent (`tasks.filter { !$0.done && !$0.drafted && $0.who == .you }.count`) and must stay exactly as it is.

- [ ] **Step 4: Commit**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git add codepet/Views/Overview/OverviewChromeRow.swift
git commit -F - <<'EOF'
feat(overview): three ranked next moves instead of one

The beacon keeps its filled Start; below it up to two more moves appear, one
per department, each with a derived reason — the count of later steps it
unlocks, which is a structural leverage signal rather than invented prose.
Replaces the single "Also needs you" line.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: Verify end to end

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything
- Produces: a signed running build plus a visual checklist handed to the founder

- [ ] **Step 1: Full suite**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility && pkill -x codepet
xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" \
  -allowProvisioningUpdates 2>&1 | grep -E "Test Case.*failed|Failing tests|Executed [0-9]+ test|\*\* TEST" | tail -8
```

Expected: `** TEST SUCCEEDED **`, ~659 tests (629 baseline + 7 copy + 3 gating + 9 suggestedNext + 14 node detail, minus any gating test renamed rather than added). **Recount from the summary line and report the real number** rather than asserting this one.

- [ ] **Step 2: Launch the signed build**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
APP=$(xcodebuild -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
ps aux | grep "[c]odepet.app" || open "$APP/codepet.app"
```

If a sibling session's instance is already running, do NOT kill it — report and stop; build-only verification is acceptable.

- [ ] **Step 3: Hand the visual checklist to the founder**

This environment cannot screenshot the app (Screen Recording is denied; the accessibility fallback reports no windows), so the visual pass is a handoff, not a self-check. Ask for these specifically:

1. Tapping any card opens the panel instead of firing the action; the panel's button fires it.
2. On a locked card (Build/Ship), the panel's REQUIRED FIRST names the phase that must settle AND the step holding it shut.
3. A locked card's face shows a lock plus the blocking step's name, not "Needs earlier steps".
4. The chrome row shows the beacon plus up to two more moves, each with an "unlocks N later steps" line.
5. "I already did this" on the Find task marks it done, and Foundation then unlocks.
6. Re-opening that task's panel offers "Not done after all", and using it re-locks Foundation.
7. Tapping Start on a Codepet-owned task shows a spinner and "In progress" on the card while it runs.
8. The board is still vertically centred after the chrome row grew (this is what the predecessor branch's layout-based centring buys — confirm it held).

- [ ] **Step 4: Report**

Report the executed-test count, each checklist item's result, and any deviation from this plan.

- [ ] **Step 5: Push and open a PR**

```bash
cd /Users/monatruong/Developer/codepet-node-legibility
git push -u origin feat/roadmap-node-legibility
gh pr create --base feat/overview-roadmap-focus \
  --title "Roadmap node legibility: what each node means, adapted from Cofounder" \
  --body "See docs/superpowers/specs/2026-08-03-roadmap-node-legibility-design.md. Targets feat/overview-roadmap-focus (PR #52), not main — it builds on that branch's gating and touches the same four files. Retarget to main once #52 merges."
```

---

## Notes for the executor

- **`runningTaskIds` already exists** and is already consumed by `DepartmentDetailView`. Do not add a second run-tracking mechanism, and do not make "running" a `TaskStatus` case.
- **Strict `blocker` vs `escapeHatch` is the whole point of Task 2.** If a later task needs "somewhere useful to send the founder", that is `escapeHatch`. If it needs "what is actually in the way", that is `blocker`.
- **Copy never goes inline in a view.** Every string a founder can read belongs in `RoadmapBoardCopy` with both languages, because that is the only place it gets tested.
- **The chrome row grows in Task 7.** That is safe only because centring is layout-based on this branch's parent; if the map drifts off-centre afterwards, the regression is in the framing, not the chrome row.

## Two deliberate departures from the spec

Both are recorded here so a reviewer reads them as decisions rather than drift.

1. **The spec says mark-complete is "hidden when already `.done`". This plan shows its undo there instead** (`markNotDone`, "Not done after all"). Following the spec literally makes marking a task done by mistake a one-way door: the button that could reverse it hides itself the moment it succeeds. `toggleTaskDone` already toggles, so the undo costs one label and no new store code. The founder can still not un-approve a task whose deliverable reached the library — this only reopens the task.

2. **The spec's file list includes `codepet/Managers/CompanyStore.swift`; this plan changes no store code.** `runningTaskIds` already exists there as `@Published private(set)`, maintained by `runTask` and `runFirstRunAction`, and `toggleTaskDone(id:)` already exists and persists. The spec was written before I read those, and the store turned out to already carry both halves of what §2 and §4 needed.
