# First-run / empty chat state — live landing — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI), branch `feat/chat-redesign` (PR #39)
**Adapts:** Phase 2 chat spec §5 (ChatLandingState) + §6 (landing view), reshaped for `feat/chat-redesign`.
**Status:** Design agreed with the founder (Q&A 2026-07-28); ready for spec review → plan.

## Goal

Turn the empty chat state from four static "send a canned message" capability cards into a **live landing**: a pure `ChatLandingState` drives the greeting + up to **three live roadmap cards** (the beacon, needs-you count, awaiting-approval count). When there's no roadmap yet, it falls back to **three prompt-starters that fill the composer**.

## Decisions (locked with the founder)

- **Live cards replace the static capability cards.** Up to 3, each omitted when its count is zero / beacon is nil: **DO THIS NEXT {beacon title}**, **NEEDS YOU {n}**, **AWAITING APPROVAL {n}**. Tapping any opens the Roadmap page (`companyStore.select(.roadmap)`).
- **Empty fallback = 3 prompt-starters** ("Draft my positioning", "Plan this week", "Review my brief") that **insert their text into the composer** (populate the draft; the founder edits/sends) — they do NOT fire immediately.
- The composer's own `+` quick-actions menu (Run a task / etc.) is **unchanged** — only the empty-state CARDS change.

## Non-goals

- No Cloud Function / schema / dependency change. No change to the orb, composer internals, cards grammar, message rendering, or column width.
- No new roadmap generation trigger here (roadmap population is owned elsewhere).

## Design

### 1. `ChatLandingState` — `codepet/Models/ChatLandingState.swift` (new, pure)

SwiftUI-free, deterministic given `now`; follows `RoadmapEngine`/`ChatContext` conventions.

```swift
struct ChatLandingState {
    let greeting: String            // "Good evening, Mona." (time-of-day + founder; "there"/"bạn" if blank)
    let question: String            // "What should we build for {company} today?"
    let beacon: RoadmapTask?        // RoadmapEngine.nextStep(company.tasks)
    let needsYouCount: Int          // status == .needsYou, EXCLUDING the beacon
    let awaitingApprovalCount: Int  // status == .needsApproval
    let isEmpty: Bool               // company.tasks.isEmpty → show prompt starters

    init(company: CompanyState, now: Date, language: AppLanguage)
}
```

- **Greeting** (moved out of `CopilotChatView.greetingLine1/2`, copy unchanged): hour from `Calendar.current.component(.hour, from: now)` — `<12` morning / `<18` afternoon / else evening (localized en/vi); founder = `company.brief.founderName` trimmed, else "there"/"bạn". `greeting = "\(part), \(founder)."`
- **Question**: company = `company.brief.projectName` trimmed, else "Codepet"; `question = "What should we build for \(company) today?"` (vi: "Hôm nay mình xây gì cho \(company)?").
- **beacon** = `RoadmapEngine.nextStep(company.tasks)`.
- **needsYouCount** = `company.tasks.filter { RoadmapEngine.status(for: $0, in: company.tasks) == .needsYou && $0.id != beacon?.id }.count`.
- **awaitingApprovalCount** = `company.tasks.filter { RoadmapEngine.status(for: $0, in: company.tasks) == .needsApproval }.count`.
- **isEmpty** = `company.tasks.isEmpty`.

### 2. `ChatEmptyState` rework — `codepet/Views/Copilot/ChatEmptyState.swift`

Replace the inputs `line1/line2/quickActions/onQuickAction` with:
```swift
    let state: ChatLandingState
    let onOpenRoadmap: () -> Void
    let onStarter: (String) -> Void
    @ViewBuilder var composer: Composer
```
- **Greeting block** unchanged visually: `state.greeting` on line 1 (primary text), `state.question` on line 2 (purple→pink gradient). (Same fonts/layout as today.)
- **Card row** (replaces the 2-column `QuickAction` grid):
  - **`state.isEmpty == true`** → three **starter cards**, each a tappable tinted card showing the starter label; tap → `onStarter(<localized text>)`. Localized starters: en `["Draft my positioning", "Plan this week", "Review my brief"]`, vi `["Soạn định vị của tôi", "Lên kế hoạch tuần này", "Xem lại bản tóm tắt"]`.
  - **else** → up to three **live cards**, built in this order, each omitted when empty:
    | Card | Shown when | Eyebrow (en/vi) | Value | Hue | Tap |
    |---|---|---|---|---|---|
    | Beacon | `state.beacon != nil` | DO THIS NEXT / TIẾP THEO | `beacon.title` | companion accent | `onOpenRoadmap()` |
    | Needs you | `state.needsYouCount > 0` | NEEDS YOU / CẦN BẠN | `"\(count)"` | `accentBlue` | `onOpenRoadmap()` |
    | Awaiting approval | `state.awaitingApprovalCount > 0` | AWAITING APPROVAL / CHỜ DUYỆT | `"\(count)"` | `accentGold` | `onOpenRoadmap()` |
  - Card visual reuses today's tinted-card style (surface fill + hairline + a leading same-hue accent bar), with an uppercase eyebrow label above the value; keep the existing `maxWidth: 600` grid cap and 2-column layout (beacon can span or sit first — a simple 2-col `LazyVGrid` as today is fine).
- The `card(_:)`/`cards` for `QuickAction` are replaced by the above; the `QuickAction` type stays (still used by the composer's `+` menu).

### 3. Wiring — `codepet/Views/Copilot/CopilotChatView.swift`

- Build the state each render: `ChatLandingState(company: companyStore.company, now: Date(), language: lang)` and pass it to `ChatEmptyState`.
- `onOpenRoadmap = { companyStore.selectedDeptKey = nil; companyStore.select(.roadmap) }`.
- `onStarter = { draft = $0; inputFocused = true }` (populate the composer draft + focus; does NOT send).
- Remove `greetingLine1`/`greetingLine2` (now in `ChatLandingState`); remove `founderName`/`companyName` if they become unused (build confirms). The composer's `quickActions`/`runQuickAction` STAY (feed the `+` menu).

## Testing

- **`ChatLandingStateTests` (new, pure):**
  - Greeting hour boundaries via injected `now` built in `Calendar.current`: hour 11 → "Good morning", 12 → "Good afternoon", 17 → "Good afternoon", 18 → "Good evening".
  - Founder name present → included; blank → "there" (en) / "bạn" (vi).
  - `question` includes the project name; blank project → "Codepet".
  - From a fixture `[RoadmapTask]`: `beacon` == `RoadmapEngine.nextStep`; `needsYouCount` excludes the beacon; `awaitingApprovalCount` counts `.needsApproval`; `isEmpty` true iff tasks empty.
- **Build gate:** foreground build → BUILD SUCCEEDED; full suite 0 real failures + new tests.
- **Signed-build visual pass:** with a roadmap → DO THIS NEXT shows the beacon title, plus NEEDS YOU / AWAITING APPROVAL counts when >0; tapping opens the Roadmap page. With no roadmap → three starter cards that populate the composer on tap (not send). Greeting reads correctly; light + dark.

## Files

**New:** `codepet/Models/ChatLandingState.swift`, `codepetTests/ChatLandingStateTests.swift`
**Modified:** `codepet/Views/Copilot/ChatEmptyState.swift` (inputs + card row + preview), `codepet/Views/Copilot/CopilotChatView.swift` (build+pass state, handlers, remove greeting computeds).

## Risks / watch-items

- **`ChatEmptyState` preview** must construct a `ChatLandingState` fixture (needs a `CompanyState` — use `.empty` or a small fixture) + the new handlers.
- **Greeting parity:** the copy must match today's exactly (moved, not rewritten) so the empty state doesn't visibly change wording.
- **Card legibility over the backdrop:** reuse the opaque-surface tinted card (same fix as the card grammar) so live cards read in light mode.
- **`select(.roadmap)`** is the real nav; confirm `.roadmap` is the correct `AppView` case (it is — used by the sidebar/workspace).

## Rollout

Implement on `feat/chat-redesign` → build + suite green → build & launch signed for the founder's visual sign-off → push (rebasing over concurrent commits). Nothing merges (branch held). Follow up on the W1 tracker's "First-run / empty chat state" task.
