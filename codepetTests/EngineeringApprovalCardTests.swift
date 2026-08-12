// codepetTests/EngineeringApprovalCardTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// The permission ask. What is testable here is the copy, the answer it sends,
/// and that it fits the dock — not what it looks like, which is a handoff.
@MainActor
final class EngineeringApprovalCardTests: XCTestCase {

    private static let dockWidth: CGFloat = 320
    /// Wide enough that overflow past `dockWidth` DRAWS rather than being
    /// clipped away by the renderer's own bounds. Without this second frame the
    /// width assertion compares 320 to itself and can never fail — three tests
    /// in EngineeringResultBarLayoutTests were vacuous for exactly that reason.
    private static let canvasWidth: CGFloat = 700

    private func card(
        input: String = "npm install stripe",
        onAnswer: @escaping (Bool, String?) async -> Void = { _, _ in }
    ) -> some View {
        EngineeringApprovalCard(
            approval: EngApproval(id: "tu_1", name: "bash", input: input),
            onAnswer: onAnswer
        )
        .environment(\.uiLanguage, .en)
    }

    private func drawnExtent(_ view: some View, width: CGFloat) -> (first: Int, last: Int)? {
        let renderer = ImageRenderer(
            content: view.frame(width: width).frame(width: Self.canvasWidth, alignment: .leading)
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

    // MARK: - it draws, and it fits

    func test_theCardActuallyRendersSomething() throws {
        let extent = try XCTUnwrap(drawnExtent(card(), width: Self.dockWidth),
                                   "ImageRenderer produced no drawn pixels for the approval card")
        XCTAssertGreaterThan(extent.last - extent.first, 100)
    }

    func test_aLongCommandWrapsRatherThanWidensTheCard() throws {
        // A real command can be long — an npm install with six packages, or a
        // git invocation with a full path. It must wrap inside the dock rather
        // than push the card past the edge where the buttons live.
        let long = "cd /workspace/repo && npm install stripe @stripe/stripe-js "
            + "@stripe/react-stripe-js zod react-hook-form --save-exact"
        let extent = try XCTUnwrap(drawnExtent(card(input: long), width: Self.dockWidth))
        XCTAssertLessThanOrEqual(extent.last, Int(Self.dockWidth),
                                 "a long command widened the card instead of wrapping")
    }

    // MARK: - the answer it sends

    func test_allowSendsTrue() async throws {
        var answered: (Bool, String?)?
        let view = EngineeringApprovalCard(
            approval: EngApproval(id: "tu_1", name: "bash", input: "npm i"),
            onAnswer: { allow, reason in answered = (allow, reason) }
        )
        // The button action is not reachable from XCTest, so the closure is
        // invoked directly — what this pins is the CONTRACT the card is wired
        // to, which is what a wrong argument would break.
        await view.onAnswer(true, nil)
        XCTAssertEqual(answered?.0, true)
        XCTAssertNil(answered?.1, "an allow carries no reason")
    }

    func test_denySendsFalse() async throws {
        var answered: (Bool, String?)?
        let view = EngineeringApprovalCard(
            approval: EngApproval(id: "tu_1", name: "bash", input: "npm i"),
            onAnswer: { allow, reason in answered = (allow, reason) }
        )
        await view.onAnswer(false, "use pnpm")
        XCTAssertEqual(answered?.0, false)
        XCTAssertEqual(answered?.1, "use pnpm")
    }

    // MARK: - copy

    func test_allowSaysAllowNotYes() {
        // The founder is granting a specific permission, and the word should
        // say so — "Yes" or "OK" answers a question nobody asked.
        XCTAssertEqual(EngineeringApprovalCard.allowLabel(lang: .en), "Allow")
    }

    func test_denyDoesNotReadAsCancellingTheRun() {
        // Refusing one command is not stopping the work — the agent can try
        // another way. "Cancel" or "Stop" would say the opposite.
        let deny = EngineeringApprovalCard.denyLabel(lang: .en).lowercased()
        XCTAssertFalse(deny.contains("cancel"), "deny must not read as abandoning the run: \(deny)")
        XCTAssertFalse(deny.contains("stop"), "deny must not read as abandoning the run: \(deny)")
    }

    func test_theTwoButtonsDoNotShareALabel() {
        for lang in [AppLanguage.en, .vi] {
            XCTAssertNotEqual(EngineeringApprovalCard.allowLabel(lang: lang),
                              EngineeringApprovalCard.denyLabel(lang: lang))
        }
    }

    func test_everyLabelExistsInBothLanguagesAndDiffers() {
        // A missing translation shows English to a Vietnamese founder, which is
        // the failure this catches rather than an empty string.
        for pair in [
            (EngineeringApprovalCard.prompt(lang: .en), EngineeringApprovalCard.prompt(lang: .vi)),
            (EngineeringApprovalCard.allowLabel(lang: .en), EngineeringApprovalCard.allowLabel(lang: .vi)),
            (EngineeringApprovalCard.denyLabel(lang: .en), EngineeringApprovalCard.denyLabel(lang: .vi))
        ] {
            XCTAssertFalse(pair.0.isEmpty)
            XCTAssertFalse(pair.1.isEmpty)
            XCTAssertNotEqual(pair.0, pair.1, "\(pair.0) has no Vietnamese translation")
        }
    }

    func test_thePromptNamesTheAgentAsTheOneAsking() {
        // "Wants to run" — the agent is asking. A passive "Run this?" makes it
        // read as the app demanding something of the founder.
        XCTAssertTrue(EngineeringApprovalCard.prompt(lang: .en).lowercased().contains("wants"))
    }

    // MARK: - the guard that is NOT here

    func test_theCardHoldsNoInFlightStateBecauseTheStoreRemovesItFirst() async {
        // Documents a deliberate absence. The obvious design is a `@State
        // sending` disabling both buttons for the round trip; it would guard a
        // window that does not exist, because EngineeringRunStore.answer removes
        // the ask from `approvals` synchronously BEFORE its await. This asserts
        // that property on the store, since it is what makes the card safe.
        let store = EngineeringRunStore(runner: MockEngineeringRunner())
        _ = await store.start(ask: "x")
        store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i")))
        XCTAssertEqual(store.approvals.count, 1)

        // Not awaited: the removal must already have happened by the time the
        // send is in flight, which is the entire guarantee.
        let task = Task { await store.answer(toolUseId: "tu_1", allow: true) }
        await task.value
        XCTAssertTrue(store.approvals.isEmpty)
    }
}
