import XCTest
@testable import codepet

/// CP-002 B: outreach messages are templates addressed to an audience, never to an invented
/// person — and a set filed before the change, which says `name`, still opens.
final class DmsAudienceTests: XCTestCase {

    private func decode(_ messageJSON: String) throws -> DmMessage {
        let json = #"{"id":"d","kind":"dms","title":"T","body":"b","payload":{"messages":["# + messageJSON + #"]}}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        return try XCTUnwrap(d.payload?.messages?.first, "the message did not decode")
    }

    func testTheNewWireShapeDecodes() throws {
        XCTAssertEqual(try decode(#"{"audience":"lapsed journaler","note":"n","msg":"m"}"#).audience, "lapsed journaler")
    }

    func testALegacyNameDecodesAsTheAudience() throws {
        XCTAssertEqual(try decode(#"{"name":"Marta (Rye & Co)","note":"n","msg":"m"}"#).audience, "Marta (Rye & Co)")
    }

    func testAudienceWinsOverALegacyName() throws {
        XCTAssertEqual(try decode(#"{"name":"Sarah Chen","audience":"indie baker","note":"n","msg":"m"}"#).audience, "indie baker")
    }

    /// Re-saving an old set must migrate it, not write the old key back.
    func testEncodesAudienceOnly() throws {
        let data = try JSONEncoder().encode(DmMessage(audience: "indie baker", note: "n", msg: "m"))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["audience", "msg", "note"])
    }

    func testCopyAndExportSayForNotTo() throws {
        let messages = [DmMessage(audience: "indie baker", note: "sells out by noon", msg: "Hi [name]")]
        XCTAssertTrue(DmsViewer.copyAllText(messages).hasPrefix("For: indie baker\n"))
        XCTAssertFalse(DmsViewer.copyAllText(messages).contains("To: "))
        let d = Deliverable(kind: .dms, title: "Beta", body: "b", payload: DeliverablePayload(messages: messages))
        let file = try XCTUnwrap(DeliverableExport.files(for: d).first)
        XCTAssertEqual(file.name, "beta-1-indie-baker.txt")
        XCTAssertTrue(String(decoding: file.data, as: UTF8.self).hasPrefix("For: indie baker\n"))
    }

    func testTheSetSaysTheyAreTemplatesInBothLanguages() {
        XCTAssertTrue(DmsSetHeader.templateNote(.en).contains("type of person"))
        XCTAssertTrue(DmsSetHeader.templateNote(.vi).contains("kiểu người"))
    }
}
