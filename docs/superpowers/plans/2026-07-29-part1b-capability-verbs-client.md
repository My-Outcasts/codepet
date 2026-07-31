# Part 1B (client) — Capability Verbs Receiver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the native client to receive and dispatch two new companion-reply verbs — `re_plan` and `walkthrough` — routing them to existing app actions (`generateRoadmap`, `walkThroughTask`).

**Architecture:** Purely additive extension of the existing reply contract (`CompanyChatResponse` / `CompanyChatReply` / `ChatDoneAction` / the SSE `done` payload) plus two new guarded handlers in `CompanyStore.handleDoneAction`. No Cloud Function change — the companyChat CF that would *emit* these verbs lives in another repo (`Murror/CodePet-Clean` → devpet-8f4b1), so this "receiver" ships no production behavior until that CF change (Plan 1B-server) lands; it is validated here via the offline `MockChat` testbed and unit tests.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild. No new dependencies.

## Scope

This is **1B-client** only. Part 1B decomposes into:
- **1B-client (this plan):** the receiver — parse + dispatch `re_plan` and `walkthrough`.
- **1B-server (deferred, other repo):** make the companyChat CF emit these verbs. Not in this repo/session.

Verbs `open` and `redo` from the Part 1 map are **deferred** — they have no clean existing target (`open` would duplicate the `nav` verb without a new library item-selection hook; `redo` needs a new "re-generate an approved deliverable" action, since `runTask` no-ops on done/drafted tasks and `redoDraft` is chat-draft-scoped). They belong to a dedicated slice that builds those library actions first. `edit_code` and `query` are out of scope (Part 2 / server-side context respectively).

## Global Constraints

- Native macOS SwiftUI app; scheme `codepet` (lowercase); `@testable import codepet`; XCTest.
- **Purely additive / no wire regression.** Existing verbs (`run_task_id`, `nav`, `setup`, `remember`) and their tests must be unchanged. New fields are optional and default to "absent" so older CF responses (and existing tests) decode and behave exactly as before.
- **Mutual-exclusivity unchanged for the existing three work verbs.** `re_plan` and `walkthrough` are new optional fields; the client dispatches whatever is present (the CF is responsible for sending at most one work verb per reply). Do not add client-side rejection logic.
- **Account guard.** Every new handler re-checks `companyId == cid` before mutating, exactly like `handleNav`/`handleSetup`/`handleRemember`.
- **Follow existing DTO style:** `Codable, Equatable`, snake_case via `CodingKeys` (mirror `NavAction`/`SetupAction`), defaulted initializers so existing call sites keep compiling.
- Build/test signing (repo memory): `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`.
- **Before `xcodebuild test`, close any running `codepet.app`** (`ps aux | grep codepet.app`) — it holds the Firestore lock and aborts the host. Also: tests that boot real Firestore (`CompanyStoreChatTests`) crash the shared host under Xcode 26 (documented flake). Both test files below are designed to avoid that: `CompanyChatClientTests` uses a mocked URLProtocol (no Firestore), and the dispatch tests follow the `CompanyStoreFanOutTests` pattern (injected fakes, no live Firestore).
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Modify** `codepet/Services/CompanyChatClient.swift` — add `WalkthroughAction` DTO; add `rePlan`/`walkthrough` to `CompanyChatResponse`, `CompanyChatReply`, `ChatDoneAction`, and the SSE `DonePayload`; populate them in `send(_:)` and `handleStreamFrame`.
- **Modify** `codepet/Managers/CompanyStore.swift` — add `handleRePlan` + `handleWalkthrough`; call them from `handleDoneAction`; extend the non-streaming fallback `ChatDoneAction` build (~line 667) to carry the new fields.
- **Modify** `codepet/Services/MockChat.swift` — add a "walk me through" route emitting a `walkthrough` action, so the offline testbed exercises the dispatch.
- **Modify** `codepetTests/CompanyChatClientTests.swift` — decode tests for the two new verbs (JSON + SSE).
- **Create** `codepetTests/CompanyStoreVerbDispatchTests.swift` — dispatch tests (injected-store, FanOut-style).

---

## Task 1: Extend the reply contract with `re_plan` + `walkthrough`

**Files:**
- Modify: `codepet/Services/CompanyChatClient.swift`
- Test: `codepetTests/CompanyChatClientTests.swift`

**Interfaces:**
- Produces:
  - `struct WalkthroughAction: Codable, Equatable { let taskId: String }` (JSON key `task_id`)
  - `ChatDoneAction` gains `let rePlan: Bool` and `let walkthrough: WalkthroughAction?` (init defaults `rePlan: false`, `walkthrough: nil`)
  - `CompanyChatReply` gains the same two (same defaults)
  - `CompanyChatResponse` gains `let rePlan: Bool?` (key `re_plan`) and `let walkthrough: WalkthroughAction?`

- [ ] **Step 1: Write the failing decode tests**

Add to `codepetTests/CompanyChatClientTests.swift` (inside the class):

```swift
    func testResponseDecodesRePlanAndWalkthrough() throws {
        let data = "{\"reply\":\"Let's re-plan\",\"re_plan\":true,\"walkthrough\":{\"task_id\":\"t7\"}}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertEqual(r.rePlan, true)
        XCTAssertEqual(r.walkthrough, WalkthroughAction(taskId: "t7"))
    }

    func testResponseDefaultsWhenVerbsAbsent() throws {
        let data = "{\"reply\":\"hi\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertNil(r.rePlan)
        XCTAssertNil(r.walkthrough)
    }

    func testSendStreamDoneCarriesRePlanAndWalkthrough() async throws {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseChunks = [
            "event: done\ndata: {\"model\":\"m\",\"cache_hit\":false,\"re_plan\":true,\"walkthrough\":{\"task_id\":\"t7\"}}\n\n".data(using: .utf8)!
        ]
        var collected: [CompanyChatStreamEvent] = []
        for try await ev in CompanyChatClient.sendStream(
            makeMinimalRequest(), session: mockedCompanyChatSession(), authTokenProvider: { "fake" }
        ) { collected.append(ev) }
        guard case let .done(_, _, action) = collected.last else { return XCTFail("expected .done") }
        XCTAssertTrue(action.rePlan)
        XCTAssertEqual(action.walkthrough, WalkthroughAction(taskId: "t7"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
ps aux | grep -i codepet.app | grep -v grep    # ensure app is closed
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyChatClientTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: FAIL — `WalkthroughAction` / `rePlan` unknown; compile error.

- [ ] **Step 3: Add the DTO and contract fields**

In `codepet/Services/CompanyChatClient.swift`:

3a. Add the DTO next to `SetupAction` (after the `struct SetupAction` block):

```swift
/// A "walk me through this myself" request from byte — the roadmap task id the
/// founder should be guided through. Resolved to a `RoadmapTask` by CompanyStore.
struct WalkthroughAction: Codable, Equatable {
    let taskId: String
    enum CodingKeys: String, CodingKey { case taskId = "task_id" }
}
```

3b. In `struct CompanyChatResponse`, add the two properties and their coding keys:

```swift
    let rePlan: Bool?
    let walkthrough: WalkthroughAction?
```
and in its `CodingKeys` add:
```swift
        case rePlan = "re_plan"
        case walkthrough
```

3c. In `struct CompanyChatReply`, add:
```swift
    let rePlan: Bool
    let walkthrough: WalkthroughAction?
```
and extend its `init` signature with `rePlan: Bool = false, walkthrough: WalkthroughAction? = nil` (place them after `remember`), assigning both.

3d. In `struct ChatDoneAction`, add:
```swift
    let rePlan: Bool
    let walkthrough: WalkthroughAction?
```
and extend its `init` with `rePlan: Bool = false, walkthrough: WalkthroughAction? = nil` (after `remember`), assigning both.

3e. In `send(_:)`, extend the returned `CompanyChatReply`:
```swift
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId, nav: decoded.nav,
                                 setup: decoded.setup, remember: decoded.remember ?? [],
                                 rePlan: decoded.rePlan ?? false, walkthrough: decoded.walkthrough)
```

3f. In `handleStreamFrame`, extend the private `DonePayload` struct with:
```swift
                let rePlan: Bool?
                let walkthrough: WalkthroughAction?
```
add to its `CodingKeys`:
```swift
                    case rePlan = "re_plan"; case walkthrough
```
and extend the `ChatDoneAction` it builds:
```swift
                let action = ChatDoneAction(runTaskId: d.runTaskId, nav: d.nav, setup: d.setup,
                                             remember: d.remember ?? [],
                                             rePlan: d.rePlan ?? false, walkthrough: d.walkthrough)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyChatClientTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: PASS — the new tests plus all pre-existing `CompanyChatClientTests` green (proves additive/no-regression).

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/CompanyChatClient.swift codepetTests/CompanyChatClientTests.swift
git commit -F - <<'EOF'
feat(chat): parse re_plan + walkthrough reply verbs (Bus Layer 2 receiver)

Additive: new optional fields on CompanyChatResponse/Reply/ChatDoneAction
and the SSE done payload; existing verbs untouched. No CF change — the
emitting CF lands in a later 1B-server plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: Dispatch `re_plan` + `walkthrough` in `CompanyStore`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreVerbDispatchTests.swift` (create)

**Interfaces:**
- Consumes: `ChatDoneAction.rePlan` / `.walkthrough` (Task 1); existing `generateRoadmap(language:)`, `walkThroughTask(_:language:)`, injectable `chatStreamer`/`roadmapFetcher` (CompanyStore init).
- Produces: `handleRePlan(_:cid:language:)`, `handleWalkthrough(_:cid:language:)` (private), called from `handleDoneAction`.

- [ ] **Step 1: Write the failing dispatch tests**

Create `codepetTests/CompanyStoreVerbDispatchTests.swift`:

```swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreVerbDispatchTests: XCTestCase {

    /// Seed + injected fakes, mirroring CompanyStoreFanOutTests: no live Firestore.
    private func store(tasks: [RoadmapTask],
                       streamer: @escaping (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error>,
                       roadmapFetcher: @escaping (CompanyBrief, AppLanguage) async -> [RoadmapTask] = { _, _ in [] }
    ) -> CompanyStore {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: tasks)
        return CompanyStore(loader: { _ in seed },
                            roadmapFetcher: roadmapFetcher,
                            tasksSaver: { _, _ in true },
                            chatStreamer: streamer,
                            librarySaver: { _, _ in true },
                            threadSaver: { _, _ in true },
                            threadsLoader: { _ in [] })
    }

    /// A stream that yields exactly one `.done` with the given action, then finishes.
    private func doneStream(_ action: ChatDoneAction) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        AsyncThrowingStream { c in
            c.yield(.delta("ok"))
            c.yield(.done(model: "m", cacheHit: false, action: action))
            c.finish()
        }
    }

    func testRePlanRegeneratesRoadmap() async {
        let fresh = [RoadmapTask(id: "n1", title: "New plan task", detail: "", phase: .build, who: .you)]
        let s = store(tasks: [RoadmapTask(id: "old", title: "Old", detail: "", phase: .find, who: .you)],
                      streamer: { _ in self.doneStream(ChatDoneAction(rePlan: true)) },
                      roadmapFetcher: { _, _ in fresh })
        await s.hydrate(companyId: "u")
        await s.sendChat("please re-plan", language: .en)
        XCTAssertEqual(s.company.tasks.map(\.id), ["n1"], "re_plan should replace tasks via roadmapFetcher")
    }

    func testWalkthroughUnknownIdIsNoOp() async {
        let s = store(tasks: [RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you)],
                      streamer: { _ in self.doneStream(ChatDoneAction(walkthrough: WalkthroughAction(taskId: "nope"))) })
        await s.hydrate(companyId: "u")
        let before = s.chatMessages.count
        await s.sendChat("hi", language: .en)
        // One user msg + one companion placeholder for THIS send; no extra walkthrough turn.
        XCTAssertEqual(s.chatMessages.filter { $0.role == .me }.count, 1,
                       "unknown walkthrough id must not start a second founder turn")
        _ = before
    }

    func testWalkthroughKnownIdStartsGuidedTurn() async {
        var calls = 0
        // First send → done(walkthrough t2). The nested walkThroughTask send → plain text.
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
            calls += 1
            if calls == 1 { return self.doneStream(ChatDoneAction(walkthrough: WalkthroughAction(taskId: "t2"))) }
            return AsyncThrowingStream { c in c.yield(.delta("Here's how")); c.finish() }
        }
        let s = store(tasks: [RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you)],
                      streamer: streamer)
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertTrue(s.chatMessages.contains { $0.role == .me && $0.text.contains("Pick a name") },
                      "known walkthrough id should start the guided 'walk me through … Pick a name' turn")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyStoreVerbDispatchTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: FAIL — `re_plan`/`walkthrough` are parsed but not dispatched, so `testRePlanRegeneratesRoadmap` and `testWalkthroughKnownIdStartsGuidedTurn` fail their assertions.

- [ ] **Step 3: Add the two handlers and wire them**

In `codepet/Managers/CompanyStore.swift`, extend `handleDoneAction` (after the `handleRemember` line):

```swift
        await handleRemember(action.remember, cid: cid)
        guard companyId == cid else { return }
        await handleRePlan(action.rePlan, cid: cid, language: language)
        guard companyId == cid else { return }
        await handleWalkthrough(action.walkthrough, cid: cid, language: language)
```

Add the two handlers immediately after `handleRemember(_:cid:)`:

```swift
    /// `re_plan`: regenerate the roadmap for the current brief/stage — the same
    /// effect as the manual "Re-plan for my stage" action. Guarded by cid.
    private func handleRePlan(_ rePlan: Bool, cid: String?, language: AppLanguage) async {
        guard rePlan, companyId == cid else { return }
        await generateRoadmap(language: language)
    }

    /// `walkthrough`: byte offers to guide the founder through a specific task —
    /// resolve the task id and start the same guided chat turn `walkThroughTask`
    /// produces. No-op on an unknown/stale id.
    private func handleWalkthrough(_ action: WalkthroughAction?, cid: String?, language: AppLanguage) async {
        guard let action, companyId == cid,
              let task = company.tasks.first(where: { $0.id == action.taskId }) else { return }
        await walkThroughTask(task, language: language)
    }
```

Then extend the non-streaming fallback `ChatDoneAction` build (~line 667) so the fallback path dispatches the new verbs too:

```swift
            let action = ChatDoneAction(runTaskId: reply?.runTaskId, nav: reply?.nav,
                                         setup: reply?.setup, remember: reply?.remember ?? [],
                                         rePlan: reply?.rePlan ?? false, walkthrough: reply?.walkthrough)
```

- [ ] **Step 4: Run to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyStoreVerbDispatchTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: PASS — 3/3. (If 0 tests + `** TEST FAILED **`, that's the Firestore host flake — confirm no `codepet.app` is running and re-run; these tests use injected fakes so they should execute like `CompanyStoreFanOutTests`.)

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreVerbDispatchTests.swift
git commit -F - <<'EOF'
feat(chat): dispatch re_plan + walkthrough reply verbs

handleDoneAction now routes re_plan → generateRoadmap and walkthrough →
walkThroughTask (resolved by task id, cid-guarded, no-op on unknown id).
Fallback path carries the new verbs too.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 3: Exercise the verbs in the offline `MockChat` testbed

**Files:**
- Modify: `codepet/Services/MockChat.swift`

**Interfaces:**
- Consumes: `ChatDoneAction(walkthrough:)` (Task 1), the mock router's `(text, ChatDoneAction)` return shape.
- Produces: a "walk me through" route so the mock testbed (`-CODEPET_MOCK_CHAT YES`) drives a real `walkthrough` dispatch end-to-end.

Only `walkthrough` is added to the mock. `re_plan` is intentionally left out of `MockChat` because it triggers `generateRoadmap` → `roadmapFetcher`, which isn't a canned mock path; `re_plan` dispatch is covered by the Task 2 unit test instead.

- [ ] **Step 1: Add the route**

In `codepet/Services/MockChat.swift`, inside `route(_:)`, add a branch (near the existing "remember"/"roadmap" branches) BEFORE the generic fallback. Match the walkthrough phrase and pick the first founder-eligible open task from the request context if available, else a fixed id:

```swift
        // "walk me through …" / "hướng dẫn mình …" → a walkthrough action.
        if lower.contains("walk me through") || lower.contains("hướng dẫn mình") {
            let taskId = req.runnable.first?.id ?? "t2"
            return ("Happy to guide you through it step by step.",
                    ChatDoneAction(walkthrough: WalkthroughAction(taskId: taskId)))
        }
```

(Use the same lowercased request text the other branches use — reuse the existing `lower`/`text` local in `route`; if the function computes it under a different name, match that name.)

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (No unit test — `MockChat` is a DEBUG-only dev harness; the dispatch it drives is already covered by Task 2's tests.)

- [ ] **Step 3: Commit**

```bash
git add codepet/Services/MockChat.swift
git commit -F - <<'EOF'
test(chat): MockChat emits a walkthrough action for the offline testbed

Lets `-CODEPET_MOCK_CHAT YES` drive a real walkthrough dispatch end to end
without the (other-repo) companyChat CF.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (Part 1 Layer 2, client receiver):**
- `re_plan` verb parsed + dispatched → `generateRoadmap` (Tasks 1, 2). ✅
- `walkthrough` verb parsed (+ `task_id`) + dispatched → `walkThroughTask` by resolved task, cid-guarded, no-op on unknown id (Tasks 1, 2). ✅
- Additive / existing verbs unchanged → new fields optional with defaults; pre-existing `CompanyChatClientTests` re-run green in Task 1 Step 4. ✅
- `open`/`redo`/`edit_code`/`query` → explicitly deferred/out-of-scope (see Scope). Not gaps.
- 1B-server (CF emission) → explicitly deferred to another repo/plan. Not a gap.

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has expected output.

**3. Type consistency:** `WalkthroughAction`/`taskId`(`task_id`), `rePlan`, `walkthrough`, `handleRePlan`, `handleWalkthrough`, and the extended `ChatDoneAction`/`CompanyChatReply`/`CompanyChatResponse`/`DonePayload` initializers are named identically across Tasks 1–3. Dispatch tests inject `chatStreamer`/`roadmapFetcher`, matching the real `CompanyStore.init` signature. The `.done(model:cacheHit:action:)` event shape matches `CompanyChatStreamEvent`.

**Note for the executor:** the `walkthrough` handler calls `walkThroughTask`, which itself starts a chat send (consuming `chatStreamer` again). In production the CF replies to that follow-up turn with guidance, not another walkthrough, so there's no loop; the Task 2 test models this with a call-count streamer. Do not add client-side recursion guards (YAGNI) unless a test shows a real loop.
