# Native Decisions-Memory Client — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Approve a deliverable → byte extracts durable decisions (live `extractDecisions` CF) → merge + persist to `companies/{uid}.decisions` → ground future chat + run-task generations.

**Architecture:** Port the decisions model + merge/normalize/compose from web (pure, unit-tested). Persist `decisions` on the company doc (Codable, mirrors `tasks`). A new `DecisionsClient` calls the deployed CF. On approve, a fire-and-forget `rememberFromApproval` extracts→merges→persists. Grounding is injected via `ChatContext.compose` (used by BOTH chat and run-task), so no generation-CF change.

**Tech Stack:** Swift, SwiftUI, XCTest. Build: `xcodebuild` scheme `codepet`.

## Global Constraints

- Branch `fix`… actually `feat/decisions-client` (off `origin/main`, which has onboarding + run-approve merged). Work in `~/Documents/Murror/codepet`.
- `decisions` persists via `CompanyState`/`CompanyDoc` Codable (mirror `tasks`); `DecisionEntry` fields are JSON-safe (`updatedAt` = epoch millis `Double?`).
- Fire-and-forget on approve: extraction/merge/persist MUST NOT block or gate the approval; fail-open (a failed extract leaves decisions unchanged).
- Grounding lives in `ChatContext.compose` — one change covers chat (`sendChat`) and run-task (`runRequest`).
- Chat-side draft path stays behaviorally intact aside from the added fire-and-forget call in `approveDraft`.
- **Xcode 26.2 test caveat:** struct-only tests (`Decisions`, `CompanyData` payload) run clean; `CompanyStore` (@MainActor) tests may crash the host on teardown (toolchain bug, NOT code) — verify via assertion-green + `xcodebuild build … CODE_SIGNING_ALLOWED=NO`.
- Build/verify: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` (foreground).

---

### Task 1: `Decisions.swift` — model + pure logic

**Files:**
- Create: `codepet/Models/Decisions.swift`
- Test: `codepetTests/DecisionsTests.swift`

**Interfaces:**
- Produces: `DecisionEntry`, `ExtractedDecision`, `Decisions.{MAX_DECISIONS, normalizeDecisions, mergeDecisions, composeDecisions}`. Consumed by Tasks 2–5.

- [ ] **Step 1: Create `codepet/Models/Decisions.swift`**

```swift
// codepet/Models/Decisions.swift
import Foundation

/// One durable decision the company has locked in (pricing, positioning, naming…),
/// keyed by `topic` so a newer decision supersedes the old. Ported from the web
/// lib/ai/projectModel.ts (DecisionEntry) + lib/ai/decisions.ts (merge). JSON-safe
/// (`updatedAt` = epoch millis) so it round-trips in companies/{uid}.decisions.
struct DecisionEntry: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
    var updatedAt: Double?   // epoch milliseconds
}

/// A decision as returned by the extractDecisions CF (no timestamp yet).
struct ExtractedDecision: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
}

enum Decisions {
    static let MAX_DECISIONS = 30

    private static func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func key(_ topic: String) -> String { t(topic).lowercased() }
    private static func cleanSource(_ s: String?) -> String? {
        let v = t(s ?? "")
        return v.isEmpty ? nil : v
    }

    /// Sanitize + cap (keep most-recently-updated; nil updatedAt sorts oldest).
    static func normalizeDecisions(_ raw: [DecisionEntry], max: Int = MAX_DECISIONS) -> [DecisionEntry] {
        var entries: [DecisionEntry] = []
        for r in raw {
            let topic = t(r.topic), statement = t(r.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            entries.append(DecisionEntry(topic: topic, statement: statement, source: cleanSource(r.source), updatedAt: r.updatedAt))
        }
        if entries.count <= max { return entries }
        return Array(entries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(max))
    }

    /// Merge extracted into existing, keyed by lowercased topic: an extraction on the same
    /// topic supersedes the old one and stamps updatedAt=now; untouched topics preserved
    /// (in original order, updates in place, new topics appended). Over cap → keep most-recent.
    static func mergeDecisions(existing: [DecisionEntry], extracted: [ExtractedDecision],
                               now: Double, max: Int = MAX_DECISIONS) -> [DecisionEntry] {
        var order: [String] = []
        var byTopic: [String: DecisionEntry] = [:]
        for d in existing {
            let topic = t(d.topic), statement = t(d.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let k = key(topic)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = d
        }
        for e in extracted {
            let topic = t(e.topic), statement = t(e.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let k = key(topic)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = DecisionEntry(topic: topic, statement: statement, source: cleanSource(e.source), updatedAt: now)
        }
        let merged = order.compactMap { byTopic[$0] }
        if merged.count <= max { return merged }
        return Array(merged.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(max))
    }

    /// Render locked-in decisions as a grounding block. "" when none. Verbatim from web composeDecisions.
    static func composeDecisions(_ decisions: [DecisionEntry]) -> String {
        if decisions.isEmpty { return "" }
        let lines = decisions.map { "- \($0.topic): \($0.statement)" }.joined(separator: "\n")
        return "Decisions the founder has locked in — honor these; never contradict or silently re-open them:\n"
            + lines
            + "\nIf the current work genuinely conflicts with one, do NOT quietly override it and do NOT ignore the conflict: stay consistent with the decision, and add one short, clearly-marked note flagging the tension so the founder can decide (e.g. \"Note: this holds to your decision that <…>; tell me if you want to revisit it\")."
    }
}
```

- [ ] **Step 2: Write the tests**

Create `codepetTests/DecisionsTests.swift`:

```swift
import XCTest
@testable import codepet

final class DecisionsTests: XCTestCase {
    func testMergeSupersedesSameTopicCaseInsensitiveAndStamps() {
        let existing = [DecisionEntry(topic: "Pricing", statement: "old", source: nil, updatedAt: 1)]
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "pricing", statement: "Plus is $4/mo", source: "Pricing page")],
            now: 1000)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].statement, "Plus is $4/mo")
        XCTAssertEqual(out[0].updatedAt, 1000)
        XCTAssertEqual(out[0].source, "Pricing page")
    }
    func testMergePreservesUntouchedAndAppendsNew() {
        let existing = [DecisionEntry(topic: "naming", statement: "Codepet", source: nil, updatedAt: 1)]
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "tech", statement: "SwiftUI", source: nil)], now: 2)
        XCTAssertEqual(out.map { $0.topic }, ["naming", "tech"])
    }
    func testMergeDropsEmptyAndCapsKeepingRecent() {
        let existing = (0..<30).map { DecisionEntry(topic: "t\($0)", statement: "s", source: nil, updatedAt: Double($0)) }
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "", statement: "x", source: nil),
                        ExtractedDecision(topic: "new", statement: "recent", source: nil)], now: 999)
        XCTAssertEqual(out.count, 30)
        XCTAssertTrue(out.contains { $0.topic == "new" })   // newest kept
        XCTAssertFalse(out.contains { $0.topic == "t0" })   // oldest evicted
    }
    func testNormalizeDropsEmptyTrimsCaps() {
        let raw = [DecisionEntry(topic: " a ", statement: " b ", source: " ", updatedAt: nil),
                   DecisionEntry(topic: "", statement: "x", source: nil, updatedAt: nil)]
        let out = Decisions.normalizeDecisions(raw)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].topic, "a"); XCTAssertEqual(out[0].statement, "b"); XCTAssertNil(out[0].source)
    }
    func testComposeEmptyAndNonEmpty() {
        XCTAssertEqual(Decisions.composeDecisions([]), "")
        let s = Decisions.composeDecisions([DecisionEntry(topic: "pricing", statement: "$4/mo", source: nil, updatedAt: nil)])
        XCTAssertTrue(s.contains("honor these"))
        XCTAssertTrue(s.contains("- pricing: $4/mo"))
    }
}
```

- [ ] **Step 3: Run tests → pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DecisionsTests`
Expected: PASS (struct/enum-only → runs clean under Xcode 26.2).

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/Decisions.swift codepetTests/DecisionsTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: DecisionEntry + merge/normalize/compose (ported)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Persist `decisions` on the company doc

**Files:**
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataTests.swift` (or a sibling — read it first)

**Interfaces:**
- Consumes: `DecisionEntry`, `Decisions.normalizeDecisions` (Task 1).
- Produces: `CompanyState.decisions`; `CompanyData.saveDecisions(companyId:decisions:)` + `decisionsPayload`.

- [ ] **Step 1: Add `decisions` to `CompanyState`**

In `codepet/Models/CompanyState.swift`, add the stored property (after `enabledTools`) and to the init (new last parameter, default `[]`, assigned), and to `.empty` (leave default):

```swift
    var enabledTools: Set<String>
    var decisions: [DecisionEntry]
```
init: add `decisions: [DecisionEntry] = []` as the last parameter and `self.decisions = decisions`.

- [ ] **Step 2: Add `decisions` to `CompanyDoc` + `state(from:)` + payload/save in `CompanyData.swift`**

- In `struct CompanyDoc`, add: `var decisions: [DecisionEntry]?`
- In `state(from:)`, add to the `CompanyState(...)` call: `decisions: Decisions.normalizeDecisions(doc.decisions ?? [])`
- Add, mirroring `tasksPayload`/`saveTasks`:

```swift
    /// Pure Firestore payload for a decisions write — testable without Firestore.
    static func decisionsPayload(_ decisions: [DecisionEntry]) -> [String: Any] {
        if let data = try? JSONEncoder().encode(decisions),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["decisions": arr]
        }
        return ["decisions": []]
    }

    /// Write companies/{uid}.decisions, merge. Fail-soft: false on error.
    static func saveDecisions(companyId: String, decisions: [DecisionEntry]) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(decisionsPayload(decisions), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 3: Test the round-trip**

Read `codepetTests/CompanyDataTests.swift` for its style, then add:

```swift
func testDecisionsPayloadEncodesAndDocDecodes() throws {
    let decisions = [DecisionEntry(topic: "pricing", statement: "$4/mo", source: "Pricing", updatedAt: 5)]
    let payload = CompanyData.decisionsPayload(decisions)
    let arr = payload["decisions"] as? [[String: Any]]
    XCTAssertEqual(arr?.count, 1)
    XCTAssertEqual(arr?.first?["topic"] as? String, "pricing")
}
func testStateFromDocNormalizesDecisions() {
    let doc = CompanyDoc(decisions: [DecisionEntry(topic: " ", statement: "x", source: nil, updatedAt: nil),
                                     DecisionEntry(topic: "tech", statement: "SwiftUI", source: nil, updatedAt: nil)])
    XCTAssertEqual(CompanyData.state(from: doc).decisions.map { $0.topic }, ["tech"])
}
```
(If `CompanyDoc`'s memberwise init requires all fields, construct it with the other fields nil — read the struct.)

- [ ] **Step 4: Run tests → pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataTests`
Expected: PASS (struct-level).

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepetTests/CompanyDataTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: persist decisions on companies/{uid} (mirror tasks)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `DecisionsClient` — call the live `extractDecisions` CF

**Files:**
- Create: `codepet/Services/DecisionsClient.swift`

**Interfaces:**
- Consumes: `DecisionEntry`, `ExtractedDecision` (Task 1).
- Produces: `struct ApprovedDeliverableDTO`; `DecisionsClient.extract(_:existing:) async -> [ExtractedDecision]`.

- [ ] **Step 1: Create `codepet/Services/DecisionsClient.swift`**

Mirror `CompanyData.fetchRoadmap` (auth token via `Auth.auth().currentUser?.getIDToken()`, POST, fail-open `[]`):

```swift
// codepet/Services/DecisionsClient.swift
import Foundation
import FirebaseAuth

/// The approved deliverable's high-signal fields sent to extractDecisions.
struct ApprovedDeliverableDTO: Encodable {
    let title: String
    let dept: String
    let type: String
    let out: String
}

/// Calls the stateless `extractDecisions` Cloud Function. FAIL-OPEN: any error → [].
/// The caller (CompanyStore.rememberFromApproval) does the merge + persist.
enum DecisionsClient {
    private static let endpoint =
        URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/extractDecisions")!

    private struct DecisionOnRecord: Encodable { let topic: String; let statement: String }
    private struct Request: Encodable { let deliverable: ApprovedDeliverableDTO; let existing_decisions: [DecisionOnRecord] }
    private struct Response: Decodable { let decisions: [ExtractedDecision] }

    static func extract(_ deliverable: ApprovedDeliverableDTO, existing: [DecisionEntry]) async -> [ExtractedDecision] {
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return [] }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let onRecord = existing.map { DecisionOnRecord(topic: $0.topic, statement: $0.statement) }
        guard let body = try? JSONEncoder().encode(Request(deliverable: deliverable, existing_decisions: onRecord)) else { return [] }
        req.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }
        return decoded.decisions
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **` (no unit test — networking client, verified by the store tests via a stubbed extractor in Task 4).

- [ ] **Step 3: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Services/DecisionsClient.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: DecisionsClient — call live extractDecisions CF (fail-open)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Store wiring — extract + merge + persist on approve

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreRunTaskTests.swift` (approve tests live here)

**Interfaces:**
- Consumes: Task 1 (`Decisions`, `ExtractedDecision`), Task 2 (`saveDecisions`), Task 3 (`ApprovedDeliverableDTO`, `DecisionsClient.extract`).
- Produces: injected `decisionsSaver` + `decisionExtractor`; `rememberFromApproval`; approve paths fire it.

- [ ] **Step 1: Inject the two closures**

In `CompanyStore`, add stored properties (after `enricher`):
```swift
    private let decisionsSaver: (String, [DecisionEntry]) async -> Bool
    private let decisionExtractor: (ApprovedDeliverableDTO, [DecisionEntry]) async -> [ExtractedDecision]
```
Add init parameters (after `enricher:`), with defaults, and assign in the body:
```swift
         decisionsSaver: @escaping (String, [DecisionEntry]) async -> Bool = CompanyData.saveDecisions,
         decisionExtractor: @escaping (ApprovedDeliverableDTO, [DecisionEntry]) async -> [ExtractedDecision] = DecisionsClient.extract) {
```
```swift
        self.decisionsSaver = decisionsSaver
        self.decisionExtractor = decisionExtractor
```

- [ ] **Step 2: Add `rememberFromApproval`**

Add to `CompanyStore` (near `approveTask`):
```swift
    /// Fire-and-forget after an approval: extract durable decisions the deliverable locks
    /// in, merge into memory, persist. Account-guarded + fail-open — a failed extract leaves
    /// decisions unchanged; the approval already happened. `dept` comes from the source task.
    private func rememberFromApproval(_ deliverable: Deliverable) async {
        let cid = companyId
        let dept = company.tasks.first { $0.id == deliverable.sourceTaskId }?.dept ?? ""
        let dto = ApprovedDeliverableDTO(title: deliverable.title, dept: dept,
                                         type: deliverable.kind.rawValue, out: deliverable.body)
        let extracted = await decisionExtractor(dto, company.decisions)
        guard companyId == cid, !extracted.isEmpty else { return }
        let now = Date().timeIntervalSince1970 * 1000
        company.decisions = Decisions.mergeDecisions(existing: company.decisions, extracted: extracted, now: now)
        if let cid { _ = await decisionsSaver(cid, company.decisions) }
    }
```

- [ ] **Step 3: Fire it from both approve paths**

In `approveTask(id:)` — after the existing library append + saves, before returning, add (capture the draft before it's cleared):
```swift
        let approved = draft
        // ... existing done/drafted/draft=nil + saves ...
        Task { await rememberFromApproval(approved) }
```
(Place the `Task { … }` at the end of the function; `approved` is the `draft` local already bound by the guard.)

In `approveDraft(messageId:)` — after `company.library.append(draft)` + save, add:
```swift
        Task { await rememberFromApproval(draft) }
```

- [ ] **Step 4: Tests**

Add to `codepetTests/CompanyStoreRunTaskTests.swift`:
```swift
func testApproveExtractsMergesAndPersistsDecisions() async {
    var savedDecisions: [DecisionEntry]?
    let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                              drafted: true, draft: Deliverable(kind: .doc, title: "Pricing", body: "Plus $4/mo", sourceTaskId: "t1"))
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: [drafted])
    let s = CompanyStore(loader: { _ in seed },
                         decisionsSaver: { _, d in savedDecisions = d; return true },
                         decisionExtractor: { _, _ in [ExtractedDecision(topic: "pricing", statement: "Plus $4/mo", source: "Pricing")] })
    await s.hydrate(companyId: "u")
    await s.approveTask(id: "t1")
    // fire-and-forget Task — allow it to run
    await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(s.company.decisions.first?.topic, "pricing")
    XCTAssertEqual(savedDecisions?.first?.statement, "Plus $4/mo")
}
func testApproveFailOpenWhenExtractorReturnsEmpty() async {
    let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                              drafted: true, draft: Deliverable(kind: .doc, title: "X", body: "y", sourceTaskId: "t1"))
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: [drafted])
    let s = CompanyStore(loader: { _ in seed }, decisionExtractor: { _, _ in [] })
    await s.hydrate(companyId: "u")
    await s.approveTask(id: "t1")
    await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(s.company.decisions.isEmpty)   // nothing extracted → unchanged
    XCTAssertTrue(s.company.tasks[0].done)        // approval still completed
}
```
(The `Task.sleep` lets the fire-and-forget task finish; adjust if the suite has a helper for awaiting spawned tasks. If flaky, keep it — the assertion after the sleep is the signal.)

- [ ] **Step 5: Run tests + build**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreRunTaskTests`
Expected: new tests' assertions green (Xcode 26.2: verify assertion-green + `xcodebuild build …` succeeds).

- [ ] **Step 6: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreRunTaskTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: extract+merge+persist decisions fire-and-forget on approve

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Ground chat + run-task on decisions

**Files:**
- Modify: `codepet/Models/ChatContext.swift`, `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/` (a `ChatContext` test — struct-only)

**Interfaces:**
- Consumes: `Decisions.composeDecisions` (Task 1); `company.decisions`.

- [ ] **Step 1: Add a `decisions` parameter to `ChatContext.compose`**

In `codepet/Models/ChatContext.swift`, change the signature and append the decisions block:
```swift
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask], decisions: [DecisionEntry] = []) -> String {
        var parts: [String] = []
        parts.append(BriefContext.compose(brief) ?? "No brief yet.")
        let d = Decisions.composeDecisions(decisions)
        if !d.isEmpty { parts.append(d) }
        parts.append("Roadmap progress: \(RoadmapEngine.progressPercent(tasks))%.")
        // ... rest unchanged ...
```
(Insert the decisions block right after the brief line; keep the rest of the function unchanged.)

- [ ] **Step 2: Pass `company.decisions` at both call sites**

In `codepet/Managers/CompanyStore.swift`, update BOTH `ChatContext.compose(brief: company.brief, tasks: company.tasks)` call sites (in `sendChat` and in `runRequest`) to:
```swift
ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions)
```

- [ ] **Step 3: Test the grounding**

Add a struct-only test (e.g. in a new `codepetTests/ChatContextDecisionsTests.swift`):
```swift
import XCTest
@testable import codepet
final class ChatContextDecisionsTests: XCTestCase {
    func testComposeIncludesDecisionsBlockWhenPresent() {
        let s = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [],
                                    decisions: [DecisionEntry(topic: "pricing", statement: "$4/mo", source: nil, updatedAt: nil)])
        XCTAssertTrue(s.contains("- pricing: $4/mo"))
        XCTAssertTrue(s.contains("honor these"))
    }
    func testComposeOmitsDecisionsWhenEmpty() {
        let s = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [])
        XCTAssertFalse(s.contains("honor these"))
    }
}
```

- [ ] **Step 4: Run tests + build**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ChatContextDecisionsTests`
then `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: tests pass (struct-only) + BUILD SUCCEEDED (confirms both call sites compile).

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/ChatContext.swift codepet/Managers/CompanyStore.swift codepetTests/ChatContextDecisionsTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: ground chat + run-task on locked-in decisions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** model+pure logic → T1; persistence → T2; client → T3; extract/merge/persist on approve → T4; grounding injection (chat+run-task via ChatContext) → T5. ✓
**Placeholder scan:** full code for pure logic/persistence/client/wiring; test-construction notes point to reading sibling init shapes (real risk, not placeholder). ✓
**Type consistency:** `DecisionEntry`/`ExtractedDecision` (T1) used in T2 (persist), T3 (client), T4 (merge). `ApprovedDeliverableDTO`/`DecisionsClient.extract` (T3) consumed in T4. `Decisions.composeDecisions` (T1) in T5. `decisionsSaver`/`decisionExtractor` defined+injected in T4. ✓
**No CF change:** grounding rides `ChatContext.compose` (context string both CFs already accept). ✓
