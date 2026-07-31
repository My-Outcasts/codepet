# Message rendering (un-bubble) + per-message feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Un-bubble assistant messages (text on canvas beside the orb), give the user's purple bubble an asymmetric tail, and add per-message thumb up/down that writes a `MessageFeedback` doc to the existing `feedback` collection (Copy + Regenerate unchanged).

**Architecture:** A pure `MessageFeedback` payload (+ tests); a small fire-and-forget `CompanyStore.reactToMessage` write; and restyle + additive thumbs in `CopilotBubble`. No `CopilotMessage`/schema/CF change.

**Tech Stack:** SwiftUI (macOS), Firebase (Firestore/Auth), CodepetTheme, Xcode.

## Global Constraints

- Repo/branch: `My-Outcasts/codepet`, `feat/chat-redesign` (PR #39). Held. Rebase over concurrent commits before pushing.
- Build/test **FOREGROUND** only: `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- Synchronized folder groups — new `.swift` in `codepet/` / `codepetTests/` auto-include; **no `project.pbxproj` edit**.
- SourceKit "Cannot find … in scope" for these files are known FALSE POSITIVES; `xcodebuild` is authoritative.
- Baseline suite: **0 real failures**; trailing overall `** TEST FAILED **` = known `CompanyStoreScaffordOnboardingTests` Firebase-init flake (NOT a regression; wobbles the test COUNT — judge by "0 failures").
- **Copy + Regenerate closures stay byte-identical.** Thumbs are additive. No `CopilotMessage` field added.
- The `feedback` write is **create-only** (matches deployed rules) and **guarded** (`!AppEnvironment.isRunningTests && !ServerLoggingGate.isOptedOut`) — never write under XCTest.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Un-bubble/radius look + a real reaction write are human-verified on a signed build (controller builds & launches).

---

### Task 1: `MessageFeedback` (pure) + tests

**Files:**
- Create: `codepet/Models/MessageFeedback.swift`
- Test: `codepetTests/MessageFeedbackTests.swift`

**Interfaces:**
- Produces: `struct MessageFeedback` with `firestoreData() -> [String: Any]`. Consumed by Task 2's `reactToMessage`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MessageFeedbackTests.swift`:

```swift
import XCTest
@testable import codepet

final class MessageFeedbackTests: XCTestCase {
    private func fixture(helpful: Bool) -> MessageFeedback {
        MessageFeedback(messageId: "m123", helpful: helpful, companyId: "c1",
                        userId: "u1", companionId: "byte")
    }

    func testDataHelpfulTrue() {
        let d = fixture(helpful: true).firestoreData()
        XCTAssertEqual(d["kind"] as? String, "chat_message")
        XCTAssertEqual(d["messageId"] as? String, "m123")
        XCTAssertEqual(d["helpful"] as? Bool, true)
        XCTAssertEqual(d["companyId"] as? String, "c1")
        XCTAssertEqual(d["userId"] as? String, "u1")
        XCTAssertEqual(d["companionId"] as? String, "byte")
        XCTAssertEqual(d["platform"] as? String, "macos")
    }

    func testDataHelpfulFalse() {
        XCTAssertEqual(fixture(helpful: false).firestoreData()["helpful"] as? Bool, false)
    }

    func testNoTimestampKey() {
        // The server timestamp is added by the writer, not the payload.
        XCTAssertNil(fixture(helpful: true).firestoreData()["timestamp"])
    }
}
```

- [ ] **Step 2: Run tests → RED**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "MessageFeedback|error:" | tail -8`
Expected: compile failure — `MessageFeedback` undefined.

- [ ] **Step 3: Implement `MessageFeedback`**

Create `codepet/Models/MessageFeedback.swift`:

```swift
import Foundation

/// A per-message reaction (thumb up/down) recorded to the `feedback` collection.
/// Pure — the writer (`CompanyStore.reactToMessage`) adds the server timestamp.
/// `kind: "chat_message"` distinguishes these from FeatureFeedbackManager's
/// feature-rating docs.
struct MessageFeedback: Equatable {
    let messageId: String
    let helpful: Bool
    let companyId: String
    let userId: String
    let companionId: String

    func firestoreData() -> [String: Any] {
        [
            "kind": "chat_message",
            "messageId": messageId,
            "helpful": helpful,
            "companyId": companyId,
            "userId": userId,
            "companionId": companionId,
            "platform": "macos",
        ]
    }
}
```

- [ ] **Step 4: Run tests → GREEN**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "MessageFeedbackTests|Executed [0-9]+ tests" | tail -6`
Expected: the 3 MessageFeedback tests pass; suite 0 real failures.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/MessageFeedback.swift codepetTests/MessageFeedbackTests.swift
git commit -m "feat(chat): pure MessageFeedback payload for per-message reactions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `reactToMessage` write + `CopilotBubble` §9 UI

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (add `reactToMessage`; imports if needed)
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (`textBubble` me + companion; `companionActions` + `reaction` state)

**Interfaces:**
- Consumes: `MessageFeedback` (Task 1); `CompanyStore.companyId` + `company.companionId` (existing); `Firestore`/`Auth`.
- Produces: `CompanyStore.reactToMessage(messageId:helpful:)`.

- [ ] **Step 1: Add the store write method**

In `codepet/Managers/CompanyStore.swift`, ensure `import FirebaseFirestore` and `import FirebaseAuth` are present (add if missing), and add this method to the class (near the other chat methods):

```swift
    /// Record a per-message thumb up/down to the `feedback` collection. Fire-and-
    /// forget, create-only, guarded like FeatureFeedbackManager — never writes
    /// under XCTest or when server logging is opted out.
    func reactToMessage(messageId: String, helpful: Bool) {
        guard !AppEnvironment.isRunningTests, !ServerLoggingGate.isOptedOut else { return }
        var data = MessageFeedback(
            messageId: messageId, helpful: helpful,
            companyId: companyId, userId: Auth.auth().currentUser?.uid ?? "anonymous",
            companionId: company.companionId
        ).firestoreData()
        data["timestamp"] = FieldValue.serverTimestamp()
        Firestore.firestore().collection("feedback").addDocument(data: data) { error in
            if let error { print("[Feedback] chat reaction error: \(error.localizedDescription)") }
        }
    }
```

Confirm the store exposes `companyId` (it is used in `sendChat`, e.g. `companyId: companyId`) and `company.companionId`; use those exact accessors. If `companyId` is named differently, use the store's actual current-company id accessor.

- [ ] **Step 2: Build (verify the store method compiles)**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: User bubble — asymmetric tail**

In `CopilotChatView.swift` `textBubble`, the `isMe` branch: replace the symmetric background shape. Change:
```swift
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CodepetTheme.accentPurple))
```
to:
```swift
                        .background(UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 14, bottomLeading: 14,
                                               bottomTrailing: 4, topTrailing: 14),
                            style: .continuous).fill(CodepetTheme.accentPurple))
```
(Keep the `.padding`, `.foregroundColor(.white)`, `.font`, `.fixedSize`, and the surrounding `HStack { Spacer(minLength: 24); … }` unchanged.)

- [ ] **Step 4: Assistant message — un-bubble**

In the `else` (companion) branch, remove the surface background and box padding from the companion `Text` so it sits on the canvas. Change:
```swift
                        Text(message.text)
                            .font(CodepetTheme.inter(15))
                            .foregroundColor(CodepetTheme.primaryText)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(CodepetTheme.surface))
                            .fixedSize(horizontal: false, vertical: true)
```
to:
```swift
                        Text(message.text)
                            .font(CodepetTheme.inter(15))
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
```
(Keep the leading `CompanionOrb(size: 28, glow: false)`, the `HStack(alignment: .top, spacing: 10)`, the `VStack(alignment: .leading, spacing: 6)`, `companionActions`, and the trailing `Spacer(minLength: 24)` unchanged.)

- [ ] **Step 5: Add the `reaction` state + thumb buttons**

In `struct CopilotBubble`, add near the other `@State`:
```swift
    @State private var reaction: Bool?   // nil = none, true = up, false = down
```

Replace `companionActions` with (Copy + Regenerate unchanged; two thumbs added):
```swift
    private var companionActions: some View {
        HStack(spacing: 14) {
            Button { copyText() } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundColor(CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            Button { regenerate() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundColor(CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            .disabled(companyStore.isCompanionTyping || companyStore.isStreaming)
            Button { react(true) } label: {
                Image(systemName: reaction == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 13))
                    .foregroundColor(reaction == true ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }.buttonStyle(.plain)
            Button { react(false) } label: {
                Image(systemName: reaction == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 13))
                    .foregroundColor(reaction == false ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
            }.buttonStyle(.plain)
        }
    }

    private func react(_ helpful: Bool) {
        reaction = helpful
        companyStore.reactToMessage(messageId: message.id, helpful: helpful)
    }
```
(`copyText()` and `regenerate()` stay exactly as they are.)

- [ ] **Step 6: Build + full suite**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **`.
Then: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3`
Expected: `codepetTests.xctest` shows 0 real failures.

- [ ] **Step 7: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): un-bubble assistant messages + per-message thumbs

Assistant replies drop the surface bubble and sit on the canvas beside the
orb; the user bubble keeps its purple fill with an asymmetric tail. Adds
thumb up/down (view-local selection) writing a MessageFeedback doc via
CompanyStore.reactToMessage. Copy + Regenerate unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (controller, human sign-off)

Rebase over concurrent commits, push, build & launch signed (quit stale by pid, `-allowProvisioningUpdates`, `open`). Founder verifies: assistant replies read as open text beside the orb (no box); user bubble is purple with the tight bottom-right corner; thumbs show on assistant messages, fill on tap, Copy/Regenerate still work; text legible in light + dark.

---

## Self-Review

**1. Spec coverage:** §9 un-bubble assistant → Task 2 Step 4. User-bubble tail → Step 3. Thumbs + reaction state → Step 5. Feedback write → Step 1 + Task 1 payload. Tests (payload data shape, both helpful values, no timestamp key) → Task 1. Build/suite/signed visual → Task 2 + post. ✓

**2. Placeholder scan:** Full code for `MessageFeedback`, tests, `reactToMessage`, and every UI edit (before→after). The only conditional is "confirm `companyId` accessor name" — a named verification, not a vague gap. ✓

**3. Type consistency:** `MessageFeedback(messageId:helpful:companyId:userId:companionId:).firestoreData()` defined Task 1, called identically in `reactToMessage` Task 2. `reactToMessage(messageId:helpful:)` defined Step 1, called in `react(_:)` Step 5. `reaction: Bool?` drives the thumb fill. Copy/Regenerate (`copyText`/`regenerate`) untouched. `UnevenRoundedRectangle` is macOS 13+ (app deploys higher). ✓
