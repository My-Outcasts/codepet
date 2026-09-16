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
}
