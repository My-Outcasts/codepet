// codepetTests/DeliverableProvenanceTests.swift
import XCTest
@testable import codepet

final class DeliverableProvenanceTests: XCTestCase {
    /// Provenance is optional because every deliverable created before this field existed
    /// has none — and a card that invents one would be worse than a card that says nothing.
    func testADeliverableDecodedWithoutProvenanceHasNone() throws {
        let json = #"{"id":"d1","kind":"doc","title":"T","body":"B"}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertNil(d.producedBy)
    }

    func testProvenanceSurvivesARoundTrip() throws {
        var d = Deliverable(kind: .doc, title: "T", body: "B")
        d.producedBy = .codex
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Deliverable.self, from: data)
        XCTAssertEqual(back.producedBy, .codex)
    }

    /// An unrecognised provider string must not throw and take the whole deliverable with
    /// it — a future provider id read by an older build degrades to "unknown", not a crash.
    func testAnUnknownProviderStringDegradesToNil() throws {
        let json = #"{"id":"d1","kind":"doc","title":"T","body":"B","producedBy":"gemini"}"#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertNil(d.producedBy)
    }

    /// **Wire-format pin for all eight `CodingKeys`.** `Deliverable.CodingKeys` used to be
    /// synthesised; this branch made it an explicit, hand-written block, and every key string
    /// is now owned by whoever last touched it. The four tests above (plus the round-trip one)
    /// only ever exercise `id`/`kind`/`title`/`body`/`producedBy` — a silent rename of
    /// `createdAt`, `sourceTaskId`, or `payload` would stay green through all of them while
    /// orphaning every stored deliverable's task link on every founder's machine. The key
    /// strings below are literals, never derived from `CodingKeys` itself — deriving them would
    /// make this test re-check the enum against itself instead of against the wire.
    func testAllEightWireKeysArePinned() throws {
        let json = #"""
        {"id":"d1","kind":"doc","title":"T","body":"B","createdAt":"2026-09-16T00:00:00Z","sourceTaskId":"task-1","payload":{"call":"hello"},"producedBy":"claudeCode"}
        """#
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(d.id, "d1")
        XCTAssertEqual(d.kind, .doc)
        XCTAssertEqual(d.title, "T")
        XCTAssertEqual(d.body, "B")
        XCTAssertEqual(d.createdAt, "2026-09-16T00:00:00Z")
        XCTAssertEqual(d.sourceTaskId, "task-1")
        XCTAssertEqual(d.payload?.call, "hello")
        XCTAssertEqual(d.producedBy, .claudeCode)
    }

    /// `producedBy` must be ABSENT from the encoded output when nil, not present as JSON
    /// `null` — `encodeIfPresent` is what gives this, and a plain `encode` would silently
    /// change the wire shape for every deliverable with no recorded provenance (all of them
    /// before 16 Sep 2026).
    func testProducedByIsAbsentNotNullWhenNil() throws {
        let d = Deliverable(kind: .doc, title: "T", body: "B")
        let data = try JSONEncoder().encode(d)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse(obj.keys.contains("producedBy"),
                       "producedBy must be absent, not null, when there is no provenance")
    }
}
