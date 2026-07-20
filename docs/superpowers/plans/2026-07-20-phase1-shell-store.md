# Phase 1 — App Shell + Navigation + CompanyStore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native app's tab shell with a native port of the web `AppRoot` shell — a sidebar + content + Copilot layout driven by a single-company `CompanyStore` hydrated from `companies/{uid}`.

**Architecture:** An `AppView` enum drives a `CompanyStore` (`@MainActor ObservableObject`) that holds the single company's state and the active view. `CompanyData` reads `companies/{uid}` from Firestore into a `CompanyState`. `AppShellView` renders the 3-column shell (sidebar · content · Copilot) with placeholder views, styled in `CodepetTheme`. `CodePetApp` registers the store and `ContentView` routes authed users to `AppShellView` instead of `MainTabView`.

**Tech Stack:** Swift/SwiftUI (macOS 13+), Firebase Auth/Firestore. Reuses `CompanyBrief` (SP1), `ProjectStage`, `CodepetTheme`, `PetCharacter`, `.pixelSystem`, `L10n`/`uiLanguage`. Spec: `docs/superpowers/specs/2026-07-20-phase1-shell-store-design.md`; anchor: `2026-07-20-native-web-product-architecture.md`.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product` (off `44dc7a7`, which already has `CompanyBrief`). `My-Outcasts/codepet`.
- **Base version note:** the base has `CompanyBrief` but NOT `RoadmapTask` (that landed on later `main`). Keep Phase 1 independent of it — `Department` is minimal (`key`, `name`), no task type. Tasks/library get fleshed out in later phases.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen` (`.xcodeproj` auto-syncs new files); test module **`@testable import codepet`**. Test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`. Full build: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`. SourceKit cross-file "cannot find type" diagnostics are FALSE POSITIVES — the `xcodebuild` result is authoritative.
- **Design:** `CodepetTheme` colors + `.pixelSystem` type + VI/EN via `@Environment(\.uiLanguage)` (already set in `CodePetApp`). `L10n` is callable (`callAsFunction(_ lang:)`).
- **Staged retirement:** route authed users to `AppShellView`; do NOT delete `MainTabView`/game/reflection code (leave unreferenced — it still compiles). Only the one authed-branch line in `ContentView` changes among the existing shell.
- **Do NOT touch** Giang's Build Coach files. Do NOT modify splash/auth/account-switch logic beyond the specified hooks. Do NOT edit `CLAUDE.md`.
- **Placeholders are the design** this phase: placeholder per-view content + placeholder Copilot; real content/chat = later phases.

---

## File Structure
- Create `codepet/Models/AppView.swift` (Task 1)
- Create `codepet/Models/CompanyState.swift` + `codepet/Services/CompanyData.swift` (Task 2)
- Create `codepet/Managers/CompanyStore.swift` (Task 3)
- Create `codepet/Views/Shell/AppShellView.swift` (Task 4)
- Modify `codepet/App/CodePetApp.swift` + `codepet/App/ContentView.swift` (Task 5)
- Tests under `codepetTests/`

---

### Task 1: `AppView` enum

**Files:**
- Create: `codepet/Models/AppView.swift`
- Test: `codepetTests/AppViewTests.swift`

**Interfaces:**
- Produces: `enum AppView: String, CaseIterable, Identifiable { case overview, company, roadmap, tasks, library, environment, settings }` + `func title(_ lang: AppLanguage) -> String` + `var icon: String`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/AppViewTests.swift
import XCTest
@testable import codepet

final class AppViewTests: XCTestCase {
    func testCoversTheSevenWebDestinations() {
        XCTAssertEqual(AppView.allCases.map(\.rawValue),
                       ["overview", "company", "roadmap", "tasks", "library", "environment", "settings"])
    }
    func testEveryCaseHasTitleAndIcon() {
        for v in AppView.allCases {
            XCTAssertFalse(v.title(.en).isEmpty)
            XCTAssertFalse(v.title(.vi).isEmpty)
            XCTAssertFalse(v.icon.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/AppViewTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'AppView' in scope`.

- [ ] **Step 3: Write the enum**

```swift
// codepet/Models/AppView.swift
import Foundation

/// The web app's top-level views (components/AppRoot.tsx), minus Giang's Build
/// Coach (summary/build/install). Drives the app shell's sidebar + content.
enum AppView: String, CaseIterable, Identifiable {
    case overview, company, roadmap, tasks, library, environment, settings

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .overview:    return lang == .vi ? "Tổng quan" : "Overview"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .settings:    return lang == .vi ? "Cài đặt" : "Settings"
        }
    }

    /// SF Symbol shown in the sidebar.
    var icon: String {
        switch self {
        case .overview:    return "square.grid.2x2"
        case .company:     return "building.2"
        case .roadmap:     return "map"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .settings:    return "gearshape"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Models/AppView.swift codepetTests/AppViewTests.swift
git commit -m "feat(shell): AppView enum (web view destinations)"
```

---

### Task 2: `CompanyState` + `CompanyData`

**Files:**
- Create: `codepet/Models/CompanyState.swift`
- Create: `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (SP1), `ProjectStage`.
- Produces: `struct Department`, `struct LibItem`, `struct CompanyState` (+ `.empty`); `struct CompanyDoc: Codable`; `enum CompanyData { static func state(from: CompanyDoc?) -> CompanyState; static func load(companyId:) async -> CompanyState }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyDataTests.swift
import XCTest
@testable import codepet

final class CompanyDataTests: XCTestCase {
    func testCompanyDocRoundTripsCodable() throws {
        let doc = CompanyDoc(brief: CompanyBrief(projectName: "Codepet"), stage: "building", companionId: "nova")
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(CompanyDoc.self, from: data)
        XCTAssertEqual(back.brief?.projectName, "Codepet")
        XCTAssertEqual(back.stage, "building")
        XCTAssertEqual(back.companionId, "nova")
    }
    func testStateMappingFromDoc() {
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(projectName: "Codepet"), stage: "launch", companionId: "luna"))
        XCTAssertEqual(s.brief.projectName, "Codepet")
        XCTAssertEqual(s.stage, .launch)
        XCTAssertEqual(s.companionId, "luna")
    }
    func testEmptyOnNilDocAndUnknownStage() {
        XCTAssertEqual(CompanyData.state(from: nil), CompanyState.empty)
        let s = CompanyData.state(from: CompanyDoc(brief: nil, stage: "bogus", companionId: nil))
        XCTAssertEqual(s.stage, .idea)         // unknown stage → default
        XCTAssertEqual(s.companionId, "byte")  // nil companion → default
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'CompanyDoc'/'CompanyData'/'CompanyState' in scope`.

- [ ] **Step 3: Write the models**

```swift
// codepet/Models/CompanyState.swift
import Foundation

/// A company department (roadmap). Minimal this phase — tasks/details land in
/// the roadmap phase. Mirrors the web Dept skeleton (key + name).
struct Department: Codable, Hashable, Identifiable {
    let key: String
    var name: String
    var id: String { key }
}

/// An approved deliverable in the library. Minimal this phase.
struct LibItem: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var kind: String
}

/// The single company's in-memory state (companies/{uid}). Departments and
/// library are typed but empty until later phases populate them.
struct CompanyState: Codable, Hashable {
    var brief: CompanyBrief
    var departments: [Department]
    var library: [LibItem]
    var stage: ProjectStage
    var companionId: String

    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea, companionId: "byte")
}
```

```swift
// codepet/Services/CompanyData.swift
import Foundation
import FirebaseFirestore

/// The companies/{uid} Firestore document (mirrors the web CompanyDoc:
/// lib/firebase/schema.ts). Departments + library live in subcollections
/// (loaded in later phases); this phase reads the top-level doc only.
struct CompanyDoc: Codable {
    var brief: CompanyBrief?
    var stage: String?
    var companionId: String?
}

/// Reads companies/{uid} and maps it to CompanyState. Mirrors
/// lib/firebase/companyData.ts. Fail-soft: missing doc / error → .empty.
enum CompanyData {
    /// Pure mapping — testable without Firestore.
    static func state(from doc: CompanyDoc?) -> CompanyState {
        guard let doc = doc else { return .empty }
        return CompanyState(
            brief: doc.brief ?? CompanyBrief(),
            departments: [],
            library: [],
            stage: doc.stage.flatMap { ProjectStage(rawValue: $0) } ?? .idea,
            companionId: doc.companionId ?? "byte"
        )
    }

    /// Load companies/{uid} from Firestore; fail-soft to .empty. Decodes via
    /// JSONSerialization → JSONDecoder (no FirebaseFirestoreSwift dependency;
    /// the doc holds only strings/nested strings, which are JSON-safe).
    static func load(companyId: String) async -> CompanyState {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("companies").document(companyId).getDocument()
            guard let dict = snap.data() else { return .empty }
            let data = try JSONSerialization.data(withJSONObject: dict)
            let doc = try JSONDecoder().decode(CompanyDoc.self, from: data)
            return state(from: doc)
        } catch {
            return .empty
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepetTests/CompanyDataTests.swift
git commit -m "feat(shell): CompanyState + CompanyData (companies/{uid} read layer)"
```

---

### Task 3: `CompanyStore`

**Files:**
- Create: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreTests.swift`

**Interfaces:**
- Consumes: `AppView` (Task 1), `CompanyState`/`CompanyData` (Task 2).
- Produces: `@MainActor final class CompanyStore: ObservableObject` with `@Published var view: AppView`, `@Published private(set) var company: CompanyState`, `@Published private(set) var isHydrating: Bool`; `init(loader:)`; `select(_:)`; `hydrate(companyId:) async`; `reset()`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreTests: XCTestCase {
    func testSelectUpdatesView() {
        let store = CompanyStore()
        store.select(.roadmap)
        XCTAssertEqual(store.view, .roadmap)
    }
    func testHydrateLoadsCompanyAndClearsFlag() async {
        let seeded = CompanyState(brief: CompanyBrief(projectName: "Codepet"),
                                  departments: [], library: [], stage: .building, companionId: "nova")
        let store = CompanyStore(loader: { _ in seeded })
        await store.hydrate(companyId: "uid1")
        XCTAssertEqual(store.company.brief.projectName, "Codepet")
        XCTAssertEqual(store.company.stage, .building)
        XCTAssertFalse(store.isHydrating)
    }
    func testResetClearsToEmptyOverview() {
        let store = CompanyStore(loader: { _ in CompanyState(brief: CompanyBrief(projectName: "X"), departments: [], library: [], stage: .growth, companionId: "luna") })
        store.select(.tasks)
        store.reset()
        XCTAssertEqual(store.view, .overview)
        XCTAssertEqual(store.company, CompanyState.empty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'CompanyStore' in scope`.

- [ ] **Step 3: Write the store**

```swift
// codepet/Managers/CompanyStore.swift
import Foundation
import Combine

/// The app's primary store — the single company (companies/{uid}) + the active
/// view. Native port of the web `useApp`/`lib/store`. Replaces ProjectStore's
/// role as the top-level store (ProjectStore/reflection are being retired).
@MainActor
final class CompanyStore: ObservableObject {
    @Published var view: AppView = .overview
    @Published private(set) var company: CompanyState = .empty
    @Published private(set) var isHydrating: Bool = false

    /// Injectable so tests can supply a stub without Firestore.
    private let loader: (String) async -> CompanyState

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load) {
        self.loader = loader
    }

    func select(_ view: AppView) { self.view = view }

    /// Hydrate the company from Firestore (fail-soft inside the loader).
    func hydrate(companyId: String) async {
        isHydrating = true
        company = await loader(companyId)
        isHydrating = false
    }

    /// Clear on sign-out / account switch.
    func reset() {
        company = .empty
        view = .overview
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreTests.swift
git commit -m "feat(shell): CompanyStore (single-company + view state)"
```

---

### Task 4: `AppShellView` (sidebar + content + Copilot, placeholders)

**Files:**
- Create: `codepet/Views/Shell/AppShellView.swift`

**Interfaces:**
- Consumes: `CompanyStore` (Task 3), `AppView` (1), `AppState.activeChar`, `PetCharacter`, `CodepetTheme`, `.pixelSystem`, `CharacterImage`.
- Produces: `struct AppShellView: View`; `struct ShellPlaceholderView: View`.

- [ ] **Step 1: Write the shell**

```swift
// codepet/Views/Shell/AppShellView.swift
import SwiftUI

/// The app's top-level shell — a native port of the web AppRoot: a sidebar of
/// AppView destinations, a content area switching on the store's view, and a
/// (placeholder) Copilot panel. Styled in CodepetTheme; the selected item and
/// accents follow the active companion's color.
struct AppShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage
    @State private var copilotCollapsed = false

    private var accent: Color { PetCharacter.all[appState.activeChar]?.color ?? CodepetTheme.accentPurple }
    private var companyName: String {
        let n = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (uiLanguage == .vi ? "Công ty của bạn" : "Your company") : n
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                ShellPlaceholderView(view: companyStore.view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !copilotCollapsed {
                    Divider()
                    copilot
                }
            }
        }
        .background(CodepetTheme.pageBackground)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CharacterImage(appState.activeChar, size: 26)
            Text(companyName).font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Spacer()
            Button { copilotCollapsed.toggle() } label: {
                Image(systemName: "bubble.left.and.bubble.right").foregroundColor(accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppView.allCases) { v in
                Button { companyStore.select(v) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: v.icon).frame(width: 18)
                        Text(v.title(uiLanguage)).font(.pixelSystem(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(companyStore.view == v ? accent : CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(companyStore.view == v ? accent.opacity(0.12) : Color.clear))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 210, alignment: .top)
    }

    private var copilot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(uiLanguage == .vi ? "Trợ lý" : "Copilot")
                .font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(uiLanguage == .vi ? "Trò chuyện sẽ xuất hiện ở đây." : "Chat lands here in a later phase.")
                .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
            Spacer()
        }
        .padding(14)
        .frame(width: 300, alignment: .top)
    }
}

/// Placeholder content per destination — the real views land in later phases.
struct ShellPlaceholderView: View {
    let view: AppView
    @Environment(\.uiLanguage) private var uiLanguage
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: view.icon).font(.system(size: 32)).foregroundColor(CodepetTheme.mutedText)
            Text(view.title(uiLanguage)).font(.pixelSystem(size: 18, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(uiLanguage == .vi ? "Sắp có" : "Coming soon").font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

> Confirm `CharacterImage`'s initializer (it's used elsewhere in the app, e.g. `MainTabView`/`ProfileView`); if its signature differs from `CharacterImage(_ id: String, size: CGFloat)`, adapt the call (e.g. a label param). If it can't be used trivially, substitute a simple `Image(systemName: "pawprint.circle.fill")` avatar for this phase.

- [ ] **Step 2: Full build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **` (the shell compiles as part of the target; it isn't routed to yet — that's Task 5).

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Views/Shell/AppShellView.swift
git commit -m "feat(shell): AppShellView — 3-column sidebar/content/Copilot (placeholders)"
```

---

### Task 5: Wire the shell into the app (route + hydrate + reset)

**Files:**
- Modify: `codepet/App/CodePetApp.swift`
- Modify: `codepet/App/ContentView.swift`

**Interfaces:**
- Consumes: `CompanyStore` (Task 3), `AppShellView` (Task 4).
- Produces: authed users see `AppShellView`; `CompanyStore` hydrated on sign-in, reset on account switch.

- [ ] **Step 1: Register the store in `CodePetApp`**

In `codepet/App/CodePetApp.swift`, add the `@StateObject` next to the others (near `projectStore`):

```swift
    @StateObject private var companyStore = CompanyStore()
```

And add to the `WindowGroup { ContentView()... }` modifier chain (next to `.environmentObject(projectStore)`):

```swift
                .environmentObject(companyStore)
```

- [ ] **Step 2: Route authed users to the shell + hydrate/reset in `ContentView`**

In `codepet/App/ContentView.swift`:
1. Add the env object near the other `@EnvironmentObject`s:

```swift
    @EnvironmentObject var companyStore: CompanyStore
```

2. Replace the authed-branch `MainTabView()` (the final `else` around line 45) with:

```swift
            } else {
                // Authenticated (or guest) — the company shell (web product).
                AppShellView()
            }
```

3. In the sign-in `onReceive(authManager.$currentUser)` block, next to `chatStore.activate(uid: user.uid)`, add:

```swift
            Task { await companyStore.hydrate(companyId: user.uid) }
```

4. In `reloadAllStores()` (next to `projectStore.reload()`), add:

```swift
        companyStore.reset()
```

5. If `ContentView`'s `#Preview` injects env objects, add `.environmentObject(CompanyStore())` so it still compiles.

- [ ] **Step 3: Full build to verify**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`. Authed users now render `AppShellView` (sidebar + placeholder views + placeholder Copilot); `MainTabView` and the game/reflection code remain in the target, unreferenced.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/App/CodePetApp.swift codepet/App/ContentView.swift
git commit -m "feat(shell): route authed users to AppShellView + hydrate/reset CompanyStore"
```

---

## Final verification

Run the full suite + build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30` — all pass, app builds. The authed app now shows the web-style shell with the 7 nav destinations (placeholder content) and a placeholder Copilot.

---

## Self-Review

**Spec coverage:** AppView (Task 1 ✓), CompanyStore (Task 3 ✓), CompanyData/companies-uid read (Task 2 ✓), AppShellView 3-column shell + placeholders + Copilot placeholder (Task 4 ✓), wiring register+route+hydrate+reset (Task 5 ✓). Staged retirement (route away, don't delete) ✓; CodepetTheme/pixelSystem/VI-EN ✓; Giang/CLAUDE.md untouched ✓.

**Type consistency:** `AppView` cases/`title(_:)`/`icon` used identically in Tasks 1/4. `CompanyState`/`CompanyDoc`/`Department`/`LibItem` defined Task 2, consumed Tasks 3/4. `CompanyStore(loader:)`/`select`/`hydrate(companyId:)`/`reset` defined Task 3, consumed Tasks 4/5. `CompanyBrief.projectName` (SP1) + `ProjectStage(rawValue:)` reused. `accent`/`companionId` default `"byte"` consistent.

**Known verification gaps for the implementer (resolve inline, not blockers):** (a) confirm `CharacterImage`'s init (Task 4 note — substitute an SF Symbol avatar if it doesn't take `(id, size:)`); (b) confirm `ContentView`'s `#Preview` env-object list needs `CompanyStore()` added; (c) `ProjectStage` lives in `ProjectHealthCheck.swift` (part of the retiring health system but present in the base) — reused deliberately for the stage value; it moves/renames in a later phase.
