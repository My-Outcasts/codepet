// codepetTests/WorkPlanValidationTests.swift
import XCTest
@testable import codepet

/// The client does not trust the op's plan: the same rules `coerceWorkPlan` applies, re-applied
/// here, so a stale sidecar or a hand-edited Firestore doc cannot schedule a cycle or 20 steps.
final class WorkPlanValidationTests: XCTestCase {
    private let roster: Set<String> = ["eng", "design", "mkt", "sales"]
    private func s(_ id: String, _ dept: String, _ deps: [String] = []) -> WorkStep {
        WorkStep(id: id, dept: dept, title: id, instruction: "", kind: "doc", dependsOn: deps)
    }
    private func plan(_ steps: [WorkStep]) -> WorkPlan {
        WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: steps)
    }

    func testDropsOffRosterAndNonRoutableSteps() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt"), s("s2", "legal"), s("s3", "chief_of_staff")]), roster: roster)!
        XCTAssertEqual(p.steps.map(\.id), ["s1", "build"])
    }
    func testKeepsOnlyEdgesToEarlierSteps() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt", ["s2"]), s("s2", "design", ["s1", "ghost"])]), roster: roster)!
        XCTAssertEqual(p.steps[0].dependsOn, [])
        XCTAssertEqual(p.steps[1].dependsOn, ["s1"])
    }
    func testCapsStepsAndDeps() {
        var many = (1...9).map { s("s\($0)", "mkt") }
        many[6] = s("s7", "design", ["s1", "s2", "s3", "s4"])
        let p = WorkPlanValidation.validate(plan(many), roster: roster)!
        XCTAssertEqual(p.departmentSteps.count, 6)
        XCTAssertTrue(p.departmentSteps.allSatisfy { $0.dependsOn.count <= 3 })
    }
    func testExactlyOneFinalBuildStepDependingOnAll() {
        let p = WorkPlanValidation.validate(plan([s("s1", "mkt"), s("build", "eng", ["s1"]), s("s2", "sales")]), roster: roster)!
        XCTAssertEqual(p.steps.filter { $0.id == "build" }.count, 1)
        XCTAssertEqual(p.steps.last?.id, "build")
        XCTAssertEqual(p.steps.last?.dependsOn, ["s1", "s2"])
    }
    func testRoomOutcomeMapping() {
        let brief = VCBrief(recommendation: "r", confidence: 3, confidenceReason: "", theRealDisagreement: "",
                            tradeoffFounderMustOwn: "", killCriteria: [], nextAction: VCNextAction(action: "", owner: ""),
                            whatWeDontKnow: "", unresolved: false)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .finished, routingDecision: "multi_agent", brief: brief), .brief(brief))
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .routing, routingDecision: "single_agent", brief: nil), .requestOnly)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .routing, routingDecision: "needs_clarification", brief: nil), .clarify)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .failed, routingDecision: "multi_agent", brief: nil), .failed)
        XCTAssertEqual(TeamBuildRoomOutcome.from(phase: .idle, routingDecision: nil, brief: nil), .failed)
    }
}
