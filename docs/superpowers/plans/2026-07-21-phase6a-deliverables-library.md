# Phase 6A — Deliverables Model + Library View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native `Deliverable` model (kind + markdown body), persisted in `companies/{uid}`, and a `LibraryView` that lists delivered work and opens each in one reusable markdown viewer. No generation this slice — the Library shows an honest empty state until 6B.

**Architecture:** `Deliverable`/`DeliverableKind` replace the placeholder `LibItem`. A pure `MarkdownBlocks.parse` (tested) turns a body into blocks; `MarkdownView` renders them in CodepetTheme — one viewer for every kind. `library` persists as a JSON-safe field array on the doc (like `tasks`); the save path is deferred to 6B. `LibraryView` reads `company.library` and routes from `AppShellView`.

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `CompanyState`/`CompanyData`, CodepetTheme (`CodepetCard`, `.pixelSystem`, accents), `@Environment(\.uiLanguage)`, `AttributedString(markdown:)`. Spec: `docs/superpowers/specs/2026-07-21-phase6a-deliverables-library-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **Decisions:** ONE markdown viewer (kind = badge/icon only); FIELD-ARRAY persistence (JSON-safe, no subcollection); NO save path this slice (6B); NO `status`/drafts (6C); unknown `kind` decodes to `.other` (fail-open). Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Create `codepet/Models/Deliverable.swift` (Task 1: `Deliverable` + `DeliverableKind`)
- Create `codepet/Models/MarkdownBlocks.swift` (Task 2)
- Modify `codepet/Models/CompanyState.swift` (Task 3: `library: [Deliverable]`, remove `LibItem`)
- Modify `codepet/Services/CompanyData.swift` (Task 3: `CompanyDoc.library` + `state(from:)`)
- Create `codepet/Views/Library/MarkdownView.swift` (Task 4)
- Create `codepet/Views/Library/LibraryView.swift` (Task 4: view + card + detail)
- Modify `codepet/Views/Shell/AppShellView.swift` (Task 4: `.library` route)
- Tests: `codepetTests/{DeliverableModelTests, MarkdownBlocksTests, CompanyDataLibraryTests}.swift`

---

### Task 1: `Deliverable` + `DeliverableKind`

**Files:**
- Create: `codepet/Models/Deliverable.swift`
- Test: `codepetTests/DeliverableModelTests.swift`

**Interfaces:**
- Consumes: `AppLanguage`.
- Produces: `enum DeliverableKind: String, Codable, CaseIterable` (12 kinds + `.other`; `init(raw:)`, `init(from:)`, `label(_:)`, `icon`); `struct Deliverable: Codable, Hashable, Identifiable` (id/kind/title/body/createdAt?/sourceTaskId?).

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/DeliverableModelTests.swift
import XCTest
@testable import codepet

final class DeliverableModelTests: XCTestCase {
    func testKindLabelsAndIconsNonEmptyBothLanguages() {
        for k in DeliverableKind.allCases {
            XCTAssertFalse(k.label(.en).isEmpty)
            XCTAssertFalse(k.label(.vi).isEmpty)
            XCTAssertFalse(k.icon.isEmpty)
        }
    }
    func testUnknownKindFallsBackToOther() {
        XCTAssertEqual(DeliverableKind(raw: "wat"), .other)
        XCTAssertEqual(DeliverableKind(raw: "plan"), .plan)
        let data = "\"wat\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(DeliverableKind.self, from: data), .other)
    }
    func testDeliverableRoundTripsWithNilOptionals() throws {
        let d = Deliverable(id: "d1", kind: .doc, title: "Scope", body: "# Hi")
        XCTAssertNil(d.createdAt)
        XCTAssertNil(d.sourceTaskId)
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DeliverableModelTests 2>&1 | tail -20`
Expected: FAIL — no `DeliverableKind`/`Deliverable`.

- [ ] **Step 3: Write `Deliverable.swift`**

```swift
// codepet/Models/Deliverable.swift
import Foundation

/// A deliverable kind — mirrors the web StructuredKind, plus `.other` for unknown
/// values. Rendering is uniform (markdown); kind drives only the badge + icon.
enum DeliverableKind: String, Codable, CaseIterable {
    case doc, post, email, legal, screens, sheet, site, dms, calendar, checklist, plan, text, other

    /// Map an arbitrary string to a known kind, unknown → `.other`.
    init(raw: String) { self = DeliverableKind(rawValue: raw) ?? .other }

    /// Decode fail-open: an unrecognized kind string becomes `.other`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeliverableKind(rawValue: raw) ?? .other
    }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .doc:       return lang == .vi ? "Tài liệu" : "Doc"
        case .post:      return lang == .vi ? "Bài đăng" : "Post"
        case .email:     return "Email"
        case .legal:     return lang == .vi ? "Pháp lý" : "Legal"
        case .screens:   return lang == .vi ? "Màn hình" : "Screens"
        case .sheet:     return lang == .vi ? "Bảng tính" : "Sheet"
        case .site:      return lang == .vi ? "Trang web" : "Site"
        case .dms:       return lang == .vi ? "Tin nhắn" : "DMs"
        case .calendar:  return lang == .vi ? "Lịch" : "Calendar"
        case .checklist: return lang == .vi ? "Danh sách" : "Checklist"
        case .plan:      return lang == .vi ? "Kế hoạch" : "Plan"
        case .text:      return lang == .vi ? "Văn bản" : "Text"
        case .other:     return lang == .vi ? "Khác" : "Other"
        }
    }

    var icon: String {
        switch self {
        case .doc:       return "doc.text"
        case .post:      return "megaphone"
        case .email:     return "envelope"
        case .legal:     return "checkmark.seal"
        case .screens:   return "rectangle.on.rectangle"
        case .sheet:     return "tablecells"
        case .site:      return "globe"
        case .dms:       return "bubble.left.and.bubble.right"
        case .calendar:  return "calendar"
        case .checklist: return "checklist"
        case .plan:      return "map"
        case .text:      return "text.alignleft"
        case .other:     return "doc"
        }
    }
}

/// A delivered work product. `body` is markdown, rendered uniformly by MarkdownView.
struct Deliverable: Codable, Hashable, Identifiable {
    let id: String
    var kind: DeliverableKind
    var title: String
    var body: String
    var createdAt: String?    // ISO-8601 (JSON-safe; newest-first sort is lexicographic)
    var sourceTaskId: String?

    init(id: String = UUID().uuidString, kind: DeliverableKind, title: String, body: String,
         createdAt: String? = nil, sourceTaskId: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.sourceTaskId = sourceTaskId
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/Deliverable.swift codepetTests/DeliverableModelTests.swift
# commit (fsmonitor-off form): "feat(library): Deliverable + DeliverableKind (kind+markdown, .other fallback)"
```

---

### Task 2: `MarkdownBlocks.parse`

**Files:**
- Create: `codepet/Models/MarkdownBlocks.swift`
- Test: `codepetTests/MarkdownBlocksTests.swift`

**Interfaces:**
- Produces: `enum MarkdownBlock: Equatable { case heading(level: Int, text: String); case bullet(String); case paragraph(String) }`; `MarkdownBlocks.parse(_:) -> [MarkdownBlock]`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/MarkdownBlocksTests.swift
import XCTest
@testable import codepet

final class MarkdownBlocksTests: XCTestCase {
    func testParsesHeadingsBulletsParagraphs() {
        let md = """
        # Title
        intro line one
        intro line two

        ## Section
        - first
        - second
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .heading(level: 1, text: "Title"),
            .paragraph("intro line one intro line two"),
            .heading(level: 2, text: "Section"),
            .bullet("first"),
            .bullet("second"),
        ])
    }
    func testLevelsAndStarBullets() {
        XCTAssertEqual(MarkdownBlocks.parse("### Deep"), [.heading(level: 3, text: "Deep")])
        XCTAssertEqual(MarkdownBlocks.parse("* star"), [.bullet("star")])
    }
    func testEmptyAndPlain() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("just text"), [.paragraph("just text")])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/MarkdownBlocksTests 2>&1 | tail -20`
Expected: FAIL — no `MarkdownBlocks`.

- [ ] **Step 3: Write `MarkdownBlocks.swift`**

```swift
// codepet/Models/MarkdownBlocks.swift
import Foundation

/// A parsed markdown block — the minimal set for deliverable bodies.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
}

/// Pure line-based markdown → blocks. Headings (# / ## / ###), bullets (- / *),
/// and paragraphs (consecutive non-blank lines joined; a blank line flushes).
enum MarkdownBlocks {
    static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: " ")))
                para = []
            }
        }
        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("### ") {
                flush(); blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush(); blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush(); blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush(); blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                para.append(line)
            }
        }
        flush()
        return blocks
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/MarkdownBlocks.swift codepetTests/MarkdownBlocksTests.swift
# commit (fsmonitor-off form): "feat(library): pure MarkdownBlocks.parse (headings/bullets/paragraphs)"
```

---

### Task 3: `CompanyState.library: [Deliverable]` + `CompanyData` mapping

**Files:**
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataLibraryTests.swift`

**Interfaces:**
- Consumes: `Deliverable` (Task 1).
- Produces: `CompanyState.library: [Deliverable]`; `CompanyDoc.library: [Deliverable]?`; `state(from:)` maps `doc.library ?? []`. `LibItem` removed.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyDataLibraryTests.swift
import XCTest
@testable import codepet

final class CompanyDataLibraryTests: XCTestCase {
    func testStateMapsLibrary() {
        let d = Deliverable(id: "d1", kind: .plan, title: "Plan", body: "x")
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(), stage: nil,
                                                   companionId: nil, onboardedAt: nil, tasks: nil, library: [d]))
        XCTAssertEqual(s.library.map(\.id), ["d1"])
        let empty = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                       onboardedAt: nil, tasks: nil, library: nil))
        XCTAssertEqual(empty.library, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataLibraryTests 2>&1 | tail -20`
Expected: FAIL — `CompanyDoc` has no `library:` param / `s.library` element type mismatch.

- [ ] **Step 3: Swap the model in `CompanyState.swift`**

Remove the `LibItem` struct (lines ~12–17) entirely. Change the `library` field type and the init parameter type from `[LibItem]` to `[Deliverable]`:

In the struct body:

```swift
    var library: [Deliverable]
```

In the explicit init signature:

```swift
    init(brief: CompanyBrief, departments: [Department], library: [Deliverable],
         stage: ProjectStage, companionId: String, onboardedAt: Date? = nil,
         tasks: [RoadmapTask] = []) {
```

(`.empty` and the init body use `library: []` / `self.library = library` — no text change needed; `[]` infers the new element type.)

- [ ] **Step 4: Extend `CompanyData.swift`**

1. Add to `CompanyDoc` (after `tasks`):

```swift
    var library: [Deliverable]?  // JSON-safe (strings/enum-as-string/optional strings)
```

2. In `state(from:)`, change the hardcoded `library: []` to map the doc:

```swift
            departments: [],
            library: doc.library ?? [],
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS. Existing `CompanyDoc` call sites (which omit `library`) still compile — it's a trailing optional with an implicit nil default.

- [ ] **Step 6: Run the CompanyData/CompanyStore regression suites**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataLibraryTests -only-testing:codepetTests/CompanyDataTests -only-testing:codepetTests/CompanyDataTasksTests -only-testing:codepetTests/CompanyDataSaveTests -only-testing:codepetTests/CompanyStoreTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` (the `LibItem`→`Deliverable` swap didn't break the doc mapping or any store test).

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepetTests/CompanyDataLibraryTests.swift
# commit (fsmonitor-off form): "feat(library): CompanyState.library: [Deliverable] + CompanyDoc mapping (replaces LibItem)"
```

---

### Task 4: `MarkdownView` + `LibraryView` + shell route

**Files:**
- Create: `codepet/Views/Library/MarkdownView.swift`, `codepet/Views/Library/LibraryView.swift`
- Modify: `codepet/Views/Shell/AppShellView.swift`
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `MarkdownBlocks.parse` (Task 2), `Deliverable`/`DeliverableKind` (Task 1), `CompanyStore.company.library`, CodepetTheme (`CodepetCard`, accents, `.pixelSystem`).
- Produces: `MarkdownView(markdown:)`; `LibraryView()`; `DeliverableCardView(deliverable:)`; `DeliverableDetailView(deliverable:)`.

- [ ] **Step 1: Write `MarkdownView.swift`**

```swift
// codepet/Views/Library/MarkdownView.swift
import SwiftUI

/// Renders markdown (via MarkdownBlocks.parse) as CodepetTheme-styled blocks — one
/// viewer for every deliverable kind. Inline emphasis via AttributedString(markdown:).
struct MarkdownView: View {
    let markdown: String
    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(.pixelSystem(size: level == 1 ? 16 : level == 2 ? 14 : 13, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundColor(CodepetTheme.mutedText)
                inline(text).foregroundColor(CodepetTheme.bodyText)
            }
            .font(.pixelSystem(size: 12))
        case let .paragraph(text):
            inline(text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.bodyText)
        }
    }

    /// Inline emphasis via AttributedString(markdown:), plain fallback.
    private func inline(_ text: String) -> Text {
        if let attr = try? AttributedString(markdown: text) { return Text(attr) }
        return Text(text)
    }
}
```

- [ ] **Step 2: Write `LibraryView.swift`**

```swift
// codepet/Views/Library/LibraryView.swift
import SwiftUI

/// The Library = delivered work. Lists company.library newest-first; each card opens
/// a markdown detail sheet. Empty → an honest empty state (nothing until 6B generates).
struct LibraryView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var selected: Deliverable?

    private var items: [Deliverable] {
        companyStore.company.library.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { d in
                            Button { selected = d } label: { DeliverableCardView(deliverable: d) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { DeliverableDetailView(deliverable: $0) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30)).foregroundColor(CodepetTheme.mutedText)
            Text(lang == .vi ? "Sản phẩm sẽ xuất hiện ở đây" : "Delivered work will appear here")
                .font(.pixelSystem(size: 15, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Khi Codepet tạo ra sản phẩm, chúng sẽ tập hợp ở đây."
                             : "Once Codepet produces work, it collects here.")
                .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: 360)
    }
}

/// One library row — kind icon + title + kind label.
struct DeliverableCardView: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang
    var body: some View {
        CodepetCard {
            HStack(spacing: 10) {
                Image(systemName: deliverable.kind.icon)
                    .foregroundColor(CodepetTheme.accentPurple).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deliverable.title)
                        .font(.pixelSystem(size: 13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(deliverable.kind.label(lang))
                        .font(.pixelSystem(size: 10, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Deliverable detail sheet — title + kind + the markdown body (scrolls).
struct DeliverableDetailView: View {
    let deliverable: Deliverable
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: deliverable.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                Text(deliverable.title)
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(16)
            Divider()
            ScrollView { MarkdownView(markdown: deliverable.body).padding(16) }
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(CodepetTheme.pageBackground)
    }
}
```

- [ ] **Step 3: Route `.library` in `AppShellView.swift`**

Extend the content-slot router (the `Group { if companyStore.view == .overview { OverviewBoardView() } else { ShellPlaceholderView(...) } }` from Phase 3B) to add a `.library` branch:

```swift
                Group {
                    if companyStore.view == .overview {
                        OverviewBoardView()
                    } else if companyStore.view == .library {
                        LibraryView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite to confirm no regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Library/MarkdownView.swift codepet/Views/Library/LibraryView.swift codepet/Views/Shell/AppShellView.swift
# commit (fsmonitor-off form): "feat(library): MarkdownView + LibraryView (list/detail) + shell .library route"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. The Library tab now renders the delivered-work list (or the honest empty state), and any deliverable opens in the markdown viewer.

---

## Self-Review

**Spec coverage:** `Deliverable` + `DeliverableKind` (12 + `.other`, label/icon, decode fallback) replacing `LibItem` (Task 1 ✓); pure `MarkdownBlocks.parse` (Task 2 ✓); `CompanyState.library: [Deliverable]` + `CompanyDoc.library` + `state(from:)` mapping (Task 3 ✓); `MarkdownView` one-viewer + `LibraryView`/`DeliverableCardView`/`DeliverableDetailView` + `.library` route (Task 4 ✓). Decisions honored: one markdown viewer; field-array persistence; no save path; no `status`; unknown kind → `.other`; VI/EN.

**Placeholder scan:** none — every step has complete code or an exact command.

**Type consistency:** `Deliverable(id:kind:title:body:createdAt:sourceTaskId:)` + `DeliverableKind.label`/`icon`/`init(raw:)` (Task 1) used by Tasks 3/4. `MarkdownBlock`/`MarkdownBlocks.parse` (Task 2) consumed by `MarkdownView` (Task 4). `CompanyState.library: [Deliverable]` / `CompanyDoc.library: [Deliverable]?` (Task 3) read by `LibraryView` (Task 4). `.sheet(item:)` uses `Deliverable: Identifiable`. `AppView.library` case already exists (Phase 1). CodepetTheme tokens (`CodepetCard`, `accentPurple`, `.pixelSystem`) match.

**Known notes for the implementer:** (a) Task 4 views have no unit tests by design (SwiftUI verified by build); TDD applies to Tasks 1–3. (b) heading font sizes are all < 18pt so they render in the Inter body face (≥18pt would switch to the Minecraft pixel face — deliberately avoided for document readability). (c) removing `LibItem` is safe — it's referenced only in `CompanyState.swift`; a repo-wide `grep LibItem` after Task 3 must return nothing.
