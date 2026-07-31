# Chat containment + cohesion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contain the active-conversation composer in the same 720pt column as the message list, share one ambient purple backdrop behind both the empty and active chat states, and drop the full-width divider.

**Architecture:** A structure-preserving layout pass on the native chat surface. Extract the empty state's inline glow into a reusable `ChatBackdrop` and hang it once behind the whole `CopilotChatView`; center the docked composer with the same `Spacer / maxWidth: 720 / Spacer` pattern the message list already uses; remove the divider (the composer's `floatingShadow` carries separation). No composer internals, message-bubble, or `CompanyStore`/chat-logic changes.

**Tech Stack:** SwiftUI (macOS), CodepetTheme design tokens, Xcode `xcodebuild`.

## Global Constraints

- Target repo/branch: `My-Outcasts/codepet`, branch `feat/chat-redesign` (PR #39). Nothing is merged — the branch is held for the user's GUI sign-off.
- Build/test in the **FOREGROUND** (never background `xcodebuild` — it stalls): `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- The project uses Xcode **synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`): a new `.swift` file placed in `codepet/Views/Copilot/` is auto-included in the target — **no `project.pbxproj` edit is required**.
- Column width is **720pt** everywhere (empty + active) — do not change it.
- Known baseline: full suite is **303 tests / 0 real failures**; the overall `** TEST FAILED **` is the `CompanyStoreScaffordOnboardingTests` Firebase-init flake (fixed on PR #40, not this branch) — it is NOT a regression.
- SourceKit shows false-positive "Cannot find CodepetTheme/…" errors for these files out of build context — ignore them; `xcodebuild build` is the authoritative signal.
- Colors/spacing via `CodepetTheme` tokens; respect `accessibilityReduceTransparency`.
- This is a layout/decoration change: there is **no new pure logic to unit-test**. Each task's test cycle is a foreground `xcodebuild build`; Task 2 also runs the full suite. The visual payoff is verified by a human GUI pass (light + dark), out of scope for these coded steps.
- Commit message trailer on every commit: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: Shared ambient backdrop behind both chat states

Extract the empty-state glow into a reusable `ChatBackdrop`, place it once behind the whole `CopilotChatView`, and remove the now-duplicate `brandWash` from `ChatEmptyState`. These ship together: removing `brandWash` alone would strip the empty-state glow, and adding the backdrop without removing `brandWash` would double the glow in the empty state.

**Files:**
- Create: `codepet/Views/Copilot/ChatBackdrop.swift`
- Modify: `codepet/Views/Copilot/ChatEmptyState.swift` (remove `brandWash` + the `reduceTransparency` env var; unwrap the `ZStack`)
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (wrap `body` in `ZStack { ChatBackdrop(); … }`)

**Interfaces:**
- Consumes: `CodepetTheme.accentPurple`, `@Environment(\.accessibilityReduceTransparency)` (existing).
- Produces: `struct ChatBackdrop: View` — a no-argument, inert decoration view (`ChatBackdrop()`), consumed by `CopilotChatView` in Task 1 and relied on by Task 2's active branch sitting inside the same `ZStack`.

- [ ] **Step 1: Create `ChatBackdrop.swift`**

Create `codepet/Views/Copilot/ChatBackdrop.swift` with exactly:

```swift
import SwiftUI

/// The chat surface's ambient purple radial wash — one shared, inert decoration
/// placed behind BOTH the empty hero and the active conversation so the two read
/// as one continuous surface. Suppressed under Reduce Transparency. Extracted from
/// `ChatEmptyState.brandWash` so the empty and active states share one definition.
struct ChatBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !reduceTransparency {
                RadialGradient(
                    gradient: Gradient(colors: [CodepetTheme.accentPurple.opacity(0.16), .clear]),
                    center: .center, startRadius: 0, endRadius: 420)
                .blur(radius: 60)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Remove `brandWash` from `ChatEmptyState` and unwrap the `ZStack`**

In `codepet/Views/Copilot/ChatEmptyState.swift`, replace the `body` (currently a `ZStack { brandWash; VStack { … } }`) so the `VStack` is the top-level content — the glow now comes from `CopilotChatView`'s `ChatBackdrop`. Change:

```swift
    var body: some View {
        ZStack {
            brandWash
            VStack(spacing: 28) {
                CompanionOrb(size: 78)

                greeting
                    .padding(.horizontal, 24)

                composer
                    .frame(maxWidth: 720)

                cards
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
    }
```

to:

```swift
    var body: some View {
        VStack(spacing: 28) {
            CompanionOrb(size: 78)

            greeting
                .padding(.horizontal, 24)

            composer
                .frame(maxWidth: 720)

            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
```

Then delete the now-unused `brandWash` computed property entirely:

```swift
    /// Soft purple radial wash behind the whole empty-state column — suppressed
    /// under Reduce Transparency.
    private var brandWash: some View {
        Group {
            if !reduceTransparency {
                RadialGradient(
                    gradient: Gradient(colors: [CodepetTheme.accentPurple.opacity(0.16), .clear]),
                    center: .center, startRadius: 0, endRadius: 420)
                .blur(radius: 60)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

And delete the now-unused environment property (only `brandWash` read it):

```swift
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
```

(Leave `@Environment(\.uiLanguage) private var lang` untouched — it is pre-existing and unrelated to this change.)

- [ ] **Step 3: Wrap `CopilotChatView.body` in a `ZStack` with `ChatBackdrop`**

In `codepet/Views/Copilot/CopilotChatView.swift`, change the `body` from:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if companyStore.chatMessages.isEmpty {
                ChatEmptyState(line1: greetingLine1,
                               line2: greetingLine2,
                               quickActions: quickActions,
                               onQuickAction: runQuickAction) {
                    composerView
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

to (this step only adds the `ZStack { ChatBackdrop(); … }` wrapper; the active branch is still the old `Divider()` + `composerView.padding(10)` and gets rewritten in Task 2):

```swift
    var body: some View {
        ZStack {
            ChatBackdrop()
            VStack(spacing: 0) {
                if companyStore.chatMessages.isEmpty {
                    ChatEmptyState(line1: greetingLine1,
                                   line2: greetingLine2,
                                   quickActions: quickActions,
                                   onQuickAction: runQuickAction) {
                        composerView
                    }
                } else {
                    messageList
                    Divider()
                    composerView.padding(10)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
```

- [ ] **Step 4: Build to verify it compiles (this is the test cycle)**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. If the compiler flags `reduceTransparency` or `lang` as still-referenced, undo only the offending deletion; if it flags them unused, the deletion in Step 2 was correct.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/ChatBackdrop.swift codepet/Views/Copilot/ChatEmptyState.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): share one ambient backdrop behind empty + active

Extract ChatEmptyState.brandWash into a reusable ChatBackdrop and hang it
once behind CopilotChatView so the empty hero and the active conversation
read as one continuous purple-washed surface. ChatEmptyState drops its
private brandWash (and the reduceTransparency env only it used); no visual
change to the empty state.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Contain the docked composer + drop the divider

Bring the active-conversation composer into the same centered 720pt column as the message list and remove the full-width divider. This is the actual "full-width" fix.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (the active branch of `body`, inside the `ZStack` added in Task 1)

**Interfaces:**
- Consumes: `ChatBackdrop` + the `ZStack { … VStack { … } }` structure from Task 1; the existing `messageList` (which centers a `maxWidth: 720` VStack via `HStack { Spacer; …; Spacer }`) and `composerView` (the shared `ChatComposer`, already carrying `floatingShadow`).
- Produces: nothing consumed downstream (final task).

- [ ] **Step 1: Rewrite the active branch — center the composer, drop the divider**

In `codepet/Views/Copilot/CopilotChatView.swift`, change the active (`else`) branch from:

```swift
                } else {
                    messageList
                    Divider()
                    composerView.padding(10)
                }
```

to:

```swift
                } else {
                    messageList
                    HStack {
                        Spacer(minLength: 0)
                        composerView.frame(maxWidth: 720)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
```

This uses the identical `Spacer / maxWidth: 720 / Spacer` centering `messageList` uses, so the composer's 720 column tracks the message-bubble column at every window width. The `Divider()` is removed — the composer's `floatingShadow` provides separation over the ambient backdrop.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full suite to confirm no regression**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3`
Expected: `Executed 303 tests, with 0 failures` on the `codepetTests.xctest` suite. (A trailing overall `** TEST FAILED **` from the known Firebase-init flake is acceptable — confirm the `codepetTests.xctest` line shows 0 failures.)

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "fix(chat): contain the docked composer in the 720 column, drop divider

The active-conversation composer rendered full-width (composerView.padding
(10)); wrap it in the same Spacer/maxWidth:720/Spacer column the message
list uses so its edges track the bubbles at every width. Drop the
full-width Divider() — the composer's floatingShadow carries the
separation over the shared ChatBackdrop.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (human, out of scope for coded steps)

Push the branch, then a GUI pass in a signed build (team `YL72VTKBR7`, ⌘R), **light + dark**:
- Active conversation: composer sits in the centered 720 column, edges aligned with bubbles; no edge-to-edge sprawl; no divider.
- Ambient purple glow present and consistent across empty and active (fixed, not scrolling); acceptable over the light cream background.
- Reduce Transparency ON → glow suppressed in both states.
- Empty state looks identical to before.

---

## Self-Review

**1. Spec coverage:**
- Spec change 1 (contain docked composer) → Task 2, Step 1. ✓
- Spec change 2 (`ChatBackdrop` extraction + shared behind both states; `ChatEmptyState` drops `brandWash`) → Task 1, Steps 1–3. ✓
- Spec change 3 (drop the `Divider()`) → Task 2, Step 1. ✓
- Non-goals (no composer-internal/bubble/logic/width changes) → respected; no task touches those. ✓
- Testing (build gate + suite 303/0; GUI pass) → Task 1 Step 4, Task 2 Steps 2–3, Post-implementation. ✓
- Risk "backdrop must be outside the ScrollView" → satisfied: `ChatBackdrop` is a sibling of the `VStack` in the `ZStack`, not inside `messageList`. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/vague steps — every code step shows the full before/after. ✓

**3. Type consistency:** `ChatBackdrop` defined in Task 1 Step 1 is used as `ChatBackdrop()` in Task 1 Step 3 and relied on structurally in Task 2. `composerView`, `messageList`, `greetingLine1/2`, `quickActions`, `runQuickAction` are all existing members, used verbatim. Column cap `720` consistent across both tasks and the spec. ✓
