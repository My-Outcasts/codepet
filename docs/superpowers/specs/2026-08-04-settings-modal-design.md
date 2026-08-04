# Settings becomes one centered modal

**Date:** 2026-08-04
**Status:** design approved, not yet planned
**Branch:** `feat/settings-modal`

## The problem

Settings today is a 182-line scrolling page (`Views/Settings/SettingsView.swift`) reached
from the account dropdown, with Billing and Support as two more full pages beside it. Three
things are wrong with that:

1. **It is a destination.** Opening Settings navigates away from the Overview, and closing
   it has no route to return to — the founder loses their place.
2. **It cannot hold what we want to add.** One scroll already mixes identity, companion,
   language, theme, brief, and sign-out. The three additions below would double it.
3. **It is the only surface in the app rendered in the pixel font.** Dense form rows at
   11–13pt in a pixel face are the hardest thing in Codepet to scan.

The founder-facing gap underneath: the companion's tone is hardcoded, the founder cannot
see or delete what the companion remembers, and there is no founder-level profile to ground
replies in.

## What we are building

A centered modal with a fixed left rail and a scrolling right panel, absorbing Settings,
Billing, and Support. Three new capabilities live inside it: **tone controls**, **memory
management**, and a **founder profile**.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Modal scope | Absorbs Settings + Billing + Support | One chrome for every account-level surface; the account dropdown collapses three items to one |
| Memory scope | Both stores, two groups | The `remember_fact` list is the trust-critical half; `PetMemoryStore` is derived, so summary + Reset is enough |
| Tone scope | One global set | Companions stay identity/voice only; adds exactly one object to the payload |
| Typography | Inter throughout | The only way it reads like the reference; pixel type stays with the logo, sprites, and game chrome |

## Architecture

### A state axis, not a destination

Settings stops being an `AppView`:

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case preferences, aiSettings, company, memory,
         notifications, billing, usage, support, advanced
}

// CompanyStore
@Published var settingsSection: SettingsSection?   // nil = closed
```

`nil` means closed; setting it opens the modal on that section. The founder keeps their
place, because there is no route to restore on close. The `String` raw values also give
chat cards a deep link — a memory-related card can open `.memory` directly.

### Presentation

A `ZStack` overlay in `AppShellView`, **not** `.sheet`. A macOS sheet is window-attached and
descends from the titlebar, so it cannot be centered and cannot match the reference.

- dimmed scrim over the whole shell; clicking it closes
- `Escape` closes; `⌘,` opens
- suppressed while `ContentView`'s `isOnboarding` guard is true
- `⌘,` must not fire while the chat composer holds focus

### Geometry

- panel: `min(920, width − 96) × min(660, height − 96)`, corner radius 16, one shadow
- rail: fixed **220pt**, carries its own "Settings" title, never scrolls
- right panel scrolls independently
- below ~820pt window width the rail collapses to a section dropdown above the panel,
  mirroring the responsive rule `ShellLayout` already applies to the dock

### Files

`Views/Settings/SettingsView.swift` is replaced, not wrapped.

| File | Role |
|---|---|
| `SettingsModal.swift` | scrim, panel frame, `⌘,` / `Escape`, rail ↔ panel switch |
| `SettingsRail.swift` | nav list and selection |
| `SettingsChrome.swift` | shared vocabulary: section header (title + subtitle), `SettingsGroup` (bordered card), `SettingsRow(label, description) { control }` |
| one file per panel | `PreferencesPanel`, `AISettingsPanel`, `CompanyPanel`, `MemoryPanel`, `NotificationsPanel`, `BillingPanel`, `UsagePanel`, `SupportPanel`, `AdvancedPanel` |

`SettingsChrome` matters most. Every row is **label + optional description + exactly one
right-aligned control**. Dropdown for three or more options, toggle for binary, button for
an action, `accentOrange` text for destructive. Defining that once is what stops nine
panels drifting apart.

## The nine panels

| Section | Contents |
|---|---|
| **Preferences** | Profile: initial-circle avatar, Preferred Name, Email (read-only) · Appearance: Theme `Light │ System │ Dark` · Language `English / Tiếng Việt` |

**Preferences persistence**, to remove the ambiguity: Preferred Name writes to the existing
founder-name field on the company brief — the same source `founderName` already reads in
`AccountMenuView` and `SettingsView`, so the avatar initial and the greeting follow it.
Email is read-only from `authManager`. Theme and Language keep their current homes
(`appState.appTheme`, `appState.uiLanguage`); this pass moves the controls, not the storage.
| **AI Settings** | Base style and tone · Characteristics: Warm, Enthusiastic, Emoji · Custom instructions · About you: Role, More about you |
| **Company** | Companion row — `Crash · "Choose a companion that works alongside you" · Select ›` drilling into the picker · Edit company brief |
| **Memory** | Enable memory · "What Crash knows" (deletable rows) · "Coding activity" (read-only + Reset) |
| **Notifications** | Category rows with `Off │ In-app`: session nudges (`HealthNudgeController`), run finished |
| **Billing** | Plan name + one-line value prop + Compare plans (existing `BillingView` content) |
| **Usage** | No number, no cap, no meter: usage is not tracked client-side. The section states that plainly. The 30/day figure this spec originally asserted is wrong — a 429 fixture shows the server returning `limit: 50`, and `MockChat.swift:365` describes the model as credits, not a per-day cap. Founder's call, Aug 4: keep the section, drop the invented figure |
| **Support** | Existing `SupportView` content |
| **Advanced** | Sign out · version. Export data and Delete all chats are deferred to their own task — both need real Firestore work, and a button that does nothing is worse than a missing one |

## The payload contract

One field on the company doc, `companies/{uid}.founderPrefs`, so preferences sync across
machines rather than living in UserDefaults. It holds a wrapper, not a bare style object —
memory and notification choices need somewhere to live too:

```swift
struct FounderPrefs: Codable, Equatable {
    var style: AIStyle = .init()
    var memoryEnabled: Bool = true
    /// Section key -> channel. Absent key means the category's default.
    var notifications: [String: NotificationChannel] = [:]
}

struct AIStyle: Codable, Equatable {
    enum Level: String, Codable { case less, `default`, more }
    enum BaseTone: String, Codable { case `default`, direct, encouraging, analytical }

    var baseTone: BaseTone = .default
    var warmth: Level = .default
    var enthusiasm: Level = .default
    var emoji: Level = .default
    var customInstructions: String = ""
    var role: String = ""
    var moreAboutYou: String = ""

    /// nil when every knob is `.default` and every string is empty.
    func promptFragment() -> String?
}
```

`promptFragment()` is the entire behavioral seam. **All-defaults returns `nil`**, so an
untouched settings panel adds zero tokens to every request — the property that makes this
safe to ship and trivial to test.

Injection: the fragment travels in the founder payload and is composed into the system
prompt in `functions/src/companyChatCore.ts`, where the persona and company context are
already assembled (the `You are ${c.name}…` builder around line 69).

### Why "Headers & Lists" is not a knob

The reference (ChatGPT) offers it. Codepet cannot, yet. `companyChatCore.ts:71` instructs:
*"Write plain text only — no markdown, asterisks, backticks, or arrows; the chat shows your
words as-is."* That is accurate — the transcript has no markdown renderer. A "more
structure" setting would print literal asterisks into replies. The knob returns when the
chat renders markdown, not before.

The **Emoji** knob is therefore an override of the existing `no emoji` clause in the same
sentence, not a new instruction.

## Deliberately excluded

| Excluded | Reason |
|---|---|
| Accent color picker | Accent derives from the chosen companion; a user-set accent would multiply the open roadmap accent-collision bug |
| Email notification channel | No email infrastructure — offering the option would lie |
| Avatar upload | No image pipeline; the reference has one, we don't need one |
| Storage quota meter | We store almost nothing per user. The meter *grammar* is reused for Usage, where the content is real |
| Per-department tone override | A second layer of state and a second place to debug a wrong-sounding reply. Nobody asked |
| Age verification, parental controls, MFA | No product surface behind them |

## Deletions and migration

| Site | Change |
|---|---|
| `Models/AppView.swift` | remove `.settings`, `.billing`, `.support` cases and their `title` / `icon` arms |
| `Views/Shell/AppShellView.swift:150-155` | remove the three branches |
| `Models/ShellLayout.swift:54` | drop the three cases from the list |
| `Views/Shell/AccountMenuView.swift:61-63` | three rows collapse to one **Settings** |
| `Views/Shell/TopNavView.swift:65` | Upgrade pill opens the modal on `.billing` instead of routing |
| `codepetTests/ShellLayoutTests.swift:70` | drop the three cases from the array |

`AppView.from(navDestination:)` never mapped these three, so no chat-card navigation breaks.

## Testing

All pure and offline:

- `promptFragment()` — all-defaults returns `nil`; each knob at each level emits its exact
  line; custom instructions append last
- `SettingsSection` raw-value round-trip, proving a chat card can open `.memory` directly
- rail-collapse threshold in `ShellLayout`, same shape as the existing dock tests
- memory: deleting a fact removes it from the payload; `enableMemory = false` suppresses
  both stores
- one vitest in `functions/` proving the style block reaches the system prompt, and is
  absent when the fragment is empty

## Risks

1. **Onboarding.** The modal must be suppressed while onboarding is running.
2. **Keyboard conflict.** `⌘,` must be inert while the chat composer has focus.
3. **Concurrent checkout.** `~/Developer/codepet` is being edited by another session; this
   work happens in the `codepet-settings-modal` worktree.
