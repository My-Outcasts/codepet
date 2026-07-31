# Chat containment + cohesion — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI app), branch `feat/chat-redesign` (PR #39)
**Files:** `codepet/Views/Copilot/CopilotChatView.swift`, `codepet/Views/Copilot/ChatEmptyState.swift`, + one new `codepet/Views/Copilot/ChatBackdrop.swift`
**Status:** Approved design; ready for implementation plan.

## Goal

The chat became the app's full-width home page (commit `ea9f701`). The empty
state is contained (a 720pt centered column with a soft purple glow), but the
**active-conversation composer is not** — it renders as `composerView.padding(10)`
with no width cap, so it sprawls edge-to-edge in the full-width page. The active
conversation also has no ambient glow, so moving from the empty hero into a live
thread feels like crossing between two unrelated surfaces.

Reference direction (user-supplied: Axora/DeepAI, Cronius): everything lives in a
tight, clearly-contained centered column over a single ambient-washed background.
Per the Codepet north-star, this is a **containment + cohesion pass — not a
structural rewrite**. The composer internals, message bubbles, orb, greeting,
cards, and all chat logic are unchanged.

## Non-goals

- No change to the composer's internals (`+` quick-actions menu, `Ask ▾` mode
  control, gradient send button) — the user chose "keep the current structure".
- No change to message bubbles, the companion orb, the greeting, the quick-action
  cards, or any `CompanyStore` / send / streaming / thread logic.
- No new visible in-composer capability pills (explicitly deferred; not this pass).
- No column-width change: the column stays **720pt** everywhere (empty + active),
  matching the existing empty-state and message-list caps.

## Decisions (locked with the user)

- **Column width:** ~720pt, unchanged. The active composer is brought into the
  same 720 column so its edges align with the message list.
- **Active-chat glow:** yes — the active conversation gets the same soft ambient
  purple glow the empty state has, so empty→active reads as one continuous surface.
- **Divider:** the hard full-width `Divider()` above the active composer is
  **dropped**. It reads wrong beneath a 720-capped column and the references have
  none; the composer's existing `floatingShadow` provides separation as it floats
  over the ambient backdrop.

## Component structure

| Unit | Responsibility | Depends on |
|---|---|---|
| `ChatBackdrop` *(new)* | The ambient purple radial wash, gated on `accessibilityReduceTransparency`. Pure decoration, no state. Placed once behind the whole chat. | `CodepetTheme` |
| `CopilotChatView` | Owns the shared `ChatBackdrop` background behind both branches; contains the docked composer in a 720 column; no divider. | `CompanyStore` |
| `ChatEmptyState` | Drops its private `brandWash`; renders only foreground content (orb + greeting + composer + cards). The glow now comes from `CopilotChatView`'s `ChatBackdrop`. | `CompanyStore` |

`ChatBackdrop` is independently understandable: it takes no inputs beyond the
environment's reduce-transparency flag and draws one gradient. It can be dropped
behind any view. Extracting it removes the duplicated radial-gradient code that
would otherwise exist in both the empty state and the active branch.

## Changes in detail

### 1. `ChatBackdrop` (new file)

Move the exact gradient currently inlined as `ChatEmptyState.brandWash` into a
standalone `struct ChatBackdrop: View`:

- `RadialGradient` of `CodepetTheme.accentPurple.opacity(0.16) → .clear`,
  `center: .center`, `startRadius: 0`, `endRadius: 420`, `.blur(radius: 60)`,
  `.allowsHitTesting(false)`, filling `maxWidth/maxHeight: .infinity`.
- Suppressed entirely under `@Environment(\.accessibilityReduceTransparency)`
  (returns an empty view / clear), matching today's behavior.

This is a straight extraction — the empty-state glow must look identical to today.

### 2. `ChatEmptyState`

- Remove the private `brandWash` computed view and the `ZStack { brandWash; … }`
  wrapper. The body becomes just the foreground `VStack` (orb, greeting, composer,
  cards) filling `maxWidth/maxHeight: .infinity`.
- Remove the now-unused `@Environment(\.accessibilityReduceTransparency)` if it is
  no longer referenced elsewhere in the file (it moves into `ChatBackdrop`).
- No layout/spacing change to the foreground content — the composer stays capped
  at 720 and the cards at 720.

### 3. `CopilotChatView`

- Wrap the whole `body` content in `ZStack { ChatBackdrop(); VStack(spacing: 0) { … } }`
  so the ambient wash sits behind **both** the empty and active branches (fixed,
  not scrolling with the message list).
- **Empty branch:** unchanged (`ChatEmptyState(…) { composerView }`) — it now
  reads its glow from the shared backdrop.
- **Active branch:** replace

  ```
  messageList
  Divider()
  composerView.padding(10)
  ```

  with

  ```
  messageList
  HStack { Spacer(minLength: 0)
           composerView.frame(maxWidth: 720)
           Spacer(minLength: 0) }
    .padding(.vertical, 10)
  ```

  i.e. drop the `Divider()`, and center the composer using the **exact same**
  `Spacer / maxWidth: 720 / Spacer` pattern the `messageList` already uses (no
  extra horizontal padding), so the composer's column edges track the message
  bubbles' column edges at every window width. The composer keeps its own
  `floatingShadow`, which now provides the message/composer separation the divider
  used to.

## Data flow / behavior

No behavioral change. Draft/mode/focus still live in `CopilotChatView`; the same
`composerView` instance is used in both branches (so the first-send refocus fix in
`send()` still applies). Send, streaming, thread switching, draft approve/redo,
interview, nav/setup chips all keep their current logic. The backdrop is inert
decoration and `.allowsHitTesting(false)`, so it never intercepts taps.

## Error handling

None applicable — this is layout + decoration. The reduce-transparency path is the
only branch, and it degrades to no glow (already the established pattern).

## Testing

- **Build gate:** `xcodebuild build -project codepet.xcodeproj -scheme codepet
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED.
- **Suite:** full unit suite stays at **303 tests / 0 real failures** (the overall
  `** TEST FAILED **` is the known `CompanyStoreScaffordOnboardingTests`
  Firebase-init flake, fixed on PR #40 — not a regression).
- **No new pure logic** to unit-test — the change is layout/decoration. There is no
  snapshot infra in the project; the payoff is verified by the GUI pass below.
- **GUI pass (light + dark, real window):**
  - Active conversation: composer sits in the centered 720 column, edges aligned
    with message bubbles; no edge-to-edge sprawl; no divider; `floatingShadow`
    reads as separation.
  - The ambient purple glow is present and consistent across empty and active
    (fixed, not scrolling); fainter/acceptable in light (cream) appearance.
  - Reduce Transparency ON → glow suppressed in both states.
  - Empty state looks identical to before the `brandWash`→`ChatBackdrop` extraction.

## Risks / watch-items

- **Light mode:** the glow opacity (0.16) was tuned in dark; confirm it isn't muddy
  over the cream `pageBackground` in the active conversation (larger visible area
  than the empty hero). Adjust opacity only if it reads poorly — cosmetic.
- **Backdrop scroll independence:** the `ChatBackdrop` must live outside the
  `ScrollView` (as a `ZStack` background of the view), so it stays fixed while
  messages scroll. Putting it inside `messageList` would be wrong.
- **Column-edge alignment:** the composer uses the identical `Spacer / maxWidth:
  720 / Spacer` centering as `messageList`, so the 720 columns coincide. Their
  internal paddings differ slightly (`messageList` VStack pads 12, composer pads
  14) → a ~2pt inset difference; acceptable, but verify bubbles and composer read
  as aligned in the GUI pass.

## Rollout

Implement on `feat/chat-redesign` (PR #39) → build + suite green → push. Nothing is
merged (the branch is held for the user's GUI sign-off, consistent with the rest of
the redesign).
