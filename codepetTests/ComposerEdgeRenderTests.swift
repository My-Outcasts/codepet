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
