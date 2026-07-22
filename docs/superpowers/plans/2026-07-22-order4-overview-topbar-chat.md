# Order 4 — Top bar + Overview map + Chat parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Make the native top bar, Overview, and chat match the web `develop`, on a web-matched type system.

**Architecture:** Phase 0 lands the GSF type scale (retrofitting order-3). Phase A replaces the sidebar with web top-bar tabs + account menu + Billing/Support views. Phase B replaces the phase-column board with a node-graph map (pure `RoadmapMapLayout` engine + `Canvas` `RoadmapMapView` + chrome). Phase C brings chat to web parity.

**Tech Stack:** Swift/SwiftUI (macOS 13+), existing `CodepetTheme`/GSF, `RoadmapEngine`, `CompanyStore`.

## Global Constraints

- **Web fidelity** — match `components/{Topbar,AccountMenu,Copilot}.tsx`, `components/views/{BillingView,SupportModal,overview/RoadmapView,OverviewSection}.tsx`, and `app/globals.css` in `/private/tmp/codepet-web-develop`. Use the exact copy + the type scale below.
- **TYPE SCALE (GSF via `CodepetTheme.inter`/roles; SwiftUI pt = web px), verbatim:** h1 **28** .semibold · subtitle **15** · dept name **25** .semibold · dept task line **16** · dept count **14** (bold num **30**) · task title **14** .semibold · task detail **12** · kanban **12.5** (title .medium / dept .bold) · nav tab **13** .medium · nav count **9** · account-menu item **13.5** · progress% **30** .bold · beacon title **21** .semibold · brand "Codepet" **PIXEL** 15. Titles are GSF, NOT pixel; pixel ONLY for the "Codepet" wordmark.
- **Single beacon** — the map "is here" node, progress card, and beacon card all read the SAME `RoadmapEngine.nextStep`.
- **Stubs (visible, faithful, wired to no-op/navigate):** Second Brain toggle, "Let's build", chat History, "Wake {companion} up" (→ Environment).
- **Branch:** native `feat/company-chat-cf`. iCloud git: implementer stops before commit; controller commits (`rm -f <gitdir>/index.lock`; background `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; verify HEAD). `-F` for messages.
- **Build authority:** `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO {build|test}` FOREGROUND. SourceKit "cannot find type/module" = false positives.

---

# PHASE 0 — Typography foundation

## Task 1: `pixelSystem` → always GSF + reusable type roles

**Files:** Modify `codepet/Views/CodepetTheme.swift`, `codepet/Views/SplashView.swift`, `codepet/Views/Onboarding/ReturningSignInView.swift`

- [ ] **Step 1: Make `pixelSystem` always GSF.** In `CodepetTheme.swift`, replace the `pixelSystem` body:

```swift
    static func pixelSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        _ = design
        // Web-matched: titles are Google Sans Flex, NOT pixel. Only the "Codepet"
        // brand wordmark uses CodepetTheme.pixel(_) directly.
        return CodepetTheme.inter(size, weight: weight)
    }
```

- [ ] **Step 2: Add type-role helpers** to `CodepetTheme` (after `inter(...)`):

```swift
    // MARK: Web-matched type roles (GSF at the web's px sizes)
    static func title() -> Font { inter(28, weight: .semibold) }        // .vhead h1
    static func subtitle() -> Font { inter(15) }                        // .vhead .sub
    static func sectionName() -> Font { inter(25, weight: .semibold) }  // .dr-name
    static func cardTitle() -> Font { inter(14, weight: .semibold) }    // .tk .tt
    static func cardDetail() -> Font { inter(12) }                      // .tk .td
    static func navTab() -> Font { inter(13, weight: .medium) }         // .tb-tab
    static func label(_ size: CGFloat = 12, _ w: Font.Weight = .medium) -> Font { inter(size, weight: w) }
```

- [ ] **Step 3: Keep the brand wordmarks pixel.** `SplashView.swift` "Codepet" `.font(.pixelSystem(size: 80, weight: .bold))` → `.font(CodepetTheme.pixel(80))`. `ReturningSignInView.swift` "Codepet" `.font(.pixelSystem(size: 30, weight: .bold))` → `.font(CodepetTheme.pixel(30))`.

- [ ] **Step 4: Build.** `xcodebuild … build` → BUILD SUCCEEDED. (Visual: titles are now clean GSF; Splash/Sign-in "Codepet" still pixel.)

- [ ] **Step 5: Controller commits.**

## Task 2: Retrofit order-3 views to the type scale

**Files:** Modify `codepet/Views/Company/CompanyView.swift`, `codepet/Views/Company/DepartmentDetailView.swift`, `codepet/Views/Tasks/TasksView.swift`

Replace undersized `.pixelSystem(size:)` calls with the web sizes (via roles or explicit inter). Key bumps (web px):
- **CompanyView:** dept **name → `CodepetTheme.sectionName()` (25)**; header h1 "Your company" → `CodepetTheme.title()` (28); subtitle → `subtitle()` (15); current-task line → `inter(16)`; count → `inter(14)` (the number where bold → `inter(30, weight:.bold)` if matching `.dr-count b`, else 14); status pill label → `inter(11.5, .semibold)`; "Open" → `inter(13, .semibold)`.
- **DepartmentDetailView:** hero name → `inter(21, .semibold)` (web dhero name); rationale → `inter(15)`; focus line → `inter(13)`; "What needs doing" → `inter(13, .semibold)`; task card title → `cardTitle()` (14); detail → `cardDetail()` (12); button → `inter(12, .semibold)`.
- **TasksView:** h1 "Tasks" → `title()` (28); subtitle → `subtitle()` (15); column label → `inter(12.5, .semibold)`; card dept → `inter(12.5, .bold)`; card title → `inter(12.5, .medium)` (`.kb-title`).

- [ ] **Step 1: Apply the size/role changes** across the three files (every `.font(.pixelSystem(size: N…))` → the web size above; titles via roles).
- [ ] **Step 2: Build.** `xcodebuild … build` → BUILD SUCCEEDED.
- [ ] **Step 3: Controller commits.**

---

# PHASE A — Top bar (retire sidebar)

## Task 3: Topbar counts helper (pure) + test

**Files:** Create `codepet/Models/TopbarCounts.swift`, `codepetTests/TopbarCountsTests.swift`

**Interfaces:** `enum TopbarCounts { static func tasks(_:[RoadmapTask])->Int; static func library(_:[Deliverable])->Int; static func envPending(enabled:Set<String>)->Int }`

- [ ] **Step 1: Failing test** `TopbarCountsTests.swift`:

```swift
import XCTest
@testable import codepet

final class TopbarCountsTests: XCTestCase {
    private func t(_ id: String, who: TaskWho, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, done: done)
    }
    func testTaskCount_openYouOrDraft() {
        let tasks = [t("a", who: .you), t("b", who: .draft), t("c", who: .does), t("d", who: .you, done: true)]
        XCTAssertEqual(TopbarCounts.tasks(tasks), 2)   // you + draft, not done; .does excluded
    }
    func testEnvPending() {
        // total catalog minus enabled
        let enabled = Set(Toolkit.all.prefix(3).map { $0.id })
        XCTAssertEqual(TopbarCounts.envPending(enabled: enabled), max(0, Toolkit.all.count - 3))
    }
}
```

- [ ] **Step 2: Fails** (`xcodebuild … test` → no `TopbarCounts`).
- [ ] **Step 3: Implement** `TopbarCounts.swift`:

```swift
import Foundation

enum TopbarCounts {
    static func tasks(_ tasks: [RoadmapTask]) -> Int {
        tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count
    }
    static func library(_ library: [Deliverable]) -> Int { library.count }
    static func envPending(enabled: Set<String>) -> Int { max(0, Toolkit.all.count - enabled.count) }
}
```

Note: confirm `Toolkit.all` exists (the 13-item catalog) with `.id`; if named differently (e.g. `Toolkit.catalog`), use that.

- [ ] **Step 4: Passes.** `xcodebuild … test` → TopbarCounts tests pass.
- [ ] **Step 5: Controller commits.**

## Task 4: `AppView` + routing for billing/support

**Files:** Modify `codepet/Models/AppView.swift`

- [ ] **Step 1:** Add `.billing`, `.support` cases (with titles + icons: billing "creditcard", support "questionmark.circle"). Keep existing cases. (These are reachable via the account menu, not the nav.)
- [ ] **Step 2: Build.** → BUILD SUCCEEDED. Controller commits (folded with Task 5's shell rewrite is fine).

## Task 5: Top bar rewrite in `AppShellView` (remove sidebar)

**Files:** Modify `codepet/Views/Shell/AppShellView.swift`; Create `codepet/Views/Shell/AccountMenuView.swift`

- [ ] **Step 1: Restructure `AppShellView.body`** — drop the `sidebar`; a full-width `topBar` carries brand + account menu + nav tabs + right controls; content area below routes on `companyStore.view` (add `.billing → BillingView()`, `.support → SupportView()`, keep `.company`/`.tasks`/etc from order 3). Structure:

```swift
    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !copilotCollapsed { Divider(); copilot }
            }
        }
        .background(CodepetTheme.pageBackground)
    }
```

`topBar` (faithful to `Topbar.tsx`): HStack —
  - brand `Text("Codepet").font(CodepetTheme.pixel(15))` + `AccountMenuView()`
  - `Spacer(minLength: 24)`
  - nav tabs: `ForEach([.overview,.company,.tasks,.library,.environment])` → a tab button: `Text(title).font(CodepetTheme.navTab())` accent when `companyStore.view == v`, an underline (`.overlay(Rectangle().frame(height:2))` when active), + a count badge (`inter(9,.semibold)` in a capsule) when `count(v) > 0`. Tap → `companyStore.select(v)` (clear `selectedDept` too). Counts from `TopbarCounts`.
  - `Spacer(minLength: 24)`
  - right: "⚡ Wake \(companionName) up" pill → `companyStore.select(.environment)`; "Upgrade" button → `companyStore.select(.billing)`.
  Padding `.horizontal 16 .vertical 10`. Keep the chat-collapse toggle (small icon) on the far right or in the chat header (Phase C).

`content` (@ViewBuilder): the existing routing switch + `.billing`/`.support` + Overview → `OverviewView()` (Phase B).

- [ ] **Step 2: `AccountMenuView.swift`** (faithful to `AccountMenu.tsx`) — a `Menu` triggered by an avatar (`CharacterImage(companyStore.company.companionId, size: 24)`) + founder name (`brief.founderName ?? "You"`, `inter(13,.medium)`):

```swift
Menu {
    Section { Text(founderName); if let e = email { Text(e).font(.caption) } }
    Button("Settings") { companyStore.select(.settings) }
    Button("Billing & Usage") { companyStore.select(.billing) }
    Button("Support") { companyStore.select(.support) }
    Menu("Appearance") {
        Button("System") { appState.appTheme = .system }
        Button("Light") { appState.appTheme = .light }
        Button("Dark") { appState.appTheme = .dark }
    }
    Divider()
    Button("Log out", role: .destructive) { authManager.signOut() }
} label: { HStack(spacing: 6) { CharacterImage(...); Text(founderName).font(CodepetTheme.label(13,.medium)) } }
```

Menu items use `inter(13.5)` where custom-styled; a native `Menu` uses system styling (acceptable) — or build a popover for exact fidelity if time allows (a popover with `.tb-menu a` = `inter(13.5)` rows is the faithful version; the plan permits the `Menu` fallback).

- [ ] **Step 3: Build** → BUILD SUCCEEDED.
- [ ] **Step 4: Controller commits.**

## Task 6: `BillingView` + `SupportView`

**Files:** Create `codepet/Views/Billing/BillingView.swift`, `codepet/Views/Support/SupportView.swift`; Modify `codepet/Views/Settings/SettingsView.swift` (remove its Plan section — moves to Billing)

- [ ] **Step 1: `BillingView`** (faithful to `BillingView.tsx`, native-appropriate): a Usage card ("Credits this month", static allowance display — reuse the Plan copy currently in Settings: Trial "Free · 7 days · ~150 credits" Current + Pro "$20/mo · 800 credits/mo · overage $0.05/credit" with a disabled "Upgrade — coming soon" pill). No BYOK. h1 "Billing & Usage" `title()`. (Move the exact Plan strings from `SettingsView`.)
- [ ] **Step 2: `SupportView`** (faithful to `SupportModal.tsx`): h1 "Support" + a message `TextEditor` + "Send" (disabled when empty) → writes via the existing feedback path (`FeatureFeedbackManager` — confirm its submit API; if it writes to Firestore `feedback`, reuse it) + a success line. If the feedback manager's API differs, adapt; keep it a real submit.
- [ ] **Step 3:** Remove the Plan section from `SettingsView` (Settings keeps companion/language/theme/edit-brief/sign-out).
- [ ] **Step 4: Build** → BUILD SUCCEEDED. Controller commits.

---

# PHASE B — Overview node-graph map

## Task 7: `RoadmapMapLayout` (pure engine) + tests

**Files:** Create `codepet/Models/RoadmapMapLayout.swift`, `codepetTests/RoadmapMapLayoutTests.swift`

**Interfaces:**
```swift
struct MapNode: Identifiable { let id: String; let task: RoadmapTask?; let x: CGFloat; let y: CGFloat }
struct MapEdge { let fromId: String; let toId: String; let critical: Bool }
struct RoadmapMap { let nodes: [MapNode]; let edges: [MapEdge]; let size: CGSize }
enum RoadmapMapLayout { static let rootId = "__root__"
    static func layout(_ tasks: [RoadmapTask], col: CGFloat = 260, row: CGFloat = 108, cardW: CGFloat = 200, cardH: CGFloat = 76, pad: CGFloat = 40) -> RoadmapMap }
```

- [ ] **Step 1: Failing test** `RoadmapMapLayoutTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapMapLayoutTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does, dependsOn: deps)
    }
    func testRootPresentAtLeft() {
        let m = RoadmapMapLayout.layout([t("a", .find)])
        let root = m.nodes.first { $0.id == RoadmapMapLayout.rootId }
        XCTAssertNotNil(root)
        XCTAssertLessThan(root!.x, m.nodes.first { $0.id == "a" }!.x)   // root left of tasks
    }
    func testPhaseIsColumn() {
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .build)])
        XCTAssertLessThan(m.nodes.first { $0.id == "a" }!.x, m.nodes.first { $0.id == "b" }!.x)
    }
    func testRootEdgeToDeplessFirstPhase() {
        let m = RoadmapMapLayout.layout([t("a", .find)])
        XCTAssertTrue(m.edges.contains { $0.fromId == RoadmapMapLayout.rootId && $0.toId == "a" })
    }
    func testDepEdge() {
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .foundation, deps: ["a"])])
        XCTAssertTrue(m.edges.contains { $0.fromId == "a" && $0.toId == "b" })
    }
    func testCriticalPathFromBeacon() {
        // beacon = first not-done dep-satisfied = a; b depends on a → edge a→b critical
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .foundation, deps: ["a"])])
        XCTAssertTrue(m.edges.first { $0.fromId == "a" && $0.toId == "b" }!.critical)
    }
    func testEmpty() {
        let m = RoadmapMapLayout.layout([])
        XCTAssertEqual(m.nodes.map(\.id), [RoadmapMapLayout.rootId])
        XCTAssertTrue(m.edges.isEmpty)
    }
}
```

- [ ] **Step 2: Fails.**
- [ ] **Step 3: Implement** `RoadmapMapLayout.swift`:

```swift
import CoreGraphics

struct MapNode: Identifiable { let id: String; let task: RoadmapTask?; let x: CGFloat; let y: CGFloat }
struct MapEdge { let fromId: String; let toId: String; let critical: Bool }
struct RoadmapMap { let nodes: [MapNode]; let edges: [MapEdge]; let size: CGSize }

enum RoadmapMapLayout {
    static let rootId = "__root__"

    static func layout(_ tasks: [RoadmapTask], col: CGFloat = 260, row: CGFloat = 108,
                       cardW: CGFloat = 200, cardH: CGFloat = 76, pad: CGFloat = 40) -> RoadmapMap {
        let phases = RoadmapPhase.allCases
        // group tasks by phase, preserving array order
        var byPhase: [RoadmapPhase: [RoadmapTask]] = [:]
        for t in tasks { byPhase[t.phase, default: []].append(t) }
        let maxRows = max(1, phases.map { byPhase[$0]?.count ?? 0 }.max() ?? 0)

        var nodes: [MapNode] = []
        var pos: [String: (CGFloat, CGFloat)] = [:]
        // root: column 0, vertically centered
        let rootX = pad
        let rootY = pad + CGFloat(maxRows - 1) * row / 2
        nodes.append(MapNode(id: rootId, task: nil, x: rootX, y: rootY))
        pos[rootId] = (rootX, rootY)
        // task columns: phaseOrder+1
        for (pi, phase) in phases.enumerated() {
            let list = byPhase[phase] ?? []
            let x = pad + CGFloat(pi + 1) * col
            let yOffset = CGFloat(maxRows - list.count) * row / 2   // center the column
            for (ri, task) in list.enumerated() {
                let y = pad + yOffset + CGFloat(ri) * row
                nodes.append(MapNode(id: task.id, task: task, x: x, y: y))
                pos[task.id] = (x, y)
            }
        }

        // beacon + its transitive dependency ids (for critical path)
        let beacon = RoadmapEngine.nextStep(tasks)
        var criticalIds = Set<String>()
        if let b = beacon {
            criticalIds.insert(b.id)
            var stack = b.dependsOn
            let byId = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            while let id = stack.popLast() {
                if criticalIds.insert(id).inserted, let dep = byId[id] { stack.append(contentsOf: dep.dependsOn) }
            }
        }

        var edges: [MapEdge] = []
        let firstPhase = phases.first
        for t in tasks {
            if t.dependsOn.isEmpty && t.phase == firstPhase {
                edges.append(MapEdge(fromId: rootId, toId: t.id,
                                     critical: criticalIds.contains(t.id)))
            }
            for dep in t.dependsOn where pos[dep] != nil {
                edges.append(MapEdge(fromId: dep, toId: t.id,
                                     critical: criticalIds.contains(t.id) && criticalIds.contains(dep)))
            }
        }

        let width = pad * 2 + CGFloat(phases.count + 1) * col
        let height = pad * 2 + CGFloat(maxRows) * row
        return RoadmapMap(nodes: nodes, edges: edges, size: CGSize(width: width, height: height))
    }
}
```

- [ ] **Step 4: Passes** (`xcodebuild … test` → 6 layout tests). **Step 5: Controller commits.**

## Task 8: `RoadmapMapView` (Canvas edges + positioned nodes)

**Files:** Create `codepet/Views/Overview/RoadmapMapView.swift`

- [ ] **Step 1: Implement** — a scrollable canvas of size `map.size`:
  - `ScrollView([.horizontal, .vertical])` containing a `ZStack(alignment: .topLeading)` sized `map.size`.
  - **Edge layer:** a `Canvas { ctx, _ in for e in map.edges { … } }` — for each edge, build a `Path` from the source node's right-center `(sx+cardW/2, sy)` to the target's left-center `(tx-cardW/2, ty)` (use a cubic with control points offset horizontally for a smooth curve). Stroke: critical → `CodepetTheme.accentPurple`, `lineWidth 2.5` (+ a wider low-opacity underlay for glow); else → `CodepetTheme.hairline`, `lineWidth 1`, dashed `[4,4]`. Node center positions come from the layout (pass the `[id: CGPoint]` map in).
  - **Node layer:** `ForEach(map.nodes)` → a card `.position(x: node.x, y: node.y)`:
    - root (task == nil): a distinct card — `CharacterImage` or Codepet glyph + company name (`inter(14,.semibold)`) + tagline (`inter(11)`), accent-tinted background + aura.
    - task: `RoadmapMapCard(task:allTasks:)` colored by `RoadmapEngine.status`: done → green tint + "Done" (`inter(11)`); beacon (`nextStep`) → accent gradient + glow + a floating "\(companionName) is here" pill above; codepetCanDo → "Start" filled chip; needsApproval → "Review"; needsYou → "Add your input"; blocked → padlock + dim + "Needs earlier steps". Title `cardTitle()`; dot per legend. Tap → `companyStore.runTask` when runnable. `.onHover` → a peek popover (`dept·phase` + a sentence + "Unlocks after: …"/"Leads to: …").
  - On first appear, scroll the beacon into view (ScrollViewReader + the beacon node id).
- [ ] **Step 2: Build** → BUILD SUCCEEDED (visual fidelity at E2E). **Step 3: Controller commits.**

## Task 9: `OverviewView` chrome (wraps the map)

**Files:** Create `codepet/Views/Overview/OverviewView.swift`; Modify `AppShellView` route `.overview → OverviewView()`

- [ ] **Step 1: Implement** (faithful to `OverviewSection.tsx`), stacking:
  - Header row: `Text("Overview").font(CodepetTheme.title())` + subtitle (`projectName — oneLiner`, `subtitle()`); top-right: a **Roadmap / Second Brain** segmented control (Second Brain selection shows a centered "Coming soon" placeholder instead of the map) + a "How to read this map" button (toggles the KEY legend/an intro sheet).
  - The existing **progress + beacon** chrome: reuse/adapt `RoadmapHeaderView` but upsize to web (progress % `inter(30,.bold)`, phase pill, "needs you {n}", "Next: {phase}"; beacon card with a **Start** button running `nextStep`, + "Also needs you: {2nd needsYou}"). Add the **KEY legend** column (5 dots + labels: Done, Codepet can do this, Needs your input, Needs approval, Needs earlier steps — web copy/colors).
  - Below: `RoadmapMapView(tasks: companyStore.company.tasks)` (Roadmap tab) filling remaining space; auto-generate on first empty appearance (`if tasks.isEmpty { await generateRoadmap(language:) }`).
- [ ] **Step 2: Build** → BUILD SUCCEEDED. (`OverviewBoardView` retired from the route; leave file.) **Step 3: Controller commits.**

---

# PHASE C — Chat parity

## Task 10: Chat shell parity in `CopilotChatView`

**Files:** Modify `codepet/Views/Copilot/CopilotChatView.swift`

- [ ] **Step 1: Header** — replace the bare top with "Your team" (`inter(14,.semibold)`) + "guiding · \(companyName)" (`inter(11)`, muted) + a **History** control (stub: a button that does nothing/opens a "coming soon" — threads aren't modeled) + the existing collapse toggle.
- [ ] **Step 2: Empty state** — personalized: `"Welcome, \(brief.founderName ?? "there"). Ask me anything about \(companyName) — where to focus, what's blocking you, or what to build next."` (`inter(13)`), then **3 quick-start chips** (`inter(12)`, tinted capsules) with exact copy: "What should I focus on first?", "Summarize where my company is", "What's blocking my launch?" — tap → `Task { await companyStore.sendChat(chipText, language: lang) }`.
- [ ] **Step 3: Footer** — a "Let's build" CTA button (`inter(12,.semibold)`, accent) as a stub (opens a "coming soon" note or is present/disabled). Input placeholder → "Ask \(companionName) anything about your company…".
- [ ] **Step 4: Build** → BUILD SUCCEEDED. **Step 5: Controller commits.**

---

# Task 11: End-to-end verification (manual — human checkpoint)

- [ ] Signed build (team `YL72VTKBR7`, no `CODE_SIGNING_ALLOWED=NO`) or Xcode ⌘R.
- [ ] **Typography:** all titles clean GSF (no pixelated headings); "Codepet" brand still pixel; Company/Overview text at web scale (dept name large).
- [ ] **Top bar:** nav tabs (Overview/Company/Tasks/Library/Environment + count badges), account menu (Settings/Billing/Support/Appearance/Log out works), Wake pill → Environment, Upgrade → Billing. No sidebar.
- [ ] **Overview:** title/subtitle, Roadmap/Second-Brain toggle, "How to read this map", progress + beacon (Start) + KEY legend, and the **node-graph map** — company root → dependency-linked cards, status colors, "{companion} is here" beacon, critical-path highlight, hover peek. Re-plan → map repopulates.
- [ ] **Chat:** "Your team" header, personalized welcome, 3 quick-start chips (tap sends), "Let's build" present.
- [ ] Update memory + handoff: order 4 shipped (topbar/nav, node-graph Overview, chat parity, app-wide GSF typography); stubs noted (Second Brain/Let's-build/History/Wake-install).

## Notes for executor
- **Phase B (map) is the hard part** — keep `RoadmapMapLayout` pure + tested; `RoadmapMapView` consumes it. Budget time on the Canvas edges + `.position` layout + scroll.
- Confirm token/API names before use: `Toolkit.all`/`.id`, `FeatureFeedbackManager` submit, `appState.appTheme`, `AuthManager.signOut`/`.currentUser?.email`, `RoadmapHeaderView` internals. Substitute the real names; don't invent.
- Build after each task; reviewer subagent gates each phase; the E2E (Task 11) is the human visual gate.
