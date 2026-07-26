# Enrichment interview (native) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the web app's first-run "enrichment interview" to the native macOS SwiftUI app, FULLY CLIENT-SIDE. After onboarding finishes, detect which of the three plan-shaping brief fields (`goal`, `traction`, `problem`) are empty, then ask up to 3 short, skippable follow-up questions ONE AT A TIME as an inline card in the Copilot chat. A non-blank answer is saved RAW (no LLM distillation) into that brief field; skip/blank advances. When gaps are exhausted (or there were none), the existing first-run greeting fires unchanged.

**Architecture:** A pure, dependency-free helper (`EnrichInterview`) owns the gap enum, priority order, `detectGaps`, and localized static `question(for:language:)`. `CompanyBrief` gains three optional `String?` fields threaded through its memberwise init and `hasAnySignal`. `CopilotMessage` gains additive `interview: InterviewGap?` + `interviewAnswered: Bool` fields mirroring the `firstRunAction`/`actionConsumed` precedent. `CopilotBubble` gains a parallel `interview` render branch (question + why-line + `TextField` + Send/Skip while unanswered, collapsing to a plain bubble once answered). `CompanyStore.finishOnboarding` triggers `startEnrichInterviewIfNeeded` AFTER the brief save/stamp and BEFORE `seedFirstRunGreeting`; `answerInterview` mutates the brief field, persists via the existing `saver`, and advances or hands off to `seedFirstRunGreeting`. A private in-memory `interviewState` (gaps + idx) mirrors the web `useRef` — session-only, never persisted.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS app in `~/Documents/Murror/codepet`.

## Global Constraints

- **Client-only:** No Cloud Function, no server route, no deploy. The web distills answers via an LLM server route; we intentionally skip that and save the founder's RAW trimmed text verbatim.
- **Build (foreground):** `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` — must end in `** BUILD SUCCEEDED **`. Never background xcodebuild.
- **Scoped test:** `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<TestClass>`.
- **Backward-compatible Codable:** new brief fields are optional with `= nil` defaults; old Firestore docs decode to `nil`.
- **One gap at a time**, serial — mirror the existing `firstRunAction` single-message-then-append pattern.
- **Raw-text save (no distillation).** Any non-blank answer = filled; blank/skip advances without saving. Gap predicate = trimmed non-empty; order `[goal, traction, problem]`.
- **Trigger only inside `finishOnboarding`** (fires once), after save/stamp, before greeting. Reuse the existing `saver` (`CompanyData.saveBrief`) and `seedFirstRunGreeting` unchanged.
- **Every task builds independently.** Task order is deliberately model-field (T3) → store methods (T4) → UI branch (T5) so no task references a symbol that doesn't exist yet.
- **Tests:** Pure helpers (`CompanyBrief` fields, `EnrichInterview`) get struct-only XCTests with NO `@MainActor` (Xcode 26.2 hosted-teardown bug). `CompanyStore` methods are `@MainActor`; keep them build-verified and covered by the pure gap/question tests rather than hosted `@MainActor` teardown.
- **Copy:** English + Vietnamese, both provided verbatim below. EN ported from `lib/ai/enrichInterview.ts`; VI added here.
- **House style:** Match `CopilotChatView` idioms — `.pixelSystem`, `CodepetTheme`, `Capsule`/`RoundedRectangle`, `.buttonStyle(.plain)`.
- **Verify real signatures.** Every code block below was written from a repo read but MUST be confirmed against actual source before writing; if an init label, theme token (`CodepetTheme.bodyText`/`hairline`/`surface`/`accentPurple`/`mutedText`/`primaryText`), or property name differs, adapt to the real one — do not invent APIs, do not restructure the model layer.
- **Branch:** `feat/enrichment-interview-native`, based on `origin/main`.

---

### Task 1: CompanyBrief goal/traction/problem fields + tests

**Files:**
- Edit: `codepet/Models/CompanyBrief.swift`
- Edit: `codepetTests/CompanyBriefTests.swift`

**Interfaces (produced):** three optional stored props `goal/traction/problem: String?`, threaded through the memberwise `init` with `= nil` defaults, added to `hasAnySignal`. Consumed by Tasks 2 and 4.

- [ ] **Step 1: Add failing tests** — append to `codepetTests/CompanyBriefTests.swift` (match the existing struct-only, non-`@MainActor` style; confirm the real `hasAnySignal` name + how the file constructs briefs):

```swift
func testGoalTractionProblemRoundTrip() throws {
    let brief = CompanyBrief(goal: "Ship v1", traction: "40 on waitlist", problem: "Recaps are manual")
    let data = try JSONEncoder().encode(brief)
    let decoded = try JSONDecoder().decode(CompanyBrief.self, from: data)
    XCTAssertEqual(decoded, brief)
}

func testOldDocDecodesNewFieldsToNil() throws {
    let decoded = try JSONDecoder().decode(CompanyBrief.self, from: Data("{}".utf8))
    XCTAssertNil(decoded.goal)
    XCTAssertNil(decoded.traction)
    XCTAssertNil(decoded.problem)
}

func testHasAnySignal_goalOnlyIsTrue() { XCTAssertTrue(CompanyBrief(goal: "Ship v1").hasAnySignal) }
func testHasAnySignal_tractionOnlyIsTrue() { XCTAssertTrue(CompanyBrief(traction: "40 users").hasAnySignal) }
func testHasAnySignal_problemOnlyIsTrue() { XCTAssertTrue(CompanyBrief(problem: "Manual recaps").hasAnySignal) }
func testHasAnySignal_blankGoalIsFalse() { XCTAssertFalse(CompanyBrief(goal: "  ").hasAnySignal) }
```

- [ ] **Step 2: Run tests, confirm they fail** (unknown `goal`/`traction`/`problem` args).

- [ ] **Step 3: Implement** — in `codepet/Models/CompanyBrief.swift`, add three stored props after `audience`:

```swift
/// Founder's immediate goal for the next few weeks (drives task priority).
/// Filled by the first-run enrichment interview; raw founder text, not distilled.
var goal: String?
/// Real traction/assets: waitlist, users, revenue, anything live.
var traction: String?
/// The problem the product solves + who feels it most (sharpens positioning).
var problem: String?
```

Extend the init signature + body to thread the three new params (`= nil` defaults), and extend `hasAnySignal`'s chain to include `s(goal) || s(traction) || s(problem)`. (Adapt to the real init/`hasAnySignal` shapes — match the file's existing compact style.)

- [ ] **Step 4:** `xcodebuild test ... -only-testing:codepetTests/CompanyBriefTests` → all pass.
- [ ] **Step 5:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** — `feat: add goal/traction/problem to CompanyBrief` (+ Co-Authored-By trailer).

---

### Task 2: Pure EnrichInterview helper + tests

**Files:**
- Create: `codepet/Models/EnrichInterview.swift`
- Create: `codepetTests/EnrichInterviewTests.swift`

**Interfaces (produced):**
- `enum InterviewGap: String, CaseIterable, Equatable { case goal, traction, problem }`
- `struct InterviewQuestion: Equatable { let ask: String; let why: String }`
- `enum EnrichInterview { static let gapOrder; static let maxQuestions = 3; static func detectGaps(_ brief: CompanyBrief?) -> [InterviewGap]; static func question(for:language:) -> InterviewQuestion }`
Consumed by Tasks 4 and 5.

- [ ] **Step 1: Write failing tests** — create `codepetTests/EnrichInterviewTests.swift` (struct-only, NO `@MainActor`):

```swift
import XCTest
@testable import codepet

final class EnrichInterviewTests: XCTestCase {
    func testNilBriefIsAllThreeGapsInOrder() {
        XCTAssertEqual(EnrichInterview.detectGaps(nil), [.goal, .traction, .problem])
    }
    func testEmptyBriefIsAllThreeGaps() {
        XCTAssertEqual(EnrichInterview.detectGaps(CompanyBrief()), [.goal, .traction, .problem])
    }
    func testFilledFieldsAreExcludedPreservingOrder() {
        let b = CompanyBrief(goal: "Ship v1", problem: "Manual recaps")
        XCTAssertEqual(EnrichInterview.detectGaps(b), [.traction])
    }
    func testBlankFieldCountsAsGap() {
        XCTAssertEqual(EnrichInterview.detectGaps(CompanyBrief(goal: "   ")), [.goal, .traction, .problem])
    }
    func testFullBriefHasNoGaps() {
        let b = CompanyBrief(goal: "a", traction: "b", problem: "c")
        XCTAssertTrue(EnrichInterview.detectGaps(b).isEmpty)
    }
    func testNeverMoreThanMaxQuestions() {
        XCTAssertLessThanOrEqual(EnrichInterview.detectGaps(CompanyBrief()).count, EnrichInterview.maxQuestions)
    }
    func testEnglishGoalQuestion() {
        let q = EnrichInterview.question(for: .goal, language: .en)
        XCTAssertEqual(q.ask, "What\u{2019}s your main goal for the next few weeks?")
        XCTAssertTrue(q.why.contains("get you there first"))
    }
    func testVietnameseTractionQuestionIsLocalized() {
        let q = EnrichInterview.question(for: .traction, language: .vi)
        XCTAssertTrue(q.ask.contains("danh sách chờ"))
        XCTAssertFalse(q.why.isEmpty)
    }
}
```

- [ ] **Step 2: Run, confirm build fails** (`EnrichInterview` not found).

- [ ] **Step 3: Implement** `codepet/Models/EnrichInterview.swift`:

```swift
// codepet/Models/EnrichInterview.swift
import Foundation

/// One of the three plan-shaping brief fields the first-run interview fills,
/// in priority order. Verbatim-logic port of the web `Gap` (lib/ai/enrichInterview.ts).
enum InterviewGap: String, CaseIterable, Equatable {
    case goal, traction, problem
}

/// byte's question for a gap plus the one-line reason it's asking (so it reads
/// like a companion, not a form).
struct InterviewQuestion: Equatable {
    let ask: String
    let why: String
}

/// Pure, dependency-free gap detector + static question copy. No I/O, no LLM —
/// unit-tested. The web distills answers via a server route; we intentionally
/// save the founder's raw text instead, so there is no distill logic here.
enum EnrichInterview {
    /// Priority order: goal (drives task priority), then traction (grounds the
    /// numbers), then problem (sharpens positioning). `detectGaps` preserves it.
    static let gapOrder: [InterviewGap] = [.goal, .traction, .problem]

    /// The most gaps byte asks about in one interview — keep it short.
    static let maxQuestions = 3

    private static func filled(_ v: String?) -> Bool {
        guard let v else { return false }
        return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func value(_ brief: CompanyBrief, _ gap: InterviewGap) -> String? {
        switch gap {
        case .goal: return brief.goal
        case .traction: return brief.traction
        case .problem: return brief.problem
        }
    }

    /// The empty plan-shaping fields, in priority order. A nil brief means ask all
    /// three; a full brief returns []. Never more than `maxQuestions`.
    static func detectGaps(_ brief: CompanyBrief?) -> [InterviewGap] {
        guard let brief else { return Array(gapOrder.prefix(maxQuestions)) }
        return Array(gapOrder.filter { !filled(value(brief, $0)) }.prefix(maxQuestions))
    }

    /// Static question + why-line per gap, localized. EN ported from the web
    /// `QUESTION_FOR`; VI added natively.
    static func question(for gap: InterviewGap, language: AppLanguage) -> InterviewQuestion {
        switch gap {
        case .goal:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Mục tiêu chính của bạn trong vài tuần tới là gì?",
                    why: "để mình ưu tiên những việc thật sự đưa bạn tới đó trước")
                : InterviewQuestion(
                    ask: "What\u{2019}s your main goal for the next few weeks?",
                    why: "so byte plans the moves that actually get you there first")
        case .traction:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Hiện tại bạn đang ở đâu — danh sách chờ, người dùng, doanh thu, đã có gì chạy chưa?",
                    why: "để các con số trong kế hoạch là của bạn, không phải bịa ra")
                : InterviewQuestion(
                    ask: "Where are you right now — waitlist, users, revenue, anything live yet?",
                    why: "so the numbers in your plan are yours, not made up")
        case .problem:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Sản phẩm giải quyết vấn đề gì, và ai cảm nhận rõ nhất?",
                    why: "để định vị và nội dung của bạn nói đúng người dùng thật")
                : InterviewQuestion(
                    ask: "What problem does it solve, and who feels it most?",
                    why: "so your positioning and copy speak to the real user")
        }
    }
}
```

- [ ] **Step 4:** `xcodebuild test ... -only-testing:codepetTests/EnrichInterviewTests` → all pass.
- [ ] **Step 5:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** — `feat: add EnrichInterview gap-detection helper` (+ trailer).

---

### Task 3: CopilotMessage interview payload (model field only)

**Files:**
- Edit: `codepet/Models/CopilotMessage.swift`

**Interfaces (produced):** `var interview: InterviewGap?` + `var interviewAnswered: Bool` on `CopilotMessage`, threaded through its init with defaults (`nil` / `false`), mirroring the existing `firstRunAction`/`actionConsumed` two-field precedent. Consumed by Tasks 4 and 5. This task is MODEL-ONLY (no UI, no store) so it builds standalone — nothing references the new fields yet.

- [ ] **Step 1: Add stored props** after `actionConsumed` (confirm the real struct/init first):

```swift
/// First-run enrichment interview: the gap this message asks about; nil otherwise.
var interview: InterviewGap?
/// True once the founder has answered or skipped — collapses the card to a plain bubble.
var interviewAnswered: Bool
```

- [ ] **Step 2: Extend the init** — append `interview: InterviewGap? = nil, interviewAnswered: Bool = false` to the parameter list (after `actionConsumed`) and assign both in the body. Keep every existing param/label unchanged (defaults mean all existing call sites still compile).

- [ ] **Step 3:** Build → `** BUILD SUCCEEDED **` (no other file changed; existing `CopilotMessage(...)` calls compile unchanged via defaults).
- [ ] **Step 4: Commit** — `feat: add interview payload to CopilotMessage` (+ trailer).

---

### Task 4: CompanyStore start/answer methods + wire into finishOnboarding

**Files:**
- Edit: `codepet/Managers/CompanyStore.swift`

**Interfaces:** private `interviewState: (gaps: [InterviewGap], idx: Int)?` (session-only, NOT persisted); `startEnrichInterviewIfNeeded(language:) -> Bool`; `answerInterview(messageId:gap:answer:language:) async`; trigger wired into `finishOnboarding`. Consumes `EnrichInterview` (T2) + `CopilotMessage.interview` field (T3). Produces `answerInterview` (consumed by T5).

Read the real `finishOnboarding`, `seedFirstRunGreeting`, the `saver` closure, `companyId`, `reset()`, and the `chatMessages` append idiom first; adapt to the real signatures (the tail-replacement below assumes the current `finishOnboarding` body — confirm it).

- [ ] **Step 1: Add the in-memory state** near the other private fields:

```swift
/// First-run enrichment interview progress: the empty gaps to ask + the index
/// we're on. Session-only, never persisted (mirrors the web useRef). Nil when
/// no interview is active.
private var interviewState: (gaps: [InterviewGap], idx: Int)?
```

- [ ] **Step 2: Add the start + advance helpers:**

```swift
/// First-run only: after the brief is saved + stamped, ask the ≤3 plan-shaping
/// questions the onboarding brief is missing (goal / traction / problem), one at
/// a time. A full brief means no gaps → caller falls through to the greeting.
/// Returns true when an interview was started (so the caller skips the greeting).
private func startEnrichInterviewIfNeeded(language: AppLanguage) -> Bool {
    guard companyId != nil else { return false }
    let gaps = EnrichInterview.detectGaps(company.brief)
    guard !gaps.isEmpty else { return false }
    interviewState = (gaps: gaps, idx: 0)
    askInterviewGap(gaps[0], language: language)
    return true
}

/// Append one interview question as a companion message carrying its gap. The
/// message text is the question itself, so once answered the card collapses to a
/// plain bubble showing that question (matches the web `answered` branch).
private func askInterviewGap(_ gap: InterviewGap, language: AppLanguage) {
    let q = EnrichInterview.question(for: gap, language: language)
    chatMessages.append(CopilotMessage(role: .companion, text: q.ask, interview: gap))
}

/// Answer (or skip) the current interview question. A non-blank answer is saved
/// RAW (trimmed, no distillation) into the brief field and persisted via the
/// existing saver — durable on mid-interview drop-off. Blank/nil = skip: advance
/// without saving. Then ask the next gap, or hand off to the first-run greeting.
func answerInterview(messageId: String, gap: InterviewGap, answer: String?, language: AppLanguage) async {
    guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
          !chatMessages[i].interviewAnswered else { return }
    chatMessages[i].interviewAnswered = true

    let trimmed = (answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, let cid = companyId {
        switch gap {
        case .goal: company.brief.goal = trimmed
        case .traction: company.brief.traction = trimmed
        case .problem: company.brief.problem = trimmed
        }
        _ = await saver(cid, company.brief)
        guard companyId == cid else { return }  // account switched mid-await → bail
    }

    guard var st = interviewState else { return }
    st.idx += 1
    if st.idx < st.gaps.count {
        interviewState = st
        askInterviewGap(st.gaps[st.idx], language: language)
    } else {
        interviewState = nil
        seedFirstRunGreeting(language: language)
    }
}
```

(Confirm the real `saver` call shape and that `company.brief.goal` etc. are mutable on the `@Published var company`. If `seedFirstRunGreeting` is `private`, these methods are in the same type so that's fine.)

- [ ] **Step 3: Wire the trigger into `finishOnboarding`** — replace the final `seedFirstRunGreeting(language: language)` call at the tail of `finishOnboarding` with:

```swift
if !startEnrichInterviewIfNeeded(language: language) {
    seedFirstRunGreeting(language: language)
}
```

(Leave the brief save / `company.brief =` / `onboardedAt` / `isOnboarding = false` lines above it unchanged. When gaps exist, the greeting fires later from `answerInterview`'s exhaustion branch; when none, it fires now — today's behavior.)

- [ ] **Step 4: Clear interview state in `reset()`** — add `interviewState = nil` alongside the other clears (confirm `reset()` exists and is where account-switch/sign-out clearing happens; if the clearing method has a different name, add it there).

- [ ] **Step 5:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** — `feat: enrichment interview flow in CompanyStore (start/answer + trigger)` (+ trailer).

Coverage note: the gap/question logic is covered by `EnrichInterviewTests` (T2). These methods are `@MainActor`; do NOT add hosted `@MainActor` teardown tests (Xcode 26.2 bug) — rely on the pure tests + build verification.

---

### Task 5: CopilotBubble InterviewCard render branch

**Files:**
- Edit: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:** consumes `message.interview`/`interviewAnswered` (T3), `EnrichInterview.question` (T2), and `companyStore.answerInterview` (T4). Produces the inline card UI.

Read the real `CopilotBubble` first: confirm it has `companyStore` + `lang` in scope (the existing `firstRunAction` branch calls the store, so it should), the exact `if let draft ... else if let action = message.firstRunAction ... else { textBubble }` chain, and the real theme tokens used nearby. Adapt token names if any below differ.

- [ ] **Step 1: Add the input state** to `CopilotBubble`:

```swift
@State private var interviewDraft = ""
```

- [ ] **Step 2: Add a parallel branch** in `CopilotBubble.body`'s if/else chain, after the `firstRunAction` branch and before the plain `else { textBubble }`:

```swift
} else if let gap = message.interview, !message.interviewAnswered {
    interviewCard(gap)
} else {
    textBubble
}
```

- [ ] **Step 3: Add the card view** to `CopilotBubble`:

```swift
private func interviewCard(_ gap: InterviewGap) -> some View {
    let q = EnrichInterview.question(for: gap, language: lang)
    let canSend = !interviewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return HStack {
        VStack(alignment: .leading, spacing: 8) {
            Text(q.ask)
                .font(.pixelSystem(size: 12, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(q.why)
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            TextField(lang == .vi ? "Nhập câu trả lời…" : "Type your answer…",
                      text: $interviewDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.pixelSystem(size: 12))
                .lineLimit(1...4)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodepetTheme.surface))
            HStack(spacing: 8) {
                Button {
                    let answer = interviewDraft
                    interviewDraft = ""
                    Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: answer, language: lang) }
                } label: {
                    Text(lang == .vi ? "Gửi" : "Send")
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(canSend ? CodepetTheme.accentPurple : CodepetTheme.mutedText))
                }
                .buttonStyle(.plain).disabled(!canSend)
                Button {
                    interviewDraft = ""
                    Task { await companyStore.answerInterview(messageId: message.id, gap: gap, answer: nil, language: lang) }
                } label: {
                    Text(lang == .vi ? "Bỏ qua" : "Skip")
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().stroke(CodepetTheme.hairline))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CodepetTheme.surface))
        .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 24)
    }
}
```

Once `interviewAnswered` flips true (T4), the branch falls through to `textBubble`, which shows `message.text` (= the question) as a plain companion bubble — matching the web's answered-collapse. Confirm `CodepetTheme.hairline`/`surface`/`accentPurple`/`mutedText`/`primaryText` and `.pixelSystem(size:weight:)` all exist as used; adapt any that differ (e.g. if there's no `hairline`, use the border token the file already uses).

- [ ] **Step 4:** Build → `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit** — `feat: render enrichment InterviewCard in Copilot chat` (+ trailer).

---

## Whole-flow verification (after Task 5)

- [ ] `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- [ ] `xcodebuild test ... -only-testing:codepetTests/CompanyBriefTests` and `-only-testing:codepetTests/EnrichInterviewTests` → pass.
- [ ] Manual (reviewer note, not automated): onboard with an empty brief → 3 skippable cards appear one at a time → after the 3rd, the first-run greeting fires; onboard with all three fields filled → greeting fires immediately, no cards.

## Self-Review

- **Coverage:** brief fields (T1) + pure gap/question logic (T2, fully tested) + message payload (T3) + store flow/trigger (T4) + card UI (T5). Trigger fires once inside `finishOnboarding`; no-gap path unchanged.
- **Build-independence:** T3 (model) precedes T4 (store, uses the field + defines `answerInterview`) precedes T5 (UI, uses field + method) — each compiles standalone.
- **Client-only / raw-save / one-at-a-time / backward-compat Codable / session-only state** all enforced in Global Constraints.
- **Adjudicated (controller):** no LLM distillation (raw text saved); no separate lead-in message before Q1 (end greeting already says "ready"); flat `interview`+`interviewAnswered` fields (mirrors `firstRunAction`/`actionConsumed`); no final re-normalize; answered-collapse via `message.text`.
