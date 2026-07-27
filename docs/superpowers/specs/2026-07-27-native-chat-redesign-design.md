# Native chat redesign — design spec

**Date:** 2026-07-27
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI app) — `codepet/Views/Copilot/CopilotChatView.swift`
**Status:** Approved design; ready for implementation plan.

## Goal

Rework the chat surface (the product's "spine") from today's sparse, left-aligned
empty state + thin bottom input into a modern AI-chat layout: a **centered,
personalized hero greeting**, an **elevated composer** with functional controls,
**quick-action pills** mapped to Codepet's real capabilities, and a **restyled
active conversation** — all within the existing chat column (no new sidebar).

Reference direction: a *quiet hero* (minimalist, space-forward, per the Codepet
design north-star) plus an **Ask / Plan / Build** mode selector.

## Non-goals

- No new left chat sidebar (the app already has a department/nav rail + in-chat
  History panel; a second nav surface is out of scope).
- No backend / `CompanyStore` / Cloud Function changes. This is a **view refactor
  + restyle**. Chat send, streaming, thread switching, draft approve/redo,
  interview cards, nav/setup chips all keep their current logic.
- No new fake affordances. Every control maps to real behavior (see Honesty).

## Honesty constraints (why the design is shaped this way)

- There is **no backend concept of chat modes** and **no build session** — the
  current "Let's build" bar is a dead stub (`Button { }`). So modes are
  implemented as **client-side intent-shaping** of the outgoing message, not
  distinct backends.
- There is **no file-attachment feature**, so the composer has **no fake attach
  button**. The `+` control opens a real **quick-actions menu** instead.
- The "Let's build" stub bar is **removed**, not restyled — its intent moves into
  the Build mode.

## Component structure

Split `CopilotChatView` (612 lines) into focused subviews in the same file group:

| Unit | Responsibility | Depends on |
|---|---|---|
| `CopilotChatView` | Thin shell: `header → (empty ? ChatEmptyState : messageList) → ChatComposer` | `CompanyStore` |
| `ChatEmptyState` | Centered hero greeting + quick-action pills | `CompanyStore` (names), sends via composer callback |
| `ChatComposer` | The composer, reused in empty + active states: multiline field, `+` menu, mode control, send | binding to draft + mode; `send` / `runQuickAction` callbacks |
| `ChatMode` | Pure enum: `.ask / .plan / .build`; `shape(_ text:) -> String` | none (unit-testable) |
| `CopilotBubble` | Unchanged logic; spacing/radius restyle only | `CompanyStore` |
| `ThreadListView` | Unchanged | `CompanyStore` |

Each unit is independently understandable: `ChatComposer` knows nothing about the
message list; `ChatMode` is pure data; `ChatEmptyState` only renders + forwards taps.

## 1. Empty-state hero (`ChatEmptyState`)

- Centered `VStack`, vertically centered in the column.
- **Greeting**: Google Sans Flex (`CodepetTheme.inter`) ~34–40pt, semibold,
  `-0.02em` tracking, `primaryText`, with the **company name** in `accentPurple`.
  Personalized with `founderName` / `companyName` (same accessors as today).
  Localized (en/vi), matching the existing greeting's bilingual pattern.
  **Not** the Minecraft pixel font (matches web `.vhead h1`).
- **Glow**: one faint `accentPurple` radial behind the greeting. Must read well in
  **both** light and dark (fainter in light). Suppressed under
  `accessibilityReduceMotion` / reduce-transparency.
- **Quick-action pills** (row, wraps): capsule, `hairline` border, `bodyText`.
  Replaces today's three left-aligned text chips. Each pill sends a canned
  message through the same path as free text:
  - Run a task
  - Review the roadmap
  - Set up a department
  - Summarize where we are

  (Exact strings finalized in the plan; localized en/vi.)

## 2. Composer (`ChatComposer`)

- `surface` card, 16pt continuous radius, `floatingShadow`.
- Multiline `TextField(axis: .vertical)`, `lineLimit(1...6)`, plain style,
  `inter(15)`, placeholder "Ask anything about your company…" (localized).
- Bottom control row:
  - **`+`** — 30pt bordered square button → menu of the same quick actions as the
    pills. This is how quick-actions stay reachable in an active conversation
    (where the hero pills are gone). Real behavior; not a file picker.
  - **Mode control** — `Ask ▾` pill → `Menu` of Ask / Plan / Build. Selected mode
    persists for the session (client-only `@State`, no persistence needed for v1).
  - **Send** — `accentPurple` filled circle, `arrow.up`, disabled unless
    `canSend` (non-empty trimmed draft AND not typing/streaming — today's gate).
- Same component instance is used centered (empty) and docked at the column bottom
  (active). A `Divider()` sits above it in active mode, as today.

## 3. Modes (`ChatMode`)

Pure, testable message-shaping. No backend change.

- `.ask` *(default)* — returns text unchanged (today's behavior).
- `.plan` — wraps text with a planning intent so byte replies with concrete next
  steps / a short plan.
- `.build` — biases text toward *running a task / producing a deliverable*, which
  the chat already supports (`run_task` → draft cards). Copy kept **modest** so it
  doesn't imply the (not-yet-native) build agent.

`send()` becomes: `companyStore.sendChat(mode.shape(text), language: lang)`.
`shape` is pure → unit-tested for all three modes in both languages.

## 4. Active conversation

- `messageList` scroll behavior unchanged (auto-scroll on new message / typing).
- `CopilotBubble` logic untouched (text / draft / nav / setup / noted / interview /
  producing). Restyle only: bump bubble radius to ~14pt, increase inter-message
  spacing for a cleaner read, keep `me = accentPurple`, `companion = surface`.
- Typing/producing rows unchanged in logic.
- The separate "Let's build" bar is **deleted**.

## 5. Header

Content unchanged: "Your team" / "guiding · {company}" + History toggle
(the working thread switcher). Light spacing polish only.

## 6. Tokens, theme, accessibility

- All colors/spacing via `CodepetTheme` tokens → automatic light/dark via the
  dynamic `Color.dyn` tokens. Verify the hero + glow in **both** appearances.
- Respect reduce-motion / reduce-transparency for the glow.
- Preserve keyboard behavior: `onSubmit` sends (Return), Shift+Return newline via
  the multiline axis. Focus state preserved.

## 7. Testing

Follow existing `codepetTests` patterns:
- **Unit**: `ChatMode.shape` for `.ask/.plan/.build` × en/vi; `canSend` gating.
- **Behavior preserved**: sending (free text + pill + `+` menu), thread switch,
  draft approve/redo, interview send/skip all still work (refactor must stay
  green). No snapshot infra assumed; assert on view-model/pure logic.

## Risks / watch-items

- **Light mode**: mockups were dark-only; the hero glow and composer contrast must
  be checked in light (cream) appearance before merge.
- **Refactor regressions**: `CopilotChatView` carries a lot of working behavior;
  the split must be mechanical (move, don't rewrite) to avoid breaking drafts /
  streaming / History.
- **Build-mode expectations**: keep copy modest; revisit when the native build
  agent lands.
- **Verify on a signed/real build**, not just `next dev`-style previews — this is
  the native app (per project conventions).

## Rollout

Branch off `My-Outcasts/codepet@main` → implement → verify in both appearances on a
signed build → PR to `main`.
