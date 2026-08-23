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

    private enum RenderFailure: Error { case producedNothing }

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
            // throw to abort.
            XCTFail("ImageRenderer produced nothing for ChatComposer")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("composer-edge-\(name).png")
        try png.write(to: url)
        print("[render] \(url.path)")
        return (rep, url)
    }

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

    /// Strongest-saturation pixel in the frame, among pixels bright enough to be
    /// the edge or an accent tint rather than dark UI chrome.
    ///
    /// **Measured, not assumed.** The brief's premise — "the edge is the only
    /// saturated thing... the send button is `mutedText`... the placeholder is
    /// grey" — missed the `+` glyph. `bodyText` is `#332e27`, and by
    /// `(max-min)/max` that solid dark brown measures **~0.235** saturation: higher
    /// than `cardEdge`'s ~0.04 and higher than the 0.15 floor test 1 asserts. With
    /// no brightness floor, `mostSaturated` found the `+` glyph in every render —
    /// RED and GREEN alike, `showsDeptChips: false` or not — never the edge itself.
    /// That made both assertions measure `bodyText`'s own fixed green/blue
    /// relationship instead of the thing under test: test 1 passed unconditionally
    /// (the glyph's saturation alone clears 0.15), and test 2 failed unconditionally
    /// (the glyph's green exceeds its blue by only ~0.03, short of the 0.05 margin)
    /// — regardless of which accent color was ever passed in.
    ///
    /// `cardEdge`, the ramp blended over `cardRaised`/cream at either opacity, and
    /// `mutedText` are all light (every channel's max component sits at 0.7+); the
    /// composer's dark UI chrome (`bodyText`, `mutedText`'s foreground, icon glyphs)
    /// tops out under 0.4. 0.5 sits with room on both sides of that measured gap.
    ///
    /// The floor is what makes this work, and it is load-bearing on two facts that
    /// are true today and not guaranteed:
    ///
    /// - `CodepetTokens.cardRaised` is `#ffffff` in light mode, so any accent
    ///   blended at 0.35 opacity over it keeps a max channel ≥0.65, comfortably
    ///   clearing 0.5.
    /// - no current companion accent is dark.
    ///
    /// Break either — a darker `cardRaised`, or a dark pet accent colour — and this
    /// floor would start skipping the real edge pixel, and this test would then
    /// measure something else (or nothing) while still passing.
    private func mostSaturated(_ rep: NSBitmapImageRep) -> NSColor? {
        var best: NSColor?
        var bestSat: CGFloat = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let hi = max(c.redComponent, max(c.greenComponent, c.blueComponent))
                guard hi > 0.5 else { continue }
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
        // Measured resting peak: ~0.199 — headroom of ~0.05 above the 0.15 floor,
        // not razor-thin but not huge either.
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

    // MARK: - Sidebar mode switch: active segment body

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

        // Pin `seenDeveloperKey` to `false` to ensure the hint below the mode
        // switch renders. Without this pin, a founder who has opened Developer
        // mode will have the key set to `true`, causing the hint to disappear and
        // the workspace nav content (which includes a violet-highlighted "Roadmap"
        // row) to shift up into this crop. That contamination would make the test
        // measure the wrong violet pixels and pass for the wrong reason. The crop
        // height (130pt) is load-bearing on this being false.
        let previousSeenDeveloper = UserDefaults.standard.value(forKey: WorkspaceMode.seenDeveloperKey)
        defer {
            if let previousSeenDeveloper {
                UserDefaults.standard.set(previousSeenDeveloper, forKey: WorkspaceMode.seenDeveloperKey)
            } else {
                UserDefaults.standard.removeObject(forKey: WorkspaceMode.seenDeveloperKey)
            }
        }
        UserDefaults.standard.set(false, forKey: WorkspaceMode.seenDeveloperKey)

        // `mode` is the ONLY binding — `railCollapsed` is `@AppStorage`
        // (`TwoModeSidebar.swift:44`), not a parameter. Passing it does not compile.
        //
        // Height 130, alignment .top — NOT the plan's original 240×120 with no
        // alignment. `TwoModeSidebar`'s body is one VStack (brand, modeSwitch,
        // +New, search, workspace, a scrolling session list, account) far taller
        // than 120pt; `.frame(width:height:)` defaults to `alignment: .center`,
        // so an unaligned 120pt-tall frame centers that oversized VStack and the
        // visible window becomes a CROPPED MIDDLE SLICE — in practice the
        // workspace nav list (which has its own violet-highlighted active row,
        // "Lộ trình"/Roadmap) with brand and modeSwitch scrolled off above it
        // entirely. Measured by rendering at height 500 with alignment: .top and
        // reading the PNG: confirmed. `alignment: .top` plus 130pt (brand ~40pt +
        // modeSwitch ~64pt + margin) isolates brand+modeSwitch cleanly, verified
        // by inspecting the render — no workspace content, no false-peak glyphs.
        let host = TwoModeSidebar(mode: .constant(.ask))
            .environmentObject(CompanyStore())
            .environmentObject(AppState())
            .frame(width: 240, height: 130, alignment: .top)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // A nil render is a FAILURE, not a skip — see the class-level enum doc.
            XCTFail("ImageRenderer produced nothing for TwoModeSidebar")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("mode-switch.png")
        try png.write(to: url)
        print("[render] \(url.path)")
        // Count violet-leaning pixels: blue clearly above green, saturation above
        // cardRaised's zero. Purple TEXT alone at this size contributes a few dozen
        // pixels; a tinted fill plus a tinted edge contributes hundreds.
        //
        // Re-measured with the reference-ground exclusion below in place, by
        // actually removing and restoring TwoModeSidebar.swift's tinted overlay
        // fill and stroke (leaving only the accented text), each reading taken
        // twice and requiring the pair to be identical before trusting it (a
        // sibling session's concurrent `xcodebuild` can kill the test host
        // mid-run — the symptom is a run failing to finish, not a wrong number —
        // so two consistent readings are what rule that out), on this exact host
        // (240×130@2x, top-aligned, brand+modeSwitch only):
        //   RED  (text only)                        =  408 (identical x2)
        //   GREEN (tinted fill + 0.45 stroke, prod)  = 1492 (identical x2)
        // Unchanged from the pre-exclusion measurement — today's cream ground
        // never came close to the blue>green margin, so the exclusion currently
        // admits everything it did before. Its purpose is future, not present: it
        // is what stops #121019's blue lead of 0.035 from flooding this count once
        // the retint lands. 3.66x apart, not a squeezed gap. 900 sits with real
        // headroom on both sides: +492 (120% of RED) above RED, -592 (40% of GREEN)
        // below GREEN.
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
        XCTAssertGreaterThan(violet, 900,
                             "the active mode segment has no purple body — only its text is "
                             + "accented, which is what it did before. See \(url.path)")
    }

    // MARK: - Sidebar surface level

    /// Renders a token through the same pipeline the app draws with. Not
    /// `NSColor(someColor)` — bridging a SwiftUI `Color` can resolve eagerly, outside
    /// any appearance block, and would hand back the LIGHT value while claiming dark.
    @MainActor
    private func rendered(_ color: Color, _ scheme: ColorScheme) throws -> NSColor {
        let swatch = Rectangle().fill(color)
            .frame(width: 20, height: 20)
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: swatch)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
                  .usingColorSpace(.sRGB) else {
            XCTFail("token swatch render produced nothing")
            throw RenderFailure.producedNothing
        }
        return c
    }

    private func dist(_ a: NSColor, _ b: NSColor) -> CGFloat {
        abs(a.redComponent - b.redComponent)
            + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent)
    }

    /// The sidebar must be drawn at the RAIL level, not the card level.
    ///
    /// This is the only assertion that can catch this task's actual change. The mode
    /// switch needs three distinct surfaces — the rail it sits on, the track beneath
    /// it, the card lifted above — and the prototype has all three
    /// (`--app-rail` / `--app-ground` / `--app-panel`). This app collapsed "sidebar"
    /// and "card" into one `surface` token, so after the retint the lifted card is
    /// byte-identical to the sidebar behind it: a track you can see and a card you
    /// cannot.
    ///
    /// **It renders the sidebar and asks what colour it came out.** An earlier draft
    /// asserted the token LADDER instead — which `AppThemeTests` already covers, and
    /// which this task's one-line edit does not affect, so it passed identically before
    /// and after and tested nothing about this change.
    ///
    /// The sample is the MODAL colour of the right-hand strip, which is sidebar padding:
    /// no text, no card, no mode switch. Taking the most common value by area rather
    /// than a single pixel keeps it robust against sub-pixel antialiasing.
    @MainActor
    func testTheSidebarIsDrawnAtTheRailLevel() throws {
        let host = TwoModeSidebar(mode: .constant(.ask))
            .environmentObject(CompanyStore())
            .environmentObject(AppState())
            .frame(width: 240, height: 130, alignment: .top)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            XCTFail("sidebar render produced nothing")
            throw RenderFailure.producedNothing
        }

        // Right-hand strip: x from 92% to 98% of the width, full height.
        var counts: [Int: Int] = [:]
        let x0 = Int(Double(rep.pixelsWide) * 0.92), x1 = Int(Double(rep.pixelsWide) * 0.98)
        for y in 0..<rep.pixelsHigh {
            for x in x0..<x1 {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = Int(c.redComponent * 255) << 16
                    | Int(c.greenComponent * 255) << 8 | Int(c.blueComponent * 255)
                counts[key, default: 0] += 1
            }
        }
        guard let modal = counts.max(by: { $0.value < $1.value })?.key else {
            XCTFail("no pixels sampled from the sidebar strip")
            throw RenderFailure.producedNothing
        }
        let actual = NSColor(srgbRed: CGFloat((modal >> 16) & 0xff) / 255,
                             green: CGFloat((modal >> 8) & 0xff) / 255,
                             blue: CGFloat(modal & 0xff) / 255, alpha: 1)

        let rail = try rendered(CodepetTokens.surface2, .dark)
        let card = try rendered(CodepetTheme.surface, .dark)
        let toRail = dist(actual, rail), toCard = dist(actual, card)
        XCTAssertLessThan(toRail, toCard,
                          "the sidebar rendered closer to `surface` (\(toCard)) than to "
                          + "`surface2` (\(toRail)) — it is still drawn at the card level, "
                          + "so the mode switch has no visible lifted card")
    }

    // MARK: - Focused state: unverified offscreen

    /// Neither test above exercises `.opacity(focus.wrappedValue ? 0.9 : 0.35)`'s
    /// focused branch, so a swapped ternary (0.9 and 0.35 traded) would ship
    /// undetected by this file. That gap was checked, not assumed:
    ///
    /// Tried forcing it — a host variant that set `@FocusState private var focused`
    /// to `true` from `.onAppear` before rendering. The peak saturation measured
    /// **identical** to the resting render, to the full precision of the float
    /// (`0.19918614589212516` both times) — the state change had no visible effect
    /// on the pixels at all. The console corroborates why: this suite's every run
    /// logs `[SwiftUI] Accessing FocusState's value outside of the body of a View.
    /// This will result in a constant Binding of the initial value and will not
    /// update.` `@FocusState` engages through the responder chain of a real window;
    /// `ImageRenderer` never creates one, so there is no first responder for focus
    /// to move to, and `focus.wrappedValue` is frozen at whatever it started as
    /// regardless of what mutates it.
    ///
    /// So this is a genuine, not a lazy, gap: a focused render is not achievable
    /// offscreen with this harness, and no test here can catch the ternary being
    /// swapped. What would catch it instead: a human opening the composer, clicking
    /// into the field, and confirming the edge visibly brightens versus at rest —
    /// the same manual check this suite's own doc comment says the ambient-wash
    /// regression needed. `CLAUDE.md`'s landmine list already treats "no window in
    /// tests" as a standing constraint (`ImageRenderer` inside a `ScrollView`
    /// renders nothing, for the same underlying reason), so this is that same
    /// ceiling, not a new one.
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
            isBusy: false,
            // `showsDeptChips: false` — the two-mode hero configuration
            // (`CopilotChatView.swift:169`), and a deliberate detour from the
            // brief's host, which left this at its `true` default. With it `true`,
            // `departmentControl`'s `Menu(...).menuStyle(.borderlessButton)` renders,
            // under THIS `ImageRenderer` host, as a solid yellow capsule stamped with
            // a red "not allowed" glyph — full saturation, dwarfing anything the
            // stroke under test could produce, in both the rest and focused frames.
            // It reproduced identically across repeated runs, so it is a rendering
            // defect in offscreen `.borderlessButton` Menus, not a flake — and with
            // it present, `mostSaturated` always found the glyph, never the edge:
            // `testTheRestingEdgeIsVisibleOnCream` passed at RED for the wrong
            // reason, which is a test that protects nothing. Hiding the chip control
            // is itself a real, shipped surface state, not a workaround invented for
            // the test.
            showsDeptChips: false,
            selectedDept: $dept,
            onSend: {}, onQuickAction: { _ in }
        )
        .padding(20)
    }
}
