# Chat as the main interface — design spec

**Date:** 2026-07-27
**Target:** `My-Outcasts/codepet` native macOS app, branch `feat/chat-redesign` (extends the chat redesign already on that branch).
**Status:** Approved design.

## Goal
Make **chat the default, full-width main interface** of Codepet. Remove the Overview tab and the persistent 50% chat side-panel; split Overview's `Roadmap | Second Brain` toggle into two standalone pages. Preserve first-run onboarding. Do not restyle the top bar (its tab *set* changes, but its look/structure stays).

## Decisions (locked with product owner)
1. Chat = full-width home + default landing. The always-on 50% right panel and the floating "C" toggle are **removed**; `content` is full-width.
2. **No Chat tab.** Chat is the default; the **Codepet wordmark becomes a Home button → chat**. Top-bar tabs become: **Summary · Roadmap · Second Brain · Company · Tasks · Library · Environment** (Overview removed; Second Brain right after Roadmap).
3. Roadmap and Second Brain each become their own page (the old Overview toggle is split).

## Non-goals
- No left chat sidebar (top bar stays the only chrome).
- No new chat *visual* work — reuse the v2 chat already on this branch (orb hero, glossy composer, mode chip, icon pills, orb avatars, Thinking…, Copy/Regenerate). The only chat change is full-width layout.
- No backend/`CompanyStore` logic changes beyond the default-view value.
- First-run `OnboardingView` (gated in `ContentView` before the shell) is untouched; the in-chat enrichment interview now renders in the full-width chat.

## Current structure (as-is)
- `AppShellView` = `VStack { topBar; Divider; HStack { content (per-tab, flex) | Divider | copilot (CopilotChatView, 50%) } }`, with a floating "C" `chatToggle` that collapses the copilot panel.
- `AppView.navTabs = [.summary, .overview, .company, .tasks, .library, .environment]`; `CompanyStore.view` defaults to `.overview`.
- `OverviewView` (256 lines) = a "How to read this map" pill + a `Roadmap | Second Brain` toggle + a KEY legend + a Project-Progress card + body that shows `RoadmapMapView(tasks:)` or `SecondBrainPanel(data:lang:)`.

## Target structure
- `AppShellView` = `VStack { topBar; Divider; content (full-width) }`. No copilot panel, no `copilotCollapsed`, no `chatToggle`.
- `content` branches add `.chat → CopilotChatView()`, `.roadmap → RoadmapView()`, `.secondBrain → SecondBrainView()`; `.overview` branch removed.
- Codepet wordmark in `topBar` becomes a `Button { companyStore.selectedDeptKey = nil; companyStore.select(.chat) }`.
- `AppView`: add `.chat` and `.secondBrain`; retire `.overview`; `navTabs = [.summary, .roadmap, .secondBrain, .company, .tasks, .library, .environment]`; `from(navDestination: "roadmap") → .roadmap`. Titles: Chat = "Trò chuyện"/"Chat", Second Brain = "Bộ não thứ hai"/"Second Brain". Icons: chat `"message"`, secondBrain `"brain"`, roadmap keeps `"map"`.
- `CompanyStore.view` defaults to `.chat`; `reset()` sets `.chat`.
- `RoadmapView` = the map (`RoadmapMapView`) + the How-to-read pill + KEY legend + Project-Progress card, extracted from `OverviewView`, **minus the toggle**. `SecondBrainView` = `SecondBrainPanel` + the same header chrome, minus the toggle. `OverviewView` is deleted once both exist and nothing references it.
- `CopilotChatView` full-width: center the conversation list, the composer, and the empty-state hero in a **max-width ~720pt column** (readable, matches the references) instead of stretching edge-to-edge.

## Testing
- Unit (extend `AppViewTests`): `navTabs` excludes `.overview`, includes `.roadmap` and `.secondBrain`, excludes `.chat`; `from(navDestination:"roadmap") == .roadmap`.
- Build green; full suite green (note: the Firebase-flake fix lives on a separate branch/PR #40 — this branch may still show the known crash-retry until #40 merges in).
- Views verified via SwiftUI previews + a human GUI pass (full-width chat in light/dark, logo→home, Roadmap & Second Brain pages, onboarding still lands in chat).

## Risks
- Retiring `.overview` touches several files; the build breaks until AppView + AppShellView + OverviewView deletion land together (sequenced so each task boundary is green).
- Full-width chat must keep the existing message/scroll behavior — center via a max-width frame, don't rewrite the list.
- Removing the omnipresent chat panel is a real UX change (chat is now a destination, not always visible) — intended.
