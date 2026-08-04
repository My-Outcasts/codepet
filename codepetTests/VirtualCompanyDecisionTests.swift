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
