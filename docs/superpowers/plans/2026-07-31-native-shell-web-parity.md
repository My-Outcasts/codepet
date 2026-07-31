# Native Shell — Web Parity Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the native macOS shell to match the web app — a top horizontal nav, a persistent collapsible right-docked "Your team" copilot across every tab, content on the left — retiring the left icon rail and the standalone full-screen Chat page.

**Architecture:** Rebuild `AppShellView.body` from `HStack{ AppRailView; VStack{ topBar; content } }` into `VStack{ TopNavView; HStack{ content; copilotDock } }`. Reuse `AccountMenuView` (account dropdown), `CopilotChatView` (dock content), `RoadmapView` (Overview, gaining a Roadmap/Second-Brain toggle). Dock width/collapse is decided by a pure `ShellLayout` helper + a store flag + a `GeometryReader` width rule.

**Tech Stack:** Swift 5, SwiftUI, macOS (non-sandboxed), XCTest, Xcode project `codepet.xcodeproj` (scheme `codepet`).

## Global Constraints

- **Branch:** `feat/shell-web-parity` (off `main` @ `4141d1d`). Commit after every task.
- **Match the web shell exactly:** top nav = **Overview · Company · Tasks · Library · Environment** (with the account dropdown top-left holding Settings/Billing/Support, and Wake + Upgrade top-right); a **persistent collapsible right-docked copilot** (`CopilotChatView`) present on every tab; **Second Brain is a toggle on the Overview**, not a nav tab; **default landing = Overview**; the standalone `.chat` full-screen destination is removed (copilot is always the dock).
- **Do not change destination view internals** — only their placement/framing. The chat message UI, roadmap, Company/Tasks/Library/Environment/SecondBrain bodies stay as-is.
- **Dock sizing:** `dockWidth = 380`; auto-collapse when the shell is narrower than `900` (dock 380 + 520 content floor); native window min is 560.
- **Build (TEAM-signed, required):** `xcodebuild build -project codepet.xcodeproj -scheme codepet -configuration Debug -destination 'platform=macOS' CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
- **Tests:** same flags with `test` + `-only-testing:codepetTests/<Class>`. **Close any running `codepet.app` first** (`pkill -x codepet 2>/dev/null`) — a live app holds the Firestore lock and the host aborts with 0 tests executed and no `Failing tests:` line (environmental flake; re-run app-closed and confirm a non-zero count).
- New `.swift` files auto-join the target (PBXFileSystemSynchronizedRootGroup) — no `.pbxproj` edits. Bilingual EN/VI copy via `@Environment(\.uiLanguage)`.
- Commit only each task's listed paths (`git add <paths>`), never `git add -A` — a stray untracked `HANDOFF-chat-redesign.md` sits in the tree.

---

### Task 1: `ShellLayout` — pure dock-collapse decision (+ test)

The one cleanly unit-testable piece: given the shell width and the user's manual-collapse preference, decide whether the dock is collapsed.

**Files:**
- Create: `codepet/Models/ShellLayout.swift`
- Test: `codepetTests/ShellLayoutTests.swift`

**Interfaces:**
- Produces: `enum ShellLayout { static func dockCollapsed(forWidth width: CGFloat, manual: Bool) -> Bool }` — returns `true` if `manual == true` OR `width < 900`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ShellLayoutTests.swift
import XCTest
@testable import codepet

final class ShellLayoutTests: XCTestCase {
    func test_manualCollapse_always() {
        XCTAssertTrue(ShellLayout.dockCollapsed(forWidth: 1400, manual: true))
    }
    func test_narrowWindow_autoCollapses() {
        XCTAssertTrue(ShellLayout.dockCollapsed(forWidth: 800, manual: false))
    }
    func test_wideEnough_expanded() {
        XCTAssertFalse(ShellLayout.dockCollapsed(forWidth: 1200, manual: false))
    }
    func test_boundary_900_expanded() {
        XCTAssertFalse(ShellLayout.dockCollapsed(forWidth: 900, manual: false))
    }
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `xcodebuild test … -only-testing:codepetTests/ShellLayoutTests …` — expect FAIL ("Cannot find 'ShellLayout' in scope").

- [ ] **Step 3: Implement**

```swift
// codepet/Models/ShellLayout.swift
import CoreGraphics

/// Pure layout decisions for the app shell. Kept out of the views so the
/// dock-collapse rule is unit-testable.
enum ShellLayout {
    /// Minimum shell width that still fits the 380pt copilot dock beside a 520pt
    /// content floor. Below this the dock auto-collapses regardless of preference.
    static let dockExpandMinWidth: CGFloat = 900

    /// The dock is collapsed if the user collapsed it, or the window is too narrow.
    static func dockCollapsed(forWidth width: CGFloat, manual: Bool) -> Bool {
        manual || width < dockExpandMinWidth
    }
}
```

- [ ] **Step 4: Run it — verify pass**

Run the same test command; expect PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ShellLayout.swift codepetTests/ShellLayoutTests.swift
git commit -m "feat(shell): ShellLayout dock-collapse decision + tests"
```

---

### Task 2: Store + `AppView` changes (default landing, dock flag, top tabs, chat-nav repoint)

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`, `codepet/Models/AppView.swift`, `codepet/Views/Roadmap/RoadmapView.swift`, `codepet/Views/Roadmap/RoadmapMapView.swift`
- Test: `codepetTests/ShellNavTests.swift`

**Interfaces:**
- Produces: `CompanyStore.view` default `.roadmap`; `@Published var dockCollapsed: Bool` on `CompanyStore` (default `false`); `AppView.topTabs: [AppView]` = `[.roadmap, .company, .tasks, .library, .environment]`; `AppView.navLabel(_:)` returning "Overview" for `.roadmap`, else `title`.

- [ ] **Step 1: Default landing → Overview + dock flag**

In `codepet/Managers/CompanyStore.swift`, change line 10 `@Published var view: AppView = .chat` to `.roadmap`, and add right after it:

```swift
    /// User's manual collapse of the docked copilot (session-only). The shell also
    /// auto-collapses on a narrow window via ShellLayout; this is the manual override.
    @Published var dockCollapsed: Bool = false
```

- [ ] **Step 2: Top tabs + Overview label on `AppView`**

In `codepet/Models/AppView.swift`, add (leave `navTabs` in place only if still referenced — see Step 4):

```swift
    /// Destinations shown as top-nav tabs, in order (web parity). Chat is the docked
    /// copilot (no tab); Second Brain is a toggle on the Overview; settings/billing/
    /// support live in the account dropdown.
    static let topTabs: [AppView] = [.roadmap, .company, .tasks, .library, .environment]

    /// Nav label — the Roadmap destination is titled "Overview" in the top nav (web parity).
    func navLabel(_ lang: AppLanguage) -> String {
        self == .roadmap ? (lang == .vi ? "Tổng quan" : "Overview") : title(lang)
    }
```

- [ ] **Step 3: Repoint the two `select(.chat)` call sites to expand the dock**

Chat is now always docked, so "navigate to chat" means "make sure the dock is open." Change both:
- `codepet/Views/Roadmap/RoadmapView.swift:92`
- `codepet/Views/Roadmap/RoadmapMapView.swift:211`

from `if RoadmapDispatch.navigatesToChat(action) { companyStore.select(.chat) }` to:

```swift
        if RoadmapDispatch.navigatesToChat(action) { companyStore.dockCollapsed = false }
```

- [ ] **Step 4: Retire `navTabs` if now unused**

Run `grep -rn "AppView.navTabs\|\.navTabs" codepet` . The only user was `AppRailView` (deleted in Task 6). If this grep returns only `AppView.swift`'s definition (and `AppRailView`, which you will delete), delete the `navTabs` declaration to avoid a stale nav list. If anything else references it, leave it and note so in the report.

- [ ] **Step 5: Write the failing test**

```swift
// codepetTests/ShellNavTests.swift
import XCTest
@testable import codepet

@MainActor
final class ShellNavTests: XCTestCase {
    func test_defaultLandingIsOverview() {
        XCTAssertEqual(CompanyStore().view, .roadmap)
    }
    func test_topTabs_areTheFiveWebTabs() {
        XCTAssertEqual(AppView.topTabs, [.roadmap, .company, .tasks, .library, .environment])
    }
    func test_overviewLabel() {
        XCTAssertEqual(AppView.roadmap.navLabel(.en), "Overview")
        XCTAssertEqual(AppView.company.navLabel(.en), AppView.company.title(.en))
    }
}
```

- [ ] **Step 6: Run — verify pass**

`pkill -x codepet 2>/dev/null`; run `xcodebuild test … -only-testing:codepetTests/ShellNavTests …`. Expect PASS (3). If `CompanyStore()` needs args to construct, mirror existing `CompanyStore` tests.

- [ ] **Step 7: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepet/Models/AppView.swift codepet/Views/Roadmap/RoadmapView.swift codepet/Views/Roadmap/RoadmapMapView.swift codepetTests/ShellNavTests.swift
git commit -m "feat(shell): default to Overview, add dock flag + top tabs, repoint chat-nav to dock"
```

---

### Task 3: `TopNavView` (new)

The horizontal nav bar replacing the left rail + old top bar.

**Files:**
- Create: `codepet/Views/Shell/TopNavView.swift`

**Interfaces:**
- Consumes: `AppView.topTabs`/`navLabel` (Task 2), `AccountMenuView`, `TopbarCounts`, `companyStore.view`/`select(_:)`.
- Produces: `struct TopNavView: View { let accent: Color }`.

- [ ] **Step 1: Create the view**

```swift
// codepet/Views/Shell/TopNavView.swift
import SwiftUI

/// The top navigation bar (web parity): account dropdown on the left, the five
/// destination tabs centered, wake pill + Upgrade on the right. Replaces the left
/// AppRailView and the old slim top bar.
struct TopNavView: View {
    let accent: Color

    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var lang

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        HStack(spacing: 16) {
            Text("Codepet").font(CodepetTheme.pixel(18)).foregroundColor(CodepetTheme.primaryText)
            AccountMenuView()   // compact:false → avatar + name + chevron + dropdown (Settings/Billing/Support)
            Spacer(minLength: 12)
            HStack(spacing: 4) { ForEach(AppView.topTabs) { tab($0) } }
            Spacer(minLength: 12)
            wakePill
            upgradeButton
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(CodepetTheme.surface)
    }

    private func tab(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = badge(v)
        return Button {
            companyStore.selectedDeptKey = nil
            companyStore.select(v)
        } label: {
            HStack(spacing: 5) {
                Text(v.navLabel(lang))
                    .font(CodepetTheme.inter(14, weight: on ? .semibold : .medium))
                    .foregroundColor(on ? accent : CodepetTheme.mutedText)
                if count > 0 {
                    Text("\(count)")
                        .font(CodepetTheme.inter(9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(on ? accent : .clear).frame(height: 2).offset(y: 6)
            }
        }
        .buttonStyle(.plain)
    }

    private func badge(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }

    private var wakePill: some View {
        Button { companyStore.selectedDeptKey = nil; companyStore.select(.environment) } label: {
            HStack(spacing: 5) {
                Circle().fill(CodepetTheme.accentOrange).frame(width: 6, height: 6)
                Text("⚡ " + (lang == .vi ? "Đánh thức \(companionName)" : "Wake \(companionName) up"))
                    .font(CodepetTheme.inter(13.5, weight: .medium))
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(CodepetTheme.surface).overlay(Capsule().stroke(CodepetTheme.hairline)))
        }.buttonStyle(.plain)
    }

    private var upgradeButton: some View {
        Button { companyStore.selectedDeptKey = nil; companyStore.select(.billing) } label: {
            Text(lang == .vi ? "Nâng cấp" : "Upgrade")
                .font(CodepetTheme.inter(13.5, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.primaryText))
        }.buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

Run the TEAM-signed build. Expected `** BUILD SUCCEEDED **`. If `AccountMenuView` needs environment objects not present here, they come from the shell's environment at runtime — a build error instead means a symbol/type mismatch; resolve against the real `AccountMenuView`/`TopbarCounts` signatures. If `CodepetTheme.pixel(_:)` isn't the wordmark font used elsewhere, match how `AppRailView`/other headers render the "Codepet" wordmark.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Shell/TopNavView.swift
git commit -m "feat(shell): TopNavView — top nav bar (account, tabs, wake, upgrade)"
```

---

### Task 4: Overview gains a Roadmap / Second Brain toggle

Second Brain stops being its own destination and becomes a toggle on the Overview, embedding `SecondBrainView`.

**Files:**
- Modify: `codepet/Views/Roadmap/RoadmapView.swift`

**Interfaces:**
- Consumes: `SecondBrainView` (embedded).

- [ ] **Step 1: Add the toggle + swap the body**

In `RoadmapView`, add state and a segmented control, and switch the body between the roadmap chrome and `SecondBrainView`. Read the current `body` (lines ~32-40) first; wrap it:

```swift
    @State private var overviewTab: OverviewTab = .roadmap
    private enum OverviewTab { case roadmap, secondBrain }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            overviewToggle.padding(.horizontal, 24).padding(.top, 16)
            if overviewTab == .roadmap {
                roadmapBody
            } else {
                SecondBrainView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if tasks.isEmpty { await companyStore.generateRoadmap(language: lang) } }
        .sheet(item: $openDeliverable) { DeliverableDetailView(deliverable: $0) }
    }

    /// The former `body` contents (roadmap map + chrome), extracted so the toggle can swap it.
    private var roadmapBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 22)
            chromeRow.padding(.horizontal, 24).padding(.top, 14)
            RoadmapMapView(tasks: tasks).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var overviewToggle: some View {
        HStack(spacing: 6) {
            ForEach([OverviewTab.roadmap, .secondBrain], id: \.self) { t in
                let on = overviewTab == t
                Button { overviewTab = t } label: {
                    Text(t == .roadmap ? (lang == .vi ? "Lộ trình" : "Roadmap")
                                       : (lang == .vi ? "Bộ não" : "Second Brain"))
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(on ? .white : CodepetTheme.mutedText)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(on ? CodepetTheme.accentPurple : CodepetTheme.surface))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
    }
```

Make `OverviewTab` conform to `Hashable` (add `: Hashable` or rely on the synthesized conformance for a no-payload enum — it's automatic). Keep the existing `header`, `chromeRow`, `mapIntroBriefing`, etc. untouched.

- [ ] **Step 2: Build**

TEAM-signed build → `** BUILD SUCCEEDED **`. If `SecondBrainView()` requires an initializer argument, pass what `AppShellView` passed it before (check the old `.secondBrain` branch); if it reads only `@EnvironmentObject`, no args are needed.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Roadmap/RoadmapView.swift
git commit -m "feat(shell): Overview Roadmap/Second-Brain toggle (embeds SecondBrainView)"
```

---

### Task 5: Rebuild `AppShellView` (top nav + content + docked copilot)

**Files:**
- Modify: `codepet/Views/Shell/AppShellView.swift`

**Interfaces:**
- Consumes: `TopNavView` (Task 3), `ShellLayout` (Task 1), `CopilotChatView`, `companyStore.dockCollapsed` (Task 2).

- [ ] **Step 1: Replace the shell body + remove the rail/topBar/.chat/.secondBrain branches**

Rewrite `AppShellView` so `body` is the new layout and `content` drops `.chat` and `.secondBrain`:

```swift
    private let dockWidth: CGFloat = 380

    var body: some View {
        GeometryReader { geo in
            let collapsed = ShellLayout.dockCollapsed(forWidth: geo.size.width, manual: companyStore.dockCollapsed)
            VStack(spacing: 0) {
                TopNavView(accent: accent)
                Divider()
                HStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
                    if collapsed {
                        dockHandle
                    } else {
                        ZStack(alignment: .topTrailing) {
                            CopilotChatView()
                            Button { companyStore.dockCollapsed = true } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .padding(6)
                            }.buttonStyle(.plain).padding(6)
                        }
                        .frame(width: dockWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(CodepetTheme.pageBackground)
        }
    }

    /// Collapsed dock: a slim reopen strip.
    private var dockHandle: some View {
        Button { companyStore.dockCollapsed = false } label: {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .medium)).foregroundColor(accent)
                Spacer()
            }
            .padding(.top, 12).frame(width: 44).frame(maxHeight: .infinity)
            .background(CodepetTheme.surface)
        }.buttonStyle(.plain)
        .help(uiLanguage == .vi ? "Mở trợ lý" : "Open copilot")
    }

    @ViewBuilder private var content: some View {
        if companyStore.view == .roadmap {
            RoadmapView()
        } else if companyStore.view == .company {
            if let dept = companyStore.selectedDeptKey {
                DepartmentDetailView(deptKey: dept, onBack: { companyStore.selectedDeptKey = nil })
            } else {
                CompanyView(onOpen: { companyStore.selectedDeptKey = $0 })
            }
        } else if companyStore.view == .tasks {
            TasksView()
        } else if companyStore.view == .library {
            LibraryView()
        } else if companyStore.view == .environment {
            EnvironmentView()
        } else if companyStore.view == .settings {
            SettingsView()
        } else if companyStore.view == .billing {
            BillingView()
        } else if companyStore.view == .support {
            SupportView()
        } else {
            // .chat and .secondBrain are no longer full-content destinations
            // (chat = docked copilot; second brain = Overview toggle).
            RoadmapView()
        }
    }
```

Delete the old `topBar`, `wakePill`, `companionName` helpers from `AppShellView` (they moved into `TopNavView`) — but first grep the file to confirm nothing else in `AppShellView` still uses them. Keep the `accent` computed property (used by `TopNavView(accent:)` and `dockHandle`).

- [ ] **Step 2: Build**

TEAM-signed build → `** BUILD SUCCEEDED **`. Resolve any "unused"/"missing" from the deleted helpers.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Shell/AppShellView.swift
git commit -m "feat(shell): rebuild AppShellView — top nav + content + docked copilot"
```

---

### Task 6: Delete `AppRailView`

**Files:**
- Delete: `codepet/Views/Shell/AppRailView.swift`

- [ ] **Step 1: Confirm no references, then delete**

Run `grep -rn "AppRailView" codepet` . Expect only `AppRailView.swift` itself (its sole caller, `AppShellView`, no longer references it after Task 5). If any other reference exists, fix that call site first. Then:

```bash
git rm codepet/Views/Shell/AppRailView.swift
```

- [ ] **Step 2: Build**

TEAM-signed build → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(shell): retire AppRailView (nav moved to TopNavView)"
```

---

### Task 7: Full-suite verification + founder visual pass

**Files:** none (verification).

- [ ] **Step 1: Full test suite (app closed)**

`pkill -x codepet 2>/dev/null`; run the full `xcodebuild test` (Global Constraints, no `-only-testing`). Report the executed count and any real failures (`Failing tests:` line). 0-executed + no-failing-list = the Firestore flake; re-run app-closed.

- [ ] **Step 2: Launch + confirm no crash**

Build TEAM-signed; `open <DerivedData>/…/codepet.app`; confirm the process stays alive and no new `~/Library/Logs/DiagnosticReports/codepet-*.ips` dated today; then `pkill -x codepet`. Do NOT attempt to click through the shell.

- [ ] **Step 3: Founder visual pass (manual — hand to the user)**

Report this checklist for the user to run (a headless agent can't drive SwiftUI):
- Top nav shows **Overview · Company · Tasks · Library · Environment**; each switches the left content; active tab is accented; Tasks/Library/Environment badges show.
- The **copilot docks on the right on every tab**; the collapse chevron hides it to a slim reopen strip; it **auto-collapses** when the window is dragged narrow (<~900pt) and reopens when widened.
- **Overview** shows the **Roadmap / Second Brain** toggle and both render.
- The **account dropdown** (top-left) reaches **Settings · Billing · Support** + theme + log out.
- App **opens on Overview** by default (not a full-screen chat).
- Starting an Engineering/other task that used to "go to chat" now just **opens/keeps the dock** (no dead navigation).

---

## Deferred / future

- Persist the dock-collapsed preference across launches.
- Reconcile with `feat/coding-agent-copilot` at merge time (both touch `CopilotChatView` usage) — whichever merges second rebases onto the first.
