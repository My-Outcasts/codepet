# Phase 7 — Environment (Toolkit) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Environment view — a static toolkit catalog (skills/connectors/agents) the founder enables/disables, with a recommendations strip, persisted per company. CF-free.

**Architecture:** A static `Toolkit.catalog` (13 items ported from the web `ENV`) + a per-company `enabledTools: Set<String>` persisted to `companies/{uid}` (field array, like tasks/library) + `EnvironmentView`. No Cloud Function.

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `CompanyState`/`CompanyData`/`CompanyStore`, CodepetTheme (`CodepetCard`, accents, `.pixelSystem`), `@Environment(\.uiLanguage)`. Spec: `docs/superpowers/specs/2026-07-21-phase7-environment-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **Decisions:** static catalog (no CF); recommendations strip shows recommended-but-OFF items; enabled-id-set persistence — `state(from:)` maps nil→`Toolkit.defaultEnabledIds`, `[]`→empty, `[ids]`→set; persistence fail-soft; defer chat-context integration. Defaults = `{prd-writer, github, explorer}`. Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Create `codepet/Models/Toolkit.swift` (Task 1)
- Modify `codepet/Models/CompanyState.swift` + `codepet/Services/CompanyData.swift` + `codepet/Managers/CompanyStore.swift` (Task 2)
- Create `codepet/Views/Environment/EnvironmentView.swift` (Task 3: view + `ToolRowView` + `ToolBadge`)
- Modify `codepet/Views/Shell/AppShellView.swift` (Task 3: `.environment` route)
- Tests: `codepetTests/{ToolkitTests, CompanyStoreToolsTests}.swift`

---

### Task 1: `Toolkit` catalog

**Files:**
- Create: `codepet/Models/Toolkit.swift`
- Test: `codepetTests/ToolkitTests.swift`

**Interfaces:**
- Consumes: `AppLanguage`, CodepetTheme (Color).
- Produces: `enum ToolCategory` (skills/connectors/agents; `label`/`enableVerb`/`onLabel`/`tint`); `struct ToolItem: Identifiable, Equatable`; `enum Toolkit` (`catalog`, `items(in:)`, `recommended`, `defaultEnabledIds`).

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ToolkitTests.swift
import XCTest
@testable import codepet

final class ToolkitTests: XCTestCase {
    func testCatalog13UniqueIds() {
        XCTAssertEqual(Toolkit.catalog.count, 13)
        XCTAssertEqual(Set(Toolkit.catalog.map(\.id)).count, 13)
    }
    func testDefaultsAndPartition() {
        XCTAssertEqual(Toolkit.defaultEnabledIds, ["prd-writer", "github", "explorer"])
        XCTAssertTrue(Toolkit.defaultEnabledIds.isSubset(of: Set(Toolkit.catalog.map(\.id))))
        let sum = ToolCategory.allCases.map { Toolkit.items(in: $0).count }.reduce(0, +)
        XCTAssertEqual(sum, 13)
    }
    func testRecommendedNonEmptyAllHaveWhy() {
        XCTAssertFalse(Toolkit.recommended.isEmpty)
        XCTAssertTrue(Toolkit.recommended.allSatisfy { $0.why != nil })
    }
    func testCategoryLabelsBothLanguages() {
        for c in ToolCategory.allCases {
            for lang in [AppLanguage.en, .vi] {
                XCTAssertFalse(c.label(lang).isEmpty)
                XCTAssertFalse(c.enableVerb(lang).isEmpty)
                XCTAssertFalse(c.onLabel(lang).isEmpty)
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ToolkitTests 2>&1 | tail -20`
Expected: FAIL — no `Toolkit`/`ToolCategory`.

- [ ] **Step 3: Write `Toolkit.swift`**

```swift
// codepet/Models/Toolkit.swift
import SwiftUI

/// A toolkit category — skills / connectors / agents. Chrome (labels/verbs) is VI/EN;
/// item content (name/detail/why) is EN, ported from the web catalog.
enum ToolCategory: String, CaseIterable, Identifiable {
    case skills, connectors, agents
    var id: String { rawValue }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Kỹ năng" : "Skills"
        case .connectors: return lang == .vi ? "Kết nối" : "Connectors"
        case .agents:     return lang == .vi ? "Trợ lý" : "Agents"
        }
    }
    func enableVerb(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Bật" : "Turn on"
        case .connectors: return lang == .vi ? "Kết nối" : "Connect"
        case .agents:     return lang == .vi ? "Bật" : "Enable"
        }
    }
    func onLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Đang bật" : "Active"
        case .connectors: return lang == .vi ? "Đã kết nối" : "Connected"
        case .agents:     return lang == .vi ? "Đã bật" : "Enabled"
        }
    }
    var tint: Color {
        switch self {
        case .skills:     return CodepetTheme.accentPurple
        case .connectors: return CodepetTheme.accentBlue
        case .agents:     return CodepetTheme.accentTeal
        }
    }
}

/// One toolkit item. `defaultOn` seeds the first-run enabled set; `recommended`/`why`
/// drive the recommendations strip.
struct ToolItem: Identifiable, Equatable {
    let id: String
    let name: String
    let badge: String
    let detail: String
    let category: ToolCategory
    let recommended: Bool
    let why: String?
    let defaultOn: Bool
}

/// The static toolkit catalog — the 13 web `ENV` items, companion-name-genericized.
enum Toolkit {
    static let catalog: [ToolItem] = [
        // skills
        ToolItem(id: "web-research", name: "Web research", badge: "Wr",
                 detail: "Searches the web and cites sources in drafts.",
                 category: .skills, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "prd-writer", name: "PRD writer", badge: "Pr",
                 detail: "Turn a rough idea into a structured product spec.",
                 category: .skills, recommended: true,
                 why: "Turn each feature into a clear spec before building it.", defaultOn: true),
        ToolItem(id: "code-review", name: "Code review", badge: "Cr",
                 detail: "Reviews diffs for bugs before anything ships.",
                 category: .skills, recommended: true,
                 why: "Catch bugs before they reach your testers.", defaultOn: false),
        ToolItem(id: "changelog", name: "Changelog", badge: "Ch",
                 detail: "Auto-drafts release notes from your commits.",
                 category: .skills, recommended: false, why: nil, defaultOn: false),
        // connectors
        ToolItem(id: "github", name: "GitHub", badge: "Gh",
                 detail: "Read repos, open PRs, track issues.",
                 category: .connectors, recommended: true,
                 why: "Reads your repo and opens PRs as it ships work.", defaultOn: true),
        ToolItem(id: "notion", name: "Notion", badge: "No",
                 detail: "Sync briefs, roadmaps, and docs.",
                 category: .connectors, recommended: true,
                 why: "Connect it so your companion can write there.", defaultOn: false),
        ToolItem(id: "figma", name: "Figma", badge: "Fi",
                 detail: "Pull designs and components into context.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "slack", name: "Slack", badge: "Sl",
                 detail: "Post updates and gather feedback.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "linear", name: "Linear", badge: "Li",
                 detail: "Create and update issues from your tasks.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        // agents
        ToolItem(id: "code-reviewer", name: "Code Reviewer", badge: "Cr",
                 detail: "A subagent that audits changes for correctness.",
                 category: .agents, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "explorer", name: "Explorer", badge: "Ex",
                 detail: "Searches the codebase to answer questions fast.",
                 category: .agents, recommended: false, why: nil, defaultOn: true),
        ToolItem(id: "test-writer", name: "Test Writer", badge: "Tw",
                 detail: "Generates tests for new code.",
                 category: .agents, recommended: true,
                 why: "Writes tests as each new feature ships.", defaultOn: false),
        ToolItem(id: "migrator", name: "Migrator", badge: "Mg",
                 detail: "Runs large, repetitive refactors safely.",
                 category: .agents, recommended: false, why: nil, defaultOn: false),
    ]

    static func items(in category: ToolCategory) -> [ToolItem] {
        catalog.filter { $0.category == category }
    }
    static var recommended: [ToolItem] { catalog.filter(\.recommended) }
    static var defaultEnabledIds: Set<String> { Set(catalog.filter(\.defaultOn).map(\.id)) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/Toolkit.swift codepetTests/ToolkitTests.swift
# commit (fsmonitor-off form): "feat(environment): Toolkit catalog (13 items, skills/connectors/agents)"
```

---

### Task 2: `enabledTools` state + persistence + `toggleTool`

**Files:**
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`, `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreToolsTests.swift`

**Interfaces:**
- Consumes: `Toolkit.defaultEnabledIds` (Task 1).
- Produces: `CompanyState.enabledTools: Set<String>`; `CompanyDoc.enabledTools: [String]?`; `state(from:)` mapping; `CompanyData.enabledToolsPayload`/`saveEnabledTools`; `CompanyStore.toggleTool(id:) async` + injectable `toolsSaver`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreToolsTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreToolsTests: XCTestCase {
    func testStateMapsEnabledTools() {
        let dflt = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                      onboardedAt: nil, tasks: nil, library: nil, enabledTools: nil))
        XCTAssertEqual(dflt.enabledTools, Toolkit.defaultEnabledIds)   // nil → defaults
        let off = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                     onboardedAt: nil, tasks: nil, library: nil, enabledTools: []))
        XCTAssertTrue(off.enabledTools.isEmpty)                        // [] → all-off
        let set = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                     onboardedAt: nil, tasks: nil, library: nil, enabledTools: ["github"]))
        XCTAssertEqual(set.enabledTools, ["github"])                   // [ids] → set
    }
    func testEnabledToolsPayloadShape() {
        let p = CompanyData.enabledToolsPayload(["github", "notion"])
        XCTAssertEqual(p["enabledTools"] as? [String], ["github", "notion"])
    }
    func testToggleFlipsAndPersists() async {
        var saved: [String] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             toolsSaver: { _, t in saved = t; return true })
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.company.enabledTools.contains("github"))       // default on
        await s.toggleTool(id: "github")
        XCTAssertFalse(s.company.enabledTools.contains("github"))      // off
        XCTAssertFalse(saved.contains("github"))                      // persisted without it
        await s.toggleTool(id: "web-research")
        XCTAssertTrue(s.company.enabledTools.contains("web-research")) // on
        XCTAssertTrue(saved.contains("web-research"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreToolsTests 2>&1 | tail -20`
Expected: FAIL — no `enabledTools`/`toggleTool`/`toolsSaver`.

- [ ] **Step 3: Add `enabledTools` to `CompanyState.swift`**

Add the field (after `tasks`) and the init param (after `tasks:`), defaulting to the catalog defaults:

```swift
    var tasks: [RoadmapTask]
    var enabledTools: Set<String>
```

In the init signature + body:

```swift
    init(brief: CompanyBrief, departments: [Department], library: [Deliverable],
         stage: ProjectStage, companionId: String, onboardedAt: Date? = nil,
         tasks: [RoadmapTask] = [], enabledTools: Set<String> = Toolkit.defaultEnabledIds) {
        self.brief = brief
        self.departments = departments
        self.library = library
        self.stage = stage
        self.companionId = companionId
        self.onboardedAt = onboardedAt
        self.tasks = tasks
        self.enabledTools = enabledTools
    }
```

(`.empty` omits `enabledTools` → defaults; fresh accounts start with the default toolkit on.)

- [ ] **Step 4: Add to `CompanyData.swift`**

1. Add to `CompanyDoc` (after `library`):

```swift
    var enabledTools: [String]?  // JSON-safe; nil → first-run defaults, [] → all-off
```

2. In `state(from:)`, map it (add to the `CompanyState(...)` call):

```swift
            tasks: doc.tasks ?? [],
            enabledTools: doc.enabledTools.map(Set.init) ?? Toolkit.defaultEnabledIds
```

3. Add the payload builder + writer (inside `enum CompanyData`):

```swift
    /// Pure Firestore payload for an enabled-tools write — testable without Firestore.
    static func enabledToolsPayload(_ tools: [String]) -> [String: Any] {
        ["enabledTools": tools]
    }

    /// Write companies/{uid}.enabledTools, merge. Fail-soft: false on error.
    static func saveEnabledTools(companyId: String, tools: [String]) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(enabledToolsPayload(tools), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 5: Add `toolsSaver` + `toggleTool` to `CompanyStore.swift`**

Add the stored dependency (after `librarySaver`):

```swift
    private let toolsSaver: (String, [String]) async -> Bool
```

Extend `init` (keep all existing defaults; add the param + assignment):

```swift
         librarySaver: @escaping (String, [Deliverable]) async -> Bool = CompanyData.saveLibrary,
         toolsSaver: @escaping (String, [String]) async -> Bool = CompanyData.saveEnabledTools) {
```
```swift
        self.librarySaver = librarySaver
        self.toolsSaver = toolsSaver
    }
```

Add the method (inside the class):

```swift
    /// Enable/disable a toolkit item and persist (fail-soft).
    func toggleTool(id: String) async {
        if company.enabledTools.contains(id) {
            company.enabledTools.remove(id)
        } else {
            company.enabledTools.insert(id)
        }
        if let cid = companyId { _ = await toolsSaver(cid, Array(company.enabledTools)) }
    }
```

- [ ] **Step 6: Run test to verify it passes + regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreToolsTests -only-testing:codepetTests/CompanyDataTests -only-testing:codepetTests/CompanyDataLibraryTests -only-testing:codepetTests/CompanyStoreTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` (new tests pass; the `CompanyDoc`/`CompanyState` additions — both trailing/defaulted — don't break existing suites).

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreToolsTests.swift
# commit (fsmonitor-off form): "feat(environment): CompanyState.enabledTools + persistence + toggleTool (nil→defaults)"
```

---

### Task 3: `EnvironmentView` + shell route

**Files:**
- Create: `codepet/Views/Environment/EnvironmentView.swift`
- Modify: `codepet/Views/Shell/AppShellView.swift`
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `Toolkit`/`ToolCategory`/`ToolItem` (Task 1), `CompanyStore` (`company.enabledTools`, `toggleTool`), CodepetTheme.
- Produces: `EnvironmentView()`; `ToolRowView(item:isOn:)`; `ToolBadge(item:)`.

- [ ] **Step 1: Write `EnvironmentView.swift`**

```swift
// codepet/Views/Environment/EnvironmentView.swift
import SwiftUI

/// The Environment = the company's toolkit. A recommendations strip (recommended-but-off
/// items) over category sections of skills/connectors/agents with per-item toggles.
struct EnvironmentView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var enabled: Set<String> { companyStore.company.enabledTools }
    private var recs: [ToolItem] { Toolkit.recommended.filter { !enabled.contains($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recs.isEmpty { recommendations }
                ForEach(ToolCategory.allCases) { cat in
                    categorySection(cat)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang == .vi ? "Bộ công cụ đề xuất" : "Recommended toolkit")
                .font(.pixelSystem(size: 13, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            ForEach(recs) { item in
                CodepetCard {
                    HStack(spacing: 10) {
                        ToolBadge(item: item)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                            if let why = item.why {
                                Text(why)
                                    .font(.pixelSystem(size: 11))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                            Text(item.category.enableVerb(lang))
                                .font(.pixelSystem(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(item.category.tint))
                        }.buttonStyle(.plain)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func categorySection(_ cat: ToolCategory) -> some View {
        let items = Toolkit.items(in: cat)
        let onCount = items.filter { enabled.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cat.label(lang).uppercased())
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.bodyText)
                Spacer()
                Text("\(onCount)/\(items.count)")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            ForEach(items) { item in
                ToolRowView(item: item, isOn: enabled.contains(item.id))
            }
        }
    }
}

/// The square category-tinted badge for a tool.
struct ToolBadge: View {
    let item: ToolItem
    var body: some View {
        Text(item.badge)
            .font(.pixelSystem(size: 11, weight: .bold))
            .foregroundColor(item.category.tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(item.category.tint.opacity(0.14)))
    }
}

/// One toolkit row — badge + name + detail + an on/off toggle button.
struct ToolRowView: View {
    let item: ToolItem
    let isOn: Bool
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        CodepetCard {
            HStack(spacing: 10) {
                ToolBadge(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(item.detail)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                    Text(isOn ? item.category.onLabel(lang) : item.category.enableVerb(lang))
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(isOn ? .white : item.category.tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? item.category.tint : item.category.tint.opacity(0.14)))
                }.buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Route `.environment` in `AppShellView.swift`**

Extend the content-slot router (the `Group { if .overview … else if .library … else … }`) with an `.environment` branch:

```swift
                Group {
                    if companyStore.view == .overview {
                        OverviewBoardView()
                    } else if companyStore.view == .library {
                        LibraryView()
                    } else if companyStore.view == .environment {
                        EnvironmentView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite to confirm no regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Environment/EnvironmentView.swift codepet/Views/Shell/AppShellView.swift
# commit (fsmonitor-off form): "feat(environment): EnvironmentView (recs + category toggles) + shell .environment route"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. The Environment tab now shows the recommended toolkit + skills/connectors/agents with working on/off toggles that persist per company.

---

## Self-Review

**Spec coverage:** `Toolkit` catalog (13 items, categories, defaults/recommended, helpers) + `ToolCategory` VI/EN chrome + tint (Task 1 ✓); `CompanyState.enabledTools` + `CompanyDoc.enabledTools` + `state(from:)` (nil→defaults / []→off / [ids]→set) + `CompanyData.enabledToolsPayload`/`saveEnabledTools` + `CompanyStore.toggleTool` + injectable `toolsSaver` (Task 2 ✓); `EnvironmentView` (recs strip of off-recommended + category sections w/ on/total + toggles) + `ToolRowView`/`ToolBadge` + `.environment` route (Task 3 ✓). Decisions honored: static catalog (no CF); recs strip drops enabled items; enabled-id-set persistence; fail-soft; defaults `{prd-writer, github, explorer}`.

**Placeholder scan:** none — every step has complete code or an exact command.

**Type consistency:** `Toolkit.defaultEnabledIds: Set<String>` (Task 1) is the `CompanyState.enabledTools` init default + the `state(from:)` fallback (Task 2). `ToolCategory.tint`/`.label`/`.enableVerb`/`.onLabel` + `ToolItem` (Task 1) consumed by `EnvironmentView`/`ToolRowView`/`ToolBadge` (Task 3). `CompanyStore.toggleTool(id:)` (Task 2) called by the views (Task 3). `toolsSaver: (String, [String]) async -> Bool = CompanyData.saveEnabledTools` — signatures match. `Toolkit.items(in:)`/`.recommended` (Task 1) drive the view sections.

**Known notes for the implementer:** (a) Task 3 views have no unit tests by design (SwiftUI verified by build); TDD applies to Tasks 1–2. (b) `enabledTools` is a `Set<String>` — persisted order is non-deterministic (`Array(company.enabledTools)`); that's fine for a set (the payload test asserts membership via a fixed literal array, and `saveEnabledTools` order doesn't matter). (c) `CompanyState.enabledTools` and `CompanyDoc.enabledTools` are both added as defaulted/trailing so every existing call site keeps compiling; the Task-2 regression step proves it. (d) `Toolkit.swift` imports SwiftUI for `Color` (the `tint`).
