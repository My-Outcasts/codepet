# Chat-First Shell — Phase 1: Structure (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the top-bar tab row with a left rail, make `.chat` the launch destination, and split the Overview page into standalone Roadmap and Second Brain pages — leaving a working app in which chat is a full-width panel.

**Architecture:** `AppView` gains `chat` and `secondBrain` and loses `overview` and `summary`. `AppShellView` drops the 50%-width docked Copilot panel and its FAB, gaining `AppRailView` on the left and a slim top bar. Overview's chrome relocates to a new `RoadmapView`; `SecondBrainPanel` gets a thin page wrapper. Routing logic that used to live inline in `OverviewView.dispatch(_:)` is extracted into a pure `RoadmapDispatch` so the new "follow the action to chat" rule is unit-testable.

**Tech Stack:** SwiftUI (macOS), XCTest, Firebase (untouched here). Xcode 26.4.

## Global Constraints

- Deployment target is macOS **26.2**; `SWIFT_VERSION` is **5.0**. Do not raise or lower either.
- Every user-facing string needs **both** English and Vietnamese, via `lang == .vi ? "…" : "…"`, matching every existing view.
- **No literal hex colours in views.** Use `CodepetTheme` tokens only; new tokens go in `CodepetTheme.swift` as `Color.dyn(light, dark)`.
- Pixel art renders with `.interpolation(.none)`.
- Tests are **XCTest** (`import XCTest` / `@testable import codepet`), not Swift Testing.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so **new files and folders under `codepet/` need no `project.pbxproj` edit**. Do not hand-edit `project.pbxproj`.
- Branch: `feat/chat-first-shell`. Commit after every task.
- **Out of scope in Phase 1:** the chat landing hero, the composer redesign, and restyling `CopilotChatView`. Those are Phase 2. Chat here is simply the full-width existing `CopilotChatView`.

**Reference commands** (run from `~/Developer/codepet`):

```bash
# Build
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5

# Run one test class
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/AppViewTests 2>&1 | tail -20
```

Build success prints `** BUILD SUCCEEDED **`; test success prints `** TEST SUCCEEDED **`.

---

## File Structure

| File | Responsibility |
|---|---|
| `codepet/Models/AppView.swift` (modify) | Destination enum, rail order, titles, icons, chat-nav mapping |
| `codepet/Models/RoadmapDispatch.swift` (create) | Pure: task status → action, and whether it follows to chat |
| `codepet/Managers/CompanyStore.swift` (modify, line 10) | Default destination |
| `codepet/Views/SecondBrain/SecondBrainView.swift` (create) | Second Brain page wrapper |
| `codepet/Views/SecondBrain/SecondBrainPanel.swift` (move) | Unchanged panel body |
| `codepet/Views/Roadmap/RoadmapView.swift` (create) | Roadmap page: header, progress, beacon, legend, map |
| `codepet/Views/Roadmap/RoadmapMapView.swift`, `TaskCardView.swift` (move) | Unchanged map + card |
| `codepet/Views/Shell/AppRailView.swift` (create) | Left rail: brand, destinations, account |
| `codepet/Views/Shell/AppShellView.swift` (modify) | Rail + slim top bar + content switch |
| `codepetTests/AppViewTests.swift` (modify) | Enum + nav-mapping assertions |
| `codepetTests/RoadmapDispatchTests.swift` (create) | Dispatch routing rules |

**Deleted in Task 8:** `Views/Overview/` entirely (`OverviewView`, plus the already-unreachable `OverviewBoardView`, `RoadmapHeaderView`, `PhaseColumnView`) and `Views/Summary/SummaryView.swift`, `Models/SummaryData.swift`, `codepetTests/SummaryDataTests.swift`.

---

### Task 1: Destination enum

**Files:**
- Modify: `codepet/Models/AppView.swift` (whole file)
- Test: `codepetTests/AppViewTests.swift:5-8` (existing assertion) + new cases

**Interfaces:**
- Consumes: `AppLanguage` (existing, `.en` / `.vi`)
- Produces: `AppView` with cases `chat, roadmap, secondBrain, tasks, library, environment, company, settings, billing, support`; `AppView.navTabs: [AppView]`; `AppView.from(navDestination: String) -> AppView?`; `title(_ lang: AppLanguage) -> String`; `icon: String`

- [ ] **Step 1: Update the failing test**

Replace the body of `testCoversAllAppDestinations` and add two new tests in `codepetTests/AppViewTests.swift`:

```swift
    func testCoversAllAppDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["chat", "roadmap", "secondBrain", "tasks", "library",
                        "environment", "company", "settings", "billing", "support"])
    }

    func testRailShowsSixDestinationsInOrder() {
        XCTAssertEqual(AppView.navTabs, [.chat, .roadmap, .secondBrain, .tasks, .library, .environment])
    }

    func testRoadmapNavDestinationResolvesToRoadmapNotOverview() {
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
        XCTAssertEqual(AppView.from(navDestination: "department"), .company)
        XCTAssertNil(AppView.from(navDestination: "nope"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/Developer/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' -only-testing:codepetTests/AppViewTests 2>&1 | tail -20
```

Expected: compile failure — `type 'AppView' has no member 'chat'`.

- [ ] **Step 3: Replace `codepet/Models/AppView.swift` entirely**

```swift
import Foundation

/// The app's top-level destinations. Chat is the primary surface; Roadmap and
/// Second Brain are the two halves of the retired Overview page.
enum AppView: String, CaseIterable, Identifiable {
    case chat, roadmap, secondBrain, tasks, library, environment, company, settings, billing, support

    var id: String { rawValue }

    /// Destinations shown in the left rail, in order. `company` is reached from a
    /// Second Brain department row; settings / billing / support from the account menu.
    static let navTabs: [AppView] = [.chat, .roadmap, .secondBrain, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .chat:        return lang == .vi ? "Trò chuyện" : "Chat"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .secondBrain: return lang == .vi ? "Bộ não" : "Second Brain"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .settings:    return lang == .vi ? "Cài đặt" : "Settings"
        case .billing:     return lang == .vi ? "Thanh toán" : "Billing & Usage"
        case .support:     return lang == .vi ? "Hỗ trợ" : "Support"
        }
    }

    /// Resolve a chat `nav` action's `destination` string. `department` resolves to
    /// `.company`; the caller additionally sets `selectedDeptKey` from `target` so
    /// `.company` opens on that department. Unknown destinations return nil so an
    /// unresolvable chip is a no-op.
    static func from(navDestination raw: String) -> AppView? {
        switch raw {
        case "roadmap":     return .roadmap
        case "tasks":       return .tasks
        case "library":     return .library
        case "company":     return .company
        case "environment": return .environment
        case "department":  return .company
        default:            return nil
        }
    }

    /// SF Symbol shown in the rail.
    var icon: String {
        switch self {
        case .chat:        return "bubble.left"
        case .roadmap:     return "map"
        case .secondBrain: return "brain"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .company:     return "building.2"
        case .settings:    return "gearshape"
        case .billing:     return "creditcard"
        case .support:     return "questionmark.circle"
        }
    }
}
```

- [ ] **Step 4: Fix the two now-broken references so the module compiles**

`CompanyStore.swift:10` still says `.overview`; `AppShellView.swift` still branches on `.overview` and `.summary`. Apply the minimum to compile — Task 3 and Task 7 do the real work.

In `codepet/Managers/CompanyStore.swift` line 10:

```swift
    @Published var view: AppView = .chat
```

In `codepet/Views/Shell/AppShellView.swift`, delete these two branches from `content`:

```swift
        if companyStore.view == .summary {
            SummaryView()
        } else if companyStore.view == .overview {
            OverviewView()
        } else if companyStore.view == .company {
```

so the chain now begins:

```swift
        if companyStore.view == .company {
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd ~/Developer/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' -only-testing:codepetTests/AppViewTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 3 tests passing.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Models/AppView.swift codepet/Managers/CompanyStore.swift \
        codepet/Views/Shell/AppShellView.swift codepetTests/AppViewTests.swift
git commit -m "feat: add chat and secondBrain destinations, retire overview and summary"
```

---

### Task 2: Pure roadmap dispatch

Extracts the routing rule from `OverviewView.dispatch(_:)` so the new behaviour — run and walk-through follow the founder to chat, approve and open-deliverable stay put — is testable without a view.

**Files:**
- Create: `codepet/Models/RoadmapDispatch.swift`
- Test: `codepetTests/RoadmapDispatchTests.swift`

**Interfaces:**
- Consumes: `TaskStatus` (`codepet/Models/RoadmapTask.swift:57`, cases `done, needsApproval, blocked, needsYou, codepetCanDo`)
- Produces: `RoadmapAction` (`.run`, `.walkThrough`, `.approve`, `.openDeliverable`, `.none`); `RoadmapDispatch.action(for: TaskStatus) -> RoadmapAction`; `RoadmapDispatch.navigatesToChat(_ action: RoadmapAction) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/RoadmapDispatchTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapDispatchTests: XCTestCase {
    func testActionPerStatus() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo), .run)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsYou), .walkThrough)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsApproval), .approve)
        XCTAssertEqual(RoadmapDispatch.action(for: .done), .openDeliverable)
        XCTAssertEqual(RoadmapDispatch.action(for: .blocked), RoadmapAction.none)
    }

    /// Only the two actions whose output streams into chat should move the founder there.
    func testOnlyStreamingActionsNavigateToChat() {
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.run))
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.walkThrough))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.approve))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.openDeliverable))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(RoadmapAction.none))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/Developer/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' -only-testing:codepetTests/RoadmapDispatchTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'RoadmapDispatch' in scope`.

- [ ] **Step 3: Create `codepet/Models/RoadmapDispatch.swift`**

```swift
import Foundation

/// What tapping a roadmap task does.
enum RoadmapAction: Equatable {
    case run              // Codepet can do it — output streams into chat
    case walkThrough      // needs the founder — the walkthrough streams into chat
    case approve          // needs approval — resolves in place
    case openDeliverable  // done — opens the deliverable sheet in place
    case none             // blocked — nothing to do yet
}

/// Pure routing rule for a roadmap task tap. Kept out of the view so the
/// "follow the action to chat" behaviour is testable on its own.
enum RoadmapDispatch {
    static func action(for status: TaskStatus) -> RoadmapAction {
        switch status {
        case .codepetCanDo:  return .run
        case .needsYou:      return .walkThrough
        case .needsApproval: return .approve
        case .done:          return .openDeliverable
        case .blocked:       return .none
        }
    }

    /// True when the action's result appears in chat, so the shell should select
    /// `.chat` after dispatching it.
    static func navigatesToChat(_ action: RoadmapAction) -> Bool {
        action == .run || action == .walkThrough
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ~/Developer/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' -only-testing:codepetTests/RoadmapDispatchTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 2 tests passing.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Models/RoadmapDispatch.swift codepetTests/RoadmapDispatchTests.swift
git commit -m "feat: extract pure RoadmapDispatch routing rule"
```

---

### Task 3: Second Brain page

**Files:**
- Create: `codepet/Views/SecondBrain/SecondBrainView.swift`
- Move: `codepet/Views/Overview/SecondBrainPanel.swift` → `codepet/Views/SecondBrain/SecondBrainPanel.swift` (contents unchanged)

**Interfaces:**
- Consumes: `SecondBrainData(company:)`, `SecondBrainPanel(data:lang:onOpenDept:)`, `CompanyStore.selectedDeptKey`, `CompanyStore.select(_:)`
- Produces: `SecondBrainView()` — takes no arguments, reads the store from the environment

- [ ] **Step 1: Move the panel with git so history follows**

```bash
cd ~/Developer/codepet
mkdir -p codepet/Views/SecondBrain
git mv codepet/Views/Overview/SecondBrainPanel.swift codepet/Views/SecondBrain/SecondBrainPanel.swift
```

- [ ] **Step 2: Create `codepet/Views/SecondBrain/SecondBrainView.swift`**

```swift
// codepet/Views/SecondBrain/SecondBrainView.swift
import SwiftUI

/// The Second Brain page — was the right half of the retired Overview toggle.
/// A thin wrapper: header plus the unchanged panel. Department rows still route
/// to `.company`, which is how Company stays reachable without a rail slot.
struct SecondBrainView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Bộ não" : "Second Brain")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Những gì Codepet biết về công ty của bạn"
                                 : "What Codepet knows about your company")
                    .font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 24).padding(.top, 22)

            SecondBrainPanel(data: SecondBrainData(company: companyStore.company), lang: lang,
                             onOpenDept: { key in
                                 companyStore.selectedDeptKey = key
                                 companyStore.select(.company)
                             })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd ~/Developer/codepet && xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (`SecondBrainView` is not routed yet — Task 7 wires it.)

- [ ] **Step 4: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Views/SecondBrain
git commit -m "feat: add Second Brain page wrapper"
```

---

### Task 4: Roadmap page

Relocates Overview's chrome. `progressCard`, `beaconCard`, `legend` and `mapIntroBriefing` are copied across essentially verbatim; the only behavioural change is that dispatch goes through `RoadmapDispatch` and selects `.chat` for streaming actions.

**Files:**
- Create: `codepet/Views/Roadmap/RoadmapView.swift`
- Move: `codepet/Views/Overview/RoadmapMapView.swift` → `codepet/Views/Roadmap/RoadmapMapView.swift`
- Move: `codepet/Views/Overview/TaskCardView.swift` → `codepet/Views/Roadmap/TaskCardView.swift`
- Delete: `codepet/Views/Overview/OverviewView.swift`

`RoadmapView` supersedes `OverviewView`, and Task 1 already removed the `.overview` branch from `AppShellView`, so `OverviewView` is unreferenced by the time this task starts. It is deleted here, in the same commit, so this is a move rather than a copy — leaving both files in place would put ~250 duplicated lines on the branch for three tasks.

**Interfaces:**
- Consumes: `RoadmapDispatch` (Task 2); `RoadmapEngine.progressPercent(_:)`, `.nextStep(_:)`, `.status(for:in:)`, `.deliverable(for:in:)`; `taskStatusTint(_:)`; `RoadmapMapView(tasks:)`; `DeliverableDetailView(deliverable:)`; `RoadmapPhase.allCases` / `.label(_:)`; `CompanyStore.runTask/walkThroughTask/approveTask/generateRoadmap/select`
- Produces: `RoadmapView()` — no arguments

- [ ] **Step 1: Move the map and card with git**

```bash
cd ~/Developer/codepet
mkdir -p codepet/Views/Roadmap
git mv codepet/Views/Overview/RoadmapMapView.swift codepet/Views/Roadmap/RoadmapMapView.swift
git mv codepet/Views/Overview/TaskCardView.swift codepet/Views/Roadmap/TaskCardView.swift
```

- [ ] **Step 2: Create `codepet/Views/Roadmap/RoadmapView.swift`**

```swift
// codepet/Views/Roadmap/RoadmapView.swift
import SwiftUI

/// The Roadmap page — was the left half of the retired Overview toggle, and now
/// owns the chrome that page carried: progress, the beacon, the KEY legend and the
/// "how to read this map" briefing, over the node-graph map.
struct RoadmapView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showMapIntro = false
    @State private var beaconPinging = false
    @State private var openDeliverable: Deliverable?

    private var tasks: [RoadmapTask] { companyStore.company.tasks }
    private var pct: Int { RoadmapEngine.progressPercent(tasks) }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var needsYouCount: Int {
        tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou }.count
    }
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var subtitle: String {
        let p = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let o = (companyStore.company.brief.oneLiner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty && o.isEmpty { return lang == .vi ? "Lộ trình xây dựng công ty của bạn" : "Your company-building roadmap" }
        return [p, o].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 22)
            chromeRow.padding(.horizontal, 24).padding(.top, 14)
            RoadmapMapView(tasks: tasks).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Lộ trình" : "Roadmap")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(CodepetTheme.subtitle())
                    .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
            Spacer()
            Button { showMapIntro = true } label: {
                HStack(spacing: 8) {
                    Text("?").font(CodepetTheme.inter(11, weight: .bold)).foregroundColor(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(CodepetTheme.accentPurple))
                    Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                        .font(CodepetTheme.inter(13, weight: .medium)).foregroundColor(CodepetTheme.accentPurple)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.accentPurple.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMapIntro) { mapIntroBriefing }
        }
    }

    private var chromeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            progressCard
            if let b = beacon { beaconCard(b) }
            Spacer()
            legend
        }
    }

    private var alsoNeedsYou: RoadmapTask? {
        tasks.filter { !$0.done && RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != beacon?.id }.first
    }

    /// Routes a task tap through the pure rule, then follows streaming actions to chat.
    private func dispatch(_ task: RoadmapTask) {
        let action = RoadmapDispatch.action(for: RoadmapEngine.status(for: task, in: tasks))
        switch action {
        case .run:              Task { await companyStore.runTask(task, language: lang) }
        case .walkThrough:      Task { await companyStore.walkThroughTask(task, language: lang) }
        case .approve:          Task { await companyStore.approveTask(id: task.id) }
        case .openDeliverable:  openDeliverable = RoadmapEngine.deliverable(for: task, in: companyStore.company.library)
        case .none:             break
        }
        if RoadmapDispatch.navigatesToChat(action) { companyStore.select(.chat) }
    }

    private var currentPhase: RoadmapPhase { beacon?.phase ?? .find }
    private var nextPhaseLabel: String? {
        let all = RoadmapPhase.allCases
        guard let i = all.firstIndex(of: currentPhase), i + 1 < all.count else { return nil }
        return all[i + 1].label(lang)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(lang == .vi ? "Tiến độ" : "Project Progress")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                Text(currentPhase.label(lang)).font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(pct)").font(CodepetTheme.inter(30, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Text("%").font(CodepetTheme.inter(14, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
                if needsYouCount > 0 {
                    Text(lang == .vi ? "cần bạn \(needsYouCount)" : "needs you \(needsYouCount)")
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.accentBlue)
                }
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(pct), total: 100).tint(CodepetTheme.accentPurple).frame(width: 120)
                if let next = nextPhaseLabel {
                    Text((lang == .vi ? "Tiếp: " : "Next: ") + next)
                        .font(CodepetTheme.inter(10, weight: .medium)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    private func beaconCard(_ b: RoadmapTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                beaconPingDot
                Text("\(companionName.uppercased()) · " + (lang == .vi ? "LÀM ĐIỀU NÀY TIẾP" : "DO THIS NEXT"))
                    .font(CodepetTheme.inter(10, weight: .bold)).foregroundColor(CodepetTheme.accentPurple)
            }
            Text(b.title).font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button { dispatch(b) } label: {
                Text(lang == .vi ? "Bắt đầu" : "Start")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }.buttonStyle(.plain)
            if let also = alsoNeedsYou {
                Button { dispatch(also) } label: {
                    Text((lang == .vi ? "Cũng cần bạn: " : "Also needs you: ") + also.title)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.accentBlue).lineLimit(1)
                        .underline()
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(CodepetTheme.accentPurple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CodepetTheme.accentPurple.opacity(0.3), lineWidth: 1))
    }

    private var beaconPingDot: some View {
        ZStack {
            Circle().fill(CodepetTheme.accentPurple)
                .frame(width: 13, height: 13)
                .scaleEffect(beaconPinging ? 2.9 : 1)
                .opacity(beaconPinging ? 0 : 0.5)
            Circle().fill(CodepetTheme.accentPurple).frame(width: 13, height: 13)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                beaconPinging = true
            }
        }
    }

    private var mapIntroBriefing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang == .vi ? "Cách đọc bản đồ" : "How to read this map")
                .font(CodepetTheme.inter(13, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text((lang == .vi ? "Giai đoạn hiện tại: " : "Current phase: ") + currentPhase.label(lang))
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.accentPurple)
                if let next = nextPhaseLabel {
                    Text((lang == .vi ? "Tiếp theo: " : "Next: ") + next)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                if let title = beacon?.title {
                    Text((lang == .vi ? "Bước tiếp theo: " : "Up next: ") + title)
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            legend
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private var legend: some View {
        let items: [(String, Color)] = [
            (lang == .vi ? "Xong" : "Done", taskStatusTint(.done)),
            (lang == .vi ? "\(companionName) làm được" : "\(companionName) can do this", taskStatusTint(.codepetCanDo)),
            (lang == .vi ? "Cần bạn nhập" : "Needs your input", taskStatusTint(.needsYou)),
            (lang == .vi ? "Cần duyệt" : "Needs approval", taskStatusTint(.needsApproval)),
            (lang == .vi ? "Cần bước trước" : "Needs earlier steps", taskStatusTint(.blocked)),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text(lang == .vi ? "CHÚ THÍCH" : "KEY")
                .font(CodepetTheme.inter(10, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
            ForEach(items, id: \.0) { it in
                HStack(spacing: 6) {
                    Circle().fill(it.1).frame(width: 7, height: 7)
                    Text(it.0).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Delete the superseded page**

`OverviewView` is unreferenced from Task 1 onward, and `RoadmapView` now carries its chrome. Remove it in this commit so the change reads as a move:

```bash
cd ~/Developer/codepet && git rm -q codepet/Views/Overview/OverviewView.swift
```

- [ ] **Step 4: Build to verify it compiles**

```bash
cd ~/Developer/codepet && xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If it fails on `RoadmapMapView` not found, the `git mv` in Step 1 did not complete — re-run it. If it fails on `OverviewView` not found, something still references it — find it with `grep -rn OverviewView codepet` and stop; that reference should have gone in Task 1.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add -A codepet/Views/Roadmap codepet/Views/Overview
git commit -m "feat: replace Overview page with a standalone Roadmap page"
```

---

### Task 5: Left rail

**Files:**
- Create: `codepet/Views/Shell/AppRailView.swift`

**Interfaces:**
- Consumes: `AppView.navTabs`, `AppView.icon`, `AppView.title(_:)`, `CompanyStore.view`, `CompanyStore.select(_:)`, `CompanyStore.selectedDeptKey`, `AccountMenuView()`, `TopbarCounts`
- Produces: `AppRailView(accent: Color)` — the caller supplies the companion accent the shell already computes

- [ ] **Step 1: Create `codepet/Views/Shell/AppRailView.swift`**

```swift
// codepet/Views/Shell/AppRailView.swift
import SwiftUI

/// The left navigation rail — replaces the top bar's centred tab row. Six
/// destinations from `AppView.navTabs`, the active one tinted with the companion
/// accent, and the account menu pinned to the bottom.
struct AppRailView: View {
    let accent: Color

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private static let width: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            Text("C").font(CodepetTheme.pixel(18)).foregroundColor(CodepetTheme.primaryText)
                .frame(height: 40)
            ForEach(AppView.navTabs) { item($0) }
            Spacer()
            AccountMenuView().padding(.bottom, 10)
        }
        .frame(width: Self.width)
        .padding(.top, 8)
        .background(CodepetTheme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
        }
    }

    private func item(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = badge(v)
        return Button {
            companyStore.selectedDeptKey = nil
            companyStore.select(v)
        } label: {
            Image(systemName: v.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(on ? accent : CodepetTheme.mutedText)
                .frame(width: 40, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(on ? accent.opacity(0.14) : .clear))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(CodepetTheme.inter(9, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(CodepetTheme.accentGold))
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(v.title(lang))
    }

    private func badge(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd ~/Developer/codepet && xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Views/Shell/AppRailView.swift
git commit -m "feat: add left navigation rail"
```

---

### Task 6: Rewire the shell

**Files:**
- Modify: `codepet/Views/Shell/AppShellView.swift` (replace `body`, `topBar`; delete `navTab`, `tabCount`, `copilot`, `chatToggle`, `copilotCollapsed`)

**Interfaces:**
- Consumes: `AppRailView(accent:)` (Task 5), `RoadmapView()` (Task 4), `SecondBrainView()` (Task 3), `CopilotChatView()` (existing, unstyled here)
- Produces: no new API

- [ ] **Step 1: Replace `body` and `topBar`, and delete the four now-unused members**

Replace the `body` property with:

```swift
    var body: some View {
        HStack(spacing: 0) {
            AppRailView(accent: accent)
            VStack(spacing: 0) {
                topBar
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CodepetTheme.pageBackground)
    }
```

Replace `topBar` with:

```swift
    /// Slim top bar: the destination title on the left, wake pill and Upgrade on
    /// the right. Navigation itself lives in the rail.
    private var topBar: some View {
        HStack(spacing: 14) {
            Text(companyStore.view.title(uiLanguage))
                .font(CodepetTheme.inter(15, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                wakePill
                Button { companyStore.selectedDeptKey = nil; companyStore.select(.billing) } label: {
                    Text(uiLanguage == .vi ? "Nâng cấp" : "Upgrade")
                        .font(CodepetTheme.inter(13.5, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.primaryText))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
```

Delete these four members entirely: `navTab(_:)`, `tabCount(_:)`, `copilot`, `chatToggle`. Also delete the state line `@State private var copilotCollapsed = false`. Keep `accent`, `companionName`, `wakePill` and `content`.

- [ ] **Step 2: Add the three new branches to `content`**

`content` currently begins with `if companyStore.view == .company` (Task 1, Step 4). Change it to begin:

```swift
    @ViewBuilder private var content: some View {
        if companyStore.view == .chat {
            CopilotChatView()
        } else if companyStore.view == .roadmap {
            RoadmapView()
        } else if companyStore.view == .secondBrain {
            SecondBrainView()
        } else if companyStore.view == .company {
```

leaving the rest of the chain unchanged.

- [ ] **Step 3: Build to verify it compiles**

```bash
cd ~/Developer/codepet && xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch and check the shell by hand**

```bash
open ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app
```

Confirm, by eye: the app opens on Chat (full width, no 50% split, no floating "C" button); the rail shows six icons with Chat active; clicking Roadmap shows the map with progress, beacon and KEY; the `?` popover opens; clicking Second Brain shows the panel; clicking a department row opens Company; the top bar shows the current destination's name.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Views/Shell/AppShellView.swift
git commit -m "feat: rail-based shell with chat as the full-width default surface"
```

---

### Task 7: Delete the retired surfaces

**Files:**
- Delete: `codepet/Views/Overview/OverviewBoardView.swift`, `RoadmapHeaderView.swift`, `PhaseColumnView.swift`
- Delete: `codepet/Views/Summary/SummaryView.swift`, `codepet/Models/SummaryData.swift`, `codepetTests/SummaryDataTests.swift`

`OverviewView.swift` was already deleted in Task 4. The three files above it are dead code that predates this work — they are unreachable from the shipping shell today.

**Interfaces:** none produced; removes `SummaryView`, `SummaryData`.

- [ ] **Step 1: Confirm nothing still references them**

```bash
cd ~/Developer/codepet
grep -rn 'OverviewView\|SummaryView\|SummaryData\|OverviewBoardView\|RoadmapHeaderView\|PhaseColumnView' \
  codepet codepetTests --include='*.swift'
```

Expected: no output. Any hit must be resolved before deleting.

- [ ] **Step 2: Delete the files**

```bash
cd ~/Developer/codepet
git rm -q codepet/Views/Overview/OverviewBoardView.swift \
          codepet/Views/Overview/RoadmapHeaderView.swift \
          codepet/Views/Overview/PhaseColumnView.swift \
          codepet/Views/Summary/SummaryView.swift \
          codepet/Models/SummaryData.swift \
          codepetTests/SummaryDataTests.swift
```

- [ ] **Step 3: Confirm `project.yml` needs no change**

`project.yml` lists sources at directory level — `- codepet/Views` and `- codepet/Models` (lines 55 and 51), not per-subdirectory — so adding and removing view folders requires no edit. Confirm that is still true:

```bash
cd ~/Developer/codepet && grep -n 'codepet/Views' project.yml
```

Expected: exactly one line, `      - codepet/Views`. If instead you see individual subdirectories, someone has changed the manifest — remove the `Views/Overview` and `Views/Summary` lines and add `Views/Roadmap` and `Views/SecondBrain`.

- [ ] **Step 4: Build and run the whole test suite**

```bash
cd ~/Developer/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **` with no failures. `Views/Overview/` and `Views/Summary/` should now be empty and removed by git.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add -A
git commit -m "refactor: delete Overview and Summary surfaces"
```

---

### Task 8: Push and open the PR

**Files:** none.

- [ ] **Step 1: Confirm the branch state**

```bash
cd ~/Developer/codepet && git log --oneline origin/main..HEAD | cat
```

Expected: the four PR #35 build-fix commits, the spec commit, and this phase's seven commits.

- [ ] **Step 2: Push**

```bash
cd ~/Developer/codepet && git push -u origin feat/chat-first-shell
```

- [ ] **Step 3: Open the PR as a draft**

```bash
cd ~/Developer/codepet
gh pr create --repo My-Outcasts/codepet --base main --head feat/chat-first-shell --draft \
  --title "feat: chat-first shell (phase 1 — structure)" \
  --body "Implements phase 1 of docs/superpowers/specs/2026-07-27-chat-first-shell-design.md: rail navigation, chat as the launch destination, Overview split into Roadmap and Second Brain pages, Overview and Summary retired. Chat is still the unstyled CopilotChatView at full width — the landing hero and composer are phase 2. Draft until phase 2 lands."
```

Draft, because the app does not reach the design's intended appearance until Phase 2.

---

## Self-Review

**Spec coverage.** Spec §1 → Task 1. §2 → Tasks 5, 6. §3 → **Phase 2**. §4 → **Phase 2**. §5 → Tasks 2, 4. §6 → Task 3. §7 (theming tokens) → **Phase 2**, since `chatCanvas`/`chatBloom` are only consumed by the landing hero. §8 → **Phase 2**. Testing section → Tasks 1, 2, 7. Files section → Tasks 3, 4, 7.

**Two deliberate deviations from the spec, both recorded here:**

1. The spec's relocation table sends `beaconCard` to the chat landing. Phase 1 keeps it on the Roadmap page, because the chat landing does not exist yet and dropping it would regress today's behaviour. Phase 2 adds the landing cards; whether the Roadmap page then keeps its own beacon is a Phase 2 decision.
2. The spec moves `generateRoadmap`'s `.task` to the chat landing. Phase 1 leaves it on `RoadmapView` for the same reason. **Phase 2 must move it**, or a new founder who never opens the Roadmap page will never get a roadmap generated. This is the single most important carry-over item.

**Placeholder scan.** No TBD/TODO. Every code step contains complete code. Task 7 Step 3 states the verified fact (`project.yml` lists sources at directory level, so no edit is needed) and gives the recovery path if that has since changed.

**Type consistency.** `RoadmapAction` / `RoadmapDispatch.action(for:)` / `navigatesToChat(_:)` are defined in Task 2 and used with those exact names in Task 4. `AppRailView(accent:)` is defined in Task 5 and called with that label in Task 6. `TaskStatus` cases match `Models/RoadmapTask.swift:57`. `RoadmapAction.none` is written as `RoadmapAction.none` in tests to avoid `Optional.none` inference.

## Phase 2 (separate plan)

`ChatLandingState` + tests, `ChatLandingView`, `ChatComposerView`, the `chatCanvas`/`chatBloom` tokens, the `Chat ⌵` thread menu, and `CopilotChatView` → `ChatView` restyled for full width. Written once Phase 1 is merged, so it can build on the real shell rather than a projected one.
