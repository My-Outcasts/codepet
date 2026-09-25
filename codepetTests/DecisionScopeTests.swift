// codepetTests/DecisionScopeTests.swift
import XCTest
@testable import codepet

/// Decisions belong to a project. A Team Build for Codepet was handed the $35-pants test's brand
/// because decisions had no project at all.
@MainActor
final class DecisionScopeTests: XCTestCase {
    private func d(_ topic: String, _ scope: String?) -> DecisionEntry {
        DecisionEntry(topic: topic, statement: "\(topic) for \(scope ?? "none")", source: nil, updatedAt: 1, scope: scope)
    }

    func testAnOpenProjectSeesItsOwnAndEverywhereButNotUnassignedOrOthers() async {
        let all = [d("brand", nil), d("pricing", "codepet"), d("voice", Decisions.everywhere), d("brand", "pants")]
        XCTAssertEqual(Decisions.applicable(all, project: "codepet").map(\.topic), ["pricing", "voice"])
        XCTAssertEqual(Decisions.unassigned(all, whileIn: "codepet").map(\.topic), ["brand"])
    }

    func testNoProjectOpenBehavesAsBeforePlusEverywhere() async {
        let all = [d("brand", nil), d("pricing", "codepet"), d("voice", Decisions.everywhere)]
        XCTAssertEqual(Decisions.applicable(all, project: nil).map(\.topic), ["brand", "voice"])
        XCTAssertEqual(Decisions.unassigned(all, whileIn: nil), [])
    }

    func testTheSameTopicInTwoProjectsIsTwoFacts() async {
        let existing = [d("brand", "pants")]
        let merged = Decisions.mergeDecisions(existing: existing,
                                              extracted: [ExtractedDecision(topic: "Brand", statement: "violet", source: nil)],
                                              now: 2, scope: "codepet")
        XCTAssertEqual(merged.count, 2, "Codepet's brand does not supersede the pants test's")
        XCTAssertEqual(merged.last?.scope, "codepet")
        // …and within one project it still supersedes.
        let again = Decisions.mergeDecisions(existing: merged,
                                             extracted: [ExtractedDecision(topic: "brand", statement: "violet v2", source: nil)],
                                             now: 3, scope: "codepet")
        XCTAssertEqual(again.count, 2)
        XCTAssertEqual(again.first { $0.scope == "codepet" }?.statement, "violet v2")
    }

    func testAStoredDecisionWithoutScopeDecodesAndReencodesUnchanged() async throws {
        let json = #"{"topic":"brand","statement":"quiet paper","updatedAt":1}"#
        let entry = try JSONDecoder().decode(DecisionEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.scope)
        let back = String(data: try JSONEncoder().encode(entry), encoding: .utf8) ?? ""
        XCTAssertFalse(back.contains("scope"), "nil is omitted — no write changes old documents")
    }

    func testNormalizeKeepsScope() async {
        XCTAssertEqual(Decisions.normalizeDecisions([d("brand", "codepet")]).first?.scope, "codepet")
    }
}
