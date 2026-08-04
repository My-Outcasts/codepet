# Settings Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Settings, Billing and Support full pages with one centered modal, and add tone controls, memory management, and a founder profile inside it.

**Architecture:** Settings becomes an overlay keyed by `CompanyStore.settingsSection` (`nil` = closed) rather than an `AppView` destination, so closing returns the founder to where they were. Layout decisions live in pure `ShellLayout` helpers; a shared `SettingsChrome` row vocabulary keeps nine panels from drifting. The new tone/profile values persist as `FounderPrefs` on the company doc and reach the model through one `promptFragment()` seam composed into the system prompt in `companyChatCore.ts`.

**Tech Stack:** SwiftUI (macOS 13+), XCTest, Firebase Firestore, TypeScript Cloud Functions, jest (ts-jest — `functions/` uses jest, NOT vitest; that is the web app).

## Global Constraints

- **Design spec:** `docs/superpowers/specs/2026-08-04-settings-modal-design.md`. Read it before Task 1.
- **Typography:** Inter only in this surface — `CodepetTheme.inter(_:weight:)`, `.title()`, `.subtitle()`, `.label(_:_:)`. Never `.pixelSystem` or `CodepetTheme.pixel` in any file this plan creates.
- **Colours:** only `CodepetTheme` tokens (`surface`, `hairline`, `primaryText`, `bodyText`, `mutedText`, `accentPurple`, `accentOrange`). No literal hex.
- **Destructive actions** use `CodepetTheme.accentOrange` text, never red literals.
- **The Usage panel shows NO cap, NO denominator and NO meter.** The `30`/day figure in Task 6's `UsagePanel` code block below is WRONG and is superseded: there is no client-side counter, a 429 fixture shows the server returning `limit: 50`, and `MockChat.swift:365` describes the model as credits rather than a per-day cap. The section states plainly that usage is not tracked on this device. Founder's call, Aug 4.
- **Every persisted type decodes absent keys as defaults.** Swift's synthesized `Decodable` does NOT fall back to a property's declared default — it calls `decode(forKey:)` and throws `keyNotFound`. So `FounderPrefs`, `AIStyle`, and the `CompanyState.founderPrefs` field all need `decodeIfPresent(...) ?? default` (a hand-written `init(from:)` where synthesis won't do). Without this, adding one property later makes every document written before it undecodable. Found in the Task 7 review, before persistence landed.
- **Separators are `SettingsDivider()`, never bare `Divider()`.** SwiftUI's `Divider()` renders in the system separator colour, which does not track `CodepetTheme` — a card's `hairline` border and a system separator inside it read as two different greys. `SettingsDivider` lives in `SettingsChrome.swift` and is backed by `CodepetTheme.hairline`. (Added after the Task 3 review; founder's call, Aug 4.)
- **No accent-colour control.** The accent derives from the chosen companion; a user-set accent would compound the open roadmap accent-collision bug.
- **Bilingual:** every user-facing string takes `lang == .vi ? "…" : "…"`, matching `AppView.title(_:)`.
- **Language is read from the environment**, not the store: `@Environment(\.uiLanguage) private var lang` — the idiom the deleted `SettingsView` used. Only the Language *picker* binds `$appState.uiLanguage` (the storage behind that key). **Every panel code block below writes `private var lang: AppLanguage { appState.uiLanguage }` for readability; replace that line with the `@Environment` property wrapper in each file, and drop `@EnvironmentObject var appState` from any panel that used it only for `lang`.**
- **Verified API names** (do not substitute): companion catalogue is `PetCharacter.all: [String: PetCharacter]` and `PetCharacter.starters`; email is `authManager.currentUser?.email`; founder name is `companyStore.company.brief.founderName` (`String?`); theme is `AppTheme.system/.light/.dark`; language is `AppLanguage.vi/.en`; the brief editor is `CompanyOnboardingView(prefillBrief:onDone:)`; derived memory fields are `PetMemory.totalSessions` and `PetMemory.currentStreak`.
- **`AppShellView` is not rendered during onboarding** (`ContentView` routes `companyStore.isOnboarding` to the onboarding flow instead), so the modal cannot appear mid-onboarding. The `⌘,` menu command still guards on it so settings does not pop open the moment onboarding finishes.
- **Panel geometry:** panel `min(920, w − 96) × min(660, h − 96)`; rail fixed `220pt`; rail collapses below `820pt` shell width.
- **Test command:** `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/<TestClass>`
- **Before running any test, quit the running app.** A live `codepet.app` holds the Firestore LevelDB lock and the test host aborts in `FirestoreClient::Initialize`. Check `pgrep -f 'codepet.app/Contents/MacOS/codepet'` first.
- **Never pass `CODE_SIGNING_ALLOWED=NO`.** It rebuilds the app target ad-hoc into shared DerivedData and breaks keychain auth. Order is always: tests first, signed build last.
- **Phase 1 (Tasks 1-6) is shippable on its own** — the modal replaces three pages with no new capabilities. Phase 2 (Tasks 7-12) adds tone, memory and notifications.

---

# Phase 1 — the container and the migration

### Task 1: `SettingsSection` and the layout rules

**Files:**
- Create: `codepet/Models/SettingsSection.swift`
- Modify: `codepet/Models/ShellLayout.swift` (append to the enum)
- Test: `codepetTests/SettingsSectionTests.swift`

**Interfaces:**
- Consumes: `AppLanguage` (existing, `codepet/Models/`)
- Produces: `SettingsSection` (RawRepresentable by `String`, `CaseIterable`, `Identifiable`) with `title(_:)`, `subtitle(_:)`, `icon`; `ShellLayout.settingsRailCollapsed(forWidth:)`, `ShellLayout.settingsPanelSize(forWidth:height:)`, `ShellLayout.settingsRailWidth`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/SettingsSectionTests.swift
import XCTest
@testable import codepet

final class SettingsSectionTests: XCTestCase {
    func test_rawValues_roundTrip_soAChatCardCanDeepLink() {
        for s in SettingsSection.allCases {
            XCTAssertEqual(SettingsSection(rawValue: s.rawValue), s)
        }
    }

    func test_preferencesIsFirst_soTheModalOpensThere() {
        XCTAssertEqual(SettingsSection.allCases.first, .preferences)
    }

    func test_everySectionHasBothLanguages() {
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title(.en).isEmpty)
            XCTAssertFalse(s.title(.vi).isEmpty)
            XCTAssertFalse(s.subtitle(.en).isEmpty)
            XCTAssertNotEqual(s.title(.en), s.title(.vi), "\(s.rawValue) is not translated")
        }
    }

    func test_railCollapsesOnlyOnANarrowShell() {
        XCTAssertTrue(ShellLayout.settingsRailCollapsed(forWidth: 780))
        XCTAssertFalse(ShellLayout.settingsRailCollapsed(forWidth: 820))
        XCTAssertFalse(ShellLayout.settingsRailCollapsed(forWidth: 1400))
    }

    func test_panelSize_insetsFromTheWindowAndCapsOut() {
        // Wide window: capped at the ideal size, not stretched.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 1600, height: 1200),
                       CGSize(width: 920, height: 660))
        // Small window: inset 96pt from each edge.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 800, height: 600),
                       CGSize(width: 704, height: 504))
        // Tiny window: never smaller than the usable floor.
        XCTAssertEqual(ShellLayout.settingsPanelSize(forWidth: 400, height: 300),
                       CGSize(width: 480, height: 400))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/SettingsSectionTests`
Expected: FAIL — "cannot find 'SettingsSection' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// codepet/Models/SettingsSection.swift
import Foundation

/// The account-level surfaces. Formerly the `.settings`, `.billing` and `.support`
/// `AppView` destinations; now sections of one centered modal.
///
/// Settings is an overlay, not a destination: `CompanyStore.settingsSection` is `nil`
/// when closed, so closing it returns the founder to the view they were already on —
/// there is no route to restore. The `String` raw values give chat cards a deep link.
enum SettingsSection: String, CaseIterable, Identifiable {
    case preferences, aiSettings, company, memory,
         notifications, billing, usage, support, advanced

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .preferences:   return lang == .vi ? "Tuỳ chọn" : "Preferences"
        case .aiSettings:    return lang == .vi ? "Cài đặt AI" : "AI Settings"
        case .company:       return lang == .vi ? "Công ty" : "Company"
        case .memory:        return lang == .vi ? "Ghi nhớ" : "Memory"
        case .notifications: return lang == .vi ? "Thông báo" : "Notifications"
        case .billing:       return lang == .vi ? "Thanh toán" : "Billing"
        case .usage:         return lang == .vi ? "Mức dùng" : "Usage"
        case .support:       return lang == .vi ? "Hỗ trợ" : "Support"
        case .advanced:      return lang == .vi ? "Nâng cao" : "Advanced"
        }
    }

    /// The muted line under the panel title.
    func subtitle(_ lang: AppLanguage) -> String {
        switch self {
        case .preferences:
            return lang == .vi ? "Hồ sơ, giao diện và tuỳ chọn tài khoản."
                               : "Manage your profile, appearance, and account preferences."
        case .aiSettings:
            return lang == .vi ? "Cách đội của bạn nói chuyện với bạn."
                               : "How your team talks to you."
        case .company:
            return lang == .vi ? "Bạn đồng hành và hồ sơ công ty."
                               : "Your companion and your company brief."
        case .memory:
            return lang == .vi ? "Những gì đội của bạn ghi nhớ về công ty."
                               : "What your team remembers about your company."
        case .notifications:
            return lang == .vi ? "Chọn khi nào Codepet nhắc bạn."
                               : "Choose when Codepet interrupts you."
        case .billing:
            return lang == .vi ? "Gói và phương thức thanh toán."
                               : "Your plan and payment method."
        case .usage:
            return lang == .vi ? "Mức dùng hôm nay." : "What you've used today."
        case .support:
            return lang == .vi ? "Nhận trợ giúp về Codepet." : "Get help with Codepet."
        case .advanced:
            return lang == .vi ? "Xuất dữ liệu, xoá và đăng xuất."
                               : "Export, delete, and sign out."
        }
    }

    var icon: String {
        switch self {
        case .preferences:   return "slider.horizontal.3"
        case .aiSettings:    return "sparkles"
        case .company:       return "building.2"
        case .memory:        return "brain"
        case .notifications: return "bell"
        case .billing:       return "creditcard"
        case .usage:         return "chart.bar"
        case .support:       return "questionmark.circle"
        case .advanced:      return "gearshape"
        }
    }
}
```

Append to `ShellLayout` (inside the existing `enum ShellLayout`, after `clampDockWidth`):

```swift
    // MARK: - Settings modal

    /// Fixed width of the settings rail. It carries its own "Settings" title and never
    /// scrolls, so the founder can always see where they are.
    static let settingsRailWidth: CGFloat = 220

    /// Below this shell width the rail collapses to a section dropdown above the panel —
    /// the same responsive move the dock makes at `dockExpandMinWidth`.
    static let settingsRailMinWidth: CGFloat = 820

    static func settingsRailCollapsed(forWidth width: CGFloat) -> Bool {
        width < settingsRailMinWidth
    }

    /// The centered panel's size: inset 96pt from each window edge, capped at the ideal
    /// so a fullscreen window does not turn settings into a full-screen sheet, and
    /// floored so a tiny window still shows a usable form.
    static func settingsPanelSize(forWidth w: CGFloat, height h: CGFloat) -> CGSize {
        CGSize(width:  min(920, max(480, w - 96)),
               height: min(660, max(400, h - 96)))
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/SettingsSectionTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/SettingsSection.swift codepet/Models/ShellLayout.swift codepetTests/SettingsSectionTests.swift
git commit -m "feat(settings): SettingsSection + panel/rail layout rules"
```

---

### Task 2: Open/close state on `CompanyStore`

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (add published property near `view` at line 10, and methods near `select(_:)` at line 200)
- Test: `codepetTests/SettingsOpenCloseTests.swift`

**Interfaces:**
- Consumes: `SettingsSection` (Task 1)
- Produces: `CompanyStore.settingsSection: SettingsSection?`, `openSettings(_ section: SettingsSection = .preferences)`, `closeSettings()`, `isSettingsOpen: Bool`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/SettingsOpenCloseTests.swift
import XCTest
@testable import codepet

@MainActor
final class SettingsOpenCloseTests: XCTestCase {
    func test_startsClosed() {
        let store = CompanyStore()
        XCTAssertNil(store.settingsSection)
        XCTAssertFalse(store.isSettingsOpen)
    }

    func test_openDefaultsToPreferences() {
        let store = CompanyStore()
        store.openSettings()
        XCTAssertEqual(store.settingsSection, .preferences)
        XCTAssertTrue(store.isSettingsOpen)
    }

    func test_openOnASpecificSection_forDeepLinks() {
        let store = CompanyStore()
        store.openSettings(.memory)
        XCTAssertEqual(store.settingsSection, .memory)
    }

    func test_closingLeavesTheDestinationAlone() {
        let store = CompanyStore()
        store.select(.tasks)
        store.openSettings(.billing)
        store.closeSettings()
        XCTAssertNil(store.settingsSection)
        XCTAssertEqual(store.view, .tasks, "settings must not navigate")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/SettingsOpenCloseTests`
Expected: FAIL — "value of type 'CompanyStore' has no member 'settingsSection'"

- [ ] **Step 3: Write minimal implementation**

In `CompanyStore.swift`, after `@Published var dockCollapsed: Bool = false` (line 13):

```swift
    /// Which settings section is open, or `nil` when settings is closed. Settings is an
    /// overlay rather than an `AppView`, so opening it never changes `view` and closing
    /// it needs no route to restore.
    @Published var settingsSection: SettingsSection?
```

After `func select(_ view: AppView) { self.view = view }` (line 200):

```swift
    var isSettingsOpen: Bool { settingsSection != nil }

    /// Open settings, optionally on a specific section (chat cards deep-link this way).
    func openSettings(_ section: SettingsSection = .preferences) {
        settingsSection = section
    }

    func closeSettings() { settingsSection = nil }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/SettingsOpenCloseTests`
Expected: PASS, 4 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/SettingsOpenCloseTests.swift
git commit -m "feat(settings): open/close state as an overlay, not a destination"
```

---

### Task 3: `SettingsChrome` — the shared row vocabulary

**Files:**
- Create: `codepet/Views/Settings/SettingsChrome.swift`

**Interfaces:**
- Consumes: `CodepetTheme`
- Produces: `SettingsPanelHeader(title:subtitle:)`, `SettingsGroup { }`, `SettingsRow(label:description:control:)`, `SettingsGroupLabel(_:)`, `SettingsDestructiveRow(label:description:actionTitle:action:)`

This task has no test of its own — it is pure presentation with no logic, and Task 4 exercises it on screen. Do not invent a snapshot-test harness for it; the codebase has none.

- [ ] **Step 1: Write the chrome**

```swift
// codepet/Views/Settings/SettingsChrome.swift
import SwiftUI

/// The settings modal's row vocabulary, defined once so nine panels cannot drift.
///
/// Every row is: label + optional description + exactly ONE right-aligned control.
/// A dropdown for three or more options, a toggle for binary, a button for an action.
/// Inter throughout — the pixel font belongs to the logo, sprites and game chrome.

/// Panel title + the muted line under it.
struct SettingsPanelHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CodepetTheme.inter(22, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(subtitle)
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small uppercase-free group caption above a card ("Profile", "Appearance").
struct SettingsGroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(CodepetTheme.inter(13, weight: .medium))
            .foregroundColor(CodepetTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A bordered card holding rows. Rows separate themselves with `SettingsDivider()`.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius)
                    .fill(CodepetTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius)
                    .stroke(CodepetTheme.hairline, lineWidth: 1)
            )
    }
}

/// label + optional description on the left, one control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var description: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                if let description {
                    Text(description)
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 12)
    }
}

/// A row whose action is destructive: `accentOrange` label on the button, never a red
/// literal, and the caller owns confirmation.
struct SettingsDestructiveRow: View {
    let label: String
    var description: String? = nil
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SettingsRow(label: label, description: description) {
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentOrange)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Settings/SettingsChrome.swift
git commit -m "feat(settings): shared row vocabulary for the modal"
```

---

### Task 4: `SettingsRail` + `SettingsModal`, mounted with one live panel

**Files:**
- Create: `codepet/Views/Settings/SettingsRail.swift`
- Create: `codepet/Views/Settings/SettingsModal.swift`
- Create: `codepet/Views/Settings/PreferencesPanel.swift`
- Modify: `codepet/Views/Shell/AppShellView.swift` (add the overlay to the outermost view)
- Modify: `codepet/App/CodePetApp.swift` (⌘, menu command)
- Modify: `codepet/Views/Shell/AccountMenuView.swift:61` (Settings row opens the modal)

**Interfaces:**
- Consumes: `SettingsSection`, `ShellLayout.settingsPanelSize(forWidth:height:)`, `ShellLayout.settingsRailCollapsed(forWidth:)`, `ShellLayout.settingsRailWidth`, `CompanyStore.settingsSection` / `closeSettings()` / `openSettings(_:)`, `SettingsChrome` types
- Produces: `SettingsModal()`, `SettingsRail(selection:)`, `PreferencesPanel()`

Panels other than Preferences render a one-line "coming in the next task" placeholder **only within this task**; Tasks 5, 6, 8, 10, 11, 12 replace each one. Do not ship Phase 1 with placeholders remaining — Task 6 removes the last of them.

- [ ] **Step 1: Write the rail**

```swift
// codepet/Views/Settings/SettingsRail.swift
import SwiftUI

/// The modal's fixed 220pt nav column. Carries its own "Settings" title and never
/// scrolls, so the founder always sees where they are.
struct SettingsRail: View {
    @Binding var selection: SettingsSection
    @EnvironmentObject var appState: AppState
    private var lang: AppLanguage { appState.uiLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lang == .vi ? "Cài đặt" : "Settings")
                .font(CodepetTheme.inter(14, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(section.title(lang))
                            .font(CodepetTheme.inter(13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(selection == section
                                     ? CodepetTheme.primaryText
                                     : CodepetTheme.bodyText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == section
                                  ? CodepetTheme.hairline
                                  : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: ShellLayout.settingsRailWidth, alignment: .leading)
    }
}
```

- [ ] **Step 2: Write the modal**

```swift
// codepet/Views/Settings/SettingsModal.swift
import SwiftUI

/// The centered settings modal: scrim + panel, rail on the left, scrolling panel on the
/// right. Deliberately NOT a `.sheet` — a macOS sheet is window-attached and descends
/// from the titlebar, so it cannot be centered.
struct SettingsModal: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    private var lang: AppLanguage { appState.uiLanguage }

    /// Mirrors `companyStore.settingsSection` while open. The modal is only built when
    /// that value is non-nil, so the initial value is never used blind.
    @State private var selection: SettingsSection

    init(initial: SettingsSection) { _selection = State(initialValue: initial) }

    var body: some View {
        GeometryReader { geo in
            let size = ShellLayout.settingsPanelSize(forWidth: geo.size.width,
                                                     height: geo.size.height)
            let railCollapsed = ShellLayout.settingsRailCollapsed(forWidth: geo.size.width)

            ZStack {
                // Scrim: dismisses on click.
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { companyStore.closeSettings() }

                panel(railCollapsed: railCollapsed)
                    .frame(width: size.width, height: size.height)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(CodepetTheme.pageBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(CodepetTheme.hairline, lineWidth: 1)
                    )
                    .shadow(color: CodepetTheme.floatingShadow.color,
                            radius: CodepetTheme.floatingShadow.radius,
                            x: CodepetTheme.floatingShadow.x,
                            y: CodepetTheme.floatingShadow.y)
            }
        }
        // Escape closes.
        .onExitCommand { companyStore.closeSettings() }
    }

    @ViewBuilder private func panel(railCollapsed: Bool) -> some View {
        HStack(spacing: 0) {
            if !railCollapsed {
                SettingsRail(selection: $selection)
                SettingsDivider()
            }
            VStack(spacing: 0) {
                header(railCollapsed: railCollapsed)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SettingsPanelHeader(title: selection.title(lang),
                                            subtitle: selection.subtitle(lang))
                        body(for: selection)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    /// Close button, plus the section dropdown that replaces the rail on a narrow window.
    @ViewBuilder private func header(railCollapsed: Bool) -> some View {
        HStack {
            if railCollapsed {
                Picker("", selection: $selection) {
                    ForEach(SettingsSection.allCases) { s in
                        Text(s.title(lang)).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Spacer()
            Button { companyStore.closeSettings() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Đóng" : "Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func body(for section: SettingsSection) -> some View {
        switch section {
        case .preferences: PreferencesPanel()
        default:
            // Replaced by Tasks 5, 6, 8, 10, 11 and 12. Phase 1 does not ship with any
            // of these remaining.
            Text(lang == .vi ? "Đang chuyển sang cửa sổ này." : "Moving into this window.")
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}
```

- [ ] **Step 3: Write the Preferences panel**

```swift
// codepet/Views/Settings/PreferencesPanel.swift
import SwiftUI

/// Profile, appearance and language. This pass MOVES the controls; theme and language
/// keep their existing homes on `AppState`.
struct PreferencesPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var authManager: AuthManager
    private var lang: AppLanguage { appState.uiLanguage }

    /// Same source `AccountMenuView` reads, so the avatar initial and greeting follow it.
    private var founderName: String {
        let n = companyStore.company.brief.founderName ?? ""
        return n.isEmpty ? (lang == .vi ? "Bạn" : "You") : n
    }
    private var email: String? { authManager.currentUser?.email }

    @State private var draftName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupLabel(lang == .vi ? "Hồ sơ" : "Profile")
            SettingsGroup {
                HStack(spacing: 12) {
                    Text(String(founderName.prefix(1)).uppercased())
                        .font(CodepetTheme.inter(16, weight: .semibold))
                        .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(CodepetTheme.accentPurple))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)

                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Tên gọi" : "Preferred Name") {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(CodepetTheme.inter(13))
                        .frame(width: 220)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                            .fill(CodepetTheme.hairline.opacity(0.5)))
                        .onSubmit { commitName() }
                }
                SettingsDivider()
                SettingsRow(label: "Email") {
                    Text(email ?? "—")
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }

            SettingsGroupLabel(lang == .vi ? "Giao diện" : "Appearance")
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Chủ đề" : "Theme") {
                    Picker("", selection: $appState.appTheme) {
                        Text(lang == .vi ? "Sáng" : "Light").tag(AppTheme.light)
                        Text(lang == .vi ? "Tự động" : "System").tag(AppTheme.system)
                        Text(lang == .vi ? "Tối" : "Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Ngôn ngữ" : "Language") {
                    Picker("", selection: $appState.uiLanguage) {
                        Text("English").tag(AppLanguage.en)
                        Text("Tiếng Việt").tag(AppLanguage.vi)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
        }
        .onAppear { draftName = companyStore.company.brief.founderName ?? "" }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await companyStore.setFounderName(trimmed) }
    }
}
```

`setFounderName(_:)` does not exist yet. Add it to `CompanyStore.swift` beside `setCompanion(id:)` (line 1435), following the same injected-saver idiom:

```swift
    /// Persist the founder's preferred name onto the brief. Fail-soft: a lost write only
    /// means the old name comes back on reload, never a broken page.
    func setFounderName(_ name: String) async {
        company.brief.founderName = name
        if let cid = companyId { _ = await briefSaver(cid, company.brief) }
    }
```

If `briefSaver` is not already an injected dependency on `CompanyStore`, use the existing brief-save path `CompanyOnboardingView`'s `onDone` triggers — grep `func saveBrief` / `briefSaver` / `setBrief` in `CompanyStore.swift` and call that one rather than adding a second write path for the same field.

- [ ] **Step 4: Mount it in the shell**

In `AppShellView.swift`, wrap the outermost body view (the one currently returned by `body`) so the modal overlays everything including the top nav:

```swift
        .overlay {
            if let section = companyStore.settingsSection {
                SettingsModal(initial: section)
                    .transition(.opacity)
            }
        }
```

In `CodePetApp.swift`, inside the `WindowGroup`'s `.commands { … }` (add a `.commands` block if none exists):

```swift
            // ⌘, is the macOS convention and lands in the app menu for free. As a menu
            // command it routes regardless of which field has focus, and typing an
            // unmodified comma in the composer is unaffected.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    // Guarded so the panel does not pop open the instant onboarding ends.
                    guard !companyStore.isOnboarding else { return }
                    companyStore.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
```

In `AccountMenuView.swift`, replace line 61:

```swift
            menuRow(lang == .vi ? "Cài đặt" : "Settings") { companyStore.openSettings() }
```

- [ ] **Step 5: Run the app and look at it**

```bash
pgrep -f 'codepet.app/Contents/MacOS/codepet' | xargs -r kill
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" 2>&1 | tail -3
codesign -dv "$(xcodebuild -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/codepet.app" 2>&1 | grep TeamIdentifier
open "$(xcodebuild -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/codepet.app"
```

Expected: `** BUILD SUCCEEDED **`, `TeamIdentifier=YL72VTKBR7`, and pressing ⌘, opens a centered panel with a 220pt rail and the Preferences form. Escape and a scrim click both close it. **A screenshot cannot be captured from this session — hand this check to the founder and ask one specific question.**

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Settings codepet/Views/Shell/AppShellView.swift codepet/Views/Shell/AccountMenuView.swift codepet/App/CodePetApp.swift codepet/Managers/CompanyStore.swift
git commit -m "feat(settings): centered modal with rail, Preferences panel, cmd-comma"
```

---

### Task 5: Company panel — the companion row

**Files:**
- Create: `codepet/Views/Settings/CompanyPanel.swift`
- Modify: `codepet/Views/Settings/SettingsModal.swift` (`case .company:` arm)
- Test: `codepetTests/CompanionRowTests.swift`

**Interfaces:**
- Consumes: `SettingsRow`, `SettingsGroup`, `companyStore.company.companionId`, `companyStore.setCompanion(id:)`, `companions` (existing catalogue), `CharacterImage`
- Produces: `CompanyPanel()`, `CompanionRowModel.summary(companionId:lang:)`

The picker is a drill-in, not a strip: one row showing the current companion, disclosing the full list.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanionRowTests.swift
import XCTest
@testable import codepet

final class CompanionRowTests: XCTestCase {
    func test_summaryNamesTheCurrentCompanion() {
        XCTAssertEqual(CompanionRowModel.summary(companionId: "crash", lang: .en), "Crash")
    }

    func test_unknownIdFallsBackRatherThanShowingRaw() {
        XCTAssertEqual(CompanionRowModel.summary(companionId: "nope", lang: .en), "Default")
        XCTAssertEqual(CompanionRowModel.summary(companionId: "", lang: .vi), "Mặc định")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CompanionRowTests`
Expected: FAIL — "cannot find 'CompanionRowModel' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// codepet/Views/Settings/CompanyPanel.swift
import SwiftUI

/// Pure naming for the companion row, so the fallback is testable without a view.
enum CompanionRowModel {
    /// Canonical narrative order (`PetCharacter.starters`), the order every other Codepet
    /// surface uses — NOT alphabetical by id. The deleted `SettingsView` sorted by id,
    /// which put crash and glitch before nova; founder's call, Aug 4. Any id present in
    /// the catalogue but absent from `starters` is appended rather than silently dropped.
    static var all: [PetCharacter] {
        let canonical = PetCharacter.starters.compactMap { PetCharacter.all[$0] }
        let extras = PetCharacter.all.values
            .filter { !PetCharacter.starters.contains($0.id) }
            .sorted { $0.id < $1.id }
        return canonical + extras
    }

    static func summary(companionId: String, lang: AppLanguage) -> String {
        if let c = PetCharacter.all[companionId] { return c.name }
        return lang == .vi ? "Mặc định" : "Default"
    }
}

/// Companion choice and the company brief.
struct CompanyPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    private var lang: AppLanguage { appState.uiLanguage }

    @State private var pickingCompanion = false
    @State private var editingBrief = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: CompanionRowModel.summary(
                        companionId: companyStore.company.companionId, lang: lang),
                    description: lang == .vi
                        ? "Chọn bạn đồng hành làm việc cùng bạn."
                        : "Choose a companion that works alongside you."
                ) {
                    Button {
                        pickingCompanion = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang == .vi ? "Chọn" : "Select")
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Hồ sơ công ty" : "Company brief") {
                    Button(lang == .vi ? "Chỉnh sửa" : "Edit") { editingBrief = true }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
            }

            if pickingCompanion { companionList }
        }
        .sheet(isPresented: $editingBrief) {
            // The same editor the deleted SettingsView opened — not a second brief form.
            CompanyOnboardingView(prefillBrief: companyStore.company.brief,
                                  onDone: { editingBrief = false })
        }
    }

    private var companionList: some View {
        SettingsGroup {
            ForEach(Array(CompanionRowModel.all.enumerated()), id: \.element.id) { idx, c in
                if idx > 0 { SettingsDivider() }
                Button {
                    Task { await companyStore.setCompanion(id: c.id) }
                    appState.activeChar = c.id
                    pickingCompanion = false
                } label: {
                    SettingsRow(label: c.name) {
                        if companyStore.company.companionId == c.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(c.color)
                        } else {
                            CharacterImage(c.id, size: 24)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

In `SettingsModal.swift`, add above `default:`:

```swift
        case .company: CompanyPanel()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CompanionRowTests`
Expected: PASS, 2 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Settings/CompanyPanel.swift codepet/Views/Settings/SettingsModal.swift codepetTests/CompanionRowTests.swift
git commit -m "feat(settings): Company panel — companion as a drill-in row"
```

---

### Task 6: Migrate Billing, Usage, Support, Advanced and delete the three destinations

**Files:**
- Create: `codepet/Views/Settings/BillingPanel.swift`, `UsagePanel.swift`, `SupportPanel.swift`, `AdvancedPanel.swift`
- Modify: `codepet/Views/Settings/SettingsModal.swift` (four arms; `default:` disappears)
- Modify: `codepet/Models/AppView.swift` (remove three cases + their `title`/`icon` arms)
- Modify: `codepet/Models/ShellLayout.swift:54` (`showsCopilot` case list)
- Modify: `codepet/Views/Shell/AppShellView.swift:150-155` (remove three branches)
- Modify: `codepet/Views/Shell/AccountMenuView.swift:62-63` (delete two rows)
- Modify: `codepet/Views/Shell/TopNavView.swift:65` (Upgrade pill opens `.billing`)
- Delete: `codepet/Views/Settings/SettingsView.swift`
- Modify: `codepetTests/ShellLayoutTests.swift:70`
- Test: `codepetTests/AppViewMigrationTests.swift`

**Interfaces:**
- Consumes: existing `BillingView`, `SupportView` bodies (lift their content into panels), `SettingsChrome`
- Produces: `BillingPanel()`, `UsagePanel()`, `SupportPanel()`, `AdvancedPanel()`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/AppViewMigrationTests.swift
import XCTest
@testable import codepet

final class AppViewMigrationTests: XCTestCase {
    func test_accountLevelSurfacesAreNoLongerDestinations() {
        let raws = AppView.allCases.map(\.rawValue)
        XCTAssertFalse(raws.contains("settings"))
        XCTAssertFalse(raws.contains("billing"))
        XCTAssertFalse(raws.contains("support"))
    }

    func test_copilotStillHidesOnEveryNonOverviewDestination() {
        for v in [AppView.company, .tasks, .library, .environment] {
            XCTAssertFalse(ShellLayout.showsCopilot(in: v), "\(v.rawValue)")
        }
        XCTAssertTrue(ShellLayout.showsCopilot(in: .roadmap))
    }

    func test_navDestinationsStillResolve() {
        XCTAssertEqual(AppView.from(navDestination: "roadmap"), .roadmap)
        XCTAssertEqual(AppView.from(navDestination: "department"), .company)
        XCTAssertNil(AppView.from(navDestination: "settings"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/AppViewMigrationTests`
Expected: FAIL — `test_accountLevelSurfacesAreNoLongerDestinations` fails because the three cases still exist

- [ ] **Step 3: Write the four panels**

```swift
// codepet/Views/Settings/BillingPanel.swift
import SwiftUI

/// Plan and payment. Content lifted from `BillingView` — plan name, one-line value prop,
/// and the compare action.
struct BillingPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    private var lang: AppLanguage { appState.uiLanguage }

    var body: some View {
        SettingsGroup {
            SettingsRow(
                label: lang == .vi ? "Codepet Miễn phí" : "Codepet Free",
                description: lang == .vi ? "Đủ dùng cho việc hằng ngày."
                                         : "Enough for everyday building."
            ) {
                Button(lang == .vi ? "So sánh gói" : "Compare plans") {
                    // Keep the existing upgrade destination BillingView used.
                    appState.showUpgrade = true
                }
                .buttonStyle(.plain)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentPurple)
            }
        }
    }
}
```

If `appState.showUpgrade` does not exist, grep `BillingView.swift` for whatever it invokes on "Upgrade" and call that instead. Do not invent a new upgrade path.

```swift
// codepet/Views/Settings/UsagePanel.swift
import SwiftUI

/// Today's usage against the per-account daily cap. Reuses the meter grammar the spec
/// borrowed from ChatGPT's storage panel — with real content, since Codepet stores
/// almost nothing per user but does meter runs.
struct UsagePanel: View {
    @EnvironmentObject var appState: AppState
    private var lang: AppLanguage { appState.uiLanguage }

    /// The daily cap enforced server-side. Keep this constant in sync with the
    /// functions-side limit; it is display only.
    private let dailyCap = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(appState.runsUsedToday) / \(dailyCap) \(lang == .vi ? "lượt hôm nay" : "runs today")")
                .font(CodepetTheme.inter(13, weight: .medium))
                .foregroundColor(CodepetTheme.primaryText)
            GeometryReader { geo in
                let frac = min(1, Double(appState.runsUsedToday) / Double(dailyCap))
                ZStack(alignment: .leading) {
                    Capsule().fill(CodepetTheme.hairline)
                    Capsule().fill(CodepetTheme.accentPurple)
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
            Text(lang == .vi ? "Giới hạn đặt lại vào nửa đêm."
                             : "The limit resets at midnight.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}
```

If `appState.runsUsedToday` does not exist, add it as a plain `@Published var runsUsedToday: Int = 0` on `AppState` incremented wherever the run path already counts against the cap — grep for the daily-cap check. If no client-side counter exists at all, show the cap and the reset line without a bar, and record the gap in the commit message rather than inventing a number.

```swift
// codepet/Views/Settings/SupportPanel.swift
import SwiftUI

/// Help links, lifted from `SupportView`.
struct SupportPanel: View {
    @EnvironmentObject var appState: AppState
    private var lang: AppLanguage { appState.uiLanguage }

    var body: some View {
        SettingsGroup {
            SettingsRow(label: lang == .vi ? "Gửi phản hồi" : "Send feedback") {
                Link(destination: URL(string: "mailto:hello@murror.app")!) {
                    Text("hello@murror.app")
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
            }
        }
    }
}
```

Replace that row set with whatever `SupportView.swift` actually contains — read it first and move its rows over verbatim rather than reducing support to one mailto.

```swift
// codepet/Views/Settings/AdvancedPanel.swift
import SwiftUI

/// Data controls and sign-out. Every destructive action confirms first.
struct AdvancedPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    private var lang: AppLanguage { appState.uiLanguage }

    @State private var confirmSignOut = false
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsDestructiveRow(
                    label: lang == .vi ? "Đăng xuất" : "Sign out",
                    actionTitle: lang == .vi ? "Đăng xuất" : "Sign out"
                ) { confirmSignOut = true }
            }
            SettingsGroup {
                SettingsRow(label: "Codepet") {
                    Text("v\(appVersion)")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
        .confirmationDialog(
            lang == .vi ? "Đăng xuất khỏi Codepet?" : "Sign out of Codepet?",
            isPresented: $confirmSignOut
        ) {
            Button(lang == .vi ? "Đăng xuất" : "Sign out", role: .destructive) {
                authManager.signOut()
            }
            Button(lang == .vi ? "Huỷ" : "Cancel", role: .cancel) { }
        }
    }
}
```

Export data and Delete all chats are **not** in this task. They need real Firestore work and land in their own task after Phase 2 — shipping a button that does nothing would be worse than not shipping it. Record that in the commit message.

- [ ] **Step 4: Delete the destinations**

`AppView.swift` — remove `settings, billing, support` from the case list and delete their `title(_:)` and `icon` arms.

`ShellLayout.swift:54`:

```swift
        case .company, .tasks, .library, .environment: return false
```

`AppShellView.swift` — delete the three `else if companyStore.view == …` branches (lines 150-155).

`AccountMenuView.swift` — delete the `Billing & Usage` and `Support` rows (62-63).

`TopNavView.swift:65`:

```swift
        Button { companyStore.openSettings(.billing) } label: {
```

`ShellLayoutTests.swift:70`:

```swift
        for v in [AppView.company, .tasks, .library, .environment] {
```

`SettingsModal.swift` — replace `default:` with the four real arms, leaving no `default:`:

```swift
        case .billing: BillingPanel()
        case .usage:   UsagePanel()
        case .support: SupportPanel()
        case .advanced: AdvancedPanel()
        case .aiSettings, .memory, .notifications:
            // Tasks 8, 10 and 11.
            Text(lang == .vi ? "Sắp có." : "Coming next.")
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
```

Delete `codepet/Views/Settings/SettingsView.swift`, then `grep -rn 'SettingsView\|BillingView()\|SupportView()' codepet` and clear every remaining reference.

- [ ] **Step 5: Run the full suite**

```bash
pgrep -f 'codepet.app/Contents/MacOS/codepet' | xargs -r kill
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`. If you see `** TEST FAILED **` with no `Failing tests:` list, whole suites never ran — the app was holding the Firestore lock. Kill it and re-run, and confirm the executed-test count matches the previous run.

- [ ] **Step 6: Commit**

```bash
git add -A codepet codepetTests
git commit -m "feat(settings): migrate Billing/Usage/Support/Advanced, drop three destinations"
```

---

# Phase 2 — tone, memory, notifications

### Task 7: `AIStyle` and `promptFragment()`

**Files:**
- Create: `codepet/Models/FounderPrefs.swift`
- Test: `codepetTests/AIStyleTests.swift`

**Interfaces:**
- Produces: `FounderPrefs` (`style: AIStyle`, `memoryEnabled: Bool`, `notifications: [String: NotificationChannel]`), `AIStyle` (`baseTone: AIStyle.BaseTone`, `warmth/enthusiasm/emoji: AIStyle.Level`, `customInstructions/role/moreAboutYou: String`, `promptFragment() -> String?`), `NotificationChannel`

`promptFragment()` returning `nil` at all-defaults is the property that keeps an untouched panel from adding tokens to every request. Test it first.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/AIStyleTests.swift
import XCTest
@testable import codepet

final class AIStyleTests: XCTestCase {
    func test_untouchedStyleAddsNothingToThePrompt() {
        XCTAssertNil(AIStyle().promptFragment())
    }

    func test_baseToneEmitsOneLine() {
        var s = AIStyle(); s.baseTone = .direct
        let f = s.promptFragment()
        XCTAssertNotNil(f)
        XCTAssertTrue(f!.contains("blunt"), f!)
    }

    func test_eachLevelEmitsItsOwnDirection() {
        var warmer = AIStyle(); warmer.warmth = .more
        var cooler = AIStyle(); cooler.warmth = .less
        XCTAssertNotEqual(warmer.promptFragment(), cooler.promptFragment())
        XCTAssertNotNil(warmer.promptFragment())
        XCTAssertNotNil(cooler.promptFragment())
    }

    func test_emojiMoreOverridesTheHardcodedProhibition() {
        var s = AIStyle(); s.emoji = .more
        XCTAssertTrue(s.promptFragment()!.lowercased().contains("emoji"))
    }

    func test_customInstructionsComeLastSoTheyWin() {
        var s = AIStyle()
        s.warmth = .more
        s.customInstructions = "Always name the file path."
        let f = s.promptFragment()!
        XCTAssertTrue(f.hasSuffix("Always name the file path."), f)
    }

    func test_blankTextIsNotAFragment() {
        var s = AIStyle(); s.customInstructions = "   \n "
        XCTAssertNil(s.promptFragment())
    }

    func test_aboutYouTravelsWithTheStyle() {
        var s = AIStyle(); s.role = "solo founder"; s.moreAboutYou = "ships on weekends"
        let f = s.promptFragment()!
        XCTAssertTrue(f.contains("solo founder"))
        XCTAssertTrue(f.contains("ships on weekends"))
    }

    func test_roundTripsThroughJSON() throws {
        var p = FounderPrefs()
        p.style.baseTone = .analytical
        p.memoryEnabled = false
        p.notifications["sessionNudges"] = .off
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(FounderPrefs.self, from: data), p)
    }

    func test_defaultsAreTheOldBehaviour() {
        let p = FounderPrefs()
        XCTAssertTrue(p.memoryEnabled)
        XCTAssertNil(p.style.promptFragment())
        XCTAssertTrue(p.notifications.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/AIStyleTests`
Expected: FAIL — "cannot find 'AIStyle' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// codepet/Models/FounderPrefs.swift
import Foundation

enum NotificationChannel: String, Codable, CaseIterable {
    case off, inApp
}

/// Everything the founder sets in the settings modal that the model or the notification
/// layer needs to see. Persisted as one field on the company doc so it syncs across
/// machines instead of living in UserDefaults.
struct FounderPrefs: Codable, Equatable {
    var style: AIStyle = .init()
    var memoryEnabled: Bool = true
    /// Category key -> channel. An absent key means that category's default.
    var notifications: [String: NotificationChannel] = [:]
}

/// How the founder's team talks to them.
///
/// `promptFragment()` is the entire behavioural seam. It returns `nil` when nothing has
/// been changed, so an untouched settings panel adds zero tokens to every request — the
/// property that makes this safe to ship.
struct AIStyle: Codable, Equatable {
    enum Level: String, Codable, CaseIterable { case less, `default`, more }
    enum BaseTone: String, Codable, CaseIterable {
        case `default`, direct, encouraging, analytical
    }

    var baseTone: BaseTone = .default
    var warmth: Level = .default
    var enthusiasm: Level = .default
    var emoji: Level = .default
    var customInstructions: String = ""
    var role: String = ""
    var moreAboutYou: String = ""

    /// nil when every knob is `.default` and every string is blank.
    func promptFragment() -> String? {
        var lines: [String] = []

        switch baseTone {
        case .default: break
        case .direct:
            lines.append("Be blunt and economical. Lead with the answer, skip the preamble.")
        case .encouraging:
            lines.append("Be encouraging. Name what the founder got right before what to fix.")
        case .analytical:
            lines.append("Be analytical. Show the reasoning and the trade-offs behind advice.")
        }

        switch warmth {
        case .default: break
        case .more: lines.append("Warmer than usual: acknowledge how the work is going.")
        case .less: lines.append("Cooler than usual: no pleasantries, no check-ins.")
        }

        switch enthusiasm {
        case .default: break
        case .more: lines.append("Show more enthusiasm when something is working.")
        case .less: lines.append("Stay level. No exclamation marks, no celebration.")
        }

        switch emoji {
        case .default: break
        // Overrides the "No emoji" clause in the base system prompt.
        case .more: lines.append("A single relevant emoji per reply is welcome.")
        case .less: lines.append("Never use emoji.")
        }

        let r = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { lines.append("The founder describes their role as: \(r).") }

        let more = moreAboutYou.trimmingCharacters(in: .whitespacesAndNewlines)
        if !more.isEmpty { lines.append("Keep in mind about the founder: \(more).") }

        // Last, so an explicit instruction wins over the knobs above it.
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { lines.append(custom) }

        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/AIStyleTests`
Expected: PASS, 9 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/FounderPrefs.swift codepetTests/AIStyleTests.swift
git commit -m "feat(prefs): AIStyle + FounderPrefs with a nil-at-defaults prompt fragment"
```

---

### Task 8: Persist `FounderPrefs` on the company doc

**Files:**
- Modify: `codepet/Models/CompanyState.swift` (add the field beside `companionId`, line 22)
- Modify: `codepet/Managers/CompanyStore.swift` (saver dependency at 116-117 / 173-174 / 192-193, mutation beside `setCompanion` at 1435)
- Modify: `codepet/Services/CloudSyncService.swift` or whichever file holds `CompanyData.saveCompanionId` — add `saveFounderPrefs`
- Test: `codepetTests/FounderPrefsPersistenceTests.swift`

**Interfaces:**
- Consumes: `FounderPrefs` (Task 7)
- Produces: `CompanyState.founderPrefs: FounderPrefs`, `CompanyStore.setFounderPrefs(_:) async`, `CompanyData.saveFounderPrefs(_:_:) async -> Bool`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/FounderPrefsPersistenceTests.swift
import XCTest
@testable import codepet

@MainActor
final class FounderPrefsPersistenceTests: XCTestCase {
    func test_setFounderPrefs_updatesStateAndWritesOnce() async {
        var written: [FounderPrefs] = []
        let store = CompanyStore(founderPrefsSaver: { _, prefs in
            written.append(prefs); return true
        })
        var prefs = FounderPrefs()
        prefs.style.baseTone = .direct
        await store.setFounderPrefs(prefs)

        XCTAssertEqual(store.company.founderPrefs.style.baseTone, .direct)
        XCTAssertEqual(written.count, 1)
    }

    func test_defaultPrefsSurviveDecodingACompanyWithoutTheField() throws {
        // Existing company docs predate founderPrefs; decoding must not throw.
        let json = #"{"brief":{},"departments":[],"companionId":"crash","tasks":[],"enabledTools":[]}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertEqual(state.founderPrefs, FounderPrefs())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/FounderPrefsPersistenceTests`
Expected: FAIL — no `founderPrefsSaver` argument, no `founderPrefs` member

- [ ] **Step 3: Write minimal implementation**

`CompanyState.swift`, after `var companionId: String` (line 22):

```swift
    /// Settings the founder chose in the settings modal. Defaulted, because every company
    /// doc written before this field existed decodes without it.
    var founderPrefs: FounderPrefs = .init()
```

If `CompanyState`'s `Codable` conformance is hand-written (explicit `init(from:)`), decode this key with `decodeIfPresent(_:forKey:) ?? .init()`. If it is synthesised, the default above is enough — verify by running the second test.

`CompanyStore.swift` — add beside the other savers:

```swift
    // line ~118
    private let founderPrefsSaver: (String, FounderPrefs) async -> Bool

    // line ~175, in init's parameter list
         founderPrefsSaver: @escaping (String, FounderPrefs) async -> Bool = CompanyData.saveFounderPrefs,

    // line ~194, in init's body
        self.founderPrefsSaver = founderPrefsSaver
```

And the mutation, beside `setCompanion(id:)`:

```swift
    /// Persist the founder's settings. Fail-soft, like `setCompanion`: a lost write only
    /// means the previous preferences come back on reload.
    func setFounderPrefs(_ prefs: FounderPrefs) async {
        company.founderPrefs = prefs
        if let cid = companyId { _ = await founderPrefsSaver(cid, prefs) }
    }
```

In the file that defines `CompanyData.saveCompanionId`, add the sibling writer following that function's exact shape (same collection, same merge semantics, same error swallowing):

```swift
    static func saveFounderPrefs(_ companyId: String, _ prefs: FounderPrefs) async -> Bool {
        await merge(companyId, ["founderPrefs": prefs.firestoreValue])
    }
```

Match whatever helper `saveCompanionId` uses instead of inventing `merge`/`firestoreValue`; read that function and mirror it.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/FounderPrefsPersistenceTests`
Expected: PASS, 2 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/CompanyState.swift codepet/Managers/CompanyStore.swift codepet/Services codepetTests/FounderPrefsPersistenceTests.swift
git commit -m "feat(prefs): persist FounderPrefs on the company doc"
```

---

### Task 9: AI Settings panel

**Files:**
- Create: `codepet/Views/Settings/AISettingsPanel.swift`
- Modify: `codepet/Views/Settings/SettingsModal.swift` (`case .aiSettings:`)

**Interfaces:**
- Consumes: `AIStyle`, `FounderPrefs`, `CompanyStore.setFounderPrefs(_:)`, `SettingsChrome`
- Produces: `AISettingsPanel()`

Four dropdowns, two text fields. **No "Headers & Lists" knob** — `companyChatCore.ts:71` tells the companion to write plain text because the transcript has no markdown renderer, so a structure setting would print literal asterisks.

- [ ] **Step 1: Write the panel**

```swift
// codepet/Views/Settings/AISettingsPanel.swift
import SwiftUI

/// How the founder's team talks to them. Edits are held locally and committed on change,
/// so each dropdown is one Firestore write rather than one per keystroke.
struct AISettingsPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    private var lang: AppLanguage { appState.uiLanguage }

    @State private var style = AIStyle()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Giọng điệu cơ bản" : "Base style and tone",
                    description: lang == .vi
                        ? "Cách đội của bạn trả lời. Không ảnh hưởng khả năng."
                        : "How your team answers. Doesn't change what they can do."
                ) {
                    Picker("", selection: $style.baseTone) {
                        Text(lang == .vi ? "Mặc định" : "Default").tag(AIStyle.BaseTone.default)
                        Text(lang == .vi ? "Thẳng thắn" : "Direct").tag(AIStyle.BaseTone.direct)
                        Text(lang == .vi ? "Động viên" : "Encouraging").tag(AIStyle.BaseTone.encouraging)
                        Text(lang == .vi ? "Phân tích" : "Analytical").tag(AIStyle.BaseTone.analytical)
                    }
                    .labelsHidden().frame(width: 160)
                }
            }

            SettingsGroupLabel(lang == .vi ? "Đặc điểm" : "Characteristics")
            SettingsGroup {
                levelRow(lang == .vi ? "Ấm áp" : "Warm", $style.warmth)
                SettingsDivider()
                levelRow(lang == .vi ? "Nhiệt tình" : "Enthusiastic", $style.enthusiasm)
                SettingsDivider()
                levelRow("Emoji", $style.emoji)
            }

            SettingsGroupLabel(lang == .vi ? "Về bạn" : "About you")
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Vai trò" : "Role") {
                    field($style.role, placeholder: lang == .vi ? "nhà sáng lập" : "solo founder")
                }
                SettingsDivider()
                SettingsRow(
                    label: lang == .vi ? "Thêm về bạn" : "More about you",
                    description: lang == .vi ? "Sở thích, giá trị, điều cần nhớ."
                                             : "Interests, values, or preferences to keep in mind."
                ) {
                    field($style.moreAboutYou, placeholder: "")
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Hướng dẫn riêng" : "Custom instructions") {
                    field($style.customInstructions,
                          placeholder: lang == .vi ? "Hành vi, phong cách…"
                                                   : "Additional behavior, style, and tone")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            style = companyStore.company.founderPrefs.style
            loaded = true
        }
        .onChange(of: style) { _ in commit() }
    }

    @ViewBuilder private func levelRow(_ label: String, _ binding: Binding<AIStyle.Level>) -> some View {
        SettingsRow(label: label) {
            Picker("", selection: binding) {
                Text(lang == .vi ? "Ít hơn" : "Less").tag(AIStyle.Level.less)
                Text(lang == .vi ? "Mặc định" : "Default").tag(AIStyle.Level.default)
                Text(lang == .vi ? "Nhiều hơn" : "More").tag(AIStyle.Level.more)
            }
            .labelsHidden().frame(width: 130)
        }
    }

    @ViewBuilder private func field(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(CodepetTheme.inter(12))
            .frame(width: 240)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                .fill(CodepetTheme.hairline.opacity(0.5)))
    }

    private func commit() {
        guard loaded else { return }
        var prefs = companyStore.company.founderPrefs
        prefs.style = style
        Task { await companyStore.setFounderPrefs(prefs) }
    }
}
```

In `SettingsModal.swift`, replace `.aiSettings` in the placeholder arm with:

```swift
        case .aiSettings: AISettingsPanel()
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Settings/AISettingsPanel.swift codepet/Views/Settings/SettingsModal.swift
git commit -m "feat(settings): AI Settings panel wired to FounderPrefs"
```

---

### Task 10: Carry the style into the system prompt

**Files:**
- Modify: `functions/src/companyChatCore.ts` (the `You are ${c.name}…` builder, ~line 69)
- Modify: whichever Swift call assembles the `companyChat` request body — grep `companyChat` in `codepet/Services/`
- Test: `functions/src/__tests__/companyChatStyle.test.ts`

**Interfaces:**
- Consumes: `AIStyle.promptFragment()` (Task 7), `FounderPrefs` on the company doc (Task 8)
- Produces: `styleBlock(fragment?: string): string` exported from `companyChatCore.ts`

- [ ] **Step 1: Write the failing test**

```ts
// functions/src/__tests__/companyChatStyle.test.ts
// No import: functions/ runs jest with globals injected (jest.config.js + ts-jest).
import { styleBlock } from "../companyChatCore";

describe("styleBlock", () => {
  it("is empty when the founder changed nothing", () => {
    expect(styleBlock(undefined)).toBe("");
    expect(styleBlock("")).toBe("");
    expect(styleBlock("   ")).toBe("");
  });

  it("carries the fragment under its own heading", () => {
    const out = styleBlock("Be blunt and economical.");
    expect(out).toContain("Be blunt and economical.");
    expect(out.startsWith("\n\n")).toBe(true);
  });

  it("does not duplicate a fragment it is given twice", () => {
    const once = styleBlock("Never use emoji.");
    expect(once.match(/Never use emoji\./g)?.length).toBe(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest src/__tests__/companyChatStyle.test.ts`
Expected: FAIL — `styleBlock` is not exported

- [ ] **Step 3: Write minimal implementation**

In `functions/src/companyChatCore.ts`, beside the existing context builder:

```ts
/**
 * The founder's tone preferences, appended after the persona and before the company
 * context. Empty when they changed nothing, so an untouched settings panel costs no
 * tokens. The fragment is composed client-side by `AIStyle.promptFragment()`.
 */
export function styleBlock(fragment?: string): string {
  const f = (fragment ?? "").trim();
  if (!f) return "";
  return `\n\nHow the founder wants you to write:\n${f}`;
}
```

Then append `styleBlock(req.styleFragment)` to the system prompt where the persona string and the company-context block are already concatenated. On the Swift side, add `styleFragment` to the request body from `companyStore.company.founderPrefs.style.promptFragment()`, omitting the key when it is `nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest src/__tests__/companyChatStyle.test.ts`
Expected: PASS, 3 tests

- [ ] **Step 5: Commit**

```bash
git add functions/src/companyChatCore.ts functions/src/__tests__/companyChatStyle.test.ts codepet/Services
git commit -m "feat(chat): carry the founder's tone into the system prompt"
```

---

### Task 11: Memory panel

**Files:**
- Create: `codepet/Views/Settings/MemoryPanel.swift`
- Create: `codepet/Models/MemoryDigest.swift`
- Modify: `codepet/Views/Settings/SettingsModal.swift` (`case .memory:`)
- Test: `codepetTests/MemoryDigestTests.swift`

**Interfaces:**
- Consumes: `PetMemoryStore.shared` (`memories`, `resetAll()`, `allMemoryPrompt()`), the company doc's facts written by the `remember_fact` tool, `FounderPrefs.memoryEnabled`
- Produces: `MemoryDigest.codingActivityLine(memories:lang:)`, `MemoryPanel()`

Before writing, grep for where `remember_fact` results land on the company doc — the field name decides the list's source. If facts are stored as `decisions`, read those.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/MemoryDigestTests.swift
import XCTest
@testable import codepet

final class MemoryDigestTests: XCTestCase {
    func test_noSessionsReadsAsNothingYet() {
        XCTAssertEqual(MemoryDigest.codingActivityLine(memories: [:], lang: .en),
                       "No coding sessions yet.")
    }

    func test_summarisesSessionsAndStreak() {
        var m = PetMemory()
        m.totalSessions = 12
        m.currentStreak = 4
        let line = MemoryDigest.codingActivityLine(memories: ["/p": m], lang: .en)
        XCTAssertTrue(line.contains("12"), line)
        XCTAssertTrue(line.contains("4"), line)
    }

    func test_ignoresProjectsWithNoSessions() {
        var real = PetMemory(); real.totalSessions = 3
        let empty = PetMemory()
        let line = MemoryDigest.codingActivityLine(
            memories: ["/a": real, "/b": empty], lang: .en)
        XCTAssertTrue(line.contains("3"), line)
    }
}
```

`PetMemory.totalSessions` and `PetMemory.currentStreak` are verified to exist (`PetMemoryStore.swift:159,163`), so this test compiles as written.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/MemoryDigestTests`
Expected: FAIL — "cannot find 'MemoryDigest' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// codepet/Models/MemoryDigest.swift
import Foundation

/// One readable line describing derived coding memory. Pure, so the wording is testable
/// without a view — `PetMemoryStore` is a singleton and awkward to inject.
enum MemoryDigest {
    static func codingActivityLine(memories: [String: PetMemory], lang: AppLanguage) -> String {
        let active = memories.values.filter { $0.totalSessions > 0 }
        guard !active.isEmpty else {
            return lang == .vi ? "Chưa có phiên lập trình nào." : "No coding sessions yet."
        }
        let sessions = active.reduce(0) { $0 + $1.totalSessions }
        let streak = active.map(\.currentStreak).max() ?? 0
        return lang == .vi
            ? "\(sessions) phiên · chuỗi \(streak) ngày"
            : "\(sessions) sessions · \(streak)-day streak"
    }
}
```

```swift
// codepet/Views/Settings/MemoryPanel.swift
import SwiftUI

/// What the founder's team remembers, and how to forget it.
///
/// Two stores, deliberately treated differently: facts the founder's team was TOLD are
/// deletable one by one, because that is the trust-critical half. Coding activity is
/// derived from sessions, so it gets a summary and one Reset rather than per-row editing.
struct MemoryPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    @ObservedObject private var petMemory = PetMemoryStore.shared
    private var lang: AppLanguage { appState.uiLanguage }

    @State private var confirmReset = false

    private var memoryEnabled: Bool { companyStore.company.founderPrefs.memoryEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Bật ghi nhớ" : "Enable memory",
                    description: lang == .vi
                        ? "Cho đội của bạn dùng những gì đã học về công ty."
                        : "Let your team personalise using what they've learned about your company."
                ) {
                    Toggle("", isOn: Binding(
                        get: { memoryEnabled },
                        set: { on in
                            var prefs = companyStore.company.founderPrefs
                            prefs.memoryEnabled = on
                            Task { await companyStore.setFounderPrefs(prefs) }
                        }
                    ))
                    .labelsHidden()
                }
            }

            SettingsGroupLabel(lang == .vi ? "Điều đội bạn biết" : "What your team knows")
            SettingsGroup {
                if facts.isEmpty {
                    SettingsRow(label: lang == .vi ? "Chưa có gì." : "Nothing yet.") {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(facts.enumerated()), id: \.offset) { idx, fact in
                        if idx > 0 { SettingsDivider() }
                        SettingsRow(label: fact) {
                            Button { forget(fact) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(CodepetTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                            .help(lang == .vi ? "Xoá" : "Forget")
                        }
                    }
                }
            }
            .opacity(memoryEnabled ? 1 : 0.5)

            SettingsGroupLabel(lang == .vi ? "Hoạt động lập trình" : "Coding activity")
            SettingsGroup {
                SettingsRow(
                    label: MemoryDigest.codingActivityLine(
                        memories: petMemory.memories, lang: lang),
                    description: lang == .vi
                        ? "Suy ra từ các phiên của bạn, không phải bạn nhập."
                        : "Derived from your sessions, not something you typed."
                ) {
                    Button(lang == .vi ? "Đặt lại" : "Reset") { confirmReset = true }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentOrange)
                }
            }
            .opacity(memoryEnabled ? 1 : 0.5)
        }
        .confirmationDialog(
            lang == .vi ? "Đặt lại hoạt động lập trình?" : "Reset coding activity?",
            isPresented: $confirmReset
        ) {
            Button(lang == .vi ? "Đặt lại" : "Reset", role: .destructive) {
                petMemory.resetAll()
            }
            Button(lang == .vi ? "Huỷ" : "Cancel", role: .cancel) { }
        }
    }

    /// The REAL store, verified against the tree. `remember_fact` (the chat tool) flows
    /// through `CompanyStore.handleRemember` -> `Decisions.mergeDecisions` -> this array,
    /// persisted by the EXISTING `decisionsSaver`. No new write path is needed.
    private var facts: [DecisionEntry] { companyStore.company.decisions }

    private func forget(_ entry: DecisionEntry) {
        Task { await companyStore.forgetDecision(entry) }
    }
}
```

**Verified API, replacing this plan's earlier guess.** There is no `companyFacts` and no
`forgetFact`:

- `CompanyState.decisions: [DecisionEntry]`, where `DecisionEntry` is
  `{ topic: String, statement: String, source: String?, updatedAt: Double? }`
  (`codepet/Models/Decisions.swift:8`).
- `CompanyStore.handleRemember(_:cid:)` (~line 1094) already merges and persists through
  `decisionsSaver`. **The write path exists — do not add a second one.**
- Rows show `statement`, with `topic` as the secondary label.

Add only `forgetDecision(_:)`, following `setFounderPrefs`'s finished idiom: capture
`hydrationToken` synchronously, bail while hydrating, remove the entry, persist through the
existing `decisionsSaver`, then re-check `token == hydrationToken && companyId == cid` after
the await. Test that it removes exactly one entry, issues exactly one write, and that a
superseded call does not write into an incoming account.

**Scope:** `decisions` holds every fact the companion knows, including entries from the
`extractDecisions` function, not only chat-remembered ones (`source` distinguishes them). The
panel lists them ALL, because they all feed the prompt — filtering to `source == "chat"` would
let a panel titled "What Crash knows" claim a completeness it does not have.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/MemoryDigestTests`
Expected: PASS, 3 tests

Then confirm the payload honours the toggle:

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/FounderPrefsPersistenceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/MemoryDigest.swift codepet/Views/Settings/MemoryPanel.swift codepet/Views/Settings/SettingsModal.swift codepet/Managers/CompanyStore.swift codepetTests
git commit -m "feat(settings): Memory panel — deletable facts, derived activity, one switch"
```

---

### Task 12: Notifications panel

**Files:**
- Create: `codepet/Views/Settings/NotificationsPanel.swift`
- Modify: `codepet/Views/Settings/SettingsModal.swift` (`case .notifications:`; the placeholder arm is now gone entirely)
- Modify: `codepet/Managers/HealthNudgeController.swift` (respect the channel)
- Test: `codepetTests/NotificationChannelTests.swift`

**Interfaces:**
- Consumes: `FounderPrefs.notifications`, `NotificationChannel`, `HealthNudgeController`
- Produces: `NotificationsPanel()`, `NotificationCategory` (`sessionNudges`, `runFinished`) with `key`, `title(_:)`, `description(_:)`

Two categories only — the two that exist. **No email channel**: there is no email infrastructure, and offering it would lie.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/NotificationChannelTests.swift
import XCTest
@testable import codepet

final class NotificationChannelTests: XCTestCase {
    func test_absentChoiceMeansInApp() {
        let prefs = FounderPrefs()
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .inApp)
    }

    func test_explicitOffIsHonoured() {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.sessionNudges.key] = .off
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .off)
        XCTAssertEqual(NotificationCategory.runFinished.channel(in: prefs), .inApp)
    }

    func test_everyCategoryIsTranslated() {
        for c in NotificationCategory.allCases {
            XCTAssertFalse(c.title(.en).isEmpty)
            XCTAssertNotEqual(c.title(.en), c.title(.vi), c.key)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/NotificationChannelTests`
Expected: FAIL — "cannot find 'NotificationCategory' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// codepet/Views/Settings/NotificationsPanel.swift
import SwiftUI

/// The two notification categories that actually exist. No email channel — there is no
/// email infrastructure, and a dropdown offering it would lie.
enum NotificationCategory: String, CaseIterable, Identifiable {
    case sessionNudges, runFinished

    var id: String { rawValue }
    var key: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .sessionNudges: return lang == .vi ? "Nhắc nghỉ" : "Session nudges"
        case .runFinished:   return lang == .vi ? "Chạy xong" : "Run finished"
        }
    }

    func description(_ lang: AppLanguage) -> String {
        switch self {
        case .sessionNudges:
            return lang == .vi ? "Khi bạn đã lập trình một lúc lâu."
                               : "When you've been coding for a long stretch."
        case .runFinished:
            return lang == .vi ? "Khi một việc đang chạy hoàn tất."
                               : "When a run you started completes."
        }
    }

    /// An absent choice means in-app — the behaviour before this panel existed.
    func channel(in prefs: FounderPrefs) -> NotificationChannel {
        prefs.notifications[key] ?? .inApp
    }
}

struct NotificationsPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    private var lang: AppLanguage { appState.uiLanguage }

    var body: some View {
        SettingsGroup {
            ForEach(Array(NotificationCategory.allCases.enumerated()), id: \.element.id) { idx, cat in
                if idx > 0 { SettingsDivider() }
                SettingsRow(label: cat.title(lang), description: cat.description(lang)) {
                    Picker("", selection: Binding(
                        get: { cat.channel(in: companyStore.company.founderPrefs) },
                        set: { ch in
                            var prefs = companyStore.company.founderPrefs
                            prefs.notifications[cat.key] = ch
                            Task { await companyStore.setFounderPrefs(prefs) }
                        }
                    )) {
                        Text(lang == .vi ? "Tắt" : "Off").tag(NotificationChannel.off)
                        Text(lang == .vi ? "Trong ứng dụng" : "In-app").tag(NotificationChannel.inApp)
                    }
                    .labelsHidden().frame(width: 150)
                }
            }
        }
    }
}
```

In `HealthNudgeController`, guard the nudge on the choice — read the controller first and place the check where it already decides whether to fire:

```swift
        guard NotificationCategory.sessionNudges
            .channel(in: companyStore.company.founderPrefs) != .off else { return }
```

In `SettingsModal.swift`, the switch now covers all nine sections with no placeholder arm:

```swift
        case .notifications: NotificationsPanel()
```

- [ ] **Step 4: Run the full suite**

```bash
pgrep -f 'codepet.app/Contents/MacOS/codepet' | xargs -r kill
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' 2>&1 | tail -20
cd functions && npx jest && cd ..
```

Expected: `** TEST SUCCEEDED **` with a test count at or above the pre-plan baseline, and green jest.

- [ ] **Step 5: Signed build, then hand the visual check to the founder**

```bash
pgrep -f 'codepet.app/Contents/MacOS/codepet' | xargs -r kill
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" 2>&1 | tail -3
```

Verify `codesign -dv` reports `TeamIdentifier=YL72VTKBR7` before launching — a `xcodebuild test` run in step 4 rebuilt the app target and may have left it ad-hoc, which breaks keychain auth and signs the founder out.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Settings/NotificationsPanel.swift codepet/Views/Settings/SettingsModal.swift codepet/Managers/HealthNudgeController.swift codepetTests/NotificationChannelTests.swift
git commit -m "feat(settings): Notifications panel — two real categories, in-app only"
```

---

## Deferred, deliberately

| Deferred | Why | Where it goes |
|---|---|---|
| Export data | Needs a real Firestore export path | Its own task after this plan |
| Delete all chats | Destructive; needs a tested batch delete | Its own task after this plan |
| "Headers & Lists" tone knob | The transcript has no markdown renderer | Returns when the chat renders markdown |
| Avatar upload | No image pipeline exists | Not planned |
| Accent colour | Would compound the roadmap accent collision | Not planned |
