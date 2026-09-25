// codepetTests/VCProgressStageTests.swift
import XCTest
@testable import codepet

/// The room always says what it is doing while it runs — including the stretch between the
/// last position and the brief, which used to show nothing at all.
@MainActor
final class VCProgressStageTests: XCTestCase {
    private let product = VCAgentMeta(agentId: "product", departmentKey: "product")
    private let marketing = VCAgentMeta(agentId: "marketing", departmentKey: "mkt")

    func testEachStageInOrder() async throws {
        var s = VirtualCompanyRunState()
        XCTAssertNil(VCProgressStage.from(s), "nothing convened yet")
        s.apply(.runStarted(runId: "r1"))
        XCTAssertEqual(VCProgressStage.from(s), .routing)
        s.apply(.agentStart(product)); s.apply(.agentStart(marketing))
        XCTAssertEqual(VCProgressStage.from(s), .answering(done: 0, total: 2))
        s.apply(.agentError(product, "x")); s.apply(.agentError(marketing, "y"))
        // The gap from the screenshot: everyone has answered, no brief yet.
        XCTAssertEqual(VCProgressStage.from(s), .comparing)
        let round = try JSONDecoder().decode(VCNegotiationRound.self, from: Data(#"{"round":1,"turns":[]}"#.utf8))
        s.apply(.negotiationRound(round))
        XCTAssertEqual(VCProgressStage.from(s), .negotiating(round: 1))
        s.apply(.done(runId: "r1", unresolved: false, skipped: nil))
        XCTAssertNil(VCProgressStage.from(s), "a finished room shows no spinner")
    }

    func testAFailedRoomShowsNoSpinner() async {
        var s = VirtualCompanyRunState()
        s.apply(.runStarted(runId: "r1")); s.apply(.agentStart(product))
        s.apply(.error("stream_lost", nil))
        XCTAssertNil(VCProgressStage.from(s))
    }

    func testEveryStageHasWords() async {
        for st in [VCProgressStage.routing, .answering(done: 1, total: 2), .comparing, .negotiating(round: 2), .finishing] {
            XCTAssertFalse(st.label(.en).isEmpty); XCTAssertFalse(st.label(.vi).isEmpty)
        }
    }
}
