# Flat Chat Ground Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the chat surface's ambient purple wash so both the empty hero and the live transcript sit on flat `pageBackground` in light and dark, and make the elements that mattered louder in the same change so nothing gets harder to see.

**Architecture:** Purely subtractive on the background — no new color, `pageBackground` already exists as a `Color.dyn` token. Additive on elements through **one** gradient constructor, `CodepetTheme.ramp(_:_:)`, with the hue pair injected by the caller: the composer's two sites pass the *companion's* accent, the hero mark alone passes the brand pair. Every claim is proved by offscreen `ImageRenderer` pixel assertions, because the native app cannot be screenshotted on this machine.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. No new dependencies, no `functions/` change, no API cost.

**Spec:** `docs/superpowers/specs/2026-08-21-flat-chat-ground-design.md`. Read the three amendments **[A1] [A2] [A3]** before starting — each one is a place where the first draft named the wrong file or the wrong current value, and Tasks 3, 4, and 5 are where they bite.

## Global Constraints

- **Swift only.** No file under `functions/` may be touched.
- **One gradient constructor.** Every two-stop gradient added by this plan calls `CodepetTheme.ramp(_:_:)`. Do not write an inline `LinearGradient` at a call site. Four independent definitions drifting apart is what produced the roadmap accent collision — red text on violet fill, still on main.
- **Never hard-code brand purple where an `accent` parameter is in scope.** `ChatComposer`'s `accent` is `companionColor` (`CopilotChatView.swift:92-94`, passed at `:277`). Replacing it with `accentPurple` erases the founder's companion hue. Same rule that keeps `DepartmentRoster`'s chips on `dep.accent`.
- **The roster chips are out of scope.** `DepartmentRoster.swift:95-97` keeps `dep.accent`. That per-department hue *is* the "each department speaks with its own voice" claim.
- **`CopilotChatView.swift:766` is out of scope.** It is a thread row in the history list, not the mode switch. Its `accentPurple.opacity(0.08)` stays exactly as it is.
- **No new `.swift` files are needed**, so no project-file edit. (`PBXFileSystemSynchronizedRootGroup` — membership follows the folder — but this plan only modifies and deletes.)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Render tests are annotated `@MainActor`, as `BrandMarkRenderTests` already is.
- **Quit `codepet.app` before running tests.** A running instance holds the Firestore lock and kills the test host, with a different victim each run. Check `pgrep -x codepet`.
- **Count tests with `xcresulttool`**, never by grepping the log.
- **`ImageRenderer` draws NOTHING inside a `ScrollView`.** Every view rendered by this plan's tests is on the empty-hero path, which has no `ScrollView`. If you add a render test for the transcript path, it will silently produce a blank image and "pass".

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

`-derivedDataPath build/dd-ci` is load-bearing: without it the unsigned test build overwrites the signed `codepet.app` in shared DerivedData and Firebase sign-in silently breaks for the next human launch. **Do not run two `xcodebuild` invocations against `build/dd-ci` at once** — a concurrent run sharing it kills the test host, presenting as ~27 tests never finishing with no actual failure.

**Full suite, required before the PR:** `./scripts/ci-test.sh`. Take the current green count from `.superpowers/sdd/progress.md`, not from this line. Whatever it is, any red is yours.

**Reading the rendered PNGs.** Every render test writes its image to `$CODEPET_RENDER_DIR` (default `NSTemporaryDirectory()`) and prints the path. When an assertion fails, open the PNG before changing the assertion — the existing suite's comment records why: a band measured from the top edge samples empty background and "proves" the logo is missing.

---

## File structure

| File | Change | Responsibility after |
|---|---|---|
| `codepet/Views/Copilot/ChatBackdrop.swift` | **deleted** | — |
| `codepet/Views/Copilot/CopilotChatView.swift` | modify `:173` | composes the pane on flat `pageBackground` |
| `codepet/Views/Copilot/MessageCard.swift` | modify comment `:16-19` | its reasoning no longer cites a view that exists |
| `codepet/Views/CodepetTheme.swift` | add `brandRamp`, `ramp(_:_:)` | the single source of gradient geometry + the brand hue pair |
| `codepet/Views/Copilot/ChatComposer.swift` | modify `:634`, `:177-180` | send button and container edge both companion-hued through `ramp` |
| `codepet/Views/Copilot/ChatEmptyState.swift` | modify `:120-126` | hero bloom is a radial built from `brandRamp` |
| `codepet/Views/Shell/TwoModeSidebar.swift` | modify `:166-176` | active mode segment has purple body, not just purple text |
| `codepetTests/BrandMarkRenderTests.swift` | extend | corner flatness (dark + light) + the bloom's pink stop |
| `codepetTests/ComposerEdgeRenderTests.swift` | **created** | the container edge is visible at rest, and honours the companion hue |

Task order is deliberate: Task 1 removes the thing, so every later task's render test measures a flat ground rather than a wash it has to see through.

---

### Task 1: Delete the wash, and prove the ground went flat

The only task whose test genuinely fails first for the reason the change exists. Do it before anything else.

**Files:**
- Delete: `codepet/Views/Copilot/ChatBackdrop.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift:173`
- Modify: `codepet/Views/Copilot/MessageCard.swift:16-19`
- Test: `codepetTests/BrandMarkRenderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ChatBackdrop` no longer exists — later tasks must not reference it. `BrandMarkRenderTests` gains a private helper `renderChatPane(colorScheme:) throws -> (rep: NSBitmapImageRep, url: URL)` used by Tasks 1 and 3.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/BrandMarkRenderTests.swift`, inside the existing class. Note this renders `CopilotChatView`, **not** `ChatEmptyState` — per spec **[A3]**, the wash is applied at `CopilotChatView.swift:173`, so a test that renders the bare hero would have flat corners before the change and prove nothing.

```swift
    /// Renders the pane the way the shell composes it and asserts the corners are
    /// the flat `pageBackground` — no ambient wash.
    ///
    /// This renders `CopilotChatView`, not `ChatEmptyState`, and the distinction is
    /// the whole test: the wash lived on `CopilotChatView`'s `.background`, so the
    /// bare hero already had flat corners and would have passed this without the
    /// change. Rendering the real composition is also what keeps this a guard —
    /// re-add an ambient gradient anywhere behind the pane and this fails again.
    ///
    /// The empty-hero path carries no `ScrollView` (the transcript's is at :484,
    /// the history's at :693, neither reachable with no threads), which is the only
    /// reason `ImageRenderer` produces anything here at all.
    @MainActor
    private func renderChatPane(colorScheme: ColorScheme) throws -> (rep: NSBitmapImageRep, url: URL) {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"]
            ?? NSTemporaryDirectory()
        // No founder name is set: `CompanyStore.company` is `@Published private(set)`
        // (`CompanyStore.swift:45`), so a test cannot write it even under
        // `@testable import` — the setter is private to that file. It does not matter
        // here. The greeting's text is not what is being sampled, and the corners are
        // 40pt from the edge, nowhere near it.
        let pane = CopilotChatView()
            .environmentObject(CompanyStore())
            .environmentObject(AppState())
            .environment(\.chatSurface, .twoMode)
            .frame(width: 760, height: 560)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: pane)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // A nil render is a FAILURE, not a skip — these are guards, and a skip
            // would let CI stay green with the guard silently gone. `XCTFail` returns
            // Void, so a non-Void throwing helper needs both: record the failure, then
            // throw to abort. Declare `private enum RenderFailure: Error { case producedNothing }`
            // alongside the other helpers.
            XCTFail("ImageRenderer produced nothing for CopilotChatView")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir)
            .appendingPathComponent("chat-pane-\(colorScheme == .dark ? "dark" : "light").png")
        try png.write(to: url)
        print("[render] \(url.path)")
        return (rep, url)
    }

    /// The four corners of the pane, 40pt in from each edge — far outside the
    /// hero's stack, and where a 420pt-radius wash centred on the pane still
    /// deposits measurable violet.
    private func cornerSamples(_ rep: NSBitmapImageRep, inset: Int) -> [NSColor] {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        return [(inset, inset), (w - inset, inset), (inset, h - inset), (w - inset, h - inset)]
            .compactMap { rep.colorAt(x: $0.0, y: $0.1)?.usingColorSpace(.sRGB) }
    }

    @MainActor
    func testTheChatGroundIsFlatInDark() throws {
        let (rep, url) = try renderChatPane(colorScheme: .dark)
        let ground = NSColor(srgbRed: 0x16 / 255.0, green: 0x13 / 255.0, blue: 0x0f / 255.0, alpha: 1)
        let corners = cornerSamples(rep, inset: 40 * 2)
        XCTAssertEqual(corners.count, 4, "could not sample four corners")
        for c in corners {
            let d = abs(c.redComponent - ground.redComponent)
                + abs(c.greenComponent - ground.greenComponent)
                + abs(c.blueComponent - ground.blueComponent)
            XCTAssertLessThan(d, 0.06,
                              "the pane's corner is not flat pageBackground — an ambient "
                              + "wash is painting over it. See \(url.path)")
        }
    }
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
pgrep -x codepet && echo "QUIT codepet.app FIRST" && exit 1
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests/testTheChatGroundIsFlatInDark \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **FAIL**, with `the pane's corner is not flat pageBackground`. The printed
`[render] …/chat-pane-dark.png` should visibly show the violet blob — open it and
confirm before proceeding, because that image is the evidence the test is measuring
the wash and not something else.

Two failures that mean something different, and what to do:
- `ImageRenderer produced nothing` — `CopilotChatView` did not render. Reduce to `ChatEmptyState(...).background(ChatBackdrop())` for this task's red state, and record in the commit message that the durable guard is weaker than intended because the composed pane would not render. **(Did not occur: the composed pane rendered, and the RED state was a real `0.0839` vs `0.06` corner-distance failure. This branch was never taken.)**
- Corners already flat — the wash is not reaching 40pt from the edge at this frame size. Move `inset` to `20 * 2` and re-run before concluding anything.

- [ ] **Step 3: Delete the view and its application**

Delete the file:

```bash
git rm codepet/Views/Copilot/ChatBackdrop.swift
```

In `codepet/Views/Copilot/CopilotChatView.swift`, remove line 173 entirely:

```swift
        .background(ChatBackdrop())
```

The pane's ground now comes from `TwoModeShellView.swift:57`, which already fills
`CodepetTheme.pageBackground`. Add nothing to replace it — a local `.background(pageBackground)`
here would be the redundant chrome the spec rejected.

- [ ] **Step 4: Run it and confirm it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests/testTheChatGroundIsFlatInDark \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **PASS**.

- [ ] **Step 5: Add the light-mode assertion**

Light mode gets its own test rather than being assumed to follow, because light mode
is where the wash was least intended — `ChatBackdrop` had no `colorScheme` check, so
it painted `accentPurple @0.16` over cream and nobody reviewed that.

```swift
    @MainActor
    func testTheChatGroundIsFlatInLight() throws {
        let (rep, url) = try renderChatPane(colorScheme: .light)
        let ground = NSColor(srgbRed: 0xf8 / 255.0, green: 0xf7 / 255.0, blue: 0xf3 / 255.0, alpha: 1)
        let corners = cornerSamples(rep, inset: 40 * 2)
        XCTAssertEqual(corners.count, 4, "could not sample four corners")
        for c in corners {
            let d = abs(c.redComponent - ground.redComponent)
                + abs(c.greenComponent - ground.greenComponent)
                + abs(c.blueComponent - ground.blueComponent)
            XCTAssertLessThan(d, 0.06,
                              "the light pane's corner is not flat cream — an ambient "
                              + "wash is painting over it. See \(url.path)")
        }
    }
```

- [ ] **Step 6: Run both, and the pre-existing mark test with them**

The third name is not optional: it is the guard that deleting the wash did not take
the mark's visibility with it.

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **3 passed, 0 failed** — `testTheBrandMarkIsVisibleOnTheDarkPane`,
`testTheChatGroundIsFlatInDark`, `testTheChatGroundIsFlatInLight`.

- [ ] **Step 7: Correct the comment that now cites a deleted view**

`codepet/Views/Copilot/MessageCard.swift:16-19` reasons about "a translucent tint
over ChatBackdrop's wash". The conclusion it defends (opaque surface base first,
then the hue tint) is still right — the reason given for it is now false. Replace:

```swift
            // Opaque surface base FIRST, then the hue tint on top — i.e. "hue @12%
            // over surface" per the spec. Without the surface base the card is only
            // a translucent tint over the page itself, washing out pale hues
            // (gold/teal) and the reading text in light mode. This mattered more
            // when an ambient wash sat behind the pane; it still holds on flat
            // ground, because `pageBackground` is not what these hues were mixed
            // against.
```

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift \
        codepet/Views/Copilot/MessageCard.swift \
        codepetTests/BrandMarkRenderTests.swift
git commit -m "$(cat <<'EOF'
fix(chat): the wash was decorating the pane, not the hero

ChatBackdrop painted accentPurple @0.16 across the chat surface with no
colorScheme check — so a violet blob mid-pane in dark, and the same wash over
cream in light, which nobody had reviewed. Both states now sit on flat
pageBackground, which TwoModeShellView already fills.

The corner assertions render CopilotChatView rather than the bare hero, and
that is the point: the wash lived on CopilotChatView's .background, so a test
of ChatEmptyState alone had flat corners already and would have passed without
proving anything. It fails before this commit and passes after.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: One gradient constructor

A pure refactor with no visual change, landed on its own so that when Tasks 3–5 do change pixels, the constructor is not also under suspicion.

**Files:**
- Modify: `codepet/Views/CodepetTheme.swift` (in the "Brand accents" section, after `accentGreen`)
- Modify: `codepet/Views/Copilot/ChatComposer.swift:632-641`
- Test: `codepetTests/AppThemeTests.swift`

**Interfaces:**
- Consumes: `CodepetTheme.accentPurple`, `CodepetTheme.accentPink` (existing).
- Produces:
  - `CodepetTheme.brandRamp: [Color]` — exactly `[accentPurple, accentPink]`, in that order.
  - `CodepetTheme.ramp(_ a: Color, _ b: Color) -> LinearGradient` — `.topLeading` → `.bottomTrailing`.
  Tasks 3, 4, and 5 all call these by these exact names.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/AppThemeTests.swift`:

```swift
    /// The ramp is a constructor, not a constant, because its two consumers need
    /// different hues: the composer's stops are the active companion's colour
    /// (`CopilotChatView.companionColor`), and only the hero mark is brand purple.
    /// A fixed `brandGradient` would have had to be overridden at the very sites
    /// that share it. This asserts the pair and its order, which the hero's radial
    /// depends on: purple reads first, pink second.
    func testBrandRampIsPurpleThenPink() {
        XCTAssertEqual(CodepetTheme.brandRamp.count, 2)
        XCTAssertEqual(CodepetTheme.brandRamp[0], CodepetTheme.accentPurple)
        XCTAssertEqual(CodepetTheme.brandRamp[1], CodepetTheme.accentPink)
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/AppThemeTests/testBrandRampIsPurpleThenPink \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **compile error** — `type 'CodepetTheme' has no member 'brandRamp'`. That
is the red state for a token; there is nothing to run yet.

- [ ] **Step 3: Add the token and the constructor**

In `codepet/Views/CodepetTheme.swift`, immediately after `static let accentGreen`:

```swift
    /// The two stops the brand ramp is made of, purple first. Exposed as a pair
    /// rather than as a finished gradient because a radial bloom must stay radial —
    /// a `LinearGradient` cannot fill one without changing its shape — so the
    /// hero's aura and the composer's stroke read from one source and build the
    /// geometry each needs.
    static let brandRamp: [Color] = [accentPurple, accentPink]

    /// The house ramp. Every two-stop gradient in the product is this function:
    /// one geometry, one direction, hues supplied by the caller. Extracted from the
    /// composer's send button, which had it inline.
    ///
    /// The hues are a parameter and not a default for a reason. `ChatComposer`'s
    /// stops are the *active companion's* accent (`CopilotChatView.companionColor`),
    /// so a ramp that hard-coded brand purple would erase the founder's companion
    /// hue at the two most visible controls on the pane.
    static func ramp(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(gradient: Gradient(colors: [a, b]),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
```

- [ ] **Step 4: Move the send button onto it**

In `codepet/Views/Copilot/ChatComposer.swift`, replace the inline gradient at
`:632-641`:

```swift
                .background(
                    Circle().fill(
                        canSend
                            ? AnyShapeStyle(CodepetTheme.ramp(accent, accent2))
                            : AnyShapeStyle(CodepetTheme.mutedText)
                    )
                    .shadow(color: canSend ? accent.opacity(0.55) : .clear, radius: 10)
                )
```

`accent` and `accent2` stay exactly as they were — this is a move, not a retint.
The rendered button must be byte-identical; if Task 4's render shows otherwise, the
direction or stop order was changed here by accident.

- [ ] **Step 5: Run the theme suite**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/AppThemeTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **PASS**, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/CodepetTheme.swift \
        codepet/Views/Copilot/ChatComposer.swift \
        codepetTests/AppThemeTests.swift
git commit -m "$(cat <<'EOF'
refactor(theme): one ramp constructor, hues injected

The send button had the only two-stop gradient in the product, inline. Lifting
it gives the three sites that are about to need it one geometry and one
direction to share.

It is a function and not a constant because its consumers disagree about hue:
ChatComposer's stops are the active companion's accent, and only the hero mark
is brand purple. A fixed brandGradient would have shipped with zero call sites
that did not immediately override it.

No visual change — the button's stops and direction are unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: The hero bloom, in radial form

**Files:**
- Modify: `codepet/Views/Copilot/ChatEmptyState.swift:120-126`
- Test: `codepetTests/BrandMarkRenderTests.swift`

**Interfaces:**
- Consumes: `CodepetTheme.brandRamp` from Task 2.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/BrandMarkRenderTests.swift`. It samples the same band the
existing mark test does, looking for the pink stop that only the new radial puts there.

```swift
    /// The bloom carries the brand's second stop.
    ///
    /// Sampled in the mark's band only (0..<155pt), for the reason the existing
    /// mark test records: the greeting's accented word below is a near-identical
    /// violet and would pass a full-frame search on its own. Pink has no such twin
    /// on this screen, but keeping the same band keeps the two assertions
    /// comparable.
    ///
    /// The threshold is deliberately loose. The pink stop is laid down at 0.18 over
    /// pageBackground and then blurred by 18pt, so no pixel is ever close to pure
    /// accentPink — what is being asserted is that the bloom is warm on its outer
    /// edge, not that a pink pixel exists.
    @MainActor
    func testTheBloomCarriesTheBrandsSecondStop() throws {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"]
            ?? NSTemporaryDirectory()
        var company = CompanyState.empty
        company.brief.founderName = "Mona"

        let hero = ChatEmptyState(
            state: ChatLandingState(company: company, now: Date(), language: .en),
            onOpenRoadmap: {}, onStarter: { _ in },
            beaconTasks: [], onBeacon: { _, _ in }
        ) { EmptyView() }
            .environment(\.chatSurface, .twoMode)
            .environmentObject(CompanyStore())
            .frame(width: 760, height: 420)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: hero)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("ImageRenderer produced nothing")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("hero-bloom.png")
        try png.write(to: url)
        print("[render] \(url.path)")

        // Warm means red leads blue. A single-hue violet bloom over #16130f has
        // blue well above red at every radius; adding pink is what tips any pixel
        // in the band the other way.
        var warmPixels = 0
        let band = 0..<Int(155 * renderer.scale)
        for y in band {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > c.blueComponent + 0.02 { warmPixels += 1 }
            }
        }
        XCTAssertGreaterThan(warmPixels, 60,
                             "the bloom has no warm edge — the pink stop is missing, or the "
                             + "radial was replaced by a linear ramp. See \(url.path)")
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests/testTheBloomCarriesTheBrandsSecondStop \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **FAIL**, `the bloom has no warm edge`. If it passes at red, something
else in the band is already warm — open the PNG, find it, and raise the `60`
threshold above that baseline before proceeding. Do not lower the `0.02` margin.

- [ ] **Step 3: Give the bloom its second stop**

In `codepet/Views/Copilot/ChatEmptyState.swift`, replace the `Circle().fill(...)`
inside `brandMark` (`:120-126`):

```swift
            Circle()
                // Radial, not `CodepetTheme.ramp` — a linear gradient cannot fill a
                // bloom without changing its shape. Same hue pair as the ramp, read
                // from `brandRamp` so the two forms cannot drift; purple reads first
                // because this is the logo's glow, not a companion's.
                .fill(RadialGradient(colors: [CodepetTheme.brandRamp[0].opacity(0.34),
                                              CodepetTheme.brandRamp[1].opacity(0.18),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 92, height: 92)
                .blur(radius: 18)
                .allowsHitTesting(false)
```

The `0.34` first stop, `endRadius: 46`, `92×92` frame, and `blur(radius: 18)` are
all unchanged from what founder review settled. Only the middle stop is new.

- [ ] **Step 4: Run the whole suite for this file**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/BrandMarkRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **4 passed, 0 failed**. `testTheBrandMarkIsVisibleOnTheDarkPane` passing
here is the one that matters — it proves the violet fill survived gaining a pink
outer stop, i.e. the mark is still legible.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/ChatEmptyState.swift \
        codepetTests/BrandMarkRenderTests.swift
git commit -m "$(cat <<'EOF'
feat(chat): the hero bloom carries both brand stops

Same hue pair as the ramp, read from brandRamp so the two cannot drift, but
built as a RadialGradient: a linear ramp cannot fill a bloom without changing
its shape, which is why the shared token is a pair and not a finished gradient.

Opacity, radius, frame and blur are untouched — only the middle stop is new.
The pre-existing violet-fill assertion still passes, which is what proves the
mark stayed legible rather than getting washed warm.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: The composer edge, both states, companion-hued

The task where spec **[A1]** bites. Read it before starting.

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift:177-180`
- Create: `codepetTests/ComposerEdgeRenderTests.swift`

**Interfaces:**
- Consumes: `CodepetTheme.ramp(_:_:)` from Task 2.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/ComposerEdgeRenderTests.swift`. Two tests: the edge is visible
at rest, and it is the companion's hue rather than brand purple.

```swift
// codepetTests/ComposerEdgeRenderTests.swift
import SwiftUI
import XCTest
@testable import codepet

/// The composer's container edge, rendered offscreen.
///
/// The resting state is what these guard. Focused, the edge was already accent at
/// 0.65 and perfectly visible; at rest it was `CodepetTokens.cardEdge` — `#ece9e2`
/// against cream `#f8f7f3` in light, a hairline of almost no value. The ambient wash
/// had been doing the separating, so removing it without touching this would have
/// been the legibility regression the spec set out to avoid.
///
/// Both tests render in LIGHT mode, deliberately. Dark mode's `cardEdge` (`#3c352b`)
/// on `#16130f` was always visible; light is where the wash was load-bearing and
/// where this can actually fail.
final class ComposerEdgeRenderTests: XCTestCase {

    @MainActor
    private func renderComposer(accent: Color, name: String) throws -> (rep: NSBitmapImageRep, url: URL) {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"]
            ?? NSTemporaryDirectory()
        let host = ComposerEdgeHost(accent: accent)
            .environment(\.chatSurface, .twoMode)
            .environmentObject(CompanyStore())
            .frame(width: 520, height: 160)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // A nil render is a FAILURE, not a skip — these are guards, and a skip
            // would let CI stay green with the guard silently gone. `XCTFail` returns
            // Void, so a non-Void throwing helper needs both: record the failure, then
            // throw to abort. Declare `private enum RenderFailure: Error { case producedNothing }`
            // alongside the other helpers.
            XCTFail("ImageRenderer produced nothing for ChatComposer")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("composer-edge-\(name).png")
        try png.write(to: url)
        print("[render] \(url.path)")
        return (rep, url)
    }

    /// Saturation computed from the RGB channels rather than read off the colour.
    ///
    /// `NSColor.saturationComponent` raises for colours that are not in an
    /// HSB-compatible space, and what `colorAt` hands back depends on the bitmap's
    /// own space. Arithmetic on three channels cannot throw, and this is HSV
    /// saturation exactly: `(max - min) / max`.
    private func saturation(_ c: NSColor) -> CGFloat {
        let hi = max(c.redComponent, max(c.greenComponent, c.blueComponent))
        let lo = min(c.redComponent, min(c.greenComponent, c.blueComponent))
        return hi <= 0 ? 0 : (hi - lo) / hi
    }

    /// Strongest-saturation pixel in the frame. The edge is the only saturated thing
    /// on a cream ground with an unfocused, empty composer — the send button is
    /// `mutedText` while `canSend` is false, and the placeholder is grey.
    private func mostSaturated(_ rep: NSBitmapImageRep) -> NSColor? {
        var best: NSColor?
        var bestSat: CGFloat = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let sat = saturation(c)
                if sat > bestSat { bestSat = sat; best = c }
            }
        }
        return best
    }

    @MainActor
    func testTheRestingEdgeIsVisibleOnCream() throws {
        let (rep, url) = try renderComposer(accent: CodepetTheme.accentPurple, name: "rest")
        guard let peak = mostSaturated(rep) else {
            return XCTFail("no pixels sampled — see \(url.path)")
        }
        // `cardEdge` (#ece9e2) has saturation ~0.04. The ramp at 0.35 over cream
        // lands well above that. 0.15 sits between the two with room on both sides.
        XCTAssertGreaterThan(saturation(peak), 0.15,
                             "the resting composer edge is a near-invisible hairline on cream — "
                             + "it is still cardEdge. See \(url.path)")
    }

    /// The regression guard for the mistake this task exists to avoid.
    ///
    /// `ChatComposer.accent` is `CopilotChatView.companionColor` — the founder's
    /// chosen pet's hue, brand purple only as a fallback. Hard-coding purple here
    /// would erase that, and would do it silently for every founder whose companion
    /// is not the default. Rendering with a green accent and asserting the edge is
    /// green is what catches it.
    @MainActor
    func testTheEdgeHonoursTheCompanionHue() throws {
        let (rep, url) = try renderComposer(accent: CodepetTheme.accentGreen, name: "companion")
        guard let peak = mostSaturated(rep) else {
            return XCTFail("no pixels sampled — see \(url.path)")
        }
        XCTAssertGreaterThan(peak.greenComponent, peak.blueComponent + 0.05,
                             "the composer edge ignored the companion accent and drew brand "
                             + "purple — accent is companionColor, not a constant. See \(url.path)")
    }
}

/// Hosts `ChatComposer` with the one `FocusState` it requires. Unfocused and empty,
/// which is exactly the resting state under test.
private struct ComposerEdgeHost: View {
    let accent: Color
    @State private var draft = ""
    @State private var mode: ChatMode = .ask
    @State private var dept: Department? = nil
    @FocusState private var focused: Bool

    var body: some View {
        ChatComposer(
            draft: $draft, mode: $mode, canSend: false,
            focus: $focused,
            placeholder: "Ask your company anything…",
            quickActions: [],
            accent: accent, accent2: CodepetTheme.accentPink,
            isBusy: false, selectedDept: $dept,
            onSend: {}, onQuickAction: { _ in }
        )
        .padding(20)
    }
}
```

**Before running:** the `ChatComposer(...)` argument list above is copied from the
existing preview host at `ChatComposer.swift:661-670`. If the initialiser has since
gained a required parameter, the compiler will say which — add it, do not remove
one of these.

`ChatMode` is declared in `codepet/Models/ChatMode.swift:7` as
`case ask, plan, build` — `.ask` is correct and needs no checking.

- [ ] **Step 2: Run and confirm both fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: `testTheRestingEdgeIsVisibleOnCream` **FAILS** with "it is still cardEdge".
`testTheEdgeHonoursTheCompanionHue` may **pass** at red — `cardEdge` is a warm grey
whose green already exceeds its blue. That is fine and expected: it is a guard
against a regression Step 3 could introduce, not a driver of Step 3. Note in the
commit that it was green before and after.

- [ ] **Step 3: Give the edge the ramp in both states**

In `codepet/Views/Copilot/ChatComposer.swift`, replace the `.overlay` at `:176-180`:

```swift
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // Both states are the same ramp at two opacities, not two different
                // treatments — one stroke definition cannot drift into reading as two
                // controls. Companion-hued: `accent` is `companionColor`, so brand
                // purple must not be hard-coded here.
                //
                // At rest this used to be `cardEdge`, which on cream is a hairline of
                // almost no value. The ambient wash had been doing that separating; with
                // flat ground the edge has to carry it.
                .stroke(CodepetTheme.ramp(accent, accent2)
                            .opacity(focus.wrappedValue ? 0.9 : 0.35),
                        lineWidth: 1)
        )
```

The comment at `:168-171` above this block claims accent moves to the edge "only on
focus", and defends it: an always-accent outline made the composer the loudest thing
on the pane. That reasoning applied to a *full-strength* outline over a washed
background. At 0.35 on flat ground it is a visible edge rather than a loud one — so
correct the comment rather than leaving it to contradict the code:

```swift
        // The house card: `cardRaised` + `cardEdge` at radius 12 with `shadowS`,
        // the same object Tasks and Roadmap are built from. The edge carries the
        // accent ramp in both states — 0.35 at rest, 0.9 focused. An always-accent
        // outline at full strength did make the composer the loudest thing on the
        // pane, which is why this used to be cardEdge at rest; a third of the way up
        // on flat ground is the opposite problem, since cardEdge on cream is
        // invisible without an ambient wash behind it.
```

- [ ] **Step 4: Run and confirm both pass**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **2 passed, 0 failed**. Open `composer-edge-rest.png` and confirm the edge
is a visible outline and not a heavy border — the assertion has a floor but no
ceiling, so only the image can tell you it went too far.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift \
        codepetTests/ComposerEdgeRenderTests.swift
git commit -m "$(cat <<'EOF'
feat(composer): the resting edge has to carry its own separation now

At rest the container was cardEdge — #ece9e2 on cream #f8f7f3, a hairline of
almost no value. The ambient wash had been doing that work, so deleting the
wash without this would have made the composer harder to find in light mode,
not cleaner.

Both states are now one ramp at two opacities, 0.35 at rest and 0.9 focused:
one definition cannot drift into reading as two controls.

Companion-hued, and there is a test for it. `accent` here is companionColor,
so hard-coding brand purple would silently erase the founder's pet hue at the
most visible control on the pane — the same mistake the roster chips refuse
one file away. The green-accent render is the guard.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: The active mode segment gets purple body

The task where spec **[A2]** bites: the address in the first draft was a thread row,
and the `0.08` fill it described does not exist on this control.

**Files:**
- Modify: `codepet/Views/Shell/TwoModeSidebar.swift:166-176`
- Test: `codepetTests/ComposerEdgeRenderTests.swift` (new test, existing file — the offscreen-render helpers are already there)

**Interfaces:**
- Consumes: `CodepetTheme.accentPurple` (existing). Deliberately **not** `ramp` — this
  control is too small for a gradient to resolve, which is the whole finding. Also
  consumes `saturation(_:)`, the private helper Task 4 added to this same file.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/ComposerEdgeRenderTests.swift`:

```swift
    /// The active mode segment reads as selected on flat ground.
    ///
    /// Flat purple, not a ramp: at this size a two-stop gradient resolves to a
    /// single warm-shifted violet, so it would add a render path and no signal. The
    /// spec's rule is gradient where there is area, stronger flat accent where there
    /// is not — this is the "where there is not" side.
    ///
    /// Before this change the active segment was `cardRaised` filled and `cardEdge`
    /// stroked with purple *text*: the purple was already at full strength and there
    /// was no fill opacity to raise. So what is asserted is that the segment's BODY
    /// became purple, which text alone cannot do.
    @MainActor
    func testTheActiveModeSegmentHasPurpleBody() throws {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"]
            ?? NSTemporaryDirectory()
        // `mode` is the ONLY binding — `railCollapsed` is `@AppStorage`
        // (`TwoModeSidebar.swift:44`), not a parameter. Passing it does not compile.
        let host = TwoModeSidebar(mode: .constant(.ask))
            .environmentObject(CompanyStore())
            .environmentObject(AppState())
            .frame(width: 240, height: 120)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // A nil render is a FAILURE, not a skip — these are guards, and a skip
            // would let CI stay green with the guard silently gone. `XCTFail` returns
            // Void, so a non-Void throwing helper needs both: record the failure, then
            // throw to abort. Declare `private enum RenderFailure: Error { case producedNothing }`
            // alongside the other helpers.
            XCTFail("ImageRenderer produced nothing for TwoModeSidebar")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("mode-switch.png")
        try png.write(to: url)
        print("[render] \(url.path)")

        // Count violet-leaning pixels: blue clearly above green, saturation above
        // cardRaised's zero. Purple TEXT alone at this size contributes a few dozen
        // pixels; a tinted fill plus a tinted edge contributes hundreds. The
        // threshold sits above what text alone can reach.
        var violet = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.blueComponent > c.greenComponent + 0.04 && saturation(c) > 0.08 {
                    violet += 1
                }
            }
        }
        XCTAssertGreaterThan(violet, 900,
                             "the active mode segment has no purple body — only its text is "
                             + "accented, which is what it did before. See \(url.path)")
    }
```

**Verified while writing this plan:** `TwoModeSidebar` has exactly one `@Binding`
(`mode: WorkspaceMode`, `:23`) and two `@EnvironmentObject`s (`CompanyStore` `:24`,
`AppState` `:27`). `railCollapsed` is `@AppStorage` (`:44`) and is not a parameter.
`WorkspaceMode.ask` is the case name used at `:63` and `:225`.

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests/testTheActiveModeSegmentHasPurpleBody \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **FAIL**, "no purple body". If it fails instead with a much lower count
than expected, read the printed count against the PNG — the `900` floor was set for
a 240×120 frame at scale 2 and must be re-derived if you changed the frame.

- [ ] **Step 3: Give the active segment purple body**

In `codepet/Views/Shell/TwoModeSidebar.swift`, replace the `.background` and
`.overlay` inside `modeSwitch` (`:166-176`):

```swift
                            // The selected segment is a raised card sitting in a
                            // well — `cardRaised` on `well`, the pairing main uses
                            // wherever something is lifted out of a track. It is now
                            // *tinted*: still raised, but with purple body rather
                            // than purple text alone, which is what it takes to read
                            // as selected once the pane lost its ambient wash.
                            //
                            // Flat, not a ramp. At this size a two-stop gradient
                            // resolves to one warm-shifted violet — a render path
                            // with no signal.
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(mode == m ? CodepetTokens.cardRaised : .clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(mode == m
                                                  ? CodepetTheme.accentPurple.opacity(0.10)
                                                  : .clear)
                                    )
                            )
                            .overlay(
                                mode == m
                                    ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(CodepetTheme.accentPurple.opacity(0.45), lineWidth: 1)
                                    : nil
                            )
```

The `.foregroundStyle(mode == m ? CodepetTheme.accentPurple : CodepetTheme.mutedText)`
below stays exactly as it is. The inactive segment is untouched — it was `.clear`
filled with no overlay and it still is.

- [ ] **Step 4: Run and confirm it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **3 passed, 0 failed** — the two composer-edge tests and this one.

Open `mode-switch.png`. The inactive segment must still look inactive; if both read
as selected, the `0.10`/`0.45` pair is too strong and the test cannot tell you that.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Shell/TwoModeSidebar.swift \
        codepetTests/ComposerEdgeRenderTests.swift
git commit -m "$(cat <<'EOF'
feat(shell): the active mode segment gets purple body, not just purple text

The spec's first draft aimed this at CopilotChatView:766 and described raising a
0.08 fill. That line is a thread row in the history list, and this control has
no purple fill to raise: the active segment was cardRaised + cardEdge with
accentPurple TEXT, so the purple was already at full strength and already the
only purple there.

Body is what was missing. A 0.10 tint over cardRaised and a 0.45 purple edge,
flat rather than a ramp — at this size two stops resolve to one warm-shifted
violet, so a gradient would be a render path with no signal.

The inactive segment is untouched, and the render asserts a count above what
accented text alone can reach.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Full suite, and hand the visual judgement to a human

Nothing here changes behaviour. It exists because every prior task ran `-only-testing:`,
and a `-only-testing:` branch is an untested branch — on 21 Aug four days and forty
commits passed with zero full runs while Actions looked green, and the first full run
found three real regressions.

**Files:** none modified.

- [ ] **Step 1: Confirm no reference to the deleted view survives**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
grep -rn "ChatBackdrop" --include="*.swift" . ; echo "exit=$?"
```

Expected: no output, `exit=1`. A hit in a comment is still a hit — the name should
survive nowhere but the spec and this plan.

- [ ] **Step 2: Run the full suite**

```bash
pgrep -x codepet && echo "QUIT codepet.app FIRST" && exit 1
./scripts/ci-test.sh 2>&1 | tail -30
```

Expected: the green count from `.superpowers/sdd/progress.md` plus the 6 tests this
plan adds, 0 failed. Around 27 tests never finishing with **no actual failure** is
the known 26.2 toolchain bug, not yours — but confirm the count via `xcresulttool`
rather than reading the log, and confirm nothing in it is one of this plan's tests.

- [ ] **Step 3: Build signed, so a human can look at it**

The assertions prove the wash is gone and the elements are present. They cannot say
whether it looks right — that judgement is a handoff, and Screen Recording is denied
on this machine, so it cannot be faked with a screenshot.

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | grep -E "error:|BUILD"
open /Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app --args -CODEPET_TWO_MODE YES
```

The launch argument is required — `defaults write app.murror.codepet` does not work
for this flag: a stale sandbox container eats the write, the unsandboxed app reads a
different plist, and `defaults read` confirms the lie. If the two-mode shell does not
appear, the argument did not arrive; do not conclude the feature is missing.

- [ ] **Step 4: Ask one specific question, then stop**

Ask Mona exactly this, in both modes (⌘, → Appearance to switch), and wait:

> The middle of the chat pane — is it flat now, and does the composer still read as
> the thing you're meant to type in?

One question, because a list of five invites a single "looks fine" that answers none
of them. The known-open item to raise only if she does: `pageBackground` dark is
`#16130f`, a warm near-black, and a purple-pink element over a brownish ground can
read muddy. Changing it touches every surface token in the app and is out of scope
here.

- [ ] **Step 5: Push and open a PR — only after Step 4 gets an answer**

Pushing a branch runs **nothing** in CI. Open the PR, even as a draft, or the suite
never runs on it.

```bash
git push -u origin feat/composer-controls
gh pr create --draft --title "Flat chat ground, gradient only on elements" --body "$(cat <<'EOF'
## What

The chat surface's ambient purple radial is gone. Both the empty hero and the live
transcript sit on flat `pageBackground` in light and dark.

`ChatBackdrop` had no `colorScheme` check, so it was also painting `accentPurple @0.16`
over cream in light mode — the same view, not a separate light-mode bug.

## Why the elements changed in the same PR

A flat ground gives elements *less* help, so removing the wash on its own would have
been a legibility regression rather than a cleanup. Most of all in light mode: the
composer's resting edge was `cardEdge` (`#ece9e2`) on cream (`#f8f7f3`), and the wash
had been doing its separating.

- hero bloom → both brand stops, radial (a linear ramp cannot fill a bloom without
  changing its shape)
- composer edge → the ramp in both states, 0.35 rest / 0.9 focused
- active mode segment → purple body, not purple text alone

Gradients went only where there is area to resolve them. `"build"` and the mode pill
keep flat accent: across a five-letter word two stops resolve to one warm-shifted
violet, and that headline is built by `Text` concatenation where `foregroundStyle`
with a gradient can silently render flat.

## Three corrections found while planning

The spec's first draft named the wrong address three times; each is marked in the
spec and in the commit that fixed it.

- **[A1]** `ChatComposer.accent` is `companionColor`, not brand purple. Hard-coding
  purple would have erased the founder's pet hue at the pane's most visible control.
  `ComposerEdgeRenderTests.testTheEdgeHonoursTheCompanionHue` is the guard.
- **[A2]** `CopilotChatView:766` is a thread row, not the mode switch, and the real
  control had no `0.08` fill to raise.
- **[A3]** The corner assertions render `CopilotChatView`, not the bare hero — the
  wash lived on `CopilotChatView`'s `.background`, so a hero-only test had flat
  corners already and would have passed without proving anything.

## Verification

Offscreen `ImageRenderer` pixel assertions, because the native app cannot be
screenshotted on this machine. The corner-flatness tests fail before this branch and
pass after; the pre-existing violet-fill assertion still passes, which is what proves
deleting the wash did not take the mark's legibility with it.

Not covered by tests: whether it looks right. That was reviewed on screen by Mona.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review

**Spec coverage.** Every section maps to a task: removal → 1; the ramp constructor and
`brandRamp` → 2; the aura's radial → 3; the composer edge in both states, companion-hued
→ 4; the mode segment's flat purple → 5; verification → 1, 3, 4, 5 with the full suite
and the human handoff in 6. The `MessageCard` comment correction is folded into Task 1,
where the view it cites is deleted. The two "gradients go where there is area" negatives
are honoured by omission and are stated in Task 5's test comment so the next person does
not re-add them.

**Out-of-scope items stay out.** The roster chips' `dep.accent`, `CopilotChatView:766`,
the cinematic entry screens, and `pageBackground`'s warm cast are each named in the Global
Constraints or Task 6 Step 4 so they are not touched by accident.

**Type consistency.** `brandRamp` and `ramp(_:_:)` are defined in Task 2 and used by
Tasks 3, 4, and 5 under exactly those names. `renderChatPane(colorScheme:)` and
`cornerSamples(_:inset:)` are defined in Task 1 and reused in Task 1 Step 5.
`mostSaturated(_:)` and `renderComposer(accent:name:)` are defined in Task 4 and the
file they live in is extended by Task 5. Task 3 does not reuse `renderChatPane` — it
renders `ChatEmptyState` rather than the pane, so it carries its own setup rather than
bending a helper built for a different view.

**Three compile breaks found by checking the plan's own API claims against the
code, rather than trusting the greps that produced them.** All fixed inline; recorded
here because each was the same mistake the spec's amendments were about.

- `CompanyStore.company` is `@Published private(set)` (`CompanyStore.swift:45`), so
  Task 1's `store.company.brief.founderName = "Mona"` could not have compiled — a
  `private` setter stays inaccessible under `@testable import`. The mutation was
  dropped; the corner samples never depended on it.
- `TwoModeSidebar` takes one binding, `mode`. `railCollapsed` is `@AppStorage`
  (`:44`), not a parameter, so Task 5's two-argument construction was invalid.
- `NSColor.saturationComponent` raises for colours outside an HSB-compatible space,
  and `colorAt` returns whatever the bitmap uses. Both saturation tests now compute
  `(max - min) / max` from the channels, which cannot throw.

**Known-fragile assertions, flagged rather than hidden.** Four numeric thresholds
(`0.06` corner distance, `60` warm pixels, `0.15` saturation, `900` violet pixels) were
derived from the frame sizes written into each test. Each step says what to do if the red
state does not appear, and none of them says "lower the threshold" — the instruction is
to open the PNG first. The `0.02` and `0.04` channel margins are floors and must not be
loosened.
