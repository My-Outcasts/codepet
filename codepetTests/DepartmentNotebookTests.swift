// codepetTests/DepartmentNotebookTests.swift
import XCTest
@testable import codepet

/// 9 Oct: decisions had no department, so Finance's runway was one line among thirty
/// company-wide facts and the desk could not tell which were Finance's.
final class DepartmentNotebookTests: XCTestCase {
    private func x(_ topic: String, _ s: String) -> ExtractedDecision { ExtractedDecision(topic: topic, statement: s, source: nil) }

    func testMergeStampsTheDepartment() {
        let m = Decisions.mergeDecisions(existing: [], extracted: [x("runway", "8 months")], now: 1, dept: "fin")
        XCTAssertEqual(m.first?.dept, "fin")
    }

    /// One truth per topic: Sales re-recording the price replaces Finance's and takes the tag.
    func testSameTopicFromAnotherDepartmentReplacesAndRetags() {
        let a = Decisions.mergeDecisions(existing: [], extracted: [x("pricing", "$19")], now: 1, dept: "fin")
        let b = Decisions.mergeDecisions(existing: a, extracted: [x("Pricing", "$29")], now: 2, dept: "sales")
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.statement, "$29")
        XCTAssertEqual(b.first?.dept, "sales")
    }

    func testNormalizeKeepsTheDepartment() {
        let e = DecisionEntry(topic: "runway", statement: "8 months", source: nil, updatedAt: 1, scope: nil, dept: "fin")
        XCTAssertEqual(Decisions.normalizeDecisions([e]).first?.dept, "fin")
    }

    func testCapIsSixty() {
        let many = (0..<70).map { x("t\($0)", "s") }
        XCTAssertEqual(Decisions.mergeDecisions(existing: [], extracted: many, now: 1).count, 60)
    }

    /// Stored before this field existed: decodes, and re-encodes without a `dept` key.
    func testAStoredDecisionWithoutDeptRoundTripsUnchanged() throws {
        let json = #"{"topic":"pricing","statement":"$19","updatedAt":1}"#
        let d = try JSONDecoder().decode(DecisionEntry.self, from: Data(json.utf8))
        XCTAssertNil(d.dept)
        let out = String(data: try JSONEncoder().encode(d), encoding: .utf8)!
        XCTAssertFalse(out.contains("dept"))
    }

    /// A company-wide re-record (a room lock-in, an ordinary turn) takes the topic off the
    /// department's desk: one truth per topic, and that truth is now nobody's in particular.
    func testReRecordingWithoutADepartmentClearsTheTag() {
        let a = Decisions.mergeDecisions(existing: [], extracted: [x("pricing", "$19")], now: 1, dept: "fin")
        let b = Decisions.mergeDecisions(existing: a, extracted: [x("pricing", "$24")], now: 2)
        XCTAssertEqual(b.count, 1)
        XCTAssertNil(b.first?.dept)
    }
}
