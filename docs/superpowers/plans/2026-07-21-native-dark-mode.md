# Native Dark Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native web-product theme-aware (light + dark) matching the web's dark palette, controlled by a System/Light/Dark preference.

**Architecture:** Convert `CodepetTheme` (12 tokens) + `OnboardingContent.Palette` (6 tokens) from hardcoded light `Color`s to appearance-resolving colors via a `Color.dyn(light,dark)` helper (dynamic `NSColor`), so every call site auto-themes with zero edits. An `AppTheme` preference on `AppState` drives `.preferredColorScheme`, which flips the dynamic colors. Splash/sign-in/cold-open stay dark.

**Tech Stack:** Swift 5 / SwiftUI + AppKit (`NSColor`/`NSAppearance`), macOS 13+. XCTest.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port`.
- **Toolchain:** scheme **`codepet`** (lowercase). Build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`. Test: `... xcodebuild test ... 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`. FOREGROUND. Launch verification uses a **signed** build (drop `CODE_SIGNING_ALLOWED=NO`). SourceKit "Cannot find type X" / "No such module" are FALSE POSITIVES.
- **iCloud git:** `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` before each git write; commits may hang → run in background, confirm HEAD advanced.
- **Exact color tables** (token → light / dark), verbatim from the spec:
  `pageBackground` #f8f7f3/#16130f · `surface` #ffffff/#221d17 · `hairline` #ece9e2/#2f2820 · `primaryText` #1f1b15/#f4f1ea · `bodyText` #332e27/#d8d2c7 · `mutedText` #776f65/#9e9789 · `accentPurple` #7c3aed/#9d6bf5 · `accentPink` #ff6b9d/#ff85ac · `accentGold` #fdb022/#fdc352 · `accentTeal` #2dd4bf/#3fe0cb · `accentOrange` #ff8c42/#ff9b5e · `accentBlue` #2563eb/#6ea8ff. Palette: `surface2` #fcfbf8/#1b1712 · `well` #f1efe9/#26211a · `faint` #a79e92/#6f685c · `accentDeep` #5b27b0/#7c3aed · `accentTint` #eee6fd/#271f3a · `accentLine` #d9c9f7/#43356b · `coldBg` #100a26 (**stays static dark**).
- **Splash / sign-in / cold-open stay dark** (their `#0a0818`/`#100a26` backgrounds are not tokens — untouched).
- **Default = System.** Keep legacy `appState.isDarkMode` for the dead ThemeManager/game path (kept in sync); `appTheme` is the web-product trigger.
- Don't touch Giang's Build Coach files or `CLAUDE.md`. `Color(hex:)` (Character.swift), `.pixelSystem`, `CodepetTheme.body` exist.

---

### Task 1: `Color.dyn` helper + `NSColor(hex:)` + prove the appearance flip

**Files:**
- Modify: `codepet/Views/CodepetTheme.swift` (add `import AppKit` if missing; append the helpers below)
- Test: `codepetTests/DynamicColorTests.swift`

**Interfaces:**
- Produces: `NSColor.init(hex: String)`; `CodepetTheme.dynamicNSColor(light: String, dark: String) -> NSColor`; `Color.dyn(_ light: String, _ dark: String) -> Color`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/DynamicColorTests.swift
import XCTest
import AppKit
@testable import codepet

final class DynamicColorTests: XCTestCase {
    func testNSColorHexParses() {
        let c = NSColor(hex: "#221d17").usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent,   CGFloat(0x22) / 255, accuracy: 0.01)
        XCTAssertEqual(c.greenComponent, CGFloat(0x1d) / 255, accuracy: 0.01)
        XCTAssertEqual(c.blueComponent,  CGFloat(0x17) / 255, accuracy: 0.01)
    }

    func testDynamicColorFlipsByAppearance() {
        let ns = CodepetTheme.dynamicNSColor(light: "#ffffff", dark: "#221d17")
        var lightR: CGFloat = -1, darkR: CGFloat = -1
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            lightR = ns.usingColorSpace(.sRGB)!.redComponent
        }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            darkR = ns.usingColorSpace(.sRGB)!.redComponent
        }
        XCTAssertEqual(lightR, 1.0, accuracy: 0.01)                 // #ffffff
        XCTAssertEqual(darkR, CGFloat(0x22) / 255, accuracy: 0.01)  // #221d17
        XCTAssertNotEqual(lightR, darkR, accuracy: 0.001)          // proves the dynamic flip
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DynamicColorTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "Cannot find 'NSColor(hex:)' / 'dynamicNSColor'".

- [ ] **Step 3: Add the helpers**

At the top of `codepet/Views/CodepetTheme.swift`, ensure AppKit is imported (add `import AppKit` after `import SwiftUI` if not present). Append at the end of the file:

```swift
import AppKit

extension NSColor {
    /// Parse "#rrggbb" (mirrors Color(hex:) in Character.swift).
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v & 0xFF0000) >> 16) / 255.0,
                  green:   CGFloat((v & 0x00FF00) >> 8) / 255.0,
                  blue:    CGFloat(v & 0x0000FF) / 255.0,
                  alpha: 1)
    }
}

extension CodepetTheme {
    /// A dynamic NSColor resolving to `light` or `dark` by the drawing appearance.
    /// Extracted (vs inline in `Color.dyn`) so the flip is unit-testable.
    static func dynamicNSColor(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

extension Color {
    /// A color that resolves to `light` under a light appearance and `dark` under
    /// a dark appearance — driven by `preferredColorScheme` / the macOS appearance.
    static func dyn(_ light: String, _ dark: String) -> Color {
        Color(nsColor: CodepetTheme.dynamicNSColor(light: light, dark: dark))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DynamicColorTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Test case.*(passed|failed)" | tail`
Expected: `** TEST SUCCEEDED **` — the dynamic NSColor mechanism flips by appearance (the tech-risk mechanism is validated at the NSColor layer; whether SwiftUI re-renders on theme change is verified at Task 4's launch).

- [ ] **Step 5: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Views/CodepetTheme.swift codepetTests/DynamicColorTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: Color.dyn + NSColor(hex:) — appearance-resolving dynamic colors" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Convert CodepetTheme + Palette tokens to dynamic

**Files:**
- Modify: `codepet/Views/CodepetTheme.swift` (the 12 token `static let`s, ~lines 25–53)
- Modify: `codepet/Models/OnboardingContent.swift` (the 6 `Palette` tokens; `coldBg` unchanged)

**Interfaces:**
- Consumes: `Color.dyn(_:_:)` (Task 1).
- Produces: same token names/types (`static let ...: Color`) — API unchanged; values now dynamic.

- [ ] **Step 1: Replace the CodepetTheme tokens**

In `codepet/Views/CodepetTheme.swift`, replace the color token `static let`s with:

```swift
    static let pageBackground = Color.dyn("#f8f7f3", "#16130f")
    static let surface        = Color.dyn("#ffffff", "#221d17")
    static let hairline       = Color.dyn("#ece9e2", "#2f2820")
    static let primaryText    = Color.dyn("#1f1b15", "#f4f1ea")
    static let bodyText       = Color.dyn("#332e27", "#d8d2c7")
    static let mutedText      = Color.dyn("#776f65", "#9e9789")
    static let accentPurple   = Color.dyn("#7c3aed", "#9d6bf5")
    static let accentPink     = Color.dyn("#ff6b9d", "#ff85ac")
    static let accentGold     = Color.dyn("#fdb022", "#fdc352")
    static let accentTeal     = Color.dyn("#2dd4bf", "#3fe0cb")
    static let accentOrange   = Color.dyn("#ff8c42", "#ff9b5e")
    static let accentBlue     = Color.dyn("#2563eb", "#6ea8ff")
```
(Keep the surrounding doc comments; only the initializers change. Leave `cardRadius`, shadows, and the font helpers untouched.)

- [ ] **Step 2: Replace the Palette tokens**

In `codepet/Models/OnboardingContent.swift`, replace the `enum Palette` body with:

```swift
    enum Palette {
        static let surface2   = Color.dyn("#fcfbf8", "#1b1712")   // --surface-2
        static let well       = Color.dyn("#f1efe9", "#26211a")   // --well
        static let faint      = Color.dyn("#a79e92", "#6f685c")   // --t-4
        static let accentDeep = Color.dyn("#5b27b0", "#7c3aed")   // --accent-deep
        static let accentTint = Color.dyn("#eee6fd", "#271f3a")   // --accent-tint
        static let accentLine = Color.dyn("#d9c9f7", "#43356b")   // --accent-line
        static let coldBg     = Color(hex: "#100a26")             // cold-open / splash — STAYS dark
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Views/CodepetTheme.swift codepet/Models/OnboardingContent.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: dynamic light/dark CodepetTheme + OnboardingContent.Palette tokens (web palette)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `AppTheme` enum + `AppState.appTheme` persistence + toggle repurpose

**Files:**
- Create: `codepet/Models/AppTheme.swift`
- Modify: `codepet/Models/AppState.swift` (add `appTheme`; repurpose `toggleDarkMode()`)
- Test: `codepetTests/AppThemeTests.swift`

**Interfaces:**
- Produces: `enum AppTheme: String { system, light, dark }` with `var colorScheme: ColorScheme?`, `func label(_:) -> String`, `var next: AppTheme`; `AppState.appTheme: AppTheme` (persisted `cp_appTheme`, default `.system`); `AppState.toggleDarkMode()` flips `appTheme` light↔dark and syncs `isDarkMode`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/AppThemeTests.swift
import XCTest
import SwiftUI
@testable import codepet

final class AppThemeTests: XCTestCase {
    func testColorSchemeMapping() {
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }
    func testNextCyclesSystemLightDark() {
        XCTAssertEqual(AppTheme.system.next, .light)
        XCTAssertEqual(AppTheme.light.next, .dark)
        XCTAssertEqual(AppTheme.dark.next, .system)
    }
    func testRawValueRoundTrip() {
        for t in AppTheme.allCases { XCTAssertEqual(AppTheme(rawValue: t.rawValue), t) }
    }
    func testLabels() {
        XCTAssertEqual(AppTheme.system.label(.en), "System")
        XCTAssertEqual(AppTheme.dark.label(.vi), "Tối")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/AppThemeTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|error:" | tail`
Expected: FAIL — "Cannot find 'AppTheme' in scope".

- [ ] **Step 3: Create AppTheme**

```swift
// codepet/Models/AppTheme.swift
import SwiftUI

/// The user's theme preference for the native web-product. `system` follows the
/// macOS appearance; `light`/`dark` force it. Drives `.preferredColorScheme`.
enum AppTheme: String, CaseIterable, Codable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .system: return lang == .vi ? "Hệ thống" : "System"
        case .light:  return lang == .vi ? "Sáng" : "Light"
        case .dark:   return lang == .vi ? "Tối" : "Dark"
        }
    }

    /// Cycle order for the tap control: System → Light → Dark → System.
    var next: AppTheme {
        switch self {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }
}
```

- [ ] **Step 4: Add `appTheme` to AppState + repurpose `toggleDarkMode`**

In `codepet/Models/AppState.swift`, add near `isDarkMode` (line ~112):

```swift
    /// Web-product theme preference (System/Light/Dark). Persisted; default System.
    @Published var appTheme: AppTheme =
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "cp_appTheme") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "cp_appTheme") }
    }
```

Replace the body of `toggleDarkMode()` (line ~389):

```swift
    func toggleDarkMode() {
        // Repurposed for the web-product theme: flip between explicit light/dark.
        appTheme = (appTheme == .dark) ? .light : .dark
        isDarkMode = (appTheme == .dark)   // keep the legacy flag in sync (dead ThemeManager path)
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/AppThemeTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Models/AppTheme.swift codepet/Models/AppState.swift codepetTests/AppThemeTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: AppTheme (system/light/dark) + AppState.appTheme persistence" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the trigger (CodePetApp) + Settings Theme control, and launch-verify the flip

**Files:**
- Modify: `codepet/Managers/ThemeManager.swift` (drop the forced `preferredColorScheme` from `ThemedBackgroundModifier` — CodePetApp now owns it)
- Modify: `codepet/App/CodePetApp.swift` (drive `preferredColorScheme` from `appTheme`)
- Modify: `codepet/Views/Settings/SettingsView.swift` (add the Theme row)

**Interfaces:**
- Consumes: `AppState.appTheme` (Task 3), `AppTheme.colorScheme`/`label`/`next`.

- [ ] **Step 1: Stop ThemedBackgroundModifier from forcing the color scheme**

In `codepet/Managers/ThemeManager.swift`, in `ThemedBackgroundModifier.body`, REMOVE the `.preferredColorScheme(isDark ? .dark : .light)` line (leave `.background(colors.background)` and `.environment(\.theme, colors)`). CodePetApp becomes the sole owner of `preferredColorScheme`.

```swift
    func body(content: Content) -> some View {
        let colors = ThemeManager.shared.colors(for: isDark)
        content
            .background(colors.background)
            .environment(\.theme, colors)
        // preferredColorScheme now driven by AppState.appTheme in CodePetApp
    }
```

- [ ] **Step 2: Drive preferredColorScheme from appTheme in CodePetApp**

In `codepet/App/CodePetApp.swift`, replace the `.themed(isDark: appState.isDarkMode)` line (~line 77) with:

```swift
                .themed(isDark: appState.appTheme == .dark)
                .preferredColorScheme(appState.appTheme.colorScheme)
```
(The existing Theme `CommandMenu` button already calls `appState.toggleDarkMode()`, which now flips `appTheme` — no change needed there.)

- [ ] **Step 3: Add the Theme row to Settings**

In `codepet/Views/Settings/SettingsView.swift`, inside the Account `CodepetCard`'s `VStack`, insert a Theme row immediately after the Language `row { … }` block and its following `Divider()` (i.e. between the Language row's `Divider()` and the `Edit company brief` button), mirroring the Language row exactly:

```swift
                    row(lang == .vi ? "Giao diện" : "Theme") {
                        Button(appState.appTheme.label(lang)) {
                            appState.appTheme = appState.appTheme.next
                        }
                        .buttonStyle(.plain)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                    }
                    Divider()
```

- [ ] **Step 4: Build the whole app**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Full test suite (nothing regressed)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Launch-verify the SwiftUI flip (the real tech-risk gate)**

Build signed + launch, then confirm the web-product themes dark:
```bash
cd ~/Documents/codepet-rebuild-wt
pkill -f "DerivedData/CodePet.*/codepet.app/Contents/MacOS/codepet" 2>/dev/null; sleep 1
xcodebuild build -scheme codepet -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
open "/Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-dpobbamgdftkmwadibjmmhvazbcv/Build/Products/Debug/codepet.app"
```
Then (controller/human): in the app, Settings → Theme → **Dark**; the shell/Overview/Library/Environment/Settings + onboarding question cards must render the warm-charcoal palette (surface #221d17, text #f4f1ea). Set Theme → **System** and toggle the macOS appearance to confirm it follows.
**If the UI does NOT flip** despite Task 1's unit test passing (i.e. `Color(nsColor:)` snapshots instead of re-resolving): FALLBACK — convert the 18 tokens to **Asset Catalog color sets** (`Assets.xcassets/Theme/<token>.colorset` with Any/Dark appearances at the table's hex values) and point each `static let` at `Color("<token>")`. Re-verify. Note the pivot in the report.

- [ ] **Step 7: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Managers/ThemeManager.swift codepet/App/CodePetApp.swift codepet/Views/Settings/SettingsView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: drive app theme from AppState.appTheme + Settings Theme control" \
  -m "CodePetApp owns preferredColorScheme (System/Light/Dark); ThemedBackgroundModifier no longer forces it. Settings gains a Theme cycle row." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification
Settings → Theme cycles System/Light/Dark; Dark renders the web's warm-charcoal palette across shell/Overview/Library/Environment/Settings + onboarding question cards; System follows macOS; splash/sign-in/cold-open stay dark; ⌘⇧T still toggles; full build + suite green. Compare Dark against the live web (`codepet-ver-1-2.vercel.app`, `data-theme=dark`).

## Self-Review
**Spec coverage:** dyn helper + NSColor(hex:) (T1 ✓); dynamic CodepetTheme + Palette tokens per the tables, coldBg static (T2 ✓); AppTheme enum + colorScheme/label/next + appState.appTheme persistence + toggleDarkMode repurpose (T3 ✓); CodePetApp preferredColorScheme trigger + ThemedBackgroundModifier de-forcing + Settings Theme control (T4 ✓); System default (T3/T4 ✓); splash stays dark (T2 coldBg ✓); tech-risk mechanism unit-tested (T1) + launch-verified with asset-set fallback (T4 S6 ✓).

**Placeholder scan:** none — every code step has complete code; every command has expected output; the one conditional (asset-set fallback) is a concrete, fully-specified pivot.

**Type consistency:** `Color.dyn(_:_:)`/`CodepetTheme.dynamicNSColor(light:dark:)`/`NSColor(hex:)` defined in T1, used in T2. `AppTheme` (`.colorScheme`/`.label(_:)`/`.next`/`.allCases`) defined T3, used T3 tests + T4. `AppState.appTheme` defined T3, used T4. Token names unchanged (T2 keeps the `static let` identifiers), so all ~44 consumers keep compiling.

**Known notes for the executor:** (a) pure logic (T1/T3) is unit-tested; token conversion (T2) and wiring (T4) are build-verified; T4 S6 is the true SwiftUI-render gate (launch). (b) If AppKit isn't already imported in CodepetTheme.swift, add it (T1 S3). (c) Controller transcribes verbatim, verifies FOREGROUND, commits in background (iCloud); reviewers are the gate.
