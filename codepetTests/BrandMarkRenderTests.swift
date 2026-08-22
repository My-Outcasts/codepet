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
}
