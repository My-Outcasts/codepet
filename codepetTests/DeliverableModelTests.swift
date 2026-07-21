// codepetTests/DeliverableModelTests.swift
import XCTest
@testable import codepet

final class DeliverableModelTests: XCTestCase {
    func testKindLabelsAndIconsNonEmptyBothLanguages() {
        for k in DeliverableKind.allCases {
            XCTAssertFalse(k.label(.en).isEmpty)
            XCTAssertFalse(k.label(.vi).isEmpty)
            XCTAssertFalse(k.icon.isEmpty)
        }
    }
    func testUnknownKindFallsBackToOther() {
        XCTAssertEqual(DeliverableKind(raw: "wat"), .other)
        XCTAssertEqual(DeliverableKind(raw: "plan"), .plan)
        let data = "\"wat\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(DeliverableKind.self, from: data), .other)
    }
    func testDeliverableRoundTripsWithNilOptionals() throws {
        let d = Deliverable(id: "d1", kind: .doc, title: "Scope", body: "# Hi")
        XCTAssertNil(d.createdAt)
        XCTAssertNil(d.sourceTaskId)
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
