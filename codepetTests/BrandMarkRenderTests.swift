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
}
