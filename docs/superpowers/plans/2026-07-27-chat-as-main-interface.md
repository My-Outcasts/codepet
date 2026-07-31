# Chat as Main Interface — Implementation Plan

> **For agentic workers:** implement task-by-task; each task ends build-green (and, where noted, test-green). Steps use `- [ ]`.

**Goal:** Make chat Codepet's full-width default page; remove Overview + the 50% side panel; split Roadmap/Second Brain into two pages; keep onboarding and the top-bar look.

**Architecture:** Reuse the v2 `CopilotChatView` as a full-width destination; `AppShellView` drops its copilot side panel; `AppView` gains `.chat`/`.secondBrain` and retires `.overview`; Overview's map/panel move into standalone `RoadmapView`/`SecondBrainView`.

## Global Constraints
- Native macOS SwiftUI; edits under `codepet/Models`, `codepet/Managers`, `codepet/Views`. All colors/spacing via `CodepetTheme`. Bilingual vi/en. Do not restyle the top bar (brand/account/tabs/wake/upgrade) beyond making the wordmark a Home button and changing which tabs appear.
- No backend/`CompanyStore` logic changes except the default `view` value.
- Build/test in the FOREGROUND: `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Known pre-existing `CompanyStoreScaffordOnboardingTests` Firebase-init flake may crash-retry (fixed on separate PR #40, not on this branch) — treat only those 2 as known; nothing else may newly fail.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

### Task IA-1: Add `RoadmapView` + `SecondBrainView` (extract from Overview; leave nav untouched)
**Files:** Create `codepet/Views/Overview/RoadmapView.swift`, `codepet/Views/Overview/SecondBrainView.swift`. Read `codepet/Views/Overview/OverviewView.swift` (256 lines) to reuse its header pieces.
**Do:** Each new view renders the shared header chrome that OverviewView shows (the "How to read this map" pill, the KEY legend, the Project-Progress card) **minus** the `Roadmap | Second Brain` toggle, then its body:
- `RoadmapView` body → `RoadmapMapView(tasks: companyStore.company.tasks)` (match how OverviewView builds `tasks`).
- `SecondBrainView` body → `SecondBrainPanel(data: SecondBrainData(company: companyStore.company), lang: lang, …)` (match OverviewView's exact call, including any closures it passes).
Factor the shared header into a small private helper or a shared subview to avoid duplication. Do NOT modify OverviewView or nav yet (build stays green with OverviewView still wired).
**Verify:** `xcodebuild build` → BUILD SUCCEEDED. Add a `#Preview` to each. Commit: `feat(nav): extract RoadmapView + SecondBrainView from Overview`.

---

### Task IA-2: Rewire navigation — chat is home, Overview retired, full-width shell
**Files:** `codepet/Models/AppView.swift`, `codepet/Managers/CompanyStore.swift`, `codepet/Views/Shell/AppShellView.swift`; delete `codepet/Views/Overview/OverviewView.swift`. Test: `codepetTests/AppViewTests.swift`.

- [ ] **AppView.swift** — add cases and retire `.overview`:
  - `enum` cases: replace `overview` usage; final set includes `chat`, `summary`, `company`, `roadmap`, `secondBrain`, `tasks`, `library`, `environment`, `settings`, `billing`, `support` (remove `overview`).
  - `navTabs = [.summary, .roadmap, .secondBrain, .company, .tasks, .library, .environment]`
  - `title(_:)`: add `case .chat: return lang == .vi ? "Trò chuyện" : "Chat"` and `case .secondBrain: return lang == .vi ? "Bộ não thứ hai" : "Second Brain"`; remove the `.overview` case.
  - `icon`: add `case .chat: return "message"` and `case .secondBrain: return "brain"`; remove `.overview` (`roadmap` keeps `"map"`).
  - `from(navDestination:)`: change `case "roadmap": return .roadmap` (was `.overview`).
- [ ] **CompanyStore.swift** — line 10 `@Published var view: AppView = .chat` (was `.overview`); line ~842 in `reset()` `view = .chat` (was `.overview`).
- [ ] **AppShellView.swift** — full-width content + new branches + Home logo + drop the side panel:
  - Delete `@State private var copilotCollapsed`, the `copilot` and `chatToggle` computed vars, and the `.overlay(alignment: .bottomTrailing) { chatToggle … }`.
  - `body`'s inner layout becomes just `content.frame(maxWidth: .infinity, maxHeight: .infinity)` (remove the `GeometryReader`/`HStack`/`Divider`/`copilot` split).
  - `content`: remove the `.overview → OverviewView()` branch; add `if companyStore.view == .chat { CopilotChatView() }`, `else if .roadmap { RoadmapView() }`, `else if .secondBrain { SecondBrainView() }`.
  - Make the wordmark a button: replace the `Text("Codepet")…` in `topBar` with `Button { companyStore.selectedDeptKey = nil; companyStore.select(.chat) } label: { Text("Codepet").font(CodepetTheme.pixel(16)).foregroundColor(CodepetTheme.primaryText) }.buttonStyle(.plain)`.
  - Delete `codepet/Views/Overview/OverviewView.swift`.
- [ ] **AppViewTests.swift** — add:
  ```swift
  func testNavTabsAreTheChatFirstStructure() {
      XCTAssertFalse(AppView.navTabs.contains(.overview) == true) // .overview retired
      XCTAssertTrue(AppView.navTabs.contains(.roadmap))
      XCTAssertTrue(AppView.navTabs.contains(.secondBrain))
      XCTAssertFalse(AppView.navTabs.contains(.chat))            // chat is home, not a tab
      XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
  }
  ```
  (If `.overview` is fully removed from the enum, drop the first assertion — it won't compile — and instead assert `navTabs.first == .summary` and `navTabs == [.summary, .roadmap, .secondBrain, .company, .tasks, .library, .environment]`.)
**Verify:** `xcodebuild build` → SUCCEEDED (no lingering `.overview` refs); full suite green except the known flake. Commit: `feat(nav): chat is the full-width home; retire Overview; Roadmap/Second Brain tabs`.

---

### Task IA-3: Full-width chat column
**Files:** `codepet/Views/Copilot/CopilotChatView.swift`.
**Do:** Constrain the chat content to a centered readable column (~720pt) now that it's full-width instead of a 50% panel:
- Wrap the `messageList` scroll content and the docked `composerView` so their inner content is centered with `.frame(maxWidth: 720)` inside a full-width, centered container (e.g. put the message `VStack` and the composer each in an `HStack { Spacer(minLength: 0); <content>.frame(maxWidth: 720); Spacer(minLength: 0) }`, or a centered `.frame(maxWidth: 720)` with `.frame(maxWidth: .infinity)` parent). The empty-state (`ChatEmptyState`) already centers — leave it, but confirm it looks right full-width.
- Keep all existing behavior (scroll-to-bottom, typing/producing rows, History branch, send/focus).
**Verify:** `xcodebuild build` → SUCCEEDED; full suite green except known flake. Commit: `style(chat): center chat content in a max-width column for full-width`.

---

## Self-Review
- Spec coverage: chat full-width home (IA-2 branch + IA-3 centering) ✓; Overview removed (IA-2) ✓; Roadmap+Second Brain pages (IA-1 + IA-2 branches/tabs) ✓; logo→home (IA-2) ✓; onboarding untouched (no task touches ContentView/OnboardingView) ✓; top bar not restyled (only tab set + logo button) ✓.
- Sequencing keeps build green: IA-1 adds views without touching nav; IA-2 flips nav + deletes Overview in one task; IA-3 is isolated polish.
- Type consistency: `RoadmapView()`/`SecondBrainView()` no-arg views used by AppShellView match IA-1's definitions; `.chat`/`.secondBrain` used across AppView/CompanyStore/AppShellView are all defined in IA-2's AppView edit.
