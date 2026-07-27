# Codepet chat redesign — session handoff (2026-07-28)

Packaged so a fresh session can resume with no prior context. **Everything durable is on GitHub** (`My-Outcasts/codepet`). The build clone used this session lives in an ephemeral scratchpad and will be gone — re-clone to continue (see Resume).

## TL;DR status
- **Two open PRs, NOTHING merged** (user is holding all merges — this is a living design branch until they're happy):
  - **PR #39** `feat/chat-redesign` → `main` — the whole chat redesign + IA restructure (19 commits).
  - **PR #40** `fix/firebase-test-flake` → `main` — a standalone test-host crash fix.
- Branch builds green; full unit suite **470–475 tests, 0 failures** (count varies only because of the flake — see below).
- Merge order when the user is ready: **#40 first**, then merge `main` into `feat/chat-redesign` (or rebase) so #39's CI runs clean.

## What was built on `feat/chat-redesign` (in order)
1. **Chat redesign (v1)** — new `ChatMode` (client-side Ask/Plan/Build message-shaping, no backend), reusable `ChatComposer`, centered-hero `ChatEmptyState`; wired into `CopilotChatView`; deleted old input bar / greeting / dead "Let's build" stub; bubble restyle. Commits `5396c69`…`f9731a9`, `8912907` (refocus-after-send + floatingShadow), `df83ef8` (menu chevron fix).
2. **v2 polish** `585aa18` — `CompanionOrb` (gradient sphere) as hero focal + message avatar + "Thinking…"; glossier composer (gradient send + accent glow); Copy/Regenerate action row (Regenerate = client-side resend of last user msg); icon quick-action pills via `QuickAction`.
3. **Chat = main interface** `26cab11`(spec/plan)…`ca4a1e3` — chat is the **full-width default page**; removed the 50% side-panel + floating "C" toggle; **retired Overview**; split into **Roadmap** + **Second Brain** pages; nav tabs = `[summary, roadmap, secondBrain, company, tasks, library, environment]`; default `CompanyStore.view = .chat`; Codepet wordmark = Home→chat; chat centered in ~720pt column. New files `RoadmapView`/`SecondBrainView`; `OverviewView` deleted.
4. **v3 personalized + purple** `9e35a6f` — time-of-day + founder-name greeting with a **purple-gradient** second line; purple page wash; purple-forward orb; purple-gradient composer border; quick-action **cards** (title + non-selectable helper description + accent bar). ("Why"/description is helper text only — the whole card is the tap target.)
5. **Sidebar restructure** `194708f`(plan)…`122faf1` — **top bar → left `SidebarView`**: Codepet brand(→home) + collapse chevron, purple **New chat**, **Recent** (optimized history, grouped Today/Yesterday/Earlier, rename/delete), **Workspace** nav (7 items + count badges), bottom **Upgrade** card + `AccountMenuView` + ⚡Wake. Removed the "Your team · guiding · {company}" chat header + the in-chat History toggle; deleted `ThreadListView` (SidebarView has its own Recent).

Design specs + plans are committed under `docs/superpowers/specs/` and `docs/superpowers/plans/` (4 spec/plan pairs).

## Key files (all under `codepet/Views/Copilot/` unless noted)
`ChatMode.swift` · `ChatComposer.swift` · `ChatEmptyState.swift` · `CompanionOrb.swift` · `QuickAction.swift` · `CopilotChatView.swift` (chat + `CopilotBubble`) · `codepet/Views/Shell/SidebarView.swift` · `codepet/Views/Shell/AppShellView.swift` (shell = sidebar + content) · `codepet/Views/Overview/RoadmapView.swift` + `SecondBrainView.swift` · `codepet/Models/AppView.swift` (nav) · `codepet/Managers/CompanyStore.swift` (`view`, threads API).

## Outstanding — human GUI pass before merge (cannot be verified headlessly)
- Sidebar in a real window, **light + dark**: widths, Recent grouping, count badges, Upgrade/account row, collapse chevron behavior.
- Full-width chat: purple-gradient greeting intensity, orb hue (purple not rainbow), composer border, cards 2×2 spacing.
- Focus stays in the field after the **first** send; Recent switch / New chat / rename / delete work; Codepet wordmark → chat; Roadmap/Second Brain/Company/etc. pages land correctly.
- First-run onboarding still runs then lands in the full-width chat with the "What's your main goal…" interview (its "why" line is plain info, not selectable — confirmed).

## Open product decisions (none blocking)
- Trial credit amount, pill copy wording — user may still tune.
- Composer radii use literals 16/9 (no exact CodepetTheme token) — cosmetic, accepted.

## Resume instructions (new session)
1. Re-clone: `git clone --branch feat/chat-redesign https://github.com/My-Outcasts/codepet.git` into a **non-iCloud** dir (e.g. a scratch/tmp path). The `~/Documents/codepet*` checkouts are iCloud-synced (slow git, may be driven by other sessions) — don't build there.
2. Read the specs/plans under `docs/superpowers/` for full design intent.
3. Build/test in the **FOREGROUND**: `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Never background xcodebuild (it stalls). First build resolves Firebase SPM (~1–2 min).

## Gotchas / environment
- **Signed vs unsigned:** `CODE_SIGNING_ALLOWED=NO` is fine for build/test, but **Firebase sign-in needs a signed build** — to actually run + sign in, open in Xcode and set team **YL72VTKBR7** (⌘R). Unsigned `open` of the .app may stall at sign-in.
- **Known test flake (FIXED on PR #40, not yet on this branch):** `CompanyStoreScaffordOnboardingTests` crash-retries on FirebaseApp-not-configured under XCTest. Root cause: `ServerLoggingGate.isOptedOut` / `ReflectionAPIClient` auth-token provider called `Auth.auth()` unguarded at launch; #40 guards both on `FirebaseApp.app() != nil`. Until #40 lands here, expect the overall `xcodebuild test` to show `TEST FAILED` from that crash-retry even though 0 real failures.
- **SourceKit false positives:** editor shows "Cannot find CodepetTheme/ChatMode/Color.dyn" etc. for these files out of build context — ignore; the authoritative signal is `xcodebuild build`.
- **git on iCloud:** use `GIT_OPTIONAL_LOCKS=0`; commit backgrounded if it hangs. (Non-issue in a /tmp clone.)
- **Companion identity:** the user chose a **gradient orb** as the chat identity (over the pixel pet) for this surface. Purple-brand gradients throughout.

## Process used (repeatable)
Brainstorm (mock in HTML→PNG, confirm) → spec + plan under `docs/superpowers/` → subagent-per-task implementation with a build/full-suite gate → review diff → push. Mockups were rendered with headless Chrome; the user approved each via side-by-side PNGs.
