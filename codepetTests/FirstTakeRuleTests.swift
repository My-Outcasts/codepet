// codepetTests/FirstTakeRuleTests.swift
import XCTest
@testable import codepet

/// CP-029: once the room lands, Codepet's first take is folded to one line and loses its own
/// offer. Before this, "Yes, make a new version" stayed purple above the room's "Lock this
/// decision in" — two primary buttons on one answer, and the founder could not tell which counted.
final class FirstTakeRuleTests: XCTestCase {
    private func reply(_ proposal: RoadmapProposal?, superseded: Bool) -> CopilotMessage {
        var m = CopilotMessage(role: .companion, text: "You've already got two in the Library…",
                               roadmapProposal: proposal)
        m.supersededByRoom = superseded
        return m
    }

    private let revise = RoadmapProposal.revise(libraryId: "lib1", title: "Landing page", note: "shorter")

    func testAFirstTakeTheRoomReplacedDrawsNoOffer() {
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(reply(revise, superseded: true)))
    }

    func testAReplyTheRoomDidNotReplaceKeepsItsOffer() {
        XCTAssertTrue(FirstTakeRule.drawsOwnOffer(reply(revise, superseded: false)))
    }

    /// Every offer-carrying branch of the message chain, not only the roadmap proposal: a first
    /// take can carry any of them, and each one drawn beside the room is a second primary action.
    func testNoOfferKindSurvivesTheRoom() {
        var m = CopilotMessage(role: .companion, text: "t", firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "Write the brief"))
        m.supersededByRoom = true
        m.chainOffer = nil
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(m), "first-run action")
        m.firstRunAction = nil
        m.blockedOffer = .grant(.claudeCode)
        XCTAssertFalse(FirstTakeRule.drawsOwnOffer(m), "grant offer")
    }

    /// The founder's own message is never a first take, whatever the flag says.
    func testTheFoundersOwnMessageIsNeverFolded() {
        var m = CopilotMessage(role: .me, text: "a landing page for this product")
        m.supersededByRoom = true
        XCTAssertFalse(FirstTakeRule.isFolded(m))
        XCTAssertTrue(FirstTakeRule.isFolded(reply(revise, superseded: true)))
    }
}

/// The race the on-screen check found: the room's card lands BEFORE the reply's roadmap offer
/// arrives. `handleRoadmapProposal` skips the room message when it looks for a reply to attach
/// to, found nothing else, and appended the offer as its own bubble under the room — a second
/// "Yes, add it" beside "Lock this decision in", which the fold above cannot see.
@MainActor
final class FirstTakeOfferRaceTests: XCTestCase {
    private static let deadStream: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private static func routing() -> VCRouting {
        let json: [String: Any] = ["decision": "multi_agent", "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        return try! JSONDecoder().decode(VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    private func store(replyDelayNanos: UInt64) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: [])
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in
                try? await Task.sleep(nanoseconds: replyDelayNanos)
                return CompanyChatReply(text: "Want me to put the pricing page on your roadmap?",
                                        addTask: AddTaskDTO(title: "Write the pricing page", detail: nil,
                                                             dept: "mkt", owner: nil))
            },
            chatStreamer: Self.deadStream,
            vcRunner: { _ in
                AsyncThrowingStream { cont in
                    Task {
                        cont.yield(.runStarted(runId: "r1"))
                        cont.yield(.routing(Self.routing()))
                        cont.finish()
                    }
                }
            },
            decisionExtractor: { _, _ in [] })
    }

    func testAnOfferThatArrivesAfterTheRoomIsNotDrawnBesideIt() async {
        let s = store(replyDelayNanos: 300_000_000)
        await s.hydrate(companyId: "u")
        await s.sendChat("a pricing page for this product", language: .en, convenesRoom: true)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }

        XCTAssertTrue(s.chatMessages.contains { $0.vcRun != nil }, "precondition: the room landed")
        let liveOffers = s.chatMessages.filter {
            $0.roadmapProposal != nil && !$0.actionConsumed && FirstTakeRule.drawsOwnOffer($0)
        }
        XCTAssertTrue(liveOffers.isEmpty,
                      "a drawn offer beside the room: \(liveOffers.map(\.text))")
    }
}
