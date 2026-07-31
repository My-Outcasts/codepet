# Chat-Section Design Upgrade (PR #42 docked copilot)

**Date:** 2026-07-31
**Status:** Approved design → ready for implementation plan
**Branch:** `feat/shell-web-parity` (PR #42; already carries the web-parity shell + the coding agent)
**Target:** upgrade the *visual design* of the docked copilot's chat, borrowing the applicable polish from PR #39 (`feat/chat-redesign`) — teammate reply cards, avatars, cleaner readable text, nicer empty-state + thinking indicator — adapted to the 380pt dock. **Visual only; no new behavior.**

---

## 1. Goal

Make the docked "Your team" chat read like PR #39's polished chat instead of `main`'s plain bubbles: companion/department replies render as **teammate cards** (avatar + name·dept header + reply in a rounded surface), text is **cleaner and more legible** (Inter, not the small pixel font), and the empty state + typing indicator match #39 — all sized for the 380pt dock, with the coding-agent card and the shell untouched.

## 2. Non-goals (explicitly out)

- #39's **full-width 760pt chat-home layout** — this is a 380pt dock.
- The **agents-working fan-out row** (needs `CompanyStore.fanOutNextMoves` — a feature).
- **Composer department chips** (a routing feature; the composer keeps its existing Engineering toggle + Let's build).
- `ChatExecLog` / any run-transparency beyond the existing coding-agent `CodeRunCardView`.
- Any change to chat *behavior*, the send path, threads, or the coding agent's logic. Purely how messages/greeting/typing look.

## 3. Current vs target

| | This branch now (`main`'s CopilotChatView) | Target (PR #39 polish, dock-sized) |
|---|---|---|
| Companion reply | plain left `textBubble`, `.pixelSystem(12)` | **teammate card**: `CompanionOrb` avatar + **name · dept** header + reply in a `MessageCard` rounded surface |
| User message | right bubble, `.pixelSystem(12)` | right-aligned bubble, restyled to match, Inter |
| Body text | `.pixelSystem(12)` | **~13.5pt Inter + `lineSpacing(3–4)`** (dock-appropriate; not #39's 18pt) |
| Empty state | inline greeting + capsule chips | `ChatEmptyState`-style greeting + starter chips, dock-sized |
| Typing | plain "…is typing…" text | `ChatThinkingRow`-style indicator |

## 4. Approach

**Port the two self-contained chrome components from #39, then surgically upgrade *this branch's* `CopilotChatView` message rendering / empty-state / typing row** — do NOT wholesale-replace `CopilotChatView` with #39's (that would lose this branch's coding-agent integration, Engineering toggle, thread header, and dock adaptations). #39's chat visuals are the *reference*; the components are the *reuse*.

- **Port verbatim (self-contained):** `MessageCard.swift`, `CompanionOrb.swift` from `feat/chat-redesign` via `git show`. Verify their only deps are `CodepetTheme` + the companion model (both present); if a ported component references a #39-only symbol, adapt that one reference.
- **Re-author in place (not verbatim port):** the teammate-card render, the empty state, and the thinking row are rewritten inside this branch's `CopilotChatView` using the ported components + #39's visual spec — because this branch's `CopilotChatView` already has structure (`CopilotBubble` if/else dispatch, thread header, composer with Engineering toggle, the coding-agent card sites) that must be preserved. Porting #39's whole `ChatEmptyState`/`ChatThinkingRow` files verbatim is avoided if their initializers pull #39-only types (e.g. `ChatLandingState`); reproduce the *look*, keep this branch's data.

*(Rejected: replacing `CopilotChatView` wholesale with #39's — loses the coding agent + Engineering toggle + dock fit.)*

## 5. Components & changes

### 5.1 Ported components (`codepet/Views/Copilot/`)
- **`MessageCard.swift`** — tinted rounded-surface card chrome (`MessageCard(hue:) { content }`). Used for teammate reply cards. Dock note: it's `.frame(maxWidth:.infinity)` left-aligned, so it fills the 380pt dock naturally.
- **`CompanionOrb.swift`** — the companion avatar (`CompanionAvatar(size:)` / orb). Used at ~20–22pt in the reply header. Confirm it reads the active companion's color from `CompanyStore` (as `main`'s theming already does).

### 5.2 `CopilotChatView` — `CopilotBubble` rendering (`codepet/Views/Copilot/CopilotChatView.swift`)
The existing `CopilotBubble.body` if/else dispatch (producing / draft / navChip / setupCard / noted / firstRunAction / interview / else→textBubble) is preserved; only the **`else` (plain companion/user text)** branch is upgraded:
- **Companion (`!isMe`) reply →** a teammate card: `HStack { CompanionOrb(size: 22); VStack { header("name · dept" in the persona color) ; MessageCard { Text(reply).font(inter(13.5)).lineSpacing(3) } } }`, left-aligned, `Spacer(minLength: 24)` trailing (mirrors #39's `textBubble` teammate branch, dock-sized fonts).
- **User (`isMe`) →** keep right-aligned bubble; restyle to Inter 13.5 on the accent fill (matches #39's user bubble, smaller).
- The other card kinds (draft/setup via `CodepetCard`, interview, noted, navChip) keep their current rendering — out of scope, and they already read fine.

### 5.3 Empty state + typing row
- **`greeting`** (currently inline in `CopilotChatView`) → reproduce #39's `ChatEmptyState` look: companion orb + welcome line + starter-chip buttons, dock-width. Keep this branch's existing `quickStarts` strings + `sendChat` wiring.
- **`typingRow`** → reproduce `ChatThinkingRow`'s look (orb + animated "thinking" beat) instead of the plain pixel-font line. Keep the existing `isCompanionTyping` gate.

### 5.4 Coding-agent card (optional consistency)
`CodeRunCardView` currently uses `CodepetCard` + no avatar (from the coding-agent port). Optionally re-skin its header to use `CompanionOrb` so the run card and the teammate cards share the same avatar chrome. Low priority; only if it reads inconsistently.

## 6. Keep intact
Docked layout + collapse (`AppShellView`), the thread/History header, the composer (TextField + Engineering toggle + Let's build + send), the coding-agent triggers + `CodeRunCardView`, threads, the send/stream path, `CompanyStore`. Bilingual EN/VI on all new/changed copy.

## 7. Dock-sizing rules
- Body text 13.5pt (not 18); headers ~13pt semibold; avatar ~22pt; card padding ~10–12pt (not #39's wider values). The teammate card + `MessageCard` are width-agnostic and reflow into 380pt; verify nothing hard-codes a wide column.

## 8. Testing
- **Build** TEAM-signed (`BUILD SUCCEEDED`); full suite stays green (this is view-layer; existing tests must not regress).
- **Founder visual pass (manual):** companion replies render as teammate cards with avatar + name·dept; text is legible at dock width (not cramped, not oversized); empty state + typing indicator match #39's feel; the coding-agent run card still renders correctly in the dock; user bubbles right-aligned.
- Any pure helper extracted gets a unit test; most of this is view code verified visually.

## 9. File change summary
- **New (ported):** `codepet/Views/Copilot/MessageCard.swift`, `codepet/Views/Copilot/CompanionOrb.swift` (via `git show feat/chat-redesign:…`, adapt only #39-only refs).
- **Modify:** `codepet/Views/Copilot/CopilotChatView.swift` (teammate-card `else` branch, `greeting`, `typingRow`, body fonts); optionally `codepet/Views/Copilot/CodeRunCardView.swift` (avatar consistency).

## 10. Deferred / future
- The fan-out agents row + `CompanyStore.fanOutNextMoves`, composer dept chips, exec-log — deliberately excluded (features, not design).
- Reconcile note: this branch is PR #42; if PR #39 or the coding-agent branch ever merge, the shared `CopilotChatView` reconciles here.
