import XCTest
@testable import codepet

final class VirtualCompanyRunStateTests: XCTestCase {

    private func routing(_ decision: String, agents: [String] = ["product", "finance"]) -> VCRouting {
        let meta = agents.map { VCAgentMeta(agentId: $0, departmentKey: $0 == "finance" ? "fin" : $0) }
        let json: [String: Any] = [
            "decision": decision, "agents": agents, "real_question": "Do you have PMF?",
            "request_type": "DECISION",
            "agent_meta": meta.map { ["agent_id": $0.agentId, "department_key": $0.departmentKey as Any] }
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(VCRouting.self, from: data)
    }

    private func position(_ stance: String = "proceed", blocker: String? = nil) -> VCPosition {
        VCPosition(stance: stance, position: "p", reasoning: "r", evidenceNeeded: [],
                   risksIOwn: [], confidence: 4, costToMyDept: "c", hardBlocker: blocker)
    }

    private func brief() -> VCBrief {
        VCBrief(recommendation: "Price it now.", confidence: 4, confidenceReason: "clear",
                theRealDisagreement: "product vs finance", tradeoffFounderMustOwn: "speed vs certainty",
                killCriteria: ["zero of 30 pay"], nextAction: VCNextAction(action: "send link", owner: "Founder"),
                whatWeDontKnow: "ad ARPU", unresolved: false)
    }

    func testMultiAgentRoutingHandsOffToTheRoom() {
        var state = VirtualCompanyRunState()
        state.apply(.runStarted(runId: "r1"))
        XCTAssertFalse(state.handsOffToRoom)
        state.apply(.routing(routing("multi_agent")))
        XCTAssertTrue(state.handsOffToRoom)
        XCTAssertFalse(state.isEscapeHatch)
        XCTAssertEqual(state.phase, .routing)
    }

    func testSingleAgentRoutingIsAnEscapeHatchAndNeverHandsOff() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("single_agent", agents: ["product"])))
        XCTAssertFalse(state.handsOffToRoom)
        XCTAssertTrue(state.isEscapeHatch)
    }

    func testNeedsClarificationIsAlsoAnEscapeHatch() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("needs_clarification", agents: [])))
        XCTAssertTrue(state.isEscapeHatch)
        XCTAssertFalse(state.handsOffToRoom)
    }

    func testAllAgentsStartWorkingBeforeAnyPositionArrives() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
        XCTAssertEqual(state.agentStatuses.count, 2)
        XCTAssertTrue(state.agentStatuses.allSatisfy { $0.status == .working })
        XCTAssertEqual(state.phase, .working)
    }

    func testPositionFlipsOnlyThatAgentToDone() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
        state.apply(.agentPosition(VCAgentMeta(agentId: "finance", departmentKey: "fin"),
                                   position(blocker: "no seats first")))

        let byAgent = Dictionary(uniqueKeysWithValues: state.agentStatuses.map { ($0.meta.agentId, $0.status) })
        XCTAssertEqual(byAgent["finance"], .done)
        XCTAssertEqual(byAgent["product"], .working)
        XCTAssertEqual(state.positions["finance"]?.hardBlocker, "no seats first")
    }

    func testAgentErrorFailsOneColumnAndLeavesTheRunAlive() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentError(VCAgentMeta(agentId: "product", departmentKey: "product"), "529 upstream"))

        XCTAssertEqual(state.agentStatuses.first?.status, .failed)
        XCTAssertEqual(state.agentErrors["product"], "529 upstream")
        XCTAssertNotEqual(state.phase, .failed, "one agent failing is not the run failing")
    }

    func testConflictsAndRoundsAccumulateInArrivalOrder() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.conflicts([VCConflict(a: "product", b: "finance", kind: "BLOCKER", reason: "blocked")]))
        state.apply(.negotiationRound(VCNegotiationRound(round: 1, turns: [])))
        state.apply(.negotiationRound(VCNegotiationRound(round: 2, turns: [])))
        XCTAssertEqual(state.conflicts.count, 1)
        XCTAssertEqual(state.negotiationRounds.map(\.round), [1, 2])
        XCTAssertEqual(state.phase, .negotiating)
    }

    func testBriefThenDoneFinishesTheRun() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.brief(brief()))
        XCTAssertEqual(state.phase, .briefing)
        state.apply(.telemetry(try! JSONDecoder().decode(
            VCTelemetry.self,
            from: #"{"tokens_per_agent":{},"cost_estimate_usd":0.21,"stopped_reason":null}"#
                .data(using: .utf8)!)))
        state.apply(.done(runId: "r1", unresolved: false, skipped: nil))
        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.telemetry?.costEstimateUsd, 0.21)
        XCTAssertNotNil(state.brief)
    }

    func testRunStoppedKeepsTheReasonVerbatim() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.runStopped(runId: "r1", reason: "Hết ngân sách cho lượt này."))
        state.apply(.done(runId: "r1", unresolved: true, skipped: nil))
        XCTAssertEqual(state.stoppedReason, "Hết ngân sách cho lượt này.")
        XCTAssertEqual(state.phase, .finished, "run_stopped is still followed by done")
    }

    func testTerminalErrorMarksTheRunFailed() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.error("upstream_failure", "credit balance too low"))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.terminalError, "upstream_failure")
    }

    func testDevilsAdvocateIsKeptButNeverGivenADepartment() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        let verdict = VCVerdict(planIsSound: false, loadBearingAssumption: "a", howItCouldBeFalse: "b",
                                cheapestTest: "c", failurePostMortem: "d", whoIsNotInTheRoom: "e",
                                objections: ["one"])
        state.apply(.devilsAdvocate(VCAgentMeta(agentId: "devils_advocate", departmentKey: nil), verdict))
        XCTAssertEqual(state.verdict?.objections, ["one"])
        XCTAssertNil(state.agentStatuses.first { $0.meta.agentId == "devils_advocate" }?.meta.departmentKey)
    }

    func testRepeatedAgentStartDoesNotDuplicateTheAgent() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        XCTAssertEqual(state.agents.count, 1)
        XCTAssertEqual(state.agentStatuses.count, 1)
    }

    func testEventsForAnAgentThatNeverStartedStillRegisterItExactlyOnce() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentPosition(VCAgentMeta(agentId: "finance", departmentKey: "fin"), position()))
        state.apply(.agentError(VCAgentMeta(agentId: "finance", departmentKey: "fin"), "529 upstream"))
        XCTAssertEqual(state.agents.count, 1)
        XCTAssertNotNil(state.positions["finance"])
        XCTAssertEqual(state.agentStatuses.first?.status, .failed)
    }

    // MARK: - A finished run has no working agents

    /// A budget-stopped run: the un-answered department must not spin forever. The
    /// status derived from "no position and no error" is only honest while the run is
    /// still going.
    func testAnAgentThatNeverAnsweredIsNotWorkingOnceTheRunFinished() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
        state.apply(.agentPosition(VCAgentMeta(agentId: "product", departmentKey: "product"), position()))
        XCTAssertEqual(state.agentStatuses.first { $0.meta.agentId == "finance" }?.status, .working)

        state.apply(.runStopped(runId: "r1", reason: "Budget ceiling reached."))
        state.apply(.done(runId: "r1", unresolved: true, skipped: nil))
        XCTAssertEqual(state.agentStatuses.first { $0.meta.agentId == "product" }?.status, .done)
        XCTAssertEqual(state.agentStatuses.first { $0.meta.agentId == "finance" }?.status, .failed,
                       "a department that never answered a finished run has stalled, not working")
    }

    /// The seal (`terminalError` + `.failed`) renders a red card. Columns must not keep
    /// spinning underneath it.
    func testAFailedRunLeavesNoAgentWorking() {
        var state = VirtualCompanyRunState()
        state.apply(.routing(routing("multi_agent")))
        state.apply(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
        state.apply(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
        state.terminalError = "stream_lost"
        state.phase = .failed
        XCTAssertTrue(state.agentStatuses.allSatisfy { $0.status != .working })
    }

    // MARK: - Lockability

    func testABriefWithARunIdAndARecommendationIsLockable() {
        var state = VirtualCompanyRunState()
        state.apply(.runStarted(runId: "r1"))
        state.apply(.routing(routing("multi_agent")))
        XCTAssertFalse(state.canLockIn, "no brief yet")
        state.apply(.brief(brief()))
        XCTAssertTrue(state.canLockIn)
    }

    func testABlankRecommendationIsNotLockable() {
        var state = VirtualCompanyRunState()
        state.apply(.runStarted(runId: "r1"))
        state.apply(.routing(routing("multi_agent")))
        state.apply(.brief(VCBrief(recommendation: "   ", confidence: 3, confidenceReason: "c",
                                   theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                                   killCriteria: [], nextAction: VCNextAction(action: "a", owner: "Founder"),
                                   whatWeDontKnow: "u", unresolved: true)))
        XCTAssertFalse(state.canLockIn, "the button would record a decision that says nothing")
    }
}
