# Message card grammar + chat readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give the seven chat message payloads one tinted-card grammar with six semantic hues (gold = decision owed), and move chat reading text from the small pixel font to `CodepetTheme.inter(~15)`.

**Architecture:** A pure `MessageCardStyle` (kind + hue) + one `MessageCard` wrapper view; refactor `CopilotBubble`'s six bespoke payload builders to route through `MessageCard` with the mapped hue, keeping every inner action/closure unchanged; swap `.pixelSystem` reading text to `CodepetTheme.inter` per a fixed scale. No model/CF/schema change.

**Tech Stack:** SwiftUI (macOS), CodepetTheme, Xcode `xcodebuild`.

## Global Constraints

- Repo/branch: `My-Outcasts/codepet`, `feat/chat-redesign` (PR #39). Nothing merges — branch held. Rebase over any concurrent branch commits before pushing.
- Build/test in the **FOREGROUND** (never background `xcodebuild`): `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- Xcode **synchronized folder groups** — new `.swift` files in `codepet/` / `codepetTests/` auto-include; **no `project.pbxproj` edit**.
- SourceKit "Cannot find CodepetTheme/CompanyStore/PetCharacter/CopilotMessage/… in scope" for these files are known FALSE POSITIVES; `xcodebuild build` is authoritative.
- Baseline suite: **0 real failures**; the trailing overall `** TEST FAILED **` is the known `CompanyStoreScaffordOnboardingTests` Firebase-init flake — NOT a regression; the flake also makes the total test COUNT wobble (crash-retry), so judge by "0 real failures," not the count.
- **No behaviour change** to any payload action (Approve/Redo/Revise, nav activate, setup enable, interview send/skip, first-run action, noted). This restyles the container + text only.
- `producing` is NOT a card — it already routes to `ChatThinkingRow`; do not touch it.
- Commit trailer on every commit: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Visual verification (hues per payload, approved-draft recede, larger text, light+dark) is human, on a signed build — the controller builds & launches it after the tasks.

## Hue map (used in Task 2)

| kind | hue expression |
|---|---|
| draft (unapproved) | `CodepetTheme.accentGold` |
| draft (approved) | `CodepetTheme.accentTeal` |
| interview | `CodepetTheme.accentBlue` |
| setupSuggestion | `CodepetTheme.accentTeal` |
| firstRunAction | companion accent (`PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple`) |
| noted | `CodepetTheme.mutedText` |
| navChip | `CodepetTheme.hairline` |

## Font scale (used in Task 2 — reading text only; pixel font untouched elsewhere)

| role | before | after |
|---|---|---|
| bubble body; card title/question | `pixelSystem(12[, .semibold])` | `CodepetTheme.inter(15[, weight: .semibold])` |
| setup name | `pixelSystem(12, .semibold)` | `CodepetTheme.inter(14, weight: .semibold)` |
| secondary (draft body, why lines, noted fact) | `pixelSystem(11)` / `pixelSystem(10)` | `CodepetTheme.inter(13)` |
| interview answer field | `pixelSystem(12)` | `CodepetTheme.inter(14)` |
| primary buttons (Approve/Redo, Send/Skip, verb, nav, first-run) | `pixelSystem(10–11, .semibold)` | `CodepetTheme.inter(12, weight: .semibold)` |
| revise chips (smallest) | `pixelSystem(9, .semibold)` | `CodepetTheme.inter(11, weight: .semibold)` |

---

### Task 1: `MessageCardStyle` (pure) + tests

**Files:**
- Create: `codepet/Models/MessageCardStyle.swift`
- Test: `codepetTests/MessageCardStyleTests.swift`

**Interfaces:**
- Produces: `enum MessageCardKind { case draft, interview, setupSuggestion, firstRunAction, noted, navChip }`; `MessageCardStyle.kind(for: CopilotMessage) -> MessageCardKind?`; `MessageCardStyle.hue(for: MessageCardKind, companionAccent: Color) -> Color`. Consumed by Task 2.
- Consumes: `CopilotMessage` fields (`producing`, `draft`, `interview`, `setupSuggestion`, `firstRunAction`, `noted`, `navChip`), `CodepetTheme` accent tokens.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MessageCardStyleTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import codepet

final class MessageCardStyleTests: XCTestCase {
    private let sentinel = Color.pink   // stand-in companion accent

    func testHueTable() {
        XCTAssertEqual(MessageCardStyle.hue(for: .draft, companionAccent: sentinel), CodepetTheme.accentGold)
        XCTAssertEqual(MessageCardStyle.hue(for: .interview, companionAccent: sentinel), CodepetTheme.accentBlue)
        XCTAssertEqual(MessageCardStyle.hue(for: .setupSuggestion, companionAccent: sentinel), CodepetTheme.accentTeal)
        XCTAssertEqual(MessageCardStyle.hue(for: .noted, companionAccent: sentinel), CodepetTheme.mutedText)
        XCTAssertEqual(MessageCardStyle.hue(for: .navChip, companionAccent: sentinel), CodepetTheme.hairline)
        // firstRunAction returns the companion accent verbatim
        XCTAssertEqual(MessageCardStyle.hue(for: .firstRunAction, companionAccent: sentinel), sentinel)
    }

    func testKindNilForPlainText() {
        let m = CopilotMessage(role: .companion, text: "hello")
        XCTAssertNil(MessageCardStyle.kind(for: m))
    }

    func testKindNilForProducing() {
        let m = CopilotMessage(role: .companion, text: "", producing: true)
        XCTAssertNil(MessageCardStyle.kind(for: m))
    }

    func testKindPerPayload() {
        // Construct minimal valid instances of each payload type by reading their
        // initializers (Deliverable, InterviewGap, SetupAction, FirstRunAction,
        // RememberedFact, NavAction). Set them via CopilotMessage's init args.
        // draft:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(draft: minimalDraft())), .draft)
        // interview:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(interview: minimalGap())), .interview)
        // setupSuggestion:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(setupSuggestion: minimalSetup())), .setupSuggestion)
        // firstRunAction:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(firstRunAction: minimalAction())), .firstRunAction)
        // noted:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(noted: [minimalFact()])), .noted)
        // navChip:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(navChip: minimalNav())), .navChip)
    }

    func testPrecedenceDraftBeatsInterview() {
        let m = msg(draft: minimalDraft(), interview: minimalGap())
        XCTAssertEqual(MessageCardStyle.kind(for: m), .draft)
    }

    // Helpers: implement `msg(...)` as a thin wrapper over CopilotMessage.init with
    // the given payload, and the `minimalX()` factories by reading each payload
    // type's initializer in codepet/Models/. Keep them tiny — just enough to be non-nil.
}
```

Implementer note: fill the `minimalX()` factories by reading each payload type's initializer in `codepet/Models/` (Deliverable, InterviewGap, SetupAction, FirstRunAction, RememberedFact, NavAction). They only need to be valid non-nil instances; field values are irrelevant to `kind(for:)`.

- [ ] **Step 2: Run tests → RED**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "MessageCardStyle|error:" | tail -8`
Expected: compile failure — `MessageCardStyle` / `MessageCardKind` undefined.

- [ ] **Step 3: Implement `MessageCardStyle`**

Create `codepet/Models/MessageCardStyle.swift`:

```swift
import SwiftUI

/// The six interactive message-card kinds and their single semantic hue.
/// Pure + testable. `producing` and plain-text messages are NOT cards (nil).
enum MessageCardKind { case draft, interview, setupSuggestion, firstRunAction, noted, navChip }

enum MessageCardStyle {
    /// Which card kind a message is, from its payload. nil for a producing
    /// placeholder or a plain-text message. Precedence (for the pathological
    /// multi-payload case, and to pin test behaviour):
    /// draft > interview > setupSuggestion > firstRunAction > noted > navChip.
    static func kind(for m: CopilotMessage) -> MessageCardKind? {
        if m.producing { return nil }
        if m.draft != nil { return .draft }
        if m.interview != nil { return .interview }
        if m.setupSuggestion != nil { return .setupSuggestion }
        if m.firstRunAction != nil { return .firstRunAction }
        if let noted = m.noted, !noted.isEmpty { return .noted }
        if m.navChip != nil { return .navChip }
        return nil
    }

    /// The single hue that carries the card's meaning. Gold = a decision is owed.
    static func hue(for kind: MessageCardKind, companionAccent: Color) -> Color {
        switch kind {
        case .draft:           return CodepetTheme.accentGold
        case .interview:       return CodepetTheme.accentBlue
        case .setupSuggestion: return CodepetTheme.accentTeal
        case .firstRunAction:  return companionAccent
        case .noted:           return CodepetTheme.mutedText
        case .navChip:         return CodepetTheme.hairline
        }
    }
}
```

Note: `hue(for: .draft, …)` returns gold unconditionally; the *approved* draft's recede to teal is handled at the call site (Task 2), which knows `draftApproved`.

- [ ] **Step 4: Run tests → GREEN**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "MessageCardStyleTests|Executed [0-9]+ tests" | tail -6`
Expected: MessageCardStyleTests pass; suite shows 0 real failures.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/MessageCardStyle.swift codepetTests/MessageCardStyleTests.swift
git commit -m "feat(chat): pure MessageCardStyle (kind + six semantic hues)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `MessageCard` wrapper + refactor `CopilotBubble` + readability

**Files:**
- Create: `codepet/Views/Copilot/MessageCard.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (the six `CopilotBubble` builders + `textBubble` fonts)

**Interfaces:**
- Consumes: `MessageCardStyle.hue(...)` (Task 1), `CodepetTheme`, `CompanyStore` (already in `CopilotBubble`'s environment), `PetCharacter`.
- Produces: `MessageCard<Content>` view. Final task.

- [ ] **Step 1: Create the `MessageCard` wrapper**

Create `codepet/Views/Copilot/MessageCard.swift`:

```swift
import SwiftUI

/// The one tinted-card construction shared by every interactive chat payload.
/// Only the hue varies (see MessageCardStyle): hue @12% over surface, a same-hue
/// 1pt border, smooth radius 12, uniform padding — matching the redesign's card
/// style. Left-aligned, fills the column width; callers add their own trailing
/// Spacer if they want the card to hug the leading edge.
struct MessageCard<Content: View>: View {
    let hue: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hue.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hue.opacity(0.9), lineWidth: 1))
    }
}
```

- [ ] **Step 2: Add a companion-accent helper to `CopilotBubble`**

In `CopilotChatView.swift`, inside `struct CopilotBubble`, add near the existing `companionName` computed property:

```swift
    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }
```

- [ ] **Step 3: Refactor each payload builder to use `MessageCard` + the font scale**

Apply this transformation to all six builders in `CopilotBubble`: replace the ad-hoc container (`CodepetCard { … }`, or a bare `Capsule`/chip) with `MessageCard(hue: <mapped hue>) { <same inner content> }`, keep the trailing `Spacer(minLength: 24)` where present, keep **every** button/closure/`Task { … }` exactly, and swap `.pixelSystem(...)` reading fonts to `CodepetTheme.inter(...)` per the Font scale table.

**Worked example — `setupCard` (teal). Before → After:**

Before (current):
```swift
        return HStack {
            CodepetCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if let why, !why.isEmpty {
                        Text(why)
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { Task { await companyStore.activateSetup(setup) } } label: {
                        Text(verb)
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                    }.buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 24)
        }
```

After:
```swift
        return HStack {
            MessageCard(hue: MessageCardStyle.hue(for: .setupSuggestion, companionAccent: companionAccent)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(CodepetTheme.inter(14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if let why, !why.isEmpty {
                        Text(why)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { Task { await companyStore.activateSetup(setup) } } label: {
                        Text(verb)
                            .font(CodepetTheme.inter(12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 24)
        }
```
(Note: the inner `.padding(12)`/`.frame(maxWidth:.infinity)` move into `MessageCard`, so drop them from the inner `VStack`. The action `Button`/`Task` is unchanged.)

**Apply the same pattern to the other five:**
- **`draftCard`** — hue `= message.draftApproved ? CodepetTheme.accentTeal : CodepetTheme.accentGold`. Wrap the existing draft `VStack` (title/body tap-to-open, the approved "Added to Library" row, the Approve/Redo `HStack`, and the Revise chips `HStack`) in `MessageCard(hue:)`; drop the old `CodepetCard` + its inner `.padding(12)`/`.frame`. Fonts: title `inter(15,.semibold)`, body `inter(13)`, "Added to Library" `inter(12,.semibold)`, Approve/Redo `inter(12,.semibold)`, revise chips `inter(11,.semibold)`. Keep `.sheet(isPresented:)`, `onTapGesture`, and all `Task { await … }` calls verbatim.
- **`interviewCard`** — hue `.interview` (blue). Wrap the existing `VStack` (ask/why/TextField/Send/Skip) in `MessageCard`; drop the old `RoundedRectangle` background + inner `.padding(12)`. Fonts: ask `inter(15,.semibold)`, why `inter(13)`, TextField `inter(14)`, Send/Skip `inter(12,.semibold)`. Keep the `interviewDraft` binding + both `Task { await companyStore.answerInterview(...) }` closures verbatim.
- **`notedChip`** — hue `.noted` (muted). Wrap the facts `VStack` in `MessageCard`; drop the per-fact `Capsule().fill(surface)`. Fonts: each fact `inter(13)`.
- **`navChip`** — hue `.navChip` (hairline). Wrap the "Go to {label}" `Button` in `MessageCard`; the button keeps `companyStore.activateNav(nav)`. Font `inter(12,.semibold)`. (Because the hairline tint is subtle, keep the button's own filled `Capsule().fill(CodepetTheme.accentPurple)` so the tap target still reads as a control inside the neutral card.)
- **`actionButton` (firstRunAction)** — hue `.firstRunAction` (companion accent). Wrap the "Do it with me: {task}" `Button` in `MessageCard`; keep `runFirstRunAction`. Font `inter(13,.semibold)`. (The greeting `textBubble` above it in `body` lines 187–192 stays a plain bubble — only the action becomes the card.)

- [ ] **Step 4: Readability on the plain bubbles — `textBubble`**

In `textBubble`, change both the `me` and companion message `Text(message.text)` fonts from `.pixelSystem(size: 12)` to `CodepetTheme.inter(15)`. Leave layout/colors/alignment unchanged.

- [ ] **Step 5: Build**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Fix any leftover reference (e.g. an orphaned `.padding` now doubled).

- [ ] **Step 6: Run the full suite**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3`
Expected: `codepetTests.xctest` shows 0 real failures (known Firebase flake aside).

- [ ] **Step 7: Commit**

```bash
git add codepet/Views/Copilot/MessageCard.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): one tinted card grammar for all payloads + Inter reading text

MessageCard wraps every payload (draft=gold decision-owed, interview=blue,
setup=teal, first-run=companion, noted=muted, nav=hairline; approved draft
recedes to teal). Chat body + card text move pixelSystem -> inter(~15) for
Claude/ChatGPT-grade readability. Actions unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (controller, human sign-off)

Rebase over any concurrent branch commits, push, then build & launch signed (quit stale instance by pid, `xcodebuild … -allowProvisioningUpdates`, `open`). Founder verifies on screen: each payload is a tinted card with its hue; a draft awaiting approval is gold and recedes to teal after Approve; nav/noted are subtle; text is clearly larger/cleaner in light + dark; Approve/Redo/nav/setup/interview all still work.

---

## Self-Review

**1. Spec coverage:** §10 kind+hue → Task 1. `MessageCard` construction → Task 2 Step 1. Six builders wrapped w/ mapped hue + approved-draft recede → Task 2 Step 3. Readability font scale → Task 2 Steps 3–4. Tests (hue table, kind per payload, nil for plain/producing, precedence) → Task 1. Build/suite/signed visual → Task 2 + post. ✓

**2. Placeholder scan:** Concrete code for `MessageCardStyle`, `MessageCard`, the hue/font tables, and a fully-worked `setupCard` example; the other five have exact hue + font + "keep actions" instructions. The only implementer-filled bits are the test `minimalX()` fixtures (payload types whose inits live in the repo) — explicitly flagged, not a vague gap. ✓

**3. Type consistency:** `MessageCardStyle.kind/hue` and `MessageCardKind` defined Task 1, used Task 2. `MessageCard(hue:)` defined Task 2 Step 1, used Step 3. `companionAccent` helper defined Step 2, used Step 3. Hue tokens (`accentGold/accentBlue/accentTeal/mutedText/hairline`) confirmed present in `CodepetTheme`. Font API `CodepetTheme.inter(_:weight:)` matches existing usage. ✓
