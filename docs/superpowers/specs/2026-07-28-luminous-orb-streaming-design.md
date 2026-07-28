# Luminous companion orb + streaming affordance — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI), branch `feat/chat-redesign` (PR #39)
**Adapts:** Phase 2 chat spec (`docs/chat-surface-phase2-spec`) §1 (second hue), §2 (orb), §4 (tokens), §8 (streaming). That spec targets a parallel branch (`CopilotChatView` + a new `CompanionOrbView`); this one reshapes the same design for `feat/chat-redesign`, which already has a `CompanionOrb` and orb-avatar bubbles.
**Status:** Design agreed with the founder (Q&A 2026-07-28); ready for spec review → plan.

## Goal

Make the companion orb the chat's real identity — a luminous, companion-tinted sphere instead of today's flat angular-gradient circle — and turn the streaming state from static text ("Thinking…") into an expressive, honest affordance: a breathing orb + a label that names the work when there is work to name.

## Decisions (locked with the founder)

- **Scope:** the luminous orb (§2) **and** the streaming state (§8) together, which pulls in the per-companion second hue (§1) and the two theme tokens (§4) the orb needs. Aura field (§3), message un-bubble (§9), and card grammar (§10) are **out of scope** here.
- **Idle-reply copy:** when there is no task to name, the label reads **"Working on it…"** (vi: "Đang xử lý…").
- **Named work:** when a task title is available, the label reads **"Drafting {title}…"** (vi: "Đang soạn {title}…").
- **Shimmer:** keep §8's subtle ~2.1s light-sweep through the label; disabled under Reduce Motion.

## Deviations from the Phase 2 spec (deliberate, to fit this branch)

- **Reimplement the existing `CompanionOrb` in place** rather than adding a new `CompanionOrbView`. Keep its current API (`size: CGFloat`, `glow: Bool`) so the 4 existing call sites (hero 78; avatars/typing/producing 28) don't churn; **add** `isWorking: Bool = false`. (Spec's `Size` enum {hero/inline/avatar} is not adopted — raw `size` already works here.)
- Companion hues are read from the environment store (per spec intent) so switching companion re-tints every orb with no call-site change.

## Non-goals

- No aura field (§3), no message un-bubble (§9), no card grammar (§10).
- No Cloud Function / `RoadmapEngine` / Firestore changes. No new dependencies. No literal hex in views except inside `CompanionOrb`/tokens (the orb's internal core stops, which are its own art).

## Design

### 1. Companion second hue — `codepet/Models/Character.swift`

`PetCharacter` has `hexColor` + `color`. Add `let secondHexColor: String` and `var secondColor: Color { Color(hex: secondHexColor) }`, and a `secondHexColor:` argument to all seven entries in `static let all` (hand-picked, not hue-rotated):

| id | `hexColor` (existing) | `secondHexColor` (new) |
|---|---|---|
| byte | `#8B7BE8` | `#4EC9D4` |
| nova | `#FF8C00` | `#6EA8FF` |
| crash | `#E04040` | `#F0A860` |
| luna | `#5B8DEF` | `#C99BF0` |
| sage | `#20B090` | `#FDC352` |
| glitch | `#E0508C` | `#5AD0E0` |
| null | `#80C830` | `#5AD0E0` |

`hexColor` is read from the static catalog at runtime and never persisted/decoded, so adding a field needs no migration.

### 2. Theme tokens — `codepet/Views/CodepetTheme.swift`

Add alongside the existing `Color.dyn` tokens:

```swift
static let chatCanvas  = Color.dyn("#f8f7f3", "#16130f")   // matches pageBackground
static let chatOrbCore = Color.dyn("#0E0A16", "#040208")   // the orb's luminous core
```

`chatCanvas` is added for parity with the Phase 2 token set; the orb consumes `chatOrbCore`. (`chatCanvas` is not otherwise wired in this scope — it lands so §3/§9 can use it later without a second edit. If the plan's self-review flags it as unused-in-scope, keep it — it's a documented forward token.)

### 3. Luminous orb — reimplement `codepet/Views/Copilot/CompanionOrb.swift`

Replace the flat angular-gradient body with a luminous sphere that reads as **emitted light**, companion-tinted. Keep the type name and API; add `isWorking`:

```swift
struct CompanionOrb: View {
    var size: CGFloat = 78
    var glow: Bool = true            // outer bloom (kept for the 4 existing call sites)
    var isWorking: Bool = false      // NEW — drives the breathe
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // hue1 = active companion .color, hue2 = .secondColor (fallback accentPurple/accentPink)
}
```

Hues: resolve `PetCharacter.all[companyStore.company.companionId]` → `.color` / `.secondColor`; fall back to `accentPurple` / `accentPink` if absent.

Composition (all clipped to the circle so the edge stays crisp), in order:
1. near-black core radial (`chatOrbCore` light→dark) so colour reads as luminous
2. three internal colour bands — `hue1`, `hue2`, and `hue1` lifted ~45% toward white — drifting on **different periods** (×0.83, ×1.17, ×0.61) so the flow never visibly loops
3. a specular crescent near −34%/−40% of the radius, drifting slightly
4. inner base shading for sphericality
5. a rim, brightest where the specular sits
6. a soft outer bloom (gated on `glow` and not Reduce Transparency)

Steps 2–3 composite additively (`GraphicsContext.BlendMode.plusLighter` inside a `drawLayer`).

**Rendering:** `TimelineView(.animation)` driving a `Canvas`. **Motion rule:** the orb drifts internally at rest; **only `isWorking` changes scale** — a 3.6s breathe between 1.0 and 1.07. Scale means "working," nothing else.

**Reduce Motion:** render one static frame — no `TimelineView`, no breathe, no drift. Composition still reads as a sphere.

**Performance is the schedule risk.** If the internal flow can't hold ~60fps at the hero size, the fallback is a Metal shader via `.layerEffect`; the plan budgets for that rather than discovering it late. Verified only on a real signed build (no agent here can see the screen).

**Call sites unchanged** except the thinking row (below) passes `isWorking: true`. The two `#Preview`s (this file + `ChatEmptyState`) must inject `.environmentObject(CompanyStore())` since the orb now reads the store.

### 4. Streaming label logic — `codepet/Models/ChatThinkingLabel.swift` (new, pure)

SwiftUI-free and unit-tested, following `RoadmapEngine`/`TopbarCounts`:

```swift
enum ChatThinkingLabel {
    /// title != nil → "Drafting {title}…"; nil → "Working on it…". Localized en/vi.
    static func text(taskTitle: String?, language: AppLanguage) -> String
}
```

- `taskTitle == nil` → en "Working on it…" / vi "Đang xử lý…"
- `taskTitle == "X"` → en "Drafting X…" / vi "Đang soạn X…"

Honesty: a title is passed only when a real one exists (a producing deliverable / in-flight run); a plain chat turn passes `nil`. Never invent a task name.

### 5. Streaming row — `codepet/Views/Copilot/ChatThinkingRow.swift` (new)

Replaces both `CopilotChatView.typingRow` and `CopilotBubble.producingRow` with one view:

```swift
struct ChatThinkingRow: View {
    let taskTitle: String?     // nil for a plain chat turn
    // orb + shimmering label, left-aligned, Spacer trailing (matches today's rows)
}
```

- **Orb:** `CompanionOrb(size: 28, glow: false, isWorking: true)` — breathing.
- **Label:** `ChatThinkingLabel.text(taskTitle:language:)`, `inter(13)`, `mutedText`.
- **Shimmer:** a brighter gradient masked over the label text, animated left→right on a **2.1s** linear `TimelineView`. Under `accessibilityReduceMotion`, render the label plain (no sweep) and the orb static.

**Wiring in `CopilotChatView`:**
- `typingRow` (chat turn, `isCompanionTyping`) → `ChatThinkingRow(taskTitle: nil)` → "Working on it…".
- `producingRow` (`CopilotBubble`, `message.producing`) → `ChatThinkingRow(taskTitle: <deliverable/task title if the producing message carries one, else nil>)`. The plan resolves the exact source; if none is readily on the message, pass `nil` (→ "Working on it…") — do **not** fabricate a title.

## Testing

- **`ChatThinkingLabelTests` (new, pure):** `taskTitle: nil` → "Working on it…" (en) / "Đang xử lý…" (vi); `taskTitle: "positioning brief"` → "Drafting positioning brief…" (en) / "Đang soạn positioning brief…" (vi).
- **Build gate:** foreground `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED. Full suite stays at 303 real passes (the `CompanyStoreScaffordOnboardingTests` Firebase-init flake is the known non-regression).
- **Visual, human-verified on a signed build (built + launched for the founder):** orb reads as luminous & companion-tinted (byte = violet→teal); breathe only when working; shimmer subtle; Reduce Motion → static orb + plain label; hero (78) performs at 60fps.

## Files

**New:** `codepet/Models/ChatThinkingLabel.swift`, `codepet/Views/Copilot/ChatThinkingRow.swift`, `codepetTests/ChatThinkingLabelTests.swift`
**Modified:** `codepet/Models/Character.swift` (§1), `codepet/Views/CodepetTheme.swift` (§2), `codepet/Views/Copilot/CompanionOrb.swift` (§3 — reimplemented), `codepet/Views/Copilot/CopilotChatView.swift` (§5 wiring + delete `typingRow`/`producingRow`), and the `ChatEmptyState` preview (inject store).

## Risks / watch-items

- **Orb performance** at hero size (Canvas/`plusLighter`/TimelineView) — the schedule risk; Metal `.layerEffect` fallback budgeted. Verify on the signed build.
- **Env coupling:** `CompanionOrb` now needs `CompanyStore` in the environment. All 4 runtime call sites already have it; only previews need the injection.
- **Reduce Motion** must fully static the orb (no TimelineView) — verify the flag path, not just the animated one.

## Rollout

Implement on `feat/chat-redesign` → build + suite green → build & launch signed for the founder's visual sign-off → push. Nothing merges (branch held). Follow up on the W1 tracker's "Streaming/typing affordance" task.
