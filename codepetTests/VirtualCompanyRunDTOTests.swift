import XCTest
@testable import codepet

final class VirtualCompanyRunDTOTests: XCTestCase {

    private func frame(_ event: String, _ data: String) -> SSEFrame {
        SSEFrame(event: event, data: data)
    }

    func testRequestEncodesSnakeCase() throws {
        let req = VirtualCompanyRequest(
            request: "Nên tăng giá hay ship team feature?",
            language: "vi",
            founder: VCFounder(profile: "Solo technical founder.",
                               stage: "Pre-revenue, 30 beta users.",
                               constraints: ["Không thuê người quý này."]),
            stressTest: false)
        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["language"] as? String, "vi")
        XCTAssertEqual(json["stress_test"] as? Bool, false)
        let founder = try XCTUnwrap(json["founder"] as? [String: Any])
        XCTAssertEqual(founder["constraints"] as? [String], ["Không thuê người quý này."])
    }

    func testDecodesRoutingWithAgentMeta() throws {
        let data = """
        {"decision":"multi_agent","agents":["product","finance"],\
        "real_question":"Do you have PMF?","request_type":"DECISION",\
        "reason_per_agent":{"product":"owns sequencing"},"excluded":{"legal":"not relevant"},\
        "missing_info":["runway"],\
        "agent_meta":[{"agent_id":"product","department_key":"product"},\
        {"agent_id":"finance","department_key":"fin"}]}
        """
        let event = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame("routing", data)))
        guard case let .routing(routing) = event else { return XCTFail("expected .routing") }
        XCTAssertEqual(routing.decision, "multi_agent")
        XCTAssertEqual(routing.realQuestion, "Do you have PMF?")
        XCTAssertEqual(routing.agentMeta.map(\.departmentKey), ["product", "fin"])
        XCTAssertEqual(routing.missingInfo, ["runway"])
    }

    func testDecodesPositionWithHardBlocker() throws {
        let data = """
        {"agent_id":"finance","department_key":"fin","position":{"stance":"proceed_with_conditions",\
        "position":"Price first.","reasoning":"No paid signal.","evidence_needed":["conversion"],\
        "risks_i_own":["runway ends dry"],"confidence":4,"cost_to_my_dept":"Forgoes seat ACV.",\
        "hard_blocker":"Do not build seats first."}}
        """
        let event = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame("agent_position", data)))
        guard case let .agentPosition(meta, position) = event else { return XCTFail("expected .agentPosition") }
        XCTAssertEqual(meta.agentId, "finance")
        XCTAssertEqual(position.confidence, 4)
        XCTAssertEqual(position.hardBlocker, "Do not build seats first.")
        XCTAssertEqual(position.risksIOwn, ["runway ends dry"])
    }

    func testDecodesPositionWithNullHardBlocker() throws {
        let data = """
        {"agent_id":"product","department_key":"product","position":{"stance":"proceed",\
        "position":"Ship it.","reasoning":"Cheap.","evidence_needed":[],"risks_i_own":[],\
        "confidence":3,"cost_to_my_dept":"A week.","hard_blocker":null}}
        """
        let event = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame("agent_position", data)))
        guard case let .agentPosition(_, position) = event else { return XCTFail("expected .agentPosition") }
        XCTAssertNil(position.hardBlocker)
    }

    func testDecodesBriefWithNextAction() throws {
        let data = """
        {"recommendation":"Price it now.","confidence":4,"confidence_reason":"Cost asymmetry is clear.",\
        "the_real_disagreement":"Product wanted evidence, finance wanted runway.",\
        "tradeoff_founder_must_own":"Speed of evidence versus quality of evidence.",\
        "kill_criteria":["Zero of 30 pay in 14 days"],\
        "next_action":{"action":"Send a payment link today","owner":"Founder"},\
        "what_we_dont_know":"Ad ARPU at this scale.","unresolved":false}
        """
        let event = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame("brief", data)))
        guard case let .brief(brief) = event else { return XCTFail("expected .brief") }
        XCTAssertEqual(brief.nextAction.owner, "Founder")
        XCTAssertEqual(brief.killCriteria.count, 1)
        XCTAssertFalse(brief.unresolved)
    }

    func testDecodesConflictsAndDone() throws {
        let conflicts = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame(
            "conflicts",
            #"{"conflicts":[{"a":"product","b":"finance","kind":"BLOCKER","reason":"finance blocked"}]}"#)))
        guard case let .conflicts(list) = conflicts else { return XCTFail("expected .conflicts") }
        XCTAssertEqual(list.first?.kind, "BLOCKER")

        let done = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame(
            "done", #"{"run_id":"run_1","unresolved":false,"skipped":"single_agent"}"#)))
        guard case let .done(runId, unresolved, skipped) = done else { return XCTFail("expected .done") }
        XCTAssertEqual(runId, "run_1")
        XCTAssertFalse(unresolved)
        XCTAssertEqual(skipped, "single_agent")
    }

    func testDecodesDoneWithNullSkipped() throws {
        let done = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame(
            "done", #"{"run_id":"run_1","unresolved":true,"skipped":null}"#)))
        guard case let .done(_, unresolved, skipped) = done else { return XCTFail("expected .done") }
        XCTAssertTrue(unresolved)
        XCTAssertNil(skipped)
    }

    func testDecodesTerminalErrorAndRunStopped() throws {
        let err = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame(
            "error", #"{"error":"upstream_failure","detail":"credit balance too low"}"#)))
        guard case let .error(code, detail) = err else { return XCTFail("expected .error") }
        XCTAssertEqual(code, "upstream_failure")
        XCTAssertEqual(detail, "credit balance too low")

        let stopped = try XCTUnwrap(VirtualCompanyEvent.from(frame: frame(
            "run_stopped", #"{"run_id":"run_1","reason":"Hết ngân sách cho lượt này."}"#)))
        guard case let .runStopped(_, reason) = stopped else { return XCTFail("expected .runStopped") }
        XCTAssertEqual(reason, "Hết ngân sách cho lượt này.")
    }

    func testUnknownEventDecodesToNilRatherThanThrowing() {
        // Forward compatibility: the backend may add frames. An unknown one must
        // be skipped, never crash a live run.
        XCTAssertNil(VirtualCompanyEvent.from(frame: frame("some_future_event", "{}")))
        XCTAssertNil(VirtualCompanyEvent.from(frame: frame("brief", "not json")))
    }
}
