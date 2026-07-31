# Part 1A — Structured Context Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a typed `CompanyContext` read-surface (Capability Bus Layer 1) that projects to today's grounding string byte-for-byte, and adds a **client-only** `project` slice that never leaves the machine.

**Architecture:** A pure Swift value type (`CompanyContext`) holds the eight context slices assembled from `CompanyState`. Its `groundingString` delegates to the existing `ChatContext.compose(...)` so the cloud wire payload is unchanged (additive refactor, no Cloud Function deploy). The `project` slice is deliberately excluded from `groundingString` and exposed only via a client-only `projectSummary`. Only the chat-send call site is routed through the new type in this plan; the run-task grounding is left untouched and migrates in a later plan.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild. No new dependencies.

## Global Constraints

- Native macOS SwiftUI app; scheme is `codepet` (lowercase); bundle `app.murror.codepet`.
- Tests use `XCTest` with `@testable import codepet` (matches `ChatLandingStateTests`).
- Follow the existing pure-model pattern (`ChatContext`, `RoadmapEngine`, `ChatLandingState`): SwiftUI-free, deterministic, unit-testable with no view.
- **No wire change.** `groundingString` MUST equal the pre-existing chat `ChatContext.compose(...)` output for identical inputs. This plan deploys no Cloud Function.
- **Client-only invariant (from the Part 1 spec, resolved Q3):** the `project` slice must never appear in `groundingString` or any string sent to the cloud.
- Build/test signing (from repo memory): TEAM-signed only — `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`.
- **Before `xcodebuild test`, close any running `codepet.app`** — a running instance holds the Firestore LevelDB LOCK and the test host aborts (the "Firebase test-host flake"; `** TEST FAILED **` with zero executed tests). Verify with `ps aux | grep codepet.app`.
- Concurrent-session protocol: this branch (`feat/chat-redesign`) may have a sibling session; rebase before any push, and this plan does not push.

---

## File Structure

- **Create** `codepet/Models/CompanyContext.swift` — the typed Layer-1 read-surface: eight slices + `groundingString` (cloud projection) + `projectSummary` (client-only). One responsibility: model + serialize the context. Sits beside `ChatContext.swift`, which it delegates to.
- **Create** `codepetTests/CompanyContextTests.swift` — parity, client-only invariant, and slice-population tests.
- **Modify** `codepet/Managers/CompanyStore.swift` (chat-send site, currently ~line 595) — build a `CompanyContext` and pass `.groundingString` instead of calling `ChatContext.compose` inline.

`ChatContext.swift` is unchanged — `CompanyContext` reuses it (DRY), preserving byte-parity.

---

## Task 1: `CompanyContext` typed model + grounding-string parity

**Files:**
- Create: `codepet/Models/CompanyContext.swift`
- Test: `codepetTests/CompanyContextTests.swift`

**Interfaces:**
- Consumes: `CompanyState` (fields `brief`, `tasks`, `decisions`, `library`, `enabledTools`, `companionId`), `CompanyBrief`, `RoadmapTask`, `DecisionEntry`, `Deliverable`, `Department`, `DepartmentSummary`, `DepartmentCatalog.summaries(tasks:)`, and `ChatContext.compose(brief:tasks:decisions:library:query:focusDepartment:)`.
- Produces:
  - `struct CompanyContext` with `init(company: CompanyState, query: String? = nil, focusDepartment: Department? = nil, project: ProjectSlice? = nil)`
  - `var groundingString: String` — cloud projection (byte-identical to the chat `ChatContext.compose` call)
  - `var projectSummary: String?` — client-only project rendering, nil when unlinked
  - `struct CompanyContext.ProjectSlice: Equatable` with `path: String, isGitRepo: Bool, hasClaudeMd: Bool, recentChangeSummary: String?`

- [ ] **Step 1: Write the failing parity test**

Create `codepetTests/CompanyContextTests.swift`:

```swift
import XCTest
@testable import codepet

final class CompanyContextTests: XCTestCase {

    private func fixtureCompany() -> CompanyState {
        var b = CompanyBrief()
        b.founderName = "Mona"
        b.projectName = "Acme"
        var c = CompanyState.empty
        c.brief = b
        c.tasks = [
            RoadmapTask(id: "t1", title: "Set up repo", detail: "", phase: .find, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you),
            RoadmapTask(id: "t3", title: "Write landing copy", detail: "", phase: .build, who: .you),
        ]
        return c
    }

    func test_groundingString_matchesChatContextCompose() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company, query: "landing page copy")
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: "landing page copy", focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)
    }

    func test_groundingString_matchesCompose_whenNoQuery() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: nil, focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

First close the app if running:

```bash
ps aux | grep -i codepet.app | grep -v grep
```

Run (from repo root):

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: FAIL — compile error "cannot find 'CompanyContext' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `codepet/Models/CompanyContext.swift`:

```swift
// codepet/Models/CompanyContext.swift
import Foundation

/// The typed, per-slice read-surface for the Capability Bus (Layer 1) — one source
/// of truth read by the companion, the department agents, and the coding agent.
/// The grounding `String` sent to the cloud is now one *projection* of this model
/// (`groundingString`); the `project` slice is CLIENT-ONLY and never appears in it.
///
/// See docs/superpowers/specs/2026-07-29-chat-system-integration-map-design.md
struct CompanyContext {

    /// Read-only, client-only view of the linked project. Populated by the coding
    /// agent (Part 2); nil when nothing is linked. NEVER serialized to the cloud —
    /// the user's code stays on their machine (Part 1 resolved Q3).
    struct ProjectSlice: Equatable {
        let path: String
        let isGitRepo: Bool
        let hasClaudeMd: Bool
        /// Optional short summary of recent local changes (filled by Part 2).
        let recentChangeSummary: String?
    }

    // MARK: Slices
    let brief: CompanyBrief
    let tasks: [RoadmapTask]
    let decisions: [DecisionEntry]
    let library: [Deliverable]
    let departments: [DepartmentSummary]
    let enabledTools: Set<String>
    let project: ProjectSlice?

    // MARK: Turn inputs that shape the cloud projection
    let query: String?
    let focusDepartment: Department?

    init(company: CompanyState,
         query: String? = nil,
         focusDepartment: Department? = nil,
         project: ProjectSlice? = nil) {
        self.brief = company.brief
        self.tasks = company.tasks
        self.decisions = company.decisions
        self.library = company.library
        self.departments = DepartmentCatalog.summaries(tasks: company.tasks)
        self.enabledTools = company.enabledTools
        self.project = project
        self.query = query
        self.focusDepartment = focusDepartment
    }

    /// Grounding string sent to the companyChat CF as `context`. Byte-identical to
    /// the pre-existing chat `ChatContext.compose(...)` call — a pure additive
    /// refactor with no wire change. Deliberately never references `project`.
    var groundingString: String {
        ChatContext.compose(brief: brief, tasks: tasks, decisions: decisions,
                            library: library, query: query, focusDepartment: focusDepartment)
    }

    /// Client-only rendering of the linked project for the LOCAL coding agent.
    /// nil when nothing is linked. This string must never be sent to the cloud.
    var projectSummary: String? {
        guard let p = project else { return nil }
        var parts = ["Linked project: \(p.path)",
                     "Git repo: \(p.isGitRepo ? "yes" : "no")",
                     "CLAUDE.md present: \(p.hasClaudeMd ? "yes" : "no")"]
        if let s = p.recentChangeSummary, !s.isEmpty { parts.append("Recent changes: \(s)") }
        return parts.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: PASS — 2 tests, `** TEST SUCCEEDED **`. If it shows 0 tests + `** TEST FAILED **`, the app was running (Firestore lock) — close it and re-run.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/CompanyContext.swift codepetTests/CompanyContextTests.swift
git commit -F - <<'EOF'
feat(context): typed CompanyContext read-surface (Bus Layer 1)

groundingString delegates to ChatContext.compose for byte-parity — no
wire change, no CF deploy. Adds the client-only project slice scaffold.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: Client-only `project` slice invariant

**Files:**
- Modify: `codepetTests/CompanyContextTests.swift` (add tests only — `CompanyContext.swift` already implements the behavior)

**Interfaces:**
- Consumes: `CompanyContext`, `CompanyContext.ProjectSlice` (from Task 1).
- Produces: no new production symbols — this task proves the client-only invariant with tests.

- [ ] **Step 1: Write the failing invariant tests**

Add to `codepetTests/CompanyContextTests.swift` (inside the class):

```swift
    func test_project_neverLeaksIntoGroundingString() {
        let company = fixtureCompany()
        let secretPath = "/Users/mona/secret-repo"
        let secretChange = "TOPSECRET_CHANGE_9f2a"
        let proj = CompanyContext.ProjectSlice(
            path: secretPath, isGitRepo: true, hasClaudeMd: true, recentChangeSummary: secretChange)
        let ctx = CompanyContext(company: company, query: "anything", project: proj)

        XCTAssertFalse(ctx.groundingString.contains(secretPath),
                       "project path must never reach the cloud grounding string")
        XCTAssertFalse(ctx.groundingString.contains(secretChange),
                       "project change summary must never reach the cloud grounding string")
    }

    func test_projectSummary_isNilWhenUnlinked_andRendersWhenLinked() {
        let company = fixtureCompany()
        XCTAssertNil(CompanyContext(company: company).projectSummary)

        let proj = CompanyContext.ProjectSlice(
            path: "/Users/mona/acme", isGitRepo: false, hasClaudeMd: false, recentChangeSummary: nil)
        let summary = CompanyContext(company: company, project: proj).projectSummary
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("/Users/mona/acme"))
        XCTAssertTrue(summary!.contains("Git repo: no"))
    }
```

- [ ] **Step 2: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: PASS — 4 tests total. (These pass immediately because Task 1 already excluded `project` from `groundingString`; the tests lock that invariant against regressions — the whole point of the client-only decision.)

- [ ] **Step 3: Commit**

```bash
git add codepetTests/CompanyContextTests.swift
git commit -F - <<'EOF'
test(context): lock the client-only project-slice invariant

project path/changes must never appear in the cloud grounding string;
projectSummary renders only client-side.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 3: Route the chat-send site through `CompanyContext`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (chat-send `CompanyChatRequest` build, currently ~line 595)

**Interfaces:**
- Consumes: `CompanyContext(company:query:focusDepartment:)` and `.groundingString` (Task 1). The existing local `department` variable at this scope is the composer's selected focus department (`Department?`).
- Produces: no new symbols — the request's `context` value is now sourced from `CompanyContext`. The wire payload is unchanged.

- [ ] **Step 1: Locate the exact current code**

Run:

```bash
grep -n "context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions,\|runnable: Array(runnable), envSetup: envSetup)" codepet/Managers/CompanyStore.swift
```

Expected: the chat-send `CompanyChatRequest(...)` block (around line 595) where `context:` calls `ChatContext.compose(... library: company.library, query: text, focusDepartment: department)`.

- [ ] **Step 2: Replace the inline compose with a `CompanyContext`**

In `codepet/Managers/CompanyStore.swift`, find the chat-send block:

```swift
        let req = CompanyChatRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions,
                                          library: company.library, query: text, focusDepartment: department),
            history: Array(history), userMessage: text, runnable: Array(runnable), envSetup: envSetup)
```

Replace it with:

```swift
        let companyContext = CompanyContext(company: company, query: text, focusDepartment: department)
        let req = CompanyChatRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: companyContext.groundingString,
            history: Array(history), userMessage: text, runnable: Array(runnable), envSetup: envSetup)
```

(Leave the `runRequest(for:...)` site near line 1032 untouched — it migrates in a later plan.)

- [ ] **Step 3: Run the full suite to verify no regression**

Close the app first (`ps aux | grep codepet.app`), then:

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyContextTests \
  -only-testing:codepetTests/CompanyStoreChatTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -40
```

Expected: PASS — `CompanyContextTests` (4) and `CompanyStoreChatTests` both green. Because `groundingString` is byte-identical to the previous inline call, the chat behavior is unchanged. (If `CompanyStoreChatTests` shows 0 executed + `** TEST FAILED **`, that's the Firestore host flake — close the app and re-run.)

- [ ] **Step 4: Verify the whole app still builds**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/CompanyStore.swift
git commit -F - <<'EOF'
refactor(chat): route chat-send grounding through CompanyContext

The chat turn now builds a typed CompanyContext and sends its
groundingString — byte-identical payload, no behavior change. run-task
grounding migrates in a later plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (Part 1 Layer 1):**
- "Replace the opaque `context: String` with one structured context object" → `CompanyContext` (Task 1). ✅ (Chat site routed; run-task site explicitly deferred and noted — not a gap, a scoped follow-on.)
- "Each feature contributes a slice" → eight slices modeled (brief, tasks, decisions, library, departments, enabledTools, project + turn inputs). ✅
- "The `project` slice is new and client-only" → `ProjectSlice` excluded from `groundingString`, exposed via `projectSummary`, locked by tests (Task 2). ✅
- "Keeps token cost controlled / no wire change" → `groundingString` delegates to `ChatContext.compose`, byte-parity asserted (Task 1). ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every command shows expected output. ✅

**3. Type consistency:** `CompanyContext`, `ProjectSlice`, `groundingString`, `projectSummary`, and `init(company:query:focusDepartment:project:)` are named identically across Tasks 1–3. The `ChatContext.compose(brief:tasks:decisions:library:query:focusDepartment:)` signature matches the real definition in `codepet/Models/ChatContext.swift`. ✅

**Deferred (not this plan):** migrating the run-task grounding site through `CompanyContext`; structured-JSON transport to the CF (Part 1 open Q1); consuming the typed slices in the lifecycle (Plan 1C). These belong to 1B/1C.
