// codepetTests/RoomInviteTests.swift
import XCTest
@testable import codepet

/// 9 Oct: "Bring Finance + Sales in" — a department's offer on its reply, and the one press that
/// convenes exactly that room.
@MainActor
final class RoomInviteTests: XCTestCase {
    private let offer = RoomOfferDTO(departments: ["fin", "sales"], question: "Discount Pro to close more deals?",
                                     why: "Price and pipeline pull apart.")

    private final class Probe { var rooms: [VirtualCompanyRequest] = []; var turns = 0 }

    private func store(_ p: Probe) -> CompanyStore {
        let offer = self.offer
        return CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { _ in nil },
            chatStreamer: { _ in
                p.turns += 1
                let first = p.turns == 1
                return AsyncThrowingStream { c in
                    c.yield(.delta("My view, and Sales should weigh in."))
                    c.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction(roomOffer: first ? offer : nil)))
                    c.finish()
                }
            },
            vcRunner: { req in
                p.rooms.append(req)
                return AsyncThrowingStream { $0.finish() }
            })
    }

    private func offered(_ s: CompanyStore) async throws -> String {
        await s.hydrate(companyId: "u")
        await s.sendChat("should we discount?", language: .en, department: DepartmentCatalog.find("fin"))
        return try XCTUnwrap(s.chatMessages.last { $0.roomOffer != nil }?.id, "no offer landed on the reply")
    }

    func testTheOfferLandsOnTheReply() async throws {
        let s = store(Probe())
        let id = try await offered(s)
        XCTAssertEqual(s.chatMessages.first { $0.id == id }?.roomOffer, offer)
    }

    func testPressingConvenesExactlyThatRoomOnce() async throws {
        let p = Probe(), s = store(p)
        let id = try await offered(s)
        XCTAssertTrue(p.rooms.isEmpty, "an offer convenes nothing on its own")
        await s.acceptRoomOffer(messageId: id, language: .en)
        XCTAssertEqual(p.rooms.count, 1)
        XCTAssertEqual(p.rooms.first?.agents, ["finance", "sales"])
        XCTAssertEqual(p.rooms.first?.request, offer.question)
        XCTAssertTrue(s.chatMessages.first { $0.id == id }?.roomOfferUsed ?? false)
        await s.acceptRoomOffer(messageId: id, language: .en)
        XCTAssertEqual(p.rooms.count, 1, "a used offer cannot convene again")
    }

    /// The Swift map must agree with ROOM_AGENT_FOR in companyChatCore.ts, key for key.
    func testEveryChatDepartmentMapsToARoomAgent() {
        let expected = ["eng": "engineering", "design": "design", "mkt": "marketing", "sales": "sales",
                        "support": "support", "fin": "finance", "ops": "operations", "legal": "legal"]
        for (k, v) in expected { XCTAssertEqual(RoomInvite.roomAgentId(for: k), v, k) }
        XCTAssertNil(RoomInvite.roomAgentId(for: "product"))
    }
}
