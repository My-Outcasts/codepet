# First-run / empty chat state — live landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A pure `ChatLandingState` drives the empty-chat greeting + up to three live roadmap cards (beacon / needs-you / awaiting-approval), falling back to three composer-filling prompt starters when there's no roadmap.

**Architecture:** `ChatLandingState` (pure, tested) computed from `CompanyState`; `ChatEmptyState` swaps its static `QuickAction` grid for live cards / starters driven by that state; `CopilotChatView` builds the state and supplies open-roadmap + fill-composer handlers. Composer + `+` quick-actions unchanged.

**Tech Stack:** SwiftUI (macOS), CodepetTheme, RoadmapEngine, Xcode.

## Global Constraints

- Repo/branch: `My-Outcasts/codepet`, `feat/chat-redesign` (PR #39). Held. Rebase over concurrent commits before pushing.
- Build/test **FOREGROUND** only: `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- Synchronized folder groups — new `.swift` auto-includes; **no `project.pbxproj` edit**.
- SourceKit "Cannot find … in scope" for these files are known FALSE POSITIVES; `xcodebuild` is authoritative.
- Baseline suite: **0 real failures**; trailing overall `** TEST FAILED **` = known `CompanyStoreScaffordOnboardingTests` Firebase-init flake (NOT a regression; wobbles the COUNT — judge by "0 failures").
- **Greeting copy is MOVED, not rewritten** — must match today's wording exactly. The composer's `+` quick-actions menu stays. Starters INSERT into the composer (do not send).
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Card look + taps are human-verified on a signed build (controller builds & launches).

## Verified APIs

- `RoadmapEngine.nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask?`; `RoadmapEngine.status(for: RoadmapTask, in: [RoadmapTask]) -> TaskStatus`.
- `TaskStatus`: `done, needsApproval, blocked, needsYou, codepetCanDo`.
- `RoadmapTask.id: String`, `.title: String`. `CompanyState.tasks: [RoadmapTask]`, `.brief.founderName: String?`, `.brief.projectName: String?`, and `CompanyState.empty` exists.
- Nav: `companyStore.select(.roadmap)`; `companyStore.selectedDeptKey`.

---

### Task 1: `ChatLandingState` (pure) + tests

**Files:**
- Create: `codepet/Models/ChatLandingState.swift`
- Test: `codepetTests/ChatLandingStateTests.swift`

**Interfaces:**
- Produces: `struct ChatLandingState` with `init(company:now:language:)` and `greeting/question/beacon/needsYouCount/awaitingApprovalCount/isEmpty`. Consumed by Task 2.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/ChatLandingStateTests.swift`:

```swift
import XCTest
@testable import codepet

final class ChatLandingStateTests: XCTestCase {
    private func date(hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 28; c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }
    private func company(founder: String? = "Mona", project: String? = "Acme",
                         tasks: [RoadmapTask] = []) -> CompanyState {
        var b = CompanyBrief(); b.founderName = founder; b.projectName = project
        var c = CompanyState.empty; c.brief = b; c.tasks = tasks
        return c
    }

    func testGreetingHourBoundaries() {
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 11), language: .en).greeting.hasPrefix("Good morning"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 12), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 17), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 18), language: .en).greeting.hasPrefix("Good evening"))
    }
    func testGreetingFounderNameAndFallback() {
        XCTAssertEqual(ChatLandingState(company: company(founder: "Mona"), now: date(hour: 9), language: .en).greeting, "Good morning, Mona.")
        XCTAssertEqual(ChatLandingState(company: company(founder: "  "), now: date(hour: 9), language: .en).greeting, "Good morning, there.")
        XCTAssertEqual(ChatLandingState(company: company(founder: nil), now: date(hour: 9), language: .vi).greeting, "Chào buổi sáng, bạn.")
    }
    func testQuestionUsesProjectWithFallback() {
        XCTAssertTrue(ChatLandingState(company: company(project: "Acme"), now: date(hour: 9), language: .en).question.contains("Acme"))
        XCTAssertTrue(ChatLandingState(company: company(project: " "), now: date(hour: 9), language: .en).question.contains("Codepet"))
    }
    func testBeaconCountsAndEmpty() {
        XCTAssertTrue(ChatLandingState(company: company(tasks: []), now: date(hour: 9), language: .en).isEmpty)
        // Build a small fixture; assert beacon == RoadmapEngine.nextStep and counts match the engine's status.
        let tasks = SampleRoadmap.mixed()   // implementer: construct a few RoadmapTasks (done / drafted / who==.you / codepetCanDo)
        let s = ChatLandingState(company: company(tasks: tasks), now: date(hour: 9), language: .en)
        XCTAssertEqual(s.beacon?.id, RoadmapEngine.nextStep(tasks)?.id)
        XCTAssertEqual(s.awaitingApprovalCount, tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count)
        XCTAssertEqual(s.needsYouCount, tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != s.beacon?.id }.count)
        XCTAssertFalse(s.isEmpty)
    }
}
```
Implementer note: replace `SampleRoadmap.mixed()` with an inline array of a few `RoadmapTask(...)` built from the real initializer (read `RoadmapTask.swift`) — include at least one `done`, one `drafted` (→ needsApproval), and one `who == .you` not-done (→ needsYou). The assertions derive expected values from `RoadmapEngine`, so they hold for whatever fixture you build.

- [ ] **Step 2: Run tests → RED**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatLandingState|error:" | tail -8`
Expected: compile failure — `ChatLandingState` undefined.

- [ ] **Step 3: Implement `ChatLandingState`**

Create `codepet/Models/ChatLandingState.swift`:

```swift
import Foundation

/// Pure landing-state for the empty chat: greeting + the live roadmap signals
/// that drive the landing cards. Deterministic given `now`. SwiftUI-free.
struct ChatLandingState {
    let greeting: String
    let question: String
    let beacon: RoadmapTask?
    let needsYouCount: Int
    let awaitingApprovalCount: Int
    let isEmpty: Bool

    init(company: CompanyState, now: Date, language: AppLanguage) {
        let founderRaw = (company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let founder = founderRaw.isEmpty ? (language == .vi ? "bạn" : "there") : founderRaw
        let hour = Calendar.current.component(.hour, from: now)
        let part: String
        switch hour {
        case ..<12:   part = language == .vi ? "Chào buổi sáng" : "Good morning"
        case 12..<18: part = language == .vi ? "Chào buổi chiều" : "Good afternoon"
        default:      part = language == .vi ? "Chào buổi tối" : "Good evening"
        }
        greeting = "\(part), \(founder)."

        let projectRaw = (company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let project = projectRaw.isEmpty ? "Codepet" : projectRaw
        question = language == .vi ? "Hôm nay mình xây gì cho \(project)?" : "What should we build for \(project) today?"

        let tasks = company.tasks
        let next = RoadmapEngine.nextStep(tasks)
        beacon = next
        needsYouCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != next?.id }.count
        awaitingApprovalCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count
        isEmpty = tasks.isEmpty
    }
}
```

- [ ] **Step 4: Run tests → GREEN**

Run: `xcodebuild test … CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatLandingStateTests|Executed [0-9]+ tests" | tail -6`
Expected: ChatLandingState tests pass; suite 0 real failures.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ChatLandingState.swift codepetTests/ChatLandingStateTests.swift
git commit -m "feat(chat): pure ChatLandingState (greeting + live roadmap signals)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `ChatEmptyState` live landing + wiring

**Files:**
- Modify: `codepet/Views/Copilot/ChatEmptyState.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: `ChatLandingState` (Task 1); `companyStore.select(.roadmap)`; `CodepetTheme` accents.

- [ ] **Step 1: Re-input `ChatEmptyState`**

Replace `line1/line2/quickActions/onQuickAction` with:
```swift
    let state: ChatLandingState
    let onOpenRoadmap: () -> Void
    let onStarter: (String) -> Void
    @ViewBuilder var composer: Composer
    @Environment(\.uiLanguage) private var lang
```
Update `greeting` to read `state.greeting` (line 1) and `state.question` (line 2) — same fonts/gradient/layout as today (just swap `line1`→`state.greeting`, `line2`→`state.question`).

- [ ] **Step 2: Replace the `cards`/`card(_:)` with live cards + starters**

```swift
    private var cards: some View {
        Group {
            if state.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(starters, id: \.self) { starterCard($0) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let b = state.beacon {
                        landingCard(eyebrow: lang == .vi ? "TIẾP THEO" : "DO THIS NEXT",
                                    value: b.title, hue: CodepetTheme.accentPurple, onTap: onOpenRoadmap)
                    }
                    if state.needsYouCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CẦN BẠN" : "NEEDS YOU",
                                    value: "\(state.needsYouCount)", hue: CodepetTheme.accentBlue, onTap: onOpenRoadmap)
                    }
                    if state.awaitingApprovalCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CHỜ DUYỆT" : "AWAITING APPROVAL",
                                    value: "\(state.awaitingApprovalCount)", hue: CodepetTheme.accentGold, onTap: onOpenRoadmap)
                    }
                }
            }
        }
        .frame(maxWidth: 600)
    }

    private var starters: [String] {
        lang == .vi
            ? ["Soạn định vị của tôi", "Lên kế hoạch tuần này", "Xem lại bản tóm tắt"]
            : ["Draft my positioning", "Plan this week", "Review my brief"]
    }

    private func landingCard(eyebrow: String, value: String, hue: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Capsule().fill(hue).frame(width: 3).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(CodepetTheme.inter(10, weight: .semibold))
                        .foregroundColor(hue).tracking(0.5)
                    Text(value).font(CodepetTheme.inter(14, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
        }.buttonStyle(.plain)
    }

    private func starterCard(_ text: String) -> some View {
        Button { onStarter(text) } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(CodepetTheme.accentPurple)
                Text(text).font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
        }.buttonStyle(.plain)
    }
```
Delete the old `QuickAction`-based `card(_:)` and the `quickActions` references in this file (the type stays for the composer's `+` menu — just not used here).

- [ ] **Step 3: Update the `#Preview`**

The `ChatEmptyState` `#Preview` must build a `ChatLandingState` fixture and the handlers:
```swift
    ChatEmptyState(
        state: ChatLandingState(company: .empty, now: Date(), language: .en),
        onOpenRoadmap: {}, onStarter: { _ in }
    ) { RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 96).frame(maxWidth: 600) }
        .frame(width: 900, height: 700).background(Color.black).environmentObject(CompanyStore())
```
(`.empty` has no tasks → the preview shows the starter fallback, which is fine.)

- [ ] **Step 4: Wire `CopilotChatView`**

- In the empty branch, replace the `ChatEmptyState(line1:…, line2:…, quickActions:…, onQuickAction:…)` call with:
```swift
                ChatEmptyState(
                    state: ChatLandingState(company: companyStore.company, now: Date(), language: lang),
                    onOpenRoadmap: { companyStore.selectedDeptKey = nil; companyStore.select(.roadmap) },
                    onStarter: { draft = $0; inputFocused = true }
                ) { composerView }
```
- Remove `greetingLine1` and `greetingLine2` (now in `ChatLandingState`). If `founderName`/`companyName` are now unreferenced anywhere else in the file, remove them too (the build will confirm; leave them only if still used).
- Keep `quickActions` and `runQuickAction` — they still feed the composer's `+` menu via `composerView`.

- [ ] **Step 5: Build + full suite**

`xcodebuild build … CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **`
`xcodebuild test … CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3` → `codepetTests.xctest` 0 real failures.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/ChatEmptyState.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): live landing cards (beacon/needs-you/awaiting) + starters

Empty chat now renders up to 3 live roadmap cards from ChatLandingState
(tap → Roadmap), or 3 composer-filling prompt starters when there's no
roadmap yet. Greeting moved into ChatLandingState (copy unchanged). The
composer + quick-actions menu are unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (controller, human sign-off)

Rebase over concurrent commits, push, build & launch signed. Founder verifies: with a roadmap → DO THIS NEXT shows the beacon title + NEEDS YOU / AWAITING APPROVAL counts (when >0), each tapping to the Roadmap page; with no roadmap → three starter cards that fill the composer (not send); greeting reads right; light + dark.

---

## Self-Review

**1. Spec coverage:** ChatLandingState (greeting/question/beacon/counts/isEmpty) → Task 1. Live cards + omit-when-zero + tap→roadmap → Task 2 Step 2. Starter fallback that fills composer → Step 2 + Step 4 (`onStarter`). Greeting moved (copy unchanged) → Task 1 + Step 1. Composer `+` unchanged → Step 4 note. Tests (hour boundaries, founder/project fallbacks, beacon/counts/empty) → Task 1. ✓

**2. Placeholder scan:** Full code for `ChatLandingState`, the card/starters builders, the wiring, and the preview. The one implementer-filled bit is the test roadmap fixture (`SampleRoadmap.mixed()` → inline `RoadmapTask`s from the real init) — explicitly flagged with what it must contain, and the assertions derive expected values from `RoadmapEngine` so they can't drift. ✓

**3. Type consistency:** `ChatLandingState(company:now:language:)` + its fields defined Task 1, consumed in Task 2 Steps 1–4. `RoadmapEngine.nextStep`/`status(for:in:)`, `TaskStatus.needsYou/.needsApproval`, `RoadmapTask.id/.title`, `CompanyState.empty/.tasks/.brief`, `companyStore.select(.roadmap)` all confirmed present. `onOpenRoadmap`/`onStarter` closures match the wiring. ✓
