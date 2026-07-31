# Message rendering (un-bubble) + per-message feedback — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI), branch `feat/chat-redesign` (PR #39)
**Adapts:** Phase 2 chat spec §9, reshaped for `feat/chat-redesign`.
**Status:** Design agreed with the founder (Q&A 2026-07-28); ready for spec review → plan.

## Goal

Make the transcript read like a modern assistant chat: the **assistant messages lose their bubble** and sit on the canvas beside the companion orb; the **user message keeps its purple bubble** but gains a chat "tail"; and each assistant message gets **per-message feedback** — Copy (exists), Regenerate (exists), and a new **thumb up / down** that records a reaction to the existing `feedback` collection.

## Decisions (locked with the founder)

- **Full §9 this pass:** un-bubble assistant + keep Copy/Regenerate + add thumb up/down (a real `feedback`-collection write via a small store method — no schema/CF change).
- **User bubble:** keep the redesign's filled **accent-purple** bubble; adopt an asymmetric radius (a "tail"), not surface+hairline.

## Deviations from §9 (deliberate)

- **No rename** of `CopilotChatView` → `ChatView` (§9 mentions it) — that's file-reorg churn for a parallel branch; risky here for zero user value. Skip.
- **User bubble stays purple** (redesign choice the founder kept), not §9's surface+hairline.
- **No `MarkdownBlocks`** — this branch renders assistant text as plain `Text` (now `inter(15)`); §9's "a bubble fights the markdown" rationale is moot, but un-bubbling still reads cleaner. Not adding markdown rendering here.

## Non-goals

- No `CopilotMessage`/schema change; no Cloud Function change; no new dependencies.
- Reaction selection is **view-local UI state** (not persisted on the message) — the durable artifact is the `feedback` doc that gets written. (Persisting the reaction on the message is a future item.)
- Not touching the composer, empty state, orb, card grammar, backdrop, or column width.

## Design

### 1. User (me) bubble — `CopilotBubble.textBubble` (me branch), `CopilotChatView.swift`

Keep the `CodepetTheme.accentPurple` fill and white `inter(15)` text; replace the symmetric `RoundedRectangle(cornerRadius: 14)` with an asymmetric shape so the bottom-trailing corner is tight (a tail toward the user's side):

```swift
.background(
    UnevenRoundedRectangle(
        cornerRadii: .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 4, topTrailing: 14),
        style: .continuous
    ).fill(CodepetTheme.accentPurple)
)
```

(macOS 13+ `UnevenRoundedRectangle`; the app deploys well above that.) Alignment/spacing unchanged.

### 2. Assistant (companion) message — un-bubble, `CopilotBubble.textBubble` (companion branch)

Remove the surface `RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.surface)` background from the companion text. The text (`inter(15)`, `primaryText`) sits directly on the canvas. Keep:
- the leading `CompanionOrb(size: 28, glow: false)` avatar and the `HStack(alignment: .top, spacing: 10)` layout,
- the `companionActions` row below the text.

Only the text's own background/padding change: drop the fill; keep a small vertical rhythm (the text keeps its natural padding within the VStack). Net effect: assistant replies read as open text next to the orb, not a boxed bubble.

### 3. Per-message feedback — `companionActions` + a store write

`companionActions` currently has **Copy** (`doc.on.doc`) and **Regenerate** (`arrow.clockwise`). Add **thumb up** (`hand.thumbsup`) and **thumb down** (`hand.thumbsdown`), same muted icon-button style, to the right of them.

- View-local `@State private var reaction: Bool?` on `CopilotBubble` (nil = none, true = up, false = down). Tapping a thumb sets it and calls the store; the selected thumb renders **filled** (`hand.thumbsup.fill` / `.thumbsdown.fill`) and tinted `accentPurple`; the other stays muted outline. A second tap of the same thumb is allowed (re-sends); tapping the opposite flips it.
- Thumbs are shown on **companion messages only** (inside `companionActions`, which already renders only there). Not on `me`, not on cards, not on the thinking row.

**Store method — `CompanyStore.reactToMessage(messageId:helpful:)`:**

```swift
func reactToMessage(messageId: String, helpful: Bool) {
    guard !AppEnvironment.isRunningTests, !ServerLoggingGate.isOptedOut else { return }
    let data = MessageFeedback(messageId: messageId, helpful: helpful,
                               companyId: companyId,
                               userId: Auth.auth().currentUser?.uid ?? "anonymous",
                               companionId: company.companionId).firestoreData()
    Firestore.firestore().collection("feedback").addDocument(data: data) { error in
        if let error { print("[Feedback] chat reaction error: \(error.localizedDescription)") }
    }
}
```

Fire-and-forget, guarded exactly like `FeatureFeedbackManager.submit` (tests + opt-out gate), create-only (matches the deployed `feedback` rules). Uses the store's existing `companyId` + `company.companionId`. (Add `import FirebaseFirestore` / `import FirebaseAuth` to the store if not already present.)

### 4. Feedback payload — `codepet/Models/MessageFeedback.swift` (new, pure + testable)

```swift
struct MessageFeedback: Equatable {
    let messageId: String
    let helpful: Bool
    let companyId: String
    let userId: String
    let companionId: String

    /// The Firestore document body (server timestamp added by the writer, not here).
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

Pure — no Firestore import; the `timestamp` (`FieldValue.serverTimestamp()`) is added by the store writer. `"kind": "chat_message"` distinguishes these from the feature-rating docs `FeatureFeedbackManager` writes.

## Testing

- **`MessageFeedbackTests` (new, pure):** `firestoreData()` for a known instance contains `kind == "chat_message"`, the exact `messageId`, `helpful` (test both true/false), `companyId`, `userId`, `companionId`, `platform == "macos"`, and does NOT contain a `timestamp` key (writer's job). Assert on the dictionary values (cast to String/Bool).
- **Build gate:** foreground `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED. Full suite stays at 0 real failures + the new MessageFeedback tests.
- **No unit test for the write itself** (fire-and-forget Firestore I/O) or the un-bubble/radius (visual). Verified by:
- **Signed-build visual pass:** assistant replies read as open text beside the orb (no box); the user bubble is purple with the tight bottom-right corner; thumbs appear on assistant messages, fill on tap, and Copy/Regenerate still work. (Optionally confirm a `feedback` doc lands, but the write is best-effort.)

## Files

**New:** `codepet/Models/MessageFeedback.swift`, `codepetTests/MessageFeedbackTests.swift`
**Modified:** `codepet/Views/Copilot/CopilotChatView.swift` (`textBubble` me + companion; `companionActions` + `reaction` state), `codepet/Managers/CompanyStore.swift` (`reactToMessage` + imports if needed).

## Risks / watch-items

- **Reaction state is view-local** — it resets if SwiftUI recreates the row (e.g. aggressive scroll recycling). Acceptable for v1 (the write is the durable part); note it so it isn't mistaken for a bug.
- **Un-bubbled assistant text legibility** — with no surface panel, confirm the `primaryText` on the `ChatBackdrop` wash reads well in light + dark (it's the same context the card-grammar surface fix addressed; plain text should be fine).
- **`feedback` write auth** — `Auth.auth()` is only safe to call once Firebase is configured; the store runs post-configure in normal use, and the tests-gate short-circuits under XCTest, so the known Firebase-init flake is not worsened. Keep the `isRunningTests` guard.
- **Behavior:** Copy + Regenerate closures must stay byte-identical; only additive thumbs.

## Rollout

Implement on `feat/chat-redesign` → build + suite green → build & launch signed for the founder's visual sign-off → push (rebasing over concurrent commits). Nothing merges (branch held). Follow up on the W1 tracker's "Message / transcript visual design" task.
