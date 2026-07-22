# Dark Mode for the Native Web-Product — Design Spec

**Date:** 2026-07-21
**Context:** The native web-product's design system (`CodepetTheme`) is hardcoded to the web's **light** palette, so the app is light-only regardless of the macOS/app appearance — while the live web (codepet-ver-1-2.vercel.app) runs a warm-charcoal **dark** theme via `[data-theme='dark']` CSS variables. This makes the native app diverge from the web in dark mode.
**Goal:** Make `CodepetTheme` (and the onboarding `OnboardingContent.Palette`) theme-aware (light + dark) using the web's exact dark palette, controlled by a System/Light/Dark preference, so the whole native web-product themes to match the web — with **zero call-site changes** (the token API is unchanged).

---

## Approved decisions (brainstorming)
1. **Dynamic tokens, unchanged API** — convert the hardcoded color tokens to appearance-resolving colors; every `CodepetTheme.surface` etc. call site auto-themes.
2. **Control = System + Settings override** — default **System** (follow macOS); a **Light / Dark / System** control in the native Settings; keep the ⌘⇧T menu as a light/dark toggle.
3. **Dark palette = the web's exact `[data-theme='dark']` values** (captured live).
4. **Accent lightens in dark** (#7c3aed → #9d6bf5), per the web.
5. **Intentionally-dark surfaces stay dark** — splash / sign-in / cold-open backgrounds (`#100a26` / `#0a0818`) do NOT flip.
6. **Rides on `feat/splash-onboarding-web-port`** (cohesive native=web polish, not yet merged).
7. **Deferred (separate task):** the live 9-step onboarding + heading vertical-centering (needs the newer web source, stale locally).

## Color tables (verbatim from the live web palettes)

`CodepetTheme` tokens — (token → light / dark):
| token | web var | light | dark |
|---|---|---|---|
| `pageBackground` | `--page` | `#f8f7f3` | `#16130f` |
| `surface` | `--surface` | `#ffffff` | `#221d17` |
| `hairline` | `--hairline` | `#ece9e2` | `#2f2820` |
| `primaryText` | `--t-1`/`--ink` | `#1f1b15` | `#f4f1ea` |
| `bodyText` | `--t-2` | `#332e27` | `#d8d2c7` |
| `mutedText` | `--t-3` | `#776f65` | `#9e9789` |
| `accentPurple` | `--accent` | `#7c3aed` | `#9d6bf5` |
| `accentPink` | `--rose` | `#ff6b9d` | `#ff85ac` |
| `accentGold` | `--gold` | `#fdb022` | `#fdc352` |
| `accentTeal` | `--teal` | `#2dd4bf` | `#3fe0cb` |
| `accentOrange` | `--clay` | `#ff8c42` | `#ff9b5e` |
| `accentBlue` | (native-only) | `#2563eb` | `#6ea8ff` (lightened; no web var) |

`OnboardingContent.Palette` tokens — used by the onboarding question cards / inputs (must also theme):
| token | web var | light | dark |
|---|---|---|---|
| `surface2` | `--surface-2` | `#fcfbf8` | `#1b1712` |
| `well` | `--well` | `#f1efe9` | `#26211a` |
| `faint` | `--t-4` | `#a79e92` | `#6f685c` |
| `accentDeep` | `--accent-deep` | `#5b27b0` | `#7c3aed` |
| `accentTint` | `--accent-tint` | `#eee6fd` | `#271f3a` |
| `accentLine` | `--accent-line` | `#d9c9f7` | `#43356b` |
| `coldBg` | (cold-open bg) | `#100a26` | `#100a26` (STAYS dark — not dynamic) |

---

## Architecture / components

- **`Color.dyn(light:dark:)` helper** (new, in `CodepetTheme.swift`) — returns an appearance-resolving `Color`:
  ```swift
  static func dyn(_ light: String, _ dark: String) -> Color {
      Color(nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          return NSColor(hex: isDark ? dark : light)   // NSColor(hex:) — new small helper
      })
  }
  ```
  Needs a tiny `NSColor(hex:)` init (mirrors the existing `Color(hex:)`), so tokens keep exact hex values. The dynamic `NSColor` resolves against the view's effective appearance (driven by `preferredColorScheme`), so SwiftUI re-resolves on theme change.
- **`CodepetTheme` tokens** — replace the 12 hardcoded `static let X = Color(red:…)` with `static let X = Color.dyn("<lightHex>", "<darkHex>")` per the table. API unchanged.
- **`OnboardingContent.Palette`** — same treatment for `surface2`/`well`/`faint`/`accentDeep`/`accentTint`/`accentLine`; `coldBg` stays `Color(hex:"#100a26")` (splash/cold-open remain dark in both modes).
- **`AppTheme` enum** (new, e.g. `codepet/Models/AppTheme.swift`):
  ```swift
  enum AppTheme: String, CaseIterable, Codable { case system, light, dark
      var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
      func label(_ lang: AppLanguage) -> String { … }   // System / Light / Dark (+ VI)
  }
  ```
- **`AppState`** — add `@Published var appTheme: AppTheme` persisted to UserDefaults key `cp_appTheme` (default `.system`). Keep the legacy `isDarkMode` for the dead ThemeManager/game path (no longer the web-product trigger); `toggleDarkMode()`/⌘⇧T repurposed to flip `appTheme` between `.light`/`.dark`.
- **`CodePetApp`** — drive the appearance from `appTheme`: apply `.preferredColorScheme(appState.appTheme.colorScheme)` to `ContentView` (nil = follow macOS). This supersedes the current `.themed(isDark:)` forced-light; keep `.themed` only if the dead ThemeManager environment still needs a value (pass `appTheme == .dark`). The ⌘⇧T Theme menu toggles `appTheme`.
- **`SettingsView`** — add a **Theme** row under Account (a segmented `Picker` Light / Dark / System bound to `appState.appTheme`), styled like the existing Language row.

## Data flow
`appState.appTheme` → `.preferredColorScheme(appTheme.colorScheme)` → macOS effective appearance → dynamic `CodepetTheme`/`Palette` colors resolve light or dark → the whole web-product (shell, Overview, Copilot, Library, Environment, Settings, onboarding question cards) themes together. Splash/sign-in/cold-open ignore it (hardcoded dark).

## Error handling / edges
- **System default**: `.preferredColorScheme(nil)` follows macOS; flipping the OS appearance re-resolves the dynamic colors live.
- **Contrast**: dark tokens are the web's, so contrast is web-verified. White-on-accent buttons: accent lightens to `#9d6bf5`, white text still legible. Companion-accent tint (0.12 of `PetCharacter.color`) reads on charcoal; pixel sprites unaffected.
- **Intentionally-dark surfaces**: unchanged, so the splash→sign-in→onboarding cinematic intro stays dark in light mode too (matches web).

## Testing
- **Unit:** `AppTheme.colorScheme` mapping (system→nil, light→.light, dark→.dark) + `AppTheme(rawValue:)` round-trip. `NSColor(hex:)` parses correctly. `Color.dyn` resolves to DIFFERENT RGB under `NSAppearance(named: .darkAqua)` vs `.aqua` (proves the flip) for a representative token (e.g. surface: near-white vs `#221d17`).
- **Build-verified:** all views compile; the app builds green; full existing suite stays green.
- **Manual:** launch signed, Settings → Theme = Dark → the shell/Overview/Library/Environment/Settings + onboarding question cards render the warm-charcoal palette; compare against the live web dark; System follows the Mac.

## Out of scope
- The live 9-step onboarding flow + heading vertical-centering (separate; needs the current web source).
- Re-theming the dead game/reflection views (Stage-2 deletion).
- Per-companion accent re-tinting in dark beyond the existing tint (web only shifts the base `--accent`).
- Vietnamese is supported for the Theme control labels (consistent with Settings), but the deferred onboarding stays English-only.

## Constraints
Don't touch Giang's Build Coach files or `CLAUDE.md`. Worktree `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port`. Toolchain: scheme `codepet` lowercase, FOREGROUND `xcodebuild build/test` `CODE_SIGNING_ALLOWED=NO` (signed build for auth/launch); SourceKit cross-file diagnostics are false positives; iCloud git → `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`, `rm` the worktree `index.lock`, background commits.

## Open decisions
None — dynamic-token approach, System-default + Settings control + ⌘⇧T, exact web dark palette, accent lightening, and splash-stays-dark all resolved in brainstorming. Ready for implementation planning.
