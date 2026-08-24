// codepetTests/VCRoomLayoutTests.swift
import SwiftUI
import XCTest
@testable import codepet

/// The founder's complaint about a landed room was competing panels: six bordered
/// regions of equal weight, each with its own tint. These tests assert the panels that
/// should no longer be cards are not cards — by rendering the room and looking for the
/// tinted fill a `MessageCard` produces.
///
/// Compared against a RENDERED reference, never a computed blend. `MessageCard` fills
/// `surface` then overlays `hue.opacity(0.12)`, and the render pipeline shifts dark
/// near-blacks 0.03–0.07 brighter per channel — a recent "regression" was diagnosed
/// from exactly that arithmetic and turned out not to exist.
///
/// `ImageRenderer` draws NOTHING inside a `ScrollView`, so `VCRunCards` is rendered
/// directly rather than through the transcript that hosts it.
final class VCRoomLayoutTests: XCTestCase {

    private enum RenderFailure: Error { case producedNothing }

    /// A landed room with three departments that disagree — the shape in the founder's
    /// screenshots. Built through `apply` like `VirtualCompanyInterviewTests.finishedRun`.
    private func landedRoom() -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        let routing: [String: Any] = ["decision": "multi_agent",
                                      "agents": ["finance", "marketing", "engineering"],
                                      "real_question": "Should we ship the paywall before launch?",
                                      "request_type": "DECISION"]
        s.apply(.routing(try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: routing))))
        // Populates `pairs` (non-ALIGNED conflicts) so the block actually renders the
        // disagreement (orange) branch rather than the agreement (teal) one — without
        // this, `state.conflicts` stays empty, `pairs.isEmpty` is true, and the block
        // would only ever render teal, making an "orange card fill" measurement
        // meaningless regardless of whether the MessageCard wrapper is present.
        s.apply(.conflicts([
            VCConflict(a: "finance", b: "marketing", kind: "CONFLICT",
                       reason: "Finance wants revenue proof before launch; marketing wants the free press."),
            VCConflict(a: "marketing", b: "engineering", kind: "TENSION",
                       reason: "Marketing wants a firm date; engineering won't commit one for billing.")
        ]))
        s.apply(.brief(VCBrief(
            recommendation: "Put the price on the page at launch and switch billing on two weeks later.",
            confidence: 3, confidenceReason: "c",
            theRealDisagreement: "Whether a price is a promise you must be able to keep, or a positioning statement you are allowed to revise.",
            tradeoffFounderMustOwn: "Either you launch with a number you may have to change, or you launch without one and give up the only day the product gets free attention.",
            killCriteria: ["k"],
            nextAction: VCNextAction(action: "a", owner: "Founder"),
            whatWeDontKnow: "u", unresolved: true)))
        s.apply(.done(runId: "r1", unresolved: true, skipped: nil))
        return s
    }

    @MainActor
    private func render<V: View>(_ view: V, _ name: String) throws -> (rep: NSBitmapImageRep, url: URL) {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"] ?? NSTemporaryDirectory()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced nothing for \(name)")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("[render] \(url.path)")
        return (rep, url)
    }

    /// The room, rendered at a width close to the chat column.
    @MainActor
    func renderRoom(_ state: VirtualCompanyRunState, scheme: ColorScheme,
                    name: String) throws -> (rep: NSBitmapImageRep, url: URL) {
        let room = VCRunCards(state: state, lockedIn: false, onLockIn: {})
            .frame(width: 620, alignment: .topLeading)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, scheme)
        return try render(room, name)
    }

    /// The interior fill a `MessageCard` of this hue actually produces, measured.
    @MainActor
    func cardFill(hue: Color, scheme: ColorScheme) throws -> NSColor {
        let swatch = MessageCard(hue: hue) {
            Rectangle().fill(Color.clear).frame(width: 120, height: 60)
        }
        .frame(width: 160)
        .environment(\.colorScheme, scheme)
        let (rep, _) = try render(swatch, "cardfill-swatch")
        guard let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
            .usingColorSpace(.sRGB) else {
            XCTFail("card fill swatch produced no centre pixel")
            throw RenderFailure.producedNothing
        }
        return c
    }

    private func count(_ rep: NSBitmapImageRep, matching target: NSColor,
                       tolerance: CGFloat) -> Int {
        var n = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - target.redComponent)
                    + abs(c.greenComponent - target.greenComponent)
                    + abs(c.blueComponent - target.blueComponent)
                if d < tolerance { n += 1 }
            }
        }
        return n
    }

    /// The disagreement block must not be a tinted card.
    ///
    /// It keeps every word — `the_real_disagreement` verbatim per rule 3, the conflict
    /// pairs, the aligned line — and loses only its border and fill, so it reads as a
    /// continuation of the call rather than a second panel competing with it.
    @MainActor
    func testTheDisagreementBlockIsNotACard() throws {
        let (rep, url) = try renderRoom(landedRoom(), scheme: .dark, name: "room-dark")
        let orange = try cardFill(hue: CodepetTheme.accentOrange, scheme: .dark)
        let n = count(rep, matching: orange, tolerance: 0.02)
        print("[measure] orange card-fill pixels = \(n)")
        // Measured: RED 72052 (the block still a MessageCard, dark scheme) / GREEN 0
        // (a plain VStack with the hue only on the pairs/agreed text). Threshold sits
        // between them with headroom on both sides: ~144x below RED, and comfortably
        // above 0 to absorb any antialiasing noise from the orange-tinted text itself.
        XCTAssertLessThan(n, 500,
                          "the disagreement block still renders as an orange tinted card "
                          + "(\(n) matching pixels). See \(url.path)")
    }
}
