// codepetTests/BrandMarkRenderTests.swift
import SwiftUI
import XCTest
@testable import codepet

/// Renders the hero offscreen and asserts the brand mark is actually VISIBLE on
/// the dark pane, because the native app cannot be screenshotted from here
/// (Screen Recording is denied) and "can you see the logo" is not a question a
/// test of numbers can answer.
///
/// This is a real guard, not a screenshot dump. `codepet-logo` is RGBA with a
/// fully transparent background and no ground of its own, so the ways it fails
/// are all silent: a missing asset renders nothing, and the dark navy outline
/// (`#2D2664`) against `pageBackground` (`#16130f`) is very nearly the same
/// value — draw only the outline and the mark disappears into the page without
/// anything throwing. Sampling for the violet FILL is what catches that.
///
/// `ImageRenderer` draws NOTHING inside a `ScrollView` — the hero is not in one,
/// which is the only reason this can work at all. The PNG is written beside the
/// assertion so a human can look at what was judged; the path is printed.
final class BrandMarkRenderTests: XCTestCase {

    /// A nil render is a FAILURE, not a skip. These are guards: if the hero ever ends up
    /// inside a `ScrollView`, `ImageRenderer` yields nothing, and a skip would let CI stay
    /// green with the guard silently gone. Matches the `XCTFail` the mark test above uses
    /// for this same condition.
    private enum RenderFailure: Error { case producedNothing }

    @MainActor
    func testTheBrandMarkIsVisibleOnTheDarkPane() throws {
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
        let url = URL(fileURLWithPath: dir).appendingPathComponent("hero-mark.png")
        try png.write(to: url)
        print("[render] \(url.path)")

        // The mark's band. NOT the top of the frame: the hero centres its stack, so
        // the glyph lands around 92–150pt in a 420pt frame, and a band measured from
        // the top edge samples empty background and "proves" the logo is missing.
        // 0..<155pt covers the mark and its glow and stops above the greeting, whose
        // accented word is a near-identical violet and would otherwise pass this test
        // on its own.
        let brandViolet = NSColor(srgbRed: 0.545, green: 0.482, blue: 0.910, alpha: 1) // ~#8B7BE8
        var violetPixels = 0
        let band = 0..<Int(155 * renderer.scale)
        for y in band {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Distance in RGB is crude but sufficient: nothing else in this band
                // is anywhere near the brand violet.
                let d = abs(c.redComponent - brandViolet.redComponent)
                    + abs(c.greenComponent - brandViolet.greenComponent)
                    + abs(c.blueComponent - brandViolet.blueComponent)
                if d < 0.25 { violetPixels += 1 }
            }
        }
        XCTAssertGreaterThan(violetPixels, 400,
                             "the C is not on screen — asset missing, or drawn in outline-only "
                             + "colours that vanish into pageBackground. See \(url.path)")
    }

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
            XCTFail("ImageRenderer produced nothing")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("hero-bloom.png")
        try png.write(to: url)
        print("[render] \(url.path)")

        // Warm means red leads blue. `pageBackground` (#16130f) is itself already
        // "warm" by this raw definition — R=0.0863, B=0.0588, a 0.0275 lead that
        // clears the +0.02 margin on its own. Counting it made the assertion
        // measure the band's background AREA rather than the bloom, so skipping
        // near-background pixels is what leaves only what the bloom actually
        // painted.
        //
        // Reference-based, so this epsilon no longer has to clear the ~0.0597
        // colour-management floor a comparison against the ideal `#16130f` hex
        // would carry (see `referenceGround`'s doc) — it only has to clear
        // per-pixel dither, which is why 0.02 replaces the old 0.08 (three-quarters
        // of which was noise budget, not signal).
        //
        // Re-measured against THIS reference-based exclusion by actually reverting
        // and restoring ChatEmptyState.swift (removing the `accentPink.opacity(0.18)`
        // middle stop for RED, restoring it for GREEN), each reading taken twice and
        // requiring the pair to be identical before trusting it (a sibling session's
        // concurrent `xcodebuild` can kill the test host mid-run — the symptom is a
        // run failing to finish, not a wrong number — so two consistent readings are
        // what rule that out):
        //   RED  (purple-only bloom)      =  8,329 warm pixels (identical x2)
        //   GREEN (production, pink stop) = 18,285 warm pixels (identical x2)
        // RED is not the near-zero this test originally expected of a "cool"
        // bloom — the purple core's blurred edge anti-aliases into the background,
        // and that boundary carries a few thousand pixels that read warm from
        // rendering noise alone, independent of the pink stop. These are the same
        // two numbers the ideal-hex version measured with its 0.08 epsilon: the old
        // epsilon already excluded true background reliably (0.0597 measured
        // distance well under 0.08), so tightening it to 0.02 against a reference
        // that measures ~0 for true background changes nothing about which pixels
        // are admitted — only how much of the epsilon is honest margin versus noise
        // budget. The RED→GREEN gap is a real 2.20x signal (18,285 / 8,329), clear
        // of the ~2x floor. Threshold is the midpoint (13,300): 4,971 of headroom
        // above RED (50.0% of the RED→GREEN span), 4,985 below GREEN (50.1%). Do not
        // loosen the `0.02` channel margin to "fix" a future threshold miss;
        // remeasure RED/GREEN instead.
        let ground = try referenceGround(colorScheme: .dark, width: 760, height: 420)
        let backgroundEpsilon: CGFloat = 0.02
        var warmPixels = 0
        let band = 0..<Int(155 * renderer.scale)
        for y in band {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let backgroundDistance = abs(c.redComponent - ground.redComponent)
                    + abs(c.greenComponent - ground.greenComponent)
                    + abs(c.blueComponent - ground.blueComponent)
                if backgroundDistance < backgroundEpsilon { continue }
                if c.redComponent > c.blueComponent + 0.02 { warmPixels += 1 }
            }
        }
        XCTAssertGreaterThan(warmPixels, 13_300,
                             "the bloom has no warm edge — the pink stop is missing, or the "
                             + "radial was replaced by a linear ramp. See \(url.path)")
    }

    /// Renders the pane the way the shell composes it and asserts the corners are
    /// the flat `pageBackground` — no ambient wash.
    ///
    /// This renders `CopilotChatView`, not `ChatEmptyState`, and the distinction is
    /// the whole test: the wash lived on `CopilotChatView`'s `.background`, so the
    /// bare hero already had flat corners and would have passed this without the
    /// change. Rendering the real composition is also what keeps this a guard —
    /// re-add an ambient gradient anywhere behind the pane and this fails again.
    ///
    /// The empty-hero path carries no `ScrollView` (the transcript's is at :595,
    /// the history's at :804, neither reachable with no threads), which is the only
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
            XCTFail("ImageRenderer produced nothing for CopilotChatView")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir)
            .appendingPathComponent("chat-pane-\(colorScheme == .dark ? "dark" : "light").png")
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
        let ground = try referenceGround(colorScheme: .dark, width: 760, height: 560)
        let corners = cornerSamples(rep, inset: 40 * 2)
        XCTAssertEqual(corners.count, 4, "could not sample four corners")
        for c in corners {
            let d = abs(c.redComponent - ground.redComponent)
                + abs(c.greenComponent - ground.greenComponent)
                + abs(c.blueComponent - ground.blueComponent)
            // GREEN (production, flat ground) = 0.0 exact, all 4 corners, reference-based
            // (see `referenceGround`'s doc). RED, measured by temporarily reconstructing the
            // deleted `ChatBackdrop` wash (`accentPurple.opacity(0.16)` radial, blur 60, the
            // exact view removed in 8ee9ff3) as a scratch `.overlay` on this same pane and
            // re-rendering through the identical pipeline: 0.024193063378334045, identical
            // across two runs. Threshold 0.012 is the RED/GREEN midpoint — 0.012 of headroom
            // above GREEN (49.6% of the RED→GREEN span), 0.012193 below RED (50.4%). This is
            // its own scheme's pair, not shared with light's: light's RED measured lower
            // (0.009053230285644531, below even the old 0.01), so a single shared threshold
            // can no longer serve both.
            XCTAssertLessThan(d, 0.012,
                              "the pane's corner is not flat pageBackground — an ambient "
                              + "wash is painting over it. See \(url.path)")
        }
    }

    @MainActor
    func testTheChatGroundIsFlatInLight() throws {
        let (rep, url) = try renderChatPane(colorScheme: .light)
        let ground = try referenceGround(colorScheme: .light, width: 760, height: 560)
        let corners = cornerSamples(rep, inset: 40 * 2)
        XCTAssertEqual(corners.count, 4, "could not sample four corners")
        for c in corners {
            let d = abs(c.redComponent - ground.redComponent)
                + abs(c.greenComponent - ground.greenComponent)
                + abs(c.blueComponent - ground.blueComponent)
            // Light's own prior threshold was 0.06 (not dark's 0.072 — the two differed
            // because the colour-management floors they had to straddle differed: ~0.0597
            // dark, ~0.0214 cream). GREEN (production, flat ground) = 0.0 exact, all 4
            // corners, reference-based (see `referenceGround`'s doc) — the reference cancels
            // that floor for both schemes alike, which is what let a shared 0.01 exist at
            // all. RED, measured by temporarily reconstructing the deleted `ChatBackdrop`
            // wash (`accentPurple.opacity(0.16)` radial, blur 60, the exact view removed in
            // 8ee9ff3) as a scratch `.overlay` on this pane in light mode and re-rendering
            // through the identical pipeline: 0.009053230285644531, identical across two
            // runs — BELOW the old hand-written 0.01, meaning that threshold would not have
            // caught this wash in light mode at all. Threshold 0.0045 is the RED/GREEN
            // midpoint — 0.0045 of headroom above GREEN (49.7% of the RED→GREEN span),
            // 0.004553 below RED (50.3%). Dark's measured RED came out higher
            // (0.024193063378334045), so the two schemes no longer share one threshold value.
            XCTAssertLessThan(d, 0.0045,
                              "the light pane's corner is not flat cream — an ambient "
                              + "wash is painting over it. See \(url.path)")
        }
    }
}
