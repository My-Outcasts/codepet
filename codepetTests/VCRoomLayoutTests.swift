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
        // Without this, `state.runId` stays nil, `canLockIn` is false, and every render
        // this fixture produces is missing `theCall`'s primary action ("Lock this
        // decision in"). Placed first to match the real event order (runStarted before
        // routing before positions before the brief).
        s.apply(.runStarted(runId: "r1"))
        let routing: [String: Any] = ["decision": "multi_agent",
                                      "agents": ["finance", "marketing", "engineering",
                                                 "operations", "product", "support"],
                                      "real_question": "Should we ship the paywall before launch?",
                                      "request_type": "DECISION"]
        s.apply(.routing(try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: routing))))
        // Without agent_start/agent_position, `state.agents` and `state.positions` stay
        // empty and `departmentsSaid` renders nothing REGARDLESS of the disclosure's
        // open/closed state — a "no department card" measurement would be meaningless in
        // the other direction: green with nothing rendered to test. Six real positions:
        // the three that conflict (below) plus operations/product/support, added so
        // `testNoDepartmentRendersAsACard` exercises all six department hues
        // (`accent(_:)` maps `fin`→gold, `mkt`→orange, `eng`→blue, `ops`→teal,
        // `product`→green, `support`→pink — see `DepartmentCatalog.all` in
        // Models/Department.swift) instead of leaving teal/green/pink structurally
        // incapable of failing.
        s.apply(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "finance", departmentKey: "fin"),
            VCPosition(stance: "do_not_proceed",
                       position: "We need revenue proof before turning billing on.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 4,
                       costToMyDept: "Delays the quarter's revenue forecast.", hardBlocker: nil)))
        s.apply(.agentStart(VCAgentMeta(agentId: "marketing", departmentKey: "mkt")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "marketing", departmentKey: "mkt"),
            VCPosition(stance: "proceed",
                       position: "Launch day is the only day the product gets free press attention.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 3,
                       costToMyDept: "Loses the press hook if the date slips.", hardBlocker: nil)))
        s.apply(.agentStart(VCAgentMeta(agentId: "engineering", departmentKey: "eng")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "engineering", departmentKey: "eng"),
            VCPosition(stance: "proceed_with_conditions",
                       position: "We can ship the price page now but won't commit a billing-on date yet.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 3,
                       costToMyDept: "Blocks the next two sprints' roadmap items.",
                       hardBlocker: "Stripe webhook integration is untested end to end.")))
        // The three added purely to exercise teal/green/pink (Finding 1). None of them
        // appear in the `conflicts` list below — the docstring's "three departments that
        // disagree" and the orange-branch reasoning stay about finance/marketing/engineering
        // only; these three just need to land a position so `departmentsSaid` renders them.
        s.apply(.agentStart(VCAgentMeta(agentId: "operations", departmentKey: "ops")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "operations", departmentKey: "ops"),
            VCPosition(stance: "proceed",
                       position: "Billing infrastructure can flip on any day we pick; ops just needs 48 hours notice.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 3,
                       costToMyDept: "Requires an on-call swap the week of launch.", hardBlocker: nil)))
        s.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "product", departmentKey: "product"),
            VCPosition(stance: "proceed_with_conditions",
                       position: "Ship the price page now, but hold the roadmap slot for billing until it's proven.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 3,
                       costToMyDept: "Keeps a roadmap slot reserved that could go to something else.", hardBlocker: nil)))
        s.apply(.agentStart(VCAgentMeta(agentId: "support", departmentKey: "support")))
        s.apply(.agentPosition(VCAgentMeta(agentId: "support", departmentKey: "support"),
            VCPosition(stance: "do_not_proceed",
                       position: "We have no billing-failure macros written yet; support will be improvising on day one.",
                       reasoning: "r", evidenceNeeded: [], risksIOwn: [], confidence: 4,
                       costToMyDept: "Ticket volume spikes with no playbook to hand new hires.", hardBlocker: nil)))
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
        // The fixture must stay representative: assert the primary action is offered so
        // it can never silently regress back to the unrepresentative version.
        XCTAssertTrue(s.canLockIn, "landedRoom() must offer the lock-in action to be representative")
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
                    name: String, openDepartments: Bool = false) throws -> (rep: NSBitmapImageRep, url: URL) {
        let room = VCRunCards(state: state, lockedIn: false, onLockIn: {},
                              openDepartmentsForTesting: openDepartments)
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

    /// No department renders as a tinted card.
    ///
    /// `positionCard` wrapped each department in `MessageCard(hue: accent(meta))` — a
    /// tinted, bordered panel carrying a name, a stance pill, confidence dots, the
    /// position, a "costs their department" line and an optional blocker. Three stacked
    /// were denser than the summary above them.
    ///
    /// Checked against every department hue the room can use, because a single hue would
    /// pass while the other two still drew cards.
    @MainActor
    func testNoDepartmentRendersAsACard() throws {
        let (rep, url) = try renderRoom(landedRoom(), scheme: .dark, name: "room-depts-dark",
                                        openDepartments: true)
        for (name, hue) in [("gold", CodepetTheme.accentGold),
                            ("orange", CodepetTheme.accentOrange),
                            ("blue", CodepetTheme.accentBlue),
                            ("teal", CodepetTheme.accentTeal),
                            ("green", CodepetTheme.accentGreen),
                            ("pink", CodepetTheme.accentPink)] {
            let fill = try cardFill(hue: hue, scheme: .dark)
            let n = count(rep, matching: fill, tolerance: 0.02)
            print("[measure] \(name) card-fill pixels = \(n)")
            // Measured with the disclosure forced open (`openDepartments: true` — without
            // that the disclosure defaults closed and every count is a vacuous 0 whether
            // or not `MessageCard` wraps the row), and with the fixture now landing all
            // six departments (fin/mkt/eng/ops/product/support — see `landedRoom()`), by
            // temporarily restoring `MessageCard(hue: accent(meta))` around `DepartmentRow`
            // in `positionRow` and re-running, then reverting exactly (confirmed via
            // `git diff --stat` before re-measuring GREEN): RED gold 33303 / orange 33429 /
            // blue 32532 / teal 33400 / green 32725 / pink 33287 — all six now genuinely
            // reachable, closing the "structurally incapable of failing" gap teal/green/pink
            // had when the fixture only routed to fin/mkt/eng. GREEN 0 across all six,
            // identical on two consecutive runs. Threshold sits far below the smallest
            // meaningful RED (32532, ~162x headroom) and comfortably above 0 to absorb
            // antialiasing noise.
            XCTAssertLessThan(n, 200,
                              "a department still renders as a \(name) tinted card "
                              + "(\(n) matching pixels). See \(url.path)")
        }
    }
}
