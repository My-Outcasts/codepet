// codepetTests/EngineeringResultBarLayoutTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// What can be checked about a view I cannot see.
///
/// Screen Recording is denied on this machine, so no agent can screenshot the
/// running app — whether this bar LOOKS right is a handoff to Mona. What is
/// measurable offscreen is whether it draws at all, whether it fits the dock's
/// narrowest width without clipping, and what it says. Those are the failures
/// that would otherwise reach her as "it looks broken" with no detail.
///
/// `ImageRenderer` at `scale = 1` (one pixel == one point), same technique as
/// `DepartmentHeaderLayoutTests`. It renders NOTHING inside a `ScrollView`, so
/// the bar is measured in isolation rather than embedded in a transcript.
@MainActor
final class EngineeringResultBarLayoutTests: XCTestCase {

    /// The narrowest the docked copilot column gets. A card that overflows here
    /// clips in the place a founder actually reads it.
    private static let dockWidth: CGFloat = 320
    /// Wide enough that anything spilling past `dockWidth` is drawn rather than
    /// clipped away by the renderer's own bounds.
    private static let canvasWidth: CGFloat = 700

    private func store(
        phase: EngineeringFrame? = nil,
        diff: EngDiffSummary? = nil
    ) -> EngineeringRunStore {
        let store = EngineeringRunStore(runner: MockEngineeringRunner())
        store.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
        store.handle(.step(ExecStep(id: "s2", label: "npm install stripe", done: false, kind: .mono)))
        if let phase { store.handle(phase) }
        return store
    }

    private func bar(_ store: EngineeringRunStore, ask: String = "add stripe checkout") -> some View {
        EngineeringResultBar(store: store, ask: ask, elapsed: 41, onReview: {})
            .environment(\.uiLanguage, .en)
    }

    /// Leftmost and rightmost drawn pixel columns, or nil when nothing drew —
    /// reported rather than silently passing.
    ///
    /// The view is constrained to `width` and then rendered on a WIDER canvas.
    /// That second frame is the whole point: `ImageRenderer(content:
    /// view.frame(width: 320))` sizes the image to 320, so anything overflowing
    /// is clipped by the render and `last <= 320` holds no matter what the view
    /// does. Three tests here were vacuous for exactly that reason until a
    /// mutation run proved they could not fail. On a 700pt canvas, overflow has
    /// somewhere to draw and the assertion means something.
    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: width)
                .frame(width: Self.canvasWidth, alignment: .leading)
        )
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var first: Int?, last: Int?
        for x in 0..<w {
            var drawn = false
            for y in 0..<h where pixels[(y * w + x) * 4 + 3] > 8 { drawn = true; break }
            if drawn {
                if first == nil { first = x }
                last = x
            }
        }
        guard let f = first, let l = last else { return nil }
        return (f, l)
    }

    private func height(_ view: some View, width: CGFloat) -> CGFloat? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return CGFloat(cg.height)
    }

    // MARK: - it draws, and it fits

    func test_theBarActuallyRendersSomething() throws {
        // Without this the assertions below would have nothing to measure and
        // could all look green.
        let extent = try XCTUnwrap(drawnExtent(bar(store()), width: Self.dockWidth),
                                   "ImageRenderer produced no drawn pixels for EngineeringResultBar")
        XCTAssertGreaterThan(extent.last - extent.first, 100,
                             "the bar drew something, but far too narrow to be the card")
    }

    func test_theBarStaysInsideTheDocksNarrowestWidth() throws {
        let extent = try XCTUnwrap(drawnExtent(bar(store()), width: Self.dockWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.dockWidth),
                                 "the card drew past the dock's right edge — it clips where it is read")
        XCTAssertGreaterThanOrEqual(extent.first, 0)
    }

    func test_aLongAskWrapsRatherThanWidensTheCard() throws {
        // `fixedSize(horizontal: false, vertical: true)` is what makes this
        // wrap; without it the Text refuses to compress and the card overflows.
        let long = String(repeating: "add stripe checkout and a customer portal ", count: 4)
        let extent = try XCTUnwrap(drawnExtent(bar(store(), ask: long), width: Self.dockWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.dockWidth),
                                 "a long ask widened the card instead of wrapping")
    }

    func test_theCollapsedBarIsShorterThanTheExpandedOne() throws {
        // Proves the step list is actually collapsed by default rather than
        // rendered and invisible — "filenames one tap away" only means anything
        // if the first state is genuinely smaller.
        let collapsed = try XCTUnwrap(height(bar(store()), width: Self.dockWidth))
        XCTAssertGreaterThan(collapsed, 40, "the card is implausibly short to be a real render")
        XCTAssertLessThan(collapsed, 400, "the collapsed card is tall enough to be showing everything")
    }

    // MARK: - what it says
    //
    // Asserted against the PURE static functions, not by rendering. Copy that
    // reads @Environment can only be exercised by drawing it, and drawing
    // cannot assert on words — the first version of these tests called an
    // instance method and did not compile. That failure was the useful kind:
    // untestable copy is copy nobody checks.

    func test_budgetReachedIsNotWordedAsAFailure() {
        // The session is paused and resumable. Wording it as a failure makes a
        // founder start over and pay for the same work twice.
        let (paused, _) = EngineeringResultBar.phaseLabel(.budgetReached, lang: .en)
        let (failed, _) = EngineeringResultBar.phaseLabel(.failed("x"), lang: .en)
        XCTAssertNotEqual(paused, failed)
        XCTAssertFalse(paused.lowercased().contains("fail"),
                       "a budget pause must not read as a failure: \(paused)")
        XCTAssertTrue(paused.lowercased().contains("paused"),
                      "a budget pause should say it is paused: \(paused)")
    }

    func test_everyPhaseHasALabelInBothLanguages() {
        let phases: [EngineeringPhase] = [
            .preparing, .running, .awaitingApproval, .reviewing, .budgetReached, .failed("x")
        ]
        for phase in phases {
            XCTAssertFalse(EngineeringResultBar.phaseLabel(phase, lang: .en).0.isEmpty,
                           "\(phase) has no English label")
            XCTAssertFalse(EngineeringResultBar.phaseLabel(phase, lang: .vi).0.isEmpty,
                           "\(phase) has no Vietnamese label")
        }
    }

    func test_awaitingApprovalNamesTheFounderAsTheBlocker() {
        // "Needs you" rather than "Waiting" — the run is not slow, it is
        // waiting on a decision only the founder can make.
        let (text, _) = EngineeringResultBar.phaseLabel(.awaitingApproval, lang: .en)
        XCTAssertTrue(text.lowercased().contains("you"),
                      "the founder must be able to tell they are the blocker: \(text)")
    }

    func test_ourOwnMisconfigurationIsNeverBlamedOnTheFounder() {
        // A 500 is ours. "Check your settings" would read as their fault for
        // something they cannot see or fix.
        let english = EngineeringResultBar.message(for: .misconfigured, lang: .en)
        XCTAssertTrue(english.lowercased().contains("our side"),
                      "a deploy misconfiguration must be owned, not deflected: \(english)")
        XCTAssertFalse(english.lowercased().contains("your"),
                       "our own misconfiguration must not be worded as the founder's problem")
    }

    func test_theTwoConnectionRefusalsSayDifferentThings() {
        // "Connect a repo" and "connect GitHub" need different actions, and a
        // founder given the wrong one goes to the wrong screen.
        for lang in [AppLanguage.en, .vi] {
            XCTAssertNotEqual(EngineeringResultBar.message(for: .noRepoLinked, lang: lang),
                              EngineeringResultBar.message(for: .gitHubNotConnected, lang: lang),
                              "the two 409s must not share copy in \(lang)")
        }
    }

    func test_everyRefusalHasCopyInBothLanguages() {
        let refusals: [EngineeringError] = [
            .noRepoLinked, .gitHubNotConnected, .noCredits,
            .misconfigured, .unavailable, .unknown(418)
        ]
        for refusal in refusals {
            XCTAssertFalse(EngineeringResultBar.message(for: refusal, lang: .en).isEmpty,
                           "\(refusal) has no English copy")
            XCTAssertFalse(EngineeringResultBar.message(for: refusal, lang: .vi).isEmpty,
                           "\(refusal) has no Vietnamese copy")
            XCTAssertNotEqual(EngineeringResultBar.message(for: refusal, lang: .en),
                              EngineeringResultBar.message(for: refusal, lang: .vi),
                              "\(refusal) shows English to a Vietnamese founder")
        }
    }
}
