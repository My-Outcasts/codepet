# Phase 5 — Copilot Chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native SwiftUI Copilot chat — the founder talks to their company's AI companion, grounded on the company brief + roadmap — replacing the placeholder Copilot column. Conversational only (tasks/deliverables are Phase 6).

**Architecture:** Chat state lives on `CompanyStore` (session-only). `sendChat` builds a grounding context (pure `ChatContext.compose`), calls an injectable fail-open `chatSender` (default `CompanyChatClient.send` → a planned `companyChat` Cloud Function), and appends a single reply — or an honest offline message on failure. `CopilotChatView` renders it. The CF is authored + deployed separately (node-22 bundle, like `scaffoldRoadmap`).

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `CompanyStore`, `CompanyBrief`/`BriefContext.compose`, `RoadmapEngine`, `PetCharacter.all`, CodepetTheme, `@Environment(\.uiLanguage)`. Spec: `docs/superpowers/specs/2026-07-21-phase5-copilot-chat-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **Decisions:** native-only + FAIL-OPEN (nil reply → honest offline message, never throw/block); SINGLE reply + typing indicator; SESSION-ONLY (chat cleared on `reset()`); token-guarded against account-switch. Honest offline copy EN "I can't reach my brain right now — try again in a bit." / VI "Mình không kết nối được lúc này — thử lại sau nhé." Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Create `codepet/Models/CopilotMessage.swift` (Task 1)
- Create `codepet/Models/ChatContext.swift` (Task 1)
- Create `codepet/Services/CompanyChatClient.swift` (Task 2)
- Modify `codepet/Managers/CompanyStore.swift` (Task 3)
- Create `codepet/Views/Copilot/CopilotChatView.swift` (Task 4: view + `CopilotBubble`)
- Modify `codepet/Views/Shell/AppShellView.swift` (Task 4: copilot column → `CopilotChatView`)
- Tests: `codepetTests/{ChatContextTests, CompanyChatClientTests, CompanyStoreChatTests}.swift`

---

### Task 1: `CopilotMessage` + `ChatContext.compose`

**Files:**
- Create: `codepet/Models/CopilotMessage.swift`, `codepet/Models/ChatContext.swift`
- Test: `codepetTests/ChatContextTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief`/`BriefContext.compose`, `RoadmapTask`/`RoadmapEngine` (nextStep/progressPercent).
- Produces: `enum CopilotRole { case me, companion }`; `struct CopilotMessage: Identifiable, Equatable { id; role; text }`; `ChatContext.compose(brief:tasks:) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ChatContextTests.swift
import XCTest
@testable import codepet

final class ChatContextTests: XCTestCase {
    func testComposeIncludesBriefNextStepAndProgress() {
        let brief = CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion")
        let tasks = [
            RoadmapTask(id: "a", title: "Interview users", detail: "", phase: .find, who: .you),
            RoadmapTask(id: "b", title: "Ship auth", detail: "", phase: .build, who: .does, done: true),
        ]
        let ctx = ChatContext.compose(brief: brief, tasks: tasks)
        XCTAssertTrue(ctx.contains("Codepet"))          // brief signal
        XCTAssertTrue(ctx.contains("Interview users"))  // next step / open task
        XCTAssertTrue(ctx.contains("%"))                // progress
    }
    func testComposeEmptyStillNonEmpty() {
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [])
        XCTAssertFalse(ctx.isEmpty)
        XCTAssertTrue(ctx.contains("No brief yet"))
    }
    func testCopilotMessageIdentityAndEquatable() {
        let m = CopilotMessage(id: "1", role: .me, text: "hi")
        XCTAssertEqual(m.id, "1")
        XCTAssertEqual(m, CopilotMessage(id: "1", role: .me, text: "hi"))
        XCTAssertNotEqual(m, CopilotMessage(id: "2", role: .companion, text: "hi"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ChatContextTests 2>&1 | tail -20`
Expected: FAIL — no `CopilotMessage` / `ChatContext`.

- [ ] **Step 3: Write `CopilotMessage.swift`**

```swift
// codepet/Models/CopilotMessage.swift
import Foundation

/// Who authored a Copilot chat message.
enum CopilotRole { case me, companion }

/// One Copilot chat message (session-only; not persisted this phase). Named to
/// avoid the reflection `ChatMessage`.
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    let text: String

    init(id: String = UUID().uuidString, role: CopilotRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
```

- [ ] **Step 4: Write `ChatContext.swift`**

```swift
// codepet/Models/ChatContext.swift
import Foundation

/// Pure grounding-string builder for the Copilot chat — the company brief plus a
/// short roadmap summary, sent to the companyChat CF as `context`. Always returns
/// a non-empty string.
enum ChatContext {
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask]) -> String {
        var parts: [String] = []
        parts.append(BriefContext.compose(brief) ?? "No brief yet.")
        parts.append("Roadmap progress: \(RoadmapEngine.progressPercent(tasks))%.")
        if let next = RoadmapEngine.nextStep(tasks) {
            parts.append("Next step: \(next.title).")
        }
        let openTitles = tasks.filter { !$0.done }.prefix(6).map { $0.title }
        if !openTitles.isEmpty {
            parts.append("Open tasks: " + openTitles.joined(separator: "; ") + ".")
        }
        return parts.joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/CopilotMessage.swift codepet/Models/ChatContext.swift codepetTests/ChatContextTests.swift
# commit (fsmonitor-off form): "feat(copilot): CopilotMessage + ChatContext.compose (brief+roadmap grounding)"
```

---

### Task 2: `CompanyChatClient` (DTOs + fail-open send)

**Files:**
- Create: `codepet/Services/CompanyChatClient.swift`
- Test: `codepetTests/CompanyChatClientTests.swift`

**Interfaces:**
- Produces: `struct ChatTurnDTO: Codable, Equatable { role; text }`; `struct CompanyChatRequest: Codable { companyId?; language; companionId; context; history; userMessage }` (snake_case keys); `struct CompanyChatResponse: Codable { reply }`; `enum CompanyChatClient { static func send(_:) async -> String? }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyChatClientTests.swift
import XCTest
@testable import codepet

final class CompanyChatClientTests: XCTestCase {
    func testRequestEncodesSnakeCaseAndRoundTrips() throws {
        let req = CompanyChatRequest(companyId: "u1", language: "en", companionId: "byte",
                                     context: "ctx", history: [ChatTurnDTO(role: "me", text: "hi")],
                                     userMessage: "hello")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["company_id"] as? String, "u1")
        XCTAssertEqual(json?["companion_id"] as? String, "byte")
        XCTAssertEqual(json?["user_message"] as? String, "hello")
        let back = try JSONDecoder().decode(CompanyChatRequest.self, from: data)
        XCTAssertEqual(back.history, req.history)
    }
    func testResponseDecodes() throws {
        let data = "{\"reply\":\"hi there\"}".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(CompanyChatResponse.self, from: data).reply, "hi there")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyChatClientTests 2>&1 | tail -20`
Expected: FAIL — no `CompanyChatRequest`/`CompanyChatClient`.

- [ ] **Step 3: Write `CompanyChatClient.swift`**

```swift
// codepet/Services/CompanyChatClient.swift
import Foundation

/// One prior chat turn sent to the CF as history.
struct ChatTurnDTO: Codable, Equatable {
    let role: String   // "me" | "companion"
    let text: String
}

/// Request body for the companyChat Cloud Function.
struct CompanyChatRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let history: [ChatTurnDTO]
    let userMessage: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case history
        case userMessage = "user_message"
    }
}

/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
}

/// Fail-open client for the (planned) companyChat Cloud Function. Returns the reply
/// on 200, `nil` on any error / non-200 / unreachable — callers never handle throws.
/// The CF is authored + deployed separately (node-22 bundle, like scaffoldRoadmap);
/// until then this returns nil and the chat shows an honest offline message.
enum CompanyChatClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat")!

    static func send(_ req: CompanyChatRequest) async -> String? {
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
        return reply.isEmpty ? nil : reply
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Services/CompanyChatClient.swift codepetTests/CompanyChatClientTests.swift
# commit (fsmonitor-off form): "feat(copilot): CompanyChatClient DTOs + fail-open send (companyChat CF)"
```

---

### Task 3: `CompanyStore` chat state + `sendChat`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreChatTests.swift`

**Interfaces:**
- Consumes: `CopilotMessage` (Task 1), `ChatContext.compose` (Task 1), `CompanyChatRequest`/`ChatTurnDTO`/`CompanyChatClient.send` (Task 2), `AppLanguage`.
- Produces: `CompanyStore.chatMessages: [CopilotMessage]`; `.isCompanionTyping: Bool`; `func sendChat(_ raw: String, language: AppLanguage) async`; injectable `chatSender` init param; `reset()` clears chat.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreChatTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatTests: XCTestCase {
    private func store(_ sender: @escaping (CompanyChatRequest) async -> String?) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true }, chatSender: sender)
    }

    func testSendAppendsUserThenCompanionReply() async {
        let s = store { _ in "Hello founder" }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.last?.text, "Hello founder")
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testFailOpenAppendsOfflineMessage() async {
        let s = store { _ in nil }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages.last?.role, .companion)
        XCTAssertTrue(s.chatMessages.last?.text.contains("reach my brain") ?? false)
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testEmptyInputIsNoOp() async {
        let s = store { _ in "x" }
        await s.hydrate(companyId: "u")
        await s.sendChat("   ", language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }
    func testResetClearsChat() async {
        let s = store { _ in "x" }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        s.reset()
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertFalse(s.isCompanionTyping)
    }
    /// A reply arriving after an account switch (reset bumps the token) must not append.
    func testStaleReplyAfterResetDiscarded() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in await ref?.reset(); return "late reply" })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.text == "late reply" })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreChatTests 2>&1 | tail -20`
Expected: FAIL — no `chatSender` param / `sendChat` / `chatMessages`.

- [ ] **Step 3: Add chat state + injected sender**

In `codepet/Managers/CompanyStore.swift`, add published state (near the other `@Published`):

```swift
    @Published private(set) var chatMessages: [CopilotMessage] = []
    @Published private(set) var isCompanionTyping = false
```

Add the stored dependency (near `roadmapFetcher`/`tasksSaver`):

```swift
    private let chatSender: (CompanyChatRequest) async -> String?
```

Extend `init` (keep all existing defaults):

```swift
    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief,
         roadmapFetcher: @escaping (CompanyBrief) async -> [RoadmapTask] = CompanyData.fetchRoadmap,
         tasksSaver: @escaping (String, [RoadmapTask]) async -> Bool = CompanyData.saveTasks,
         chatSender: @escaping (CompanyChatRequest) async -> String? = CompanyChatClient.send) {
        self.loader = loader
        self.saver = saver
        self.roadmapFetcher = roadmapFetcher
        self.tasksSaver = tasksSaver
        self.chatSender = chatSender
    }
```

- [ ] **Step 4: Add `sendChat` + clear on reset**

Add the method (inside the class):

```swift
    /// Send a founder message to the company companion (single reply, fail-open,
    /// session-only). Token-guarded: an account switch mid-reply discards the reply.
    func sendChat(_ raw: String, language: AppLanguage) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isCompanionTyping else { return }
        chatMessages.append(CopilotMessage(role: .me, text: text))
        isCompanionTyping = true
        let history = chatMessages.dropLast().suffix(20).map {
            ChatTurnDTO(role: $0.role == .me ? "me" : "companion", text: $0.text)
        }
        let req = CompanyChatRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks),
            history: Array(history), userMessage: text)
        let token = hydrationToken
        let reply = await chatSender(req)
        guard token == hydrationToken else { return }
        let offline = language == .vi
            ? "Mình không kết nối được lúc này — thử lại sau nhé."
            : "I can't reach my brain right now — try again in a bit."
        chatMessages.append(CopilotMessage(role: .companion, text: reply ?? offline))
        isCompanionTyping = false
    }
```

In `reset()`, add (with the other clears):

```swift
        chatMessages = []
        isCompanionTyping = false
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (5 tests). Existing `CompanyStore` tests still compile (new init param defaulted).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreChatTests.swift
# commit (fsmonitor-off form): "feat(copilot): CompanyStore chat state + sendChat (fail-open, token-guarded, session-only)"
```

---

### Task 4: `CopilotChatView` + shell wiring

**Files:**
- Create: `codepet/Views/Copilot/CopilotChatView.swift` (view + `CopilotBubble`)
- Modify: `codepet/Views/Shell/AppShellView.swift` (copilot column → `CopilotChatView`)
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `CompanyStore` (`chatMessages`, `isCompanionTyping`, `sendChat`, `company.companionId`), `PetCharacter.all`, CodepetTheme, `@Environment(\.uiLanguage)`.
- Produces: `CopilotChatView()`; `CopilotBubble(message:)`.

- [ ] **Step 1: Write `CopilotChatView.swift`**

```swift
// codepet/Views/Copilot/CopilotChatView.swift
import SwiftUI

/// The Copilot column: a company-grounded chat with the founder's companion.
struct CopilotChatView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !companyStore.isCompanionTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .frame(maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if companyStore.chatMessages.isEmpty { greeting }
                    ForEach(companyStore.chatMessages) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                    if companyStore.isCompanionTyping { typingRow }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: companyStore.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(companyStore.chatMessages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var greeting: some View {
        Text(lang == .vi
             ? "Chào, mình là \(companionName). Hỏi mình bất cứ điều gì về công ty của bạn."
             : "Hi, I'm \(companionName). Ask me anything about your company.")
            .font(.pixelSystem(size: 12))
            .foregroundColor(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var typingRow: some View {
        Text(lang == .vi ? "\(companionName) đang trả lời…" : "\(companionName) is typing…")
            .font(.pixelSystem(size: 11))
            .foregroundColor(CodepetTheme.mutedText)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(lang == .vi ? "Nhắn cho \(companionName)…" : "Message \(companionName)…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.pixelSystem(size: 12))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(10)
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Task { await companyStore.sendChat(text, language: lang) }
    }
}

/// One chat bubble — me (accent, right) vs companion (surface, left).
struct CopilotBubble: View {
    let message: CopilotMessage
    private var isMe: Bool { message.role == .me }

    var body: some View {
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
}
```

- [ ] **Step 2: Wire the copilot column in `AppShellView.swift`**

Replace the entire `copilot` computed property body (the placeholder `VStack` with the "Copilot"/"Chat lands here in a later phase." text) with:

```swift
    private var copilot: some View {
        CopilotChatView()
            .frame(width: 300)
    }
```

(Leave the `topBar` copilot-collapse toggle and the `if !copilotCollapsed { Divider(); copilot }` in `body` exactly as-is.)

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
git add codepet/Views/Copilot/CopilotChatView.swift codepet/Views/Shell/AppShellView.swift
# commit (fsmonitor-off form): "feat(copilot): CopilotChatView + bubble + shell wiring (Copilot column)"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. The Copilot column now shows a working chat UI: greeting → founder message → typing indicator → companion reply (or the honest offline message until the `companyChat` CF ships).

---

## Self-Review

**Spec coverage:** `CopilotMessage`/`CopilotRole` + pure `ChatContext.compose` (Task 1 ✓); `CompanyChatClient` DTOs + fail-open `send` (Task 2 ✓); `CompanyStore.chatMessages`/`isCompanionTyping` + `sendChat` (token-guarded, fail-open, session-only) + injectable `chatSender` + `reset` clears (Task 3 ✓); `CopilotChatView` + `CopilotBubble` + `AppShellView` copilot wiring (Task 4 ✓). Decisions honored: native-only fail-open (nil→honest offline copy verbatim), single reply + typing indicator, session-only (reset clears), token-guard, VI/EN.

**Placeholder scan:** none — every step has complete code or an exact command.

**Type consistency:** `CopilotMessage(role:text:)` / `CopilotRole.me`/`.companion` (Task 1) used in Task 3/4. `ChatContext.compose(brief:tasks:)` (Task 1) called in Task 3. `CompanyChatRequest`/`ChatTurnDTO`/`CompanyChatClient.send` (Task 2) used by Task 3's `chatSender` default + `sendChat`. `chatSender: (CompanyChatRequest) async -> String?` init default `CompanyChatClient.send` — signatures match. `sendChat(_:language:)` (Task 3) called by `CopilotChatView.send` (Task 4). `AppLanguage.rawValue` ("vi"/"en") used for `language`. `PetCharacter.all[id]?.name` for the greeting.

**Known notes for the implementer:** (a) Task 4 views have no unit tests by design (spec: SwiftUI verified by build); TDD applies to Tasks 1–3. (b) `sendChat`'s `!isCompanionTyping` guard + the view's `canSend` (`!isCompanionTyping`) together prevent overlapping sends. (c) the stale-reply test resets the store from inside the injected sender via a captured `ref` — `await ref?.reset()` hops to the MainActor; this exercises `sendChat`'s post-await token guard.
