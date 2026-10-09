// codepetTests/RoomOfferWireTests.swift
import XCTest
@testable import codepet

/// 9 Oct: the wire for "Bring Finance + Sales in" — `room_offer` arrives on the done frame, and
/// the room request carries the founder's pick as `agents`, omitted when there is none.
final class RoomOfferWireTests: XCTestCase {
    private func done(_ json: String) async throws -> ChatDoneAction? {
        var action: ChatDoneAction?
        let stream = AsyncThrowingStream<CompanyChatStreamEvent, Error> { c in
            try? CompanyChatClient.handleStreamFrame(frame: SSEFrame(event: "done", data: json), continuation: c)
            c.finish()
        }
        for try await ev in stream { if case .done(_, _, let a) = ev { action = a } }
        return action
    }

    func testTheDoneFrameCarriesARoomOffer() async throws {
        let a = try await done(#"{"model":"m","cache_hit":false,"run_task_id":null,"room_offer":{"departments":["fin","sales"],"question":"Discount?","why":"They pull apart."}}"#)
        XCTAssertEqual(a?.roomOffer, RoomOfferDTO(departments: ["fin", "sales"], question: "Discount?", why: "They pull apart."))
    }

    func testADoneFrameWithoutOneHasNone() async throws {
        let a = try await done(#"{"model":"m","cache_hit":false,"run_task_id":null}"#)
        XCTAssertNotNil(a)
        XCTAssertNil(a?.roomOffer)
    }

    private let founder = VCFounder(profile: "", stage: "", constraints: [])

    /// Without a pick the request is byte-identical to before: no `agents` key at all.
    func testARoomRequestWithoutAPickHasNoAgentsKey() throws {
        let r = VirtualCompanyRequest(request: "q", language: "en", founder: founder, stressTest: false)
        let json = String(data: try JSONEncoder().encode(r), encoding: .utf8)!
        XCTAssertFalse(json.contains("agents"))
    }

    func testARoomRequestCarriesTheFoundersPick() throws {
        let r = VirtualCompanyRequest(request: "q", language: "en", founder: founder, stressTest: false,
                                      agents: ["finance", "sales"])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as! [String: Any]
        XCTAssertEqual(obj["agents"] as? [String], ["finance", "sales"])
    }
}
