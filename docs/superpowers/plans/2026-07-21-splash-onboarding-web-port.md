# Splash + Onboarding Web-Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native game-framed splash and 6-field first-run onboarding with faithful, English-only ports of the web dark cinematic splash + 8-step cinematic onboarding.

**Architecture:** View-layer only — `CompanyBrief` already holds every field the web wizard collects. New pure models (`OnboardingContent`, `OnboardingReveal`), one new store method (`scaffoldFromOnboarding`), a rewritten `SplashView`, and a new `OnboardingView` + 5 sub-views wired into the unchanged `ContentView` gate. Fail-open at the analysis step (the `scaffoldRoadmap` CF is undeployed).

**Tech Stack:** Swift 5 / SwiftUI (macOS 13+), XCTest. Web source of truth: `~/Desktop/Codepet v1.2` (`components/Splash.tsx`, `components/Onboarding.tsx`, `lib/data.ts`, `lib/onboarding/firstRun.ts`, `app/globals.css`).

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port` (off `origin/main` = `108b240`).
- **Toolchain:** scheme **`codepet`** (lowercase), no xcodegen, `@testable import codepet`. Build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. Test: `... xcodebuild test ... 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3` → `** TEST SUCCEEDED **`. Run **FOREGROUND**. SourceKit cross-file diagnostics ("Cannot find type X", "No such module XCTest") are FALSE POSITIVES.
- **iCloud git:** `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`; on hang, `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` and retry; commit via `-F <msgfile>`.
- **Language:** English-only. Do NOT add Vietnamese / `uiLanguage` branching to any new splash/onboarding copy. (Deliberate exception to the app's VI/EN convention.)
- **Exact web copy** — headings, body, button labels, notes, option labels are transcribed verbatim from the web source. Do not paraphrase.
- **Web→native color map** (web CSS var → native): `--page #f8f7f3`→`CodepetTheme.pageBackground`; `--surface #ffffff`→`CodepetTheme.surface`; `--surface-2 #fcfbf8`→`OnboardingContent.Palette.surface2`; `--well #f1efe9`→`.well`; `--hairline #ece9e2`→`CodepetTheme.hairline`; `--t-1 #1f1b15`→`CodepetTheme.primaryText`; `--t-2 #332e27`→`CodepetTheme.bodyText`; `--t-3 #776f65`→`CodepetTheme.mutedText`; `--t-4 #a79e92`→`.faint`; `--accent #7c3aed`→`CodepetTheme.accentPurple`; `--accent-deep #5b27b0`→`.accentDeep`; `--accent-tint #eee6fd`→`.accentTint`; `--accent-line #d9c9f7`→`.accentLine`; cold-open bg `#100a26`→`.coldBg`.
- **Keep** `CompanyOnboardingView` (Settings edit-brief editor) — do NOT delete or modify it.
- Don't touch Giang's Build Coach files or `CLAUDE.md`. `Color(hex:)` (Character.swift), `.pixelSystem(size:weight:)` and `CodepetTheme.body(_)` (CodepetTheme.swift) already exist.

---

### Task 1: Import splash + onboarding art assets

**Files:**
- Create: `codepet/Assets.xcassets/Onboarding/splash.imageset/{Contents.json, splash.jpg}`
- Create: `codepet/Assets.xcassets/Onboarding/ob-team.imageset/{Contents.json, ob-team.jpg}` and likewise `ob-couch`, `ob-chess`, `ob-drummer`, `ob-observatory`, `ob-isometric`, `ob-boardroom` (8 imagesets total).

**Interfaces:**
- Produces: asset names `splash`, `ob-team`, `ob-couch`, `ob-chess`, `ob-drummer`, `ob-observatory`, `ob-isometric`, `ob-boardroom` (resolvable via `Image("...")`).

- [ ] **Step 1: Copy the source images into imageset folders**

```bash
cd ~/Documents/codepet-rebuild-wt
WEB="/Users/monatruong/Desktop/Codepet v1.2"
DST="codepet/Assets.xcassets/Onboarding"
mkdir -p "$DST/splash.imageset"
cp "$WEB/public/splash.jpg" "$DST/splash.imageset/splash.jpg"
for n in team couch chess drummer observatory isometric boardroom; do
  mkdir -p "$DST/ob-$n.imageset"
  cp "$WEB/public/onboarding/ob-$n.jpg" "$DST/ob-$n.imageset/ob-$n.jpg"
done
ls "$DST"/*/  # expect 8 imageset dirs each holding one .jpg
```
Expected: 8 `.imageset` dirs, each containing its `.jpg`.

- [ ] **Step 2: Write each imageset's Contents.json**

For `splash.imageset/Contents.json` (repeat for each, substituting the filename):
```json
{
  "images" : [
    { "filename" : "splash.jpg", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

```bash
cd ~/Documents/codepet-rebuild-wt
DST="codepet/Assets.xcassets/Onboarding"
write() { printf '{\n  "images" : [\n    { "filename" : "%s", "idiom" : "universal" }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "$1" > "$2"; }
write "splash.jpg" "$DST/splash.imageset/Contents.json"
for n in team couch chess drummer observatory isometric boardroom; do
  write "ob-$n.jpg" "$DST/ob-$n.imageset/Contents.json"
done
# Assets.xcassets uses folder-based discovery (no per-image project.pbxproj entries needed).
```

- [ ] **Step 3: Build to confirm the asset catalog compiles with the new imagesets**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **` (no "unassigned children" / asset warnings for the new sets).

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Assets.xcassets/Onboarding
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: import splash + onboarding cinematic art assets

splash.jpg + 7 ob-*.jpg from the web app into Assets.xcassets/Onboarding.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: OnboardingContent — ported constants + palette

**Files:**
- Create: `codepet/Models/OnboardingContent.swift`
- Test: `codepetTests/OnboardingContentTests.swift`

**Interfaces:**
- Produces:
  - `enum OnboardingContent` with statics: `roles: [(label:String,key:String)]` (8), `tech: [(label:String,key:String)]` (3), `stages: [String]` (6), `stageNotes: [String]` (6), `categories: [String]` (8), `departments: [(name:String,dot:Color)]` (8), `stepArt: [String]` (8, indices 0–7), `analysisLines: [String]` (4), `total = 8`, `defaultStageIndex = 2`.
  - `enum OnboardingContent.Palette` with `Color` statics: `surface2`, `well`, `faint`, `accentDeep`, `accentTint`, `accentLine`, `coldBg`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/OnboardingContentTests.swift
import XCTest
@testable import codepet

final class OnboardingContentTests: XCTestCase {
    func testCountsAndKeyValues() {
        XCTAssertEqual(OnboardingContent.roles.count, 8)
        XCTAssertEqual(OnboardingContent.roles.first?.key, "founder")
        XCTAssertEqual(OnboardingContent.tech.count, 3)
        XCTAssertEqual(OnboardingContent.stages.count, 6)
        XCTAssertEqual(OnboardingContent.stageNotes.count, OnboardingContent.stages.count)
        XCTAssertEqual(OnboardingContent.stages[2], "Private beta")
        XCTAssertEqual(OnboardingContent.defaultStageIndex, 2)
        XCTAssertEqual(OnboardingContent.categories.count, 8)
        XCTAssertEqual(OnboardingContent.departments.count, 8)
        XCTAssertEqual(OnboardingContent.departments.first?.name, "Engineering")
        XCTAssertEqual(OnboardingContent.analysisLines.count, 4)
        XCTAssertEqual(OnboardingContent.total, 8)
        // step art covers steps 0...7 and every name resolves to an imageset base
        XCTAssertEqual(OnboardingContent.stepArt.count, 8)
        XCTAssertEqual(OnboardingContent.stepArt[0], "ob-team")
        XCTAssertEqual(OnboardingContent.stepArt[6], "ob-boardroom")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingContentTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "Cannot find 'OnboardingContent' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/OnboardingContent.swift
import SwiftUI

/// Ported constants for the first-run cinematic onboarding (verbatim from the web
/// app's lib/data.ts + Onboarding.tsx). English-only by design.
enum OnboardingContent {
    /// (display label, stable key) — the numbered single-select on the role step.
    static let roles: [(label: String, key: String)] = [
        ("Founder building a product", "founder"),
        ("Engineer / developer", "eng"),
        ("Designer who codes", "design"),
        ("Product manager", "product"),
        ("Marketing / growth", "mkt"),
        ("Operations / business", "ops"),
        ("Solo / indie hacker", "solo"),
        ("Something else", "other"),
    ]
    /// (display label, stable key) — how hands-on with the code.
    static let tech: [(label: String, key: String)] = [
        ("I write the code myself", "hands"),
        ("I direct engineers / build with AI", "direct"),
        ("I'm not on the technical side", "non"),
    ]
    static let stages = [
        "Just an idea", "Prototype", "Private beta", "Public beta", "Launched", "Growing",
    ]
    static let stageNotes = [
        "Perfect — I'll focus on shaping the idea and pressure-testing it.",
        "Great — let's turn the prototype into something testable.",
        "I'll help you run a tight private beta and learn fast.",
        "I'll focus on measurement, polish, and getting to launch.",
        "I'll help you grow distribution and tighten the funnel.",
        "I'll focus on scaling what already works.",
    ]
    static let categories = [
        "Web app", "Mobile app", "SaaS", "Dev tool", "AI / ML", "Marketplace", "Game", "Other",
    ]
    /// (name, dot color) — cold-open department preview chips (DEPTS + DEPT_DOT).
    static let departments: [(name: String, dot: Color)] = [
        ("Engineering", Color(hex: "#6ea8ff")),
        ("Marketing", Color(hex: "#ff9d6b")),
        ("Operations", Color(hex: "#4fe0cf")),
        ("Finance", Color(hex: "#f2c94c")),
        ("Legal", Color(hex: "#b98cf0")),
        ("Design", Color(hex: "#d08cf5")),
        ("Sales", Color(hex: "#7ea8ff")),
        ("Support", Color(hex: "#7fd694")),
    ]
    /// Per-step left-panel art (STEP_ART), steps 0...7. Step 0 & 7 reuse ob-team.
    static let stepArt = [
        "ob-team", "ob-couch", "ob-chess", "ob-drummer",
        "ob-observatory", "ob-isometric", "ob-boardroom", "ob-team",
    ]
    static let analysisLines = [
        "Reading what you told me…",
        "Mapping it across 8 departments",
        "Cross-checking your space & stage",
        "Drafting your roadmap to launch",
    ]
    static let total = 8
    static let defaultStageIndex = 2

    /// Web CSS theme vars that CodepetTheme doesn't already expose, mapped 1:1.
    enum Palette {
        static let surface2 = Color(hex: "#fcfbf8")   // --surface-2
        static let well = Color(hex: "#f1efe9")       // --well
        static let faint = Color(hex: "#a79e92")      // --t-4
        static let accentDeep = Color(hex: "#5b27b0") // --accent-deep
        static let accentTint = Color(hex: "#eee6fd") // --accent-tint
        static let accentLine = Color(hex: "#d9c9f7") // --accent-line
        static let coldBg = Color(hex: "#100a26")     // cold-open / splash bg
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingContentTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/OnboardingContent.swift codepetTests/OnboardingContentTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingContent — ported onboarding constants + palette

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: OnboardingReveal — pure task-based reveal builder

**Files:**
- Create: `codepet/Models/OnboardingReveal.swift`
- Test: `codepetTests/OnboardingRevealTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask` (existing — `RoadmapTask(id:title:detail:phase:who:dependsOn:done:drafted:)`, `.title`, `.done`; `RoadmapPhase.build`, `TaskWho.does`).
- Produces: `struct OnboardingReveal: Equatable { let ok: Bool; let taskCount: Int; let sampleTasks: [String] }`, `static let empty`, `static func build(tasks: [RoadmapTask]) -> OnboardingReveal`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/OnboardingRevealTests.swift
import XCTest
@testable import codepet

final class OnboardingRevealTests: XCTestCase {
    private func t(_ id: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task " + id, detail: "", phase: .build, who: .does, done: done)
    }

    func testEmptyTasksIsNotOk() {
        XCTAssertEqual(OnboardingReveal.build(tasks: []), OnboardingReveal.empty)
        XCTAssertFalse(OnboardingReveal.build(tasks: []).ok)
    }
    func testCountsNotDoneAndSamplesFirstThree() {
        let tasks = [t("a"), t("b"), t("c", done: true), t("d"), t("e")]
        let r = OnboardingReveal.build(tasks: tasks)
        XCTAssertTrue(r.ok)                              // scaffold produced tasks
        XCTAssertEqual(r.taskCount, 4)                   // done 'c' excluded from count
        XCTAssertEqual(r.sampleTasks, ["Task a", "Task b", "Task d"]) // ≤3 not-done titles, 'c' skipped
    }
    func testAllDoneStillOkButZeroSamples() {
        let r = OnboardingReveal.build(tasks: [t("a", done: true)])
        XCTAssertTrue(r.ok)                              // non-empty ⇒ ok
        XCTAssertEqual(r.taskCount, 0)
        XCTAssertEqual(r.sampleTasks, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingRevealTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "Cannot find 'OnboardingReveal' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/OnboardingReveal.swift
import Foundation

/// The first-run reveal summary (wizard step 7), adapted to the native task model.
/// Native has no "departments" in the product (the Overview is phase-based), so the
/// reveal is derived from the scaffolded roadmap tasks. Pure; unit-tested.
struct OnboardingReveal: Equatable {
    /// True when the scaffold produced any tasks (vs. the fail-open empty fallback).
    let ok: Bool
    /// Open (not-done) task count across the roadmap.
    let taskCount: Int
    /// Up to 3 open task titles, for the reveal rows.
    let sampleTasks: [String]

    static let empty = OnboardingReveal(ok: false, taskCount: 0, sampleTasks: [])

    static func build(tasks: [RoadmapTask]) -> OnboardingReveal {
        guard !tasks.isEmpty else { return .empty }
        let open = tasks.filter { !$0.done }
        return OnboardingReveal(
            ok: true,
            taskCount: open.count,
            sampleTasks: Array(open.prefix(3).map { $0.title })
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingRevealTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/OnboardingReveal.swift codepetTests/OnboardingRevealTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingReveal — pure task-based first-run reveal builder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: CompanyStore.scaffoldFromOnboarding

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (add one method after `generateRoadmap`, ~line 129)
- Test: `codepetTests/CompanyStoreScaffordOnboardingTests.swift`

**Interfaces:**
- Consumes: existing private `saver`, `generateRoadmap()`, `company`, `companyId`, `hydrationToken`, public `onboardingToken`; `CompanyBrief`, `OnboardingReveal` (Task 3).
- Produces: `func scaffoldFromOnboarding(brief: CompanyBrief, token: Int) async -> OnboardingReveal` — persists the brief, sets `company.brief`, runs the fail-open `generateRoadmap()`, returns `OnboardingReveal.build(tasks: company.tasks)`. Does NOT change `isOnboarding`. Token-guarded (discards on mismatch, returning `.empty`).

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreScaffordOnboardingTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreScaffordOnboardingTests: XCTestCase {
    private func task(_ id: String) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task " + id, detail: "", phase: .build, who: .does)
    }

    func testPersistsBriefScaffoldsAndReturnsRevealWithoutLeavingOnboarding() async {
        var savedBrief: CompanyBrief?
        let s = CompanyStore(
            loader: { _ in .empty },
            saver: { _, b in savedBrief = b; return true },
            roadmapFetcher: { _ in [self.task("a"), self.task("b")] }
        )
        await s.hydrate(companyId: "u")     // fresh account ⇒ isOnboarding true
        XCTAssertTrue(s.isOnboarding)
        let brief = CompanyBrief(projectName: "Codepet", oneLiner: "run your company with AI")
        let reveal = await s.scaffoldFromOnboarding(brief: brief, token: s.onboardingToken)
        XCTAssertEqual(savedBrief?.projectName, "Codepet")   // brief persisted
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertEqual(s.company.tasks.count, 2)              // roadmap scaffolded
        XCTAssertTrue(reveal.ok)
        XCTAssertEqual(reveal.taskCount, 2)
        XCTAssertEqual(reveal.sampleTasks, ["Task a", "Task b"])
        XCTAssertTrue(s.isOnboarding)                        // still in the wizard (reveal shows next)
    }

    func testEmptyScaffoldReturnsNotOk() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             roadmapFetcher: { _ in [] })     // fail-open: no tasks
        await s.hydrate(companyId: "u")
        let reveal = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "X"), token: s.onboardingToken)
        XCTAssertFalse(reveal.ok)
        XCTAssertEqual(reveal.taskCount, 0)
        XCTAssertTrue(s.company.tasks.isEmpty)
    }

    func testStaleTokenAfterSwitchDiscards() async {
        var savedTo: [String] = []
        let s = CompanyStore(loader: { _ in .empty },
                             saver: { cid, _ in savedTo.append(cid); return true },
                             roadmapFetcher: { _ in [self.task("a")] })
        await s.hydrate(companyId: "A")
        let aToken = s.onboardingToken
        s.reset()
        await s.hydrate(companyId: "B")
        let reveal = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "A-Co"), token: aToken)
        XCTAssertEqual(reveal, OnboardingReveal.empty)       // discarded
        XCTAssertFalse(savedTo.contains("A"))                // A's brief not written after switch
        XCTAssertEqual(s.company.brief.projectName, nil)     // B (empty) not clobbered
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreScaffordOnboardingTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "value of type 'CompanyStore' has no member 'scaffoldFromOnboarding'".

- [ ] **Step 3: Add the method**

Insert into `codepet/Managers/CompanyStore.swift` immediately after the `generateRoadmap()` method (after its closing brace near line 129):

```swift
    /// First-run scaffold: persist the collected brief, then run the fail-open
    /// roadmap generation — WITHOUT leaving onboarding (the wizard's reveal step
    /// renders next). Token-guarded like finishOnboarding: an account switch
    /// during the persist/scaffold awaits discards (returns .empty), so one
    /// account's brief/tasks can't land under another's doc. Mirrors the web's
    /// scaffoldFromOnboarding; the reveal is derived from the resulting tasks.
    func scaffoldFromOnboarding(brief: CompanyBrief, token: Int) async -> OnboardingReveal {
        guard token == hydrationToken, let cid = companyId else { return .empty }
        _ = await saver(cid, brief)
        guard token == hydrationToken else { return .empty }
        company.brief = brief
        await generateRoadmap()
        guard token == hydrationToken else { return .empty }
        return OnboardingReveal.build(tasks: company.tasks)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreScaffordOnboardingTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreScaffordOnboardingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: CompanyStore.scaffoldFromOnboarding — persist brief + fail-open scaffold, no exit

Token-guarded; returns an OnboardingReveal from the scaffolded tasks without
flipping isOnboarding (the wizard reveal step renders next).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 5: SplashView — dark cinematic rewrite

**Files:**
- Rewrite: `codepet/Views/SplashView.swift` (replace the whole file)

**Interfaces:**
- Consumes: `Image("splash")` (Task 1), `Color(hex:)`, `.pixelSystem(size:weight:)`, `CodepetTheme.body(_)`, `OnboardingContent.Palette.coldBg` (Task 2).
- Produces: `struct SplashView` — UNCHANGED public API `SplashView(onContinue: (() -> Void)? = nil)` (ContentView calls `SplashView(onContinue:)` and bare `SplashView()`). No `SoundManager`, no `PetCharacter` cast.

- [ ] **Step 1: Replace the file**

```swift
// codepet/Views/SplashView.swift
import SwiftUI

/// Brand splash — the first screen before sign-in. Faithful port of the web
/// `Splash` (dark cinematic: splash.jpg Ken Burns + scrim + pixel title +
/// purple pill). Click anywhere OR "Let's go" advances. English-only.
struct SplashView: View {
    var onContinue: (() -> Void)? = nil

    @State private var appear = false
    @State private var kenBurns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()

            // Slow Ken-Burns image layer.
            GeometryReader { geo in
                Image("splash")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()

            // Readability scrim: flat darkening + a soft center vignette.
            Color(hex: "#0d0522").opacity(0.52).ignoresSafeArea()
            RadialGradient(colors: [.clear, Color(hex: "#0d0522").opacity(0.5)],
                           center: UnitPoint(x: 0.5, y: 0.46),
                           startRadius: 0, endRadius: 620)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Text("Codepet")
                    .font(.pixelSystem(size: 80, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "#a078ff").opacity(0.55), radius: 17)
                    .shadow(color: Color(hex: "#220e40").opacity(0.7), radius: 0, x: 0, y: 3)
                Text("Let's learn how to run your company with AI.")
                    .font(CodepetTheme.body(20))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .shadow(color: Color(hex: "#0a041e").opacity(0.7), radius: 9)
                Button { onContinue?() } label: {
                    Text("Let's go")
                        .font(CodepetTheme.body(14))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: OnboardingContent.Palette.accentDeep.opacity(0.5), radius: 13, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 32)
                Spacer()
                Text("click anywhere to continue")
                    .font(CodepetTheme.body(11))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 22)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { onContinue?() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) { appear = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }
}

#Preview {
    SplashView(onContinue: {})
}
```

- [ ] **Step 2: Build to verify it compiles + no SoundManager reference remains**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. Then confirm the tangle is gone:
Run: `grep -n "SoundManager\|PetCharacter\|char-" codepet/Views/SplashView.swift || echo "clean"`
Expected: `clean`.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/SplashView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: SplashView — dark cinematic web splash (drop game cast + SoundManager)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 6: OnboardingStageSlider — draggable stage ruler

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingStageSlider.swift`
- Test: `codepetTests/OnboardingStageSliderTests.swift`

**Interfaces:**
- Consumes: `OnboardingContent.stages`, `.stageNotes`, `.Palette` (Task 2).
- Produces:
  - `enum StageSliderMath { static func stageIndex(atX x: CGFloat, width: CGFloat, count: Int) -> Int }` — pure, unit-tested (clamps 0…count-1).
  - `struct OnboardingStageSlider: View` — `init(stageIndex: Binding<Int>)`; draggable + arrow-key ruler with major/minor ticks, thumb, the `.rngticks` stage labels, and the active `.obnote`.

- [ ] **Step 1: Write the failing test (pure math)**

```swift
// codepetTests/OnboardingStageSliderTests.swift
import XCTest
@testable import codepet

final class OnboardingStageSliderTests: XCTestCase {
    func testMapsXToNearestStageAndClamps() {
        // width 500, 6 stages ⇒ segment 100pt; snap to nearest index.
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 0, width: 500, count: 6), 0)
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 500, width: 500, count: 6), 5)
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 240, width: 500, count: 6), 2) // 0.48*5=2.4→2
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 260, width: 500, count: 6), 3) // 0.52*5=2.6→3
        XCTAssertEqual(StageSliderMath.stageIndex(atX: -50, width: 500, count: 6), 0) // clamp low
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 999, width: 500, count: 6), 5) // clamp high
    }
    func testZeroWidthIsSafe() {
        XCTAssertEqual(StageSliderMath.stageIndex(atX: 10, width: 0, count: 6), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingStageSliderTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "Cannot find 'StageSliderMath' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Views/Onboarding/OnboardingStageSlider.swift
import SwiftUI

/// Pure mapping from a pointer x-position to the nearest stage index. Extracted
/// for unit testing; the view calls it on drag.
enum StageSliderMath {
    static func stageIndex(atX x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 1 else { return 0 }
        let f = max(0, min(1, x / width))
        return Int((f * CGFloat(count - 1)).rounded())
    }
}

/// The stage step's draggable ruler (web `StageBar` + `.rngticks` + `.obnote`).
/// Major ticks at each stage, minor ticks between; drag or ← → to change.
struct OnboardingStageSlider: View {
    @Binding var stageIndex: Int
    @State private var dragging = false

    private let stages = OnboardingContent.stages
    private var n: Int { stages.count }
    private let step = 4 // minor ticks between stages

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let frac = n > 1 ? CGFloat(stageIndex) / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    // base track
                    Capsule().fill(OnboardingContent.Palette.well).frame(height: 3)
                    // progress
                    Capsule()
                        .fill(LinearGradient(colors: [CodepetTheme.accentPurple, OnboardingContent.Palette.accentDeep],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, w * frac), height: 3)
                    // ticks
                    ForEach(0...( (n - 1) * step ), id: \.self) { t in
                        let tf = CGFloat(t) / CGFloat((n - 1) * step)
                        let isMajor = t % step == 0
                        let filled = tf <= frac + 0.001
                        Capsule()
                            .fill(filled ? (isMajor ? OnboardingContent.Palette.accentDeep : CodepetTheme.accentPurple)
                                         : Color(hex: isMajor ? "#cbc3b2" : "#dad3c5"))
                            .frame(width: isMajor ? 2.5 : 2, height: isMajor ? 18 : 9)
                            .position(x: w * tf, y: 24)
                    }
                    // thumb
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(CodepetTheme.accentPurple, lineWidth: 3))
                        .overlay(Circle().fill(CodepetTheme.accentPurple).padding(6))
                        .frame(width: 26, height: 26)
                        .shadow(color: CodepetTheme.accentPurple.opacity(0.4), radius: 6, y: 4)
                        .position(x: w * frac, y: 24)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        stageIndex = StageSliderMath.stageIndex(atX: v.location.x, width: w, count: n)
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 48)
            .focusable(true)
            .onMoveCommand { dir in
                if dir == .right { stageIndex = min(n - 1, stageIndex + 1) }
                if dir == .left { stageIndex = max(0, stageIndex - 1) }
            }

            // stage labels
            HStack {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(CodepetTheme.body(10))
                        .foregroundColor(i == stageIndex ? OnboardingContent.Palette.accentDeep : OnboardingContent.Palette.faint)
                        .fontWeight(i == stageIndex ? .bold : .regular)
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : (i == n - 1 ? .trailing : .center))
                }
            }

            // active-stage note
            Text(OnboardingContent.stageNotes[stageIndex])
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.leading, 13)
                .overlay(Rectangle().fill(OnboardingContent.Palette.accentLine).frame(width: 2), alignment: .leading)
                .padding(.top, 10)
        }
    }
}
```

- [ ] **Step 4: Run the test + build**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingStageSliderTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **` (this compiles the view too).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingStageSlider.swift codepetTests/OnboardingStageSliderTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingStageSlider — draggable stage ruler + pure StageSliderMath

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 7: OnboardingOptionList — numbered single-select

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingOptionList.swift`

**Interfaces:**
- Consumes: `OnboardingContent.Palette`, `CodepetTheme`.
- Produces: `struct OnboardingOptionList: View` — `init(options: [(label: String, key: String)], selectedKey: Binding<String>)`. Renders `.obopt` rows: two-digit index badge, label, selected check circle; tap sets `selectedKey`.

- [ ] **Step 1: Write the implementation**

```swift
// codepet/Views/Onboarding/OnboardingOptionList.swift
import SwiftUI

/// Numbered single-select list (web `.obopts`/`.obopt`), used by the role and
/// tech steps. Selection is by stable key.
struct OnboardingOptionList: View {
    let options: [(label: String, key: String)]
    @Binding var selectedKey: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let sel = selectedKey == opt.key
                Button { selectedKey = opt.key } label: {
                    HStack(spacing: 13) {
                        Text(String(format: "%02d", i + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(sel ? OnboardingContent.Palette.accentDeep : OnboardingContent.Palette.faint)
                            .frame(width: 16, alignment: .leading)
                        Text(opt.label)
                            .font(CodepetTheme.body(14))
                            .fontWeight(.medium)
                            .foregroundColor(CodepetTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            Circle()
                                .stroke(sel ? Color.clear : CodepetTheme.hairline, lineWidth: 1.5)
                                .background(Circle().fill(sel ? CodepetTheme.accentPurple : Color.clear))
                                .frame(width: 20, height: 20)
                            if sel {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(sel ? OnboardingContent.Palette.accentTint : CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(sel ? CodepetTheme.accentPurple : CodepetTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingOptionList.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingOptionList — numbered single-select rows

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 8: OnboardingColdOpen — full-bleed hero (step 0)

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingColdOpen.swift`

**Interfaces:**
- Consumes: `Image("ob-team")` (Task 1), `OnboardingContent.departments`, `.Palette`, `CodepetTheme`.
- Produces: `struct OnboardingColdOpen: View` — `init(onStart: @escaping () -> Void, onSkip: @escaping () -> Void)`. Full-bleed dark hero: skip pill, headline with gradient punchline, body, "Codepet runs all 8 departments" + dept chips, "Set up my company" button.

- [ ] **Step 1: Write the implementation**

```swift
// codepet/Views/Onboarding/OnboardingColdOpen.swift
import SwiftUI

/// Step 0 — the cinematic cold-open (full-bleed hero), distinct from the question
/// screens. Faithful port of the web `.ob-cold` block. English-only.
struct OnboardingColdOpen: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    @State private var kenBurns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()
            GeometryReader { geo in
                Image("ob-team")
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()
            // left-weighted readability scrim
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#0d0522").opacity(0.96), location: 0.0),
                    .init(color: Color(hex: "#0d0522").opacity(0.9), location: 0.34),
                    .init(color: Color(hex: "#0d0522").opacity(0.62), location: 0.56),
                    .init(color: Color(hex: "#0d0522").opacity(0.12), location: 0.86),
                ],
                startPoint: .leading, endPoint: .trailing
            ).ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    (Text("Let's build your company — ")
                        .foregroundColor(.white)
                     + Text("not just your code.")
                        .foregroundColor(Color(hex: "#a78bfa")))
                        .font(.system(size: 46, weight: .bold))
                        .lineSpacing(3)
                        .shadow(color: Color(hex: "#0c0424").opacity(0.55), radius: 30)
                    Text("Codepet runs the whole company around your product, department by department — and does the work with you, so you always understand what's happening.")
                        .font(CodepetTheme.body(16))
                        .foregroundColor(Color(hex: "#f0eefc").opacity(0.95))
                        .lineSpacing(4)
                        .frame(maxWidth: 500, alignment: .leading)
                        .padding(.top, 20)

                    Text("CODEPET RUNS ALL \(OnboardingContent.departments.count) DEPARTMENTS")
                        .font(CodepetTheme.body(11)).fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 26).padding(.bottom, 11)
                    deptChips.frame(maxWidth: 540, alignment: .leading)

                    Button(action: onStart) {
                        Text("Set up my company")
                            .font(CodepetTheme.body(14)).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30).padding(.vertical, 12)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                            .shadow(color: OnboardingContent.Palette.accentDeep.opacity(0.5), radius: 13, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 30)
                    Spacer()
                }
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.leading, 90)
                .padding(.trailing, 40)
                Spacer()
            }

            Button(action: onSkip) {
                Text("Skip onboarding →")
                    .font(CodepetTheme.body(12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 32).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }

    private var deptChips: some View {
        // simple wrapping flow via a fixed-column grid keeps it dependency-free
        FlowChips(items: OnboardingContent.departments.map { ($0.name, $0.dot) })
    }
}

/// Minimal wrapping chip row (no external deps) for the cold-open department chips.
private struct FlowChips: View {
    let items: [(String, Color)]
    var body: some View {
        // Fixed adaptive grid; chips wrap and left-align.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 200), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 7) {
                    Circle().fill(it.1).frame(width: 7, height: 7)
                        .shadow(color: it.1, radius: 4)
                    Text(it.0).font(CodepetTheme.body(12)).foregroundColor(.white.opacity(0.86))
                }
                .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingColdOpen.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingColdOpen — full-bleed cinematic hero (step 0)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 9: OnboardingAnalysisView — step 6 analysis animation

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingAnalysisView.swift`

**Interfaces:**
- Consumes: `OnboardingContent.analysisLines`, `CodepetTheme`, `.Palette`.
- Produces: `struct OnboardingAnalysisView: View` — `init(projectName: String, shown: Int, done: Bool)`. Renders the heading, the streaming `.anrow` lines (checkmark for completed, spinner for the live one). `shown`/`done` are driven by the parent controller (Task 11) so timing lives in one place.

- [ ] **Step 1: Write the implementation**

```swift
// codepet/Views/Onboarding/OnboardingAnalysisView.swift
import SwiftUI

/// Step 6 body — "byte is reading {project}…" with streaming analysis lines.
/// The controller drives `shown` (how many lines revealed) and `done`.
struct OnboardingAnalysisView: View {
    let projectName: String
    let shown: Int
    let done: Bool
    @State private var spin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("byte is reading \(projectName.isEmpty ? "your project" : projectName)…")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text("Turning what you told me into a full company plan.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<max(0, min(shown, OnboardingContent.analysisLines.count)), id: \.self) { i in
                    let live = !done && i == shown - 1
                    HStack(spacing: 10) {
                        ZStack {
                            if live {
                                Circle().stroke(OnboardingContent.Palette.accentLine, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                Circle().trim(from: 0, to: 0.25)
                                    .stroke(CodepetTheme.accentPurple, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                    .rotationEffect(.degrees(spin ? 360 : 0))
                            } else {
                                Circle().fill(CodepetTheme.accentPurple).frame(width: 16, height: 16)
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        Text(OnboardingContent.analysisLines[i])
                            .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingAnalysisView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingAnalysisView — step 6 streaming analysis lines

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 10: OnboardingRevealView — step 7 reveal

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingRevealView.swift`

**Interfaces:**
- Consumes: `OnboardingReveal` (Task 3), `OnboardingContent.stages`, `CodepetTheme`, `.Palette`.
- Produces: `struct OnboardingRevealView: View` — `init(name: String, roleLabel: String, stageIndex: Int, reveal: OnboardingReveal)`. Renders "Here's your company, {name}." + the founder/stage line + task rows (from `reveal.sampleTasks`) OR the 3 generic value-props when `!reveal.ok`.

- [ ] **Step 1: Write the implementation**

```swift
// codepet/Views/Onboarding/OnboardingRevealView.swift
import SwiftUI

/// Step 7 — the reveal. Task-based (native has no departments); falls back to the
/// generic value-props when the fail-open scaffold produced nothing (`!reveal.ok`).
struct OnboardingRevealView: View {
    let name: String
    let roleLabel: String
    let stageIndex: Int
    let reveal: OnboardingReveal

    private var role: String { (roleLabel.isEmpty ? "founder" : roleLabel).lowercased() }
    private var stage: String { OnboardingContent.stages[stageIndex].lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Here's your company\(name.isEmpty ? "" : ", \(name)").")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            (Text("You're a ") + Text(role).bold()
             + Text(" at the ") + Text(stage).bold()
             + Text(reveal.ok
                    ? " stage. I built your roadmap — \(reveal.taskCount) tasks already prepped:"
                    : " stage. I built your roadmap and staffed your departments — here's what I'll take off your plate:"))
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 9) {
                if reveal.ok && !reveal.sampleTasks.isEmpty {
                    ForEach(reveal.sampleTasks, id: \.self) { title in
                        valueRow(title, bold: true)
                    }
                } else {
                    valueRow("A living roadmap", suffix: " — staged from \"\(OnboardingContent.stages[stageIndex])\" to launch.")
                    valueRow("Real work, done with you", suffix: " — tasks prepped across your departments.")
                    valueRow("You stay in control", suffix: " — I draft & build; you approve.")
                }
            }
            .padding(.top, 16)
        }
    }

    private func valueRow(_ head: String, suffix: String = "", bold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("✦")
                .font(.system(size: 11))
                .foregroundColor(OnboardingContent.Palette.accentDeep)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(OnboardingContent.Palette.accentTint))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OnboardingContent.Palette.accentLine, lineWidth: 1))
            (Text(head).bold().foregroundColor(CodepetTheme.primaryText) + Text(suffix).foregroundColor(CodepetTheme.bodyText))
                .font(CodepetTheme.body(13))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingRevealView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingRevealView — step 7 task-based reveal + generic fallback

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 11: OnboardingView controller + ContentView wiring

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingView.swift`
- Modify: `codepet/App/ContentView.swift` (the `isOnboarding` branch, ~line 44–46: `CompanyOnboardingView()` → `OnboardingView()`)

**Interfaces:**
- Consumes: `CompanyStore` (`isOnboarding`, `onboardingToken`, `scaffoldFromOnboarding(brief:token:)`, `finishOnboarding(brief:token:)`, `skipOnboarding()`), all sub-views (Tasks 6–10), `OnboardingContent`, `OnboardingReveal`, `CompanyBrief`, `Image(...)` art (Task 1).
- Produces: `struct OnboardingView: View` — no required init args (reads `@EnvironmentObject companyStore`). Drives `step` 0–7, holds an `ObDraft`, builds a `CompanyBrief`, runs step-6 scaffold + reveal, and calls `finishOnboarding`/`skipOnboarding`.

- [ ] **Step 1: Write the controller**

```swift
// codepet/Views/Onboarding/OnboardingView.swift
import SwiftUI

/// First-run cinematic onboarding — faithful English-only port of the web
/// `Onboarding` (8 steps 0–7). Replaces the 6-field CompanyOnboardingView at
/// first run; the reveal/scaffold is fail-open (scaffoldRoadmap CF undeployed).
struct OnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore

    struct ObDraft {
        var name = "", role = "", roleLabel = "", tech = ""
        var projName = "", oneLiner = "", audience = "", link = "", notes = ""
        var categories: [String] = []
        var stageIndex = OnboardingContent.defaultStageIndex
    }

    @State private var step = 0
    @State private var d = ObDraft()
    @State private var anShown = 0
    @State private var anDone = false
    @State private var reveal: OnboardingReveal = .empty
    @State private var slow = false

    private func brief() -> CompanyBrief {
        CompanyBrief(
            founderName: d.name.isEmpty ? nil : d.name,
            role: d.roleLabel.isEmpty ? nil : d.roleLabel,
            tech: OnboardingContent.tech.first(where: { $0.key == d.tech })?.label,
            stage: OnboardingContent.stages[d.stageIndex],
            projectName: d.projName.isEmpty ? nil : d.projName,
            oneLiner: d.oneLiner.isEmpty ? nil : d.oneLiner,
            notes: d.notes.isEmpty ? nil : d.notes,
            link: d.link.isEmpty ? nil : d.link,
            categories: d.categories.isEmpty ? nil : d.categories,
            audience: d.audience.isEmpty ? nil : d.audience
        )
    }

    var body: some View {
        Group {
            if step == 0 {
                OnboardingColdOpen(onStart: { step = 1 }, onSkip: skip)
            } else {
                card
            }
        }
        .background(CodepetTheme.pageBackground.ignoresSafeArea())
    }

    // Two-panel card: art left (42%), form right.
    private var card: some View {
        HStack(spacing: 0) {
            Image(OnboardingContent.stepArt[min(step, OnboardingContent.stepArt.count - 1)])
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .clipped()
                .id(step) // re-fade on step change
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if step != 6 {
                        Button(action: { step = max(0, step - 1) }) {
                            Text("← Back").font(CodepetTheme.body(12)).foregroundColor(CodepetTheme.mutedText)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button(action: skip) {
                        Text("Skip onboarding →").font(CodepetTheme.body(12)).foregroundColor(CodepetTheme.mutedText)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                ScrollView { stepBody.frame(maxWidth: 600, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer.frame(maxWidth: 600)
            }
            .padding(.horizontal, 64).padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(CodepetTheme.surface)
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 1:
            heading("First — what should I call you?", "I'll use it when I walk you through your company.")
            label("Your name")
            textField("e.g. Mona", text: $d.name)
        case 2:
            heading("Which best describes you?", "This shapes how I explain each department to you.")
            OnboardingOptionList(options: OnboardingContent.roles, selectedKey: Binding(
                get: { d.role },
                set: { k in d.role = k; d.roleLabel = OnboardingContent.roles.first(where: { $0.key == k })?.label ?? "" }))
        case 3:
            heading("How hands-on are you with the code?", "So I know how deep to go on the technical side.")
            OnboardingOptionList(options: OnboardingContent.tech, selectedKey: $d.tech)
        case 4:
            heading("Now — what are you building?",
                    "A name and one clear sentence — that line is what I read to tailor your whole plan. Everything else is optional but sharpens it.")
            label("Project name"); textField("e.g. Codepet", text: $d.projName)
            label("In one sentence, what is it?")
            textField("A macOS companion that helps founders run their company with AI", text: $d.oneLiner)
            label("What kind of product is it? (optional)")
            chips(OnboardingContent.categories, selected: d.categories) { c in
                if d.categories.contains(c) { d.categories.removeAll { $0 == c } } else { d.categories.append(c) }
            }
            label("Who's it for? (optional)")
            textField("e.g. solo founders shipping their first product", text: $d.audience)
            label("Link (optional — website, repo, or Figma)")
            textField("https://", text: $d.link)
            label("Anything else to read? (optional — paste a pitch, README, or notes)")
            TextEditor(text: $d.notes)
                .font(CodepetTheme.body(14)).frame(minHeight: 74)
                .scrollContentBackground(.hidden)   // hide TextEditor's default backing (macOS 13+)
                .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
        case 5:
            heading("Where are you today?", "This sets your starting point on the roadmap.")
            OnboardingStageSlider(stageIndex: $d.stageIndex)
        case 6:
            OnboardingAnalysisView(projectName: d.projName, shown: anShown, done: anDone)
        default:
            OnboardingRevealView(name: d.name, roleLabel: d.roleLabel, stageIndex: d.stageIndex, reveal: reveal)
        }
    }

    // Progress + primary action.
    @ViewBuilder private var footer: some View {
        let pct = CGFloat(step + 1) / CGFloat(OnboardingContent.total)
        HStack(spacing: 14) {
            if step != 6 || (anDone && reveal.ok) || (anDone && !reveal.ok) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OnboardingContent.Palette.well).frame(height: 5)
                        Capsule().fill(CodepetTheme.accentPurple).frame(width: geo.size.width * pct, height: 5)
                    }
                }.frame(width: 150, height: 5)
                Text("Step \(step + 1) of \(OnboardingContent.total)")
                    .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
            } else if slow {
                Text("Still building your company…")
                    .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
            }
            Spacer()
            primaryButton
        }
        .padding(.top, 22)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 1: bigButton("Continue", enabled: !d.name.trimmed.isEmpty) { step = 2 }
        case 2: bigButton("Continue", enabled: !d.role.isEmpty) { step = 3 }
        case 3: bigButton("Continue", enabled: !d.tech.isEmpty) { step = 4 }
        case 4: bigButton("Continue", enabled: !d.projName.trimmed.isEmpty && !d.oneLiner.trimmed.isEmpty) { step = 5 }
        case 5: bigButton("Analyze my project", enabled: true) { startAnalysis() }
        case 6: if anDone { bigButton("See what I found", enabled: true) { step = 7 } }
        default: bigButton("See my company", enabled: true) { finish() }
        }
    }

    // MARK: actions

    private func startAnalysis() {
        step = 6; anShown = 0; anDone = false; slow = false; reveal = .empty
        let token = companyStore.onboardingToken
        let capturedBrief = brief()
        // stream the lines
        Task { @MainActor in
            for i in 0..<OnboardingContent.analysisLines.count {
                anShown = i + 1
                try? await Task.sleep(nanoseconds: 640_000_000)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            anDone = true
        }
        // run the real (fail-open) scaffold in parallel; min-display already covered by the lines
        Task { @MainActor in
            let slowTimer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !anDone { slow = true }
            }
            reveal = await companyStore.scaffoldFromOnboarding(brief: capturedBrief, token: token)
            slowTimer.cancel()
            slow = false
        }
    }

    private func finish() {
        let token = companyStore.onboardingToken
        Task { await companyStore.finishOnboarding(brief: brief(), token: token) }
    }
    private func skip() { Task { await companyStore.skipOnboarding() } }

    // MARK: small view helpers

    private func heading(_ h: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(h).font(.system(size: 20, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
            Text(sub).font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
        }.padding(.bottom, 4)
    }
    private func label(_ t: String) -> some View {
        Text(t).font(CodepetTheme.body(12)).fontWeight(.semibold)
            .foregroundColor(CodepetTheme.primaryText).padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func textField(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .textFieldStyle(.plain).font(CodepetTheme.body(14))
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }
    private func chips(_ items: [String], selected: [String], toggle: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 200), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { c in
                let sel = selected.contains(c)
                Button { toggle(c) } label: {
                    Text(c).font(CodepetTheme.body(13)).fontWeight(sel ? .semibold : .medium)
                        .foregroundColor(sel ? OnboardingContent.Palette.accentDeep : CodepetTheme.bodyText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(sel ? OnboardingContent.Palette.accentTint : OnboardingContent.Palette.surface2))
                        .overlay(Capsule().stroke(sel ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
    private func bigButton(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(title).font(CodepetTheme.body(13)).fontWeight(.semibold).foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.accentPurple))
                .opacity(enabled ? 1 : 0.38)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
```

- [ ] **Step 2: Wire ContentView**

In `codepet/App/ContentView.swift`, the `isOnboarding` branch currently reads:
```swift
            } else if companyStore.isOnboarding {
                // Fresh account — first-run founder interview before the shell.
                CompanyOnboardingView()
            } else {
```
Replace `CompanyOnboardingView()` with `OnboardingView()`:
```swift
            } else if companyStore.isOnboarding {
                // Fresh account — first-run cinematic onboarding before the shell.
                OnboardingView()
            } else {
```
(Leave everything else in ContentView unchanged. Do NOT remove the `CompanyOnboardingView` type — Settings still uses it.)

- [ ] **Step 3: Build the whole app**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Full test suite (nothing regressed; new suites pass)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingView.swift codepet/App/ContentView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F - <<'MSG'
feat: OnboardingView — cinematic 8-step first-run flow, wired into ContentView

Replaces the 6-field CompanyOnboardingView at first run (it survives only as
the Settings edit-brief editor). Step 6 scaffold is fail-open.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

---

## Final verification
After Task 11: `AppShellView` unchanged; a fresh account routes `ContentView → OnboardingView` (cinematic 8 steps) → `AppShellView`; the splash is the dark cinematic web splash; Settings still opens the 6-field `CompanyOnboardingView` to edit the brief; full build + test green. Manual smoke (guest / "Continue without signing in" reaches onboarding): cold-open → steps → analysis (fail-open) → reveal (generic value-props while the CF is undeployed) → shell.

## Self-Review
**Spec coverage:** splash rewrite (Task 5 ✓); onboarding constants (Task 2 ✓); reveal builder task-based (Task 3 ✓); `scaffoldFromOnboarding` persist+fail-open+no-exit+token-guard (Task 4 ✓); cold-open + dept chips (Task 8 ✓); option lists (Task 7 ✓); stage slider (Task 6 ✓); analysis animation (Task 9 ✓); reveal view + generic fallback (Task 10 ✓); controller + ObDraft→brief + ContentView gate (Task 11 ✓); assets (Task 1 ✓); EN-only (Global Constraints ✓); Settings editor kept (Task 11 Step 2 note ✓); SoundManager dropped (Task 5 ✓).

**Placeholder scan:** none — every code step carries complete code; every command has expected output.

**Type consistency:** `OnboardingReveal{ok,taskCount,sampleTasks}` + `.empty`/`.build` used identically in Tasks 3, 4, 10, 11. `OnboardingContent` statics (`roles`/`tech` as `(label,key)`, `stages`, `stageNotes`, `categories`, `departments` as `(name,dot)`, `stepArt`, `analysisLines`, `total`, `defaultStageIndex`, `Palette.*`) referenced consistently across Tasks 2/5/6/7/8/9/10/11. `scaffoldFromOnboarding(brief:token:)->OnboardingReveal` and `finishOnboarding(brief:token:)`/`skipOnboarding()`/`onboardingToken` match CompanyStore (verified against source). `StageSliderMath.stageIndex(atX:width:count:)` defined (Task 6) and used only there.

**Known notes for the executor:** (a) SwiftUI view tasks are verified by `xcodebuild build` (no unit tests); pure logic (Tasks 2/3/4/6-math) is unit-tested. (b) Implementers keep stalling on backgrounded xcodebuild — the controller transcribes the exact code, verifies FOREGROUND, and commits; reviewers are the gate. (c) `FlowChips`/chip wrapping uses `LazyVGrid(.adaptive)` to stay dependency-free — a reviewer may prefer a true flow layout; acceptable for this port. (d) If `.onMoveCommand`/`.focusable` arrow-key handling on the slider proves flaky on macOS 13, drag still fully works — keyboard is a progressive enhancement, not required.
