# Message card grammar + chat readability — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI), branch `feat/chat-redesign` (PR #39)
**Adapts:** Phase 2 chat spec §10 (card grammar), reshaped for `feat/chat-redesign` (whose `CopilotBubble` already draws the seven payloads as six bespoke builders). Plus a founder-requested chat text-size/readability pass, bundled into this phase.
**Status:** Design agreed with the founder (Q&A 2026-07-28); ready for spec review → plan.

## Goal

1. **One card grammar (§10):** the seven `CopilotMessage` interactive payloads currently render six different ways, so nothing tells the founder which ones need them. Collapse them onto one tinted-card construction with six semantic hues — **gold, and only gold, means "you owe a decision."**
2. **Readability:** the chat message body + card text render in `.pixelSystem(11–12)` — small and pixel-font. Move chat reading text to `CodepetTheme.inter` at a standard size (matching the composer's `inter(15)` and Claude/ChatGPT), keeping the pixel font for brand bits only.

## Decisions (locked with the founder)

- **Chat body text → `CodepetTheme.inter`, ~15pt.** Keep the pixel font only for brand (the sidebar wordmark) — not for chat message/card reading text.
- Semantic hue system per §10 (gold = decision owed).
- Card construction is **smooth** (RoundedRectangle continuous), not the older pixel "stepped border" — consistent with the redesign's existing cards (ChatEmptyState cards radius 14, composer radius 16). This is a deliberate deviation from §10's "stepped border" wording to match the shipped redesign aesthetic.

## Non-goals

- No change to any payload's BEHAVIOR (Approve/Redo/Revise, nav activate, setup enable, interview send/skip, first-run action, noted display all keep their current logic) — this restyles the wrapper + text, not the actions.
- No Cloud Function / `CompanyStore` / model / schema change. No new deps.
- `producing` is NOT a card — it already routes to `ChatThinkingRow` (§8, shipped). Not touched.
- Not touching §9 message un-bubble, §7 composer, §3 aura, §5/6 landing — separate phases.

## Design

### 1. `MessageCardStyle` — `codepet/Models/MessageCardStyle.swift` (new, pure)

SwiftUI-free (imports SwiftUI only for `Color`), testable:

```swift
enum MessageCardKind { case draft, interview, setupSuggestion, firstRunAction, noted, navChip }

enum MessageCardStyle {
    /// Which kind a message is, from its payload. nil for plain text and for `producing`.
    /// Precedence when a message somehow carries more than one payload:
    /// draft > interview > setupSuggestion > firstRunAction > noted > navChip.
    static func kind(for m: CopilotMessage) -> MessageCardKind?
    /// The single hue that carries the card's meaning.
    static func hue(for kind: MessageCardKind, companionAccent: Color) -> Color
}
```

Hue table:

| kind | hue | meaning |
|---|---|---|
| `draft` | `CodepetTheme.accentGold` | a decision is owed |
| `firstRunAction` | `companionAccent` | the companion is offering |
| `interview` | `CodepetTheme.accentBlue` | you are being asked |
| `setupSuggestion` | `CodepetTheme.accentTeal` | capability change |
| `noted` | `CodepetTheme.mutedText` | receipt; recedes |
| `navChip` | `CodepetTheme.hairline` | pure navigation |

`kind(for:)` returns nil when `m.producing` is true or when the message carries no payload (plain text). It checks payloads in the documented precedence order (a real message carries one; precedence only disambiguates the pathological case + pins test behavior).

### 2. `MessageCard` — `codepet/Views/Copilot/MessageCard.swift` (new)

One construction, hue-parameterized, wrapping arbitrary content:

```swift
struct MessageCard<Content: View>: View {
    let hue: Color
    @ViewBuilder var content: Content
    // hue.opacity(0.12) fill over CodepetTheme.surface, same-hue 1pt border,
    // RoundedRectangle(cornerRadius: 12, .continuous), uniform padding 12,
    // frame(maxWidth: .infinity, alignment: .leading)
}
```

Only the hue varies between the six kinds. Callers pass `MessageCardStyle.hue(for: kind, companionAccent:)`.

### 3. Refactor `CopilotBubble` payload builders — `codepet/Views/Copilot/CopilotChatView.swift`

Each of the six builders keeps its **inner content and actions unchanged**, but is wrapped in `MessageCard(hue:)` instead of its ad-hoc container (`CodepetCard`, bare `Capsule` chips, etc.). Resolve the companion accent once: `PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple`.

- `draftCard`: wrap in `MessageCard`. Hue = **gold while unapproved** (`!message.draftApproved`); once approved, recede to `CodepetTheme.accentTeal` (the existing "Added to Library" done-state colour). This keeps "gold = decision still owed" honest.
- `interviewCard` → blue; `setupCard` → teal; `notedChip` → muted; `navChip` → hairline; first-run action → companion accent.
- `navChip` / first-run / `noted` currently render as bare capsules/chips; they become small `MessageCard`s too, so the whole surface shares one grammar.
- The `body`'s payload dispatch keeps working; optionally route through `MessageCardStyle.kind(for:)` — but at minimum each builder passes the correct hue.

### 4. Readability pass — same file (and only reading text)

Move chat **reading** text from `.pixelSystem` to `CodepetTheme.inter`, on this scale (pixel font stays ONLY on the sidebar wordmark, untouched here):

| Element | before | after |
|---|---|---|
| message bubble body (me + companion) | `pixelSystem(12)` | `inter(15)` |
| card title (draft, interview ask) | `pixelSystem(12, semibold)` | `inter(15, weight: .semibold)` |
| setup name | `pixelSystem(12, semibold)` | `inter(14, weight: .semibold)` |
| secondary/detail (draft body, why lines, noted facts) | `pixelSystem(11)` | `inter(13)` |
| interview answer field | `pixelSystem(12)` | `inter(14)` |
| primary buttons (Approve/Redo, Send/Skip, verb, nav, first-run) | `pixelSystem(10–11, semibold)` | `inter(12–13, weight: .semibold)` |
| revise chips / smallest labels | `pixelSystem(9, semibold)` | `inter(11, weight: .semibold)` |

No copy changes; en/vi unaffected.

## Testing

- **`MessageCardStyleTests` (new, pure):** every `MessageCardKind` → its documented hue (pass a sentinel `companionAccent` and assert `firstRunAction` returns exactly it); `kind(for:)` returns the right kind for a message carrying each single payload; `nil` for a plain-text message and for a `producing` message; a message carrying two payloads resolves by the documented precedence (`draft` beats `interview`, etc.).
- **Build gate:** foreground `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED. Full suite stays at 0 real failures (known Firebase-init flake aside) + the new MessageCardStyle tests.
- **Visual, human-verified on a signed build (built + launched):** each payload reads as a tinted card with its hue (trigger a draft → gold; interview → blue; etc.); approved draft recedes to teal; text is clearly larger/cleaner (Inter 15) in both light + dark.

## Files

**New:** `codepet/Models/MessageCardStyle.swift`, `codepet/Views/Copilot/MessageCard.swift`, `codepetTests/MessageCardStyleTests.swift`
**Modified:** `codepet/Views/Copilot/CopilotChatView.swift` (`CopilotBubble` builders: wrap in `MessageCard` + font scale).

## Risks / watch-items

- **Behavior regressions:** `CopilotBubble` carries a lot of working action logic; the refactor must be mechanical (swap the container + fonts, keep the buttons/closures), verified by the suite staying green + a signed-build click-through of Approve/Redo/nav/setup/interview.
- **Hue legibility in light mode:** hue@12% over cream `surface` for the paler accents (gold, teal) — confirm the tint is visible but not garish in light; adjust opacity only if needed (cosmetic).
- **`CodepetCard` may become unused** once the builders stop calling it — if so, leave it (used elsewhere) or note it; don't delete shared infra without checking other callers.

## Rollout

Implement on `feat/chat-redesign` → build + suite green → build & launch signed for the founder's visual sign-off → push (rebasing over any concurrent branch commits). Nothing merges (branch held). Follow up on the W1 tracker's "Run-card design (Approve / Open / Redo)" task.
