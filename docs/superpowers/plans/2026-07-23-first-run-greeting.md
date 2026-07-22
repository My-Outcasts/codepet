# First-run chat greeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed a companion chat greeting at onboarding finish that names the best first move and offers a one-tap "Do it with me" action producing an inline draft deliverable — the native port of the web `greetFirstRun`.

**Architecture:** A pure greeting builder (`FirstRunGreetingBuilder`) turns the brief + `RoadmapEngine.nextStep` into text + an optional action. `CompanyStore.finishOnboarding` seeds it as a companion `CopilotMessage`; `CopilotMessage` gains an additive action field; `CopilotBubble` renders the action button, which calls `CompanyStore.runFirstRunAction` — reusing the existing 6C `runTask`/`buildDeliverable`/draft-card path.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS app in `~/Documents/codepet-rebuild-wt`.

## Global Constraints

- **Build (foreground):** `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` — never background xcodebuild (subagents stall on backgrounded jobs).
- **Scoped test:** `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<TestClass>`
- **Commit (iCloud worktree):** stage, then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (a bare `git commit -m` can hang; `rm -f .git/index.lock` first if it does).
- **Tests import** `@testable import codepet`; store tests are `@MainActor`.
- **Copy:** English + Vietnamese, both provided verbatim below. Onboarding display is English-only, but the greeting is localized by the live UI language.
- **SourceKit diagnostics** in this worktree show false "Cannot find … in scope" errors (no built index) — trust `xcodebuild`, not the editor squiggles.

---

### Task 1: Pure greeting builder

**Files:**
- Create: `codepet/Models/FirstRunGreeting.swift`
- Test: `codepetTests/FirstRunGreetingTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (`founderName`, `projectName`), `RoadmapTask` (`id`, `title`), `AppLanguage` (`.en`/`.vi`) — all existing.
- Produces:
  - `struct FirstRunAction: Equatable { let taskId: String; let taskTitle: String }`
  - `struct FirstRunGreeting: Equatable { let text: String; let action: FirstRunAction? }`
  - `enum FirstRunGreetingBuilder { static func build(brief: CompanyBrief, nextStep: RoadmapTask?, language: AppLanguage) -> FirstRunGreeting }`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/FirstRunGreetingTests.swift`:

```swift
import XCTest
@testable import codepet

final class FirstRunGreetingTests: XCTestCase {
    private func task(_ id: String, _ title: String) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .find, who: .does)
    }

    func testNameAndNextStepProducesAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: task("t1", "Write your landing page"), language: .en)
        XCTAssertTrue(g.text.hasPrefix("Mona, your company for Codepet is ready."))
        XCTAssertTrue(g.text.contains("The best first move is \"Write your landing page\"."))
        XCTAssertEqual(g.action, FirstRunAction(taskId: "t1", taskTitle: "Write your landing page"))
    }

    func testNoNameFallsBackToGenericLead() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(projectName: "Codepet"),
            nextStep: task("t1", "X"), language: .en)
        XCTAssertTrue(g.text.hasPrefix("Your company for Codepet is ready."))
    }

    func testNoProjectNameUsesPlaceholder() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona"), nextStep: nil, language: .en)
        XCTAssertTrue(g.text.contains("your product"))
    }

    func testNoNextStepHasNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, language: .en)
        XCTAssertNil(g.action)
        XCTAssertTrue(g.text.contains("Take a look around"))
    }

    func testVietnameseLeadNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, language: .vi)
        XCTAssertTrue(g.text.contains("đã sẵn sàng"))
        XCTAssertNil(g.action)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FirstRunGreetingTests 2>&1 | grep -E "error:|BUILD FAILED"`
Expected: build FAILS — `FirstRunGreetingBuilder` / `FirstRunGreeting` / `FirstRunAction` not found.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/FirstRunGreeting.swift`:

```swift
// codepet/Models/FirstRunGreeting.swift
import Foundation

/// The one-tap "Do it with me: {task}" action carried by the first-run greeting.
struct FirstRunAction: Equatable {
    let taskId: String
    let taskTitle: String
}

/// The first-run greeting: byte's opening message + an optional inline action.
struct FirstRunGreeting: Equatable {
    let text: String
    let action: FirstRunAction?
}

/// Pure builder — verbatim-logic port of the web `buildFirstRunGreeting`
/// (lib/onboarding/firstRun.ts). No I/O; unit-tested.
enum FirstRunGreetingBuilder {
    static func build(brief: CompanyBrief, nextStep: RoadmapTask?, language: AppLanguage) -> FirstRunGreeting {
        let who = (brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let projRaw = (brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let proj = projRaw.isEmpty ? (language == .vi ? "sản phẩm của bạn" : "your product") : projRaw

        let lead: String
        if who.isEmpty {
            lead = language == .vi
                ? "Công ty cho \(proj) đã sẵn sàng."
                : "Your company for \(proj) is ready."
        } else {
            lead = language == .vi
                ? "\(who), công ty cho \(proj) đã sẵn sàng."
                : "\(who), your company for \(proj) is ready."
        }

        guard let task = nextStep else {
            let tail = language == .vi
                ? " Cứ khám phá xung quanh — mở bất kỳ phần nào trong công ty để xem mình đã chuẩn bị gì, và mình sẽ làm cùng bạn khi bạn sẵn sàng."
                : " Take a look around — open any part of your company to see what I've lined up, and I'll produce the work with you whenever you're ready."
            return FirstRunGreeting(text: lead + tail, action: nil)
        }

        let tail = language == .vi
            ? " Bước đầu tốt nhất là \"\(task.title)\". Bạn muốn mình làm cùng bạn ngay tại đây chứ? Mình soạn bản nháp, bạn duyệt — không có gì được xuất bản nếu bạn chưa đồng ý."
            : " The best first move is \"\(task.title)\". Want me to do it with you, right here? I'll draft it and you approve — nothing ships without your say-so."
        return FirstRunGreeting(text: lead + tail,
                                action: FirstRunAction(taskId: task.id, taskTitle: task.title))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FirstRunGreetingTests 2>&1 | grep -E "Test Case.*passed|failed|\*\* TEST"`
Expected: all `FirstRunGreetingTests` cases pass.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt && rm -f .git/index.lock
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/FirstRunGreeting.swift codepetTests/FirstRunGreetingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat(greeting): pure first-run greeting builder + tests"
```

---

### Task 2: Seed the greeting at onboarding finish

**Files:**
- Modify: `codepet/Models/CopilotMessage.swift` (add `firstRunAction`, `actionConsumed`)
- Modify: `codepet/Managers/CompanyStore.swift` (`finishOnboarding` language arg + `seedFirstRunGreeting`)
- Modify: `codepet/Views/Onboarding/OnboardingView.swift` (`finishWithCompanion` passes language)
- Test: `codepetTests/CompanyStoreFirstRunGreetingTests.swift`

**Interfaces:**
- Consumes: `FirstRunGreetingBuilder.build` (Task 1); `RoadmapEngine.nextStep(_:) -> RoadmapTask?`; existing `CompanyStore` state (`company`, `companyId`, `hydrationToken`, `chatMessages`, `saver`).
- Produces:
  - `CopilotMessage.firstRunAction: FirstRunAction?`, `CopilotMessage.actionConsumed: Bool` (both default nil/false).
  - `CompanyStore.finishOnboarding(brief:token:language:)` — `language` defaults `.en`.
  - `CompanyStore.seedFirstRunGreeting(language:)` (private).

- [ ] **Step 1: Write the failing test**

Create `codepetTests/CompanyStoreFirstRunGreetingTests.swift`:

```swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreFirstRunGreetingTests: XCTestCase {
    private func seeded(tasks: [RoadmapTask], brief: CompanyBrief) -> CompanyState {
        CompanyState(brief: brief, departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: nil, tasks: tasks)
    }

    func testFinishSeedsGreetingWithActionFromNextStep() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        let m = s.chatMessages[0]
        XCTAssertEqual(m.role, .companion)
        XCTAssertTrue(m.text.contains("Write your landing page"))
        XCTAssertEqual(m.firstRunAction?.taskId, "t1")
        XCTAssertFalse(m.actionConsumed)
    }

    func testFinishWithNoTasksSeedsGreetingWithoutAction() async {
        let state = seeded(tasks: [], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertNil(s.chatMessages[0].firstRunAction)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests 2>&1 | grep -E "error:|BUILD FAILED"`
Expected: build FAILS — `finishOnboarding` has no `language:` label, `firstRunAction` unknown.

- [ ] **Step 3a: Add the CopilotMessage fields**

In `codepet/Models/CopilotMessage.swift`, replace the struct body:

```swift
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    let text: String
    var draft: Deliverable?
    var draftApproved: Bool
    /// First-run "Do it with me" action (greeting message only); nil otherwise.
    var firstRunAction: FirstRunAction?
    /// True once the action has been tapped — hides the button.
    var actionConsumed: Bool

    init(id: String = UUID().uuidString, role: CopilotRole, text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false,
         firstRunAction: FirstRunAction? = nil, actionConsumed: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.draft = draft
        self.draftApproved = draftApproved
        self.firstRunAction = firstRunAction
        self.actionConsumed = actionConsumed
    }
}
```

- [ ] **Step 3b: Add the language arg + seed to finishOnboarding**

In `codepet/Managers/CompanyStore.swift`, replace `finishOnboarding`:

```swift
    func finishOnboarding(brief: CompanyBrief, token: Int, language: AppLanguage = .en) async {
        guard token == hydrationToken, let cid = companyId else { return }
        _ = await saver(cid, brief)
        guard token == hydrationToken else { return }
        company.brief = brief
        company.onboardedAt = Date()
        isOnboarding = false
        seedFirstRunGreeting(language: language)
    }

    /// Seed byte's first-run greeting (name + best first move + optional inline action)
    /// as one companion message. Called once, at the onboarding→app edge.
    private func seedFirstRunGreeting(language: AppLanguage) {
        guard companyId != nil else { return }
        let next = RoadmapEngine.nextStep(company.tasks)
        let g = FirstRunGreetingBuilder.build(brief: company.brief, nextStep: next, language: language)
        chatMessages.append(CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action))
    }
```

- [ ] **Step 3c: Pass the live language from OnboardingView**

In `codepet/Views/Onboarding/OnboardingView.swift`, in `finishWithCompanion`, change the finish call:

```swift
            await companyStore.finishOnboarding(brief: brief(), token: token, language: appState.uiLanguage)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests 2>&1 | grep -E "Test Case.*passed|failed|\*\* TEST"`
Expected: both cases pass.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt && rm -f .git/index.lock
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/CopilotMessage.swift codepet/Managers/CompanyStore.swift codepet/Views/Onboarding/OnboardingView.swift codepetTests/CompanyStoreFirstRunGreetingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat(greeting): seed first-run greeting at onboarding finish"
```

---

### Task 3: Run the inline action → draft card

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (`runFirstRunAction`)
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (`CopilotBubble` action button)
- Test: `codepetTests/CompanyStoreFirstRunGreetingTests.swift` (add a case)

**Interfaces:**
- Consumes: `CopilotMessage.firstRunAction`/`actionConsumed` (Task 2); existing `runRequest(for:language:)`, `taskRunner`, `buildDeliverable(from:task:)`, `runningTaskIds`, `companyId`.
- Produces: `CompanyStore.runFirstRunAction(messageId:language:)`.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/CompanyStoreFirstRunGreetingTests.swift` (inside the class):

```swift
    func testRunFirstRunActionAppendsDraftAndConsumes() async {
        let t = RoadmapTask(id: "t1", title: "Landing page", detail: "d", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Landing page", body: "# Hello") })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        let greetingId = s.chatMessages[0].id
        await s.runFirstRunAction(messageId: greetingId, language: .en)
        XCTAssertTrue(s.chatMessages[0].actionConsumed)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages[1].draft?.body, "# Hello")
    }

    func testRunFirstRunActionIsIdempotentOnceConsumed() async {
        let t = RoadmapTask(id: "t1", title: "Landing page", detail: "d", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        let id = s.chatMessages[0].id
        await s.runFirstRunAction(messageId: id, language: .en)
        await s.runFirstRunAction(messageId: id, language: .en)   // second call is a no-op
        XCTAssertEqual(s.chatMessages.count, 2)                    // greeting + one draft only
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests 2>&1 | grep -E "error:|BUILD FAILED"`
Expected: build FAILS — `runFirstRunAction` not found.

- [ ] **Step 3a: Add runFirstRunAction to CompanyStore**

In `codepet/Managers/CompanyStore.swift`, add after `runTask(_:language:)`:

```swift
    /// Run the greeting's "Do it with me" task → append an inline draft (reuses the 6C
    /// run path). Marks the action consumed (optimistic, idempotent); in-flight +
    /// account-switch guarded; fail-open honest message on a nil result.
    func runFirstRunAction(messageId: String, language: AppLanguage) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let action = chatMessages[i].firstRunAction,
              !chatMessages[i].actionConsumed,
              let task = company.tasks.first(where: { $0.id == action.taskId }),
              !runningTaskIds.contains(task.id) else { return }
        chatMessages[i].actionConsumed = true
        runningTaskIds.insert(task.id)
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        if let draft = buildDeliverable(from: result, task: task) {
            chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft))
        } else {
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không tạo được ngay bây giờ — thử lại nhé."
                : "Couldn't generate that just now — try again."))
        }
    }
```

- [ ] **Step 3b: Render the action button in CopilotBubble**

In `codepet/Views/Copilot/CopilotChatView.swift`, replace `CopilotBubble.body`:

```swift
    var body: some View {
        if let draft = message.draft {
            draftCard(draft)
        } else if let action = message.firstRunAction, !message.actionConsumed {
            VStack(alignment: .leading, spacing: 8) {
                textBubble
                actionButton(action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            textBubble
        }
    }

    private func actionButton(_ action: FirstRunAction) -> some View {
        Button {
            Task { await companyStore.runFirstRunAction(messageId: message.id, language: lang) }
        } label: {
            Text((lang == .vi ? "Làm cùng mình: " : "Do it with me: ") + action.taskTitle)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.accentPurple))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 4: Run test + full build to verify**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests 2>&1 | grep -E "Test Case.*passed|failed|\*\* TEST"`
Expected: all cases pass.
Then: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: `** BUILD SUCCEEDED **` (CopilotBubble wiring compiles).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt && rm -f .git/index.lock
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepet/Views/Copilot/CopilotChatView.swift codepetTests/CompanyStoreFirstRunGreetingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat(greeting): 'Do it with me' inline action → draft card"
```

---

## Notes for the executor

- **Do NOT background xcodebuild** — run builds/tests in the foreground; backgrounded jobs stall.
- After all three tasks, the feature is complete: greeting seeds at onboarding finish, the action runs a task into an inline draft, Approve/Redo use the existing `approveDraft`/`redoDraft`.
- Runtime (real Firebase sign-in + CF) needs a signed build and is verified visually by the user; the plan's automated gate is the unit tests + `BUILD SUCCEEDED`.
