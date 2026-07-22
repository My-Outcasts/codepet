# Order 3 — Departments (Company + Detail + Tasks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the native macOS app the web's 8-department model as three faithful views — Company, Department detail, and Tasks — derived from one `dept`-tagged roadmap task list.

**Architecture:** Add an optional `dept` to `RoadmapTask`; `generateRoadmap` emits it; a static `DEPARTMENTS` catalog + a pure per-department derivation helper feed three new SwiftUI views (CompanyView, DepartmentDetailView, TasksView), reusing existing `CompanyStore` actions and `RoadmapEngine` status. Overview is untouched.

**Tech Stack:** Swift/SwiftUI (macOS 13+), the existing `CodepetTheme`/`CodepetCard`/`pixelSystem` design system; TypeScript Firebase CF (`generateRoadmap`) for the `dept` field.

## Global Constraints

- **Web fidelity is the mandate** — match `components/views/{CompanyView,DepartmentDetail,TasksView}.tsx` in `/private/tmp/codepet-web-develop` for layout, copy, states, colors. Exact copy strings are given verbatim below; use them.
- **8 departments, this exact order + abbreviations + accent:** `eng` Engineering (En, accentBlue) · `design` Design (De, accentPurple) · `mkt` Marketing (Mk, accentOrange) · `sales` Sales (Sa, accentPurple) · `support` Support (Su, accentPink) · `fin` Finance (Fi, accentGold) · `ops` Operations (Op, accentTeal) · `legal` Legal (Lg, accentPurple).
- **`dept` is OPTIONAL** (`String?`) on `RoadmapTask` — strict Codable; a required field blanks existing saved boards.
- **Two repos:** Swift → `/Users/monatruong/Documents/codepet-rebuild-wt` (branch `feat/company-chat-cf`). CF → `/Users/monatruong/Documents/codepet-scaffoldfn-wt` (branch `feat/company-chat-fn`). Deploy scoped from `/private/tmp/cc-deploy` (the off-iCloud dir), never a bare functions deploy.
- **iCloud git:** implementers do NOT commit — the controller commits (git hangs on the worktree). `rm -f "<gitdir>/index.lock"` before writes; commit as a background job with `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; verify HEAD advanced. Commit messages via `-F <file>`.
- **Build authority:** `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` (FOREGROUND) / `tsc`. SourceKit "cannot find type / no such module" are FALSE POSITIVES.
- **CF tests:** jest can't run on the iCloud worktree — verify pure CF logic via `node --experimental-strip-types` off iCloud; `tsc` is the authoritative type check.
- **Swift tests:** the `codepetTests` target (XCTest); pure helpers get unit tests, SwiftUI views are verified by build + the final E2E.

---

## Task 1: `RoadmapTask.dept` (optional, migration-safe)

**Files:**
- Modify: `codepet/Models/RoadmapTask.swift`
- Test: `codepetTests/RoadmapTaskDeptTests.swift`

**Interfaces:**
- Produces: `RoadmapTask.dept: String?` (default `nil` in the initializer).

- [ ] **Step 1: Write the failing test**

Create `codepetTests/RoadmapTaskDeptTests.swift`:

```swift
import XCTest
@testable import codepet

final class RoadmapTaskDeptTests: XCTestCase {
    // Existing saved tasks have NO `dept` key — decode must still succeed (dept == nil).
    func testDecodesWithoutDept() throws {
        let json = """
        {"id":"t1","title":"Ship","detail":"d","phase":"build","who":"does","dependsOn":[],"done":false,"drafted":false}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(RoadmapTask.self, from: json)
        XCTAssertNil(task.dept)
        XCTAssertEqual(task.id, "t1")
    }
    func testDecodesWithDept() throws {
        let json = """
        {"id":"t1","title":"Ship","detail":"d","phase":"build","who":"does","dependsOn":[],"done":false,"drafted":false,"dept":"eng"}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(RoadmapTask.self, from: json)
        XCTAssertEqual(task.dept, "eng")
    }
    func testInitDefaultsDeptNil() {
        let t = RoadmapTask(id: "x", title: "T", detail: "", phase: .find, who: .you)
        XCTAssertNil(t.dept)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "RoadmapTaskDept|error:"`
Expected: compile failure — `RoadmapTask` has no member `dept`.

- [ ] **Step 3: Add the field**

In `codepet/Models/RoadmapTask.swift`, add to the `RoadmapTask` struct (after `var dependsOn: [String]`), and to the initializer:

```swift
    var done: Bool
    var drafted: Bool
    /// Owning department key (one of the 8 DEPARTMENTS keys). OPTIONAL: existing saved
    /// tasks predate this field, and RoadmapTask decodes strictly — a required `dept`
    /// would fail to decode every stored board. nil == unassigned (pre-department tasks).
    var dept: String?

    init(id: String, title: String, detail: String, phase: RoadmapPhase, who: TaskWho,
         dependsOn: [String] = [], done: Bool = false, drafted: Bool = false, dept: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.phase = phase
        self.who = who; self.dependsOn = dependsOn; self.done = done; self.drafted = drafted
        self.dept = dept
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "RoadmapTaskDept|Test Suite.*passed|error:"`
Expected: the 3 `RoadmapTaskDept` tests pass; build succeeds.

- [ ] **Step 5: Controller commits** (implementer stops here)

---

## Task 2: `Department` model + `DEPARTMENTS` catalog + derivation helper

**Files:**
- Create: `codepet/Models/Department.swift`
- Test: `codepetTests/DepartmentCatalogTests.swift`

**Interfaces:**
- Produces:
  - `struct Department { let key, name, ab: String; let accent: Color; let rationale, focus: String; var coverAsset: String { "dept-\(key)" } }`
  - `enum DepartmentCatalog { static let all: [Department]; static func find(_ key: String?) -> Department? }`
  - `enum DepartmentStatus { case attention, ready, idle, later }` with `label(_ lang)` and a tint color.
  - `struct DepartmentSummary { let department: Department; let status: DepartmentStatus; let pending: Int; let currentTaskTitle: String? }`
  - `static func DepartmentCatalog.summaries(tasks: [RoadmapTask]) -> [DepartmentSummary]` (catalog order) and `static func needToday(_ summaries:) -> Int`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentCatalogTests.swift`:

```swift
import XCTest
@testable import codepet

final class DepartmentCatalogTests: XCTestCase {
    func testEightDepartmentsInOrder() {
        XCTAssertEqual(DepartmentCatalog.all.map(\.key),
                       ["eng","design","mkt","sales","support","fin","ops","legal"])
        XCTAssertEqual(DepartmentCatalog.find("eng")?.name, "Engineering")
        XCTAssertEqual(DepartmentCatalog.find("eng")?.ab, "En")
        XCTAssertNil(DepartmentCatalog.find(nil))
        XCTAssertFalse(DepartmentCatalog.find("eng")!.rationale.isEmpty)
    }
    private func task(_ id: String, dept: String?, who: TaskWho, done: Bool = false, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, dependsOn: deps, done: done, dept: dept)
    }
    func testSummaryStatusAndCounts() {
        let tasks = [
            task("a", dept: "eng", who: .you),                 // needsYou → attention
            task("b", dept: "eng", who: .does),                // codepetCanDo
            task("c", dept: "mkt", who: .does),                // codepetCanDo → ready
            task("d", dept: "fin", who: .does, done: true),    // done → idle (no open)
        ]
        let s = DepartmentCatalog.summaries(tasks: tasks)
        let eng = s.first { $0.department.key == "eng" }!
        XCTAssertEqual(eng.status, .attention)         // has a needsYou task
        XCTAssertEqual(eng.pending, 2)
        XCTAssertEqual(eng.currentTaskTitle, "a")
        XCTAssertEqual(s.first { $0.department.key == "mkt" }!.status, .ready)
        XCTAssertEqual(s.first { $0.department.key == "fin" }!.status, .idle)   // only a done task
        XCTAssertEqual(s.first { $0.department.key == "legal" }!.status, .later) // zero tasks
        XCTAssertEqual(DepartmentCatalog.needToday(s), 1)   // only eng is attention
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "DepartmentCatalog|error:"`
Expected: compile failure — no `Department`/`DepartmentCatalog`.

- [ ] **Step 3: Implement**

Create `codepet/Models/Department.swift`:

```swift
// codepet/Models/Department.swift
import SwiftUI

/// One of the 8 fixed departments (mirrors the web DEPTS catalog). Static identity +
/// hand-written rationale/focus; live status/tasks are DERIVED from the dept-tagged
/// roadmap tasks, never stored here.
struct Department: Identifiable, Hashable {
    let key: String
    let name: String
    let ab: String          // 2-letter badge
    let accent: Color
    let rationale: String    // web `d.need` — what this department must accomplish
    let focus: String        // web `d.byte` — a short companion-style focus line
    var id: String { key }
    var coverAsset: String { "dept-\(key)" }
}

enum DepartmentStatus {
    case attention, ready, idle, later
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .attention: return lang == .vi ? "cần bạn" : "needs you"
        case .ready:     return lang == .vi ? "sẵn sàng" : "ready"
        case .idle:      return lang == .vi ? "nhàn rỗi" : "idle"
        case .later:     return lang == .vi ? "sau này" : "later"
        }
    }
    var tint: Color {
        switch self {
        case .attention: return CodepetTheme.accentBlue
        case .ready:     return CodepetTheme.accentTeal
        case .idle:      return CodepetTheme.mutedText
        case .later:     return CodepetTheme.mutedText
        }
    }
}

struct DepartmentSummary: Identifiable {
    let department: Department
    let status: DepartmentStatus
    let pending: Int
    let currentTaskTitle: String?
    var id: String { department.key }
}

enum DepartmentCatalog {
    static let all: [Department] = [
        Department(key: "eng", name: "Engineering", ab: "En", accent: CodepetTheme.accentBlue,
            rationale: "Build and ship the product itself — the features, the technical foundation, the things users touch.",
            focus: "This is where the thing you're building actually gets made."),
        Department(key: "design", name: "Design", ab: "De", accent: CodepetTheme.accentPurple,
            rationale: "Shape how the product looks and feels so the first run lands and people get it fast.",
            focus: "Make it clear, make it yours, make it easy to fall into."),
        Department(key: "mkt", name: "Marketing", ab: "Mk", accent: CodepetTheme.accentOrange,
            rationale: "Get the product in front of the right people and tell its story clearly.",
            focus: "The best product still needs someone to hear about it."),
        Department(key: "sales", name: "Sales", ab: "Sa", accent: CodepetTheme.accentPurple,
            rationale: "Turn interest into real users and first customers, one conversation at a time.",
            focus: "Early on, you land users personally — not by broadcasting."),
        Department(key: "support", name: "Support", ab: "Su", accent: CodepetTheme.accentPink,
            rationale: "Help your users succeed and turn their friction into what you build next.",
            focus: "Every question is a signal about what to fix."),
        Department(key: "fin", name: "Finance", ab: "Fi", accent: CodepetTheme.accentGold,
            rationale: "Keep the money side sound — pricing, runway, and the basics that keep you shipping.",
            focus: "Know your numbers before they force your hand."),
        Department(key: "ops", name: "Operations", ab: "Op", accent: CodepetTheme.accentTeal,
            rationale: "Stand up the machinery that lets the whole company run without you touching every step.",
            focus: "The boring plumbing that makes everything else possible."),
        Department(key: "legal", name: "Legal", ab: "Lg", accent: CodepetTheme.accentPurple,
            rationale: "Cover the legal and compliance minimum so shipping never becomes a liability.",
            focus: "Not glamorous, but it protects everything you're building."),
    ]

    static func find(_ key: String?) -> Department? {
        guard let key else { return nil }
        return all.first { $0.key == key }
    }

    /// Derive a summary per department (catalog order) from the dept-tagged tasks.
    static func summaries(tasks: [RoadmapTask]) -> [DepartmentSummary] {
        all.map { dep in
            let mine = tasks.filter { $0.dept == dep.key }
            if mine.isEmpty {
                return DepartmentSummary(department: dep, status: .later, pending: 0, currentTaskTitle: nil)
            }
            let open = mine.filter { !$0.done }
            let statuses = open.map { RoadmapEngine.status(for: $0, in: tasks) }
            let status: DepartmentStatus =
                statuses.contains(.needsYou) ? .attention
                : statuses.contains(.codepetCanDo) ? .ready
                : .idle
            return DepartmentSummary(department: dep, status: status,
                                     pending: open.count, currentTaskTitle: open.first?.title)
        }
    }

    static func needToday(_ summaries: [DepartmentSummary]) -> Int {
        summaries.filter { $0.status == .attention }.count
    }
}
```

Note: the existing bare `Department` struct in `Models/CompanyState.swift` is unused (`departments` is always `[]`). Leave it or rename it if it collides — if the compiler reports a redeclaration of `Department`, delete the stub in `CompanyState.swift` and change `var departments: [Department]` there to `var departments: [String] = []` (it's never populated; keeps the doc shape). Confirm via build.

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "DepartmentCatalog|Test Suite.*passed|error:"`
Expected: `DepartmentCatalog` tests pass; build succeeds.

- [ ] **Step 5: Controller commits**

---

## Task 3: `generateRoadmap` CF — emit `dept`

**Files (functions repo `codepet-scaffoldfn-wt`):**
- Modify: `functions/src/generateRoadmapCore.ts`
- Modify: `functions/src/generateRoadmap.ts` (tool schema)
- Modify: `functions/src/__tests__/generateRoadmap.test.ts`

**Interfaces:**
- `coerceRoadmap` output tasks now carry `dept` (∈ 8 keys, default `"ops"`).

- [ ] **Step 1: Add the failing test** (append to `generateRoadmap.test.ts`)

```ts
describe("coerceRoadmap dept", () => {
  it("keeps a valid dept and defaults an invalid/missing one to ops", () => {
    const out = coerceRoadmap({ tasks: [
      { phase: "build", title: "A", who: "does", deps: [], dept: "eng" },
      { phase: "find",  title: "B", who: "you",  deps: [], dept: "zzz" },
      { phase: "ship",  title: "C", who: "draft", deps: [] },
    ]}, { language: "en" });
    expect(out.tasks.find(t => t.title === "A")!.dept).toBe("eng");
    expect(out.tasks.find(t => t.title === "B")!.dept).toBe("ops"); // invalid → ops
    expect(out.tasks.find(t => t.title === "C")!.dept).toBe("ops"); // missing → ops
  });
});
```

- [ ] **Step 2: Verify it fails** (node strip-types, off iCloud)

Copy `generateRoadmapCore.ts` to `/private/tmp/gr3/` and run a node assertion importing `coerceRoadmap` and checking `.dept`. Expected: `dept` is `undefined` (field not emitted yet).

- [ ] **Step 3: Implement** in `functions/src/generateRoadmapCore.ts`

Add near the top constants:
```ts
const DEPT_KEYS = new Set(["eng","design","mkt","sales","support","fin","ops","legal"]);
```
Add `dept` to `RawTask` (`dept?: unknown`) and to `KeptTask` (`dept: string`). In the kept-loop push, resolve the dept:
```ts
    const dept = typeof t.dept === "string" && DEPT_KEYS.has(t.dept) ? t.dept : "ops";
    kept.push({ id: `${slug(title)}-${kept.length}`, title, detail, phase: t.phase, who, deps, dept });
```
Add `dept: k.dept` to the returned `RoadmapTask` object (alongside `done: false, drafted: false`). Update the `RoadmapTask` type in this file to include `dept: string`.

In `functions/src/generateRoadmap.ts`, add `dept` to the `record_roadmap` tool `input_schema` task properties: `dept: { type: "string", description: "The single owning department: one of eng, design, mkt, sales, support, fin, ops, legal." }`, and add `"dept"` to the task `required` array. In `buildRoadmapPrompt` (core), add a line instructing: "Assign each task the single department that owns it, from: eng, design, mkt, sales, support, fin, ops, legal."

- [ ] **Step 4: Verify it passes** (node strip-types) + build

Run the node assertion → dept valid/default correct. Then sync to `/private/tmp/cc-deploy/functions/src` and `npm run build` → `tsc` exit 0.

- [ ] **Step 5: Controller commits, then deploys (scoped, from local disk)**

```bash
cd /private/tmp/cc-deploy && FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --only functions:generateRoadmap --force
```
Verify: `firebase functions:list | grep generateRoadmap` present; `curl -s -o /dev/null -w "%{http_code}" -X POST .../generateRoadmap -d '{"language":"en"}'` → 401. (A fresh in-app regeneration will carry `dept`; verified in the E2E.)

---

## Task 4: Cover art assets (avif → PNG → Assets.xcassets)

**Files:**
- Create: `codepet/Assets.xcassets/dept-{key}.imageset/` (8 imagesets) + PNGs

- [ ] **Step 1: Convert the 8 web covers to PNG**

```bash
mkdir -p /private/tmp/dept-covers
for k in eng design mkt sales support fin ops legal; do
  sips -s format png "/private/tmp/codepet-web-develop/public/covers/$k.avif" --out "/private/tmp/dept-covers/dept-$k.png" >/dev/null 2>&1 && echo "converted $k" || echo "FAILED $k (try the .webp source)"
done
ls -la /private/tmp/dept-covers/
```
Expected: 8 `dept-*.png` files. If avif fails, retry with the `.webp` source.

- [ ] **Step 2: Add each as an imageset**

For each key, create `codepet/Assets.xcassets/dept-{key}.imageset/` containing the PNG and a `Contents.json`:
```json
{
  "images" : [ { "filename" : "dept-{key}.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```
(Replace `{key}`.) Copy the matching PNG into each folder.

- [ ] **Step 3: Verify they load in a build**

Add a throwaway `Image("dept-eng")` nowhere-shown, or just confirm the build sees the assets: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|error:"`. The real visual check is the E2E (covers render on the cards). Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Controller commits** (assets are binary — `git add codepet/Assets.xcassets/dept-*.imageset`)

---

## Task 5: CompanyView

**Files:**
- Create: `codepet/Views/Company/CompanyView.swift`

**Interfaces:**
- Consumes: `DepartmentCatalog.summaries`, `CompanyStore`. Produces: `CompanyView` with a binding/callback to open a department (`onOpen: (String) -> Void`).

- [ ] **Step 1: Implement** (faithful to `CompanyView.tsx`)

Create `codepet/Views/Company/CompanyView.swift`:

```swift
// codepet/Views/Company/CompanyView.swift
import SwiftUI

/// The web CompanyView — every department as a scannable row (cover + status +
/// current task + count). Derives per-dept summaries from the dept-tagged tasks.
struct CompanyView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    let onOpen: (String) -> Void

    private var summaries: [DepartmentSummary] {
        DepartmentCatalog.summaries(tasks: companyStore.company.tasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                VStack(spacing: 10) {
                    ForEach(summaries) { s in row(s) }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Công ty của bạn" : "Your company")
                    .font(.pixelSystem(size: 22, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Text(subtitle).font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
            }
            Spacer()
            Button {
                Task { await companyStore.generateRoadmap(language: lang) }
            } label: {
                Text(replanLabel)
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(CodepetTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(companyStore.isGeneratingRoadmap)
        }
    }

    private var subtitle: String {
        let n = DepartmentCatalog.needToday(summaries)
        return lang == .vi ? "Tám phòng ban · \(n) cần bạn hôm nay"
                           : "Eight departments · \(n) need you today"
    }
    private var replanLabel: String {
        companyStore.isGeneratingRoadmap
            ? (lang == .vi ? "Đang lập lại…" : "Re-planning…")
            : (lang == .vi ? "Lập lại cho giai đoạn của tôi" : "Re-plan for my stage")
    }

    private func row(_ s: DepartmentSummary) -> some View {
        let later = s.status == .later
        return Button { if !later { onOpen(s.department.key) } } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Image(s.department.coverAsset).resizable().scaledToFill()
                        .frame(width: 96, height: 64).clipped()
                        .cornerRadius(10)
                    Text(s.department.ab)
                        .font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(s.department.accent.opacity(0.85)).cornerRadius(6)
                        .padding(6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(s.department.name).font(.pixelSystem(size: 14, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        statusPill(s.status)
                    }
                    Text(taskLine(s)).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(countLabel(s)).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.bodyText)
                    if !later {
                        Text(lang == .vi ? "Mở" : "Open").font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(s.department.accent)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.hairline, lineWidth: 1))
            .opacity(later ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ st: DepartmentStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(st.tint).frame(width: 6, height: 6)
            Text(st.label(lang)).font(.pixelSystem(size: 10, weight: .medium)).foregroundColor(st.tint)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(st.tint.opacity(0.12)))
    }

    private func taskLine(_ s: DepartmentSummary) -> String {
        if s.status == .later { return lang == .vi ? "Sẽ đến sau khi bạn tiến bộ" : "Comes later as you progress" }
        return s.currentTaskTitle ?? (lang == .vi ? "Đã xong hết" : "All clear")
    }
    private func countLabel(_ s: DepartmentSummary) -> String {
        if s.status == .later { return lang == .vi ? "Sau" : "Later" }
        if s.pending == 0 { return lang == .vi ? "Đã xong hết" : "All clear" }
        return lang == .vi ? "\(s.pending) việc" : "\(s.pending) to do"
    }
}
```

Note: this references `companyStore.isGeneratingRoadmap` and `CodepetTheme.surface`/`.hairline`. If `isGeneratingRoadmap` doesn't exist, add a `@Published var isGeneratingRoadmap = false` to `CompanyStore` set true/false around the `generateRoadmap` body (a small addition — do it in this task). If `CodepetTheme.surface`/`.hairline` are named differently, use the nearest existing token (check `CodepetTheme.swift`; e.g. `cardBackground`/`border`) — match what CompanyView/LibraryView already use.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|error:"`
Expected: BUILD SUCCEEDED. (Visual fidelity confirmed in the E2E.)

- [ ] **Step 3: Controller commits**

---

## Task 6: DepartmentDetailView + web-faithful task card

**Files:**
- Create: `codepet/Views/Company/DepartmentDetailView.swift`

**Interfaces:**
- Consumes: `DepartmentCatalog.find`, `CompanyStore` (`runTask`, `company.tasks`, `company.library`, `company.companionId`), `RoadmapEngine.status`, `CharacterImage`. Produces: `DepartmentDetailView(deptKey: String, onBack: () -> Void)`.

- [ ] **Step 1: Implement** (faithful to `DepartmentDetail.tsx`)

Create `codepet/Views/Company/DepartmentDetailView.swift`:

```swift
// codepet/Views/Company/DepartmentDetailView.swift
import SwiftUI

struct DepartmentDetailView: View {
    let deptKey: String
    let onBack: () -> Void
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var dept: Department? { DepartmentCatalog.find(deptKey) }
    private var tasks: [RoadmapTask] { companyStore.company.tasks.filter { $0.dept == deptKey } }
    private var left: Int { tasks.filter { !$0.done }.count }

    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        return AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(lang == .vi ? "Công ty" : "Company").font(.pixelSystem(size: 12))
                    }.foregroundColor(CodepetTheme.bodyText)
                }.buttonStyle(.plain)

                hero(d)
                Text(d.rationale).font(.pixelSystem(size: 13)).foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    CharacterImage(companyStore.company.companionId, size: 28)
                    Text(d.focus).font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(lang == .vi ? "Việc cần làm · còn \(left)/\(tasks.count)"
                                 : "What needs doing · \(left) of \(tasks.count) left")
                    .font(.pixelSystem(size: 12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                    .padding(.top, 4)
                if tasks.isEmpty {
                    Text(lang == .vi ? "Chưa có việc trong phòng ban này." : "No tasks in this department yet.")
                        .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                } else {
                    ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                }
            }
            .padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private func hero(_ d: Department) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(d.coverAsset).resizable().scaledToFill().frame(height: 140).clipped()
            LinearGradient(colors: [.clear, d.accent.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 8) {
                Text(d.ab).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text(d.name).font(.pixelSystem(size: 18, weight: .bold)).foregroundColor(.white)
            }.padding(12)
        }
        .frame(height: 140).cornerRadius(14).clipped()
    }
}

/// Web-faithful department task card (mirrors DepartmentDetail.tsx TaskCard): title +
/// detail + status pill and ONE action button by state; done → a delivered row.
private struct DepartmentTaskCard: View {
    let task: RoadmapTask
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    private var status: TaskStatus { RoadmapEngine.status(for: task, in: companyStore.company.tasks) }
    private var delivered: Deliverable? { companyStore.company.library.first { $0.sourceTaskId == task.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.pixelSystem(size: 13, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                    if !task.detail.isEmpty {
                        Text(task.detail).font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !task.done {
                    Text(status.label(lang)).font(.pixelSystem(size: 10, weight: .medium))
                        .foregroundColor(statusTint(status))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(statusTint(status).opacity(0.12)))
                }
            }
            if task.done {
                Text(lang == .vi ? "✓ Đã duyệt · đã giao" : "✓ Approved · delivered")
                    .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.accentTeal)
            } else {
                actionButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder private var actionButton: some View {
        let running = companyStore.runningTaskIds.contains(task.id)
        Button {
            Task { await companyStore.runTask(task, language: lang) }
        } label: {
            HStack(spacing: 5) {
                if running { ProgressView().controlSize(.mini) }
                Text(running ? (lang == .vi ? "Đang chạy…" : "Running…") : buttonLabel)
            }
            .font(.pixelSystem(size: 11, weight: .semibold))
            .foregroundColor(task.who == .you ? CodepetTheme.bodyText : .white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(task.who == .you
                ? AnyView(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
                : AnyView(Capsule().fill(CodepetTheme.accentPurple)))
        }
        .buttonStyle(.plain)
        .disabled(status == .blocked || running)
    }

    private var buttonLabel: String {
        if task.drafted { return lang == .vi ? "Xem & duyệt" : "Review & approve" }
        switch task.who {
        case .you:   return lang == .vi ? "Hướng dẫn tôi" : "Walk me through it"
        case .draft: return lang == .vi ? "Codepet soạn giúp" : "Have Codepet draft it"
        case .does:  return lang == .vi ? "Codepet làm giúp" : "Have Codepet do it"
        }
    }
}
```

Note: `statusTint(_:)` — reuse the same helper `TaskCardView` uses (it's a free function or a method there). If it's private to `TaskCardView`, lift it to a small shared function in `RoadmapTask.swift` or duplicate the 5-case switch here (done → teal, needsApproval → gold, blocked → muted, needsYou → blue, codepetCanDo → purple). Match `TaskCardView`'s colors.

- [ ] **Step 2: Build** — `xcodebuild … build` → BUILD SUCCEEDED.
- [ ] **Step 3: Controller commits**

---

## Task 7: TasksView (4-column kanban)

**Files:**
- Create: `codepet/Views/Tasks/TasksView.swift`
- Test: `codepetTests/TaskColumnTests.swift`

**Interfaces:**
- Produces: `enum TaskColumn { case upNext, awaiting, yourMove, done }`, `static func column(for task:in:) -> TaskColumn`, and `TasksView`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/TaskColumnTests.swift`:

```swift
import XCTest
@testable import codepet

final class TaskColumnTests: XCTestCase {
    private func t(_ id: String, who: TaskWho, done: Bool = false, drafted: Bool = false, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, dependsOn: deps, done: done, drafted: drafted)
    }
    func testColumnMapping() {
        let base = t("blocker", who: .you)                       // undone → dep unsatisfied for dependents
        let all = [
            base,
            t("does", who: .does),                                // codepetCanDo → upNext
            t("draftpending", who: .draft),                       // codepetCanDo (draft, not yet) → upNext
            t("drafted", who: .does, drafted: true),              // needsApproval → awaiting
            t("you", who: .you),                                  // needsYou → yourMove
            t("done", who: .does, done: true),                    // done
            t("blocked", who: .does, deps: ["blocker"]),          // blocked → upNext (queued)
        ]
        func col(_ id: String) -> TaskColumn { TaskColumn.column(for: all.first { $0.id == id }!, in: all) }
        XCTAssertEqual(col("does"), .upNext)
        XCTAssertEqual(col("draftpending"), .upNext)
        XCTAssertEqual(col("blocked"), .upNext)
        XCTAssertEqual(col("drafted"), .awaiting)
        XCTAssertEqual(col("you"), .yourMove)
        XCTAssertEqual(col("done"), .done)
    }
}
```

- [ ] **Step 2: Verify it fails** — `xcodebuild … test` → no `TaskColumn`.

- [ ] **Step 3: Implement**

Create `codepet/Views/Tasks/TasksView.swift`:

```swift
// codepet/Views/Tasks/TasksView.swift
import SwiftUI

/// Kanban buckets by the task's derived state. Up next folds "Codepet can do" +
/// "queued/blocked does-or-draft" (web's does + draft-not-yet); a produced draft
/// sits in Awaiting; needsYou in Your move; done in Done.
enum TaskColumn: CaseIterable {
    case upNext, awaiting, yourMove, done
    static func column(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskColumn {
        if task.done { return .done }
        switch RoadmapEngine.status(for: task, in: tasks) {
        case .done:          return .done
        case .needsApproval: return .awaiting
        case .needsYou:      return .yourMove
        case .codepetCanDo, .blocked: return .upNext
        }
    }
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .upNext:   return lang == .vi ? "Tiếp theo" : "Up next"
        case .awaiting: return lang == .vi ? "Chờ bạn duyệt" : "Awaiting your approval"
        case .yourMove: return lang == .vi ? "Lượt của bạn" : "Your move"
        case .done:     return lang == .vi ? "Xong" : "Done"
        }
    }
    var dot: Color {
        switch self {
        case .upNext:   return CodepetTheme.accentPurple
        case .awaiting: return CodepetTheme.accentGold
        case .yourMove: return CodepetTheme.accentBlue
        case .done:     return CodepetTheme.accentTeal
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Nhiệm vụ" : "Tasks").font(.pixelSystem(size: 22, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Việc \(companionName) đang làm, đang soạn, hoặc đang chờ bạn."
                                 : "What \(companionName) is doing, drafting, or waiting on you for.")
                    .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskColumn.allCases, id: \.self) { col in column(col) }
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tasks(in col: TaskColumn) -> [RoadmapTask] {
        companyStore.company.tasks.filter { TaskColumn.column(for: $0, in: companyStore.company.tasks) == col }
    }

    private func column(_ col: TaskColumn) -> some View {
        let items = tasks(in: col)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(col.dot).frame(width: 7, height: 7)
                Text(col.label(lang)).font(.pixelSystem(size: 11, weight: .semibold)).foregroundColor(CodepetTheme.bodyText)
                Text("\(items.count)").font(.pixelSystem(size: 10)).foregroundColor(CodepetTheme.mutedText)
            }
            if items.isEmpty {
                Text(lang == .vi ? "Trống" : "Nothing here")
                    .font(.pixelSystem(size: 11)).foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 20)
            } else {
                ForEach(items) { t in card(t) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(col.dot.opacity(0.06)))
    }

    private func card(_ t: RoadmapTask) -> some View {
        Button {
            if !t.done { Task { await companyStore.runTask(t, language: lang) } }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if let d = DepartmentCatalog.find(t.dept)?.name {
                    Text(d).font(.pixelSystem(size: 10, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                }
                Text(t.title).font(.pixelSystem(size: 12, weight: .medium)).foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.surface))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Verify it passes** — `xcodebuild … test` → `TaskColumn` tests pass; build succeeds.
- [ ] **Step 5: Controller commits**

---

## Task 8: Sidebar wiring + Department detail navigation

**Files:**
- Modify: `codepet/Views/Shell/AppShellView.swift`

- [ ] **Step 1: Wire the two views + a Company→Detail push**

In `AppShellView`, add state for the selected department and route `.company`/`.tasks` to the real views. Replace the content `Group` (lines ~27-39) with:

```swift
                Group {
                    if companyStore.view == .overview {
                        OverviewBoardView()
                    } else if companyStore.view == .company {
                        if let dept = selectedDept {
                            DepartmentDetailView(deptKey: dept, onBack: { selectedDept = nil })
                        } else {
                            CompanyView(onOpen: { selectedDept = $0 })
                        }
                    } else if companyStore.view == .tasks {
                        TasksView()
                    } else if companyStore.view == .library {
                        LibraryView()
                    } else if companyStore.view == .environment {
                        EnvironmentView()
                    } else if companyStore.view == .settings {
                        SettingsView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

Add the state property near the top of `AppShellView`:
```swift
    @State private var selectedDept: String?
```
And reset it when leaving Company — in the sidebar `Button { companyStore.select(v) }`, change to also clear the drill-in:
```swift
                Button { if v != .company { selectedDept = nil }; companyStore.select(v) } label: {
```
(So navigating away from Company and back returns to the department list, not a stale detail.)

- [ ] **Step 2: Build** — `xcodebuild … build` → BUILD SUCCEEDED.
- [ ] **Step 3: Controller commits**

---

## Task 9: End-to-end verification (manual — human checkpoint)

**Files:** none

The user drives the signed app; the controller reads CF logs.

- [ ] **Step 1: Signed build + launch** (team `YL72VTKBR7`, no `CODE_SIGNING_ALLOWED=NO`) or Xcode ⌘R.

- [ ] **Step 2: Verify the three views** (user confirms visually):
  - **Company** — 8 department rows with cover art, status pills, current-task lines, "N to do"/"Open"; "Eight departments · N need you today" header; "Re-plan for my stage" works.
  - **Department detail** — tapping a row opens the cover hero + rationale + companion focus line + "What needs doing · X of Y left" + task cards with the correct action buttons ("Have Codepet do it" etc.); back returns to the list.
  - **Tasks** — 4 columns (Up next / Awaiting your approval / Your move / Done) with the right tasks bucketed; "Nothing here" on empty; cards show dept + title.
  - Tasks are **dept-tagged** — regenerate the roadmap (Re-plan) so new tasks carry `dept`; confirm they distribute across departments (not all under one).

- [ ] **Step 3: CF logs** — `firebase functions:log --only generateRoadmap -n 10` shows a clean invocation on Re-plan (no error).

- [ ] **Step 4: Update memory + handoff** — record order 3 shipped (Company + Detail + Tasks on the 8-dept model, dept on RoadmapTask + generateRoadmap), the placeholders retired, and that `.roadmap` tab + typed viewers remain (order 4).

---

## Notes for the executor

- **Two repos:** Task 3 is the functions repo (`codepet-scaffoldfn-wt`); everything else is the native repo (`codepet-rebuild-wt`). Don't cross them.
- **Token-value fidelity:** if `CodepetTheme.surface`/`.hairline` names differ, substitute the actual token names used by the existing `LibraryView`/`EnvironmentView` (check `CodepetTheme.swift` first) — do NOT invent tokens.
- **`isGeneratingRoadmap`:** if absent on `CompanyStore`, add a `@Published var isGeneratingRoadmap = false` toggled around `generateRoadmap`'s body (Task 5).
- **Build after each task; the reviewer is the gate.** SwiftUI view fidelity is confirmed at the E2E (Task 9), so keep the copy/state/color values exactly as specified — that's where parity lives.
- **PRs:** feature branches; open the native + functions PRs after the E2E passes.
