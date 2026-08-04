import XCTest
@testable import codepet

final class VirtualCompanyDecisionTests: XCTestCase {

    private func state(recommendation: String = "Price it now.",
                       realQuestion: String = "Do you have PMF?") -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        let json: [String: Any] = ["decision": "multi_agent", "agents": ["product", "finance"],
                                   "real_question": realQuestion, "request_type": "DECISION"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        s.apply(.routing(try! JSONDecoder().decode(VCRouting.self, from: data)))
        s.apply(.brief(VCBrief(recommendation: recommendation, confidence: 4, confidenceReason: "c",
                               theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                               killCriteria: ["k"], nextAction: VCNextAction(action: "a", owner: "Founder"),
                               whatWeDontKnow: "u", unresolved: false)))
        s.runId = "run_42"
        return s
    }

    func testDecisionTopicIsTheRealQuestionAndStatementIsTheRecommendation() {
        let decision = VirtualCompanyDecision.extracted(from: state(), runId: "run_42")
        XCTAssertEqual(decision?.topic, "Do you have PMF?")
        XCTAssertEqual(decision?.statement, "Price it now.")
        XCTAssertEqual(decision?.source, "virtual-company/run_42")
    }

    func testNoDecisionWithoutABrief() {
        var s = VirtualCompanyRunState()
        s.runId = "run_42"
        XCTAssertNil(VirtualCompanyDecision.extracted(from: s, runId: "run_42"))
    }

    func testMergingKeepsExistingDecisionsAndAddsThisOne() {
        let existing = [DecisionEntry(topic: "Pricing tier", statement: "One tier only",
                                     source: "library/x", updatedAt: 1)]
        let extracted = VirtualCompanyDecision.extracted(from: state(), runId: "run_42")!
        let merged = Decisions.mergeDecisions(existing: existing, extracted: [extracted], now: 2)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.last?.source, "virtual-company/run_42")
    }
}

/// The routing panel's refusals. Sorting is the substance here, not style: with
/// nine departments the router writes several refusals per run, and `excluded` is
/// a dictionary — unsorted iteration reshuffles a live card on every redraw.
final class VirtualCompanyRoutingExclusionTests: XCTestCase {

    private func routing(excluded: [String: String]) -> VCRouting {
        let json: [String: Any] = [
            "decision": "multi_agent", "agents": ["product", "legal"],
            "real_question": "q", "request_type": "DECISION",
            "reason_per_agent": ["product": "owns retention policy"],
            "excluded": excluded
        ]
        return try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    func testExclusionsDecodeAndSurviveAsAWholeSet() {
        // Seven refusals is the normal shape now, not an edge case.
        let seven = ["engineering": "follows the policy decision",
                     "design": "not a design question",
                     "marketing": "messaging follows the choice",
                     "sales": "downstream of the choice",
                     "support": "not a stakeholder in direction",
                     "operations": "not operationally material",
                     "finance": "cost is an input, not the decision"]
        let r = routing(excluded: seven)
        XCTAssertEqual(r.excluded.count, 7)
        XCTAssertEqual(r.excluded["engineering"], "follows the policy decision")
    }

    func testTheRenderedOrderIsStableAcrossRedraws() {
        let r = routing(excluded: ["support": "b", "engineering": "a", "marketing": "c"])
        let first = r.excluded.sorted(by: { $0.key < $1.key }).map(\.key)
        let again = r.excluded.sorted(by: { $0.key < $1.key }).map(\.key)
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, ["engineering", "marketing", "support"])
    }

    func testAMissingExcludedMapIsNotAnError() {
        // The backend omits it on some decisions; a routing frame must still render.
        let json: [String: Any] = ["decision": "multi_agent", "agents": ["product", "legal"],
                                   "real_question": "q", "request_type": "DECISION"]
        let r = try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(r.excluded.isEmpty)
    }
}
