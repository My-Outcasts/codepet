// codepetTests/RoomGatingTests.swift
import XCTest
@testable import codepet

/// The Virtual Company is convened only from Plan.
///
/// It used to fan out on EVERY typed message in all three modes, with the router's escape hatch
/// as the only filter. That is the design's intent — the founder should not have to know when a
/// question deserves four departments — but a convened decision is measured at ~$0.20 against
/// ~$0.005 for an ordinary turn, so a casual Ask could cost forty times what it looked like it
/// would. Founder's call, Aug 7: gate it.
@MainActor
final class RoomGatingTests: XCTestCase {

    func testOnlyPlanMayConveneTheRoom() {
        XCTAssertTrue(ChatMode.plan.convenesRoom)
        XCTAssertFalse(ChatMode.ask.convenesRoom, "Ask is the cheap mode")
        XCTAssertFalse(ChatMode.build.convenesRoom, "the room deliberates; Build executes")
    }

    private func store(_ conveneSeen: @escaping (String) -> Void) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: [])
            },
            saver: { _, _ in true }, tasksSaver: { _, _ in true },
            chatSender: { _ in nil },
            chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
            vcRunner: { req in
                conveneSeen(req.request)
                return AsyncThrowingStream { $0.finish() }
            },
            decisionExtractor: { _, _ in [] })
    }

    /// The gate is on the FAN-OUT, so the proof is whether the runner is reached at all.
    func testAskDoesNotReachTheRoomRunner() async {
        var convened: [String] = []
        let s = store { convened.append($0) }
        await s.hydrate(companyId: "u")
        await s.sendChat("should we raise prices?", language: .en,
                         founderAsk: "should we raise prices?",
                         convenesRoom: ChatMode.ask.convenesRoom)
        XCTAssertTrue(convened.isEmpty, "an Ask must not spend ~$0.20 on a room")
    }

    func testPlanReachesTheRoomRunnerWithTheFoundersOwnWords() async {
        var convened: [String] = []
        let s = store { convened.append($0) }
        await s.hydrate(companyId: "u")
        // The composer sends SHAPED text to the companion and the raw words to the router.
        await s.sendChat(ChatMode.plan.shape("should we raise prices?", language: .en),
                         language: .en, founderAsk: "should we raise prices?",
                         convenesRoom: ChatMode.plan.convenesRoom)
        XCTAssertEqual(convened, ["should we raise prices?"],
                       "the router must get the founder's words, not the mode's framing")
    }

    /// The default is the safe one: a caller that has not thought about the room does not get a
    /// ~$0.20 call by omission.
    func testTheDefaultIsNoRoom() async {
        var convened: [String] = []
        let s = store { convened.append($0) }
        await s.hydrate(companyId: "u")
        await s.sendChat("what should I set up in my environment?", language: .en)
        XCTAssertTrue(convened.isEmpty)
    }
}
