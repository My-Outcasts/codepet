# Sign-in Screen — Faithful Web Port — Design Spec

**Date:** 2026-07-21
**Context:** The splash + first-run onboarding were ported to the web's dark cinematic design (branch `feat/splash-onboarding-web-port`). The native `ReturningSignInView` still has the old light-purple pixel design, so the pre-app flow (splash → sign-in → onboarding) is visually inconsistent. The web sign-in shares the same dark cosmic world (its own `auth.jpg`), so this closes the gap.
**Goal:** Rewrite `ReturningSignInView` to the web sign-in design — a dark cosmic background with a light floating card — while preserving every existing auth behavior and the two native-only features (guest escape + forgot-password). View-layer only.

---

## Approved decisions (brainstorming)
1. **Faithful port** of the web `SignIn.tsx` / `.signin` design: dark `#0a0818` background + `auth.jpg` Ken-Burns + radial vignette, with a light card (white, radius 20, soft shadow, rise-in).
2. **`auth.jpg`** (the web's distinct cosmic image for sign-in) is imported and used — NOT `splash.jpg`; splash → sign-in should read as moving through scenes.
3. **Web "company" copy** ("Sign in to your company." / "Create your company." / "New here? Create a company" / "Create company"), consistent with the splash + onboarding framing.
4. **Pixel "Codepet" text brand** (matches the splash title), not the `codepet-text-logo` image.
5. **Placeholder-only inputs** (no field labels), as the web does.
6. **Name field in sign-up mode** (bound locally, passed to `signUpWithEmail`), as the web does.
7. **Native-only features preserved** (web has neither): "Forgot password?" as a subtle right-aligned action under the password (+ the "reset email sent" confirmation); "Continue without signing in →" as a quiet white link BELOW the card on the dark background (mirrors the onboarding's outside-the-card Skip).
8. **English-only** (consistent with the splash + onboarding port).

## What must be preserved (auth wiring — view-layer change only)
All `AuthManager` calls stay exactly as today, only re-skinned:
- `authManager.signInWithGoogle()`
- `authManager.signInWithEmail(email:password:)`
- `authManager.signUpWithEmail(email:password:name:)` — `name` = the new sign-up name field (fallback: `appState.displayName`)
- `authManager.sendPasswordReset(email:)` + the `resetSent` confirmation
- `authManager.isGuestMode = true` (guest escape)
- `authManager.authError` (error display; the existing "reset email sent" filter stays)
- Local state: `email`, `password`, `isSignUp` toggle, `isAuthenticating` busy state, `emailReady` validation (`!email.isEmpty && password.count >= 6 && !isAuthenticating`), the 2s `isAuthenticating` reset.

## Source of truth (web) — port these
- `~/Desktop/Codepet v1.2/components/auth/SignIn.tsx` (structure + copy).
- `~/Desktop/Codepet v1.2/app/globals.css` `.signin*` (lines ~7029–7195): bg `#0a0818`; `::before` = `auth.jpg` `kenburns 34s`; `::after` = radial vignette `rgba(8,6,24,.34)→(.74)`; `.signin-card` = `--surface` white, `1px rgba(255,255,255,.55)` border, radius 20, padding `34/32/28`, shadow `0 24px 70px rgba(6,3,28,.5)` + inset top highlight, riseIn; `.signin-brand` pixel 30px `--ink`; `.signin-sub` 14px `--t-3`; `.signin-google` white/`--hairline`, h46 r12; `.signin-or` hairline rules + `--t-4` "or"; `.signin-input` h46 r12 `--surface-2` bg, focus `--accent-line` + `0 0 0 3px rgba(124,58,237,.12)`; `.signin-submit` `--accent`, r12, shadow, hover `--accent-deep`; `.signin-error` `--rose`; `.signin-toggle` `--t-3`, hover `--accent-deep`.
- Asset: `~/Desktop/Codepet v1.2/public/auth.jpg` (confirmed present).

### Web→native color map (reuse existing tokens)
`--surface #ffffff`→`CodepetTheme.surface`; `--surface-2 #fcfbf8`→`OnboardingContent.Palette.surface2`; `--well #f1efe9`→`.well`; `--hairline #ece9e2`→`CodepetTheme.hairline`; `--ink #1f1b15`→`CodepetTheme.primaryText`; `--t-3 #776f65`→`CodepetTheme.mutedText`; `--t-4 #a79e92`→`OnboardingContent.Palette.faint`; `--accent #7c3aed`→`CodepetTheme.accentPurple`; `--accent-deep #5b27b0`→`.accentDeep`; `--accent-line #d9c9f7`→`.accentLine`; `--rose #ff6b9d`→`CodepetTheme.accentPink`; `--clay #ff8c42`→`CodepetTheme.accentOrange`. Sign-in bg `#0a0818` and vignette `#080618` are new literals (inline `Color(hex:)`).

---

## Architecture / components
Single-file rewrite of `codepet/Views/Onboarding/ReturningSignInView.swift` + one asset import. No new types beyond a couple of private sub-view helpers kept inside the file.

- **Layout** — `ZStack`: dark bg (`Color(hex:"#0a0818")`) + `Image("auth")` (`.scaledToFill`, slow Ken-Burns scale via `withAnimation(...repeatForever(autoreverses:true))`, static under `accessibilityReduceMotion`) + radial vignette overlay + a centered `VStack` holding the **card** and, beneath it, the **guest link**.
- **Card** (`signInCard`) — a `VStack(alignment: .leading)` in a `RoundedRectangle(cornerRadius: 20)` fill `CodepetTheme.surface`, white 0.55 stroke, soft shadow, max-width 394, rise-in (opacity+offset on appear). Contents in order:
  1. Pixel "Codepet" (`.pixelSystem(size: 30, weight: .bold)`, `primaryText`).
  2. Sub-line: `isSignUp ? "Create your company." : "Sign in to your company."` (14, `mutedText`).
  3. `authError` line when present (and not the reset-sent message) → `accentPink`.
  4. Google button (`signInWithGoogle`) — white fill, hairline border, h46 r12, "Continue with Google".
  5. "or" divider (two hairline `Rectangle`s + "or" in `faint`).
  6. Form fields — name (`isSignUp` only), email, password — placeholder-only, `surface2` bg, hairline border r12, purple focus ring (via `@FocusState`). Email `.textContentType(.emailAddress)`; password `SecureField`.
  7. Below password: `HStack` with a `Spacer()` then "Forgot password?" (right-aligned, `faint`) — sign-in mode only; guard-empty-email keeps the existing behavior. `resetSent` confirmation line (the existing native green `Color(hex:"#20B090")`) when sent.
  8. Submit — accent-purple fill (dimmed when `!emailReady`), r12, shows `ProgressView` + "Signing in…" while `isAuthenticating`, else "Sign in"/"Create company"; disabled unless `emailReady`.
  9. Mode toggle — full-width, `mutedText`: `isSignUp ? "Already have an account? Sign in" : "New here? Create a company"`; clears `authError` + `resetSent` on toggle.
- **Guest link** (below the card, on the dark bg) — "Continue without signing in →" in `white.opacity(0.7)`, `.plain`, sets `authManager.isGuestMode = true`.
- **Name field state** — add `@State private var name = ""`; sign-up passes `name.isEmpty ? appState.displayName : name`.
- **Asset** — `codepet/Assets.xcassets/Onboarding/auth.imageset/` (copy `public/auth.jpg` + `Contents.json`).

## Data flow
Unchanged from today: the view mutates `AuthManager` (`currentUser`/`isGuestMode`/`authError`) which `ContentView` observes to route to onboarding/shell. This spec only re-skins the view; no store/router change.

## Error handling
- `authError` surfaced inside the card (rose), same filter as today (hide the reset-sent string).
- `resetSent` confirmation retained.
- Reduce-motion: static background (no Ken-Burns).
- Buttons disabled during `isAuthenticating` / when `!emailReady` (unchanged validation).

## Testing
No new unit tests — this is a view re-skin with no new pure logic (auth wiring unchanged and already covered by `SignInStepTests`/existing auth paths). Success = `xcodebuild build` green + the full existing suite stays green (native convention: SwiftUI views are build-verified). Manual smoke: dark cosmic bg + light card renders; Google / email / sign-up-with-name / forgot-password / guest all still fire their `AuthManager` calls; toggle switches copy; error + reset-sent lines show.

## Out of scope
- The sign-out confirmation modal (`.so-*`) and any other auth surfaces.
- Firebase/AuthManager behavior changes (view-layer only).
- Vietnamese translation (English-only).
- Re-skinning the splash/onboarding (already done on this branch).

## Constraints
Don't touch Giang's Build Coach files or `CLAUDE.md`. Worktree `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port` (this rides on the same branch, extending the pre-app flow). Toolchain: scheme `codepet` lowercase, FOREGROUND `xcodebuild build/test` `CODE_SIGNING_ALLOWED=NO`; SourceKit cross-file diagnostics are false positives; iCloud git → `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false`, `rm` the worktree `index.lock`, commit via background.

## Open decisions
None — background image (`auth.jpg`), copy ("company"), brand (pixel text), placeholders, name field, and the placement of the two native-only features (forgot-password in card, guest below card) all resolved in brainstorming. Ready for implementation planning.
