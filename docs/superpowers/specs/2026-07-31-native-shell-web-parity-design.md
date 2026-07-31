# Native Shell — Web Parity Redesign

**Date:** 2026-07-31
**Status:** Approved design → ready for implementation plan
**Branch:** `feat/shell-web-parity` (off `main` @ `4141d1d`)
**Target:** rework the native macOS app's top-level shell to match the live web app (`codepet-v1-2.vercel.app`): a top horizontal nav + a persistent, collapsible right-docked "Your team" copilot, with content on the left.

---

## 1. Goal

Make the native app's shell look and behave like the website: a **top nav** (Overview · Company · Tasks · Library · Environment), the **"Your team" copilot docked as a persistent, collapsible right-side panel across every tab**, and the selected destination's content filling the left. Remove the native-only divergences (left icon rail; Chat as a separate full-screen destination).

## 2. Non-goals

- Redesigning the *contents* of any destination view (the Overview roadmap, Company, Tasks, Library, Environment, Second Brain, and the chat message UI all stay as they are — only their placement/framing changes).
- Onboarding / first-run flow (gated before the shell by `ContentView`; untouched).
- The coding-agent port (separate branch `feat/coding-agent-copilot`; not included here). The copilot dock here is `main`'s `CopilotChatView`.
- Renaming or restyling the companion (native already renders the selected companion's name/color automatically — the web's "Nova" comes for free).

## 3. Current vs target

| | Web (target) | Native `main` (now) |
|---|---|---|
| Navigation | **Top** horizontal nav: Overview · Company · Tasks · Library · Environment; account dropdown top-left; Wake + Upgrade top-right | **Left** vertical icon rail (`AppRailView`) + slim top bar (title only) |
| Copilot ("Your team") | **Persistent collapsible right-docked panel**, present on every page | **Separate full-screen** `.chat` destination; not docked (`AppShellView.swift:4-7`: "it is no longer a docked panel") |
| Second Brain | Toggle on the Overview (Roadmap / Second Brain switch) | Separate `.secondBrain` destination |
| Settings / Billing / Support | In the top-left account dropdown | Separate destinations reached via the rail/menu |
| Default landing | Overview | `.chat` (full-screen) |

## 4. Approach

**Restructure `AppShellView` in place.** Rebuild its `body` from `HStack { AppRailView; VStack { topBar; content } }` into `VStack { topNav; HStack { content; copilotDock } }`. Reuse existing components — `AccountMenuView` (account dropdown), `CopilotChatView` (the dock's content), `RoadmapView` (Overview), `SecondBrainView` (Overview toggle target) — and retire `AppRailView`. *(Rejected alternative: a parallel feature-flagged shell — more code, no benefit, and we want the old shell gone, not toggled.)*

## 5. Architecture

### 5.1 New `AppShellView` layout
```
VStack(spacing: 0):
  TopNavView                       // account ▾ | tabs | wake + upgrade
  Divider
  HStack(spacing: 0):
    content                        // switches on companyStore.view — left, flexible
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    if dockVisible:
      Divider (vertical)
      CopilotChatView()            // the dock — fixed width, full height
        .frame(width: dockWidth)
    else:
      collapsedDockHandle          // slim reopen affordance
  .frame(maxWidth: .infinity, maxHeight: .infinity)
.background(CodepetTheme.pageBackground)
```
The copilot dock lives **outside** the `content` switch so it persists across every tab (matching web).

### 5.2 `TopNavView` (new — `codepet/Views/Shell/TopNavView.swift`)
A single horizontal bar, replacing both `AppRailView` and the old `topBar`:
- **Left:** app wordmark + **account dropdown** (`AccountMenuView`, presented as a `Menu`/popover) exposing account info + **Settings · Billing · Support** (routes via `companyStore.select(.settings/.billing/.support)` — which now render in the `content` area, not the dock).
- **Center:** tab buttons **Overview · Company · Tasks · Library · Environment**, each mapping to a `companyStore.view` value; the active tab underlined/accented in the companion color (mirror the rail's current selection styling). Tabs carry the same count badges the rail/web show (Tasks, Library, Environment).
- **Right:** the existing **Wake pill** + **Upgrade** button (moved verbatim from `AppShellView.topBar`).

Tab → view mapping: **Overview → `.roadmap`**, Company → `.company`, Tasks → `.tasks`, Library → `.library`, Environment → `.environment`.

### 5.3 Global docked copilot
- Content is the unchanged `CopilotChatView()`.
- **Width:** `dockWidth = 380`.
- **Collapse:** a `@State private var dockCollapsed` in `AppShellView` (session-only; default expanded). A toggle in the dock header (mirroring web's `▷`) flips it; collapsed shows a slim vertical handle with the companion orb to reopen.
- **Responsive auto-collapse:** wrap the shell in a `GeometryReader`; when total width `< 900pt` (dock 380 + a 520 content floor), force-collapse regardless of the manual flag so content is never crushed (native window min is 560). Manual expand is honored again once width allows.
- Because the dock is always mounted (just width-toggled), `CopilotChatView`'s state/streaming is preserved across tab switches.

### 5.4 Destination changes
- **Remove the standalone `.chat` destination** from `content` (the copilot is always the dock). `content`'s `if view == .chat` branch is deleted; any code that did `companyStore.select(.chat)` to "show the chat" instead ensures the dock is expanded (`dockCollapsed = false`) rather than switching the main view. (Grep for `select(.chat)` — e.g. `RoadmapView`/`RoadmapMapView`/`TasksView` navigation — and repoint to "expand the dock".)
- **Second Brain becomes an Overview toggle:** the Overview (`RoadmapView`) gains a **Roadmap / Second Brain** segmented control at the top that swaps its body between the roadmap map and `SecondBrainView`'s content. Remove `.secondBrain` as a standalone destination/nav item. (If `RoadmapView` already renders a Roadmap/Second-Brain toggle, wire it to `SecondBrainView` instead of a separate destination.)
- **Default landing view → `.roadmap`** (Overview), matching web (was `.chat`).
- **Settings / Billing / Support** remain valid `content` destinations but are reached only from the account dropdown (no nav tab).

### 5.5 Retired
- `codepet/Views/Shell/AppRailView.swift` — deleted (its nav role moves to `TopNavView`).
- `AppShellView.topBar` — folded into `TopNavView`.
- The `.chat` content branch.

## 6. State & data flow
- **Nav selection** = existing `companyStore.view` (unchanged enum; `.chat`/`.secondBrain` simply stop being selectable destinations). Tabs set it via `companyStore.select(_:)`.
- **Dock collapse** = `@State` in `AppShellView` + the `GeometryReader` width rule. No store/persistence change needed for v1.
- **Account dropdown** routes to `.settings/.billing/.support` (already-existing views) in the content area.

## 7. Edge cases
- **Narrow window** (≥560 and <900): dock auto-collapses; content uses full width; reopen handle present.
- **A destination with no content beside a dock** (e.g. Settings): content simply renders at reduced width with the dock beside it, same as web.
- **`select(.chat)` callers**: repointed to expand the dock (Section 5.4) — verified by grep so no dead navigation.
- **Onboarding**: `ContentView` still gates the shell; unaffected.

## 8. Testing
- **Build** TEAM-signed (`BUILD SUCCEEDED`).
- **Logic tests** (lightweight, where testable without the GUI): the tab→`view` mapping and the auto-collapse width rule (extract the width→collapsed decision into a tiny pure helper, e.g. `ShellLayout.dockCollapsed(forWidth:manual:)`, and unit-test it).
- **Manual visual pass (founder):** top nav switches all tabs; copilot dock persists + collapses/expands + auto-collapses on a narrow window; Overview's Roadmap/Second-Brain toggle works; account dropdown reaches Settings/Billing/Support; default landing is Overview. (SwiftUI shell — an agent can't click through it.)

## 9. File change summary
- **New:** `codepet/Views/Shell/TopNavView.swift`; `codepet/Models/ShellLayout.swift` (pure collapse-decision helper) + its test.
- **Modify:** `codepet/Views/Shell/AppShellView.swift` (new layout: top nav + content + dock; remove `.chat` branch, `topBar`, rail; default view → `.roadmap`); `codepet/Views/Roadmap/RoadmapView.swift` (Roadmap/Second-Brain toggle → `SecondBrainView`); `AccountMenuView.swift` if it needs a top-nav presentation entry point; any `select(.chat)` call sites (repoint to expand dock); wherever the default `companyStore.view` is initialized.
- **Delete:** `codepet/Views/Shell/AppRailView.swift`.

## 10. Deferred / future
- Persisting the dock-collapsed preference across launches.
- Per-tab dock behavior differences (v1: identical global dock everywhere, like web).
- Reconciling with the coding-agent branch (`feat/coding-agent-copilot`) at merge time — both touch `CopilotChatView`'s placement/usage; whichever merges second rebases onto the first.
