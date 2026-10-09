# Department Notebook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each department remembers what it learned. Decisions carry the department that recorded them, and that department's desk shows its own notes.

**Architecture:** Add an optional `dept` to `DecisionEntry` and stamp it at the two writers that know a department. Raise the cap to 60. Render a department's notes on its desk (`ChatContext.composeDesk`) and leave them out of the general decisions block. Swift only: no backend or sidecar change.

**Tech Stack:** Swift 5 / SwiftUI / XCTest (Xcode 26.2), Firestore payload via `JSONEncoder`.

**Spec:** `docs/superpowers/specs/2026-10-09-department-notebook-design.md`

## Global Constraints

- Branch `feat/dept-notebook`, stacked on `feat/dept-ask-expertise` (PR #247). The desk is from #247.
- `dept` holds native department keys (`eng design mkt sales support fin ops legal`), nil = company-wide.
- Identity stays `scope|topic`. Do not add `dept` to `Decisions.identity`.
- `MAX_DECISIONS = 60`.
- Desk notes cap: 8, newest first, applicable-scope only, omitted entirely when memory is off.
- Run tests per suite with `-only-testing:` (landmine 3). Host restarts with zero failures are the known 26.2 deinit crash.

## Review Focus

1. A decision stored before this change (no `dept` key) must decode and re-encode byte-identically. Pinned in Task 1.
2. A note from another project must not appear on the desk, because the desk filters on the same `applicable` set as the decisions block. Pinned in Task 3.
3. A Finance note on topic "pricing" re-recorded by Sales moves to Sales and leaves Finance's desk. Pinned in Task 1 (merge) and Task 3 (desk).
4. An ordinary chat turn with no department records `dept == nil` and never inherits the previous turn's department. Pinned in Task 2.
5. With memory off, nothing from `decisions` reaches the context, desk included. Pinned in Task 3.

---

### Task 1: `DecisionEntry.dept`, merge stamping, cap 60

**Files:**
- Modify: `codepet/Models/Decisions.swift`
- Test: `codepetTests/DepartmentNotebookTests.swift` (create)

**Interfaces:**
- Produces: `DecisionEntry.dept: String?` (default nil, last stored property);
  `Decisions.mergeDecisions(existing:extracted:now:scope:dept:max:)` with `dept: String? = nil`;
  `Decisions.MAX_DECISIONS == 60`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import codepet

/// 9 Oct: decisions had no department, so Finance's runway was one line among thirty
/// company-wide facts and the desk could not tell which were Finance's.
final class DepartmentNotebookTests: XCTestCase {
    private func x(_ topic: String, _ s: String) -> ExtractedDecision { ExtractedDecision(topic: topic, statement: s, source: nil) }

    func testMergeStampsTheDepartment() {
        let m = Decisions.mergeDecisions(existing: [], extracted: [x("runway", "8 months")], now: 1, dept: "fin")
        XCTAssertEqual(m.first?.dept, "fin")
    }

    /// One truth per topic: Sales re-recording the price replaces Finance's and takes the tag.
    func testSameTopicFromAnotherDepartmentReplacesAndRetags() {
        let a = Decisions.mergeDecisions(existing: [], extracted: [x("pricing", "$19")], now: 1, dept: "fin")
        let b = Decisions.mergeDecisions(existing: a, extracted: [x("Pricing", "$29")], now: 2, dept: "sales")
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.statement, "$29")
        XCTAssertEqual(b.first?.dept, "sales")
    }

    func testNormalizeKeepsTheDepartment() {
        let e = DecisionEntry(topic: "runway", statement: "8 months", source: nil, updatedAt: 1, scope: nil, dept: "fin")
        XCTAssertEqual(Decisions.normalizeDecisions([e]).first?.dept, "fin")
    }

    func testCapIsSixty() {
        let many = (0..<70).map { x("t\($0)", "s") }
        XCTAssertEqual(Decisions.mergeDecisions(existing: [], extracted: many, now: 1).count, 60)
    }

    /// Stored before this field existed: decodes, and re-encodes without a `dept` key.
    func testAStoredDecisionWithoutDeptRoundTripsUnchanged() throws {
        let json = #"{"topic":"pricing","statement":"$19","updatedAt":1}"#
        let d = try JSONDecoder().decode(DecisionEntry.self, from: Data(json.utf8))
        XCTAssertNil(d.dept)
        let out = String(data: try JSONEncoder().encode(d), encoding: .utf8)!
        XCTAssertFalse(out.contains("dept"))
    }
}
```

- [ ] **Step 2: Run, expect a compile failure** (`dept` does not exist)

`xcodebuild test -project codepet.xcodeproj -scheme codepet -derivedDataPath build/DerivedData -only-testing:codepetTests/DepartmentNotebookTests`

- [ ] **Step 3: Implement** in `Decisions.swift`:
  - add `var dept: String? = nil` after `scope`, with a doc comment (who stamps it, nil = company-wide, identity deliberately excludes it);
  - `MAX_DECISIONS = 60`, with a comment explaining the change (8 departments share it; ~42 KB of 1 MiB);
  - `normalizeDecisions`: pass `dept: r.dept` into the rebuilt entry;
  - `mergeDecisions`: new parameter `dept: String? = nil` after `scope`, set on `fresh`.

- [ ] **Step 4: Run** `DepartmentNotebookTests`, `DecisionsTests`, `DecisionScopeTests`, `CompanyStoreForgetDecisionTests`. Expect all to pass.

- [ ] **Step 5: Commit** `Decisions carry the department that recorded them; cap 60`

### Task 2: Stamp the department at the writers

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`: `handleDoneAction` (~3370), `handleRemember` (~3608), its two callers (~2345, ~2384), `rememberFromApproval` (~4351)
- Test: `codepetTests/CompanyStoreChatTests.swift` (append next to `testDoneWithRememberMergesDecisionsAndAppendsNotedChip`)

**Interfaces:**
- Consumes: `mergeDecisions(..., dept:)` from Task 1.
- Produces: `handleDoneAction(_:cid:language:deptKey:)` and `handleRemember(_:cid:deptKey:)`, both `deptKey: String? = nil`.

- [ ] **Step 1: Write the failing tests**

```swift
    /// The turn's department is the one that noted the fact.
    func testRememberOnADepartmentTurnIsTaggedWithThatDepartment() async {
        let fact = RememberedFact(topic: "runway", statement: "8 months")
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["Noted"], remember: [fact]),
                             decisionsSaver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.sendChat("our runway is 8 months", language: .en, department: DepartmentCatalog.find("fin"))
        XCTAssertEqual(s.company.decisions.first { $0.topic == "runway" }?.dept, "fin")
    }

    /// An ordinary turn is company-wide, even straight after a department turn.
    func testRememberOnAnOrdinaryTurnIsUntagged() async {
        let fact = RememberedFact(topic: "goal", statement: "ten paying founders")
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["Noted"], remember: [fact]),
                             decisionsSaver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.sendChat("ten paying founders is the goal", language: .en)
        XCTAssertNil(s.company.decisions.first { $0.topic == "goal" }?.dept)
    }
```

The approval stamp is tested in `ApprovalParityTests` style. Build a store whose `company.tasks` holds a `dept: "fin"` task with a draft, inject `decisionExtractor: { _, _ in [ExtractedDecision(topic: "price", statement: "$19", source: nil)] }`, approve it through `approveTask`, wait for the fire-and-forget extraction the way the neighbouring tests do, then assert `decisions.first { $0.topic == "price" }?.dept == "fin"`.

- [ ] **Step 2: Run, expect failures** (dept is nil)
- [ ] **Step 3: Implement**
  - `handleRemember(_ facts:, cid:, deptKey: String? = nil)` passes `dept: deptKey` to `mergeDecisions`.
  - `handleDoneAction(..., deptKey: String? = nil)` forwards it. The two callers inside the chat-send path pass the `deptKey` already computed there (the one sent on the request). If a caller sits in a different function from where `deptKey` is computed, thread it through that function's parameters. Do not re-derive it.
  - `rememberFromApproval`: `let dept = deptKey(forSourceTaskId:)` already exists. Pass `dept: dept.isEmpty ? nil : dept` to `mergeDecisions`.
  - Room lock-in: unchanged (nil). Add a one-line comment saying why.
- [ ] **Step 4: Run** `CompanyStoreChatTests`, `ApprovalParityTests`, `CompanyStoreChatRunTests`, `VirtualCompanyDecisionTests`. Expect all to pass.
- [ ] **Step 5: Commit** `The department that learns a fact is the one that notes it`

### Task 3: The desk shows the department's notes

**Files:**
- Modify: `codepet/Models/ChatContext.swift` (`compose`, `composeDesk`)
- Test: `codepetTests/ChatContextDepartmentDeskTests.swift` (append)

**Interfaces:**
- Consumes: `DecisionEntry.dept`.
- Produces: `ChatContext.deskNotesCap = 8`; `composeDesk(_:brief:tasks:work:notes:)`.

- [ ] **Step 1: Write the failing tests**

```swift
    private func note(_ topic: String, _ s: String, dept: String?, at t: Double = 1) -> DecisionEntry {
        DecisionEntry(topic: topic, statement: s, source: nil, updatedAt: t, scope: nil, dept: dept)
    }

    func testTheDeskListsOnlyItsOwnNotesAndTheDecisionsBlockDoesNotRepeatThem() {
        let ds = [note("runway", "8 months", dept: "fin"), note("pitch", "one line", dept: "mkt"),
                  note("goal", "ten founders", dept: nil)]
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: ds, focusDepartment: finance)
        XCTAssertTrue(out.contains("Finance has noted:"))
        XCTAssertEqual(out.components(separatedBy: "8 months").count - 1, 1, "on the desk, not again below")
        XCTAssertTrue(out.contains("- goal: ten founders"), "company-wide stays in the decisions block")
        let desk = out.components(separatedBy: "Finance has noted:")[1].components(separatedBy: "\n\n")[0]
        XCTAssertFalse(desk.contains("one line"))
    }

    func testNotesAreNewestFirstAndCapped() {
        let ds = (0..<10).map { note("t\($0)", "s\($0)", dept: "fin", at: Double($0)) }
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: ds, focusDepartment: finance)
        XCTAssertTrue(out.contains("- t9: s9"))
        XCTAssertFalse(out.contains("- t1: s1"))
    }

    func testMemoryOffMeansNoNotes() {
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: [note("runway", "8 months", dept: "fin")],
                                      focusDepartment: finance, memoryEnabled: false)
        XCTAssertFalse(out.contains("8 months"))
        XCTAssertFalse(out.contains("has noted"))
    }
```

The cross-project case is covered by construction: the store passes `compose` the already-`applicable` decisions (`applicableDecisions`), and the desk reads only that parameter. Add a comment saying so at the read site rather than a test that cannot fail.

- [ ] **Step 2: Run, expect failures**
- [ ] **Step 3: Implement** in `compose`:
  - `let usable = memoryEnabled ? decisions : []`.
  - `notes` = usable entries with `dept == focusDepartment?.key`, sorted by `updatedAt` descending, prefix `deskNotesCap`.
  - Pass `notes` to `composeDesk`, which appends `"\(dep.name) has noted:"` plus `- topic: statement` lines when non-empty.
  - The decisions block composes `usable` minus those exact notes (by `Decisions.identity`).
  - Keep the existing `memoryEnabled ? … : ""` behaviour for the block.
- [ ] **Step 4: Run** all `ChatContext*` suites. Expect all to pass.
- [ ] **Step 5: Commit** `A department's desk shows what it has noted`

### Task 4: Memory panel names the department

**Files:**
- Modify: `codepet/Views/Settings/MemoryPanel.swift:85`

- [ ] **Step 1: Implement** `description: [fact.topic, DepartmentCatalog.find(fact.dept)?.name, scopeLabel(fact)].compactMap { $0 }.joined(separator: " · ")`. This is pure view code. `DepartmentCatalog.find` is already covered by `DepartmentCatalogTests`.
- [ ] **Step 2: Build**, then **commit** `Memory panel says which department noted a fact`

### Task 5: Verify in the app, open the PR

- [ ] Run `./scripts/build-sidecar.sh` (no functions change, but the bundle must exist), build Debug, launch.
- [ ] Pick Finance → "Our runway is 8 months." Confirm the Noted chip appears.
- [ ] Start a new chat → "Ask Finance: how long is our runway?" Expect it to say 8 months, from the desk.
- [ ] Settings → Memory: the runway row reads `runway · Finance · …`.
- [ ] Push `feat/dept-notebook` and open a PR with base `feat/dept-ask-expertise`, or `main` if #247 has merged.
