# Composer — department chips + state expression + companion-tinted send — design spec

**Date:** 2026-07-28
**Target:** `My-Outcasts/codepet` (native macOS SwiftUI), branch `feat/chat-redesign` (PR #39)
**Adapts:** Phase 2 chat spec §7, reshaped for `feat/chat-redesign`.
**Status:** Design agreed with the founder (Q&A 2026-07-28); ready for spec review → plan.

## Goal

Make the composer express what it can do and what state it's in: **department chips** that genuinely refocus the answer, a **companion-tinted send**, and visible **idle / focused / busy** states — without adding any fake affordance.

## Decisions (locked with the founder)

- **Department chips are REAL via grounding scope:** selecting a department focuses the grounding `context` sent to the companyChat CF on that department (client-side; no CF change). No selection = today's behaviour exactly (additive).
- **Keep the existing `+` quick-actions menu as-is** — no fake "attach" button (the app has no file attachments; the redesign already chose quick-actions here).
- **State expression** (idle/focused/busy) and **companion-tinted send** are included (safe, real).

## Deviations from §7 (deliberate)

- **`+` stays a quick-actions menu**, not §7's attach (brief/deliverable/file) — file attach would be fake here.
- **The `Ask / Plan / Build` mode menu stays** (a real client-side feature the redesign shipped); §7 omitted it.
- **Dept chips scope grounding, they don't "route" the turn to a department backend** — there is no per-department chat CF; grounding-scope is the honest, CF-free way to make the chip real.

## Non-goals

- No Cloud Function / schema / new-dependency change. No file attachments. No change to the orb/cards/message rendering/backdrop/column.

## Design

### 1. Grounding scope — `codepet/Models/ChatContext.swift`

Add `focusDepartment: Department? = nil` to `compose(...)`. When set, insert (right after the brief part, before roadmap) a focus directive so the model prioritizes that department:

```swift
if let dep = focusDepartment {
    parts.append("The founder is focused on the \(dep.name) department right now — "
        + "prioritize \(dep.name) in your answer: \(dep.focus)")
}
```

The existing full department block still follows (context isn't removed — the answer is *focused*, not blinkered). Pure + deterministic; when `nil`, `compose` output is byte-identical to today.

### 2. Thread the selection — `codepet/Managers/CompanyStore.swift`

`sendChat` and `sendMessage` gain `department: Department? = nil`, passed straight into the `ChatContext.compose(...)` call in `sendMessage` (line ~479) as `focusDepartment: department`. Every existing caller (`walkThroughTask`, the run-task path, plain sends) keeps today's behaviour by omitting the argument (defaults to nil). The run-task compose call (line ~727) is unchanged.

```swift
func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil) async { … sendMessage(text, language: language, department: department) }
private func sendMessage(_ text: String, language: AppLanguage, department: Department? = nil) async { … ChatContext.compose(…, query: …, focusDepartment: department) … }
```

### 3. Composer UI — `codepet/Views/Copilot/ChatComposer.swift`

New inputs (provided by `CopilotChatView`, which has the store):
- `var accent: Color` / `var accent2: Color` — the active companion's two hues (for send + focus border).
- `var isBusy: Bool` — `isCompanionTyping || isStreaming`.
- `@Binding var selectedDept: Department?`.

**Department chip row** — a new row between the `TextField` and the existing control row. Render the **first 3** of `DepartmentCatalog.all` as toggle chips (2-letter `ab` badge + short name), plus an **overflow `Menu`** (`•••`) listing the remaining departments. Tapping a chip toggles `selectedDept` (tap the selected one to clear). Selected chip: filled `dep.accent.opacity(0.15)` + `dep.accent` border + `dep.accent` text; unselected: `hairline` border + `bodyText`. Overflow menu items set `selectedDept`; a check marks the current one.

**Control row unchanged in structure:** `quickActionsMenu` (`+`), `modeMenu` (`Ask ▾`), `Spacer`, `sendButton`.

**State expression:**
- **Idle** (not focused, not busy): current resting look, but the border/glow use the companion `accent` instead of the fixed purple→pink gradient.
- **Focused** (`focus.wrappedValue == true`): border brightens to `accent` and gains a soft outer `accent` glow (the existing `.shadow` becomes focus-gated + companion-tinted, respecting reduce-transparency).
- **Busy** (`isBusy`): the whole card `.opacity(0.72)` and the send button fills `mutedText` (regardless of `canSend`).

**Companion-tinted send:** the send button's `canSend` gradient changes from `[accentPurple, accentPink]` to `[accent, accent2]`; the disabled/busy fill stays `mutedText`. The `arrow.up` + shape/size unchanged.

### 4. Wiring — `codepet/Views/Copilot/CopilotChatView.swift`

- Add `@State private var selectedDept: Department?`.
- Compute `accent = PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple` and `accent2 = …?.secondColor ?? CodepetTheme.accentPink`.
- Pass `accent`, `accent2`, `isBusy: companyStore.isCompanionTyping || companyStore.isStreaming`, and `selectedDept: $selectedDept` into the single `composerView` (used in both empty + docked placements).
- In `send()`, pass the selection: `companyStore.sendChat(text, language: lang, department: selectedDept)`. (Quick-actions/`runQuickAction` may keep passing nil, or also pass `selectedDept` — pass `selectedDept` there too for consistency.)
- The selected department **persists** across sends for the session (a `@State`, not cleared on send) — a founder working on Marketing stays focused on Marketing until they clear the chip.

## Testing

- **`ChatContextFocusTests` (new, pure):** `compose(..., focusDepartment: dep)` contains "focused on the \(dep.name) department" and `dep.focus`; `compose(..., focusDepartment: nil)` does NOT contain "focused on the" and equals the pre-existing output for the same inputs (guard against drift). Use a `DepartmentCatalog.all.first!` fixture.
- **Build gate:** foreground `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED. Full suite 0 real failures + the new tests.
- **No unit test** for the composer UI or the send-threading (view/I-O) — verified by build + the signed-build visual pass.
- **Signed-build visual pass:** dept chips render (3 + overflow), toggle + tint on select; focusing the field brightens the border to the companion hue with a glow; while a reply streams the card dims + send greys; send is the companion's colors; the `+` quick-actions + `Ask ▾` still work; and selecting a dept then asking a question yields a visibly department-focused answer.

## Files

**New:** `codepetTests/ChatContextFocusTests.swift`
**Modified:** `codepet/Models/ChatContext.swift` (focus param), `codepet/Managers/CompanyStore.swift` (`sendChat`/`sendMessage` department param), `codepet/Views/Copilot/ChatComposer.swift` (chips + state + tinted send + new inputs), `codepet/Views/Copilot/CopilotChatView.swift` (selectedDept + accents + isBusy + threading).

## Risks / watch-items

- **Composer height:** the new chip row adds vertical height to the composer (both empty hero + docked). Confirm it doesn't crowd the empty-state hero on a small window — the chips may need to be a single scrollable line if they wrap.
- **`ChatComposer` previews** don't have the new inputs — update the `#Preview` host(s) with sample `accent`/`accent2`/`isBusy`/`selectedDept`.
- **Grounding-scope honesty:** the focus directive must genuinely reach the model (verify the `focusDepartment` is threaded all the way to the CF `context` string) — otherwise the chip is decorative. The pure test asserts the directive is in the composed string; the visual pass confirms the answer shifts.
- **`compose` default-path parity:** the `nil` branch must not change the existing output (a test pins this).

## Rollout

Implement on `feat/chat-redesign` → build + suite green → build & launch signed for the founder's visual sign-off → push (rebasing over concurrent commits). Nothing merges (branch held). Follow up on the W1 tracker's "Composer UX" task.
