# Per-Message Action Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every assistant reply in the copilot chat one action row — copy, copy as Markdown, try again, 👍/👎, timestamp — revealed on hover with the last reply pinned.

**Architecture:** `CopilotBubble.body` splits into a thin wrapper plus a `content` property holding today's payload if-chain, so one row serves every branch instead of only `textBubble`. Three new pure types carry the logic that must be testable without the flaky Firebase test host: `MessageTranscript` (what the clipboard gets), `MessageActionRules` (when retry is allowed), `MessageFeedbackPayload` (what Firestore gets). The Firestore write reuses the `feedback` collection that is already live.

**Tech Stack:** Swift 5, SwiftUI, XCTest, FirebaseFirestore. macOS target 26.2.

## Global Constraints

- Branch `feat/message-action-row` off `main` at `554cb1e`. Do not commit to `main` directly.
- A concurrent session is working in this same checkout. `git status` will show files you did not touch (e.g. `codepet/Views/Overview/TaskNodePanel.swift`) — never `git add .`; stage only the paths each task names.
- Build signed: `xcodebuild build -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development"`. `CODE_SIGNING_ALLOWED=NO` builds run but break Firebase auth at runtime.
- Run tests per-suite with `-only-testing:` — the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates, so a full-suite run exits 65 on a clean checkout. That is landmine 3 in `CLAUDE.md`, not a regression.
- Test module import is `@testable import codepet` (lowercase).
- New `.swift` files need no `.xcodeproj` edit — `PBXFileSystemSynchronizedRootGroup` picks them up from disk. Do **not** run `xcodegen`.
- Every user-facing string is bilingual: English and `lang == .vi` Vietnamese, matching the existing `messageActions` strings.
- No Firestore rule change and no function deploy. `firestore.rules:37-43` already permits `create` on `feedback` for `{rating: int in 1...5, feature: string}`.
- Commit messages carry the reasoning — the why, the measurement, the rejected alternative.
- Spec: `docs/superpowers/specs/2026-08-11-message-action-row-design.md`.

---

### Task 1: `MessageTranscript` — what the clipboard actually gets

Copy today does `NSPasteboard.general.setString(message.text, ...)` (`CopilotChatView.swift:643`). On a draft-card reply `message.text` is frequently blank — `textBubble` even returns `EmptyView()` for that case (`:984-985`) — so the moment the row appears on card branches, copy would hand back an empty clipboard. This serializer reads the payload the branch actually rendered.

**Files:**
- Create: `codepet/Models/MessageTranscript.swift`
- Test: `codepetTests/MessageTranscriptTests.swift`

**Interfaces:**
- Consumes: `CopilotMessage` (`codepet/Models/CopilotMessage.swift:9`), `Deliverable` (`:292`, has `title`/`body`), `VirtualCompanyRunState.brief` → `VCBrief.recommendation` (`VirtualCompanyRun.swift:160`), `VCAgentMeta.departmentKey` (`:34`), `VCPosition.position` (`:79`), `ExecStep.label`/`.done` (`ExecStep.swift:28-29`), `RunProposal.line(_:)` (`RunProposal.swift:29`), `RoadmapProposal.line(_:)` (`RoadmapProposal.swift:34`), `EnrichInterview.question(for:language:)` → `InterviewQuestion.ask` (`EnrichInterview.swift:55`), `AppLanguage`.
- Produces: `MessageTranscript.plain(_ m: CopilotMessage, lang: AppLanguage) -> String` and `MessageTranscript.markdown(_ m: CopilotMessage, speaker: String, lang: AppLanguage) -> String`. Task 6 calls both.

- [ ] **Step 1: Confirm you are on the branch**

The branch was created when this plan was committed. Confirm rather than recreate — a second session may have moved `main` since.

```bash
cd /Users/monatruong/Developer/codepet
git fetch --prune origin
git rev-parse --abbrev-ref HEAD
git log --oneline -1
```

Expected: `feat/message-action-row`, with this plan as the tip commit. If you are somewhere else, `git checkout feat/message-action-row`.

- [ ] **Step 2: Write the failing tests**

Create `codepetTests/MessageTranscriptTests.swift`:

```swift
// codepetTests/MessageTranscriptTests.swift
import XCTest
@testable import codepet

/// Struct-only tests for the pure `MessageTranscript` serializer — no `CompanyStore`,
/// no `@MainActor`, no Firebase. The blank-text draft case is the bug this type exists
/// to prevent: `message.text` is empty on a draft-card reply, so copying it handed the
/// founder an empty clipboard.
final class MessageTranscriptTests: XCTestCase {

    private func reply(_ text: String) -> CopilotMessage {
        CopilotMessage(role: .companion, text: text)
    }

    // MARK: - plain

    func testPlainReturnsProseForAnOrdinaryReply() {
        let m = reply("Here is the pricing page copy.")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), "Here is the pricing page copy.")
    }

    func testPlainTrimsSurroundingWhitespace() {
        let m = reply("  Ready when you are.\n\n")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), "Ready when you are.")
    }

    /// The bug. A draft-card reply carries a blank `text`, so the old copy path
    /// produced "". The title and body must both survive.
    func testPlainOnADraftWithBlankTextIsNotEmpty() {
        var m = reply("")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(out.contains("Launch plan"))
        XCTAssertTrue(out.contains("Week 1: ship billing."))
    }

    func testPlainOnADraftKeepsProseAboveTheDraft() {
        var m = reply("I drafted this for you.")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.plain(m, lang: .en)
        let prose = out.range(of: "I drafted this for you.")
        let title = out.range(of: "Launch plan")
        XCTAssertNotNil(prose)
        XCTAssertNotNil(title)
        XCTAssertTrue(prose!.lowerBound < title!.lowerBound, "prose must come before the draft")
    }

    func testPlainOnARoomKeepsTheHandoffLineThenTheRecommendation() {
        var m = reply("This one needs the whole room.")
        var run = VirtualCompanyRunState()
        run.brief = VCBrief(recommendation: "Charge for the beta.",
                            confidence: 70, confidenceReason: "r",
                            theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                            killCriteria: [], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "u", unresolved: false)
        m.vcRun = run
        let out = MessageTranscript.plain(m, lang: .en)
        let handoff = out.range(of: "This one needs the whole room.")
        let rec = out.range(of: "Charge for the beta.")
        XCTAssertNotNil(handoff)
        XCTAssertNotNil(rec)
        XCTAssertTrue(handoff!.lowerBound < rec!.lowerBound)
    }

    func testPlainOnExecStepsListsThemWithDoneMarkers() {
        var m = reply("")
        m.execSteps = [ExecStep(label: "Read the brief", done: true),
                       ExecStep(label: "Draft the copy", done: false)]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("✓ Read the brief"))
        XCTAssertTrue(out.contains("• Draft the copy"))
    }

    func testPlainOnARunProposalUsesTheProposalSentence() {
        var m = reply("")
        m.runProposal = RunProposal(taskId: "t1", title: "Pricing page",
                                    deptName: "Marketing", companionId: "nova")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Let's do \"Pricing page\" in Marketing — ready when you are.")
    }

    func testPlainOnARoadmapProposalUsesTheProposalSentence() {
        var m = reply("")
        m.roadmapProposal = .complete(taskId: "t1", title: "Ship billing")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Want me to mark \"Ship billing\" done?")
    }

    func testPlainOnAnInterviewUsesTheQuestion() {
        var m = reply("")
        m.interview = .goal
        let expected = EnrichInterview.question(for: .goal, language: .en).ask
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), expected)
    }

    func testPlainHonoursVietnamese() {
        var m = reply("")
        m.roadmapProposal = .complete(taskId: "t1", title: "Ship billing")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .vi),
                       "Mình đánh dấu \"Ship billing\" là xong nhé?")
    }

    // MARK: - markdown

    func testMarkdownLeadsWithTheSpeaker() {
        let m = reply("Here is the copy.")
        let out = MessageTranscript.markdown(m, speaker: "Glitch · Engineering", lang: .en)
        XCTAssertTrue(out.hasPrefix("**Glitch · Engineering**"))
        XCTAssertTrue(out.contains("Here is the copy."))
    }

    func testMarkdownHeadsADraftWithItsTitle() {
        var m = reply("")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("## Launch plan"))
        XCTAssertTrue(out.contains("Week 1: ship billing."))
    }

    func testMarkdownRendersExecStepsAsATaskList() {
        var m = reply("")
        m.execSteps = [ExecStep(label: "Read the brief", done: true),
                       ExecStep(label: "Draft the copy", done: false)]
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("- [x] Read the brief"))
        XCTAssertTrue(out.contains("- [ ] Draft the copy"))
    }

    func testMarkdownOnARoomListsEachSeatsPosition() {
        var m = reply("")
        var run = VirtualCompanyRunState()
        run.brief = VCBrief(recommendation: "Charge for the beta.",
                            confidence: 70, confidenceReason: "r",
                            theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                            killCriteria: [], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "u", unresolved: false)
        run.agents = [VCAgentMeta(agentId: "a1", departmentKey: "finance")]
        run.positions = ["a1": VCPosition(stance: "proceed", position: "Price it at $20.",
                                          reasoning: "r", evidenceNeeded: [], risksIOwn: [],
                                          confidence: 60, costToMyDept: "c", hardBlocker: nil)]
        m.vcRun = run
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("Charge for the beta."))
        XCTAssertTrue(out.contains("**finance** — Price it at $20."))
    }

    func testMarkdownOnAnEmptyMessageIsJustTheSpeaker() {
        let out = MessageTranscript.markdown(reply(""), speaker: "Codepet", lang: .en)
        XCTAssertEqual(out, "**Codepet**")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageTranscriptTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'MessageTranscript' in scope`.

If instead a `VCBrief`, `VCNextAction`, `VCPosition` or `Deliverable` initializer fails to compile, the memberwise signature has drifted — read the type and fix the test's call, not the type.

- [ ] **Step 4: Write the implementation**

Create `codepet/Models/MessageTranscript.swift`:

```swift
// codepet/Models/MessageTranscript.swift
import Foundation

/// Serializes one chat message for the clipboard.
///
/// Copy used to send `message.text` straight to the pasteboard. That is correct only for
/// a plain-text reply: a draft-card, exec-log, room or proposal reply carries its content
/// in a payload and frequently has a blank `text` — `textBubble` renders `EmptyView()` for
/// exactly that case. Once the action row appears on those branches, copying `text` would
/// return "". So this reads the payloads in the same precedence order `CopilotBubble.content`
/// renders them, and text (when present) always leads, because that is what is on screen.
///
/// Pure by design: no SwiftUI, no Firebase, no `CompanyStore`. It is the half of the action
/// row that can be tested without the XCTest host that crashes on `@MainActor` deallocation.
enum MessageTranscript {

    /// Plain text for the Copy button.
    static func plain(_ m: CopilotMessage, lang: AppLanguage) -> String {
        blocks(m, lang: lang, markdown: false).joined(separator: "\n\n")
    }

    /// Markdown for the Copy as Markdown button, headed by who said it.
    static func markdown(_ m: CopilotMessage, speaker: String, lang: AppLanguage) -> String {
        (["**\(speaker)**"] + blocks(m, lang: lang, markdown: true))
            .joined(separator: "\n\n")
    }

    // MARK: - Blocks

    private static func blocks(_ m: CopilotMessage, lang: AppLanguage,
                               markdown: Bool) -> [String] {
        var out: [String] = []

        let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { out.append(text) }

        if let draft = m.draft {
            out.append(markdown ? "## \(draft.title)" : draft.title)
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out.append(body) }
        }

        if let run = m.vcRun {
            if let recommendation = run.brief?.recommendation
                .trimmingCharacters(in: .whitespacesAndNewlines), !recommendation.isEmpty {
                out.append(recommendation)
            }
            if markdown {
                for agent in run.agents {
                    guard let dept = agent.departmentKey,
                          let position = run.positions[agent.agentId]?.position
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !position.isEmpty else { continue }
                    out.append("**\(dept)** — \(position)")
                }
            }
        }

        if let steps = m.execSteps, !steps.isEmpty {
            out.append(steps.map { step in
                if markdown { return "- [\(step.done ? "x" : " ")] \(step.label)" }
                return "\(step.done ? "✓" : "•") \(step.label)"
            }.joined(separator: "\n"))
        }

        if let proposal = m.runProposal { out.append(proposal.line(lang)) }
        if let proposal = m.roadmapProposal { out.append(proposal.line(lang)) }
        if let gap = m.interview {
            out.append(EnrichInterview.question(for: gap, language: lang).ask)
        }

        return out
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageTranscriptTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 15 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/MessageTranscript.swift codepetTests/MessageTranscriptTests.swift
git commit -F- <<'EOF'
feat(chat): serialize the reply that is actually on screen

Copy sends message.text to the pasteboard (CopilotChatView.swift:643).
That is right for a plain-text reply and wrong for every other branch:
a draft, exec log, room or proposal carries its content in a payload and
routinely has a blank text — textBubble returns EmptyView() for exactly
that case (:984). The row is about to appear on those branches, so
without this the founder would copy a deliverable and get "".

MessageTranscript reads the payloads in the same precedence order
CopilotBubble renders them, with prose first because that is the reading
order on screen. Pure — no SwiftUI, no Firebase — so it is testable
without the XCTest host that crashes on @MainActor deallocation
(CLAUDE.md landmine 3). The blank-text-draft case has its own test.

Rejected: teaching the Copy button to switch on payload inline, which
would have put the same if-chain in a view that cannot be unit-tested.
EOF
```

---

### Task 2: `MessageActionRules` — when retry is allowed

`CompanyStore.retryReply` calls `chatMessages.removeSubrange(askIndex...)` (`CompanyStore.swift:1273`) — it drops the founder's question and every turn after it. That is safe today only because the button is effectively unreachable. Confining retry to the last reply makes the deletion equal to what the button visibly promises. The rule lives in a pure type so a test goes red if it is deleted, per the repo's working agreement.

**Files:**
- Create: `codepet/Models/MessageActionRules.swift`
- Test: `codepetTests/MessageActionRulesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `MessageActionRules.canRetry(isLast: Bool, isTyping: Bool, isStreaming: Bool) -> Bool`. Task 6 calls it.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MessageActionRulesTests.swift`:

```swift
// codepetTests/MessageActionRulesTests.swift
import XCTest
@testable import codepet

/// The guard that keeps `retryReply`'s destructive `removeSubrange(askIndex...)` honest.
/// If `isLast` is dropped from the rule these go red — which is the point: retry on an
/// older reply silently deletes every turn after it.
final class MessageActionRulesTests: XCTestCase {

    func testRetryIsAllowedOnTheLastIdleReply() {
        XCTAssertTrue(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false))
    }

    func testRetryIsRefusedOnAnOlderReply() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: false, isStreaming: false),
                       "retryReply drops every turn after the ask — an older reply must not offer it")
    }

    func testRetryIsRefusedWhileTyping() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: true, isStreaming: false))
    }

    func testRetryIsRefusedWhileStreaming() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: true))
    }

    func testRetryIsRefusedOnAnOlderReplyEvenWhenIdle() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: true, isStreaming: true))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageActionRulesTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'MessageActionRules' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/MessageActionRules.swift`:

```swift
// codepet/Models/MessageActionRules.swift
import Foundation

/// When a per-message action may be offered.
///
/// Extracted from the view for one reason: `CompanyStore.retryReply` walks back to the
/// preceding `.me` message and calls `removeSubrange(askIndex...)`, so retrying an OLDER
/// reply deletes the founder's question and every turn that followed it. That was harmless
/// while the action row was unreachable — the hover target was an invisible 22x20 strip —
/// and stops being harmless the moment the row is pinned to the last reply.
///
/// Confining retry to the last reply makes the deletion equal to what the button promises:
/// your last question and its answer, re-asked. It is a rule rather than an inline
/// `.disabled` condition so a test goes red when someone deletes it.
enum MessageActionRules {
    static func canRetry(isLast: Bool, isTyping: Bool, isStreaming: Bool) -> Bool {
        isLast && !isTyping && !isStreaming
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageActionRulesTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/MessageActionRules.swift codepetTests/MessageActionRulesTests.swift
git commit -F- <<'EOF'
feat(chat): confine retry to the last reply

retryReply walks back to the preceding .me message and calls
removeSubrange(askIndex...) (CompanyStore.swift:1273) — retrying an
older reply deletes the founder's question and every turn after it.
Harmless while the button was unreachable behind an invisible 22x20
hover strip; a data-loss footgun the moment the row gets pinned.

Confined to the last reply, that removeSubrange deletes exactly what
the button promises. The rule is a pure type, not an inline .disabled
condition, so a test goes red when it is deleted — the repo's rule that
a guard without a failing test is not protecting anything.

Rejected: a confirm sheet on older replies (a modal in a row whose whole
point is to stay quiet), and a non-destructive in-place replace, which
leaves later turns answering a reply that no longer exists.
EOF
```

---

### Task 3: `MessageVote` on the model and `CompanyStore.recordVote`

The chosen thumb has to stay filled as the founder scrolls. `@State` in `CopilotBubble` will not do it — SwiftUI drops view state as rows recycle — so the vote lives on the message. `chatMessages` is `@Published private(set)` (`CompanyStore.swift:28`), so the mutation must be a store method.

**Files:**
- Modify: `codepet/Models/CopilotMessage.swift` (add `MessageVote` + `vote` field)
- Modify: `codepet/Managers/CompanyStore.swift` (add `recordVote`, near `retryReply` at `:1262`)
- Test: `codepetTests/MessageVoteTests.swift`

**Interfaces:**
- Consumes: `CopilotMessage`, `CompanyStore.chatMessages`.
- Produces: `enum MessageVote { case up, down }`; `CopilotMessage.vote: MessageVote?`; `CompanyStore.recordVote(messageId: String, vote: MessageVote)`. Task 6 calls `recordVote` and reads `message.vote`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MessageVoteTests.swift`:

```swift
// codepetTests/MessageVoteTests.swift
import XCTest
@testable import codepet

/// The vote lives on the message, not in `@State`, because SwiftUI drops view state as
/// rows recycle during scrolling — the founder would watch their thumb disappear.
@MainActor
final class MessageVoteTests: XCTestCase {

    func testVoteDefaultsToNil() {
        XCTAssertNil(CopilotMessage(role: .companion, text: "hi").vote)
    }

    func testVoteIsCarriedByTheInitializer() {
        XCTAssertEqual(CopilotMessage(role: .companion, text: "hi", vote: .up).vote, .up)
    }

    func testRecordVoteSetsTheVoteOnTheNamedMessage() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([
            CopilotMessage(id: "a", role: .me, text: "ask"),
            CopilotMessage(id: "b", role: .companion, text: "answer")
        ])
        store.recordVote(messageId: "b", vote: .down)
        XCTAssertEqual(store.chatMessages[1].vote, .down)
        XCTAssertNil(store.chatMessages[0].vote, "the other message must be untouched")
    }

    /// The rule denies `update`, so a correction writes a second doc rather than editing
    /// the first — but the UI must still show the corrected thumb.
    func testRecordVoteReplacesAnEarlierVote() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([CopilotMessage(id: "b", role: .companion, text: "answer")])
        store.recordVote(messageId: "b", vote: .up)
        store.recordVote(messageId: "b", vote: .down)
        XCTAssertEqual(store.chatMessages[0].vote, .down)
    }

    func testRecordVoteOnAnUnknownIdIsANoOp() {
        let store = CompanyStore()
        store.seedChatMessagesForTesting([CopilotMessage(id: "b", role: .companion, text: "answer")])
        store.recordVote(messageId: "nope", vote: .up)
        XCTAssertNil(store.chatMessages[0].vote)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageVoteTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'MessageVote' in scope`.

- [ ] **Step 3: Add the model field**

In `codepet/Models/CopilotMessage.swift`, add above `struct CopilotMessage` (after the `CopilotRole` enum at line 5):

```swift
/// The founder's verdict on one reply. Written straight to Firestore; the copy held
/// here only keeps the chosen thumb filled while the transcript is on screen.
enum MessageVote { case up, down }
```

Add the stored property after `drafts` (line 76):

```swift
    /// The founder's thumb on this reply, or nil until they give one.
    ///
    /// On the message rather than in `CopilotBubble`'s `@State` because SwiftUI drops view
    /// state as rows recycle during scrolling, which would make the filled thumb vanish
    /// mid-scroll. Session-only like the rest of the transcript — the vote itself is durable
    /// in Firestore, this is only what the row draws.
    var vote: MessageVote?
```

Add the parameter to the initializer — after `drafts: [MessageDraftDTO] = []` in the signature (line 96) and after `self.drafts = drafts` in the body (line 117):

```swift
         drafts: [MessageDraftDTO] = [], vote: MessageVote? = nil) {
```

```swift
        self.vote = vote
```

- [ ] **Step 4: Add the store method and the test seam**

In `codepet/Managers/CompanyStore.swift`, immediately above `func retryReply` (line 1262):

```swift
    /// Record the founder's thumb on a reply.
    ///
    /// `chatMessages` is `private(set)`, so this is the only way in. The Firestore write is
    /// the caller's job (`MessageFeedbackService`) — this keeps the store free of Firebase
    /// and keeps the vote's on-screen state testable without a configured `FirebaseApp`.
    func recordVote(messageId: String, vote: MessageVote) {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
        chatMessages[index].vote = vote
    }

    #if DEBUG
    /// Seed the transcript directly. Tests only — `chatMessages` is `private(set)` and the
    /// real paths all go through the network.
    func seedChatMessagesForTesting(_ messages: [CopilotMessage]) {
        chatMessages = messages
    }
    #endif
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageVoteTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 5 tests, 0 failures.

If the host crashes on teardown rather than failing an assertion, that is landmine 3 — confirm the assertions themselves passed in the log before moving on.

- [ ] **Step 6: Check nothing else broke**

`CopilotMessage` is `Equatable` and widely constructed, so a new field can ripple.

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/CopilotMessageDraftTests \
  -only-testing:codepetTests/ChatThreadsTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add codepet/Models/CopilotMessage.swift codepet/Managers/CompanyStore.swift codepetTests/MessageVoteTests.swift
git commit -F- <<'EOF'
feat(chat): carry the founder's thumb on the message

The chosen thumb has to survive scrolling. @State in CopilotBubble does
not: SwiftUI drops view state as rows recycle, so the fill would vanish
mid-scroll and read as the vote being lost. So the vote is a field on
CopilotMessage, set through CompanyStore.recordVote because chatMessages
is @Published private(set).

recordVote deliberately does not touch Firestore — that is
MessageFeedbackService's job — which keeps the store free of Firebase and
keeps this testable without a configured FirebaseApp. Auth.auth() traps
rather than throwing when Firebase is unconfigured (CLAUDE.md landmine 4)
and that crash mimics the @MainActor teardown crash, so keeping the two
apart is worth the extra type.

Session-only, like the transcript. The vote itself is durable in
Firestore; this field is only what the row draws.
EOF
```

---

### Task 4: `MessageFeedbackService` — the Firestore write

`firestore.rules:37-43` already allows `create` on `feedback` for any payload with an int `rating` in `1...5` and a string `feature`, with no field whitelist. So a thumb costs no rule change and no deploy — the `messageActions` doc comment at `:630` claiming otherwise is out of date. The payload builder is split out so the writer and the rule cannot drift apart silently.

**Files:**
- Modify: `codepet/Models/FeatureFeedbackManager.swift` (add the `chatMessage` case)
- Create: `codepet/Models/MessageFeedbackService.swift`
- Test: `codepetTests/MessageFeedbackPayloadTests.swift`

**Interfaces:**
- Consumes: `MessageVote` (Task 3), `CopilotMessage`, `AuthManager`, `AppState`, `FeedbackFeature`, `AppEnvironment.isRunningTests`, `ServerLoggingGate.isOptedOut`.
- Produces: `MessageFeedbackPayload.build(vote:messageId:threadId:companionId:deptName:userId:authMethod:displayName:pet:appVersion:build:) -> [String: Any]` and `MessageFeedbackService.submit(vote:message:threadId:authManager:appState:)`. Task 6 calls `submit`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MessageFeedbackPayloadTests.swift`:

```swift
// codepetTests/MessageFeedbackPayloadTests.swift
import XCTest
@testable import codepet

/// The payload has to satisfy `firestore.rules:37-43`, which is the only thing standing
/// between a thumb and a silent write failure in production. These assertions ARE the rule:
/// `rating is int` in 1...5 and `feature is string`. If someone switches rating to a Bool
/// or empties feature, these go red here rather than failing at the Firestore boundary
/// where nothing surfaces to the founder.
final class MessageFeedbackPayloadTests: XCTestCase {

    private func build(_ vote: MessageVote) -> [String: Any] {
        MessageFeedbackPayload.build(vote: vote, messageId: "m1", threadId: "t1",
                                     companionId: "glitch", deptName: "Engineering",
                                     userId: "u1", authMethod: "google",
                                     displayName: "Mona", pet: "byte",
                                     appVersion: "1.2", build: "42")
    }

    func testThumbUpIsRatingFive() {
        XCTAssertEqual(build(.up)["rating"] as? Int, 5)
    }

    func testThumbDownIsRatingOne() {
        XCTAssertEqual(build(.down)["rating"] as? Int, 1)
    }

    /// The rule reads `request.resource.data.rating is int`. A Bool would be rejected.
    func testRatingSatisfiesTheFirestoreRule() {
        for vote in [MessageVote.up, .down] {
            guard let rating = build(vote)["rating"] as? Int else {
                return XCTFail("rating must be an Int — the rule reads `rating is int`")
            }
            XCTAssertTrue((1...5).contains(rating))
        }
    }

    func testFeatureIsANonEmptyStringDistinctFromCompanionChat() {
        let feature = build(.up)["feature"] as? String
        XCTAssertEqual(feature, "chatMessage")
        XCTAssertNotEqual(feature, FeedbackFeature.companionChat.rawValue,
                          "thumbs must not pollute the 5-face companionChat stats")
    }

    func testPayloadCarriesTheMessageAndThreadIdentity() {
        let data = build(.up)
        XCTAssertEqual(data["messageId"] as? String, "m1")
        XCTAssertEqual(data["threadId"] as? String, "t1")
        XCTAssertEqual(data["companionId"] as? String, "glitch")
        XCTAssertEqual(data["deptName"] as? String, "Engineering")
    }

    func testPayloadCarriesTheSameIdentityFieldsAsTheExistingToast() {
        let data = build(.up)
        XCTAssertEqual(data["userId"] as? String, "u1")
        XCTAssertEqual(data["authMethod"] as? String, "google")
        XCTAssertEqual(data["displayName"] as? String, "Mona")
        XCTAssertEqual(data["pet"] as? String, "byte")
        XCTAssertEqual(data["appVersion"] as? String, "1.2")
        XCTAssertEqual(data["build"] as? String, "42")
        XCTAssertEqual(data["platform"] as? String, "macos")
    }

    func testNilCompanionAndDeptAreOmittedRatherThanWrittenAsNull() {
        let data = MessageFeedbackPayload.build(vote: .up, messageId: "m1", threadId: "t1",
                                                companionId: nil, deptName: nil,
                                                userId: "u1", authMethod: "guest",
                                                displayName: "Mona", pet: "byte",
                                                appVersion: "1.2", build: "42")
        XCTAssertNil(data["companionId"])
        XCTAssertNil(data["deptName"])
    }

    func testChatMessageFeatureExists() {
        XCTAssertEqual(FeedbackFeature.chatMessage.rawValue, "chatMessage")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageFeedbackPayloadTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'MessageFeedbackPayload' in scope`.

- [ ] **Step 3: Add the `chatMessage` feedback feature**

In `codepet/Models/FeatureFeedbackManager.swift`, add the case to the enum (after `dictionary`, line 18):

```swift
    /// A thumb on one chat reply. Unlike every other case this is NOT a once-ever
    /// first-experience prompt — it never appears in `FeatureFeedbackToast`, and exists so
    /// per-message votes are separable from the `companionChat` 5-face ratings.
    case chatMessage
```

Both `icon` and `question(_:)` switch exhaustively over the enum, so add a case to each:

In `icon` (after the `dictionary` case, line 34):

```swift
        case .chatMessage:   return "hand.thumbsup"
```

In `question(_:)` (after the `dictionary` case, line 58-59):

```swift
        case .chatMessage:
            return language == .vi ? "Câu trả lời này thế nào?" : "How was this reply?"
```

- [ ] **Step 4: Write the service**

Create `codepet/Models/MessageFeedbackService.swift`:

```swift
// codepet/Models/MessageFeedbackService.swift
import Foundation
import FirebaseFirestore

/// The `feedback` document a thumb writes, built as pure data.
///
/// Split from the writer so it can be tested against `firestore.rules:37-43` without a
/// configured `FirebaseApp`. That rule — `rating is int` in 1...5, `feature is string` —
/// is the only thing between a thumb and a write that fails silently in production, and a
/// rejected write surfaces nothing to the founder. It permits extra fields, so the
/// message/thread identity rides along without a rule change.
enum MessageFeedbackPayload {
    static func build(vote: MessageVote, messageId: String, threadId: String,
                      companionId: String?, deptName: String?,
                      userId: String, authMethod: String, displayName: String,
                      pet: String, appVersion: String, build: String) -> [String: Any] {
        var data: [String: Any] = [
            "feature": FeedbackFeature.chatMessage.rawValue,
            // 5/1 rather than a Bool: the rule reads `rating is int`, and it cannot be
            // relaxed without a deploy.
            "rating": vote == .up ? 5 : 1,
            "messageId": messageId,
            "threadId": threadId,
            "userId": userId,
            "authMethod": authMethod,
            "displayName": displayName,
            "pet": pet,
            "appVersion": appVersion,
            "build": build,
            "platform": "macos",
            "timestamp": FieldValue.serverTimestamp()
        ]
        if let companionId, !companionId.isEmpty { data["companionId"] = companionId }
        if let deptName, !deptName.isEmpty { data["deptName"] = deptName }
        return data
    }
}

/// Writes one thumb to the `feedback` collection.
///
/// Separate from `FeatureFeedbackManager.submit` because that one is welded to the
/// once-ever toast — it takes the toast's state and ends in `dismiss()`. Same collection,
/// same identity fields, same opt-out gate.
///
/// The rule denies `update`, so correcting a misclicked thumb writes a SECOND document with
/// the same `messageId`. That is deliberate and the reader resolves it by latest `timestamp`;
/// duplicate messageIds are not a bug.
@MainActor
enum MessageFeedbackService {
    static func submit(vote: MessageVote, message: CopilotMessage, threadId: String,
                       authManager: AuthManager, appState: AppState) {
        guard !AppEnvironment.isRunningTests, !ServerLoggingGate.isOptedOut else { return }
        let user = authManager.currentUser
        let data = MessageFeedbackPayload.build(
            vote: vote,
            messageId: message.id,
            threadId: threadId,
            companionId: message.companionId,
            deptName: message.deptName,
            userId: user?.uid ?? "anonymous",
            authMethod: authManager.authMethod ?? (authManager.isGuestMode ? "guest" : "none"),
            displayName: user?.displayName ?? appState.displayName,
            pet: appState.activeChar,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
        Firestore.firestore().collection("feedback").addDocument(data: data) { error in
            if let error {
                print("[MessageFeedback] submit error: \(error.localizedDescription)")
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageFeedbackPayloadTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 8 tests, 0 failures.

If `FeatureFeedbackToast` now fails to compile over a non-exhaustive switch, add the `chatMessage` case there returning the same copy — it is never shown, but the switch must be total.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/MessageFeedbackService.swift codepet/Models/FeatureFeedbackManager.swift codepetTests/MessageFeedbackPayloadTests.swift
git commit -F- <<'EOF'
feat(chat): write a thumb to the feedback collection that already exists

The comment above messageActions said thumbs need "a feedback collection
and a Firestore rule that do not exist natively yet". Both exist:
FeatureFeedbackManager.swift:157 already writes db.collection("feedback"),
and firestore.rules:37-43 permits create for any {rating: int 1...5,
feature: string} with no field whitelist. So a thumb costs no rule
change and no deploy, and the message/thread identity rides along in
the extra fields the rule already allows.

rating is 5/1 rather than a Bool because the rule reads `rating is int`
and cannot be relaxed without a deploy. A new chatMessage feature keeps
per-message votes out of the companionChat 5-face statistics.

The payload builder is split from the writer so the rule and the writer
cannot drift apart silently — a rejected write surfaces NOTHING to the
founder, so the test asserting the rule's own predicate is the only
place that failure can be caught.

Separate from FeatureFeedbackManager.submit, which is welded to the
once-ever toast and ends in dismiss(). The rule denies update, so
correcting a thumb writes a second doc with the same messageId; the
reader resolves by latest timestamp.
EOF
```

---

### Task 5: Split `CopilotBubble.body` so every branch gets a row

`messageActions` is called once, at `:1035`, inside the assistant branch of `textBubble`. That is why a draft, exec log, room, or proposal reply has no actions at all. And `.onHover` is attached to `messageActions` itself at `:670` — the same view held at `.opacity(0)` — so the hover target is an invisible strip rather than the message.

This task is verified by a build, not a unit test: the change is view composition, and `ImageRenderer` renders nothing inside a `ScrollView`. Founder verification is Task 7.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (`:212`, `:498-548`, `:668-670`, `:1035`)

**Interfaces:**
- Consumes: `ChatRhythm.proseToAction` (`:1357-1382`).
- Produces: `CopilotBubble(message:isLast:)`. No other call sites exist — `grep -n "CopilotBubble(" codepet` returns only `:212`.

- [ ] **Step 1: Add `isLast` and pass it from the list**

In `CopilotBubble`, after `let message: CopilotMessage` (line 454):

```swift
    /// True for the newest message in the transcript. Pins the action row (so the reply
    /// being read always shows its affordances) and gates retry, whose store method deletes
    /// every turn after the ask.
    let isLast: Bool
```

At the call site (line 212), inside the already-enumerated `ForEach`:

```swift
                        CopilotBubble(message: m,
                                      isLast: idx == companyStore.chatMessages.count - 1)
```

- [ ] **Step 2: Rename `body` to `content` and add the wrapper**

At line 498, change:

```swift
    var body: some View {
```

to:

```swift
    /// The action row belongs to the MESSAGE, not to one branch of this chain. It used to be
    /// called from inside `textBubble`, so a draft, exec log, room or proposal reply — the
    /// replies most worth copying and rating — had no actions at all. Wrapping `content` is
    /// what makes the row universal without touching a single payload branch.
    ///
    /// `.onHover` sits here rather than on the row (where it used to, at `messageActions`),
    /// because the row is held at `opacity(0)`: the target was a blank 22x20 strip below the
    /// prose, which is why the founder read the actions as missing entirely.
    var body: some View {
        if isMe || message.producing {
            // Your own words need no copy/retry/thumb, and a reply still being produced has
            // nothing to act on yet.
            content
        } else {
            VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
                content
                messageActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering = $0 }
        }
    }

    @ViewBuilder private var content: some View {
```

- [ ] **Step 3: Remove the old call from `textBubble`**

At line 1035, delete the line `messageActions` from inside `textBubble`'s assistant branch, leaving `inlineActions` as the last child of that inner `VStack`:

```swift
                    inlineActions
                }
            }
```

- [ ] **Step 4: Move hover off the row and pin the last reply**

Replace lines `:668-670` (the tail of `messageActions`):

```swift
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
```

with:

```swift
        // Pinned on the newest reply so the affordance is discoverable at all — hover alone
        // taught nobody it existed. Still `opacity` rather than a conditional, so the row's
        // height never changes under the cursor.
        .opacity(hovering || isLast ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: hovering)
```

Update the doc comment above `messageActions` (`:630-638`) — its claim that thumbs are impossible is now false:

```swift
    /// Per-message actions, revealed on hover and pinned on the newest reply — the row both
    /// references put under an answer. Copy, copy as Markdown, try again, a thumb either way,
    /// and the age of the turn.
    ///
    /// Hover-reveal because an answer is for reading; the affordances belong to the moment you
    /// reach for them. Pinned on the last reply because hover alone taught nobody the row was
    /// there — the target was this row itself, held at `opacity(0)`.
```

- [ ] **Step 5: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

SourceKit errors in the editor ("cannot find type X in scope") are false positives across files — `xcodebuild` is authoritative.

- [ ] **Step 6: Confirm nothing else constructs a bubble**

```bash
grep -rn "CopilotBubble(" codepet
```

Expected: exactly one hit, the call site in `messageList`. If a `#Preview` also constructs one, add `isLast:` there too and rebuild.

- [ ] **Step 7: Run the chat suites**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/ChatColumnTests \
  -only-testing:codepetTests/ChatThreadsTests \
  -only-testing:codepetTests/MessageVoteTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -F- <<'EOF'
fix(chat): the action row belongs to the message, not to one branch

Two bugs, one cause — the row was wired into the wrong place.

messageActions was called once, at :1035, inside textBubble's assistant
branch. Every card-bearing reply dispatches elsewhere in body's if-chain,
so a deliverable draft, an exec log, a Virtual Company room and both
proposals had NO actions at all — the replies most worth copying and
rating. body now splits into a wrapper plus `content`, so one row serves
every branch without touching a single payload case.

And .onHover was attached to messageActions itself (:670), the same view
held at opacity(0), so the hover target was a blank 22x20 strip below
the prose rather than the message. Hovering the reply did nothing, which
is why the founder read the row as missing. Hover moves to the wrapper.

The newest reply pins its row: hover alone taught nobody the row existed,
and a control nobody finds is the same as no control. Still opacity
rather than a conditional so the height never moves under the cursor.

Build-verified, not test-verified: this is view composition, and
ImageRenderer renders nothing inside a ScrollView. Founder verification
covers the hover and pinning behaviour.
EOF
```

---

### Task 6: The row itself — Markdown, thumbs, and the retry guard

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (`:453-467`, `:639-684`)

**Interfaces:**
- Consumes: `MessageTranscript.plain(_:lang:)` / `.markdown(_:speaker:lang:)` (Task 1), `MessageActionRules.canRetry(isLast:isTyping:isStreaming:)` (Task 2), `CompanyStore.recordVote(messageId:vote:)` and `CopilotMessage.vote` (Task 3), `MessageFeedbackService.submit(vote:message:threadId:authManager:appState:)` (Task 4), `CompanyStore.activeThreadId` (`:71`), `headerName` (`:486`).
- Produces: nothing downstream.

- [ ] **Step 1: Add the environment objects and the Markdown-copy state**

`appState` and `authManager` are injected app-wide (`CodePetApp.swift:50-51`), so `CopilotBubble` can take them directly. After `@Environment(\.colorScheme) private var scheme` (line 458):

```swift
    /// For the identity fields on a thumb — the same ones `FeatureFeedbackManager` sends.
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var appState: AppState
```

After `@State private var copied = false` (line 466):

```swift
    /// Separate from `copied` so the two acknowledgements never overwrite each other's label.
    @State private var copiedMarkdown = false
```

- [ ] **Step 2: Replace the body of `messageActions`**

Replace lines `:640-667` (the `HStack` contents, from `HStack(spacing: 2) {` through the closing brace before `.opacity`):

```swift
        HStack(spacing: 2) {
            actionIcon("doc.on.doc", help: lang == .vi ? "Sao chép" : "Copy") {
                copy(MessageTranscript.plain(message, lang: lang)) {
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copied = false
                    }
                }
            }
            .overlay(alignment: .leading) {
                if copied { copiedLabel(lang == .vi ? "Đã sao chép" : "Copied") }
            }
            // Distinct from Copy: the founder's paste target for a draft or a room is
            // Notion or a PR, and plain text loses the headings and the per-seat structure.
            actionIcon("square.and.arrow.up",
                       help: lang == .vi ? "Sao chép dạng Markdown" : "Copy as Markdown") {
                copy(MessageTranscript.markdown(message, speaker: headerName, lang: lang)) {
                    copiedMarkdown = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copiedMarkdown = false
                    }
                }
            }
            .overlay(alignment: .leading) {
                if copiedMarkdown { copiedLabel(lang == .vi ? "Đã sao chép" : "Copied") }
            }
            actionIcon("arrow.clockwise", help: lang == .vi ? "Hỏi lại" : "Try again") {
                Task { await companyStore.retryReply(messageId: message.id, language: lang) }
            }
            .disabled(!MessageActionRules.canRetry(isLast: isLast,
                                                   isTyping: companyStore.isCompanionTyping,
                                                   isStreaming: companyStore.isStreaming))
            thumb(.up, icon: "hand.thumbsup", help: lang == .vi ? "Hữu ích" : "Good reply")
            thumb(.down, icon: "hand.thumbsdown", help: lang == .vi ? "Chưa tốt" : "Bad reply")
            Text(Self.age(of: message.createdAt, lang: lang))
                .font(.pixelSystem(size: 9))
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.leading, 4)
        }
```

- [ ] **Step 3: Add the three helpers**

After `actionIcon(_:help:action:)` (which ends at line 684), add:

```swift
    private func copy(_ string: String, then acknowledge: @escaping () -> Void) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        acknowledge()
    }

    private func copiedLabel(_ text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 9, weight: .semibold))
            .foregroundColor(CodepetTheme.accentTeal)
            .offset(x: 22)
            .transition(.opacity)
    }

    /// A thumb fills once given, and the other stays live so a misclick is correctable.
    ///
    /// The correction writes a SECOND `feedback` document — `firestore.rules:42` denies
    /// `update` — which the reader resolves by latest `timestamp`. Voting the same way twice
    /// is a no-op rather than a duplicate write.
    @ViewBuilder private func thumb(_ vote: MessageVote, icon: String, help: String) -> some View {
        let chosen = message.vote == vote
        Button {
            guard !chosen else { return }
            companyStore.recordVote(messageId: message.id, vote: vote)
            MessageFeedbackService.submit(vote: vote, message: message,
                                          threadId: companyStore.activeThreadId ?? "",
                                          authManager: authManager, appState: appState)
        } label: {
            Image(systemName: chosen ? "\(icon).fill" : icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(chosen ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify the signature, because an unsigned build breaks Firebase at runtime**

```bash
codesign -dv /Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app 2>&1 | grep TeamIdentifier
```

Expected: `TeamIdentifier=YL72VTKBR7`. If it says `not set`, an earlier `CODE_SIGNING_ALLOWED=NO` test run clobbered the signing — rebuild with the Step 4 command before handing off.

- [ ] **Step 6: Run every suite this touched**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/MessageTranscriptTests \
  -only-testing:codepetTests/MessageActionRulesTests \
  -only-testing:codepetTests/MessageVoteTests \
  -only-testing:codepetTests/MessageFeedbackPayloadTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 33 tests, 0 failures.

- [ ] **Step 7: Rebuild signed and commit**

Step 6 ran with `CODE_SIGNING_ALLOWED=NO`, which strips the signature. Rebuild before handing off:

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" 2>&1 | tail -3
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -F- <<'EOF'
feat(chat): copy as Markdown, and a thumb either way

Copy now serializes the reply that is on screen rather than
message.text, which is blank on every card branch. Copy as Markdown is
separate because the paste target for a draft or a room is Notion or a
PR, and plain text loses the headings and the per-seat structure.

Thumbs fill when chosen and leave the other live, so a misclick is
correctable; the correction writes a second feedback doc because the
rule denies update. Voting the same way twice is a no-op rather than a
duplicate write.

Retry is gated on MessageActionRules.canRetry, so it is offered only on
the newest reply — the only position where retryReply's
removeSubrange(askIndex...) deletes what the button implies.

Rejected: NSSharingServicePicker for share. Same text payload, but it
opens an OS popover off a 22pt button in a row whose whole job is to
stay quiet.
EOF
```

---

### Task 7: Founder verification and PR

Screen Recording is denied on this machine, so native UI cannot be verified by screenshot — visual confirmation is a handoff, and green tests are not evidence that the row looks right.

Do not `pkill` a running `codepet.app` without asking: a concurrent session may be mid-verification, and two instances fight over the Firestore lock.

- [ ] **Step 1: Check whether a sibling instance is running**

```bash
pgrep -lf "codepet.app" | grep -v grep
```

If anything is running, ask Mona before quitting it. If nothing is, continue.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin feat/message-action-row
gh pr create --base main --title "Every reply carries its own action row" --body "$(cat <<'EOF'
## What

Copy, Copy as Markdown, Try again, 👍/👎 and a timestamp under **every** assistant reply — hover-reveal, pinned on the newest one.

Spec: `docs/superpowers/specs/2026-08-11-message-action-row-design.md`

## Why it read as missing

Copy, retry and a timestamp already existed. Two things hid them:

- `.onHover` was attached to `messageActions` itself, the same view held at `opacity(0)` — the target was a blank 22×20pt strip below the prose, not the message.
- The row was called from inside `textBubble`, so every card-bearing reply (draft, exec log, VC room, run/roadmap proposal, interview) had no actions at all.

## Notes

- **No Firestore rule change, no function deploy.** `firestore.rules:37-43` already permits `create` on `feedback` for `{rating: int 1...5, feature: string}`. The comment claiming otherwise was out of date and is corrected.
- **Retry is now confined to the newest reply.** `retryReply` calls `removeSubrange(askIndex...)` — it deletes the ask and every turn after it. Safe only where that equals what the button implies.
- Correcting a thumb writes a second `feedback` doc (the rule denies `update`); resolve by latest `timestamp`.
- Copy on a draft used to return an empty string. `MessageTranscript` fixes that and has a test for it.

## Verified

- 33 unit tests across `MessageTranscriptTests`, `MessageActionRulesTests`, `MessageVoteTests`, `MessageFeedbackPayloadTests`.
- Signed build succeeds, `TeamIdentifier=YL72VTKBR7`.
- Hover, pinning and the filled-thumb state are a founder-verification handoff — Screen Recording is denied here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Hand off with specific questions**

Give Mona the built app path and ask exactly these, which are the four things no test here covers:

1. On a reply that is a **deliverable draft**, does the row appear at all? (It never has.)
2. Does hovering **the text of an older reply** reveal the row — not just the strip beneath it?
3. Is the row on the **newest** reply visible without hovering?
4. Does a thumb **stay filled** after you scroll it off screen and back?

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| `CopilotBubble` splits into wrapper and content | 5 |
| `isLast` plumbed from the `ForEach` | 5 |
| Hover moves to the whole reply | 5 |
| Row order: Copy · Markdown · Retry · 👍 · 👎 · timestamp | 6 |
| `.opacity(hovering \|\| isLast ? 1 : 0)` | 5 |
| `MessageTranscript.plain` / `.markdown` + payload table | 1 |
| Prose leads where a branch renders both | 1 |
| `MessageFeedbackService` + `chatMessage` feature | 4 |
| `rating` 5/1 as an int, per the rule | 4 |
| `CopilotMessage.vote` + `CompanyStore.recordVote` | 3 |
| Filled thumb, other stays live, second doc on correction | 6 |
| Retry gated to the last reply, store unchanged | 2, 6 |
| Test: blank-text draft | 1 |
| Test: retry guard | 2 |
| Test: payload satisfies the rule | 4 |
| Founder-verification handoff | 7 |

Two spec details are deliberately not implemented as written: the spec's `plain`/`markdown` signatures omit `lang`, but `RunProposal.line(_:)`, `RoadmapProposal.line(_:)` and `EnrichInterview.question(for:language:)` all require an `AppLanguage`, so both take it. And the spec says markdown fences a draft body "if it is code or structured"; the plan emits the body unfenced, because `Deliverable.kind` does not distinguish prose from code and guessing would corrupt prose. Neither changes any decision in the spec.

**Placeholder scan:** none — every step carries its code or its exact command.

**Type consistency:** `MessageVote` (Task 3) is used by Tasks 4 and 6 with the same case names. `MessageTranscript.plain(_:lang:)` / `.markdown(_:speaker:lang:)` are defined in Task 1 and called with those labels in Task 6. `MessageActionRules.canRetry(isLast:isTyping:isStreaming:)` matches between Tasks 2 and 6. `MessageFeedbackPayload.build` and `MessageFeedbackService.submit` match between Tasks 4 and 6. `seedChatMessagesForTesting` is defined in Task 3 Step 4 and used in Task 3 Step 1.
