# Phase 6B — Deliverable Generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a `codepetCanDo` roadmap task → produce a `Deliverable` → append to the Library + persist. Native-only + fail-open (the `runTask` Cloud Function ships separately). Task left as-is on success.

**Architecture:** A Run affordance on `TaskCardView` calls `CompanyStore.runTask`, which grounds a request (`ChatContext.compose`), calls an injectable fail-open `RunTaskClient.run`, and — on a valid result — builds a `Deliverable` honoring the 6A gates (unique UUID id, canonical `ISOTime.utc` timestamp, required title+body) and persists it via `CompanyData.saveLibrary`. Failures surface one honest `runError`.

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `Deliverable`/`DeliverableKind` (6A), `RoadmapTask`/`RoadmapEngine`/`TaskCardView`/`OverviewBoardView` (3B), `ChatContext.compose` (5), `CompanyStore`/`CompanyData`, CodepetTheme. Spec: `docs/superpowers/specs/2026-07-21-phase6b-deliverable-generation-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **6A gates (MUST honor in `runTask`):** deliverable `id` = fresh `UUID().uuidString` (**unique**); `createdAt` = `ISOTime.utc(Date())` (**one canonical UTC ISO-8601**); `title` non-empty (fall back to `task.title`) and `body` non-empty (**required-fields guard** — never append a malformed deliverable).
- **Decisions:** native-only FAIL-OPEN (client nil → honest `runError`, never throw/block); task LEFT AS-IS on success; Run only on `status == .codepetCanDo`; APPEND each run (no dedup); account-switch guarded via `companyId`. Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Create `codepet/Models/ISOTime.swift` (Task 1)
- Create `codepet/Services/RunTaskClient.swift` (Task 2)
- Modify `codepet/Services/CompanyData.swift` (Task 3: `deliverablesPayload` + `saveLibrary`)
- Modify `codepet/Managers/CompanyStore.swift` (Task 4: `runningTaskIds`/`runError` + `runTask`)
- Modify `codepet/Views/Overview/TaskCardView.swift` + `codepet/Views/Overview/OverviewBoardView.swift` (Task 5)
- Tests: `codepetTests/{ISOTimeTests, RunTaskClientTests, CompanyDataDeliverablesTests, CompanyStoreRunTaskTests}.swift`

---

### Task 1: `ISOTime.utc`

**Files:**
- Create: `codepet/Models/ISOTime.swift`
- Test: `codepetTests/ISOTimeTests.swift`

**Interfaces:**
- Produces: `enum ISOTime { static func utc(_ date: Date) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ISOTimeTests.swift
import XCTest
@testable import codepet

final class ISOTimeTests: XCTestCase {
    func testUtcCanonicalFormat() {
        XCTAssertEqual(ISOTime.utc(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        // Ends in Z (UTC), no fractional seconds → lexicographic == chronological.
        let s = ISOTime.utc(Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertTrue(s.hasSuffix("Z"))
        XCTAssertFalse(s.contains("."))
    }
    func testLexicographicOrderMatchesTime() {
        let earlier = ISOTime.utc(Date(timeIntervalSince1970: 1000))
        let later = ISOTime.utc(Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(later > earlier)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ISOTimeTests 2>&1 | tail -20`
Expected: FAIL — no `ISOTime`.

- [ ] **Step 3: Write `ISOTime.swift`**

```swift
// codepet/Models/ISOTime.swift
import Foundation

/// One canonical UTC ISO-8601 timestamp for stored records. Default
/// `ISO8601DateFormatter` options = UTC `Z`, no fractional seconds — so
/// lexicographic string order equals chronological order (the Library sort relies
/// on this). Use for every `Deliverable.createdAt`.
enum ISOTime {
    private static let formatter = ISO8601DateFormatter()

    static func utc(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/ISOTime.swift codepetTests/ISOTimeTests.swift
# commit (fsmonitor-off form): "feat(library): ISOTime.utc — canonical UTC ISO-8601 timestamp"
```

---

### Task 2: `RunTaskClient` (DTOs + fail-open run)

**Files:**
- Create: `codepet/Services/RunTaskClient.swift`
- Test: `codepetTests/RunTaskClientTests.swift`

**Interfaces:**
- Produces: `struct RunTaskRequest: Codable` (companyId?/language/companionId/context/taskId/taskTitle/taskDetail, snake_case); `struct RunTaskResponse: Codable` (kind/title/body); `enum RunTaskClient { static func run(_:) async -> RunTaskResponse? }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RunTaskClientTests.swift
import XCTest
@testable import codepet

final class RunTaskClientTests: XCTestCase {
    func testRequestEncodesSnakeCaseAndRoundTrips() throws {
        let req = RunTaskRequest(companyId: "u1", language: "en", companionId: "byte",
                                 context: "ctx", taskId: "t1", taskTitle: "Survey", taskDetail: "willingness to pay")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["company_id"] as? String, "u1")
        XCTAssertEqual(json?["companion_id"] as? String, "byte")
        XCTAssertEqual(json?["task_id"] as? String, "t1")
        XCTAssertEqual(json?["task_title"] as? String, "Survey")
        XCTAssertEqual(json?["task_detail"] as? String, "willingness to pay")
        let back = try JSONDecoder().decode(RunTaskRequest.self, from: data)
        XCTAssertEqual(back.taskId, "t1")
    }
    func testResponseDecodes() throws {
        let data = "{\"kind\":\"doc\",\"title\":\"Scope\",\"body\":\"# Hi\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: data)
        XCTAssertEqual(r.kind, "doc")
        XCTAssertEqual(r.title, "Scope")
        XCTAssertEqual(r.body, "# Hi")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RunTaskClientTests 2>&1 | tail -20`
Expected: FAIL — no `RunTaskRequest`/`RunTaskClient`.

- [ ] **Step 3: Write `RunTaskClient.swift`**

```swift
// codepet/Services/RunTaskClient.swift
import Foundation

/// Request body for the runTask Cloud Function.
struct RunTaskRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let taskId: String
    let taskTitle: String
    let taskDetail: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case taskId = "task_id"
        case taskTitle = "task_title"
        case taskDetail = "task_detail"
    }
}

/// Response body from the runTask Cloud Function — a deliverable as kind + markdown.
struct RunTaskResponse: Codable {
    let kind: String
    let title: String
    let body: String
}

/// Fail-open client for the (planned) runTask Cloud Function. Returns the decoded
/// response on 200, `nil` on any error / non-200 / unreachable — callers never handle
/// throws. The CF is authored + deployed separately (node-22 bundle, like companyChat);
/// until then this returns nil and the run surfaces an honest error.
enum RunTaskClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!

    static func run(_ req: RunTaskRequest) async -> RunTaskResponse? {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RunTaskResponse.self, from: data)
        else { return nil }
        return decoded
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Services/RunTaskClient.swift codepetTests/RunTaskClientTests.swift
# commit (fsmonitor-off form): "feat(library): RunTaskClient DTOs + fail-open run (runTask CF)"
```

---

### Task 3: `CompanyData.deliverablesPayload` + `saveLibrary`

**Files:**
- Modify: `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataDeliverablesTests.swift`

**Interfaces:**
- Consumes: `Deliverable` (6A).
- Produces: `CompanyData.deliverablesPayload(_:) -> [String: Any]`; `CompanyData.saveLibrary(companyId:library:) async -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyDataDeliverablesTests.swift
import XCTest
@testable import codepet

final class CompanyDataDeliverablesTests: XCTestCase {
    func testDeliverablesPayloadShape() {
        let d = Deliverable(id: "d1", kind: .plan, title: "Plan", body: "# x",
                            createdAt: "2026-07-21T00:00:00Z", sourceTaskId: "t1")
        let payload = CompanyData.deliverablesPayload([d])
        let arr = payload["library"] as? [[String: Any]]
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["id"] as? String, "d1")
        XCTAssertEqual(arr?.first?["kind"] as? String, "plan")
        XCTAssertEqual(arr?.first?["title"] as? String, "Plan")
        XCTAssertEqual(arr?.first?["source_task_id"] as? String ?? arr?.first?["sourceTaskId"] as? String, "t1")
    }
    func testEmptyLibraryPayload() {
        let payload = CompanyData.deliverablesPayload([])
        XCTAssertEqual((payload["library"] as? [[String: Any]])?.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataDeliverablesTests 2>&1 | tail -20`
Expected: FAIL — no `deliverablesPayload`.

- [ ] **Step 3: Add the payload builder + write to `CompanyData.swift`**

Add inside `enum CompanyData` (next to `tasksPayload`/`saveTasks`):

```swift
    /// Pure Firestore payload for a library write — testable without Firestore.
    static func deliverablesPayload(_ library: [Deliverable]) -> [String: Any] {
        if let data = try? JSONEncoder().encode(library),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["library": arr]
        }
        return ["library": []]
    }

    /// Write companies/{uid}.library, merge. Fail-soft: false on error.
    static func saveLibrary(companyId: String, library: [Deliverable]) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(deliverablesPayload(library), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests). (`Deliverable`'s `sourceTaskId` encodes as `sourceTaskId` — the test accepts either key form.)

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Services/CompanyData.swift codepetTests/CompanyDataDeliverablesTests.swift
# commit (fsmonitor-off form): "feat(library): CompanyData deliverablesPayload + saveLibrary (fail-soft)"
```

---

### Task 4: `CompanyStore.runTask`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreRunTaskTests.swift`

**Interfaces:**
- Consumes: `RunTaskRequest`/`RunTaskResponse`/`RunTaskClient.run` (Task 2), `ISOTime.utc` (Task 1), `CompanyData.saveLibrary` (Task 3), `ChatContext.compose` (5), `Deliverable`/`DeliverableKind` (6A), `RoadmapTask`.
- Produces: `CompanyStore.runningTaskIds: Set<String>`; `.runError: String?`; `func runTask(_ task: RoadmapTask, language: AppLanguage) async`; injectable `taskRunner`/`librarySaver`; `reset()` clears both.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreRunTaskTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRunTaskTests: XCTestCase {
    private func task(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "Survey users", detail: "wtp", phase: .find, who: .does)
    }
    private func store(_ runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     taskRunner: runner, librarySaver: saver)
    }

    func testRunProducesDeliverableAndPersists() async {
        var saved: [Deliverable] = []
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "WTP Survey", body: "# Q1") },
                      saver: { _, lib in saved = lib; return true })
        await s.hydrate(companyId: "u")
        let t = task()
        await s.runTask(t, language: .en)
        XCTAssertEqual(s.company.library.count, 1)
        let d = s.company.library[0]
        XCTAssertEqual(d.kind, .doc)
        XCTAssertEqual(d.title, "WTP Survey")
        XCTAssertEqual(d.sourceTaskId, "t1")
        XCTAssertFalse(d.id.isEmpty)                    // unique id
        XCTAssertTrue(d.createdAt?.hasSuffix("Z") ?? false)  // canonical UTC
        XCTAssertEqual(saved.count, 1)                  // persisted
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
        XCTAssertFalse(s.company.tasks.contains { $0.id == "t1" && $0.done })  // task unchanged
    }
    func testEmptyBodyFailsOpenNoDeliverable() async {
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "x", body: "   ") })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testNilResultFailsOpen() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
    }
    func testTitleFallsBackToTaskTitle() async {
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "  ", body: "# body") })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertEqual(s.company.library.first?.title, "Survey users")
    }
    func testAccountSwitchMidRunDiscards() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             taskRunner: { _ in await ref?.hydrate(companyId: "B"); return RunTaskResponse(kind: "doc", title: "x", body: "# y") },
                             librarySaver: { _, _ in true })
        ref = s
        await s.hydrate(companyId: "A")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)   // discarded on switch
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testResetClearsRunState() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        s.reset()
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreRunTaskTests 2>&1 | tail -20`
Expected: FAIL — no `taskRunner`/`librarySaver`/`runTask`/`runningTaskIds`.

- [ ] **Step 3: Add published state + injected deps**

In `codepet/Managers/CompanyStore.swift`, add published state (after `isCompanionTyping`):

```swift
    @Published private(set) var runningTaskIds: Set<String> = []
    @Published private(set) var runError: String?
```

Add stored deps (after `chatSender`):

```swift
    private let taskRunner: (RunTaskRequest) async -> RunTaskResponse?
    private let librarySaver: (String, [Deliverable]) async -> Bool
```

Extend `init` (keep all existing defaults):

```swift
    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief,
         roadmapFetcher: @escaping (CompanyBrief) async -> [RoadmapTask] = CompanyData.fetchRoadmap,
         tasksSaver: @escaping (String, [RoadmapTask]) async -> Bool = CompanyData.saveTasks,
         chatSender: @escaping (CompanyChatRequest) async -> String? = CompanyChatClient.send,
         taskRunner: @escaping (RunTaskRequest) async -> RunTaskResponse? = RunTaskClient.run,
         librarySaver: @escaping (String, [Deliverable]) async -> Bool = CompanyData.saveLibrary) {
        self.loader = loader
        self.saver = saver
        self.roadmapFetcher = roadmapFetcher
        self.tasksSaver = tasksSaver
        self.chatSender = chatSender
        self.taskRunner = taskRunner
        self.librarySaver = librarySaver
    }
```

- [ ] **Step 4: Add `runTask` + clear on reset**

Add the method (inside the class, e.g. after `toggleTaskDone`):

```swift
    /// Run a codepetCanDo task → produce a Deliverable → append to the library + persist.
    /// Fail-open: a nil/empty result surfaces an honest runError and appends nothing.
    /// Task is left as-is. companyId-guarded against account switch mid-run.
    func runTask(_ task: RoadmapTask, language: AppLanguage) async {
        guard !runningTaskIds.contains(task.id) else { return }
        runningTaskIds.insert(task.id)
        runError = nil
        let req = RunTaskRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks),
            taskId: task.id, taskTitle: task.title, taskDetail: task.detail)
        let cid = companyId
        let result = await taskRunner(req)
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        let body = result?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let result, !body.isEmpty else {
            runError = language == .vi
                ? "Không tạo được \"\(task.title)\" — thử lại nhé."
                : "Couldn't generate \"\(task.title)\" — try again."
            return
        }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliverable = Deliverable(
            id: UUID().uuidString, kind: DeliverableKind(raw: result.kind),
            title: title.isEmpty ? task.title : title, body: body,
            createdAt: ISOTime.utc(Date()), sourceTaskId: task.id)
        company.library.append(deliverable)
        if let cid { _ = await librarySaver(cid, company.library) }
    }

    /// Clear the transient run error (e.g. when the board's error line is dismissed).
    func clearRunError() { runError = nil }
```

In `reset()`, add (with the other clears):

```swift
        runningTaskIds = []
        runError = nil
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (6 tests). Existing `CompanyStore` tests still compile (new init params defaulted).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreRunTaskTests.swift
# commit (fsmonitor-off form): "feat(library): CompanyStore.runTask (fail-open, 6A gates, task left as-is)"
```

---

### Task 5: Run affordance + `runError` line

**Files:**
- Modify: `codepet/Views/Overview/TaskCardView.swift`, `codepet/Views/Overview/OverviewBoardView.swift`
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `CompanyStore` (`runningTaskIds`, `runError`, `runTask`, `clearRunError`), `TaskStatus` (3A), CodepetTheme.

- [ ] **Step 1: Add the Run affordance to `TaskCardView.swift`**

Insert a Run row right after the who/status `HStack` closes (before the `if status == .blocked` block). The card already has `@EnvironmentObject var companyStore` and `private var status`:

```swift
                if status == .codepetCanDo {
                    Button {
                        Task { await companyStore.runTask(task, language: lang) }
                    } label: {
                        HStack(spacing: 5) {
                            if companyStore.runningTaskIds.contains(task.id) {
                                ProgressView().controlSize(.mini)
                                Text(lang == .vi ? "Đang chạy…" : "Running…")
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 9))
                                Text(lang == .vi ? "Chạy" : "Run")
                            }
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                    }
                    .buttonStyle(.plain)
                    .disabled(companyStore.runningTaskIds.contains(task.id))
                }
```

- [ ] **Step 2: Add the `runError` line to `OverviewBoardView.swift`**

In the `board` computed view, insert the error line at the top of the `VStack` (before `RoadmapHeaderView`). `OverviewBoardView` already has `@EnvironmentObject var companyStore`; add `@Environment(\.uiLanguage) private var lang` if not present, then:

```swift
        VStack(alignment: .leading, spacing: 14) {
            if let err = companyStore.runError {
                HStack(spacing: 8) {
                    Text(err)
                        .font(.pixelSystem(size: 11, weight: .medium))
                        .foregroundColor(CodepetTheme.accentOrange)
                    Spacer()
                    Button { companyStore.clearRunError() } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.accentOrange.opacity(0.12)))
            }
            RoadmapHeaderView(tasks: tasks)
            ScrollView(.horizontal, showsIndicators: true) {
```

(Leave the rest of `board` — the `ScrollView`/`HStack`/`ForEach` — exactly as-is.)

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
git add codepet/Views/Overview/TaskCardView.swift codepet/Views/Overview/OverviewBoardView.swift
# commit (fsmonitor-off form): "feat(library): Run affordance on codepetCanDo cards + board runError line"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. A `codepetCanDo` task card shows Run → a spinner while running → the deliverable appears in the Library (or the honest `runError` line until the `runTask` CF ships).

---

## Self-Review

**Spec coverage:** `ISOTime.utc` canonical timestamp (Task 1 ✓); `RunTaskClient` DTOs + fail-open run (Task 2 ✓); `CompanyData.deliverablesPayload`/`saveLibrary` (Task 3 ✓); `CompanyStore.runningTaskIds`/`runError` + `runTask` honoring the 6A gates (unique UUID / canonical `ISOTime.utc` / required title+body) + injectable deps + `reset` clears (Task 4 ✓); Run affordance on `codepetCanDo` cards + board `runError` line (Task 5 ✓). Decisions honored: native-only fail-open; task left as-is; Run on codepetCanDo only; honest runError; append each run; account-switch guard.

**Placeholder scan:** none — every step has complete code or an exact command.

**Type consistency:** `RunTaskRequest`/`RunTaskResponse`/`RunTaskClient.run` (Task 2) used by Task 4's `taskRunner` default + `runTask`. `ISOTime.utc` (Task 1) called in Task 4. `CompanyData.saveLibrary` (Task 3) = Task 4's `librarySaver` default. `Deliverable(id:kind:title:body:createdAt:sourceTaskId:)` + `DeliverableKind(raw:)` (6A) used in Task 4. `ChatContext.compose(brief:tasks:)` (5) used in Task 4. `runTask(_:language:)` (Task 4) called by `TaskCardView` (Task 5). `runningTaskIds`/`runError`/`clearRunError` (Task 4) read by Tasks 5. `TaskStatus.codepetCanDo` (3A) gates the Run button.

**Known notes for the implementer:** (a) Task 5 views have no unit tests by design (SwiftUI verified by build); TDD applies to Tasks 1–4. (b) the `runTask` account-switch test resets via a same-pattern `ref?.hydrate("B")` inside the injected runner (companyId changes A→B → the `companyId == cid` guard discards). (c) `body`/`title` are trimmed before the required-fields guard so a whitespace-only result correctly fails open. (d) `runTask` appends each run (no dedup) — running a task twice yields two library entries, per the approved decision.