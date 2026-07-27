# Native Chat Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the native chat column into a centered hero + elevated composer with Ask/Plan/Build modes and capability quick-actions, plus a restyled active conversation — no backend changes.

**Architecture:** A pure `ChatMode` enum shapes the outgoing message client-side; a reusable `ChatComposer` view is used in both the empty and active states; a `ChatEmptyState` view renders the centered hero + quick-action pills. `CopilotChatView` becomes a thin shell that switches between empty and active layouts. All other chat behavior (send, streaming, threads, draft cards, interview/nav/setup chips) is preserved unchanged.

**Tech Stack:** SwiftUI (macOS), XCTest, `CodepetTheme` design tokens, Google Sans Flex via `CodepetTheme.inter`.

## Global Constraints

- Native macOS SwiftUI app. All edits live under `codepet/Views/Copilot/` and `codepet/Models/`. Tests under `codepetTests/`.
- **No changes** to `CompanyStore`, `CompanyChatClient`, any Cloud Function, or any model other than the new `ChatMode`.
- **No fake affordances:** the composer has NO file-attach button; the `+` button opens a real quick-actions menu; modes are client-side message-shaping only.
- All colors, radii, and spacing come from `CodepetTheme` tokens (never hardcoded hex) so the UI adapts to the app's dynamic light/dark automatically.
- Fonts via `CodepetTheme.inter(_:weight:)`. The hero greeting is Google Sans Flex (NOT the Minecraft pixel font).
- Bilingual: every user-facing string has a `.vi` and `.en` form, following the existing `lang == .vi ? … : …` pattern. `AppLanguage` cases are `.vi` and `.en`.
- Preserve behavior: sending (Return / send button), streaming, thread switching, draft approve/redo, interview send/skip, nav/setup/noted chips must all still work.
- **Build/test commands must run in the FOREGROUND** (backgrounded `xcodebuild` stalls in this environment). Commands:
  - Single test class: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -30`
  - Full suite: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40`
  - Build only: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
- Every commit message ends with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `codepet/Models/ChatMode.swift` | Pure enum `.ask/.plan/.build`; `label(_:)`, `shape(_:language:)` | Create |
| `codepetTests/ChatModeTests.swift` | Unit tests for `ChatMode` | Create |
| `codepet/Views/Copilot/ChatComposer.swift` | Reusable composer (field + `+` menu + mode menu + send) | Create |
| `codepet/Views/Copilot/ChatEmptyState.swift` | Centered hero greeting + quick-action pills | Create |
| `codepet/Views/Copilot/CopilotChatView.swift` | Thin shell; wires composer + empty state; deletes old input/greeting/letsBuild; bubble restyle | Modify |

---

### Task 1: `ChatMode` model + tests

**Files:**
- Create: `codepet/Models/ChatMode.swift`
- Test: `codepetTests/ChatModeTests.swift`

**Interfaces:**
- Consumes: `AppLanguage` (cases `.vi`, `.en`).
- Produces:
  - `enum ChatMode: CaseIterable, Identifiable { case ask, plan, build }`
  - `func label(_ lang: AppLanguage) -> String`
  - `func shape(_ text: String, language lang: AppLanguage) -> String`  (`.ask` is identity)

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ChatModeTests.swift`:

```swift
import XCTest
@testable import codepet

final class ChatModeTests: XCTestCase {
    func testAskReturnsTextUnchanged() {
        XCTAssertEqual(ChatMode.ask.shape("what's next?", language: .en), "what's next?")
        XCTAssertEqual(ChatMode.ask.shape("việc gì tiếp?", language: .vi), "việc gì tiếp?")
    }

    func testPlanWrapsAndPreservesText() {
        let out = ChatMode.plan.shape("pricing page", language: .en)
        XCTAssertTrue(out.contains("pricing page"))
        XCTAssertNotEqual(out, "pricing page")
        XCTAssertTrue(out.lowercased().contains("plan"))
    }

    func testBuildWrapsAndPreservesText() {
        let out = ChatMode.build.shape("landing page", language: .en)
        XCTAssertTrue(out.contains("landing page"))
        XCTAssertNotEqual(out, "landing page")
    }

    func testPlanIsLocalized() {
        XCTAssertNotEqual(ChatMode.plan.shape("x", language: .en),
                          ChatMode.plan.shape("x", language: .vi))
    }

    func testAllCasesHaveNonEmptyLabels() {
        for m in ChatMode.allCases {
            XCTAssertFalse(m.label(.en).isEmpty)
            XCTAssertFalse(m.label(.vi).isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ChatModeTests 2>&1 | tail -30`
Expected: FAIL — compile error, `ChatMode` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/ChatMode.swift`:

```swift
import Foundation

/// Client-side chat "mode". Shapes the founder's raw message with an intent,
/// then hands the plain string to the existing `CompanyStore.sendChat`. There
/// is no backend concept of modes and no build session — this is pure
/// message-shaping, which is why it is a small, unit-testable value type.
enum ChatMode: CaseIterable, Identifiable {
    case ask, plan, build

    var id: Self { self }

    /// Short control label — matches the terse pill style used elsewhere in chat.
    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.ask, .vi):   return "Hỏi"
        case (.ask, _):     return "Ask"
        case (.plan, .vi):  return "Lập kế hoạch"
        case (.plan, _):    return "Plan"
        case (.build, .vi): return "Bắt tay làm"
        case (.build, _):   return "Build"
        }
    }

    /// Wrap the founder's raw text with this mode's intent. `.ask` is identity.
    /// `.build` copy is deliberately modest — the chat can already run tasks and
    /// produce draft deliverables; it must NOT imply the (not-yet-native) build agent.
    func shape(_ text: String, language lang: AppLanguage) -> String {
        switch self {
        case .ask:
            return text
        case .plan:
            return lang == .vi
                ? "Giúp mình lập kế hoạch — nêu các bước cụ thể tiếp theo: \(text)"
                : "Help me plan this — give me the concrete next steps: \(text)"
        case .build:
            return lang == .vi
                ? "Cùng bắt tay làm luôn — nếu là việc bạn làm được, hãy chạy và cho mình xem bản nháp: \(text)"
                : "Let's build this together — if it's a task you can do, run it and show me a draft: \(text)"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ChatModeTests 2>&1 | tail -30`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ChatMode.swift codepetTests/ChatModeTests.swift
git commit -m "feat(chat): add ChatMode message-shaping enum

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `ChatComposer` reusable view

**Files:**
- Create: `codepet/Views/Copilot/ChatComposer.swift`

**Interfaces:**
- Consumes: `ChatMode` (Task 1); `CodepetTheme`; `\.uiLanguage` environment.
- Produces:
  ```swift
  struct ChatComposer: View {
      @Binding var draft: String
      @Binding var mode: ChatMode
      var canSend: Bool
      var focus: FocusState<Bool>.Binding
      var placeholder: String
      var quickActions: [String]
      var onSend: () -> Void
      var onQuickAction: (String) -> Void
  }
  ```

This view has no snapshot-test harness in the repo, so its verification is: the
project builds, its `#Preview` renders, and the full suite stays green. Correctness
of the message-shaping it triggers is covered by Task 1.

- [ ] **Step 1: Write the view + preview**

Create `codepet/Views/Copilot/ChatComposer.swift`:

```swift
import SwiftUI

/// The chat composer — one reusable input surface used in BOTH the empty hero
/// and the docked active conversation. Owns no state: draft/mode live in the
/// parent (`CopilotChatView`) so the same value drives both placements.
///
/// Honesty notes: the `+` button is a quick-actions menu (NOT a file picker —
/// the app has no attachments), and the mode control shapes the outgoing message
/// via `ChatMode` (no backend mode exists).
struct ChatComposer: View {
    @Binding var draft: String
    @Binding var mode: ChatMode
    var canSend: Bool
    var focus: FocusState<Bool>.Binding
    var placeholder: String
    var quickActions: [String]
    var onSend: () -> Void
    var onQuickAction: (String) -> Void

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(15))
                .lineLimit(1...6)
                .focused(focus)
                .onSubmit(onSend)

            HStack(spacing: 8) {
                quickActionsMenu
                modeMenu
                Spacer()
                sendButton
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CodepetTheme.hairline)
        )
    }

    private var quickActionsMenu: some View {
        Menu {
            ForEach(quickActions, id: \.self) { qa in
                Button(qa) { onQuickAction(qa) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(CodepetTheme.hairline)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var modeMenu: some View {
        Menu {
            ForEach(ChatMode.allCases) { m in
                Button(m.label(lang)) { mode = m }
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode.label(lang)).font(CodepetTheme.inter(13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodepetTheme.hairline)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }
}

#if DEBUG
private struct ChatComposerPreviewHost: View {
    @State private var draft = ""
    @State private var mode: ChatMode = .ask
    @FocusState private var focused: Bool
    var body: some View {
        ChatComposer(
            draft: $draft, mode: $mode, canSend: !draft.isEmpty,
            focus: $focused,
            placeholder: "Ask anything about your company…",
            quickActions: ["Run a task", "Review the roadmap"],
            onSend: {}, onQuickAction: { _ in }
        )
        .frame(width: 640)
        .padding()
    }
}

#Preview("ChatComposer") { ChatComposerPreviewHost() }
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full test suite (no regressions)**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40`
Expected: all tests pass (composer is not yet wired into anything, so nothing changes behaviorally).

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift
git commit -m "feat(chat): add reusable ChatComposer view

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `ChatEmptyState` hero view

**Files:**
- Create: `codepet/Views/Copilot/ChatEmptyState.swift`

**Interfaces:**
- Consumes: `CodepetTheme`; `\.uiLanguage`; `\.accessibilityReduceTransparency`.
- Produces:
  ```swift
  struct ChatEmptyState<Composer: View>: View {
      let companyName: String
      let quickActions: [String]
      let onQuickAction: (String) -> Void
      @ViewBuilder var composer: Composer
  }
  ```
  Layout order top→bottom: hero greeting, `composer`, quick-action pills.

- [ ] **Step 1: Write the view + preview**

Create `codepet/Views/Copilot/ChatEmptyState.swift`:

```swift
import SwiftUI

/// The chat empty state: a centered, personalized hero greeting, the composer
/// (injected so the parent keeps ownership of draft/mode), and a row of
/// capability quick-action pills. Replaces the old left-aligned welcome text.
struct ChatEmptyState<Composer: View>: View {
    let companyName: String
    let quickActions: [String]
    let onQuickAction: (String) -> Void
    @ViewBuilder var composer: Composer

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 28) {
            greeting
                .font(CodepetTheme.inter(34, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .background(glow)

            composer
                .frame(maxWidth: 680)

            pills
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    /// "How can I help you build {company} today?" with the company in accent.
    private var greeting: Text {
        let accent = Text(companyName).foregroundColor(CodepetTheme.accentPurple)
        switch lang {
        case .vi: return Text("Mình giúp gì cho ") + accent + Text(" hôm nay?")
        case .en: return Text("How can I help you build ") + accent + Text(" today?")
        }
    }

    /// One faint accent radial behind the greeting. Suppressed under
    /// reduce-transparency; kept subtle so it reads in light AND dark.
    @ViewBuilder private var glow: some View {
        if reduceTransparency {
            Color.clear
        } else {
            RadialGradient(
                colors: [CodepetTheme.accentPurple.opacity(0.16), .clear],
                center: .center, startRadius: 0, endRadius: 260
            )
            .blur(radius: 24)
            .allowsHitTesting(false)
        }
    }

    /// Quick-action pills. One row when it fits, two rows otherwise, so a narrow
    /// column never clips them.
    private var pills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { ForEach(quickActions, id: \.self) { pill($0) } }
            VStack(spacing: 10) {
                HStack(spacing: 10) { ForEach(firstHalf, id: \.self) { pill($0) } }
                HStack(spacing: 10) { ForEach(secondHalf, id: \.self) { pill($0) } }
            }
        }
    }

    private var firstHalf: [String] { Array(quickActions.prefix((quickActions.count + 1) / 2)) }
    private var secondHalf: [String] { Array(quickActions.suffix(quickActions.count / 2)) }

    private func pill(_ text: String) -> some View {
        Button { onQuickAction(text) } label: {
            Text(text)
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.bodyText)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(CodepetTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ChatEmptyState") {
    ChatEmptyState(
        companyName: "Acme",
        quickActions: ["Run a task", "Review the roadmap", "Set up a department", "Summarize where we are"],
        onQuickAction: { _ in }
    ) {
        RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 96).frame(maxWidth: 680)
    }
    .frame(width: 900, height: 620)
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Copilot/ChatEmptyState.swift
git commit -m "feat(chat): add ChatEmptyState centered hero view

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire composer + empty state into `CopilotChatView`; delete old input, greeting, and Let's-build stub

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: `ChatMode` (Task 1), `ChatComposer` (Task 2), `ChatEmptyState` (Task 3).
- Produces: no new public API. Internal `send()` now applies `mode.shape(...)`; new private `runQuickAction(_:)`, `quickActions`, `placeholder`, `composerView`, and `@State mode`.

This task is a mechanical restructure of working code. Do NOT rewrite the message
list, bubbles, header, or thread logic — only move/replace the pieces named below.

- [ ] **Step 1: Add mode state**

In `CopilotChatView`, next to `@State private var draft = ""` (around line 8), add:

```swift
    @State private var mode: ChatMode = .ask
```

- [ ] **Step 2: Replace the `body` layout**

Replace the current `var body` (the `VStack(spacing: 0) { header; Divider(); if showHistory {…} else { messageList; letsBuild }; Divider(); inputBar }`) with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showHistory {
                ThreadListView(showHistory: $showHistory)
            } else if companyStore.chatMessages.isEmpty {
                ChatEmptyState(companyName: companyName,
                               quickActions: quickActions,
                               onQuickAction: runQuickAction) {
                    composerView.frame(maxWidth: 680)
                }
            } else {
                messageList
                Divider()
                composerView.padding(10)
            }
        }
        .frame(maxHeight: .infinity)
    }
```

- [ ] **Step 3: Add the shared composer + helpers; delete the old `inputBar`, `letsBuild`, `greeting`, `quickStarts`**

Delete these existing members entirely: `letsBuild`, `greeting`, `quickStarts`, `inputBar`.
In `messageList`, delete the empty-state branch line `if companyStore.chatMessages.isEmpty { greeting }` (the empty state is now handled in `body`; `messageList` only renders when there are messages).

Add these new members:

```swift
    /// The one composer instance, reused in the empty hero and docked in an
    /// active conversation. State (draft/mode/focus) stays here so both
    /// placements share the same value.
    private var composerView: some View {
        ChatComposer(
            draft: $draft,
            mode: $mode,
            canSend: canSend,
            focus: $inputFocused,
            placeholder: placeholder,
            quickActions: quickActions,
            onSend: send,
            onQuickAction: runQuickAction
        )
    }

    private var placeholder: String {
        lang == .vi
            ? "Hỏi \(companionName) bất cứ điều gì về công ty…"
            : "Ask \(companionName) anything about your company…"
    }

    /// Capability quick-actions — the strings are complete intents, so they are
    /// sent as-is (NOT mode-shaped). Replaces the old `quickStarts`.
    private var quickActions: [String] {
        lang == .vi
            ? ["Chạy một tác vụ", "Xem lộ trình", "Thiết lập một phòng ban", "Tóm tắt tình hình công ty"]
            : ["Run a task", "Review the roadmap", "Set up a department", "Summarize where we are"]
    }

    /// Send a canned capability prompt through the normal chat path. Bypasses
    /// mode-shaping (the string already expresses the intent). Guarded like send.
    private func runQuickAction(_ text: String) {
        guard !companyStore.isCompanionTyping, !companyStore.isStreaming else { return }
        showHistory = false
        Task { await companyStore.sendChat(text, language: lang) }
    }
```

- [ ] **Step 4: Update `send()` to apply the mode**

Replace the existing `send()` with:

```swift
    private func send() {
        guard canSend else { return }
        let text = mode.shape(draft, language: lang)
        draft = ""
        showHistory = false   // sending always returns to the live conversation
        Task { await companyStore.sendChat(text, language: lang) }
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. If it fails on a now-unused symbol, confirm `letsBuild`/`greeting`/`quickStarts`/`inputBar` were fully removed and had no other references.

- [ ] **Step 6: Run the full test suite (no regressions)**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40`
Expected: all tests pass (send/thread/draft behavior unchanged).

- [ ] **Step 7: Manual verification (run the app)**

Launch the app (foreground). Verify:
- Empty chat shows the centered hero greeting with the company name in accent, the composer, and 4 quick-action pills.
- Typing + Return sends; the send button enables only with text and while not streaming.
- Switching the mode menu to Plan/Build then sending produces a shaped message (byte replies with a plan / attempts the work).
- Tapping a pill sends its capability prompt.
- Once messages exist, the composer is docked at the bottom and the `+` menu lists the quick actions.
- History toggle still opens the thread switcher.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): wire composer + empty state, drop old input/greeting/lets-build

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Bubble restyle + light/dark & reduce-motion verification

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: nothing new. Pure visual polish on `CopilotBubble.textBubble` and `messageList` spacing.

- [ ] **Step 1: Increase message spacing**

In `messageList`, change the messages `VStack(alignment: .leading, spacing: 10)` to `spacing: 14`.

- [ ] **Step 2: Soften the bubble radius**

In `CopilotBubble.textBubble`, change the background `RoundedRectangle(cornerRadius: 12, style: .continuous)` to `cornerRadius: 14`.

- [ ] **Step 3: Build**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify both appearances + reduce-motion**

Run the app and toggle macOS Appearance (System Settings → Appearance, or the in-app AppTheme setting) between Light and Dark:
- **Dark:** hero greeting legible, glow subtle (not a bright blob), composer/pills read against the charcoal surface.
- **Light (cream):** greeting legible on cream, glow barely-there (not a grey smear), composer border visible.
- Enable System Settings → Accessibility → Display → Reduce transparency and confirm the greeting glow disappears (no layout shift).

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "style(chat): restyle bubbles + verify light/dark hero

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Component structure → Tasks 1–4 (ChatMode, ChatComposer, ChatEmptyState, CopilotChatView shell). ✓
- Empty-state hero (centered greeting, glow, pills, GSF font) → Task 3. ✓
- Composer (`+` quick-actions menu, mode control, send, canSend gate, multiline) → Task 2 + Task 4 wiring. ✓
- Modes honest / client-side shaping → Task 1 + Task 4 `send()`. ✓
- Active conversation (docked composer, bubble restyle, delete Let's-build stub) → Task 4 + Task 5. ✓
- Header unchanged → untouched (confirmed no task modifies it beyond leaving it as-is). ✓
- Tokens + dynamic light/dark + reduce-motion → tokens used throughout; verified in Task 5. ✓
- No fake affordances → `+` is a real menu; no attach; modes real. ✓
- Testing (ChatMode unit tests; behavior preserved) → Task 1 tests + full-suite runs in Tasks 2/4/5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output. ✓

**Type consistency:** `ChatMode.shape(_:language:)` and `label(_:)` signatures match between Task 1 (definition), Task 2 (`ChatComposer` mode menu), and Task 4 (`send()`). `ChatComposer`'s parameter list in Task 2 matches its construction in Task 4's `composerView`. `ChatEmptyState`'s init (`companyName`, `quickActions`, `onQuickAction`, `composer`) matches Task 4's call site. ✓
