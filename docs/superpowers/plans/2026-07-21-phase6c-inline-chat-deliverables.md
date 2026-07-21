# Phase 6C — Inline Chat Deliverable Cards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Copilot chat can run a task inline — byte's reply optionally carries a `runTaskId`; if it names a runnable task, produce a **draft** deliverable card in chat with **Approve** (→ Library) / **Redo** (re-run). Native-only + fail-open.

**Architecture:** Extend the Phase-5 chat contract so `chatSender` returns `CompanyChatReply { text, runTaskId? }`. `CopilotMessage` carries an ephemeral `draft: Deliverable?`. A shared `buildDeliverable` centralizes the 6A gates (both `runTask` and the chat-run use it). `sendChat` runs a matching runnable task and attaches the draft to a companion message; `approveDraft` promotes it to `company.library`; `redoDraft` re-runs. The inline card lives in `CopilotBubble`.

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `CompanyChatClient`/`sendChat` (5), `RunTaskClient`/`taskRunner`/`saveLibrary`/`ISOTime` (6B), `Deliverable`/`DeliverableDetailView`/`MarkdownView` (6A), `RoadmapEngine`, CodepetTheme. Spec: `docs/superpowers/specs/2026-07-21-phase6c-inline-chat-deliverables-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **6A gates (enforced ONLY in `buildDeliverable`):** unique `UUID().uuidString` id; canonical `ISOTime.utc(Date())` createdAt; non-empty title (fallback `task.title`) + non-empty body — else return nil (never a malformed draft/deliverable).
- **Decisions:** AI-decides via `runTaskId`; ephemeral chat-attached drafts (no `status` on Deliverable; library = approved only); Approve → Library (persist), Redo → re-run; runnable = `RoadmapEngine.status == .codepetCanDo`; fail-open (honest companion bubbles, never throw/block); account-switch guarded via `companyId`. Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Modify `codepet/Services/CompanyChatClient.swift` (Task 1: `CompanyChatReply` + `runTaskId` + `send` return)
- Modify `codepet/Managers/CompanyStore.swift` (Task 1: `chatSender` type + `sendChat` text; Task 2: `buildDeliverable`/`runRequest` + `runTask` refactor; Task 3: run-integration + `approveDraft`/`redoDraft`)
- Modify `codepet/Models/CopilotMessage.swift` (Task 2: `draft`/`draftApproved`)
- Modify `codepet/Views/Copilot/CopilotChatView.swift` (Task 4: `CopilotBubble` card)
- Tests: modify `codepetTests/{CompanyChatClientTests, CompanyStoreChatTests}.swift` (Task 1); create `codepetTests/CompanyStoreChatRunTests.swift` (Task 3)

---

### Task 1: Chat contract → `CompanyChatReply`

**Files:**
- Modify: `codepet/Services/CompanyChatClient.swift`, `codepet/Managers/CompanyStore.swift`, `codepetTests/CompanyChatClientTests.swift`, `codepetTests/CompanyStoreChatTests.swift`

**Interfaces:**
- Produces: `struct CompanyChatReply { let text: String; let runTaskId: String? }`; `CompanyChatResponse.runTaskId: String?` (`run_task_id`); `CompanyChatClient.send(_:) async -> CompanyChatReply?`; `CompanyStore.chatSender: (CompanyChatRequest) async -> CompanyChatReply?`.

- [ ] **Step 1: Update the contract test (fails until the type changes)**

Replace `testResponseDecodes` in `codepetTests/CompanyChatClientTests.swift` and add a reply test:

```swift
    func testResponseDecodesWithRunTaskId() throws {
        let data = "{\"reply\":\"On it\",\"run_task_id\":\"t1\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertEqual(r.reply, "On it")
        XCTAssertEqual(r.runTaskId, "t1")
    }
    func testResponseDecodesWithoutRunTaskId() throws {
        let data = "{\"reply\":\"hi\"}".data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(CompanyChatResponse.self, from: data).runTaskId)
    }
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyChatClientTests 2>&1 | tail -20`
Expected: FAIL — `CompanyChatResponse` has no `runTaskId`.

- [ ] **Step 3: Extend `CompanyChatClient.swift`**

Replace `CompanyChatResponse` + add `CompanyChatReply`, and change `send`'s return:

```swift
/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
    let runTaskId: String?

    enum CodingKeys: String, CodingKey {
        case reply
        case runTaskId = "run_task_id"
    }
}

/// A companion reply — text plus an optional "run this task" action (byte's run_task).
struct CompanyChatReply: Equatable {
    let text: String
    let runTaskId: String?
}
```

Change `send`'s signature + tail:

```swift
    static func send(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyChatResponse.self, from: data)
        else { return nil }
        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId)
    }
```

- [ ] **Step 4: Change `chatSender` type + `sendChat` text use in `CompanyStore.swift`**

Change the stored property + init default type (the default `CompanyChatClient.send` now already returns `CompanyChatReply?`):

```swift
    private let chatSender: (CompanyChatRequest) async -> CompanyChatReply?
```
```swift
         chatSender: @escaping (CompanyChatRequest) async -> CompanyChatReply? = CompanyChatClient.send,
```

In `sendChat`, change the append to use `reply?.text` (leave the rest of `sendChat` as-is this task — `runTaskId` is wired in Task 3):

```swift
        chatMessages.append(CopilotMessage(role: .companion, text: reply?.text ?? offline))
```

- [ ] **Step 5: Update the Phase-5 chat test stubs in `CompanyStoreChatTests.swift`**

The `store(_:)` helper's `sender` param + every inline stub returns `CompanyChatReply?` now. Update the helper signature and each stub. Replace the file's `store` helper + stubs:

```swift
    private func store(_ sender: @escaping (CompanyChatRequest) async -> CompanyChatReply?) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true }, chatSender: sender)
    }
```

Then change each stub to wrap text in `CompanyChatReply(text:runTaskId:)`:
- `{ _ in "Hello founder" }` → `{ _ in CompanyChatReply(text: "Hello founder", runTaskId: nil) }`
- `{ _ in nil }` → unchanged (nil is valid)
- `{ _ in "x" }` → `{ _ in CompanyChatReply(text: "x", runTaskId: nil) }` (appears 3×: testEmptyInputIsNoOp, testResetClearsChat, testReplyStillAppliesAfterSameUserRehydrate)
- in `testStaleReplyAfterResetDiscarded`: `{ _ in await ref?.reset(); return "late reply" }` → `{ _ in await ref?.reset(); return CompanyChatReply(text: "late reply", runTaskId: nil) }`
- in `testAccountSwitchViaHydrateClearsRunState`… (that's a run-task test, not chat) — skip.
- in `testReplyStillAppliesAfterSameUserRehydrate`: `{ _ in await ref?.hydrate(companyId: "u"); return "reply" }` → `{ _ in await ref?.hydrate(companyId: "u"); return CompanyChatReply(text: "reply", runTaskId: nil) }`
- in `testAccountSwitchViaHydrateClearsChatAndDiscardsReply`: `{ _ in await ref?.hydrate(companyId: "B"); return "A reply" }` → `{ _ in await ref?.hydrate(companyId: "B"); return CompanyChatReply(text: "A reply", runTaskId: nil) }`

(The assertions on `.text` values stay the same.)

- [ ] **Step 6: Run the contract + chat tests to verify green**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyChatClientTests -only-testing:codepetTests/CompanyStoreChatTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (behavior unchanged; `runTaskId` unused yet).

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Services/CompanyChatClient.swift codepet/Managers/CompanyStore.swift codepetTests/CompanyChatClientTests.swift codepetTests/CompanyStoreChatTests.swift
# commit (fsmonitor-off form): "feat(copilot): chat reply carries optional runTaskId (CompanyChatReply)"
```

---

### Task 2: `CopilotMessage.draft` + shared `buildDeliverable` + `runTask` refactor

**Files:**
- Modify: `codepet/Models/CopilotMessage.swift`, `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CopilotMessageDraftTests.swift`

**Interfaces:**
- Consumes: `Deliverable`/`DeliverableKind`/`RunTaskResponse`/`RoadmapTask`/`ISOTime` (6A/6B).
- Produces: `CopilotMessage.draft: Deliverable?` + `.draftApproved: Bool`; `CompanyStore.buildDeliverable(from:task:) -> Deliverable?` (private); `CompanyStore.runRequest(for:language:) -> RunTaskRequest` (private); `runTask` refactored onto both.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CopilotMessageDraftTests.swift
import XCTest
@testable import codepet

final class CopilotMessageDraftTests: XCTestCase {
    func testDraftDefaultsNilAndNotApproved() {
        let m = CopilotMessage(role: .companion, text: "hi")
        XCTAssertNil(m.draft)
        XCTAssertFalse(m.draftApproved)
    }
    func testCarriesDraftAndEquatable() {
        let d = Deliverable(id: "d1", kind: .doc, title: "T", body: "b")
        let m = CopilotMessage(id: "m1", role: .companion, text: "", draft: d)
        XCTAssertEqual(m.draft?.id, "d1")
        XCTAssertEqual(m, CopilotMessage(id: "m1", role: .companion, text: "", draft: d))
        XCTAssertNotEqual(m, CopilotMessage(id: "m1", role: .companion, text: "", draft: d, draftApproved: true))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CopilotMessageDraftTests 2>&1 | tail -20`
Expected: FAIL — `CopilotMessage` has no `draft`/`draftApproved`.

- [ ] **Step 3: Extend `CopilotMessage.swift`**

```swift
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    let text: String
    var draft: Deliverable?
    var draftApproved: Bool

    init(id: String = UUID().uuidString, role: CopilotRole, text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.draft = draft
        self.draftApproved = draftApproved
    }
}
```

- [ ] **Step 4: Add the shared helpers + refactor `runTask` in `CompanyStore.swift`**

Add two private helpers (near `runTask`):

```swift
    /// Build a RunTaskRequest for a task (grounded on brief + roadmap).
    private func runRequest(for task: RoadmapTask, language: AppLanguage) -> RunTaskRequest {
        RunTaskRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks),
            taskId: task.id, taskTitle: task.title, taskDetail: task.detail)
    }

    /// Build a Deliverable from a run result — the 6A gates in one place: unique id,
    /// canonical createdAt, non-empty title (fallback task.title) + body. Returns nil
    /// on a nil result or empty body — never a malformed deliverable.
    private func buildDeliverable(from result: RunTaskResponse?, task: RoadmapTask) -> Deliverable? {
        let body = result?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let result, !body.isEmpty else { return nil }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Deliverable(
            id: UUID().uuidString, kind: DeliverableKind(raw: result.kind),
            title: title.isEmpty ? task.title : title, body: body,
            createdAt: ISOTime.utc(Date()), sourceTaskId: task.id)
    }
```

Refactor `runTask`'s body (from the `let req = RunTaskRequest(...)` line through the append) onto them:

```swift
    func runTask(_ task: RoadmapTask, language: AppLanguage) async {
        guard !runningTaskIds.contains(task.id) else { return }
        runningTaskIds.insert(task.id)
        runError = nil
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        guard let deliverable = buildDeliverable(from: result, task: task) else {
            runError = language == .vi
                ? "Không tạo được \"\(task.title)\" — thử lại nhé."
                : "Couldn't generate \"\(task.title)\" — try again."
            return
        }
        company.library.append(deliverable)
        if let cid { _ = await librarySaver(cid, company.library) }
    }
```

- [ ] **Step 5: Run the draft test + the runTask regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CopilotMessageDraftTests -only-testing:codepetTests/CompanyStoreRunTaskTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` (draft model works; `runTask` behavior unchanged by the refactor).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/CopilotMessage.swift codepet/Managers/CompanyStore.swift codepetTests/CopilotMessageDraftTests.swift
# commit (fsmonitor-off form): "feat(copilot): CopilotMessage.draft + shared buildDeliverable/runRequest (runTask refactor)"
```

---

### Task 3: `sendChat` run-integration + Approve/Redo

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreChatRunTests.swift`

**Interfaces:**
- Consumes: `buildDeliverable`/`runRequest` (Task 2), `taskRunner`/`librarySaver` (6B), `RoadmapEngine.status` (3A), `CompanyChatReply` (Task 1).
- Produces: `sendChat` run-integration; `CompanyStore.approveDraft(messageId:) async`; `redoDraft(messageId:language:) async`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreChatRunTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatRunTests: XCTestCase {
    private func seeded() -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: Date(),
                     tasks: [RoadmapTask(id: "t1", title: "Survey users", detail: "wtp", phase: .find, who: .does)])
    }
    private func store(reply: CompanyChatReply?,
                       runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                     chatSender: { _ in reply }, taskRunner: runner, librarySaver: saver)
    }

    func testRunnableReplyProducesDraftNotInLibrary() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") })
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(s.chatMessages[1].text, "On it")           // lead-in
        let draftMsg = s.chatMessages[2]
        XCTAssertEqual(draftMsg.draft?.sourceTaskId, "t1")
        XCTAssertFalse(draftMsg.draft?.id.isEmpty ?? true)
        XCTAssertTrue(draftMsg.draft?.createdAt?.hasSuffix("Z") ?? false)
        XCTAssertTrue(s.company.library.isEmpty)                  // draft NOT in library
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testUnknownRunTaskIdNoDraft() async {
        let s = store(reply: CompanyChatReply(text: "hm", runTaskId: "nope"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)                   // me + lead-in only
        XCTAssertNil(s.chatMessages.last?.draft)
    }
    func testChatRunFailureHonestBubble() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in nil })
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        XCTAssertEqual(s.chatMessages.count, 3)
        XCTAssertNil(s.chatMessages[2].draft)                     // failure bubble, no draft
        XCTAssertFalse(s.chatMessages[2].text.isEmpty)
    }
    func testApproveDraftMovesToLibraryAndPersists() async {
        var saved: [Deliverable] = []
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") },
                      saver: { _, lib in saved = lib; return true })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(s.chatMessages[2].draftApproved)
        // second approve is a no-op
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
    }
    func testRedoReplacesDraft() async {
        var body = "# first"
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: body) })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        let firstId = s.chatMessages[2].draft?.id
        body = "# second"
        await s.redoDraft(messageId: mid, language: .en)
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# second")
        XCTAssertNotEqual(s.chatMessages[2].draft?.id, firstId)   // fresh deliverable
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreChatRunTests 2>&1 | tail -20`
Expected: FAIL — no run-integration / `approveDraft` / `redoDraft`.

- [ ] **Step 3: Add the run-integration to `sendChat`**

Replace `sendChat`'s tail (from the `chatMessages.append(CopilotMessage(role: .companion, text: reply?.text ?? offline))` line + the trailing `isCompanionTyping = false`) with:

```swift
        chatMessages.append(CopilotMessage(role: .companion, text: reply?.text ?? offline))
        // If byte chose to run a runnable task, produce a draft deliverable inline.
        if let runId = reply?.runTaskId,
           let task = company.tasks.first(where: { $0.id == runId }),
           RoadmapEngine.status(for: task, in: company.tasks) == .codepetCanDo {
            let result = await taskRunner(runRequest(for: task, language: language))
            guard companyId == cid else { return }
            if let draft = buildDeliverable(from: result, task: task) {
                chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft))
            } else {
                chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                    ? "Không tạo được ngay bây giờ — thử lại nhé."
                    : "Couldn't generate that just now — try again."))
            }
        }
        isCompanionTyping = false
```

- [ ] **Step 4: Add `approveDraft` + `redoDraft`**

Add both (inside the class, e.g. after `sendChat`):

```swift
    /// Approve a chat draft: append it to the library (approved) + persist.
    func approveDraft(messageId: String) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved else { return }
        company.library.append(draft)
        chatMessages[i].draftApproved = true
        if let cid = companyId { _ = await librarySaver(cid, company.library) }
    }

    /// Redo a chat draft: re-run its source task and replace the draft (fail-soft).
    func redoDraft(messageId: String, language: AppLanguage) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved,
              let task = company.tasks.first(where: { $0.id == draft.sourceTaskId }) else { return }
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        guard companyId == cid,
              let j = chatMessages.firstIndex(where: { $0.id == messageId }),
              let fresh = buildDeliverable(from: result, task: task) else { return }
        chatMessages[j].draft = fresh
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (5 tests). Also re-run the Phase-5 chat suite to confirm no regression: `-only-testing:codepetTests/CompanyStoreChatTests` → still green.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreChatRunTests.swift
# commit (fsmonitor-off form): "feat(copilot): sendChat run-integration + approveDraft/redoDraft (inline drafts)"
```

---

### Task 4: Inline deliverable card in `CopilotBubble`

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `CompanyStore` (`approveDraft`/`redoDraft`), `Deliverable`/`DeliverableDetailView` (6A), CodepetTheme.

- [ ] **Step 1: Replace `CopilotBubble` in `CopilotChatView.swift`**

```swift
/// One chat bubble — me (accent, right) vs companion (surface, left), OR a draft
/// deliverable card (Approve/Redo) when the message carries a draft.
struct CopilotBubble: View {
    let message: CopilotMessage
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var showDetail = false
    private var isMe: Bool { message.role == .me }

    var body: some View {
        if let draft = message.draft {
            draftCard(draft)
        } else {
            textBubble
        }
    }

    private var textBubble: some View {
        HStack {
            if isMe { Spacer(minLength: 24) }
            Text(message.text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(isMe ? .white : CodepetTheme.primaryText)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isMe ? CodepetTheme.accentPurple : CodepetTheme.surface))
                .fixedSize(horizontal: false, vertical: true)
            if !isMe { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }

    private func draftCard(_ d: Deliverable) -> some View {
        HStack {
            CodepetCard {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: d.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                            Text(d.title)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                        }
                        Text(d.body)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showDetail = true }

                    if message.draftApproved {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(lang == .vi ? "Đã thêm vào Thư viện" : "Added to Library")
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentTeal)
                    } else {
                        HStack(spacing: 8) {
                            Button { Task { await companyStore.approveDraft(messageId: message.id) } } label: {
                                Text(lang == .vi ? "Duyệt" : "Approve")
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(CodepetTheme.accentPurple))
                            }.buttonStyle(.plain)
                            Button { Task { await companyStore.redoDraft(messageId: message.id, language: lang) } } label: {
                                Text(lang == .vi ? "Làm lại" : "Redo")
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(CodepetTheme.bodyText)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().stroke(CodepetTheme.hairline))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 24)
        }
        .sheet(isPresented: $showDetail) { DeliverableDetailView(deliverable: d) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full test suite to confirm no regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Copilot/CopilotChatView.swift
# commit (fsmonitor-off form): "feat(copilot): inline draft deliverable card in CopilotBubble (Approve/Redo/open)"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. When byte's reply carries a runnable `runTaskId`, the chat shows the lead-in + a draft deliverable card; Approve promotes it to the Library, Redo re-runs, tap opens the detail (all fail-open until the CFs ship).

---

## Self-Review

**Spec coverage:** chat contract → `CompanyChatReply` + `runTaskId` + `chatSender` type (Task 1 ✓); `CopilotMessage.draft`/`draftApproved` + shared `buildDeliverable`/`runRequest` centralizing the 6A gates + `runTask` refactor (Task 2 ✓); `sendChat` run-integration (runnable-guard, fail-open honest bubble, account-guarded) + `approveDraft`/`redoDraft` (Task 3 ✓); inline card in `CopilotBubble` w/ Approve/Redo/approved + detail sheet (Task 4 ✓). Decisions honored: AI-decides via runTaskId; ephemeral chat drafts (no status field); Approve→Library+persist; Redo re-runs; runnable == codepetCanDo; fail-open.

**Placeholder scan:** none — every step has complete code or an exact command.

**Type consistency:** `CompanyChatReply {text, runTaskId}` (Task 1) returned by `chatSender`, read in `sendChat` (Tasks 1/3). `CompanyChatClient.send -> CompanyChatReply?` matches the init default. `CopilotMessage(role:text:draft:draftApproved:)` (Task 2) used by Task 3 (`draft:`) + Task 4 (reads `.draft`/`.draftApproved`). `buildDeliverable(from:task:)`/`runRequest(for:language:)` (Task 2) used by `runTask` + Task 3's run-integration/redoDraft. `approveDraft(messageId:)`/`redoDraft(messageId:language:)` (Task 3) called by `CopilotBubble` (Task 4). `DeliverableDetailView(deliverable:)` (6A) reused. `RoadmapEngine.status(for:in:) == .codepetCanDo` gates the run.

**Known notes for the implementer:** (a) Task 4 has no unit tests by design (SwiftUI verified by build); TDD applies to Tasks 1–3. (b) `sendChat` keeps `isCompanionTyping = true` through the whole exchange (lead-in + run) and clears it once at the end; the run's `guard companyId == cid` early-returns without clearing only on an account switch, where hydrate/reset already cleared it. (c) the draft-message text is `""` — `CopilotBubble` renders the card (not a text bubble) whenever `message.draft != nil`. (d) drafts are session-only; `reset()`/account-switch already clear `chatMessages`, so drafts ride along.
