# Onboarding / Chrome Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Checkbox (`- [ ]`) steps.

**Goal:** Port four small client-only polish items to native (parity with web): name autofocus + Enter-to-advance, return-to-splash on sign-out, per-step art color-grade, and cold-open Starfield + pointer parallax.

**Architecture:** Four independent SwiftUI changes; no backend/CF, no deploy. Verified by `xcodebuild build` (SwiftUI views aren't unit-tested) + one pure-logic test for the parallax `clampNorm`.

**Tech Stack:** Swift, SwiftUI, XCTest.

## Global Constraints

- Branch `feat/onboarding-polish` (off `origin/main`). Work in `~/Documents/Murror/codepet`.
- Client-only; no CF/schema/deploy. Respect `@Environment(\.accessibilityReduceMotion)` (existing convention in OnboardingColdOpen) for the animated items (grade is static; Starfield/parallax gate on reduce-motion).
- Build/verify: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` (foreground). Xcode 26.2 hosted-test teardown caveat applies to any @MainActor test; the only test here (`clampNorm`) is struct/free-function → runs clean.

---

### Task 1: Name autofocus + Enter-to-advance

**Files:** Modify `codepet/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Add focus state + wire the name field**

Add to `OnboardingView` (near its other `@State`):
```swift
    @FocusState private var nameFocused: Bool
```
At the name-field call site (step 1, ~line 104), attach focus + submit (do NOT modify the shared `textField` helper):
```swift
                textField("e.g. Mona", text: $d.name)
                    .focused($nameFocused)
                    .onSubmit { if !d.name.trimmed.isEmpty { step = 2 } }
```
Autofocus on entering step 1 — add an `.onChange(of: step)` on the top-level content container (the `Group`/`card` in `body`, ~line 46):
```swift
            .onChange(of: step) { newStep in
                nameFocused = (newStep == 1)
            }
```
(If focus doesn't take on the very first appearance of step 1, wrap the assignment in `Task { @MainActor in nameFocused = (newStep == 1) }`; verify by building + the reviewer/PM noting the visual. Also set it on first appearance if step starts at 1 — add `.onAppear { if step == 1 { nameFocused = true } }` on the same container.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`. (Focus/submit behavior is visual — confirmed at runtime by the product owner.)

- [ ] **Step 3: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/OnboardingView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: onboarding name autofocus + Enter-to-advance

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Return-to-splash on sign-out

**Files:** Modify `codepet/App/ContentView.swift`

- [ ] **Step 1: Flip `showSplash` on a real sign-out**

In the `.onReceive(authManager.$currentUser)` handler (~line 77), the sign-out branch is `guard let user = user else { ... return }` (~lines 78-83). Add, inside that else (before `return`):
```swift
        guard let user = user else {
            // Real sign-out (authed → nil): return to the brand splash before the
            // sign-in screen, mirroring web Gate's wasAuthed/splashSeen. Guard on a
            // persisted prior sign-in so the initial cold-null doesn't re-splash.
            if PersistenceManager.shared.currentUserId != nil {
                withAnimation { showSplash = true }
            }
            return
        }
```
(Read the exact current else-body first and keep its existing statements; only add the `if … { showSplash = true }`. If `PersistenceManager.shared.currentUserId` isn't the right signal, add `@State private var wasAuthed = false`, set it `true` in the `let user = user` success path, and guard on `wasAuthed` instead — a 1:1 port of the web ref.)

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/App/ContentView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: return to splash on sign-out (web parity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Per-step art color-grade overlay

**Files:** Modify `codepet/Models/OnboardingContent.swift`, `codepet/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Add the `stepGrade` palette (ported from web STEP_GRADE)**

In `codepet/Models/OnboardingContent.swift`, near `stepArt` (~line 50), add (requires `import SwiftUI` — add it if the file only imports Foundation):
```swift
    /// Per-step colour grade over the art panel (web STEP_GRADE), applied soft-light. Steps 0...8.
    static let stepGrade: [Color] = [
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.28), // 0
        Color(red: 255/255, green: 157/255, blue: 107/255).opacity(0.24), // 1
        Color(red: 110/255, green: 168/255, blue: 255/255).opacity(0.24), // 2
        Color(red: 79/255,  green: 224/255, blue: 207/255).opacity(0.24), // 3
        Color(red: 208/255, green: 140/255, blue: 245/255).opacity(0.26), // 4
        Color(red: 242/255, green: 201/255, blue: 76/255 ).opacity(0.22), // 5
        Color(red: 126/255, green: 168/255, blue: 255/255).opacity(0.26), // 6
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.26), // 7
        Color(red: 124/255, green: 58/255,  blue: 237/255).opacity(0.26), // 8
    ]
```

- [ ] **Step 2: Overlay it on the art Image**

In `OnboardingView.swift`, the art panel Image (~lines 60-65): add the overlay before `.id(step)`:
```swift
            .overlay(
                OnboardingContent.stepGrade[min(step, OnboardingContent.stepGrade.count - 1)]
                    .blendMode(.softLight)
            )
```
If the soft-light bleeds onto the surrounding surface, add `.compositingGroup()` on the Image immediately before the `.frame(width: 360)` to isolate the blend to the image.

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/OnboardingContent.swift codepet/Views/Onboarding/OnboardingView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: per-step art colour grade (STEP_GRADE parity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Cold-open Starfield + pointer parallax

**Files:** Create `codepet/Views/Onboarding/Starfield.swift`; Modify `codepet/Views/Onboarding/OnboardingColdOpen.swift`; Test `codepetTests/StarfieldParallaxTests.swift`

- [ ] **Step 1: Create `Starfield.swift` (view + testable `clampNorm`)**

```swift
// codepet/Views/Onboarding/Starfield.swift
import SwiftUI

/// Normalize a value within [min,max] to [-1,1] (port of web lib/ui/useParallax clampNorm).
/// Pure + free function so it unit-tests without a view.
func clampNorm(_ value: CGFloat, _ minV: CGFloat, _ maxV: CGFloat) -> CGFloat {
    if maxV <= minV { return 0 }
    let f = ((value - minV) / (maxV - minV)) * 2 - 1
    return max(-1, min(1, f))
}

/// 40 deterministic drifting dots — port of web components/ui/Starfield.tsx. Gated on
/// reduce-motion. Purely decorative (no hit testing).
struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Dot: Identifiable { let id: Int; let x, y, size, dur, delay: Double }
    private static let dots: [Dot] = (0..<40).map { i in
        Dot(id: i, x: Double((i*37)%100), y: Double((i*61)%100),
            size: 1 + Double(i%3), dur: 6 + Double(i%5)*2, delay: Double(i%7)*0.9)
    }
    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                ZStack {
                    ForEach(Self.dots) { d in
                        TwinklingDot(dot: d)
                            .position(x: geo.size.width * d.x/100, y: geo.size.height * d.y/100)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
    fileprivate struct TwinklingDot: View {
        let dot: Dot
        @State private var bright = false
        var body: some View {
            Circle()
                .fill(Color.white.opacity(bright ? 0.9 : 0.25))
                .frame(width: dot.size, height: dot.size)
                .onAppear {
                    withAnimation(.easeInOut(duration: dot.dur).repeatForever(autoreverses: true).delay(dot.delay)) {
                        bright = true
                    }
                }
        }
    }
}
```

- [ ] **Step 2: Test `clampNorm`**

Create `codepetTests/StarfieldParallaxTests.swift`:
```swift
import XCTest
@testable import codepet

final class StarfieldParallaxTests: XCTestCase {
    func testClampNormMapsRangeToMinusOneToOne() {
        XCTAssertEqual(clampNorm(0, 0, 100), -1, accuracy: 0.001)   // min → -1
        XCTAssertEqual(clampNorm(100, 0, 100), 1, accuracy: 0.001)  // max → +1
        XCTAssertEqual(clampNorm(50, 0, 100), 0, accuracy: 0.001)   // mid → 0
    }
    func testClampNormClampsOutOfRangeAndDegenerate() {
        XCTAssertEqual(clampNorm(-50, 0, 100), -1, accuracy: 0.001) // below → -1
        XCTAssertEqual(clampNorm(200, 0, 100), 1, accuracy: 0.001)  // above → +1
        XCTAssertEqual(clampNorm(5, 10, 10), 0, accuracy: 0.001)    // max<=min → 0
    }
}
```

- [ ] **Step 3: Wire Starfield + parallax into the cold-open**

In `OnboardingColdOpen.swift`, add state (near line 10):
```swift
    @State private var px: CGFloat = 0
    @State private var py: CGFloat = 0
```
Inside the root `ZStack` (~line 13), layer `Starfield()` above the scrim and add a pointer-parallax offset to it (and a smaller one to the Ken-Burns image for depth). Wrap the ZStack content so bounds are available, and add `.onContinuousHover` on the ZStack:
```swift
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // ... existing coldBg + Ken-Burns Image + scrim ...
                //   add to the Image: .offset(x: px * 6, y: py * 6)
                Starfield()
                    .offset(x: px * 14, y: py * 14)
            }
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                switch phase {
                case .active(let p):
                    withAnimation(.easeOut(duration: 0.25)) {
                        px = clampNorm(p.x, 0, geo.size.width)
                        py = clampNorm(p.y, 0, geo.size.height)
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.4)) { px = 0; py = 0 }
                }
            }
        }
```
(Read the current OnboardingColdOpen body first; preserve the existing `coldBg`, Ken-Burns `Image`, gradient scrim, and skip/CTA content — only add the `GeometryReader` wrapper, the `Starfield()` layer, the two `.offset`s, and `.onContinuousHover`. `reduceMotion` is the existing `@Environment(\.accessibilityReduceMotion)` at line 10.)

- [ ] **Step 4: Run test + build**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/StarfieldParallaxTests`
then `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: test passes (free function → clean) + `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Onboarding/Starfield.swift codepet/Views/Onboarding/OnboardingColdOpen.swift codepetTests/StarfieldParallaxTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: cold-open starfield + pointer parallax

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Scope:** 4 independent client-only items; no CF/deploy. Item 1 → OnboardingView; Item 2 → ContentView; Item 3 → OnboardingContent+OnboardingView; Item 4 → new Starfield + OnboardingColdOpen. ✓
**Placeholders:** concrete code for each; the reduce-motion gate + compositing/focus-timing gotchas are called out with the fallback. ✓
**Tests:** SwiftUI views are build-verified (visual behavior confirmed at runtime); the one pure function (`clampNorm`) is unit-tested. ✓
**New infra flag:** Task 4 is the largest (net-new Starfield view + parallax); if it regresses the cold-open, it can ship without the others (each task is independent).
