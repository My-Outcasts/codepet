import XCTest
@testable import codepet

final class DeliverablePayloadTests: XCTestCase {
    func testChecklistPayloadRoundTrips() throws {
        let d = Deliverable(kind: .checklist, title: "T", body: "md",
            payload: DeliverablePayload(items: [ChecklistItem(t: "Step", done: false)]))
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.payload?.items?.first?.t, "Step")
    }
    func testLegacyDeliverableWithoutPayloadDecodes() throws {
        let legacy = #"{"id":"x","kind":"post","title":"T","body":"md"}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(legacy.utf8))
        XCTAssertNil(back.payload)
    }
    func testDecodesStructuredPayloadFromCFShape() throws {
        let json = #"{"id":"y","kind":"plan","title":"P","body":"md","payload":{"goal":"g","steps":["a"],"changes":[{"area":"x","edit":"y"}],"verify":[],"risks":"r"}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.goal, "g")
        XCTAssertEqual(back.payload?.changes?.first?.area, "x")
    }
}
