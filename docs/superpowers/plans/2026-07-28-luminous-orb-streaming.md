# Luminous orb + streaming affordance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn `CompanionOrb` into a luminous, companion-tinted sphere that breathes while working, and replace the static chat "Thinking…" text with a `ChatThinkingRow` that names the work and shimmers.

**Architecture:** Additive, layout/rendering only. Add a per-companion second hue (§1) + two theme tokens (§2), reimplement `CompanionOrb` as a `TimelineView`-driven ZStack of gradient layers (§3), a pure `ChatThinkingLabel` (§4), and a `ChatThinkingRow` that replaces `typingRow`/`producingRow` (§5). No Cloud Function / RoadmapEngine / Firestore / schema changes.

**Tech Stack:** SwiftUI (macOS), CodepetTheme (`Color.dyn`), Xcode `xcodebuild`.

## Global Constraints

- Repo/branch: `My-Outcasts/codepet`, `feat/chat-redesign` (PR #39). Nothing merges — branch held.
- Build/test in the **FOREGROUND** (never background `xcodebuild`): `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- Xcode **synchronized folder groups** — new `.swift` files in `codepet/` / `codepetTests/` auto-include; **no `project.pbxproj` edit**.
- SourceKit shows false-positive "Cannot find CodepetTheme/CompanyStore/… in scope" for these files — ignore; `xcodebuild build` is authoritative.
- Baseline suite: **303 real passes / 0 failures**; the trailing overall `** TEST FAILED **` is the known `CompanyStoreScaffordOnboardingTests` Firebase-init flake (fixed on PR #40) — NOT a regression.
- No literal hex in views **except** inside `CompanionOrb` (its core art) and the two `CodepetTheme` tokens. All other colours via `CodepetTheme`.
- All user-facing strings localized **en + vi** (match existing `lang == .vi ? … : …` pattern).
- Respect `accessibilityReduceMotion` (orb + shimmer) and `accessibilityReduceTransparency` (bloom).
- Commit trailer on every commit: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Orb visual fidelity + 60fps + Reduce-Motion are **human-verified on a signed build** (no agent can see a screen). Each task's automated gate is the foreground build; Tasks 2 & 4 also run the suite.

---

### Task 1: Per-companion second hue + theme tokens

Data-only additions the orb depends on. No behaviour change on its own.

**Files:**
- Modify: `codepet/Models/Character.swift`
- Modify: `codepet/Views/CodepetTheme.swift`

**Interfaces:**
- Produces: `PetCharacter.secondHexColor: String` + `PetCharacter.secondColor: Color`; `CodepetTheme.chatCanvas`, `CodepetTheme.chatOrbCore`. Consumed by Task 3.

- [ ] **Step 1: Add the second-hue property to `PetCharacter`**

In `codepet/Models/Character.swift`: directly after the existing `let hexColor: String` stored property, add:

```swift
    let secondHexColor: String
```

And near the existing `var color` computed property, add:

```swift
    var secondColor: Color { Color(hex: secondHexColor) }
```

- [ ] **Step 2: Add `secondHexColor:` to all seven entries in `static let all`**

Each entry is a `PetCharacter(… color: Color(hex: "#…"), hexColor: "#…", …)`. Add a `secondHexColor:` argument (immediately after the `hexColor:` argument) to each, using this table:

| id | secondHexColor |
|---|---|
| byte | `#4EC9D4` |
| nova | `#6EA8FF` |
| crash | `#F0A860` |
| luna | `#C99BF0` |
| sage | `#FDC352` |
| glitch | `#5AD0E0` |
| null | `#5AD0E0` |

Example for `byte` (match the surrounding formatting):

```swift
            color: Color(hex: "#8B7BE8"), hexColor: "#8B7BE8", secondHexColor: "#4EC9D4",
```

- [ ] **Step 3: Add the two theme tokens**

In `codepet/Views/CodepetTheme.swift`, immediately after the accent block (after `static let accentBlue …`), add:

```swift
    static let chatCanvas  = Color.dyn("#f8f7f3", "#16130f")   // matches pageBackground
    static let chatOrbCore = Color.dyn("#0E0A16", "#040208")   // the orb's luminous core
```

- [ ] **Step 4: Build (the test cycle for this data task)**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (a missing `secondHexColor:` on any of the 7 entries fails the build — fix until green).

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/Character.swift codepet/Views/CodepetTheme.swift
git commit -m "feat(chat): per-companion second hue + chatCanvas/chatOrbCore tokens

Adds PetCharacter.secondHexColor (+ secondColor) for all seven companions
and the chatCanvas/chatOrbCore Color.dyn tokens the luminous orb needs.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `ChatThinkingLabel` (pure) + tests

Pure, testable label logic. Independent of the other tasks. TDD.

**Files:**
- Create: `codepet/Models/ChatThinkingLabel.swift`
- Test: `codepetTests/ChatThinkingLabelTests.swift`

**Interfaces:**
- Produces: `enum ChatThinkingLabel { static func text(taskTitle: String?, language: AppLanguage) -> String }`. Consumed by Task 4.
- Consumes: existing `AppLanguage` enum (cases `.en` / `.vi` — confirm the exact non-vi case name from any existing file that switches on `AppLanguage`; the codebase uses `lang == .vi ? … : …`, so treat non-`.vi` as English).

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ChatThinkingLabelTests.swift`:

```swift
import XCTest
@testable import codepet

final class ChatThinkingLabelTests: XCTestCase {
    func testNoTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .en), "Working on it…")
    }
    func testNoTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: nil, language: .vi), "Đang xử lý…")
    }
    func testNamedTaskEnglish() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .en),
                       "Drafting positioning brief…")
    }
    func testNamedTaskVietnamese() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "positioning brief", language: .vi),
                       "Đang soạn positioning brief…")
    }
    func testBlankTitleTreatedAsNone() {
        XCTAssertEqual(ChatThinkingLabel.text(taskTitle: "   ", language: .en), "Working on it…")
    }
}
```

If `AppLanguage`'s English case is not `.en`, use the correct case (e.g. `.english`) consistently in the tests and implementation.

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatThinkingLabel|error:" | tail -8`
Expected: compile failure — `ChatThinkingLabel` is undefined.

- [ ] **Step 3: Implement `ChatThinkingLabel`**

Create `codepet/Models/ChatThinkingLabel.swift`:

```swift
import Foundation

/// The streaming-state label copy. Pure + localized. Names the in-flight work
/// when a real title exists; otherwise a generic, honest verb — never fabricate
/// a task name.
enum ChatThinkingLabel {
    static func text(taskTitle: String?, language: AppLanguage) -> String {
        let title = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return language == .vi ? "Đang soạn \(title)…" : "Drafting \(title)…"
        }
        return language == .vi ? "Đang xử lý…" : "Working on it…"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatThinkingLabelTests|Executed [0-9]+ tests" | tail -6`
Expected: the 5 `ChatThinkingLabelTests` pass; the `codepetTests.xctest` line shows 0 real failures (known Firebase flake aside).

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ChatThinkingLabel.swift codepetTests/ChatThinkingLabelTests.swift
git commit -m "feat(chat): pure ChatThinkingLabel (names the work, honest fallback)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Reimplement `CompanionOrb` as a luminous, companion-tinted sphere

The schedule-risk task. Keep the type name + `size`/`glow` API; add `isWorking`; read companion hues from the store.

**Files:**
- Modify (replace body): `codepet/Views/Copilot/CompanionOrb.swift`
- Modify (preview only): `codepet/Views/Copilot/ChatEmptyState.swift` (inject a store into its `#Preview`)

**Interfaces:**
- Consumes: `PetCharacter.color` / `.secondColor` (Task 1), `CodepetTheme.chatOrbCore` (Task 1), `CompanyStore` from the environment.
- Produces: `CompanionOrb(size:glow:isWorking:)` — `isWorking: true` drives a 3.6s breathe. Consumed by Task 4. The existing call sites (`ChatEmptyState` hero 78; `CopilotChatView` avatars 28) keep working unchanged (default `isWorking: false`).

- [ ] **Step 1: Replace `CompanionOrb.swift` with the luminous implementation**

Replace the entire body of `codepet/Views/Copilot/CompanionOrb.swift` with:

```swift
import SwiftUI

/// A luminous, companion-tinted sphere — the companion's identity in chat
/// (hero focal, message avatar, thinking indicator). Reads the active companion's
/// two hues from the store so switching companion re-tints every orb. Pure
/// SwiftUI, no assets. Only `isWorking` changes scale (a slow breathe); at rest
/// the internal colour drifts. Reduce Motion → one static frame.
struct CompanionOrb: View {
    var size: CGFloat = 78
    var glow: Bool = true
    var isWorking: Bool = false

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var character: PetCharacter? { PetCharacter.all[companyStore.company.companionId] }
    private var hue1: Color { character?.color ?? CodepetTheme.accentPurple }
    private var hue2: Color { character?.secondColor ?? CodepetTheme.accentPink }

    var body: some View {
        Group {
            if reduceMotion {
                orb(t: 0)
            } else {
                TimelineView(.animation) { tl in
                    orb(t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func breathe(_ t: Double) -> CGFloat {
        guard isWorking && !reduceMotion else { return 1.0 }
        // 3.6s period, scale 1.0 … 1.07
        return 1.0 + 0.035 * (1 + CGFloat(sin(t * (2 * .pi / 3.6))))
    }

    private func orb(t: Double) -> some View {
        ZStack {
            // 1. near-black luminous core — makes colour read as emitted light
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [CodepetTheme.chatOrbCore, .black]),
                center: .center, startRadius: 0, endRadius: size * 0.5))

            // 2. three internal colour bands, drifting on different periods, additive
            band(hue1, degPerSec: 30, t: t)
            band(hue2, degPerSec: 42, t: t)
            band(.white.opacity(0.5), degPerSec: 22, t: t)   // hue1 "lifted toward white"

            // 3. specular crescent
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [.white.opacity(0.9), .clear]),
                center: UnitPoint(x: 0.34 + 0.015 * sin(t * 0.6), y: 0.30),
                startRadius: 0, endRadius: size * 0.30))

            // 4. base shading for sphericality
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.40)]),
                center: UnitPoint(x: 0.70, y: 0.80),
                startRadius: size * 0.15, endRadius: size * 0.60))

            // 5. rim, brightest near the specular
            Circle().strokeBorder(
                AngularGradient(gradient: Gradient(colors: [
                    .white.opacity(0.55), .clear, .clear, .white.opacity(0.2), .white.opacity(0.55)]),
                    center: .center),
                lineWidth: max(1, size * 0.02))
        }
        .compositingGroup()
        .clipShape(Circle())
        .scaleEffect(breathe(t))
        .background(bloom)   // 6. outer bloom, behind and unclipped
    }

    private func band(_ color: Color, degPerSec: Double, t: Double) -> some View {
        AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.0), color.opacity(0.6), color.opacity(0.0)]),
            center: .center,
            angle: .degrees(reduceMotion ? 0 : t * degPerSec))
        .clipShape(Circle())
        .blendMode(.plusLighter)
    }

    private var bloom: some View {
        Circle()
            .fill(hue1.opacity((glow && !reduceTransparency) ? 0.45 : 0.0))
            .blur(radius: size * 0.45)
            .scaleEffect(1.12)
    }
}

#if DEBUG
#Preview("CompanionOrb") {
    HStack(spacing: 24) {
        CompanionOrb(size: 78, isWorking: true)
        CompanionOrb(size: 28, glow: false)
    }
    .padding(40)
    .background(Color.black)
    .environmentObject(CompanyStore())
}
#endif
```

Note (implementer latitude): this is a real, compile-first implementation. If any SwiftUI signature needs adjusting for your SDK, fix it to compile while preserving the ordered composition, the `isWorking`-only breathe, and the Reduce-Motion static path. Do NOT switch to Canvas/Metal unless the ZStack cannot hold 60fps at size 78 on the signed build — that judgement happens at visual verification, not here.

- [ ] **Step 2: Fix the `ChatEmptyState` preview to inject a store**

`CompanionOrb` now reads `CompanyStore` from the environment, so `ChatEmptyState`'s `#Preview` must provide one. In `codepet/Views/Copilot/ChatEmptyState.swift`, find the `#Preview("ChatEmptyState")` block and add `.environmentObject(CompanyStore())` to its returned view (alongside the existing `.frame`/`.background` modifiers).

- [ ] **Step 3: Build**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. (If a call site errors because the orb needs the store, confirm every runtime call site is inside a view that has `CompanyStore` in its environment — all current ones do; only previews need the explicit inject.)

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/CompanionOrb.swift codepet/Views/Copilot/ChatEmptyState.swift
git commit -m "feat(chat): luminous companion-tinted orb with working-breathe

Reimplement CompanionOrb as a TimelineView-driven layered sphere (near-black
core, drifting colour bands, specular, rim, bloom), tinted from the active
companion's two hues. isWorking drives a 3.6s breathe; Reduce Motion renders
one static frame. API (size/glow) unchanged; adds isWorking.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `ChatThinkingRow` + wire it in (replace `typingRow` / `producingRow`)

**Files:**
- Create: `codepet/Views/Copilot/ChatThinkingRow.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (replace `typingRow`; route `producingRow` through the new row; delete the two old row bodies)

**Interfaces:**
- Consumes: `CompanionOrb(size:glow:isWorking:)` (Task 3), `ChatThinkingLabel.text(taskTitle:language:)` (Task 2), the `\.uiLanguage` environment.
- Produces: `ChatThinkingRow(taskTitle: String?)`.

- [ ] **Step 1: Create `ChatThinkingRow`**

Create `codepet/Views/Copilot/ChatThinkingRow.swift`:

```swift
import SwiftUI

/// The streaming/producing state: a breathing companion orb + a label that names
/// the work (via ChatThinkingLabel), with a subtle light sweep through the text.
/// Replaces the old static typingRow/producingRow. Reduce Motion → orb static +
/// no sweep.
struct ChatThinkingRow: View {
    /// A real in-flight title, or nil for a plain chat turn (→ "Working on it…").
    var taskTitle: String? = nil

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String { ChatThinkingLabel.text(taskTitle: taskTitle, language: lang) }

    var body: some View {
        HStack(spacing: 10) {
            CompanionOrb(size: 28, glow: false, isWorking: true)
            shimmerLabel
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder private var shimmerLabel: some View {
        let base = Text(label).font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.mutedText)
        if reduceMotion {
            base
        } else {
            TimelineView(.animation) { tl in
                let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.1) / 2.1
                base.overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, CodepetTheme.primaryText.opacity(0.7), .clear]),
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .offset(x: CGFloat(phase * 260 - 60))
                    .mask(base)
                    .allowsHitTesting(false)
                )
            }
        }
    }
}

#if DEBUG
#Preview("ChatThinkingRow") {
    VStack(alignment: .leading, spacing: 16) {
        ChatThinkingRow(taskTitle: nil)
        ChatThinkingRow(taskTitle: "positioning brief")
    }
    .padding(40)
    .environmentObject(CompanyStore())
}
#endif
```

- [ ] **Step 2: Wire the chat-turn typing state**

In `codepet/Views/Copilot/CopilotChatView.swift`: the `messageList` appends `typingRow` when `companyStore.isCompanionTyping`. Replace that usage with `ChatThinkingRow(taskTitle: nil)` (keep the same `.id("typing")` on it so the existing auto-scroll `proxy.scrollTo("typing", …)` still works), and **delete** the `private var typingRow` computed property.

Concretely, the block that today reads:
```swift
                        if companyStore.isCompanionTyping { typingRow.id("typing") }
```
becomes:
```swift
                        if companyStore.isCompanionTyping { ChatThinkingRow(taskTitle: nil).id("typing") }
```
and delete the `typingRow` property (lines defining `private var typingRow: some View { … }`).

- [ ] **Step 3: Wire the producing state**

In `CopilotBubble` (same file), `producingRow` renders when `message.producing`. Replace the `producingRow` body so it returns a `ChatThinkingRow`, passing a title only if the producing message already carries one. Inspect `CopilotMessage` for an existing title-bearing field on a producing message (e.g. a draft/run title). If one exists, pass it; if not, pass `nil`. Do NOT add new model fields or fabricate a title in this task.

Replace the `producingRow` computed property with:
```swift
    private var producingRow: some View {
        // Pass a real title if the producing message carries one; else nil → "Working on it…".
        ChatThinkingRow(taskTitle: nil)
    }
```
(If you find a title field on the message during inspection, substitute it for `nil` and note it in your report.)

- [ ] **Step 4: Build**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Fix any dangling reference left by deleting `typingRow`/`producingRow`.

- [ ] **Step 5: Run the full suite (regression)**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3`
Expected: `codepetTests.xctest` shows `Executed <N> tests, with 0 failures` (N = 303 + the new ChatThinkingLabel tests). Trailing overall `** TEST FAILED **` from the known Firebase flake is acceptable.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/ChatThinkingRow.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): ChatThinkingRow replaces static typing/producing text

Breathing orb + a label that names the work (ChatThinkingLabel) with a
subtle 2.1s light-sweep; Reduce Motion → static. Replaces typingRow and
producingRow.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (human, out of scope for coded steps)

Build & launch signed (I do this, as before): quit any stale instance, `xcodebuild build … -allowProvisioningUpdates` (signed), `open` the fixed `.app`. Founder verifies **on screen**: orb reads as luminous & companion-tinted (byte violet→teal), breathes only while a reply/produce is in flight, shimmer is subtle, Reduce Motion stills it, hero (78) is smooth. If the orb stutters at 60fps, fall back to Canvas/Metal per the spec (new task).

---

## Self-Review

**1. Spec coverage:** §1 second hue → Task 1 Steps 1–2. §2 tokens → Task 1 Step 3. §4 ChatThinkingLabel → Task 2. §3 luminous orb (core/bands/specular/shading/rim/bloom, isWorking breathe, reduce-motion static, companion hues) → Task 3 Step 1. §5 ChatThinkingRow + typing/producing wiring + shimmer + reduce-motion → Task 4. Testing (ChatThinkingLabelTests; build gate; suite; signed visual) → Task 2 + each build step + Post-implementation. ✓

**2. Placeholder scan:** No TBD/vague steps; every code step ships complete code. The producing-title source is an explicit inspect-and-decide with a concrete honest fallback (`nil`), not a gap. ✓

**3. Type consistency:** `CompanionOrb(size:glow:isWorking:)` defined Task 3, used Task 4. `ChatThinkingLabel.text(taskTitle:language:)` defined Task 2, used Task 4 (via `ChatThinkingRow`) — signature matches. `secondColor`/`chatOrbCore` defined Task 1, used Task 3. `.id("typing")` preserved so existing auto-scroll keeps working. `AppLanguage` English case to be confirmed against the codebase in Task 2 and used consistently. ✓
