# Purple Surface Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the app's surface and text family from warm brown-on-cream to the prototype's cool purple ground, in both light and dark mode, without touching a single accent.

**Architecture:** Task 1 is the load-bearing one and changes no colours at all: it makes the four pixel guards **palette-independent** by comparing against a reference render pushed through the identical `ImageRenderer` pipeline, instead of against hardcoded hexes. That collapses the colour-management noise floor to ~0 and means the retint in Task 2 does not invalidate a single threshold. Tasks 3–5 then handle the one view edit, a duplicate token block, and the roadmap's relative surfaces.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. No new dependencies, no `functions/` change, no API cost.

**Spec:** `docs/superpowers/specs/2026-08-22-purple-surface-palette-design.md`. Read the "rail level the app does not have" section before Task 3 — that is where the one non-retint edit lives and why.

## Global Constraints

- **Swift only.** No file under `functions/` may be touched.
- **Accents are out of scope, entirely.** `accentPurple`, `accentPink`, `accentGold`, `accentTeal`, `accentOrange`, `accentBlue`, `accentGreen`, and all six per-department tint/line triads (`violet`/`gold`/`blue`/`teal`/`clay`/`rose` × base/tint/line) keep their current values. Each department answers in its own hue and `DepartmentRoster` keeps `dep.accent` for that reason. If a task's diff touches an accent, that task is wrong.
- **No pixel threshold may be written by hand.** Six were hand-written during the previous plan and all six were wrong. Every threshold here either comes from a measured RED/GREEN pair with both numbers in a comment beside it, or is eliminated by Task 1's reference-render approach.
- **Zero is not the noise floor.** Before Task 1, a flat dark corner measures `0.0597` from its ideal hex through `ImageRenderer` → `NSBitmapImageRep` → `.usingColorSpace(.sRGB)`; flat cream measures `0.0214`. Task 1 exists to make that irrelevant. Do not reintroduce a comparison against an ideal hex.
- **A nil render must `XCTFail` plus throw — never `throw XCTSkip`.** A skip lets CI go green with the guard silently gone. `XCTFail` returns `Void`, so a non-`Void` throwing helper needs both a recorded failure and a `throw`.
- **Saturation from RGB channels** (`(max - min) / max`), never `NSColor.saturationComponent`, which raises outside an HSB-compatible colour space.
- **`ImageRenderer` renders NOTHING inside a `ScrollView`.** Every view rendered here is on a path with none.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Render tests are `@MainActor`.
- **Count tests with `xcresulttool`**, never by grepping the log.
- **Locate every anchor by `grep`, never by line number.** Seven line references went stale during the previous plan because a concurrent session edits this repo continuously.

**Known false-peak sources in this render pipeline** — check for these before trusting any measurement:

- `Menu(...).menuStyle(.borderlessButton)` renders as a **full-saturation yellow "not allowed" glyph** under `ImageRenderer`. A reproducible AppKit/SwiftUI defect.
- Dark chrome fills read as saturated: `bodyText` measures ~0.235.
- A `.frame(width:height:)` with no `alignment` defaults to `.center`, so an oversized `VStack` renders a **cropped middle slice**. One guard in this suite was measuring the wrong view entirely because of it.
- `@AppStorage`-backed state changes what is inside a crop. `testTheActiveModeSegmentHasPurpleBody` pins `WorkspaceMode.seenDeveloperKey` for that reason.

**Per-suite test command:**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/SUITE_NAME \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

`-derivedDataPath build/dd-ci` is load-bearing: without it the unsigned test build overwrites the signed `codepet.app` and Firebase sign-in silently breaks for the next human launch. **Never run two `xcodebuild` invocations at once**; if you hit a DB-lock collision with the concurrent session's build, wait it out rather than retrying blind.

**Full suite, required before the PR:** `./scripts/ci-test.sh` — **1721/1721 green when this plan was written.** Take the current number from `.superpowers/sdd/progress.md`, not this line.

**`codepet.app` may be running and belongs to a concurrent session. Do not kill it.** Its Firestore lock can kill the test host; the symptom is tests failing to *finish*, not spurious passes. Wait and retry.

**Shared-worktree rules — these caused real damage during the previous plan:**

- Stage by explicit path only. **Never** `git add -A`, `git add .`, or `git commit -a`.
- **Leave nothing staged between steps.** The sibling session's commit swept a staged deletion once and produced a commit that does not compile.
- After committing, confirm `git diff --cached --name-only` is empty. A broken `&&` chain has silently left files staged here.
- If you temporarily edit a file to measure a state, **restore it exactly** and prove it with `git diff --stat <file>` showing no change before committing.

---

## File structure

| File | Change | Responsibility after |
|---|---|---|
| `codepetTests/BrandMarkRenderTests.swift` | Task 1 | corner + bloom guards, palette-independent |
| `codepetTests/ComposerEdgeRenderTests.swift` | Task 1 | edge + mode-segment guards, palette-independent |
| `codepet/Views/CodepetTheme.swift` | Task 2 | 6 surface/text pairs, cool |
| `codepet/Views/CodepetTokens.swift` | Task 2, Task 5 | 10 surface/line pairs cool; roadmap's relative surfaces |
| `codepet/Views/Shell/TwoModeSidebar.swift` | Task 3 | sidebar sits on the rail level |
| `codepet/Models/OnboardingContent.swift` | Task 4 | reads the shared tokens instead of duplicating them |
| `codepetTests/RoadmapPaletteTests.swift` | Task 5 | asserts the board-card *relationship*, not a hex |

Task 1 comes first for one reason: after it, the retint in Task 2 invalidates no thresholds. Doing it in the other order means re-measuring six numbers against a palette that is itself changing.

---

### Task 1: Make the pixel guards palette-independent

Changes no colours. This is a pure test refactor that must leave all seven existing assertions passing, and it is what lets Task 2 be a simple retint.

**Files:**
- Modify: `codepetTests/BrandMarkRenderTests.swift`
- Modify: `codepetTests/ComposerEdgeRenderTests.swift`

**Interfaces:**
- Produces, in **both** files (each file gets its own copy — they are separate `XCTestCase` classes and cannot share a private helper):
  - `referenceGround(colorScheme: ColorScheme, width: CGFloat, height: CGFloat) throws -> NSColor` — renders a bare rectangle filled with `CodepetTheme.pageBackground` through the same `ImageRenderer` at the same scale, and returns its centre pixel.
  - `enum RenderFailure: Error { case producedNothing }` already exists in `BrandMarkRenderTests`; add the same to `ComposerEdgeRenderTests` if it lacks one.
- Tasks 2–5 rely on these guards continuing to pass without threshold edits.

- [ ] **Step 1: Add the reference-render helper to `BrandMarkRenderTests.swift`**

Put it beside the existing `renderChatPane(colorScheme:)`:

```swift
    /// The ground's value AFTER the render pipeline has had its way with it.
    ///
    /// Comparing a sampled pixel against an ideal hex does not work: a flat dark
    /// corner measures 0.0597 away from `#16130f` and flat cream 0.0214, purely from
    /// colour management through `ImageRenderer` → `NSBitmapImageRep` →
    /// `.usingColorSpace(.sRGB)`. Thresholds then have to straddle that floor, which
    /// is how the dark corner guard came to pass by 0.47%.
    ///
    /// Pushing a bare `pageBackground` rectangle through the IDENTICAL pipeline
    /// returns the same distorted value the real render produces, so the distortion
    /// cancels and the comparison is against the colour as rendered. It also means
    /// this guard no longer knows or cares what `pageBackground` actually is.
    @MainActor
    private func referenceGround(colorScheme: ColorScheme,
                                width: CGFloat, height: CGFloat) throws -> NSColor {
        let swatch = Rectangle()
            .fill(CodepetTheme.pageBackground)
            .frame(width: width, height: height)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: swatch)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
                  .usingColorSpace(.sRGB) else {
            XCTFail("reference ground render produced nothing")
            throw RenderFailure.producedNothing
        }
        return c
    }
```

- [ ] **Step 2: Point both corner tests at the reference**

In `testTheChatGroundIsFlatInDark`, replace the hardcoded ground and threshold. Find it with `grep -n "let ground = NSColor(srgbRed: 0x16" codepetTests/BrandMarkRenderTests.swift`:

```swift
        let ground = try referenceGround(colorScheme: .dark, width: 760, height: 560)
        let corners = cornerSamples(rep, inset: 40 * 2)
        XCTAssertEqual(corners.count, 4, "could not sample four corners")
        for c in corners {
            let d = abs(c.redComponent - ground.redComponent)
                + abs(c.greenComponent - ground.greenComponent)
                + abs(c.blueComponent - ground.blueComponent)
            // 0.01, not 0.072. The reference cancels the ~0.0597 colour-management
            // offset the old ideal-hex comparison had to straddle, so a genuinely flat
            // corner now measures ~0. This is roughly 8x tighter than the old
            // threshold and catches a wash at a small fraction of the original 0.16
            // opacity — where 0.072 needed about 70% of it.
            XCTAssertLessThan(d, 0.01,
                              "the pane's corner is not flat pageBackground — an ambient "
                              + "wash is painting over it. See \(url.path)")
        }
```

Do the same in `testTheChatGroundIsFlatInLight`, with `colorScheme: .light` and the same `0.01`. The two thresholds are now allowed to match, because the per-scheme noise floors that forced them apart are gone.

- [ ] **Step 3: Run both corner tests — they must still pass**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
pgrep -x codepet >/dev/null && echo "NOTE: sibling's app is running; do NOT kill it"
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **4 passed, 0 failed, 0 skipped.**

If a corner test fails, print the measured `d` and the reference's RGB before changing anything — a non-zero `d` here means the reference render is not going through the same pipeline as the pane render (different scale, different colour space) and the helper is wrong, not the threshold.

- [ ] **Step 4: Make the bloom test's background exclusion reference-based**

`testTheBloomCarriesTheBrandsSecondStop` currently excludes near-background pixels using `backgroundEpsilon: CGFloat = 0.08`, a value chosen to clear the 0.0597 floor. With a reference, the epsilon can be small and honest. Find the constant with `grep -n "backgroundEpsilon" codepetTests/BrandMarkRenderTests.swift` and replace the ground it compares against:

```swift
        // Reference-based, so this epsilon no longer has to clear a 0.0597
        // colour-management floor — it only has to clear per-pixel dither. The old
        // 0.08 was three-quarters noise budget.
        let ground = try referenceGround(colorScheme: .dark, width: 760, height: 420)
        let backgroundEpsilon: CGFloat = 0.02
```

Keep the `+ 0.02` warm-test margin and the `13_300` threshold untouched for now — Step 5 re-measures the threshold, because tightening the exclusion admits fewer background pixels and the count will drop.

- [ ] **Step 5: Re-measure the bloom's RED and GREEN, then set the threshold**

The exclusion change moves the count, so the old `13_300` is stale. Measure both states by actually editing the production file, exactly as the previous pass did:

1. Add `print("[measure] warm=\(warmPixels)")` above the assertion. Run the single test. Record — this is GREEN.
2. In `codepet/Views/Copilot/ChatEmptyState.swift`, temporarily delete the line `CodepetTheme.accentPink.opacity(0.18),` so the bloom is purple → clear. Run again. Record — this is RED.
3. **Restore `ChatEmptyState.swift` exactly** and prove it: `git diff --stat codepet/Views/Copilot/ChatEmptyState.swift` must show no change.
4. Remove the `print`. Set the threshold between the two with real headroom, and write both measured numbers into the comment.

For reference, the previous pass measured RED 8,329 / GREEN 18,285 with the 0.08 epsilon. **If your new separation is under about 2x, stop and report it** rather than shipping a squeezed guard.

- [ ] **Step 6: Add the same helper to `ComposerEdgeRenderTests.swift` and use it in the mode-segment test**

`testTheActiveModeSegmentHasPurpleBody` counts pixels where `c.blueComponent > c.greenComponent + 0.04 && saturation(c) > 0.08`. That metric is about to become dangerous: the new dark ground `#121019` has G=0x10 and B=0x19, a blue lead of 0.035 — just under the 0.04 margin. A small shift and every background pixel counts.

Add the helper (same code as Step 1, with its own `RenderFailure` if the file lacks one) and exclude near-reference pixels before the violet test:

```swift
        let ground = try referenceGround(colorScheme: .light, width: 240, height: 130)
        var violet = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Skip the ground itself. Today's cream ground is nowhere near the
                // blue>green test, but the palette is about to become COOL — #121019
                // has a blue lead of 0.035 against this 0.04 margin — so counting
                // background would flood this the moment the retint lands.
                let dg = abs(c.redComponent - ground.redComponent)
                    + abs(c.greenComponent - ground.greenComponent)
                    + abs(c.blueComponent - ground.blueComponent)
                if dg < 0.02 { continue }
                if c.blueComponent > c.greenComponent + 0.04 && saturation(c) > 0.08 {
                    violet += 1
                }
            }
        }
```

- [ ] **Step 7: Re-measure the mode segment's RED and GREEN**

Same procedure, on `codepet/Views/Shell/TwoModeSidebar.swift`:

1. `print("[measure] violet=\(violet)")` above the assertion, run, record GREEN.
2. Temporarily remove the purple overlay `.fill(mode == m ? CodepetTheme.accentPurple.opacity(0.10) : .clear)` and the `accentPurple.opacity(0.45)` stroke so only the accented text remains. Run, record RED.
3. **Restore the file exactly** and prove it with `git diff --stat`.
4. Remove the `print`, set the threshold between them, write both numbers into the comment.

Previous pass measured RED 408 / GREEN 1492 with no exclusion. **Under about 2x separation, stop and report.**

- [ ] **Step 8: Run both suites**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **7 passed, 0 failed, 0 skipped** (4 + 3).

- [ ] **Step 9: Commit**

```bash
git add codepetTests/BrandMarkRenderTests.swift codepetTests/ComposerEdgeRenderTests.swift
git status --porcelain   # confirm ONLY those two are staged
git commit -m "$(cat <<'EOF'
test: compare against a reference render, not an ideal hex

These guards compared sampled pixels to hardcoded hexes, so every threshold had
to straddle a colour-management floor — 0.0597 in dark, 0.0214 in cream, purely
from ImageRenderer → NSBitmapImageRep → .usingColorSpace(.sRGB). That is how the
dark corner guard came to pass by 0.47%.

Pushing a bare pageBackground rectangle through the identical pipeline returns
the same distorted value the real render produces, so the distortion cancels.
The corner threshold drops from 0.072 to 0.01 — about 8x tighter — and the two
schemes can share one number now that the per-scheme floors are gone.

The guards also stop knowing what the palette IS, which is the point: a retint
no longer invalidates them.

The mode-segment count gains the same exclusion for a specific reason: the ground
is about to become cool, and #121019's blue lead of 0.035 sits just under that
test's 0.04 blue>green margin. Counting background would have flooded it the
moment the palette changed.

No colours changed. 7 passed / 0 failed / 0 skipped.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 2: Retint the surface and text family

**Files:**
- Modify: `codepet/Views/CodepetTheme.swift`
- Modify: `codepet/Views/CodepetTokens.swift`
- Test: `codepetTests/AppThemeTests.swift`

**Interfaces:**
- Consumes: Task 1's reference-based guards, which must keep passing untouched.
- Produces: the new values below. Task 3 depends on `CodepetTokens.surface2` being `#171420` in dark, and Task 5 depends on `CodepetTheme.surface` being `#1d1928` in dark.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/AppThemeTests.swift`. This asserts the ordering that makes the palette work, not just the values — a hex assertion alone would pass on a typo that broke the hierarchy:

```swift
    /// The dark surfaces must form a strict ladder, because the mode switch depends on
    /// it: a track darker than the rail, a card lighter than the rail. Before this
    /// retint the app inset by going LIGHTER (`well` #26211a was brighter than
    /// `surface` #221d17, and `cardRaised` #26201a was within one hex digit of `well`),
    /// which is why the active segment needed purple body added to read as selected.
    func testDarkSurfacesFormALadder() {
        func lum(_ hex: String) -> CGFloat {
            let c = NSColor(hex: hex).usingColorSpace(.sRGB)!
            return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        }
        // well (track) < rail < panel (card)
        XCTAssertLessThan(lum("#121019"), lum("#171420"), "the track must be darker than the rail")
        XCTAssertLessThan(lum("#171420"), lum("#1d1928"), "the card must be lighter than the rail")
        XCTAssertLessThan(lum("#1d1928"), lum("#2a2438"), "the hairline must be lighter than the card")
        XCTAssertLessThan(lum("#2a2438"), lum("#3a3350"), "the strong line must be lighter than the hairline")
    }

    /// The ground is COOL now, not warm. This is the single assertion that would catch
    /// a revert to the brown family: `#16130f` had red leading blue by 0.0275;
    /// `#121019` has blue leading red.
    func testTheDarkGroundIsCoolNotWarm() {
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let g = CodepetTheme.dynamicNSColor(light: "#f5f3fa", dark: "#121019")
                .usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(g.blueComponent, g.redComponent,
                                 "the dark ground went warm again — blue must lead red")
        }
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/AppThemeTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: `testDarkSurfacesFormALadder` **PASSES** (it asserts on literals, not on the tokens — it is a guard for later, documenting the intended ladder). `testTheDarkGroundIsCoolNotWarm` also **PASSES** for the same reason. Both are guards against future regression rather than drivers of this change.

That is deliberate and was ruled on during the previous plan: a test that guards a silent failure with no other detector is worth keeping even when it does not drive the implementation. Note it in your report; do not restructure them to force a red state.

- [ ] **Step 3: Retint `CodepetTheme.swift`**

Find each with `grep -n "Color.dyn" codepet/Views/CodepetTheme.swift`. Replace exactly these six, and **nothing else in the file**:

```swift
    /// Page background — the prototype's cool near-black purple (`--app-ground`),
    /// replacing a warm brown-black that made every purple element on it read muddy.
    static let pageBackground = Color.dyn("#f5f3fa", "#121019")

    /// Card / panel surface — `--app-panel`.
    static let surface = Color.dyn("#ffffff", "#1d1928")

    /// Subtle hairline — `--app-line`.
    static let hairline = Color.dyn("#e0dced", "#2a2438")

    /// Headline / primary text — `--app-ink`.
    static let primaryText = Color.dyn("#2d2b26", "#f2eefb")

    /// Body copy — `--app-ink-2`.
    static let bodyText = Color.dyn("#4d4859", "#cec7e0")

    /// Muted text — `--app-muted`.
    static let mutedText = Color.dyn("#746d87", "#8f88a3")
```

Do **not** touch `accentPurple` through `accentGreen` in this file.

- [ ] **Step 4: Retint `CodepetTokens.swift`**

Find each with `grep -n "Color.dyn" codepet/Views/CodepetTokens.swift`. Replace exactly these ten:

```swift
    static let well      = Color.dyn("#efecf7", "#121019")   // --app-ground: the TRACK
    static let surface2  = Color.dyn("#faf9fd", "#171420")   // --app-rail
    static let faint     = Color.dyn("#9a93ab", "#6b6480")   // --app-faint
    static let page      = Color.dyn("#f5f3fa", "#121019")   // --app-ground
```

```swift
    static let cardRaised = Color.dyn("#ffffff", "#1d1928")  // --app-panel: the CARD
    static let cardEdge   = Color.dyn("#cdc6e2", "#3a3350")  // --app-line-2
```

```swift
    static let railFill   = Color.dyn("#cdc6e2", "#2a2438")
    static let railBorder = Color.dyn("#a79ec4", "#3a3350")

    static let railFillHover   = Color.dyn("#bcb3d6", "#332c4a")
    static let railBorderHover = Color.dyn("#9188b0", "#4a4268")
```

Do **not** touch `accentDeep`, `accentTint`, `accentLine`, or any of `violet`/`gold`/`blue`/`teal`/`clay`/`rose` and their tints and lines.

- [ ] **Step 5: Correct the comment that defends the old inset direction**

`CodepetTokens.swift` describes `well`/`cardRaised` as a lifted-out-of-a-track pairing where the well is the lighter value. Find it with `grep -n "well" codepet/Views/CodepetTokens.swift` and correct the direction — the conclusion holds, the direction reverses:

```swift
    /// `well` is the TRACK and is now DARKER than the card that sits in it, which is
    /// the conventional direction and the prototype's. It used to be lighter: `well`
    /// (#26211a) was brighter than `surface` (#221d17) and within one hex digit of
    /// `cardRaised` (#26201a), so "a card lifted out of a track" had almost no
    /// contrast to work with — part of why the active mode segment needed purple body
    /// added before it read as selected.
```

- [ ] **Step 6: Run the theme suite and both render suites**

The render guards are the real test of this task: after Task 1 they should pass **unchanged** against a completely different palette. That is the whole point.

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/AppThemeTests \
  -only-testing:codepetTests/BrandMarkRenderTests \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  -only-testing:codepetTests/DynamicColorTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: all pass, 0 failed, 0 skipped.

**If a render guard fails here, do not adjust its threshold.** It means Task 1's reference approach did not fully decouple it, which is information worth more than a green run — report the measured numbers and stop.

- [ ] **Step 7: Commit**

```bash
git add codepet/Views/CodepetTheme.swift codepet/Views/CodepetTokens.swift codepetTests/AppThemeTests.swift
git status --porcelain   # confirm ONLY those three are staged
git commit -m "$(cat <<'EOF'
feat(theme): the surfaces go cool

Sixteen pairs move from a warm brown-on-cream family to the prototype's cool
purple: ground #16130f → #121019, panel #221d17 → #1d1928, lines, and the four
text levels. Light takes the prototype's own light :root, since its app palette
is explicitly dark-only and inventing a second purple family would be worse.

The inset direction reverses. `well` was LIGHTER than `surface` and within one
hex digit of `cardRaised`, so "a card lifted out of a track" had almost no
contrast — part of why the active mode segment needed purple body before it read
as selected. The track is now darker than the card, as the prototype has it.

Accents are untouched, deliberately: each department answers in its own hue.

The render guards passed unchanged against an entirely different palette, which
is what the previous commit's reference-render refactor was for.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 3: Give the sidebar the rail level

The one view edit in this plan. Read the spec's "rail level the app does not have" section first.

**Files:**
- Modify: `codepet/Views/Shell/TwoModeSidebar.swift`
- Test: `codepetTests/ComposerEdgeRenderTests.swift`

**Interfaces:**
- Consumes: `CodepetTokens.surface2` = `#171420` dark, `#faf9fd` light (Task 2).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Without this edit the sidebar and the lifted card are the same colour, so the mode switch has a visible track and an invisible card. Add to `codepetTests/ComposerEdgeRenderTests.swift`:

```swift
    /// The mode switch needs THREE distinct surfaces: the rail it sits on, the track
    /// beneath it, and the card lifted above. The prototype has all three
    /// (--app-rail / --app-ground / --app-panel); this app collapsed "sidebar" and
    /// "card" into one `surface` token, so after the retint the lifted card would be
    /// byte-identical to the sidebar behind it — a track you can see and a card you
    /// cannot.
    ///
    /// Asserts the three are pairwise distinct in DARK, where they collide. In light
    /// `surface`/`cardRaised` are #ffffff and `surface2` is #faf9fd, which never
    /// collided.
    func testTheSidebarRailIsDistinctFromTrackAndCard() {
        func lum(_ c: NSColor) -> CGFloat {
            let s = c.usingColorSpace(.sRGB)!
            return 0.2126 * s.redComponent + 0.7152 * s.greenComponent + 0.0722 * s.blueComponent
        }
        // Resolve via `dynamicNSColor` with the hex pair, NOT `NSColor(someColor)`.
        // Bridging a SwiftUI `Color` to `NSColor` can resolve eagerly, outside the
        // appearance block, and would then silently read the LIGHT value while
        // claiming to test dark. `DynamicColorTests` established this pattern.
        func darkLum(light: String, dark: String) -> CGFloat {
            var v: CGFloat = -1
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                v = lum(CodepetTheme.dynamicNSColor(light: light, dark: dark))
            }
            return v
        }
        let rail  = darkLum(light: "#faf9fd", dark: "#171420")   // surface2
        let track = darkLum(light: "#efecf7", dark: "#121019")   // well
        let card  = darkLum(light: "#ffffff", dark: "#1d1928")   // cardRaised
        XCTAssertLessThan(track, rail, "the track must be darker than the rail it sits on")
        XCTAssertLessThan(rail, card, "the card must be lighter than the rail behind it")
        XCTAssertGreaterThan(abs(card - rail), 0.005,
                             "the card is indistinguishable from the rail — the sidebar "
                             + "is still on `surface`, so the mode switch has no visible card")
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests/testTheSidebarRailIsDistinctFromTrackAndCard \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **PASSES**, because it asserts on the token ladder Task 2 already established, not on which token the sidebar uses. It is a guard for the ladder, and the *sidebar's* use of it cannot be asserted from tokens alone — see Step 4.

- [ ] **Step 3: Point the sidebar at the rail level**

Find it with `grep -n "background(CodepetTheme.surface)" codepet/Views/Shell/TwoModeSidebar.swift`:

```swift
        // The sidebar is the RAIL, not a card. `surface2` is `--app-rail`, one step
        // between the track (`well`) beneath the mode switch and the card
        // (`cardRaised`) lifted inside it. On `surface` the sidebar and the lifted
        // card were the same value, so the switch had a visible track and an
        // invisible card.
        .background(CodepetTokens.surface2)
```

- [ ] **Step 4: Verify the three surfaces are actually distinct on screen**

The token test cannot see which token the sidebar uses, so confirm the rendered result. Add a temporary print to `testTheActiveModeSegmentHasPurpleBody`, which already renders `TwoModeSidebar` at `240x130` with `alignment: .top`:

```swift
        print("[measure] distinct greys=\(Set(
            (0..<rep.pixelsHigh).flatMap { y in
                (0..<rep.pixelsWide).compactMap { x in
                    rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB).map {
                        Int($0.redComponent * 255) << 16 | Int($0.greenComponent * 255) << 8 | Int($0.blueComponent * 255)
                    }
                }
            }).count)")
```

Run the test, record the number, then **remove the print**. Report it. This is a sanity signal, not an assertion: a render containing rail, track, and card should show meaningfully more distinct values than one where two of the three coincide.

- [ ] **Step 5: Run the suite**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **4 passed, 0 failed, 0 skipped.**

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Shell/TwoModeSidebar.swift codepetTests/ComposerEdgeRenderTests.swift
git status --porcelain   # confirm ONLY those two are staged
git commit -m "$(cat <<'EOF'
feat(shell): the sidebar is the rail, not a card

The prototype has three surfaces where this app had two. Its mode switch works
because the rail, the track beneath it, and the card lifted inside it are all
different values; here "sidebar" and "card" were the same `surface` token, so
after the retint the lifted card was byte-identical to the sidebar behind it —
a track you can see and a card you cannot.

One line: the sidebar takes `surface2` (--app-rail). Found in spec self-review
rather than on screen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 4: Collapse the duplicate palette

**Files:**
- Modify: `codepet/Models/OnboardingContent.swift`

**Interfaces:**
- Consumes: `CodepetTokens.surface2`, `CodepetTokens.well`, `CodepetTokens.faint` (Task 2).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Find every consumer of the duplicated names**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
grep -rn "Palette.surface2\|Palette.well\|Palette.faint" --include="*.swift" .
```

Record the list. Every one must still compile after Step 2.

- [ ] **Step 2: Point the duplicates at the shared tokens**

`OnboardingContent.Palette` re-declares three tokens with byte-identical warm hexes, under a comment claiming they are vars `CodepetTheme` does not expose. They **are** exposed, in `CodepetTokens` — so this was a second source of truth, and retinting one without the other would have split the palette. Find it with `grep -n "enum Palette" codepet/Models/OnboardingContent.swift` and replace those three lines:

```swift
    /// Web CSS theme vars mapped 1:1. Three of these used to be re-declared here with
    /// their own hex literals, duplicating `CodepetTokens` — the comment claimed
    /// `CodepetTheme` did not expose them, which was not true. A retint of one and not
    /// the other would have split the palette silently, so they now alias the shared
    /// tokens. The accent trio below IS still duplicated; it is out of scope for the
    /// surface retint and left as-is deliberately.
    enum Palette {
        static let surface2   = CodepetTokens.surface2
        static let well       = CodepetTokens.well
        static let faint      = CodepetTokens.faint
        static let accentDeep = Color.dyn("#5b27b0", "#7c3aed")   // --accent-deep
        static let accentTint = Color.dyn("#eee6fd", "#271f3a")   // --accent-tint
        static let accentLine = Color.dyn("#d9c9f7", "#43356b")   // --accent-line
        static let coldBg     = Color(hex: "#100a26")             // cold-open / splash — STAYS dark
    }
```

`coldBg` (`#100a26`) is already a deep purple and stays exactly as it is — it was the one part of the app that had the right hue family all along.

- [ ] **Step 3: Build to confirm every consumer still compiles**

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

- [ ] **Step 4: Run the onboarding suite**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/AppThemeTests \
  -only-testing:codepetTests/DynamicColorTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: all pass, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/OnboardingContent.swift
git status --porcelain   # confirm ONLY that one is staged
git commit -m "$(cat <<'EOF'
refactor(onboarding): one palette, not two

OnboardingContent.Palette re-declared surface2, well and faint with hex literals
byte-identical to CodepetTokens', under a comment saying CodepetTheme did not
expose them. It did. Retinting one and not the other would have split the palette
with nothing failing to say so — found by grepping for the warm hexes, not by
reading the token files.

The accent trio stays duplicated: accents are out of scope for the surface
retint, and collapsing them is its own decision. coldBg (#100a26) stays too — it
was already the right hue family.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 5: The roadmap's relative surfaces

**Files:**
- Modify: `codepet/Views/CodepetTokens.swift` (the `RoadmapTokens` hex pairs)
- Test: `codepetTests/RoadmapPaletteTests.swift`

**Interfaces:**
- Consumes: `CodepetTheme.surface` = `#1d1928` dark, `CodepetTokens.cardRaised` = `#1d1928` dark (Task 2).
- Produces: nothing.

- [ ] **Step 1: Replace the hex assertions with the relationship they stand for**

`RoadmapPaletteTests` asserts `chipBGHex.light == "#f1efe9"` and `chipBorderHex.light == "#ece9e2"`, and that `cardBGHex.dark != "#26201a"`. Those literals break on this change, but the *invariant* behind them is what matters — `RoadmapTokens`' own comment says the board card is deliberately lighter than both `surface` and `cardRaised` so cards keep a visible edge. Assert that instead. Find the tests with `grep -n "chipBGHex\|cardBGHex" codepetTests/RoadmapPaletteTests.swift`:

```swift
    /// The board's card is deliberately LIGHTER than the app's own surfaces, so a card
    /// keeps a visible edge on the near-black page. That relationship is the invariant;
    /// the specific hex is not, and asserting the hex is why this test broke on a
    /// palette change that preserved every relationship it cared about.
    func testTheBoardCardIsLighterThanTheAppSurfaces() {
        func lum(_ hex: String) -> CGFloat {
            let c = NSColor(hex: hex).usingColorSpace(.sRGB)!
            return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        }
        XCTAssertGreaterThan(lum(RoadmapTokens.cardBGHex.dark), lum("#1d1928"),
                             "the board card must be lighter than `surface`/`cardRaised`")
        XCTAssertGreaterThan(lum(RoadmapTokens.chipBGHex.dark), lum(RoadmapTokens.cardBGHex.dark),
                             "the status chip sits ON the card, so it must be lighter still")
        XCTAssertGreaterThan(lum(RoadmapTokens.chipBorderHex.dark), lum(RoadmapTokens.chipBGHex.dark),
                             "the chip's edge must be lighter than its fill")
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapPaletteTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **FAIL** on the first assertion — the current warm `cardBGHex.dark` (`#2a241c`) has luminance below the new cool `#1d1928`, so the board card is currently *darker* than the app surface it is supposed to sit above. That inversion is exactly what Task 2 introduced and this task fixes.

- [ ] **Step 3: Retint the roadmap's three pairs**

Find them with `grep -n "cardBGHex\|chipBGHex\|chipBorderHex" codepet/Views/CodepetTokens.swift`:

```swift
    static let cardBGHex: HexPair      = ("#ffffff", "#252036")   // --rm-card-bg
    static let chipBGHex: HexPair      = ("#efecf7", "#2f2846")   // --rm-chip-bg
    static let chipBorderHex: HexPair  = ("#e0dced", "#403858")   // --rm-chip-border
```

Dark values are derived, not verbatim — the prototype has no board-card level. Each sits one step above the app surface below it, preserving the ladder the comment describes. Light `cardBG` stays `#ffffff`; `chipBG` and `chipBorder` take `--ground-2` and `--hairline`.

- [ ] **Step 4: Run it and confirm it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapPaletteTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: all pass, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/CodepetTokens.swift codepetTests/RoadmapPaletteTests.swift
git status --porcelain   # confirm ONLY those two are staged
git commit -m "$(cat <<'EOF'
feat(roadmap): the board's surfaces follow the app's

RoadmapTokens' surfaces are defined RELATIVE to the app's — its own comment says
the board card is deliberately lighter than both `surface` and `cardRaised` so
cards keep a visible edge. Retinting the app's without these inverted that: the
warm #2a241c fell below the new cool #1d1928.

The tests now assert the relationship instead of the hex. Asserting the literal
is why they broke on a change that preserved every relationship they cared about.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 6: Full suite, then hand the colour judgement to a human

**Files:** none modified.

- [ ] **Step 1: Confirm no warm surface hex survives outside the excluded sites**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
grep -rn --include="*.swift" -iE "#16130f|#221d17|#2f2820|#26211a|#1b1712|#26201a|#3c352b|#2a241c|#342d23|#473e31" . \
  | grep -v "WorldMapView.swift" | grep -v "DynamicColorTests.swift"
echo "exit=$?"
```

Expected: only *comments* that describe the old values as history (Task 2's and Task 5's explanatory comments legitimately name them). **Any live `Color.dyn` or `HexPair` still using one is a miss.** `WorldMapView.swift` is an excluded legacy screen; `DynamicColorTests.swift` uses `#221d17` as an arbitrary fixture for testing the `Color.dyn` mechanism, which is still valid — but correct its stale comment if it claims the value is the app surface.

- [ ] **Step 2: Run the full suite**

```bash
pgrep -x codepet >/dev/null && echo "NOTE: sibling's app is running — do NOT kill it; expect a possible lock"
./scripts/ci-test.sh 2>&1 | tail -30
xcrun xcresulttool get test-results summary --path build/ci.xcresult | head -20
```

Expected: **1721 + the tests this plan adds**, 0 failed. Take the current baseline from `.superpowers/sdd/progress.md`. Around 27 tests never finishing with no actual failure is the known 26.2 toolchain bug plus the sibling's Firestore lock — confirm via `xcresulttool` that none of them are this plan's.

- [ ] **Step 3: Build signed so a human can look at it**

Colour is the one thing no assertion in this plan judges. Screen Recording is denied on this machine, so this is a handoff, not a screenshot.

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | grep -E "error:|BUILD"
```

Do **not** launch it if the sibling's instance is running — one bundle id, one keychain session. Report that the build is ready and let the founder launch it, or wait until `pgrep -x codepet` is empty. The launch argument is required and `defaults write` does not work for it:

```bash
open ~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app --args -CODEPET_TWO_MODE YES
```

- [ ] **Step 4: Ask three questions, then stop**

In both modes (⌘, → Appearance):

> 1. Does the ground read purple rather than brown?
> 2. Is anything now too dark or too light to read? `bodyText` in light mode went *lighter* (`#332e27` → `#4d4859`) and `mutedText` with it, so contrast on the cream ground dropped.
> 3. Does the ASK/DEVELOPER switch read as three layers now — rail, track, lifted card?

Question 2 is the one with a real risk behind it. Question 3 is the payoff from the sidebar edit.

The known-open item to raise only if the founder does: `accentPurple` is still `#7c3aed`/`#9d6bf5` where the prototype pairs its ground with `#a89bf2`. It should read far better on a cool ground than on brown, but it is not the prototype's exact pairing, and closing that gap is its own spec.

- [ ] **Step 5: Push only after Step 4 gets an answer**

A PR already exists — **#110**, open on `feat/composer-controls`. Do **not** run `gh pr create`; pushing updates that PR. The branch is shared with a concurrent session, so `git push` may report "Everything up-to-date" if they have already pushed your commits along with theirs. Verify individually rather than trusting the sync count:

```bash
git fetch --quiet origin
for c in $(git log --format=%h -6); do
  printf '%-9s ' "$c"
  git branch -r --contains "$c" | grep -q "origin/feat/composer-controls" && echo "on remote" || echo "NOT on remote"
done
```

---

## Self-review

**Spec coverage.** Every section maps to a task: the dark and light mapping tables → Task 2; the rail-level resolution → Task 3; the `OnboardingContent` duplicate → Task 4; `RoadmapTokens`' relative surfaces and `RoadmapPaletteTests` → Task 5; the four affected test files → Task 1 (which removes the dependency rather than re-measuring it) plus Task 5; verification and the human handoff → Task 6. The spec's out-of-scope list (accents, dept triads, `WorldMapView`, the web repo, dark-only) appears in the Global Constraints and in Task 6 Step 1's grep exclusions.

**One deliberate departure from the spec, in the plan's favour.** The spec said to re-measure every threshold against the new palette. Task 1 instead makes the guards palette-independent so most thresholds need no re-measuring at all — the corner guard drops from `0.072` to `0.01` and both schemes share one number. Two thresholds still get re-measured (the bloom's warm count and the mode segment's violet count) because their *metrics* change character, not just their baselines. This is strictly better than what the spec asked for and is why Task 1 is first.

**Placeholder scan.** No TBD, TODO, "similar to Task N", or "add appropriate handling". Every code step carries the actual code. Two steps deliberately expect a **passing** red state (Task 2 Step 2, Task 3 Step 2) and say so explicitly with the reason, rather than pretending they drive the change — that was ruled on during the previous plan.

**One API correctness fix caught in self-review.** Task 3's test first used `NSColor(CodepetTokens.surface2)` inside a `performAsCurrentDrawingAppearance` block. Bridging a SwiftUI `Color` to `NSColor` can resolve eagerly — outside the block — so the test would have read LIGHT values while reporting on dark, and passed for the wrong reason. It now resolves through `CodepetTheme.dynamicNSColor(light:dark:)`, the pattern `DynamicColorTests.testDynamicColorFlipsByAppearance` already proves works.\n\n**Type consistency.** `referenceGround(colorScheme:width:height:)` is defined in Task 1 and used by Task 1 only; both test files get their own copy because they are separate `XCTestCase` classes. `RenderFailure.producedNothing` exists in `BrandMarkRenderTests` already and is added to `ComposerEdgeRenderTests` if absent. `lum(_:)` is declared locally inside each test that uses it (Task 2, Task 3, Task 5) rather than shared, since the three live in three different files. `CodepetTokens.surface2` is set in Task 2 and consumed in Task 3; `CodepetTheme.surface`'s new value is set in Task 2 and referenced by Task 5's assertion.

**Known-fragile items, flagged rather than hidden.** Task 5's dark roadmap values (`#252036`, `#2f2846`, `#403858`) are derived, not verbatim — the prototype has no board-card level — and the luminance assertions in Step 1 are what hold them honest. Task 3's Step 4 print is a sanity signal explicitly labelled as not an assertion; the sidebar's *choice of token* cannot be asserted from tokens alone, which is a real coverage limit rather than an oversight.
