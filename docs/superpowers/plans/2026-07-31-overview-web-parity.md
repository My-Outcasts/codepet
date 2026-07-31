# Native Overview → Web Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native macOS Overview page match the shipped web Overview (`codepet-v1-2.vercel.app`) exactly — one Overview page with a Roadmap ⁄ Second Brain toggle, a department-lane board with orthogonal connectors, web-exact card/chrome metrics, and the first-run briefing modal.

**Architecture:** Three layers, built bottom-up. (1) **Tokens** — port the web's roadmap-local CSS custom properties into `CodepetTheme` so every metric below has a real token to reference instead of ad-hoc `.opacity()` math. (2) **Pure layout engine** — replace `RoadmapMapLayout` with a line-by-line port of `lib/overview/roadmapLayout.ts`: department lanes, orthogonal elbow polylines, current-task-only critical path, top-left coordinates. Fully unit-tested with no SwiftUI. (3) **Views** — a new `OverviewSectionView` owning the header, mode toggle and chrome strip, delegating to a rewritten board renderer and the existing `SecondBrainPanel`.

**Tech Stack:** Swift 5 / SwiftUI (macOS 13+), XCTest, `xcodebuild` scheme `codepet` (lowercase), Firebase Firestore (`companies/{uid}`).

**Execution order: 0 → 1 → 2 → 3 → 4 → 5 → 7 → 6 → 8 → 9.** Tasks 6 (chrome strip) and 7 (first-run briefing) build the components Task 8 (unify the page) composes, so they run before it — that way no task ever creates a placeholder, a stub, or commented-out code to keep the branch compiling. Every task on this branch builds and passes tests on its own, with nothing disabled left behind. Task numbers below are stable; only the dispatch order differs.

## Global Constraints

- **Base branch:** branch off `origin/main` (native repo `My-Outcasts/codepet`), NOT `feat/chat-redesign`. `RoadmapView.swift` / `RoadmapMapView.swift` are byte-identical on both branches, but the shell differs (`main` = `AppRailView`; `feat/chat-redesign` = `SidebarView`). Ship path is: branch off `origin/main` → PR → merge → verify.
- **Isolation:** work in a git worktree. `~/Developer/codepet` is driven by a concurrent session — never edit it directly. Worktree path for this plan: `~/Desktop/codepet-wt-overview-parity`.
- **Toolchain:** scheme **`codepet`** (lowercase), no `xcodegen`, `@testable import codepet`.
  - Unit test: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`
  - Build: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`
  - **Run all `xcodebuild` in the FOREGROUND.** Backgrounded `xcodebuild` stalls.
  - **SourceKit cross-file diagnostics are FALSE POSITIVES** ("Cannot find type X", "No such module XCTest/FirebaseFirestore"). `xcodebuild` output is authoritative.
- **Test host lock:** a running `codepet.app` holds the Firestore LevelDB LOCK and aborts the test host in `FirestoreClient::Initialize`. **Quit the app before every `xcodebuild test`.** `** TEST FAILED **` with zero `Failing tests:` lines means whole suites never ran — quit the app and re-run, don't debug the code.
- **Do NOT hand-edit the Xcode project.** `CodePet.xcodeproj` is `objectVersion = 77` and uses `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file created under `codepet/` or `codepetTests/` is picked up automatically on the next build. Never add `PBXBuildFile`/`PBXFileReference` entries by hand and never `git add CodePet.xcodeproj` — if a new file seems missing from the target, you have a real compile error, not a membership problem.
- **Parity rule:** where this plan quotes a number, it is copied from web source. Do not "improve" it. Web references are `origin/main` of `My-Outcasts/Codepet-ver-1.2` at `d384cc3`:
  - `components/views/OverviewSection.tsx` — page shell, header, toggle, chrome strip, first-run modal
  - `components/views/overview/RoadmapView.tsx` — board renderer, cards, connectors, root node
  - `lib/overview/roadmapLayout.ts` — layout geometry + lanes + elbows
  - `lib/overview/roadmapModel.ts` — `deriveEdges` critical-path rule
  - `app/globals.css` lines 1–120 — design tokens
- **Colors that are hardcoded on web have no dark variant.** `#16a34a` (done), `#d97706` (approve), `#2563eb` (needsYou) are literal hex in the web source and must be literal in native too — do NOT wrap them in `Color.dyn`.
- **Copy:** English + Vietnamese for every user-facing string, following the existing `lang == .vi ? "…" : "…"` pattern. Vietnamese strings are given inline in each task.
- **Do not touch** `BuildCoachView`/`InstallView`/`SummaryView` or anything under Giang's Build Coach surface.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `codepet/Models/RoadmapLayout.swift` | Pure layout engine — geometry constants, department lanes, node positions (top-left), orthogonal edge polylines, critical path, root box. Replaces `RoadmapMapLayout.swift`. |
| `codepet/Models/RoadmapBoardCopy.swift` | Pure copy/state helpers for the board — chip verb, quiet status label, tray-marker rule, "is here" phrase. Keeps view files free of branching text logic. |
| `codepet/Views/Overview/OverviewSectionView.swift` | The Overview page — header, "How to read this map", Roadmap ⁄ Second Brain toggle, chrome strip, mode switch. Replaces `RoadmapView.swift`'s page role. |
| `codepet/Views/Overview/OverviewChromeRow.swift` | Progress card + beacon card + KEY legend (the compact strip under the header). |
| `codepet/Views/Overview/OverviewIntroSheet.swift` | The first-run briefing modal (also reopened by "How to read this map"). |
| `codepet/Views/Overview/RoadmapBoardView.swift` | Board renderer — scroll container, fit-to-height scale, phase header row, connector canvas, root node, task cards, edge fades. Replaces `RoadmapMapView.swift`. |
| `codepet/Views/Overview/RoadmapCardView.swift` | One task card (208×64) + the floating "is here" marker. |
| `codepetTests/RoadmapLayoutTests.swift` | Geometry, lanes, row spill, elbows, critical path, root, canvas size. Replaces `RoadmapMapLayoutTests.swift`. |
| `codepetTests/RoadmapBoardCopyTests.swift` | Copy/state helper tests. |
| `codepetTests/RoadmapPaletteTests.swift` | Token hex assertions. |
| `codepetTests/CompanyDataIntroSeenTests.swift` | `introSeenAt` read mapping + write payload. |

**Modified:**

| Path | Change |
|---|---|
| `codepet/Views/CodepetTokens.swift` | Append `RoadmapTokens` (cardBG/chipBG/chipBorder/lockedOpacity) + `RoadmapPalette` (incl. `tint(for:)`). Everything else the board needs is already in this file. |
| `codepet/Models/AppView.swift` | Add `.overview`; drop `.roadmap`/`.secondBrain` from `navTabs` and the enum; map `navDestination "roadmap"` → `.overview`. |
| `codepet/Views/Shell/AppShellView.swift:37-40` | Route `.overview` → `OverviewSectionView()`; delete the `.roadmap`/`.secondBrain` branches. |
| `codepet/Views/Copilot/CopilotChatView.swift:152` | `select(.roadmap)` → `select(.overview)`. |
| `codepet/Views/SecondBrain/SecondBrainView.swift` | Strip the page header (it becomes a mode inside Overview). |
| `codepet/Models/CompanyState.swift` | Add `introSeenAt: Date?`. |
| `codepet/Services/CompanyData.swift` | `CompanyDoc.introSeenAt` (millis), read mapping, `introSeenPayload`, `saveIntroSeen`. |
| `codepet/Managers/CompanyStore.swift` | `markIntroSeen()`. |

**Deleted:** `codepet/Models/RoadmapMapLayout.swift`, `codepet/Views/Roadmap/RoadmapMapView.swift`, `codepet/Views/Roadmap/RoadmapView.swift`, `codepetTests/RoadmapMapLayoutTests.swift`.

---

## Task 0: Worktree

**Files:** none (environment only)

- [ ] **Step 1: Fetch and create the worktree**

```bash
cd ~/Developer/codepet
git fetch origin main --no-show-forced-updates
git worktree add ~/Desktop/codepet-wt-overview-parity -b feat/overview-web-parity origin/main
cd ~/Desktop/codepet-wt-overview-parity && git log --oneline -1
```

Expected: the worktree is created and HEAD matches `origin/main`.

- [ ] **Step 2: Baseline build**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If it fails, stop — the baseline is broken and nothing below is measurable.

- [ ] **Step 3: Baseline test run**

Quit `codepet.app` first (`ps aux | grep codepet.app`), then run:
`cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | tail -5`
Expected: `** TEST SUCCEEDED **` and a non-zero executed-test count. Record the count — Task 9 compares against it.

---

## Task 1: Roadmap design tokens

Web's board leans on tokens that native doesn't have. Two matter functionally: `--rm-card-bg`/`--rm-card-border` are *lighter* than `surface`/`hairline` in dark mode specifically so cards keep a visible edge on the near-black page, and `--t-4` is the dependency-line color (native currently uses `hairline`, which is nearly invisible in dark).

**Files:**
- Modify: `codepet/Views/CodepetTokens.swift` (append two new sections at the end of the file)
- **Unchanged on purpose:** `codepet/Models/RoadmapTask.swift` — see Step 4
- Test: `codepetTests/RoadmapPaletteTests.swift`

**REUSE, don't duplicate.** `CodepetTokens` (added by PR #45) is already the 1:1 port of the web's `globals.css` scale and ALREADY provides everything below — use these, do not redefine them:

| Web token | Existing native token |
| --- | --- |
| `--well` | `CodepetTokens.well` |
| `--t-4` | `CodepetTokens.faint` |
| `--accent-deep` | `CodepetTokens.accentDeep` |
| `--accent-tint` | `CodepetTokens.accentTint` |
| `--accent-line` | `CodepetTokens.accentLine` |
| `--rm-card-border` | `CodepetTokens.cardEdge` (already exactly `#ece9e2` / `#3c352b`) |

Only the genuinely-missing roadmap tokens get added. Note `--rm-card-bg` is NOT `CodepetTokens.cardRaised`: web sets `.deptrow/.kb-card/.lib-tile` to `#26201a` in dark but `--rm-card-bg` to `#2a241c`, so the board card is a slightly lighter surface than the other list cards. Keep them separate.

**Interfaces:**
- Produces: `RoadmapTokens.cardBG`, `.chipBG`, `.chipBorder` (`Color`); `RoadmapTokens.lockedOpacity(dark:) -> Double`; `RoadmapTokens.cardBGHex/chipBGHex/chipBorderHex` (`(light: String, dark: String)`); `RoadmapPalette.doneHex/approveHex/needsYouHex` (`String`) and `.done/.approve/.needsYou/.canDo/.blocked` (`Color`).
- Later tasks reference the board's card edge as `CodepetTokens.cardEdge` and its tints as `CodepetTokens.accentTint` / `.accentLine` — there is no `CodepetTokens.cardEdge`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/RoadmapPaletteTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapPaletteTests: XCTestCase {
    // Web hardcodes these three (RoadmapView.tsx DOT, OverviewSection.tsx legendFor) with no
    // dark variant, so native must use the same literals in both appearances.
    func testStateHexMatchesWeb() {
        XCTAssertEqual(RoadmapPalette.doneHex, "#16a34a")
        XCTAssertEqual(RoadmapPalette.approveHex, "#d97706")
        XCTAssertEqual(RoadmapPalette.needsYouHex, "#2563eb")
    }

    // globals.css --rm-locked-op: 0.62 light / 0.9 dark.
    func testLockedOpacityMatchesWeb() {
        XCTAssertEqual(RoadmapTokens.lockedOpacity(dark: false), 0.62, accuracy: 0.0001)
        XCTAssertEqual(RoadmapTokens.lockedOpacity(dark: true), 0.9, accuracy: 0.0001)
    }

    // The board's card surface is LIGHTER than the app surface (#221d17) in dark mode — that's
    // deliberate on web so cards keep a visible edge on the near-black page.
    func testBoardSurfaceTokensMatchWeb() {
        XCTAssertEqual(RoadmapTokens.cardBGHex.light, "#ffffff")
        XCTAssertEqual(RoadmapTokens.cardBGHex.dark, "#2a241c")
        XCTAssertEqual(RoadmapTokens.chipBGHex.light, "#f1efe9")
        XCTAssertEqual(RoadmapTokens.chipBGHex.dark, "#342d23")
        XCTAssertEqual(RoadmapTokens.chipBorderHex.light, "#ece9e2")
        XCTAssertEqual(RoadmapTokens.chipBorderHex.dark, "#473e31")
    }

    // --rm-card-bg is a DIFFERENT dark surface from the list cards' (#26201a). If these ever
    // become equal, one of them drifted from globals.css.
    func testBoardCardSurfaceIsNotTheListCardSurface() {
        XCTAssertNotEqual(RoadmapTokens.cardBGHex.dark, "#26201a")
    }

    func testBoardTintCoversEveryState() {
        XCTAssertEqual(RoadmapPalette.tint(for: .done), RoadmapPalette.done)
        XCTAssertEqual(RoadmapPalette.tint(for: .codepetCanDo), RoadmapPalette.canDo)
        XCTAssertEqual(RoadmapPalette.tint(for: .needsApproval), RoadmapPalette.approve)
        XCTAssertEqual(RoadmapPalette.tint(for: .needsYou), RoadmapPalette.needsYou)
        XCTAssertEqual(RoadmapPalette.tint(for: .blocked), RoadmapPalette.blocked)
    }

    // The board palette and the department cards' palette are separate on web and must stay
    // separate here: web styles department task states from globals.css `.st-*`, where "Done"
    // is --accent-deep, NOT green. Merging them would recolor the Company page.
    func testBoardPaletteIsNotTheDepartmentPalette() {
        XCTAssertNotEqual(RoadmapPalette.tint(for: .done), taskStatusTint(.done))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapPaletteTests 2>&1 | tail -20`
Expected: compile failure — `cannot find 'RoadmapPalette' in scope`.

- [ ] **Step 3: Add the two missing token sections**

Append to `codepet/Views/CodepetTokens.swift` (the existing 1:1 port of the web scale — everything else the board needs is already in this file, see the REUSE table above):

```swift
// MARK: - Overview roadmap board

/// The roadmap-local custom properties from `app/globals.css` that no other surface uses.
/// `--rm-card-border` is deliberately absent: it is byte-for-byte `CodepetTokens.cardEdge`.
/// Each token is exposed twice — as a `(light, dark)` hex pair, so parity is unit-testable
/// without resolving an NSAppearance, and as the `Color` the views consume.
enum RoadmapTokens {
    typealias HexPair = (light: String, dark: String)

    static let cardBGHex: HexPair      = ("#ffffff", "#2a241c")   // --rm-card-bg
    static let chipBGHex: HexPair      = ("#f1efe9", "#342d23")   // --rm-chip-bg
    static let chipBorderHex: HexPair  = ("#ece9e2", "#473e31")   // --rm-chip-border

    /// Board card fill. In dark this is LIGHTER than both `--surface` (#221d17) and the list
    /// cards' `cardRaised` (#26201a) — web gives the board its own slightly-raised surface so
    /// cards keep a visible edge on the near-black page.
    static let cardBG = Color.dyn(cardBGHex.light, cardBGHex.dark)
    /// The status-icon box inside a card.
    static let chipBG = Color.dyn(chipBGHex.light, chipBGHex.dark)
    /// That box's edge.
    static let chipBorder = Color.dyn(chipBorderHex.light, chipBorderHex.dark)

    /// `--rm-locked-op` — how far a locked card's CONTENT fades. Never applied to the card
    /// itself: a translucent card would let the connectors behind it show through.
    static func lockedOpacity(dark: Bool) -> Double { dark ? 0.9 : 0.62 }
}

/// The board's five states. `done`/`approve`/`needsYou` are literal hex on web with no dark
/// variant (`RoadmapView.tsx` DOT, `OverviewSection.tsx` legendFor), so they are literal here
/// too — do NOT wrap them in `Color.dyn`. `canDo` and `blocked` follow the app's accent and
/// muted-text tokens, exactly as web follows `--accent` and `--t-3`.
enum RoadmapPalette {
    static let doneHex = "#16a34a"
    static let approveHex = "#d97706"
    static let needsYouHex = "#2563eb"

    static let done = Color(hex: doneHex)
    static let approve = Color(hex: approveHex)
    static let needsYou = Color(hex: needsYouHex)
    static var canDo: Color { CodepetTheme.accentPurple }
    static var blocked: Color { CodepetTheme.mutedText }
}
```

`Color(hex:)` already exists — `codepet/Models/Character.swift`. `Color.dyn` is in `CodepetTheme.swift`.

- [ ] **Step 4: Add the board's own state→color lookup — and leave `taskStatusTint` ALONE**

**Founder decision (Jul 31):** do NOT repoint the shared `taskStatusTint`. It is also read by `DepartmentDetailView`, and web's department cards use a *different* palette (`globals.css` `.st-done` → `--accent-deep`, `.st-draft` → `--gold-deep`, `.st-you` → `--blue`, `.st-locked` → `--t-4` — "Done" there is not green at all). Repointing it would silently recolor the Company/department page, which is outside this branch's scope. `codepet/Models/RoadmapTask.swift` must be left completely untouched by this task.

Instead, give the board its own lookup. Add to `RoadmapPalette` (in `codepet/Views/CodepetTokens.swift`):

```swift
    /// State → dot/chip color for the roadmap board only, mirroring `RoadmapView.tsx`'s `DOT`
    /// map. Deliberately NOT `taskStatusTint`: that one serves the department cards, which web
    /// styles from a different scale (`globals.css` `.st-*`), so the two must not be merged.
    static func tint(for status: TaskStatus) -> Color {
        switch status {
        case .done:          return done
        case .codepetCanDo:  return canDo
        case .needsApproval: return approve
        case .needsYou:      return needsYou
        case .blocked:       return blocked
        }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapPaletteTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Verify the two palettes stay separate**

Run: `cd ~/Desktop/codepet-wt-overview-parity && git diff --stat HEAD -- codepet/Models/RoadmapTask.swift && grep -rn "taskStatusTint" codepet/`
Expected: `RoadmapTask.swift` shows **no changes**, and every `taskStatusTint` call site is unchanged. The board's own views (Tasks 4–6) will call `RoadmapPalette.tint(for:)`; nothing outside the Overview may change color as a result of this branch.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add codepet/Views/CodepetTokens.swift codepet/Models/RoadmapTask.swift codepetTests/RoadmapPaletteTests.swift
git commit -m "feat(overview): port the web's roadmap design tokens + state palette"
```

---

## Task 2: Port the layout engine

The crux. Native currently centers each phase column vertically and draws bezier curves; web assigns each department a horizontal lane across all columns and draws orthogonal elbows. Coordinates stay **top-left** (as on web) — the view converts to SwiftUI's center-based `.position` — so these tests can be read directly against `roadmapLayout.ts`.

**Files:**
- Create: `codepet/Models/RoadmapLayout.swift`
- **Delete nothing.** The old `RoadmapMapLayout.swift` / `RoadmapMapView.swift` / `RoadmapMapLayoutTests.swift` stay and keep passing; **Task 5** retires them together with the old board. See Step 4.
- Test: `codepetTests/RoadmapLayoutTests.swift`

**Interfaces:**
- Consumes: `RoadmapEngine.nextStep(_:)`, `RoadmapTask`, `RoadmapPhase` (unchanged).
- Produces:
  - `RoadmapGeometry.cardW/cardH/colGap/rowPitch/top/bottomPad/rootW/rootH/rootLeft/rootGap/rootRight` — all `CGFloat`
  - `struct PositionedNode { let task: RoadmapTask; let col: Int; let row: Int; let x: CGFloat; let y: CGFloat; var id: String }`
  - `struct EdgePath { let from: String; let to: String; let points: [CGPoint]; let critical: Bool }`
  - `struct PhaseColumn { let phase: RoadmapPhase; let x: CGFloat; let done: Int; let total: Int; let current: Bool; var id: String }`
  - `struct RoadmapLayout { let nodes: [PositionedNode]; let edges: [EdgePath]; let columns: [PhaseColumn]; let root: CGRect?; let rootEdges: [EdgePath]; let size: CGSize }`
  - `enum RoadmapLayoutEngine { static let rootId: String; static func layout(_ tasks: [RoadmapTask], hasRoot: Bool = true) -> RoadmapLayout }`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/RoadmapLayoutTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapLayoutTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String? = "eng",
                   deps: [String] = [], done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does,
                    dependsOn: deps, done: done, dept: dept)
    }
    private func node(_ l: RoadmapLayout, _ id: String) -> PositionedNode {
        l.nodes.first { $0.task.id == id }!
    }

    // MARK: geometry

    func testGeometryMatchesWeb() {
        XCTAssertEqual(RoadmapGeometry.cardW, 208)
        XCTAssertEqual(RoadmapGeometry.cardH, 64)
        XCTAssertEqual(RoadmapGeometry.colGap, 60)
        XCTAssertEqual(RoadmapGeometry.rowPitch, 96)
        XCTAssertEqual(RoadmapGeometry.top, 40)
        XCTAssertEqual(RoadmapGeometry.bottomPad, 16)
        XCTAssertEqual(RoadmapGeometry.rootW, 172)
        XCTAssertEqual(RoadmapGeometry.rootH, 118)
        XCTAssertEqual(RoadmapGeometry.rootLeft, 12)
        XCTAssertEqual(RoadmapGeometry.rootGap, 48)
    }

    func testColumnXIsRootRightPlusGapThenPitch() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .foundation)])
        XCTAssertEqual(node(l, "a").x, 12 + 172 + 48)              // 232
        XCTAssertEqual(node(l, "b").x, 232 + 208 + 60)             // 500
    }

    func testFirstRowTopIsTOP() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        XCTAssertEqual(node(l, "a").y, 40)
    }

    // MARK: department lanes

    // A dept keeps ONE row across every column it appears in — the horizontal track read.
    func testDeptKeepsOneLaneAcrossColumns() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("e2", .build, dept: "eng"),
            t("m1", .find, dept: "mkt"), t("m2", .build, dept: "mkt"),
        ])
        XCTAssertEqual(node(l, "e1").row, node(l, "e2").row)
        XCTAssertEqual(node(l, "m1").row, node(l, "m2").row)
        XCTAssertNotEqual(node(l, "e1").row, node(l, "m1").row)
    }

    // Lane order is the canonical DEPT_LANE_ORDER, not first-appearance order.
    func testLaneOrderIsCanonical() {
        let l = RoadmapLayoutEngine.layout([
            t("l1", .find, dept: "legal"), t("e1", .find, dept: "eng"),
        ])
        XCTAssertLessThan(node(l, "e1").row, node(l, "l1").row)   // eng is lane 0, legal last
    }

    // Depts that never share a column pack onto the same lane (compact layout).
    func testDisjointDeptsShareALane() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("s1", .build, dept: "sales"),
        ])
        XCTAssertEqual(node(l, "e1").row, node(l, "s1").row)
    }

    // A 2nd task in the same (phase, dept) cell spills to the nearest free row.
    func testSecondTaskInCellSpillsToFreeRow() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("e2", .find, dept: "eng"),
        ])
        XCTAssertNotEqual(node(l, "e1").row, node(l, "e2").row)
    }

    func testUnassignedDeptDoesNotCrash() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, dept: nil), t("b", .find, dept: nil)])
        XCTAssertEqual(l.nodes.count, 2)
        XCTAssertNotEqual(node(l, "a").row, node(l, "b").row)
    }

    // MARK: edges

    func testAlignedRowsGiveAStraightTwoPointEdge() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng"), t("b", .foundation, dept: "eng", deps: ["a"]),
        ])
        let e = l.edges.first { $0.from == "a" && $0.to == "b" }!
        XCTAssertEqual(e.points.count, 2)
        XCTAssertEqual(e.points[0].y, e.points[1].y)
        XCTAssertEqual(e.points[0].x, node(l, "a").x + 208)        // leaves the right edge
        XCTAssertEqual(e.points[1].x, node(l, "b").x)              // lands on the left edge
    }

    // Different rows → a 4-point elbow whose vertical sits in the gutter left of the TARGET
    // column, so it never crosses an intermediate column's cards.
    func testOffsetRowsGiveAnElbowInTheTargetGutter() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("m2", .foundation, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m2" }!
        XCTAssertEqual(e.points.count, 4)
        let gutter = (node(l, "m2").x - 30).rounded()
        XCTAssertEqual(e.points[1].x, gutter)
        XCTAssertEqual(e.points[2].x, gutter)
        XCTAssertEqual(e.points[1].y, e.points[0].y)
        XCTAssertEqual(e.points[2].y, e.points[3].y)
    }

    // Same-column deps hook through the column's LEFT gutter instead of doubling back.
    func testSameColumnEdgeHooksLeft() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m1" }!
        XCTAssertEqual(e.points.count, 4)
        XCTAssertEqual(e.points[0].x, node(l, "e1").x)             // starts at the LEFT edge
        XCTAssertLessThan(e.points[1].x, node(l, "e1").x)          // hooks further left
    }

    func testDanglingDepIsDropped() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, deps: ["ghost"])])
        XCTAssertTrue(l.edges.isEmpty)
    }

    // MARK: critical path

    // Web's rule: an edge is critical ONLY if it touches the current task. Not the whole
    // transitive chain — that lit up the entire board.
    func testCriticalIsOnlyEdgesTouchingCurrent() {
        // a done → b current → c. Edge a→b and b→c are critical; c→d is not.
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng", done: true),
            t("b", .foundation, dept: "eng", deps: ["a"]),
            t("c", .build, dept: "eng", deps: ["b"]),
            t("d", .ship, dept: "eng", deps: ["c"]),
        ])
        XCTAssertEqual(RoadmapEngine.nextStep(l.nodes.map(\.task))?.id, "b")
        XCTAssertTrue(l.edges.first { $0.from == "a" && $0.to == "b" }!.critical)
        XCTAssertTrue(l.edges.first { $0.from == "b" && $0.to == "c" }!.critical)
        XCTAssertFalse(l.edges.first { $0.from == "c" && $0.to == "d" }!.critical)
    }

    // MARK: root

    func testRootBoxIsVerticallyCentered() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
        ])
        let r = l.root!
        XCTAssertEqual(r.origin.x, 12)
        XCTAssertEqual(r.size.width, 172)
        XCTAssertEqual(r.size.height, 118)
        XCTAssertEqual(r.origin.y, ((l.size.height - 118) / 2).rounded())
    }

    // Root fans out to ENTRY tasks only (no in-roadmap dependency), in any phase.
    func testRootEdgesGoToEntryTasksOnly() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng"), t("b", .foundation, dept: "eng", deps: ["a"]),
        ])
        XCTAssertEqual(l.rootEdges.map(\.to), ["a"])
        XCTAssertTrue(l.rootEdges.allSatisfy { $0.from == RoadmapLayoutEngine.rootId })
        XCTAssertTrue(l.rootEdges.allSatisfy { !$0.critical })   // root edges are their own style
    }

    func testRootCanBeOmitted() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)], hasRoot: false)
        XCTAssertNil(l.root)
        XCTAssertTrue(l.rootEdges.isEmpty)
        XCTAssertEqual(node(l, "a").x, 12)
    }

    // MARK: columns + canvas

    func testColumnsAreEveryPhaseInOrderWithCounts() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, done: true), t("b", .find), t("c", .build),
        ])
        XCTAssertEqual(l.columns.map(\.phase), RoadmapPhase.allCases)
        XCTAssertEqual(l.columns[RoadmapPhase.find.order].done, 1)
        XCTAssertEqual(l.columns[RoadmapPhase.find.order].total, 2)
        XCTAssertEqual(l.columns[RoadmapPhase.ship.order].total, 0)
    }

    func testCurrentColumnIsFlagged() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, done: true), t("b", .build)])
        XCTAssertEqual(l.columns.filter(\.current).map(\.phase), [.build])
    }

    func testCanvasSizeFromLastColumnAndLowestRow() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        let lastX = 232 + CGFloat(RoadmapPhase.allCases.count - 1) * 268
        XCTAssertEqual(l.size.width, lastX + 208 + 16)
        XCTAssertEqual(l.size.height, 40 + 64 + 16)                 // one row
    }

    func testEmptyTasksStillGivesRootAndSixColumns() {
        let l = RoadmapLayoutEngine.layout([])
        XCTAssertTrue(l.nodes.isEmpty)
        XCTAssertTrue(l.edges.isEmpty)
        XCTAssertNotNil(l.root)
        XCTAssertEqual(l.columns.count, RoadmapPhase.allCases.count)
        XCTAssertEqual(l.size.height, 120)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapLayoutTests 2>&1 | tail -20`
Expected: compile failure — `cannot find 'RoadmapGeometry' in scope`.

- [ ] **Step 3: Write the engine**

Create `codepet/Models/RoadmapLayout.swift`:

```swift
// codepet/Models/RoadmapLayout.swift
import CoreGraphics

/// Geometry — one source of truth for card size + spacing. Values mirror the web's
/// `lib/overview/roadmapLayout.ts` exactly; do not tune them independently.
enum RoadmapGeometry {
    static let cardW: CGFloat = 208
    static let cardH: CGFloat = 64
    static let colGap: CGFloat = 60      // horizontal gap between phase columns
    static let rowPitch: CGFloat = 96    // vertical distance between task rows
    static let top: CGFloat = 40         // room above row 0 for the "is here" marker
    static let bottomPad: CGFloat = 16
    static let rootW: CGFloat = 172
    static let rootH: CGFloat = 118
    static let rootLeft: CGFloat = 12
    static let rootGap: CGFloat = 48     // gap between the root node and column 0
    static let rootRight: CGFloat = rootLeft + rootW
}

/// One positioned task card. `x`/`y` are the card's TOP-LEFT (web's coordinate scheme);
/// the view converts to SwiftUI's center-based `.position`.
struct PositionedNode: Identifiable {
    let task: RoadmapTask
    let col: Int
    let row: Int
    let x: CGFloat
    let y: CGFloat
    var id: String { task.id }
}

/// A connector as a polyline: 2 points for a straight run, 4 for an orthogonal elbow.
struct EdgePath {
    let from: String
    let to: String
    let points: [CGPoint]
    let critical: Bool
}

/// A phase column's header data.
struct PhaseColumn: Identifiable {
    let phase: RoadmapPhase
    let x: CGFloat
    let done: Int
    let total: Int
    let current: Bool
    var id: String { phase.rawValue }
}

struct RoadmapLayout {
    let nodes: [PositionedNode]
    let edges: [EdgePath]
    let columns: [PhaseColumn]
    /// The company root box, or nil when `hasRoot: false`.
    let root: CGRect?
    /// Root → entry-task connectors. Styled separately from dependency edges, never critical.
    let rootEdges: [EdgePath]
    let size: CGSize
}

/// Pure layout for the Overview roadmap board: columns = phases, rows = department lanes,
/// edges = dependencies, orthogonal connectors, critical path = the edges touching the
/// current move. Deterministic and side-effect-free so the renderer stays thin.
enum RoadmapLayoutEngine {
    static let rootId = "__root__"

    /// Canonical department lane order (top → bottom): product first, then growth-facing
    /// functions, then company-shell functions. Any dept not listed falls in after these,
    /// in first-appearance order.
    private static let deptLaneOrder = ["eng", "design", "mkt", "sales", "support", "ops", "fin", "legal"]

    private static func colLeft(_ col: Int, hasRoot: Bool) -> CGFloat {
        let start = hasRoot ? RoadmapGeometry.rootRight + RoadmapGeometry.rootGap : RoadmapGeometry.rootLeft
        return start + CGFloat(col) * (RoadmapGeometry.cardW + RoadmapGeometry.colGap)
    }

    private static func rowTop(_ row: Int) -> CGFloat {
        RoadmapGeometry.top + CGFloat(row) * RoadmapGeometry.rowPitch
    }

    /// Orthogonal connector from a right-edge point to a left-edge point. A straight
    /// segment when the rows line up, otherwise an elbow whose vertical sits in the gutter
    /// just left of the TARGET column — so it never crosses an intermediate column's cards.
    static func elbow(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        if a.y == b.y { return [a, b] }
        let mid = (b.x - RoadmapGeometry.colGap / 2).rounded()
        return [a, CGPoint(x: mid, y: a.y), CGPoint(x: mid, y: b.y), b]
    }

    /// Connector between two cards in the SAME column: a hook that drops into the column's
    /// LEFT gutter instead of doubling back through the cards. Both x's are the column's left edge.
    static func sideElbow(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let g = (a.x - RoadmapGeometry.colGap / 2).rounded()
        return [a, CGPoint(x: g, y: a.y), CGPoint(x: g, y: b.y), b]
    }

    static func layout(_ tasks: [RoadmapTask], hasRoot: Bool = true) -> RoadmapLayout {
        let phases = RoadmapPhase.allCases
        var colOf: [RoadmapPhase: Int] = [:]
        for (i, p) in phases.enumerated() { colOf[p] = i }

        // ── Department lanes ──────────────────────────────────────────────────────────
        // Each department keeps a single horizontal row across the columns it appears in,
        // so a function reads as a track left-to-right. Depts that never share a column
        // pack onto the same lane; a 2nd task in one (phase, dept) cell spills to the
        // nearest free row in that column only.
        var deptCols: [String: Set<Int>] = [:]
        var deptSeen: [String] = []
        for t in tasks {
            guard let c = colOf[t.phase] else { continue }
            let d = t.dept ?? ""            // legacy tasks predate `dept`
            if deptCols[d] == nil { deptCols[d] = []; deptSeen.append(d) }
            deptCols[d]?.insert(c)
        }
        let orderedDepts = deptLaneOrder.filter { deptCols[$0] != nil }
            + deptSeen.filter { !deptLaneOrder.contains($0) }

        // Greedy interval-graph coloring: give each dept the lowest lane whose
        // already-claimed columns don't clash with the dept's columns.
        var laneOf: [String: Int] = [:]
        var laneCols: [Set<Int>] = []
        for d in orderedDepts {
            guard let cols = deptCols[d] else { continue }
            var lane = 0
            while lane < laneCols.count && !laneCols[lane].isDisjoint(with: cols) { lane += 1 }
            laneOf[d] = lane
            if lane == laneCols.count { laneCols.append([]) }
            laneCols[lane].formUnion(cols)
        }
        let laneCount = max(1, laneCols.count)

        // Place a task at its dept lane, or the nearest free row in that column if the
        // lane is taken there (search down, then up, then extend below all lanes).
        var occ: [Int: Set<Int>] = [:]
        func takeRow(_ col: Int, _ lane: Int) -> Int {
            var used = occ[col] ?? []
            var row = lane
            if used.contains(row) {
                row = -1
                var r = lane + 1
                while r < laneCount && row < 0 { if !used.contains(r) { row = r }; r += 1 }
                r = lane - 1
                while r >= 0 && row < 0 { if !used.contains(r) { row = r }; r -= 1 }
                if row < 0 { row = laneCount; while used.contains(row) { row += 1 } }
            }
            used.insert(row)
            occ[col] = used
            return row
        }

        var nodes: [PositionedNode] = []
        var nodeById: [String: PositionedNode] = [:]
        for task in tasks {
            guard let col = colOf[task.phase] else { continue }   // unknown phase → skip, don't crash
            let row = takeRow(col, laneOf[task.dept ?? ""] ?? 0)
            let n = PositionedNode(task: task, col: col, row: row,
                                   x: colLeft(col, hasRoot: hasRoot), y: rowTop(row))
            nodes.append(n)
            nodeById[task.id] = n
        }

        func centerY(_ n: PositionedNode) -> CGFloat { n.y + RoadmapGeometry.cardH / 2 }
        func rightX(_ n: PositionedNode) -> CGFloat { n.x + RoadmapGeometry.cardW }

        // An edge is CRITICAL when it TOUCHES the current task — the incoming edge that led
        // here and the outgoing edges to what this move unblocks. Nothing else.
        let currentId = RoadmapEngine.nextStep(tasks)?.id
        let ids = Set(tasks.map { $0.id })

        var edges: [EdgePath] = []
        for t in tasks {
            for dep in t.dependsOn {
                guard ids.contains(dep), let a = nodeById[dep], let b = nodeById[t.id] else { continue }
                let points = a.col == b.col
                    ? sideElbow(from: CGPoint(x: a.x, y: centerY(a)),
                                to: CGPoint(x: b.x, y: centerY(b)))
                    : elbow(from: CGPoint(x: rightX(a), y: centerY(a)),
                            to: CGPoint(x: b.x, y: centerY(b)))
                edges.append(EdgePath(from: dep, to: t.id, points: points,
                                      critical: t.id == currentId || dep == currentId))
            }
        }

        let maxRows = max(1, nodes.map { $0.row + 1 }.max() ?? 1)
        let height = RoadmapGeometry.top + CGFloat(maxRows - 1) * RoadmapGeometry.rowPitch
            + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        let width = colLeft(phases.count - 1, hasRoot: hasRoot)
            + RoadmapGeometry.cardW + RoadmapGeometry.bottomPad

        let currentPhase = currentId.flatMap { nodeById[$0]?.task.phase }
        let columns: [PhaseColumn] = phases.enumerated().map { i, p in
            let list = tasks.filter { $0.phase == p }
            return PhaseColumn(phase: p, x: colLeft(i, hasRoot: hasRoot),
                               done: list.filter { $0.done }.count, total: list.count,
                               current: p == currentPhase)
        }

        var root: CGRect?
        var rootEdges: [EdgePath] = []
        if hasRoot {
            let ry = ((height - RoadmapGeometry.rootH) / 2).rounded()
            root = CGRect(x: RoadmapGeometry.rootLeft, y: ry,
                          width: RoadmapGeometry.rootW, height: RoadmapGeometry.rootH)
            let start = CGPoint(x: RoadmapGeometry.rootRight, y: ry + RoadmapGeometry.rootH / 2)
            for n in nodes where n.task.dependsOn.allSatisfy({ !ids.contains($0) }) {
                rootEdges.append(EdgePath(from: rootId, to: n.task.id,
                                          points: elbow(from: start,
                                                        to: CGPoint(x: n.x, y: centerY(n))),
                                          critical: false))
            }
        }

        return RoadmapLayout(nodes: nodes, edges: edges, columns: columns, root: root,
                             rootEdges: rootEdges, size: CGSize(width: width, height: height))
    }
}
```

- [ ] **Step 4: Leave the old engine in place**

The new engine is ADDITIVE in this task. `RoadmapMapLayout.swift`, `RoadmapMapView.swift` and `RoadmapMapLayoutTests.swift` all stay exactly as they are and keep compiling — Task 5 removes the old engine and the old board together, once `RoadmapBoardView` exists to replace them. Do not delete anything here, do not create `.swift.bak` files, and do not comment out any branch in `AppShellView.swift`: every task on this branch must build and pass tests with no disabled code left behind.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapLayoutTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, 20 tests executed.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add -A codepet/Models codepetTests
git commit -m "feat(overview): port the web roadmap layout engine (dept lanes + orthogonal edges)"
```

---

## Task 3: Board copy helpers

Pull the card's branching text out of the view so it's testable and can't drift from web.

**Files:**
- Create: `codepet/Models/RoadmapBoardCopy.swift`
- Test: `codepetTests/RoadmapBoardCopyTests.swift`

**Interfaces:**
- Produces: `RoadmapBoardCopy.verb(for:_:) -> String?`, `.quietLabel(for:lang:) -> String?`, `.showsTrayMarker(_:) -> Bool`, `.herePhrase(founderName:lang:) -> String`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/RoadmapBoardCopyTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapBoardCopyTests: XCTestCase {
    // Web VERB map: only actionable states earn a verb chip.
    func testVerbsMatchWeb() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .en), "Start")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .en), "Review")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .en), "Add your input")
        XCTAssertNil(RoadmapBoardCopy.verb(for: .done, .en))
        XCTAssertNil(RoadmapBoardCopy.verb(for: .blocked, .en))
    }

    func testVerbsLocalised() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .vi), "Bắt đầu")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .vi), "Duyệt")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .vi), "Cần bạn")
    }

    // done / blocked render as PLAIN TEXT on web, never a pill — so they get a quiet label
    // and no verb. Everything else is nil here (it has a chip instead).
    func testQuietLabelsOnlyForDoneAndBlocked() {
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .en), "Done")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .en), "Needs earlier steps")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .vi), "Xong")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .vi), "Cần bước trước")
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .codepetCanDo, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsYou, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsApproval, lang: .en))
    }

    // Web shows the small deliverable/tray marker ONLY on locked cards.
    func testTrayMarkerOnlyOnBlocked() {
        XCTAssertTrue(RoadmapBoardCopy.showsTrayMarker(.blocked))
        for s in [TaskStatus.done, .codepetCanDo, .needsYou, .needsApproval] {
            XCTAssertFalse(RoadmapBoardCopy.showsTrayMarker(s))
        }
    }

    // The beacon names the FOUNDER (never the companion), and falls back to second person —
    // composed so it reads "You are here", never "You is here".
    func testHerePhrase() {
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .en), "Mona is here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "  ", lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .vi), "Mona đang ở đây")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .vi), "Bạn đang ở đây")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapBoardCopyTests 2>&1 | tail -20`
Expected: compile failure — `cannot find 'RoadmapBoardCopy' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/RoadmapBoardCopy.swift`:

```swift
// codepet/Models/RoadmapBoardCopy.swift
import Foundation

/// Pure copy + presentation rules for a roadmap board card, ported from the web
/// `RoadmapView.tsx` (VERB, STATUS, the locked tray marker, herePhrase). Kept out of the
/// views so the wording is unit-tested and can't drift from web.
enum RoadmapBoardCopy {
    /// Actionable states earn a verb the founder can act on; done/locked stay quiet labels.
    static func verb(for status: TaskStatus, _ lang: AppLanguage) -> String? {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Bắt đầu" : "Start"
        case .needsApproval: return lang == .vi ? "Duyệt" : "Review"
        case .needsYou:      return lang == .vi ? "Cần bạn" : "Add your input"
        case .done, .blocked: return nil
        }
    }

    /// The plain-language status line shown INSTEAD of a chip — web renders done/locked as
    /// text, not a pill. Returns nil for any state that has a verb chip.
    static func quietLabel(for status: TaskStatus, lang: AppLanguage) -> String? {
        switch status {
        case .done:    return lang == .vi ? "Xong" : "Done"
        case .blocked: return lang == .vi ? "Cần bước trước" : "Needs earlier steps"
        case .codepetCanDo, .needsYou, .needsApproval: return nil
        }
    }

    /// The small deliverable/output marker in a card's top-right — locked cards only.
    static func showsTrayMarker(_ status: TaskStatus) -> Bool { status == .blocked }

    /// The beacon marks where the FOUNDER stands — named when we have it, second person
    /// otherwise. Composed (not "{label} is here") so the fallback reads "You are here".
    static func herePhrase(founderName: String?, lang: AppLanguage) -> String {
        let n = (founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return lang == .vi ? "Bạn đang ở đây" : "You are here" }
        return lang == .vi ? "\(n) đang ở đây" : "\(n) is here"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapBoardCopyTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add codepet/Models/RoadmapBoardCopy.swift codepetTests/RoadmapBoardCopyTests.swift
git commit -m "feat(overview): board card copy helpers (verb, quiet label, tray, here-phrase)"
```

---

## Task 4: The task card

208×64, horizontal content, marker floating above the card, quiet states as text, circle dot for done, tray on locked only.

**Files:**
- Create: `codepet/Views/Overview/RoadmapCardView.swift`
- Test: build-verified (SwiftUI view; the logic it branches on is covered by Task 3)

**Interfaces:**
- Consumes: `RoadmapGeometry`, `RoadmapBoardCopy`, `RoadmapPalette`, `RoadmapTokens` (cardBG/chipBG/chipBorder/lockedOpacity), `CodepetTokens.cardEdge`, `RoadmapPalette.tint(for:)`
- Produces: `RoadmapCardView(task:status:isCurrent:herePhrase:pulsing:onTap:)`

**Decision (founder, Jul 31) — this task INTENTIONALLY reverses a choice made in PR #46.** `main`'s `RoadmapMapView.statusChip` sets `filled = status == .codepetCanDo`, with a comment claiming "web fills every Start, not just the beacon". The live web contradicts that: only the `current` card's Start is filled; every other runnable card gets a tinted **outline** chip (verified by inspecting the rendered board). So `filled` here is `isCurrent && status == .codepetCanDo`, giving the board exactly one hero CTA. Do not "restore" #46's behavior.

- [ ] **Step 1: Write the view**

Create `codepet/Views/Overview/RoadmapCardView.swift`:

```swift
// codepet/Views/Overview/RoadmapCardView.swift
import SwiftUI

/// One roadmap board card — a native port of `Node` in the web `RoadmapView.tsx`.
///
/// Layout is HORIZONTAL and fixed at 208×64: a 26pt status-icon box, then the title with
/// its chip (or quiet status text) stacked beside it. The "is here" marker floats ABOVE
/// the card (web `top:-32`), which is why the layout engine reserves `TOP = 40`.
struct RoadmapCardView: View {
    let task: RoadmapTask
    let status: TaskStatus
    /// The single current move (the beacon) — the only card with a filled chip + marker.
    let isCurrent: Bool
    let herePhrase: String
    let pulsing: Bool
    let onTap: () -> Void

    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { RoadmapPalette.tint(for: status) }
    private var isDone: Bool { status == .done }
    private var isLocked: Bool { status == .blocked }

    var body: some View {
        HStack(spacing: 10) {
            statusBox
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(2)
                    .lineSpacing(0)          // web line-height 1.2
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150, alignment: .leading)
                if let verb = RoadmapBoardCopy.verb(for: status, lang) {
                    chip(verb)
                } else if let quiet = RoadmapBoardCopy.quietLabel(for: status, lang: lang) {
                    Text(quiet)
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: RoadmapGeometry.cardW, height: RoadmapGeometry.cardH, alignment: .leading)
        // The locked fade lives on the CONTENT, never the card — a faded card would let the
        // connectors behind it show through.
        .opacity(isLocked ? RoadmapTokens.lockedOpacity(dark: scheme == .dark) : 1)
        .overlay(alignment: .topTrailing) { if RoadmapBoardCopy.showsTrayMarker(status) { trayMarker } }
        .background(cardFill)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(cardBorder, lineWidth: 1))
        .shadow(color: isCurrent ? CodepetTheme.accentPurple.opacity(0.6) : .clear,
                radius: 15, x: 0, y: 10)
        .overlay(alignment: .topLeading) {
            if isCurrent { hereMarker.offset(x: -1, y: -32) }
        }
        .scaleEffect(pulsing ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.5), value: pulsing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // Web: a 26×26 rounded box holding a 10×10 dot — a CIRCLE when done, a 3px rounded
    // square otherwise. Done also tints the box green.
    private var statusBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(isDone ? RoadmapPalette.done.opacity(0.14) : RoadmapTokens.chipBG)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(isDone ? RoadmapPalette.done.opacity(0.3) : RoadmapTokens.chipBorder,
                            lineWidth: 1))
                .frame(width: 26, height: 26)
            Group {
                if isDone { Circle().fill(tint) }
                else { RoundedRectangle(cornerRadius: 3).fill(tint) }
            }
            .frame(width: 10, height: 10)
        }
        .frame(width: 26, height: 26)
    }

    // Only the current move is a FILLED chip; every other actionable card is an outline, so
    // the board has exactly one unmistakable hero.
    @ViewBuilder private func chip(_ label: String) -> some View {
        let filled = isCurrent && status == .codepetCanDo
        Text(label)
            .font(CodepetTheme.inter(10, weight: .bold))
            .foregroundColor(filled ? CodepetTheme.onAccent(tint) : tint)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.10)))
            .overlay(Capsule().stroke(filled ? tint : tint.opacity(0.35), lineWidth: 1))
    }

    // The card is always OPAQUE — the state tint is layered over the base surface rather than
    // replacing it, so a dependency line running behind a card can never bleed through.
    private var cardFill: some View {
        let tintOverlay: Color? = isCurrent
            ? CodepetTheme.accentPurple.opacity(0.10)
            : isDone ? RoadmapPalette.done.opacity(0.06) : nil
        return RoundedRectangle(cornerRadius: 11).fill(RoadmapTokens.cardBG)
            .overlay {
                if let tintOverlay {
                    RoundedRectangle(cornerRadius: 11).fill(tintOverlay)
                }
            }
    }

    private var cardBorder: Color {
        if isCurrent { return CodepetTheme.accentPurple.opacity(0.6) }
        if isDone { return RoadmapPalette.done.opacity(0.22) }
        return CodepetTokens.cardEdge
    }

    // Web: a 10×10 square with a thick bottom border — an out-tray glyph marking a step
    // that still owes a deliverable.
    private var trayMarker: some View {
        VStack(spacing: 0) {
            Rectangle().stroke(CodepetTheme.mutedText, lineWidth: 1.5).frame(height: 6)
            Rectangle().fill(CodepetTheme.mutedText).frame(height: 4.5)
        }
        .frame(width: 10, height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .opacity(0.9)
        .padding(.top, 9).padding(.trailing, 10)
    }

    // Web: a surface-filled pill with an accent border, a 17pt gradient square, and
    // ACCENT-colored text (not white on purple).
    private var hereMarker: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [CodepetTokens.accentDeep, CodepetTheme.accentPurple],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 17, height: 17)
            Text(herePhrase.uppercased())
                .font(CodepetTheme.inter(9.5)).tracking(0.57)   // web .06em at 9.5px
                .foregroundColor(CodepetTheme.accentPurple)
                .fixedSize()
        }
        .padding(.leading, 4).padding(.trailing, 9).padding(.vertical, 3)
        .background(Capsule().fill(CodepetTheme.surface))
        .overlay(Capsule().stroke(CodepetTheme.accentPurple.opacity(0.5), lineWidth: 1))
        .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 10, x: 0, y: 6)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -12`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add codepet/Views/Overview/RoadmapCardView.swift
git commit -m "feat(overview): web-exact roadmap card (208x64, floating here-marker, quiet states)"
```

---

## Task 5: The board renderer

**Files:**
- Create: `codepet/Views/Overview/RoadmapBoardView.swift`
- Modify: `codepet/Views/Roadmap/RoadmapView.swift:34` (repoint the old page at the new board so it keeps compiling until Task 8 replaces it)
- Delete: `codepet/Views/Roadmap/RoadmapMapView.swift`, `codepet/Models/RoadmapMapLayout.swift`, `codepetTests/RoadmapMapLayoutTests.swift`
- Test: build-verified + the full suite still green after the old engine's tests are removed

**Interfaces:**
- Consumes: `RoadmapLayoutEngine.layout(_:)`, `RoadmapCardView`, `RoadmapGeometry`, `CodepetTokens.faint`/`well`/`accentPurple`
- Produces: `RoadmapBoardView(tasks:companionName:founderName:projectName:tagline:onTaskTap:)`

- [ ] **Step 1: Write the view**

Create `codepet/Views/Overview/RoadmapBoardView.swift`:

```swift
// codepet/Views/Overview/RoadmapBoardView.swift
import SwiftUI

/// The Overview roadmap board — a native port of the web `RoadmapView.tsx` renderer.
/// A thin layer over `RoadmapLayoutEngine`: it takes node boxes and orthogonal edge
/// polylines and draws them. Columns are phases, rows are department lanes, edges are
/// dependencies; the edges touching the current move are lit, everything else is a faint
/// dotted dependency. The tree begins at a luminous company root node.
struct RoadmapBoardView: View {
    let tasks: [RoadmapTask]
    let companionName: String
    let founderName: String?
    let projectName: String
    let tagline: String?
    let onTaskTap: (RoadmapTask) -> Void

    @Environment(\.uiLanguage) private var lang

    /// Measured height of the scroll area, for the fit-to-height scale.
    @State private var avail: CGFloat = 0
    /// Task ids mid-pulse (a step just became current, or just unlocked).
    @State private var pulseIds: Set<String> = []
    @State private var prevStates: [String: TaskStatus] = [:]
    @State private var scrollEdge = (left: false, right: false)

    private var layout: RoadmapLayout { RoadmapLayoutEngine.layout(tasks) }
    private var currentId: String? { RoadmapEngine.nextStep(tasks)?.id }
    private var herePhrase: String {
        RoadmapBoardCopy.herePhrase(founderName: founderName, lang: lang)
    }

    private let headerBlock: CGFloat = 34    // phase-header row (28) + its 6pt bottom margin

    /// Scale the diagram up to fill the available height, capped at 1.0 (never upscale past
    /// natural size), and center any leftover height — so a short roadmap leaves no dead space.
    private func scale(for l: RoadmapLayout) -> CGFloat {
        let natural = l.size.height + headerBlock
        guard avail > 0, natural > 0 else { return 1 }
        return min(1, avail / natural)   // shrink to fit; never upscale past natural size
    }

    var body: some View {
        let l = layout
        let s = scale(for: l)
        let scaledH = (l.size.height + headerBlock) * s
        let padTop = avail > scaledH ? ((avail - scaledH) / 2).rounded() : 0

        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    phaseHeaders(l)
                    diagram(l)
                }
                .frame(width: l.size.width, alignment: .topLeading)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: l.size.width * s, height: scaledH, alignment: .topLeading)
                .padding(.top, padTop)
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { avail = g.size.height }
                    .onChange(of: g.size.height) { _, h in avail = h }
            })
            .onAppear {
                // Open framed on the current move — the founder shouldn't hunt for it.
                if let id = currentId { proxy.scrollTo(id, anchor: .center) }
                prevStates = statusMap(tasks)
            }
            .onChange(of: tasks) { _, new in detectAdvances(new) }
        }
        .overlay(alignment: .leading) { if scrollEdge.left { edgeFade(.leading) } }
        .overlay(alignment: .trailing) { if scrollEdge.right { edgeFade(.trailing) } }
    }

    // MARK: phase headers

    // Left-aligned to each column's card edge (web places them at `c.x`), in their own
    // 28pt row above the diagram.
    private func phaseHeaders(_ l: RoadmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.columns) { c in
                HStack(spacing: 10) {
                    Text(c.phase.label(lang).uppercased())
                        .font(CodepetTheme.inter(10.5)).tracking(1.47)     // web .14em at 10.5px
                        .foregroundColor(c.current ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(c.current ? CodepetTokens.accentTint : CodepetTokens.well))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(c.current ? CodepetTokens.accentLine : CodepetTheme.hairline,
                                    lineWidth: 1))
                    Text("\(c.done)/\(c.total)")
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                .fixedSize()
                .offset(x: c.x, y: 0)
            }
        }
        .frame(width: l.size.width, height: 28, alignment: .topLeading)
    }

    // MARK: diagram

    private func diagram(_ l: RoadmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            edgeCanvas(l)
            if let r = l.root { rootNode(r) }
            ForEach(l.nodes) { n in
                let status = RoadmapEngine.status(for: n.task, in: tasks)
                let isCurrent = n.task.id == currentId
                RoadmapCardView(task: n.task, status: status, isCurrent: isCurrent,
                                herePhrase: herePhrase,
                                pulsing: pulseIds.contains(n.task.id),
                                onTap: { onTaskTap(n.task) })
                    // engine coords are TOP-LEFT; SwiftUI .position is center-based
                    .position(x: n.x + RoadmapGeometry.cardW / 2,
                              y: n.y + RoadmapGeometry.cardH / 2)
                    .zIndex(isCurrent ? 1 : 0)   // keep the floating marker above neighbours
                    .id(n.task.id)
                    .help(peekText(n.task, status: status))
            }
        }
        .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
    }

    private func edgeCanvas(_ l: RoadmapLayout) -> some View {
        Canvas { ctx, _ in
            func path(_ pts: [CGPoint]) -> Path {
                var p = Path()
                guard let first = pts.first else { return p }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                return p
            }
            // Root fan-out: solid, accent-tinted, its own style — never dashed, never critical.
            for e in l.rootEdges {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            // Faint dotted dependencies.
            for e in l.edges where !e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTokens.faint),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            // Critical path: a wide soft halo under a solid line.
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: l.size.width, height: l.size.height)
        .allowsHitTesting(false)
    }

    // MARK: root node

    // 172×118, accent gradient, the Codepet mark, and a blurred aura behind it so the origin
    // reads as the luminous root the whole tree grows from — not just another card.
    private func rootNode(_ r: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44)
                .fill(RadialGradient(colors: [CodepetTheme.accentPurple.opacity(0.42), .clear],
                                     center: .center, startRadius: 0, endRadius: r.width * 0.6))
                .frame(width: r.width + 52, height: r.height + 40)
                .blur(radius: 22)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 11) {
                Image("codepet-logo")
                    .resizable().interpolation(.none).scaledToFill()
                    .frame(width: 36, height: 36).clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(projectName)
                        .font(CodepetTheme.inter(19, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText).lineLimit(1)
                    if let tagline, !tagline.isEmpty {
                        Text(tagline).font(CodepetTheme.inter(11, weight: .medium))
                            .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
                    } else {
                        Text(lang == .vi ? "CÔNG TY CỦA BẠN" : "YOUR COMPANY")
                            .font(CodepetTheme.inter(9.5)).tracking(1.33)   // web .14em at 9.5px
                            .foregroundColor(CodepetTokens.accentDeep)
                    }
                }
            }
            .padding(15)
            .frame(width: r.width, height: r.height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [CodepetTheme.accentPurple.opacity(0.16),
                                              CodepetTheme.accentPurple.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(CodepetTheme.accentPurple.opacity(0.45), lineWidth: 1))
            .shadow(color: CodepetTheme.accentPurple.opacity(0.55), radius: 22, x: 0, y: 16)
        }
        .position(x: r.midX, y: r.midY)
    }

    private func edgeFade(_ edge: HorizontalAlignment) -> some View {
        LinearGradient(colors: edge == .leading
                       ? [CodepetTheme.pageBackground, .clear]
                       : [.clear, CodepetTheme.pageBackground],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: edge == .leading ? 48 : 56)
            .allowsHitTesting(false)
    }

    // MARK: advance pulse

    private func statusMap(_ ts: [RoadmapTask]) -> [String: TaskStatus] {
        Dictionary(uniqueKeysWithValues: ts.map { ($0.id, RoadmapEngine.status(for: $0, in: ts)) })
    }

    /// The "advance" moment (web `.rm-pulse`): a task became the current move, or a locked
    /// task unlocked because its prerequisites just completed → pulse it once, so finishing
    /// one step visibly lights up the next.
    private func detectAdvances(_ new: [RoadmapTask]) {
        let now = statusMap(new)
        guard !prevStates.isEmpty else { prevStates = now; return }
        let newCurrent = RoadmapEngine.nextStep(new)?.id
        var fresh = Set<String>()
        for (id, st) in now {
            guard let was = prevStates[id] else { continue }
            if was == .blocked && (st == .codepetCanDo || st == .needsYou) { fresh.insert(id) }
        }
        if let c = newCurrent, prevStates[c] == .blocked { fresh.insert(c) }
        prevStates = now
        guard !fresh.isEmpty else { return }
        pulseIds = fresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pulseIds.subtract(fresh) }
    }

    /// The hover peek's plain-language line — the founder learns a card without opening chat.
    private func peekText(_ task: RoadmapTask, status: TaskStatus) -> String {
        var parts: [String] = []
        if let d = DepartmentCatalog.find(task.dept)?.name {
            parts.append("\(d) · \(task.phase.label(lang))")
        }
        if !task.detail.isEmpty { parts.append(task.detail) }
        let deps = task.dependsOn.compactMap { id in tasks.first { $0.id == id }?.title }
        if !deps.isEmpty {
            parts.append((lang == .vi ? "Mở khoá sau: " : "Unlocks after: ") + deps.joined(separator: ", "))
        }
        let unlocks = tasks.filter { $0.dependsOn.contains(task.id) }.map(\.title)
        if !unlocks.isEmpty {
            parts.append((lang == .vi ? "Dẫn tới: " : "Leads to: ")
                         + unlocks.prefix(3).joined(separator: ", "))
        }
        switch status {
        case .codepetCanDo:
            parts.append(lang == .vi ? "Nước đi tiếp theo của \(companionName). Nhấn để bắt đầu."
                                     : "\(companionName)'s next move. Click to start.")
        case .needsYou:      parts.append(lang == .vi ? "Cần bạn nhập. Nhấn để thêm." : "Your input needed. Click to add it.")
        case .needsApproval: parts.append(lang == .vi ? "Bản nháp đã sẵn sàng. Nhấn để xem lại." : "Ready for your review.")
        case .done:          parts.append(lang == .vi ? "Xong. Nhấn để mở." : "Finished — click to open the result.")
        case .blocked:       parts.append(lang == .vi ? "Cần hoàn thành các bước trước." : "Locked — finish the earlier steps first.")
        }
        return parts.joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Retire the old board and engine**

The old page (`RoadmapView.swift`) is still routed until Task 8 replaces it, so repoint it at the
new board first — replace line 34's `RoadmapMapView(tasks: tasks)` with:

```swift
            RoadmapBoardView(tasks: tasks, companionName: companionName, founderName: nil,
                             projectName: (companyStore.company.brief.projectName ?? "Codepet"),
                             tagline: companyStore.company.brief.oneLiner,
                             onTaskTap: { dispatch($0) })
```

Then remove the old board and the engine it was the only consumer of:

```bash
cd ~/Desktop/codepet-wt-overview-parity
git rm codepet/Views/Roadmap/RoadmapMapView.swift \
       codepet/Models/RoadmapMapLayout.swift \
       codepetTests/RoadmapMapLayoutTests.swift
grep -rn "RoadmapMapLayout\|RoadmapMapView" codepet/ codepetTests/
```
Expected from the grep: no hits. Nothing to do in the project file — the synchronized group drops them automatically.

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -12`
Expected: `** BUILD SUCCEEDED **`

Then quit `codepet.app` and run the full suite:
`cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Verify the scroll-edge state actually toggles**

`scrollEdge` is declared but nothing sets it — SwiftUI's `ScrollView` has no `onScroll`. Wire it with a `GeometryReader` sentinel inside the scroll content that reports its frame in the `.named("board")` coordinate space, and set `scrollEdge.left = offset < -4`, `scrollEdge.right = contentWidth - offset - viewportWidth > 4`. If the sentinel approach proves flaky, delete the two `.overlay` fade modifiers and `scrollEdge` entirely and note the omission in the PR — a broken fade is worse than no fade. Do not leave dead state in the file.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add -A codepet/Views
git commit -m "feat(overview): web-exact roadmap board (lanes, orthogonal edges, luminous root)"
```

---

## Task 6: Unify into one Overview page

**Files:**
- Create: `codepet/Views/Overview/OverviewSectionView.swift`
- Modify: `codepet/Models/AppView.swift`, `codepet/Views/Shell/AppShellView.swift:37-40`, `codepet/Views/Copilot/CopilotChatView.swift:152`, `codepet/Views/SecondBrain/SecondBrainView.swift`
- Delete: `codepet/Views/Roadmap/RoadmapView.swift`
- Test: build-verified + a nav-routing test

**Interfaces:**
- Consumes: `RoadmapBoardView` (Task 5), `OverviewChromeRow` (Task 6), `OverviewIntroSheet` + `CompanyStore.markIntroSeen()` + `CompanyState.introSeenAt` (Task 7), `SecondBrainPanel` (existing)
- Produces: `AppView.overview`, `OverviewSectionView()`

**Execution order note:** this task runs AFTER Tasks 6 and 7, so every component it composes already exists. Do not create placeholder or stub versions of anything.

- [ ] **Step 1: Write the failing nav test**

Create `codepetTests/OverviewNavTests.swift`:

```swift
import XCTest
@testable import codepet

final class OverviewNavTests: XCTestCase {
    // Web has ONE Overview tab; the Roadmap ⁄ Second Brain split lives inside it.
    func testNavTabsHasOverviewAndNoSplitTabs() {
        XCTAssertTrue(AppView.navTabs.contains(.overview))
        XCTAssertFalse(AppView.navTabs.map(\.rawValue).contains("roadmap"))
        XCTAssertFalse(AppView.navTabs.map(\.rawValue).contains("secondBrain"))
    }

    // A chat nav chip saying "roadmap" must still land somewhere real.
    func testRoadmapNavDestinationResolvesToOverview() {
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .overview)
        XCTAssertEqual(AppView.from(navDestination: "overview"), .overview)
    }

    func testOverviewTitleLocalised() {
        XCTAssertEqual(AppView.overview.title(.en), "Overview")
        XCTAssertEqual(AppView.overview.title(.vi), "Tổng quan")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OverviewNavTests 2>&1 | tail -20`
Expected: compile failure — `type 'AppView' has no member 'overview'`.

- [ ] **Step 3: Update `AppView`**

In `codepet/Models/AppView.swift`: replace `case chat, roadmap, secondBrain, tasks, …` with

```swift
enum AppView: String, CaseIterable, Identifiable {
    case chat, overview, tasks, library, environment, company, settings, billing, support
```

then:

```swift
    /// Destinations shown in the rail, in order. Overview carries the Roadmap ⁄ Second Brain
    /// toggle internally (matching the web), so it occupies one slot, not two.
    static let navTabs: [AppView] = [.chat, .overview, .company, .tasks, .library, .environment]
```

In `title(_:)` replace the `.roadmap` and `.secondBrain` cases with:

```swift
        case .overview:    return lang == .vi ? "Tổng quan" : "Overview"
```

In `from(navDestination:)` replace `case "roadmap": return .roadmap` with:

```swift
        case "roadmap", "overview": return .overview
```

In `icon` replace the `.roadmap`/`.secondBrain` cases with:

```swift
        case .overview:    return "map"
```

- [ ] **Step 4: Update the shell and the chat entry point**

In `codepet/Views/Shell/AppShellView.swift`, replace the two branches at lines 37-40:

```swift
        } else if companyStore.view == .overview {
            OverviewSectionView()
```

In `codepet/Views/Copilot/CopilotChatView.swift:152`, `select(.roadmap)` → `select(.overview)`.

- [ ] **Step 5: Demote `SecondBrainView` to a panel**

Replace the body of `codepet/Views/SecondBrain/SecondBrainView.swift` — the header moves to the Overview page, so this is now just the panel:

```swift
// codepet/Views/SecondBrain/SecondBrainView.swift
import SwiftUI

/// The Second Brain surface — the right half of the Overview toggle (web: the `map` tab).
/// The page header lives in `OverviewSectionView`; this is the panel only. Department rows
/// still route to `.company`, which is how Company stays reachable without a rail slot.
struct SecondBrainView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        SecondBrainPanel(data: SecondBrainData(company: companyStore.company), lang: lang,
                         onOpenDept: { key in
                             companyStore.selectedDeptKey = key
                             companyStore.select(.company)
                         })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 6: Write the Overview page**

Create `codepet/Views/Overview/OverviewSectionView.swift`:

```swift
// codepet/Views/Overview/OverviewSectionView.swift
import SwiftUI

/// The Overview page — a native port of the web `OverviewSection.tsx`. One page, one header,
/// and a Roadmap ⁄ Second Brain toggle; the roadmap board is the hero and gets the space.
struct OverviewSectionView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    enum Mode: String { case roadmap, map }
    @State private var mode: Mode = .roadmap
    @State private var showIntro = false
    @State private var openDeliverable: Deliverable?

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var projectName: String {
        let p = (companyStore.company.brief.projectName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? (lang == .vi ? "Công ty của bạn" : "Your company") : p
    }
    private var founderName: String? {
        let n = (companyStore.company.brief.founderName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }
    private var oneLiner: String? {
        let o = (companyStore.company.brief.oneLiner ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return o.isEmpty ? nil : o
    }
    /// Codepet's read of the company for the briefing — web's fallback chain minus the AI
    /// `projectAnalysis` layer, which native doesn't have yet.
    private var briefSummary: String? {
        let s = (companyStore.company.brief.summary ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? oneLiner : s
    }
    /// Once we know the company, say whose it is and what it is; otherwise the generic framing.
    private var headerLine: String {
        if projectName != (lang == .vi ? "Công ty của bạn" : "Your company"), let o = oneLiner {
            return "\(projectName) — \(o)"
        }
        return lang == .vi
            ? "Toàn bộ công ty của bạn dưới dạng lộ trình — bạn đang ở đâu, \(companionName) làm gì tiếp, và bạn đã đi được bao xa."
            : "Your whole company as a roadmap — where you are, what \(companionName) does next, and how far you’ve come."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mode == .roadmap {
                header.padding(.horizontal, 24).padding(.top, 14)
                OverviewChromeRow(tasks: tasks, companionName: companionName,
                                  onStart: { dispatch($0) }, onOpenTask: { dispatch($0) })
                    .padding(.horizontal, 24).padding(.top, 16)
                RoadmapBoardView(tasks: tasks, companionName: companionName,
                                 founderName: founderName, projectName: projectName,
                                 tagline: oneLiner, onTaskTap: { dispatch($0) })
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The map fills the whole tab (its own surface); the toggle floats on top so
                // there's no strip seam between the toggle and the panel.
                SecondBrainView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { toggle.padding(.top, 16).padding(.leading, 24) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
        .sheet(isPresented: $showIntro) {
            OverviewIntroSheet(companionName: companionName, projectName: projectName,
                               summary: briefSummary, tasks: tasks, onDismiss: {
                                   showIntro = false
                                   companyStore.markIntroSeen()
                               })
        }
        .onAppear {
            // First run per account: the briefing shows once, then "How to read this map" reopens it.
            if companyStore.company.introSeenAt == nil { showIntro = true }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Tổng quan" : "Overview")
                    .font(CodepetTheme.inter(28, weight: .semibold)).tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(headerLine)
                    .font(CodepetTheme.inter(15)).foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                howToReadButton
                toggle
            }
        }
    }

    private var howToReadButton: some View {
        Button { showIntro = true } label: {
            HStack(spacing: 7) {
                Text("?").font(CodepetTheme.inter(10, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(CodepetTheme.accentPurple))
                Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                    .font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTokens.accentTint))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(CodepetTokens.accentLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // The toggle adapts to its surface: light on Roadmap, dark-glass on the Second Brain panel.
    private var toggle: some View {
        HStack(spacing: 3) {
            segment(.roadmap, lang == .vi ? "Lộ trình" : "Roadmap")
            segment(.map, lang == .vi ? "Bộ não" : "Second Brain")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    private func segment(_ m: Mode, _ label: String) -> some View {
        let on = mode == m
        return Button { mode = m } label: {
            Text(label)
                .font(CodepetTheme.inter(12.5, weight: .semibold))
                .foregroundColor(on ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(on ? CodepetTokens.accentTint : .clear))
        }
        .buttonStyle(.plain)
    }

    /// Route a task tap through the pure `RoadmapDispatch` rule, then follow the two
    /// streaming actions to chat, where their output appears.
    private func dispatch(_ task: RoadmapTask) {
        let action = RoadmapDispatch.action(for: RoadmapEngine.status(for: task, in: tasks))
        switch action {
        case .run:             Task { await companyStore.runTask(task, language: lang) }
        case .walkThrough:     Task { await companyStore.walkThroughTask(task, language: lang) }
        case .approve:         Task { await companyStore.approveTask(id: task.id) }
        case .openDeliverable: openDeliverable = RoadmapEngine.deliverable(
                                    for: task, in: companyStore.company.library)
        case .none:            break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.select(.chat) }
    }
}
```

`OverviewChromeRow`, `OverviewIntroSheet`, `company.introSeenAt` and `markIntroSeen()` all already exist — they were built in Tasks 6 and 7, which run before this one. Use them directly.

- [ ] **Step 7: Delete the old page and build**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git rm codepet/Views/Roadmap/RoadmapView.swift
rmdir codepet/Views/Roadmap 2>/dev/null || true
grep -rn "\.roadmap\b\|\.secondBrain\b" codepet/ | grep -v RoadmapPhase
```
Expected from the grep: no hits (other than `RoadmapPhase` cases).

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Run the nav test**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OverviewNavTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add -A codepet codepetTests
git commit -m "feat(overview): one Overview page with a Roadmap/Second Brain toggle (web parity)"
```

---

## Task 7: The chrome strip

**Files:**
- Create: `codepet/Views/Overview/OverviewChromeRow.swift`
- Test: build-verified

**Execution order note:** this task runs BEFORE the page that composes it (Task 8), so the file does not exist yet — create it. Nothing routes to it until Task 8; a build is the gate here.

**Interfaces:**
- Consumes: `RoadmapEngine.progressPercent(_:)`, `RoadmapEngine.nextStep(_:)`, `RoadmapEngine.status(for:in:)`, `RoadmapPalette.tint(for:)`, `CodepetTokens.well`/`accentTint`/`accentLine`/`accentDeep`
- Produces: `OverviewChromeRow(tasks:companionName:onStart:onOpenTask:)`

- [ ] **Step 1: Write the view**

Create `codepet/Views/Overview/OverviewChromeRow.swift`:

```swift
// codepet/Views/Overview/OverviewChromeRow.swift
import SwiftUI

/// Project Progress + Do This Next side by side, with the states KEY pushed right — one
/// compact top strip so the roadmap below gets the space. Native port of the strip in the
/// web `OverviewSection.tsx`.
struct OverviewChromeRow: View {
    let tasks: [RoadmapTask]
    let companionName: String
    let onStart: (RoadmapTask) -> Void
    let onOpenTask: (RoadmapTask) -> Void

    @Environment(\.uiLanguage) private var lang
    @State private var pinging = false

    /// The two cards sit side by side, each ~HUD-sized. The row is capped so they stay small.
    private let panelW: CGFloat = 430

    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var currentPhase: RoadmapPhase? { beacon?.phase }
    private var nextMilestone: String? {
        guard let p = currentPhase else { return nil }
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: p), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }
    /// The one actionable nudge kept on the compact card: tasks that need the founder.
    private var needsYou: Int {
        tasks.filter { !$0.done && !$0.drafted && $0.who == .you }.count
    }
    /// The founder often ALSO has a step waiting on them — surface the top one as a distinct
    /// secondary line under Start, never the same task as the move.
    private var alsoNeedsYou: RoadmapTask? {
        tasks.first { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou
                      && $0.id != beacon?.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            HStack(alignment: .top, spacing: 14) {
                progressCard
                if let b = beacon { beaconCard(b) }
            }
            .frame(maxWidth: panelW, alignment: .leading)
            Spacer(minLength: 0)
            key
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(lang == .vi ? "Tiến độ dự án" : "Project Progress")
                    .font(CodepetTheme.inter(12.5, weight: .semibold)).tracking(-0.125)
                    .foregroundColor(CodepetTheme.primaryText)
                if let p = currentPhase {
                    Text(p.label(lang))
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(CodepetTokens.accentTint))
                        .overlay(Capsule().stroke(CodepetTokens.accentLine, lineWidth: 1))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(pct)").font(CodepetTheme.inter(22, weight: .bold)).tracking(-0.66)
                        .foregroundColor(CodepetTheme.primaryText)
                        .monospacedDigit()
                    Text("%").font(CodepetTheme.inter(13, weight: .bold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                if needsYou > 0 {
                    Text(lang == .vi ? "cần bạn \(needsYou)" : "needs you \(needsYou)")
                        .font(CodepetTheme.inter(12)).foregroundColor(RoadmapPalette.needsYou)
                }
            }
            .padding(.top, 3).padding(.bottom, 6)
            progressBar
        }
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    // A 14pt well with a glowing gradient fill, and the next-milestone chip riding INSIDE
    // the bar at its right end (web: `position:absolute; right:5`).
    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(CodepetTokens.well)
                Capsule()
                    .fill(LinearGradient(colors: [CodepetTokens.accentDeep, CodepetTheme.accentPurple],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(pct > 0 ? 14 : 0, g.size.width * CGFloat(pct) / 100))
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.5), radius: 5.5)
                if let next = nextMilestone {
                    HStack {
                        Spacer()
                        Text((lang == .vi ? "Tiếp: " : "Next: ") + next)
                            .font(CodepetTheme.inter(10.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(CodepetTokens.accentTint))
                            .padding(.trailing, 5)
                    }
                }
            }
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8), value: pct)
        }
        .frame(height: 14)
    }

    private func beaconCard(_ b: RoadmapTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                pingDot
                Text("\(companionName) · " + (lang == .vi ? "LÀM ĐIỀU NÀY TIẾP" : "DO THIS NEXT"))
                    .font(CodepetTheme.inter(10)).tracking(1.3)      // web .13em at 10px
                    .foregroundColor(CodepetTheme.accentPurple)
                    .textCase(.uppercase)
            }
            Text(b.title).font(CodepetTheme.inter(13, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button { onStart(b) } label: {
                Text(lang == .vi ? "Bắt đầu" : "Start")
                    .font(CodepetTheme.inter(12.5, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(CodepetTheme.accentPurple))
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 7, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            if let also = alsoNeedsYou {
                Button { onOpenTask(also) } label: {
                    HStack(spacing: 5) {
                        Text(lang == .vi ? "Cũng cần bạn:" : "Also needs you:")
                            .foregroundColor(RoadmapPalette.needsYou.opacity(0.75))
                        Text(also.title).underline().lineLimit(1)
                            .foregroundColor(RoadmapPalette.needsYou)
                    }
                    .font(CodepetTheme.inter(11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help((lang == .vi ? "Cũng cần bạn: " : "Also needs you: ") + also.title)
            }
        }
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTokens.accentTint))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTokens.accentLine, lineWidth: 1))
    }

    // Web `@keyframes beaconPing`: a ring scaling 1→2.9 while fading .5→0, looping.
    private var pingDot: some View {
        ZStack {
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
                .scaleEffect(pinging ? 2.9 : 1).opacity(pinging ? 0 : 0.5)
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
                .shadow(color: CodepetTheme.accentPurple.opacity(0.6), radius: 6)
        }
        .frame(width: 13, height: 13)
        .onAppear {
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pinging = true
            }
        }
    }

    // Teaches a first-time user what the card colors mean. Order matches the web legend.
    private var key: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(lang == .vi ? "CHÚ THÍCH" : "KEY")
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1.2)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.bottom, 1)
            ForEach(keyItems, id: \.0) { item in
                HStack(spacing: 8) {
                    Circle().fill(item.1).frame(width: 7, height: 7)
                    Text(item.0).font(CodepetTheme.inter(11.5))
                        .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    private var keyItems: [(String, Color)] {
        [
            (lang == .vi ? "Xong" : "Done", RoadmapPalette.done),
            (lang == .vi ? "\(companionName) làm được" : "\(companionName) can do this", RoadmapPalette.canDo),
            (lang == .vi ? "Cần bạn nhập" : "Needs your input", RoadmapPalette.needsYou),
            (lang == .vi ? "Cần duyệt" : "Needs approval", RoadmapPalette.approve),
            (lang == .vi ? "Cần bước trước" : "Needs earlier steps", RoadmapPalette.blocked),
        ]
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -12`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add codepet/Views/Overview/OverviewChromeRow.swift
git commit -m "feat(overview): chrome strip — progress card, beacon card, states KEY"
```

---

## Task 8: First-run briefing + `introSeenAt`

**Files:**
- Create: `codepet/Views/Overview/OverviewIntroSheet.swift`
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`, `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyDataIntroSeenTests.swift`

**Execution order note:** this task runs BEFORE the page that presents the sheet (Task 8), so the sheet file does not exist yet — create it. Nothing presents it until Task 8.

**Interfaces:**
- Produces: `CompanyState.introSeenAt: Date?`, `CompanyDoc.introSeenAt: Double?`, `CompanyData.introSeenPayload(_:) -> [String: Any]`, `CompanyData.saveIntroSeen(companyId:at:) async -> Bool`, `CompanyStore.markIntroSeen()`, `OverviewIntroSheet(companionName:projectName:summary:tasks:onDismiss:)`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/CompanyDataIntroSeenTests.swift`:

```swift
import XCTest
@testable import codepet

final class CompanyDataIntroSeenTests: XCTestCase {
    // The web writes companies/{uid}.introSeenAt as MILLIS (schema.ts: `introSeenAt?: Millis`),
    // not an ISO string like onboardedAt — both clients read the same doc, so native must match.
    func testReadsMillisIntoADate() {
        let doc = CompanyDoc(introSeenAt: 1_753_900_000_000)
        let state = CompanyData.state(from: doc)
        XCTAssertEqual(state.introSeenAt?.timeIntervalSince1970 ?? 0, 1_753_900_000, accuracy: 0.001)
    }

    func testMissingFieldMeansNeverSeen() {
        XCTAssertNil(CompanyData.state(from: CompanyDoc()).introSeenAt)
        XCTAssertNil(CompanyData.state(from: nil).introSeenAt)
    }

    func testPayloadIsMillisNumber() {
        let at = Date(timeIntervalSince1970: 1_753_900_000)
        let payload = CompanyData.introSeenPayload(at)
        XCTAssertEqual(payload["introSeenAt"] as? Double, 1_753_900_000_000)
    }
}
```

`CompanyDoc` is a `Codable` struct with all-optional fields, so `CompanyDoc(introSeenAt:)` needs the memberwise initializer to accept it — verify the struct still has a usable memberwise init after Step 3 (it's internal and all fields are optional, so Swift synthesizes one with every field defaulted only if you add `= nil` defaults; add them if the test won't compile).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataIntroSeenTests 2>&1 | tail -20`
Expected: compile failure — `'CompanyDoc' has no member 'introSeenAt'`.

- [ ] **Step 3: Add the model field**

In `codepet/Models/CompanyState.swift`, add to `CompanyState` after `onboardedAt`:

```swift
    /// When this account first saw the Overview briefing. Account-scoped (not per-device) so
    /// the one-time intro doesn't reappear on another machine. Mirrors the web's
    /// `companies/{uid}.introSeenAt`.
    var introSeenAt: Date?
```

Add `introSeenAt: Date? = nil` to the memberwise init's parameter list (after `onboardedAt`) and `self.introSeenAt = introSeenAt` to its body.

- [ ] **Step 4: Add the persistence**

In `codepet/Services/CompanyData.swift`, add to `CompanyDoc` after `onboardedAt`:

```swift
    var introSeenAt: Double?   // epoch MILLIS (matches the web schema's `Millis`)
```

In `state(from:)` add to the `CompanyState(...)` call after `onboardedAt:`:

```swift
            introSeenAt: doc.introSeenAt.map { Date(timeIntervalSince1970: $0 / 1000) },
```

Add after `saveBrief`:

```swift
    /// Pure Firestore payload for the intro-seen write — testable without Firestore.
    /// Millis, not ISO: the web reads this same field as a number.
    static func introSeenPayload(_ at: Date) -> [String: Any] {
        ["introSeenAt": at.timeIntervalSince1970 * 1000]
    }

    /// Write companies/{uid}.introSeenAt, merge. Fail-soft: false on error — a lost write
    /// only means the briefing shows once more, never a broken page.
    static func saveIntroSeen(companyId: String, at: Date = Date()) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(introSeenPayload(at), merge: true)
            return true
        } catch {
            return false
        }
    }
```

In `codepet/Managers/CompanyStore.swift`, add:

```swift
    /// Remember that this account has seen the Overview briefing — locally at once (so the
    /// sheet closes for good this session) and persisted fail-soft.
    func markIntroSeen() {
        guard company.introSeenAt == nil else { return }
        let now = Date()
        company.introSeenAt = now
        guard let id = companyId else { return }
        Task { _ = await CompanyData.saveIntroSeen(companyId: id, at: now) }
    }
```

Check the actual name of the store's company-id property (`companyId` / `uid` / `authUid`) with `grep -n "companyId\|saveTasks(companyId" codepet/Managers/CompanyStore.swift` and use that.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataIntroSeenTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Write the briefing sheet**

Replace `codepet/Views/Overview/OverviewIntroSheet.swift` with:

```swift
// codepet/Views/Overview/OverviewIntroSheet.swift
import SwiftUI

/// The Overview briefing — Codepet introduces the map in its own voice. Auto-shows once per
/// account, and "How to read this map" reopens it any time, so the instructions are never
/// lost after the one-time dismissal. Native port of the modal in web `OverviewSection.tsx`.
struct OverviewIntroSheet: View {
    let companionName: String
    let projectName: String
    /// Codepet's one-line read of the company. Web prefers its AI `projectAnalysis.overall` and
    /// falls back through the brief; native has no analysis surface yet, so the caller passes
    /// `brief.summary ?? brief.oneLiner` and the paragraph is simply omitted when both are empty.
    let summary: String?
    let tasks: [RoadmapTask]
    let onDismiss: () -> Void

    @Environment(\.uiLanguage) private var lang

    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var currentPhase: String? { beacon?.phase.label(lang) }
    private var nextMilestone: String? {
        guard let p = beacon?.phase else { return nil }
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: p), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [CodepetTokens.accentDeep, CodepetTheme.accentPurple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.7), radius: 11, x: 0, y: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(companionName.uppercased())
                        .font(CodepetTheme.inter(10.5, weight: .semibold)).tracking(1.26)
                        .foregroundColor(CodepetTheme.accentPurple)
                    Text(lang == .vi ? "\(projectName), trên bản đồ" : "\(projectName), mapped")
                        .font(CodepetTheme.inter(19, weight: .bold)).tracking(-0.19)
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
            .padding(.bottom, 15)

            if let summary, !summary.isEmpty {
                Text(summary).font(CodepetTheme.inter(14.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(phaseLine).font(CodepetTheme.inter(13.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTokens.accentTint))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTokens.accentLine, lineWidth: 1))
            .padding(.bottom, 16)

            Text(lang == .vi ? "CÁCH ĐỌC BẢN ĐỒ" : "HOW TO READ THE MAP")
                .font(CodepetTheme.inter(12, weight: .semibold)).tracking(0.72)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(bullets, id: \.1) { color, head, body in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
                        (Text(head).font(CodepetTheme.inter(13.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                         + Text(" — \(body)").font(CodepetTheme.inter(13.5))
                            .foregroundColor(CodepetTheme.bodyText))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 22)

            Button(action: onDismiss) {
                Text(lang == .vi ? "Đã hiểu — xem ngay" : "Got it — show me")
                    .font(CodepetTheme.inter(14, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple))
                    .shadow(color: CodepetTheme.accentPurple.opacity(0.7), radius: 11, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 22)
        .frame(width: 440)
        .background(CodepetTheme.surface)
    }

    private var phaseLine: String {
        let phase = currentPhase ?? (lang == .vi ? "đầu tiên" : "first")
        var s = lang == .vi ? "Bạn đang ở giai đoạn \(phase)" : "You’re in the \(phase) phase"
        if let m = nextMilestone {
            s += lang == .vi ? " — mốc tiếp theo: \(m)." : " — next milestone: \(m)."
        } else {
            s += "."
        }
        if let t = beacon?.title {
            s += lang == .vi ? " Đầu tiên: \(t)." : " First up: \(t)."
        }
        return s
    }

    private var bullets: [(Color, String, String)] {
        [
            (RoadmapPalette.done,
             lang == .vi ? "Xanh là đã xong" : "Green is done",
             lang == .vi ? "bạn đã đi được bao xa." : "how far you’ve already come."),
            (CodepetTheme.accentPurple,
             lang == .vi ? "Thẻ đang sáng là nước đi tiếp theo" : "The glowing card is your next move",
             lang == .vi ? "nhấn Bắt đầu và tôi sẽ làm." : "hit Start and I’ll get to work."),
            (CodepetTheme.mutedText,
             lang == .vi ? "Thẻ mờ là đang khoá" : "Greyed-out steps are locked",
             lang == .vi ? "chúng mở khi bạn xong các bước phụ thuộc."
                         : "they unlock as you finish what they depend on."),
        ]
    }
}
```

- [ ] **Step 7: Build and run the full suite**

Quit `codepet.app`, then run:
`cd ~/Desktop/codepet-wt-overview-parity && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed|Failing tests" | tail -10`
Expected: `** TEST SUCCEEDED **` with an executed count ≥ the Task 0 baseline. A `TEST FAILED` with no `Failing tests:` lines means the app was still running — quit it and re-run.

- [ ] **Step 8: Commit**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git add -A codepet codepetTests
git commit -m "feat(overview): first-run briefing modal + account-scoped introSeenAt"
```

---

## Task 9: Visual verification against the live web

Everything above is source parity. This task is the only one that catches "the numbers are right but it looks wrong".

**Files:** none (verification + PR)

- [ ] **Step 1: Signed build**

Adhoc signing breaks the keychain and sign-in across rebuilds, so build TEAM-signed:

```bash
cd ~/Desktop/codepet-wt-overview-parity
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Launch, checking for a sibling instance first**

```bash
ps aux | grep -i "codepet.app" | grep -v grep
```
If another instance is running, it belongs to a concurrent session — **build only, do not `pkill` or relaunch**. Otherwise kill any stale pid and `open` the built app. Do not stop at "it looks the same": on native that means a stale build, not a bug.

- [ ] **Step 3: Side-by-side comparison**

Open `https://codepet-v1-2.vercel.app/` next to the app, both on the Overview tab, both in the same appearance (light, then dark). Walk this checklist:

- [ ] One Overview tab; the toggle switches Roadmap ⁄ Second Brain without a layout jump
- [ ] Title "Overview" + a two-line subtitle; "How to read this map" and the toggle sit top-right
- [ ] Progress card: phase chip, `NN%`, "needs you N", the "Next: …" chip riding inside the bar
- [ ] Beacon card: pinging dot, "codepet · do this next", Start (rounded rect, not a pill), "Also needs you"
- [ ] KEY: five rows — done is **green**, approval is **amber**
- [ ] Board rows form a **grid across columns** (department lanes), not per-column centered stacks
- [ ] Connectors are **right-angle elbows**, dotted for dependencies, and never cross a card
- [ ] The lit purple path covers only the edges touching the current move — not a chain back to the root
- [ ] The current card's "… is here" pill floats **above** the card, accent text on a surface pill
- [ ] Done cards show a **circle** dot and plain "Done" text; locked cards show plain text + the tray glyph; only actionable cards have pills
- [ ] The board opens with the current move roughly centered
- [ ] The company root reads as a luminous node with the Codepet mark, the name, and the tagline / "YOUR COMPANY"
- [ ] Dark mode: cards keep a visible edge against the page; dependency lines are visible

For each miss, note the web value and fix it — the numbers in Tasks 1–8 are the reference.

- [ ] **Step 4: Screenshot the result**

Save a light and a dark screenshot of the native Overview for the PR body.

- [ ] **Step 5: Open the PR**

```bash
cd ~/Desktop/codepet-wt-overview-parity
git push -u origin feat/overview-web-parity
gh pr create --base main --title "Overview → web parity: one page, dept lanes, orthogonal board" --body-file <(cat <<'BODY'
Brings the native Overview in line with the shipped web Overview.

- One Overview page with a Roadmap ⁄ Second Brain toggle (retires the two split rail tabs)
- Layout engine ported from `lib/overview/roadmapLayout.ts`: department lanes, orthogonal
  elbow connectors, current-task-only critical path, 208×64 cards
- Web-exact cards: floating "is here" marker, quiet states as text, circle dot for done,
  tray glyph on locked only
- Chrome strip: progress bar with the inner "Next:" chip, beacon card, states KEY
- First-run briefing modal + account-scoped `introSeenAt` (millis, shared with web)
- Ported the web's roadmap design tokens; `done` is now green (#16a34a) and approval amber
  (#d97706), matching web — this also recolors the department task cards

Verified side by side against https://codepet-v1-2.vercel.app/ in light and dark.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)
```

- [ ] **Step 6: Merge and verify prod**

Committed ≠ merged ≠ shipped. After review, merge to `main`, then confirm the merge commit is on `origin/main` and that a fresh build off `main` still shows the new Overview.

- [ ] **Step 7: Clean up the worktree**

```bash
cd ~/Developer/codepet && git worktree remove ~/Desktop/codepet-wt-overview-parity
```

---

## Deferred (explicitly not in this plan)

- **The briefing's AI summary layer.** Web's modal prefers `projectAnalysis.overall` (a generated one-line read of the company) and falls back through `brief.summary` → `brief.oneLiner`. Native has no `projectAnalysis` surface, so Task 8 implements the fallback chain only. Porting the analysis route is its own plan.
- **The `aiOffline` "Codepet is paused" banner.** Native has no offline/rate-limit state to drive it — that's a store + AI-client change, not an Overview change. Separate plan.
- **Native Second Brain ≠ web Second Brain.** Web's toggle opens the 3D force-graph nebula (`OverviewView.tsx`, three.js); native's is `SecondBrainPanel` (department rows). This plan puts them behind the same toggle but does not port the graph. Separate, much larger plan.
- **Shell nav shape.** Web is a centered text top-nav with count chips; native is a 64pt icon rail. Out of scope — it changes every page, not just Overview.
- **Card hover lift** (`.rm-node:hover{filter:brightness(1.14);transform:translateY(-1px)}`) and the **hover peek popover**. Native uses `.help()` tooltips, which carry the same content in the platform-native way. Revisit only if the user asks for the exact popover.
- **`--rm-locked-op` as a real environment-driven token.** Task 1 exposes it as a function of `colorScheme`; if a view needs it outside a SwiftUI environment, promote it then.

## Self-review notes

- **Audit coverage.** Every item in the audit maps to a task: structure → 6; header/chrome → 7; first-run → 8; board geometry/lanes/elbows/critical → 2, 5; cards → 3, 4; root → 5; palette/tokens → 1. The three items I deliberately dropped are listed under Deferred with reasons.
- **Type consistency.** `RoadmapLayoutEngine.layout` → `RoadmapLayout` is consumed only by `RoadmapBoardView`; `PositionedNode.x/y` is top-left everywhere and converted exactly once (Task 5, `.position(x: n.x + cardW/2, …)`). `RoadmapBoardCopy` names are identical in Task 3's tests, Task 4's card, and Task 5's board.
- **Known soft spot.** Task 5 Step 3 — SwiftUI has no scroll-offset callback, so the edge fades need a `GeometryReader` sentinel. The step gives an explicit permission to drop the fades rather than ship broken state, because guessing at a scroll-observation hack is the likeliest place for this plan to go wrong.
