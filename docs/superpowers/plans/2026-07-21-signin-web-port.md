# Sign-in Screen Web-Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `ReturningSignInView` to the web sign-in design — a dark cosmic `auth.jpg` background with a light floating card — preserving every auth behavior and the two native-only features (forgot-password, guest escape).

**Architecture:** View-layer only. One asset import + a single-file rewrite of `ReturningSignInView.swift`. All `AuthManager` calls and local state stay exactly as today, only re-skinned. Reuses `CodepetTheme` + `OnboardingContent.Palette` tokens.

**Tech Stack:** Swift 5 / SwiftUI (macOS 13+). Web source of truth: `~/Desktop/Codepet v1.2/components/auth/SignIn.tsx` + `app/globals.css` `.signin*`.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port` (this rides on the same branch — it completes the pre-app flow).
- **Toolchain:** scheme **`codepet`** (lowercase), no xcodegen. Build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`. Test: `... xcodebuild test ... 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3`. Run **FOREGROUND**. SourceKit "Cannot find type X" / "No such module" are FALSE POSITIVES.
- **iCloud git:** `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` before each git write; commits may hang — run them in the background and confirm HEAD advanced.
- **View-layer only** — do NOT change `AuthManager` or any auth behavior. Preserve verbatim: `signInWithGoogle()`, `signInWithEmail(email:password:)`, `signUpWithEmail(email:password:name:)` (name is a NON-optional `String`), `sendPasswordReset(email:)`, `authManager.isGuestMode = true`, `authManager.authError`. Preserve local state: `email`, `password`, `isSignUp`, `isAuthenticating`, `resetSent`, `emailReady == !email.isEmpty && password.count >= 6 && !isAuthenticating`, and the `DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isAuthenticating = false }` reset.
- **English-only.** **Exact web copy**: "Sign in to your company." / "Create your company." / "Continue with Google" / "or" / "Sign in" / "Create company" / "New here? Create a company" / "Already have an account? Sign in". Native-only strings kept verbatim from today: "Forgot password?", "Enter your email above first.", "Password reset email sent! Check your inbox.", "Continue without signing in →".
- **Color map** (web CSS var → native): `--surface`→`CodepetTheme.surface`; `--surface-2`→`OnboardingContent.Palette.surface2`; `--hairline`→`CodepetTheme.hairline`; `--ink`→`CodepetTheme.primaryText`; `--t-3`→`CodepetTheme.mutedText`; `--t-4`→`OnboardingContent.Palette.faint`; `--accent`→`CodepetTheme.accentPurple`; `--accent-line`→`.accentLine`; `--rose`→`CodepetTheme.accentPink`. New literals: bg `#0a0818`, vignette `#080618`, card shadow `#06031c`, reset-confirmation green `#20B090`. `Color(hex:)`, `.pixelSystem(size:weight:)`, `CodepetTheme.body(_:weight:)` all exist.
- Don't touch Giang's Build Coach files or `CLAUDE.md`.

---

### Task 1: Import the auth.jpg background asset

**Files:**
- Create: `codepet/Assets.xcassets/Onboarding/auth.imageset/{Contents.json, auth.jpg}`

**Interfaces:**
- Produces: asset name `auth` (resolvable via `Image("auth")`).

- [ ] **Step 1: Copy the image + write Contents.json**

```bash
cd ~/Documents/codepet-rebuild-wt
DST="codepet/Assets.xcassets/Onboarding/auth.imageset"
mkdir -p "$DST"
cp "/Users/monatruong/Desktop/Codepet v1.2/public/auth.jpg" "$DST/auth.jpg"
printf '{\n  "images" : [\n    { "filename" : "auth.jpg", "idiom" : "universal" }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$DST/Contents.json"
ls "$DST"   # expect: Contents.json  auth.jpg
```
Expected: both files present.

- [ ] **Step 2: Build to confirm the catalog compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -12`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit (background — iCloud)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Assets.xcassets/Onboarding/auth.imageset
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: import auth.jpg sign-in background asset" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(If the commit hangs, `rm` the lock and re-run; confirm `git log --oneline -1` shows it.)

---

### Task 2: Rewrite ReturningSignInView to the dark cinematic design

**Files:**
- Rewrite (replace whole file): `codepet/Views/Onboarding/ReturningSignInView.swift`

**Interfaces:**
- Consumes: `Image("auth")` (Task 1); `AuthManager` (`signInWithGoogle`, `signInWithEmail(email:password:)`, `signUpWithEmail(email:password:name:)`, `sendPasswordReset(email:)`, `authError`, `isGuestMode`); `AppState.displayName`; `Color(hex:)`, `.pixelSystem(size:weight:)`, `CodepetTheme` (`surface`/`primaryText`/`mutedText`/`hairline`/`accentPurple`/`accentPink`/`body(_:weight:)`), `OnboardingContent.Palette` (`surface2`/`faint`/`accentLine`).
- Produces: `struct ReturningSignInView` — same environment objects (`appState`, `authManager`), no public init args (unchanged call site in `ContentView`).

- [ ] **Step 1: Replace the file**

```swift
// codepet/Views/Onboarding/ReturningSignInView.swift
import SwiftUI

/// Returning-user sign-in — faithful port of the web `SignIn` (dark cosmic
/// auth.jpg world + a light rise-in card). Google + email/password, with the
/// two native-only extras the web lacks: forgot-password and a guest escape.
/// View-layer only — all AuthManager wiring is preserved.
struct ReturningSignInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var resetSent = false
    @State private var isSignUp = false
    @State private var appear = false
    @State private var kenBurns = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case name, email, password }
    private var emailReady: Bool { !email.isEmpty && password.count >= 6 && !isAuthenticating }

    var body: some View {
        ZStack {
            Color(hex: "#0a0818").ignoresSafeArea()
            GeometryReader { geo in
                Image("auth")
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()
            RadialGradient(colors: [Color(hex: "#080618").opacity(0.34), Color(hex: "#080618").opacity(0.74)],
                           center: .center, startRadius: 0, endRadius: 640)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                card
                Button("Continue without signing in →") {
                    authManager.authError = nil
                    authManager.isGuestMode = true
                }
                .font(CodepetTheme.body(13))
                .foregroundColor(.white.opacity(0.7))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 394)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 34).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Codepet")
                .font(.pixelSystem(size: 30, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(isSignUp ? "Create your company." : "Sign in to your company.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.mutedText)
                .padding(.top, 9)

            if let error = authManager.authError, !error.contains("reset email sent") {
                Text(error)
                    .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.accentPink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            // Google
            Button { authManager.signInWithGoogle() } label: {
                Text("Continue with Google")
                    .font(CodepetTheme.body(14)).fontWeight(.medium)
                    .foregroundColor(CodepetTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 22)

            // or
            HStack(spacing: 12) {
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                Text("or").font(CodepetTheme.body(12)).foregroundColor(OnboardingContent.Palette.faint)
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
            }
            .padding(.vertical, 18)

            // form
            VStack(spacing: 10) {
                if isSignUp { field("Your name", text: $name, id: .name) }
                field("Email", text: $email, id: .email, isEmail: true)
                field("Password", text: $password, id: .password, secure: true)
            }

            // forgot password (sign-in only) + reset confirmation
            if !isSignUp {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        guard !email.isEmpty else {
                            authManager.authError = "Enter your email above first."
                            return
                        }
                        authManager.sendPasswordReset(email: email)
                        resetSent = true
                    }
                    .font(CodepetTheme.body(12)).foregroundColor(OnboardingContent.Palette.faint)
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            if resetSent {
                Text("Password reset email sent! Check your inbox.")
                    .font(CodepetTheme.body(11)).foregroundColor(Color(hex: "#20B090"))
                    .padding(.top, 6)
            }

            // submit
            Button { submit() } label: {
                HStack(spacing: 8) {
                    if isAuthenticating { ProgressView().controlSize(.small) }
                    Text(isAuthenticating ? "Signing in…" : (isSignUp ? "Create company" : "Sign in"))
                        .font(CodepetTheme.body(14)).fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple))
                .opacity(emailReady ? 1 : 0.6)
            }
            .buttonStyle(.plain).disabled(!emailReady).padding(.top, 14)

            // toggle mode
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp.toggle(); resetSent = false; authManager.authError = nil
                }
            } label: {
                Text(isSignUp ? "Already have an account? Sign in" : "New here? Create a company")
                    .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain).padding(.top, 18)
        }
        .padding(EdgeInsets(top: 34, leading: 32, bottom: 28, trailing: 32))
        .background(RoundedRectangle(cornerRadius: 20).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.55), lineWidth: 1))
        .shadow(color: Color(hex: "#06031c").opacity(0.5), radius: 35, y: 24)
    }

    private func field(_ placeholder: String, text: Binding<String>, id: Field,
                       secure: Bool = false, isEmail: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain)
        .textContentType(isEmail ? .emailAddress : nil)
        .font(CodepetTheme.body(14))
        .focused($focus, equals: id)
        .frame(minHeight: 46)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(focus == id ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline,
                    lineWidth: focus == id ? 2 : 1))
    }

    private func submit() {
        isAuthenticating = true
        authManager.authError = nil
        if isSignUp {
            authManager.signUpWithEmail(email: email, password: password,
                                        name: name.isEmpty ? appState.displayName : name)
        } else {
            authManager.signInWithEmail(email: email, password: password)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isAuthenticating = false }
    }
}
```

- [ ] **Step 2: Build the whole app**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -12`
Expected: `** BUILD SUCCEEDED **`. (SourceKit "Cannot find CodepetTheme/OnboardingContent/AuthManager" in the editor are false positives — the command output is authoritative. If `.textContentType(.emailAddress)` errors on this SDK, replace that one line with `.textContentType(nil)` and re-build — it's a cosmetic autofill hint; note the substitution in the report. The original file used `.textContentType(.emailAddress)` and compiled, so it is expected to build as written.)

- [ ] **Step 3: Full test suite (nothing regressed)**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **` (the existing suite incl. `SignInStepTests` stays green; no new tests — this is a view re-skin).

- [ ] **Step 4: Confirm the auth wiring survived (grep sanity)**

```bash
cd ~/Documents/codepet-rebuild-wt
F=codepet/Views/Onboarding/ReturningSignInView.swift
for c in "signInWithGoogle" "signInWithEmail(email:" "signUpWithEmail(email:" "sendPasswordReset(email:" "isGuestMode = true"; do
  printf '%s -> ' "$c"; grep -c "$c" "$F"
done
```
Expected: each count ≥ 1 (all five auth calls still present).

- [ ] **Step 5: Commit (background — iCloud)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Views/Onboarding/ReturningSignInView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: ReturningSignInView — dark cinematic web sign-in (auth.jpg + light card)" \
  -m "Faithful port of web SignIn.tsx; preserves Google/email/sign-up/forgot-password/guest wiring. View-layer only." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(Confirm `git log --oneline -1` shows the commit; re-run on hang.)

---

## Final verification
`ReturningSignInView` renders the dark `auth.jpg` cosmic world + light rise-in card; `ContentView`'s call site is unchanged; the whole pre-app flow (splash → sign-in → onboarding) is one continuous dark cinematic world. All five `AuthManager` calls present (Step 4 grep). Build + full suite green. Manual smoke: Google / email sign-in / sign-up-with-name / forgot-password (+ empty-email guard + reset-sent line) / guest all still fire; toggle flips copy; error line shows in rose.

## Self-Review
**Spec coverage:** dark bg + auth.jpg + vignette (Task 2 body ✓); light rise-in card (card + appear/offset ✓); pixel Codepet brand (✓); sub copy sign-in/up (✓); Google button (✓); or divider (✓); name(signup)/email/password placeholder inputs + purple focus ring via @FocusState (field() ✓); forgot-password sign-in-only + empty guard + reset-sent (✓); submit accent/dim/spinner/disabled (✓); mode toggle clears error+reset (✓); guest below card (✓); reduce-motion static bg (✓); auth.jpg asset import (Task 1 ✓); English-only + exact copy (Global Constraints ✓); view-layer-only auth preserved (Global Constraints + Step-4 grep ✓).

**Placeholder scan:** none — full file in Step 1; every command has expected output.

**Type consistency:** `Field` enum (`.name/.email/.password`) defined once, used in `field(id:)` + `@FocusState focus`. `emailReady` matches the spec formula. `signUpWithEmail(email:password:name:)` called with a non-optional `String` (`name.isEmpty ? appState.displayName : name`) — matches the verified signature. Colors all from the Global-Constraints map or the named new literals. `field(_:text:id:secure:isEmail:)` signature is self-consistent between definition and its three call sites.

**Known notes for the executor:** (a) no new unit tests — SwiftUI view re-skin, verified by build + the unchanged full suite; (b) controller transcribes the file verbatim, verifies FOREGROUND, commits in background (iCloud); reviewers are the gate; (c) the only conditional is the `.textContentType(.emailAddress)` fallback in Step 2 (expected to compile as-is).
