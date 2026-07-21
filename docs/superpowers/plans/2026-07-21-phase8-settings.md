# Phase 8 — Settings (Account + Billing) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sectioned Settings view — companion picker (persist), language, edit-brief, sign out (Account); a static Trial/Pro plan card (Plan); app info (About). CF-free. **Final phase.**

**Architecture:** Mostly surfaces existing controls; adds a persisting `CompanyStore.setCompanion`, a `CompanyOnboardingModel.prefill` (for the edit-brief sheet), and a static `Plan` enum. `SettingsView` composes them + routes from `AppShellView`.

**Tech Stack:** SwiftUI (macOS 13+), Firebase. Reuses `CompanyStore`/`CompanyData`, `AppState` (`uiLanguage`/`activeChar`), `AuthManager` (`signOut`), `PetCharacter.all`, `CompanyOnboardingModel`/`View`, CodepetTheme. Spec: `docs/superpowers/specs/2026-07-21-phase8-settings-design.md`.

## Global Constraints
- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; `@testable import codepet`. **Run all `xcodebuild` in the FOREGROUND.** Unit test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -20`. Build (view task): `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. SourceKit cross-file diagnostics (Cannot find type X, No such module XCTest/FirebaseFirestore) are FALSE POSITIVES — trust xcodebuild.
- **git on this iCloud worktree hangs.** Commit with: `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` then `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -F <msgfile>` (message from file; retry once on timeout). Use `ls`/`grep`, not `git status`.
- **Decisions:** static plan card (Trial current + Pro upgrade; "Manage plan" no-op; NO usage counter); companion picker sets BOTH `company.companionId` (via `setCompanion`) AND `appState.activeChar`; `setCompanion` follows the `toggleTool` pattern (sync mutate + persist captured cid, fail-soft). Do NOT touch Giang's files or `CLAUDE.md`.

---

## File Structure
- Modify `codepet/Managers/CompanyStore.swift` + `codepet/Services/CompanyData.swift` (Task 1)
- Modify `codepet/Views/Onboarding/CompanyOnboardingModel.swift` + `codepet/Views/Onboarding/CompanyOnboardingView.swift` (Task 2)
- Create `codepet/Models/Plan.swift` + `codepet/Views/Settings/SettingsView.swift` (Task 3)
- Modify `codepet/Views/Shell/AppShellView.swift` (Task 3: `.settings` route)
- Tests: `codepetTests/{CompanyStoreCompanionTests, CompanyOnboardingModelPrefillTests}.swift`

---

### Task 1: `setCompanion` + persistence

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`, `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyStoreCompanionTests.swift`

**Interfaces:**
- Produces: `CompanyStore.setCompanion(id:) async` + injectable `companionSaver`; `CompanyData.companionIdPayload`/`saveCompanionId`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreCompanionTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreCompanionTests: XCTestCase {
    func testSetCompanionSetsAndPersists() async {
        var saved: (String, String)?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             companionSaver: { c, id in saved = (c, id); return true })
        await s.hydrate(companyId: "u")
        await s.setCompanion(id: "nova")
        XCTAssertEqual(s.company.companionId, "nova")
        XCTAssertEqual(saved?.0, "u")
        XCTAssertEqual(saved?.1, "nova")
    }
    func testCompanionIdPayloadShape() {
        XCTAssertEqual(CompanyData.companionIdPayload("luna")["companionId"] as? String, "luna")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreCompanionTests 2>&1 | tail -20`
Expected: FAIL — no `companionSaver`/`setCompanion`/`companionIdPayload`.

- [ ] **Step 3: Add to `CompanyData.swift`**

Add inside `enum CompanyData` (next to the other save helpers):

```swift
    /// Pure Firestore payload for a companion write — testable without Firestore.
    static func companionIdPayload(_ id: String) -> [String: Any] {
        ["companionId": id]
    }

    /// Write companies/{uid}.companionId, merge. Fail-soft: false on error.
    static func saveCompanionId(companyId: String, companionId: String) async -> Bool {
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(companionIdPayload(companionId), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 4: Add `companionSaver` + `setCompanion` to `CompanyStore.swift`**

Add the stored dependency (after `toolsSaver`):

```swift
    private let companionSaver: (String, String) async -> Bool
```

Extend `init` (keep all existing defaults; add the param + assignment after `toolsSaver`):

```swift
         toolsSaver: @escaping (String, [String]) async -> Bool = CompanyData.saveEnabledTools,
         companionSaver: @escaping (String, String) async -> Bool = CompanyData.saveCompanionId) {
```
```swift
        self.toolsSaver = toolsSaver
        self.companionSaver = companionSaver
    }
```

Add the method (inside the class, e.g. after `toggleTool`):

```swift
    /// Set + persist the company's companion (fail-soft). Mirrors the toggleTool
    /// pattern: sync mutate, persist with the captured companyId, no post-await mutation.
    func setCompanion(id: String) async {
        company.companionId = id
        if let cid = companyId { _ = await companionSaver(cid, id) }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests). (Existing `CompanyStore` call sites default the new param.)

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Managers/CompanyStore.swift codepet/Services/CompanyData.swift codepetTests/CompanyStoreCompanionTests.swift
# commit (fsmonitor-off form): "feat(settings): CompanyStore.setCompanion + CompanyData.saveCompanionId (fail-soft)"
```

---

### Task 2: Edit-brief prefill

**Files:**
- Modify: `codepet/Views/Onboarding/CompanyOnboardingModel.swift`, `codepet/Views/Onboarding/CompanyOnboardingView.swift`
- Test: `codepetTests/CompanyOnboardingModelPrefillTests.swift`

**Interfaces:**
- Produces: `CompanyOnboardingModel.prefill(from:)`; `CompanyOnboardingView` gains `var prefillBrief: CompanyBrief? = nil` + `var onDone: (() -> Void)? = nil`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyOnboardingModelPrefillTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyOnboardingModelPrefillTests: XCTestCase {
    func testPrefillMapsFieldsAndStage() {
        let m = CompanyOnboardingModel()
        m.prefill(from: CompanyBrief(founderName: "Mona", role: "Founder", stage: "Launched",
                                     projectName: "Codepet", oneLiner: "AI companion", audience: "devs"))
        XCTAssertEqual(m.founderName, "Mona")
        XCTAssertEqual(m.role, "Founder")
        XCTAssertEqual(m.projectName, "Codepet")
        XCTAssertEqual(m.oneLiner, "AI companion")
        XCTAssertEqual(m.audience, "devs")
        XCTAssertEqual(m.stageIndex, 4)   // "Launched" is index 4 in stages
    }
    func testPrefillEmptyBriefDefaults() {
        let m = CompanyOnboardingModel()
        m.prefill(from: CompanyBrief())
        XCTAssertEqual(m.founderName, "")
        XCTAssertEqual(m.stageIndex, 2)   // nil stage → default
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyOnboardingModelPrefillTests 2>&1 | tail -20`
Expected: FAIL — no `prefill`.

- [ ] **Step 3: Add `prefill` to `CompanyOnboardingModel.swift`**

Add (after `buildBrief()`):

```swift
    /// Prefill the fields from an existing brief (for edit-from-Settings). Maps the
    /// stage string back to its index; an absent/unknown stage falls to the default.
    func prefill(from brief: CompanyBrief) {
        founderName = brief.founderName ?? ""
        role = brief.role ?? ""
        projectName = brief.projectName ?? ""
        oneLiner = brief.oneLiner ?? ""
        audience = brief.audience ?? ""
        stageIndex = brief.stage.flatMap { Self.stages.firstIndex(of: $0) } ?? 2
    }
```

- [ ] **Step 4: Add `prefillBrief`/`onDone` + wiring to `CompanyOnboardingView.swift`**

Add the two stored properties (after `private let api = ReflectionAPIClient()`):

```swift
    var prefillBrief: CompanyBrief? = nil
    var onDone: (() -> Void)? = nil
```

Add a prefill task to the view's root (e.g. on the outer container via `.task`):

```swift
        .task { if let b = prefillBrief { model.prefill(from: b) } }
```

Change the **Finish** button action to call `onDone` after submit — replace:

```swift
                        Task { await model.submit(store: companyStore, api: api) }
```
with:
```swift
                        Task { await model.submit(store: companyStore, api: api); onDone?() }
```

Change the **left (Skip)** button so edit mode shows Cancel→onDone instead of Skip→skipOnboarding — replace:

```swift
                Button(uiLanguage == .vi ? "Bỏ qua" : "Skip") { Task { await companyStore.skipOnboarding() } }
```
with:
```swift
                if let onDone {
                    Button(uiLanguage == .vi ? "Hủy" : "Cancel") { onDone() }
                } else {
                    Button(uiLanguage == .vi ? "Bỏ qua" : "Skip") { Task { await companyStore.skipOnboarding() } }
                }
```

- [ ] **Step 5: Run the prefill test + build (the view edits compile)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyOnboardingModelPrefillTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` (2 tests; the run also compiles the whole target incl. the `CompanyOnboardingView` changes — the existing first-run `CompanyOnboardingView()` call site still compiles since both new props default nil).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Views/Onboarding/CompanyOnboardingModel.swift codepet/Views/Onboarding/CompanyOnboardingView.swift codepetTests/CompanyOnboardingModelPrefillTests.swift
# commit (fsmonitor-off form): "feat(settings): CompanyOnboardingModel.prefill + edit-mode onDone/prefillBrief"
```

---

### Task 3: `Plan` + `SettingsView` + shell route

**Files:**
- Create: `codepet/Models/Plan.swift`, `codepet/Views/Settings/SettingsView.swift`
- Modify: `codepet/Views/Shell/AppShellView.swift`
- Verified by: build + the full existing test suite still green.

**Interfaces:**
- Consumes: `CompanyStore` (`company`, `setCompanion`), `AppState` (`uiLanguage`/`activeChar`), `AuthManager` (`signOut`), `PetCharacter.all`, `CompanyOnboardingView` (Task 2), `Plan` (below), CodepetTheme, `CharacterImage`.
- Produces: `enum Plan`; `SettingsView()`.

- [ ] **Step 1: Write `Plan.swift`**

```swift
// codepet/Models/Plan.swift
import Foundation

/// Static plan copy for the Settings billing card. No live usage tracking (no billing
/// backend yet); mirrors the credits pricing (Trial → Pro).
enum Plan: CaseIterable {
    case trial, pro

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "Dùng thử" : "Trial"
        case .pro:   return "Pro"
        }
    }
    func priceLine(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "Miễn phí · 7 ngày" : "Free · 7 days"
        case .pro:   return lang == .vi ? "$20/tháng" : "$20/mo"
        }
    }
    func creditsLine(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "~150 tín dụng" : "~150 credits"
        case .pro:   return lang == .vi ? "800 tín dụng/tháng · vượt mức $0.05/tín dụng"
                                        : "800 credits/mo · overage $0.05/credit"
        }
    }
}
```

- [ ] **Step 2: Write `SettingsView.swift`**

```swift
// codepet/Views/Settings/SettingsView.swift
import SwiftUI

/// The Settings view — Account (companion / language / edit brief / sign out),
/// Plan (static Trial + Pro cards), and About. CF-free; no live billing.
struct SettingsView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang
    @State private var editingBrief = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var companions: [PetCharacter] {
        PetCharacter.all.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                account
                planSection
                about
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $editingBrief) {
            CompanyOnboardingView(prefillBrief: companyStore.company.brief,
                                  onDone: { editingBrief = false })
        }
    }

    // MARK: Account

    private var account: some View {
        section(lang == .vi ? "Tài khoản" : "Account") {
            Text(lang == .vi ? "Bạn đồng hành" : "Companion")
                .font(.pixelSystem(size: 11, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(companions) { c in
                        let selected = companyStore.company.companionId == c.id
                        Button {
                            Task { await companyStore.setCompanion(id: c.id) }
                            appState.activeChar = c.id
                        } label: {
                            VStack(spacing: 4) {
                                CharacterImage(c.id, size: 34)
                                Text(c.name)
                                    .font(.pixelSystem(size: 9, weight: .medium))
                                    .foregroundColor(selected ? c.color : CodepetTheme.mutedText)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? c.color.opacity(0.14) : Color.clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
            CodepetCard {
                VStack(spacing: 0) {
                    row(lang == .vi ? "Ngôn ngữ" : "Language") {
                        Button(appState.uiLanguage == .vi ? "Tiếng Việt" : "English") {
                            appState.uiLanguage = (appState.uiLanguage == .vi) ? .en : .vi
                        }
                        .buttonStyle(.plain)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                    }
                    Divider()
                    Button { editingBrief = true } label: {
                        rowLabel(lang == .vi ? "Chỉnh sửa hồ sơ công ty" : "Edit company brief",
                                 icon: "square.and.pencil", tint: CodepetTheme.primaryText)
                    }.buttonStyle(.plain)
                    Divider()
                    Button { authManager.signOut() } label: {
                        rowLabel(lang == .vi ? "Đăng xuất" : "Sign out",
                                 icon: "rectangle.portrait.and.arrow.right", tint: CodepetTheme.accentOrange)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Plan

    private var planSection: some View {
        section(lang == .vi ? "Gói" : "Plan") {
            planCard(.trial, current: true)
            planCard(.pro, current: false)
        }
    }

    private func planCard(_ plan: Plan, current: Bool) -> some View {
        CodepetCard(fill: current ? CodepetTheme.accentPurple.opacity(0.08) : CodepetTheme.surface) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title(lang))
                            .font(.pixelSystem(size: 13, weight: .bold))
                            .foregroundColor(CodepetTheme.primaryText)
                        if current {
                            Text(lang == .vi ? "Hiện tại" : "Current")
                                .font(.pixelSystem(size: 9, weight: .semibold))
                                .foregroundColor(CodepetTheme.accentPurple)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
                        }
                    }
                    Text(plan.priceLine(lang))
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                    Text(plan.creditsLine(lang))
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !current {
                    Text(lang == .vi ? "Quản lý" : "Manage plan")
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().stroke(CodepetTheme.hairline))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: About

    private var about: some View {
        section(lang == .vi ? "Giới thiệu" : "About") {
            CodepetCard {
                row("Codepet") {
                    Text("v\(appVersion)")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(CodepetTheme.bodyText)
            content()
        }
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.primaryText)
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
    }

    private func rowLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 18)
            Text(title).font(.pixelSystem(size: 12)).foregroundColor(tint)
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Route `.settings` in `AppShellView.swift`**

Extend the content-slot router with a `.settings` branch (after `.environment`):

```swift
                    } else if companyStore.view == .environment {
                        EnvironmentView()
                    } else if companyStore.view == .settings {
                        SettingsView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite to confirm no regression**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
git add codepet/Models/Plan.swift codepet/Views/Settings/SettingsView.swift codepet/Views/Shell/AppShellView.swift
# commit (fsmonitor-off form): "feat(settings): SettingsView (account + plan + about) + shell .settings route"
```

---

## Final verification
Full build + test in the FOREGROUND: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15` → `** TEST SUCCEEDED **`. The Settings tab now shows the companion picker (persists + updates the sprite), a language toggle, edit-brief (prefilled sheet), sign out, the Trial/Pro plan cards, and app version.

---

## Self-Review

**Spec coverage:** `CompanyStore.setCompanion` + `CompanyData.saveCompanionId`/`companionIdPayload` (Task 1 ✓); `CompanyOnboardingModel.prefill` + `CompanyOnboardingView` `onDone`/`prefillBrief` edit mode (Task 2 ✓); `Plan` static copy + `SettingsView` (Account: companion picker→setCompanion+activeChar, language→uiLanguage, edit-brief sheet, sign out; Plan: Trial current + Pro upgrade + Manage no-op; About: version) + `.settings` route (Task 3 ✓). Decisions honored: static plan (no usage counter); companion sets both companionId + activeChar; setCompanion follows the toggleTool pattern.

**Placeholder scan:** none — every step has complete code or an exact command. ("Manage plan" is an intentional non-interactive placeholder per spec, not a code stub.)

**Type consistency:** `CompanyStore.setCompanion(id:)` + `companionSaver: (String, String) async -> Bool = CompanyData.saveCompanionId` (Task 1) called by `SettingsView` (Task 3). `CompanyOnboardingModel.prefill(from:)` (Task 2) + `CompanyOnboardingView(prefillBrief:onDone:)` (Task 2) used by `SettingsView`'s `.sheet` (Task 3). `Plan.title`/`priceLine`/`creditsLine` (Task 3) fed the plan cards. `appState.uiLanguage`/`activeChar` (settable) + `authManager.signOut()` + `PetCharacter.all`/`CharacterImage(id,size:)` are existing. `AppView.settings` exists (Phase 1).

**Known notes for the implementer:** (a) Task 3 (and the view part of Task 2) have no unit tests by design (SwiftUI verified by build); TDD applies to the model/store parts (Tasks 1, 2-model). (b) `authManager` is injected app-wide via `.environmentObject(authManager)` in `CodePetApp` (confirmed), so `SettingsView`'s `@EnvironmentObject var authManager` resolves. (c) the companion picker sets `appState.activeChar` (sprite) in the view AND `company.companionId` (identity) via `setCompanion` — both, per the decision. (d) `CompanyOnboardingView`'s two new props default nil so the first-run `CompanyOnboardingView()` call site in `ContentView` is unchanged.
