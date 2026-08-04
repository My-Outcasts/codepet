# Virtual Company in the Copilot Chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the founder types a decision into the copilot chat, the Virtual Company convenes on its own — routing, two departments answering independently, their conflict, and a brief — all inside the conversation they were already having.

**Architecture:** `CompanyStore.sendMessage` fans out to `companyChat` and `virtualCompanyRun` in parallel. The router's escape hatch decides: `single_agent`/`needs_clarification` discards the run and chat proceeds untouched; `multi_agent` replaces byte's in-flight message with a one-line handoff and renders the room. Every piece of logic lives in a plain value type — a `Codable` DTO layer, a pure `VirtualCompanyRunState.apply(event:)` reducer, a plain-enum streaming client — so it is unit-testable without instantiating `CompanyStore` (see Global Constraints).

**Tech Stack:** Swift 5 / SwiftUI, macOS 26.2 deployment, XCTest, Firebase Auth for the ID token, existing `SSEParser`.

**Spec:** `docs/superpowers/specs/2026-08-03-virtual-company-in-chat-design.md`
**Wire contract:** `docs/superpowers/specs/virtual-company-sse-contract.md` — build against this, never against `functions/src/company/`.

## Global Constraints

- **New `.swift` files need no project-file edit.** `CodePet.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77): target membership follows the folder on disk. Dropping a file into `codepet/` or `codepetTests/` is enough.
- **Never unit-test through `CompanyStore`.** The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every unmarked `ObservableObject` gets an isolated deinit, and Xcode 26.2's runtime double-frees on teardown inside the XCTest host — the host crashes and the test fails in 0.000s. This is a documented toolchain bug, not a code defect. Consequence for this plan: tasks 1–5 and 7's mapping helper are unit-tested; tasks 6, 8 and the views are verified by a green build plus a real run.
- **Client type prefix is `VC`** (`VCPosition`, `VCBrief`, …) to avoid colliding with the existing `CompanyBrief`, `Deliverable`, and `AgentRun` types on `main`.
- **All wire keys are snake_case**; every DTO declares explicit `CodingKeys`. The backend never sends camelCase.
- **A failed run must never damage the chat.** Any error path discards the run and leaves `chatMessages` exactly as a no-feature run would.
- **Endpoint:** `https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun`
- **Build:** `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- **Run one test suite:** `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/<SuiteName> CODE_SIGNING_ALLOWED=NO`

## File Structure

| File | Responsibility |
|---|---|
| `codepet/Models/VirtualCompanyRun.swift` (create) | Request + response DTOs mirroring the contract, the `VirtualCompanyEvent` enum, and `VirtualCompanyEvent.from(frame:)` decoding. No networking, no state. |
| `codepet/Models/VirtualCompanyRunState.swift` (create) | Pure reducer: `apply(_:)` folds events into renderable state; `handsOffToRoom` answers the one question `CompanyStore` needs. |
| `codepet/Models/FounderContextMapper.swift` (create) | `CompanyBrief` + constraints → `VCFounder`. Pure. |
| `codepet/Services/VirtualCompanyClient.swift` (create) | The only thing that talks to `virtualCompanyRun`. Plain enum, static funcs, injectable session + token provider. |
| `codepet/Views/Copilot/VirtualCompanyCards.swift` (create) | `VCRoutingCard`, `VCPositionCard`, `VCConflictCard`, `VCBriefCard` on the existing `MessageCard` chrome. |
| `codepet/Models/Department.swift` (modify) | Add the `product` entry the contract asks for. |
| `codepet/Models/CompanyBrief.swift` (modify) | Two new optional fields, `runway` and `constraints`. |
| `codepet/Models/EnrichInterview.swift` (modify) | Two new `InterviewGap` cases plus their question copy, kept out of `gapOrder` so onboarding is untouched. |
| `codepet/Models/VirtualCompanyInterview.swift` (create) | The gate deciding when to ask for runway and constraints. |
| `codepet/Models/CopilotMessage.swift` (modify) | One optional run payload field. |
| `codepet/Managers/CompanyStore.swift` (modify) | Fan-out, handoff, the constraints interview, and the Decisions action. |
| `codepet/Views/Copilot/CopilotChatView.swift` (modify) | Render the cards when a message carries a run. |

---

### Task 1: Wire DTOs and event decoding

**Files:**
- Create: `codepet/Models/VirtualCompanyRun.swift`
- Test: `codepetTests/VirtualCompanyRunDTOTests.swift`

**Interfaces:**
- Consumes: `SSEFrame` (from `codepet/Services/SSEParser.swift`)
- Produces: `VirtualCompanyRequest`, `VCFounder`, `VCAgentMeta`, `VCRouting`, `VCPosition`, `VCConflict`, `VCNegotiationRound`, `VCNegotiationTurn`, `VCVerdict`, `VCNextAction`, `VCBrief`, `VCTelemetry`, `enum VirtualCompanyEvent`, `static VirtualCompanyEvent.from(frame: SSEFrame) -> VirtualCompanyEvent?`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VirtualCompanyRunDTOTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyRunDTOTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'VirtualCompanyRequest' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/VirtualCompanyRun.swift`:

```swift
// codepet/Models/VirtualCompanyRun.swift
import Foundation

/// Wire types for the `virtualCompanyRun` SSE endpoint. Field-for-field mirrors of
/// docs/superpowers/specs/virtual-company-sse-contract.md — that document is the
/// boundary, not the backend source. Prefixed VC to avoid colliding with the
/// existing CompanyBrief / AgentRun / Deliverable types.

struct VCFounder: Codable, Equatable {
    let profile: String
    let stage: String
    let constraints: [String]
}

struct VirtualCompanyRequest: Codable, Equatable {
    let request: String
    let language: String
    let founder: VCFounder
    let stressTest: Bool

    enum CodingKeys: String, CodingKey {
        case request, language, founder
        case stressTest = "stress_test"
    }
}

struct VCAgentMeta: Codable, Equatable {
    let agentId: String
    /// null for chief_of_staff and devils_advocate — neither is a department.
    let departmentKey: String?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case departmentKey = "department_key"
    }
}

struct VCRouting: Codable, Equatable {
    let decision: String            // single_agent | multi_agent | needs_clarification
    let agents: [String]
    let realQuestion: String
    let requestType: String
    let reasonPerAgent: [String: String]
    let excluded: [String: String]
    let missingInfo: [String]
    let agentMeta: [VCAgentMeta]

    enum CodingKeys: String, CodingKey {
        case decision, agents, excluded
        case realQuestion = "real_question"
        case requestType = "request_type"
        case reasonPerAgent = "reason_per_agent"
        case missingInfo = "missing_info"
        case agentMeta = "agent_meta"
    }

    // Soft-optional maps and lists: the backend omits them on some decisions, and
    // a missing reason must not fail the whole frame. Mirrors the robust-decode
    // approach already used for library payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decision = try c.decode(String.self, forKey: .decision)
        agents = try c.decodeIfPresent([String].self, forKey: .agents) ?? []
        realQuestion = try c.decodeIfPresent(String.self, forKey: .realQuestion) ?? ""
        requestType = try c.decodeIfPresent(String.self, forKey: .requestType) ?? ""
        reasonPerAgent = try c.decodeIfPresent([String: String].self, forKey: .reasonPerAgent) ?? [:]
        excluded = try c.decodeIfPresent([String: String].self, forKey: .excluded) ?? [:]
        missingInfo = try c.decodeIfPresent([String].self, forKey: .missingInfo) ?? []
        agentMeta = try c.decodeIfPresent([VCAgentMeta].self, forKey: .agentMeta) ?? []
    }
}

struct VCPosition: Codable, Equatable {
    let stance: String              // proceed | proceed_with_conditions | do_not_proceed
    let position: String
    let reasoning: String
    let evidenceNeeded: [String]
    let risksIOwn: [String]
    let confidence: Int
    let costToMyDept: String
    let hardBlocker: String?

    enum CodingKeys: String, CodingKey {
        case stance, position, reasoning, confidence
        case evidenceNeeded = "evidence_needed"
        case risksIOwn = "risks_i_own"
        case costToMyDept = "cost_to_my_dept"
        case hardBlocker = "hard_blocker"
    }
}

struct VCConflict: Codable, Equatable {
    let a: String
    let b: String
    let kind: String                // CONFLICT | BLOCKER | TENSION | ALIGNED
    let reason: String
}

struct VCNegotiationTurn: Codable, Equatable {
    let agent: String
    let preciseDisagreement: String
    let whatWouldChangeMyMind: String
    let proposal: String
    let resolved: Bool

    enum CodingKeys: String, CodingKey {
        case agent, proposal, resolved
        case preciseDisagreement = "precise_disagreement"
        case whatWouldChangeMyMind = "what_would_change_my_mind"
    }
}

struct VCNegotiationRound: Codable, Equatable {
    let round: Int
    let turns: [VCNegotiationTurn]
}

struct VCVerdict: Codable, Equatable {
    let planIsSound: Bool
    let loadBearingAssumption: String
    let howItCouldBeFalse: String
    let cheapestTest: String
    let failurePostMortem: String
    let whoIsNotInTheRoom: String
    let objections: [String]

    enum CodingKeys: String, CodingKey {
        case objections
        case planIsSound = "plan_is_sound"
        case loadBearingAssumption = "load_bearing_assumption"
        case howItCouldBeFalse = "how_it_could_be_false"
        case cheapestTest = "cheapest_test"
        case failurePostMortem = "failure_post_mortem"
        case whoIsNotInTheRoom = "who_is_not_in_the_room"
    }
}

struct VCNextAction: Codable, Equatable {
    let action: String
    let owner: String
}

struct VCBrief: Codable, Equatable {
    let recommendation: String
    let confidence: Int
    let confidenceReason: String
    let theRealDisagreement: String
    let tradeoffFounderMustOwn: String
    let killCriteria: [String]
    let nextAction: VCNextAction
    let whatWeDontKnow: String
    let unresolved: Bool

    enum CodingKeys: String, CodingKey {
        case recommendation, confidence, unresolved
        case confidenceReason = "confidence_reason"
        case theRealDisagreement = "the_real_disagreement"
        case tradeoffFounderMustOwn = "tradeoff_founder_must_own"
        case killCriteria = "kill_criteria"
        case nextAction = "next_action"
        case whatWeDontKnow = "what_we_dont_know"
    }
}

struct VCTelemetry: Codable, Equatable {
    let costEstimateUsd: Double?
    let stoppedReason: String?

    enum CodingKeys: String, CodingKey {
        case costEstimateUsd = "cost_estimate_usd"
        case stoppedReason = "stopped_reason"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        costEstimateUsd = try c.decodeIfPresent(Double.self, forKey: .costEstimateUsd)
        stoppedReason = try c.decodeIfPresent(String.self, forKey: .stoppedReason)
    }
}

/// One decoded SSE frame. Emission order and the two short-circuit flows are
/// documented in the contract; the reducer in VirtualCompanyRunState enforces
/// nothing about order, it only folds what arrives.
enum VirtualCompanyEvent: Equatable {
    case runStarted(runId: String)
    case routing(VCRouting)
    case agentStart(VCAgentMeta)
    case agentPosition(VCAgentMeta, VCPosition)
    case agentError(VCAgentMeta, String)
    case conflicts([VCConflict])
    case negotiationRound(VCNegotiationRound)
    case devilsAdvocate(VCAgentMeta, VCVerdict)
    case brief(VCBrief)
    case runStopped(runId: String, reason: String)
    case telemetry(VCTelemetry)
    case done(runId: String, unresolved: Bool, skipped: String?)
    case error(String, String?)

    /// Decodes a frame, or returns nil when the event name is unknown or the
    /// payload will not parse. Nil rather than throw on purpose: the backend may
    /// add frames later, and one unrecognised frame must not kill a live run.
    static func from(frame: SSEFrame) -> VirtualCompanyEvent? {
        guard let data = frame.data.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        switch frame.event {
        case "run_started":
            struct P: Codable { let run_id: String }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .runStarted(runId: p.run_id)

        case "routing":
            guard let p = try? decoder.decode(VCRouting.self, from: data) else { return nil }
            return .routing(p)

        case "agent_start":
            guard let p = try? decoder.decode(VCAgentMeta.self, from: data) else { return nil }
            return .agentStart(p)

        case "agent_position":
            struct P: Codable { let agent_id: String; let department_key: String?; let position: VCPosition }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .agentPosition(VCAgentMeta(agentId: p.agent_id, departmentKey: p.department_key), p.position)

        case "agent_error":
            struct P: Codable { let agent_id: String; let department_key: String?; let error: String }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .agentError(VCAgentMeta(agentId: p.agent_id, departmentKey: p.department_key), p.error)

        case "conflicts":
            struct P: Codable { let conflicts: [VCConflict] }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .conflicts(p.conflicts)

        case "negotiation_round":
            guard let p = try? decoder.decode(VCNegotiationRound.self, from: data) else { return nil }
            return .negotiationRound(p)

        case "devils_advocate":
            struct P: Codable { let agent_id: String; let department_key: String?; let verdict: VCVerdict }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .devilsAdvocate(VCAgentMeta(agentId: p.agent_id, departmentKey: p.department_key), p.verdict)

        case "brief":
            guard let p = try? decoder.decode(VCBrief.self, from: data) else { return nil }
            return .brief(p)

        case "run_stopped":
            struct P: Codable { let run_id: String; let reason: String }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .runStopped(runId: p.run_id, reason: p.reason)

        case "telemetry":
            guard let p = try? decoder.decode(VCTelemetry.self, from: data) else { return nil }
            return .telemetry(p)

        case "done":
            struct P: Codable { let run_id: String; let unresolved: Bool; let skipped: String? }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .done(runId: p.run_id, unresolved: p.unresolved, skipped: p.skipped)

        case "error":
            struct P: Codable { let error: String; let detail: String? }
            guard let p = try? decoder.decode(P.self, from: data) else { return nil }
            return .error(p.error, p.detail)

        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyRunDTOTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 9 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/VirtualCompanyRun.swift codepetTests/VirtualCompanyRunDTOTests.swift
git commit -m "feat(vc): wire DTOs and SSE event decoding for virtualCompanyRun"
```

---

### Task 2: Founder context from the brief

**Files:**
- Create: `codepet/Models/FounderContextMapper.swift`
- Test: `codepetTests/FounderContextMapperTests.swift`

**Interfaces:**
- Consumes: `VCFounder` (Task 1), `CompanyBrief` (existing, `codepet/Models/CompanyBrief.swift`)
- Produces: `enum FounderContextMapper { static func founder(from brief: CompanyBrief) -> VCFounder }`

**Also modifies:** `codepet/Models/CompanyBrief.swift` — two new optional fields, `runway: String?` and `constraints: String?`, filled by the interview in Task 8. They live on the brief rather than on `CompanyStore` because the brief is already the founder-context store and already persists and syncs. Raw founder text, not distilled — the same choice `EnrichInterview` documents for the fields it fills.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/FounderContextMapperTests.swift`:

```swift
import XCTest
@testable import codepet

final class FounderContextMapperTests: XCTestCase {

    func testBuildsProfileFromRoleAndTech() {
        let brief = CompanyBrief(founderName: "Giang", role: "Solo founder, technical",
                                 tech: "Swift, Firebase")
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertTrue(founder.profile.contains("Solo founder, technical"))
        XCTAssertTrue(founder.profile.contains("Swift, Firebase"))
    }

    func testStageCarriesTractionGoalAndRunway() {
        var brief = CompanyBrief(stage: "Building", oneLiner: "An AI coding companion",
                                 goal: "Ship to the App Store this month",
                                 traction: "30 beta users, no revenue")
        brief.runway = "About 4 months of money left"
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertTrue(founder.stage.contains("Building"))
        XCTAssertTrue(founder.stage.contains("30 beta users"))
        XCTAssertTrue(founder.stage.contains("Ship to the App Store this month"))
        XCTAssertTrue(founder.stage.contains("4 months"), "runway belongs in stage")
    }

    func testConstraintsSplitOnNewlines() {
        var brief = CompanyBrief()
        brief.constraints = "Không thuê người quý này.\nPhải ship trong tháng này."
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertEqual(founder.constraints,
                       ["Không thuê người quý này.", "Phải ship trong tháng này."])
    }

    func testSingleLineConstraintBecomesOneEntry() {
        var brief = CompanyBrief()
        brief.constraints = "Không nhận đầu tư ở giai đoạn này."
        XCTAssertEqual(FounderContextMapper.founder(from: brief).constraints,
                       ["Không nhận đầu tư ở giai đoạn này."])
    }

    func testEmptyBriefStillProducesAValidPayload() {
        // The endpoint rejects a missing profile or stage with HTTP 400, so both
        // must be strings even when the founder has told us nothing.
        let founder = FounderContextMapper.founder(from: CompanyBrief())
        XCTAssertFalse(founder.profile.isEmpty)
        XCTAssertFalse(founder.stage.isEmpty)
        XCTAssertTrue(founder.constraints.isEmpty)
    }

    func testBlankFieldsAreDroppedNotJoinedAsEmptySegments() {
        let brief = CompanyBrief(role: "   ", tech: "Swift")
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertFalse(founder.profile.contains("·  ·"))
        XCTAssertTrue(founder.profile.contains("Swift"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/FounderContextMapperTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'FounderContextMapper' in scope`

- [ ] **Step 3: Add the two brief fields**

In `codepet/Models/CompanyBrief.swift`, add next to `traction` and `problem`:

```swift
    /// How long the founder's current money lasts. Raw founder text, not distilled.
    var runway: String?
    /// What the company must not propose — no hiring, a ship date, no outside
    /// investment. Raw founder text; one constraint per line.
    var constraints: String?
```

Add both to the memberwise `init` with `= nil` defaults and to the `self.x = x` list, and add them to `hasAnySignal`'s `s(...)` chain so a brief carrying only these still counts as signal.

- [ ] **Step 4: Write the mapper**

Create `codepet/Models/FounderContextMapper.swift`:

```swift
// codepet/Models/FounderContextMapper.swift
import Foundation

/// Builds the `founder` object the Virtual Company endpoint expects out of the
/// brief the app already holds.
///
/// Constraints matter more than they look: measured against the real backend,
/// departments produce concrete hard blockers when constraints are present and
/// noticeably vaguer positions when they are not. They are gathered by the
/// interview in Task 8, never invented here.
enum FounderContextMapper {

    static func founder(from brief: CompanyBrief) -> VCFounder {
        VCFounder(profile: profile(from: brief),
                  stage: stage(from: brief),
                  constraints: constraints(from: brief))
    }

    /// Joins the non-blank parts with " · ". Never returns "" — the endpoint
    /// answers HTTP 400 on a missing profile or stage.
    private static func join(_ parts: [String?], fallback: String) -> String {
        let kept = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return kept.isEmpty ? fallback : kept.joined(separator: " · ")
    }

    private static func profile(from brief: CompanyBrief) -> String {
        join([brief.role, brief.tech, brief.founderName],
             fallback: "Solo founder. Nothing else on record yet.")
    }

    /// Runway rides along in `stage`: the contract has no field for it, and stage
    /// is where the backend's own fixture puts "4 months of runway".
    private static func stage(from brief: CompanyBrief) -> String {
        join([brief.stage, brief.traction, brief.runway, brief.oneLiner, brief.goal],
             fallback: "Stage not on record yet.")
    }

    private static func constraints(from brief: CompanyBrief) -> [String] {
        (brief.constraints ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/FounderContextMapperTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 6 tests

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/CompanyBrief.swift codepet/Models/FounderContextMapper.swift \
        codepetTests/FounderContextMapperTests.swift
git commit -m "feat(vc): runway and constraints on the brief, mapped to the founder payload"
```

---

### Task 3: The streaming client

**Files:**
- Create: `codepet/Services/VirtualCompanyClient.swift`
- Test: `codepetTests/VirtualCompanyClientTests.swift`

**Interfaces:**
- Consumes: `VirtualCompanyRequest`, `VirtualCompanyEvent` (Task 1), `SSEParser`/`SSEFrame` (existing)
- Produces: `enum VirtualCompanyClient { static func run(_ req: VirtualCompanyRequest, session: URLSession = .shared, authTokenProvider: (() async throws -> String)? = nil) -> AsyncThrowingStream<VirtualCompanyEvent, Error> }`, `enum VirtualCompanyRunError: Error, Equatable { case notSignedIn, http(status: Int, body: VCErrorBody?), malformedResponse }`, `struct VCErrorBody: Codable, Equatable { let error: String; let detail: String?; let resetAt: String?; let limit: Int? }`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VirtualCompanyClientTests.swift`:

```swift
import XCTest
@testable import codepet

// Mirrors CompanyChatMockURLProtocol. VirtualCompanyClient is a plain enum with
// static functions (no actor isolation), so these tests need no @MainActor and
// dodge the Xcode 26.2 isolated-deinit teardown bug entirely.
final class VCMockURLProtocol: URLProtocol {
    static var responseStatus: Int = 200
    static var responseHeaders: [String: String] = ["Content-Type": "text/event-stream"]
    static var responseChunks: [Data] = []

    static func reset() {
        responseStatus = 200
        responseHeaders = ["Content-Type": "text/event-stream"]
        responseChunks = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: VCMockURLProtocol.responseStatus,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: VCMockURLProtocol.responseHeaders)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in VCMockURLProtocol.responseChunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class VirtualCompanyClientTests: XCTestCase {

    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VCMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func request() -> VirtualCompanyRequest {
        VirtualCompanyRequest(request: "Nên tăng giá hay ship team feature?",
                              language: "vi",
                              founder: VCFounder(profile: "p", stage: "s", constraints: []),
                              stressTest: false)
    }

    private func collect(_ session: URLSession) async throws -> [VirtualCompanyEvent] {
        var events: [VirtualCompanyEvent] = []
        for try await ev in VirtualCompanyClient.run(request(),
                                                    session: session,
                                                    authTokenProvider: { "fake" }) {
            events.append(ev)
        }
        return events
    }

    func testEscapeHatchStreamYieldsRoutingThenDone() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: run_started\ndata: {\"run_id\":\"r1\"}\n\n".data(using: .utf8)!,
            ("event: routing\ndata: {\"decision\":\"single_agent\",\"agents\":[\"product\"],"
             + "\"real_question\":\"Which label?\",\"request_type\":\"DECISION\"}\n\n").data(using: .utf8)!,
            "event: telemetry\ndata: {\"cost_estimate_usd\":0.004}\n\n".data(using: .utf8)!,
            "event: done\ndata: {\"run_id\":\"r1\",\"unresolved\":false,\"skipped\":\"single_agent\"}\n\n".data(using: .utf8)!
        ]

        let events = try await collect(mockedSession())
        XCTAssertEqual(events.count, 4)
        guard case let .done(_, _, skipped) = events[3] else { return XCTFail("expected .done last") }
        XCTAssertEqual(skipped, "single_agent")
    }

    func testFrameSplitAcrossChunksStillParses() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: run_star".data(using: .utf8)!,
            "ted\ndata: {\"run_".data(using: .utf8)!,
            "id\":\"r2\"}\n\n".data(using: .utf8)!
        ]
        let events = try await collect(mockedSession())
        XCTAssertEqual(events, [.runStarted(runId: "r2")])
    }

    func testUnknownFrameIsSkippedAndTheRestSurvives() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: some_future_event\ndata: {}\n\n".data(using: .utf8)!,
            "event: run_started\ndata: {\"run_id\":\"r3\"}\n\n".data(using: .utf8)!
        ]
        let events = try await collect(mockedSession())
        XCTAssertEqual(events, [.runStarted(runId: "r3")])
    }

    func testNon200ThrowsTypedErrorCarryingTheBody() async {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseStatus = 503
        VCMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        VCMockURLProtocol.responseChunks = [
            #"{"error":"feature_disabled"}"#.data(using: .utf8)!
        ]
        do {
            _ = try await collect(mockedSession())
            XCTFail("expected a throw")
        } catch let error as VirtualCompanyRunError {
            guard case let .http(status, body) = error else { return XCTFail("expected .http") }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(body?.error, "feature_disabled")
        } catch {
            XCTFail("expected VirtualCompanyRunError, got \(error)")
        }
    }

    func testRateLimitBodyDecodesResetAt() async {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseStatus = 429
        VCMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        VCMockURLProtocol.responseChunks = [
            #"{"error":"daily_limit_reached","reset_at":"2026-08-05T00:00:00Z","limit":100000}"#
                .data(using: .utf8)!
        ]
        do {
            _ = try await collect(mockedSession())
            XCTFail("expected a throw")
        } catch let error as VirtualCompanyRunError {
            guard case let .http(_, body) = error else { return XCTFail("expected .http") }
            XCTAssertEqual(body?.resetAt, "2026-08-05T00:00:00Z")
            XCTAssertEqual(body?.limit, 100_000)
        } catch {
            XCTFail("expected VirtualCompanyRunError, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyClientTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'VirtualCompanyClient' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Services/VirtualCompanyClient.swift`:

```swift
// codepet/Services/VirtualCompanyClient.swift
import Foundation
import FirebaseAuth

/// Non-SSE error body. The endpoint answers 400/401/405/429/503 as plain JSON
/// without opening a stream — see the contract's error table.
struct VCErrorBody: Codable, Equatable {
    let error: String
    let detail: String?
    let resetAt: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case error, detail, limit
        case resetAt = "reset_at"
    }
}

enum VirtualCompanyRunError: Error, Equatable {
    case notSignedIn
    case http(status: Int, body: VCErrorBody?)
    case malformedResponse
}

/// The only thing in the app that talks to `virtualCompanyRun`.
///
/// Deliberately shaped like `CompanyChatClient.sendStream`: a plain enum with
/// static functions, `URLSession.bytes(for:)` fed through the shared `SSEParser`,
/// and injectable `session` / `authTokenProvider` so tests exercise the decoding
/// with no network. Carrying no actor isolation also keeps its tests clear of the
/// Xcode 26.2 isolated-deinit teardown bug.
enum VirtualCompanyClient {

    static let endpoint = URL(string:
        "https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun")!

    static func run(
        _ req: VirtualCompanyRequest,
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = nil
    ) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        let capturedSession = session
        let capturedToken = authTokenProvider ?? {
            guard let token = try? await Auth.auth().currentUser?.getIDToken() else {
                throw VirtualCompanyRunError.notSignedIn
            }
            return token
        }

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedToken()

                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(req)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw VirtualCompanyRunError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw VirtualCompanyRunError.http(
                            status: http.statusCode,
                            body: try? JSONDecoder().decode(VCErrorBody.self, from: data))
                    }

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                if let event = VirtualCompanyEvent.from(frame: frame) {
                                    continuation.yield(event)
                                }
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            if let event = VirtualCompanyEvent.from(frame: frame) {
                                continuation.yield(event)
                            }
                        }
                    }
                    // The server always ends a frame with a blank line, but flush
                    // anyway so a missing trailing newline cannot swallow the last one.
                    for frame in parser.feedLines([""]) {
                        if let event = VirtualCompanyEvent.from(frame: frame) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyClientTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/VirtualCompanyClient.swift codepetTests/VirtualCompanyClientTests.swift
git commit -m "feat(vc): streaming client for virtualCompanyRun with offline tests"
```

---

### Task 4: The `product` department the contract asks for

**Files:**
- Modify: `codepet/Models/Department.swift` (the `DepartmentCatalog.all` array)
- Test: `codepetTests/VirtualCompanyDepartmentTests.swift`

**Interfaces:**
- Consumes: `DepartmentCatalog.all`, `Department` (existing)
- Produces: a `Department` whose `key == "product"`, so `department_key` from the wire resolves for both department agents.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VirtualCompanyDepartmentTests.swift`:

```swift
import XCTest
@testable import codepet

final class VirtualCompanyDepartmentTests: XCTestCase {

    /// The backend emits department_key "product" and "fin" for its two
    /// department agents (contract line 161). Both must resolve or the column
    /// renders with no name, cover or accent.
    func testEveryDepartmentKeyTheBackendSendsResolves() {
        let keys = Set(DepartmentCatalog.all.map(\.key))
        XCTAssertTrue(keys.contains("product"), "backend sends department_key=product")
        XCTAssertTrue(keys.contains("fin"), "backend sends department_key=fin")
    }

    func testProductDepartmentIsFullyPopulated() {
        let product = DepartmentCatalog.all.first { $0.key == "product" }
        let dept = try? XCTUnwrap(product)
        XCTAssertNotNil(dept)
        guard let dept else { return }
        XCTAssertFalse(dept.name.isEmpty)
        XCTAssertEqual(dept.ab.count, 2)
        XCTAssertFalse(dept.rationale.isEmpty)
        XCTAssertFalse(dept.focus.isEmpty)
    }

    func testKeysStayUnique() {
        let keys = DepartmentCatalog.all.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyDepartmentTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `backend sends department_key=product`

- [ ] **Step 3: Write minimal implementation**

In `codepet/Models/Department.swift`, append to the `DepartmentCatalog.all` array (after the `eng` entry, so Product reads next to Engineering):

```swift
        Department(key: "product", name: "Product", ab: "Pr", accent: CodepetTheme.accentTeal,
            rationale: "Decide what to build next and what to leave alone — sequencing, scope, and whether anyone actually wants it.",
            focus: "This is where you find out if the thing is worth building before you build it."),
```

Note on the cover image: `Department.coverAsset` derives `"dept-product"`, and `Assets.xcassets` has no such imageset. Add one by copying `dept-eng.imageset` to `dept-product.imageset` and renaming its `Contents.json` filename entry, or the row falls back to a blank image.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyDepartmentTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 3 tests

Then confirm nothing that counts departments broke:

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CompanyDataDeliverablesTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS. If a test asserts exactly eight departments, that assertion is now wrong — update it to reflect nine and say why in the commit.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/Department.swift codepet/Assets.xcassets/dept-product.imageset codepetTests/VirtualCompanyDepartmentTests.swift
git commit -m "feat(vc): add the Product department the SSE contract asks for"
```

---

### Task 5: The run-state reducer

This is where every rendering and handoff decision lives, so it can be tested without touching `CompanyStore`.

**Files:**
- Create: `codepet/Models/VirtualCompanyRunState.swift`
- Test: `codepetTests/VirtualCompanyRunStateTests.swift`

**Interfaces:**
- Consumes: every type from Task 1
- Produces:
  - `struct VirtualCompanyRunState: Equatable`
  - `enum VCRunPhase: Equatable { case idle, routing, working, negotiating, briefing, finished, failed }`
  - `mutating func apply(_ event: VirtualCompanyEvent)`
  - `var handsOffToRoom: Bool` — true once routing says `multi_agent`
  - `var isEscapeHatch: Bool` — true once routing says anything else
  - `var agentStatuses: [(meta: VCAgentMeta, status: AgentRunStatus)]` — feeds the existing `AgentsWorkingRow`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VirtualCompanyRunStateTests.swift`:

```swift
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
            VCTelemetry.self, from: #"{"cost_estimate_usd":0.21}"#.data(using: .utf8)!)))
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyRunStateTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'VirtualCompanyRunState' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/VirtualCompanyRunState.swift`:

```swift
// codepet/Models/VirtualCompanyRunState.swift
import Foundation

enum VCRunPhase: Equatable {
    case idle, routing, working, negotiating, briefing, finished, failed
}

/// Everything the cards render, folded out of the event stream by `apply`.
///
/// A plain struct on purpose. All the interesting decisions — does this hand off
/// to the room, which agent column is still spinning, did the run fail or just one
/// department — are answered here, where they can be unit-tested. `CompanyStore`
/// only forwards events into it, so the Xcode 26.2 isolated-deinit bug (which makes
/// any test that deallocates a @MainActor ObservableObject crash the test host)
/// costs no coverage.
struct VirtualCompanyRunState: Equatable {
    var runId: String?
    var routing: VCRouting?
    /// Agents in the order their `agent_start` arrived.
    var agents: [VCAgentMeta] = []
    var positions: [String: VCPosition] = [:]
    var agentErrors: [String: String] = [:]
    var conflicts: [VCConflict] = []
    var negotiationRounds: [VCNegotiationRound] = []
    var verdict: VCVerdict?
    var brief: VCBrief?
    var telemetry: VCTelemetry?
    var stoppedReason: String?
    var terminalError: String?
    var phase: VCRunPhase = .idle

    /// The one question CompanyStore asks: does byte hand this to the room?
    var handsOffToRoom: Bool { routing?.decision == "multi_agent" }

    /// The router judged this doesn't need the company. A correct, common outcome
    /// — not a failure.
    var isEscapeHatch: Bool {
        guard let decision = routing?.decision else { return false }
        return decision != "multi_agent"
    }

    /// Feeds the existing `AgentsWorkingRow`, which renders N concurrent agents.
    var agentStatuses: [(meta: VCAgentMeta, status: AgentRunStatus)] {
        agents.map { meta in
            if agentErrors[meta.agentId] != nil { return (meta, .failed) }
            if positions[meta.agentId] != nil { return (meta, .done) }
            return (meta, .working)
        }
    }

    mutating func apply(_ event: VirtualCompanyEvent) {
        switch event {
        case let .runStarted(runId):
            self.runId = runId
            phase = .routing

        case let .routing(routing):
            self.routing = routing
            phase = .routing

        case let .agentStart(meta):
            if !agents.contains(where: { $0.agentId == meta.agentId }) {
                agents.append(meta)
            }
            phase = .working

        case let .agentPosition(meta, position):
            if !agents.contains(where: { $0.agentId == meta.agentId }) {
                agents.append(meta)
            }
            positions[meta.agentId] = position

        case let .agentError(meta, message):
            if !agents.contains(where: { $0.agentId == meta.agentId }) {
                agents.append(meta)
            }
            // One department failing is not the run failing (spec §7).
            agentErrors[meta.agentId] = message

        case let .conflicts(list):
            conflicts = list

        case let .negotiationRound(round):
            negotiationRounds.append(round)
            phase = .negotiating

        case let .devilsAdvocate(meta, verdict):
            if !agents.contains(where: { $0.agentId == meta.agentId }) {
                agents.append(meta)
            }
            self.verdict = verdict

        case let .brief(brief):
            self.brief = brief
            phase = .briefing

        case let .runStopped(_, reason):
            // Shown verbatim; a `done` still follows, so the phase is not final here.
            stoppedReason = reason

        case let .telemetry(telemetry):
            self.telemetry = telemetry

        case .done:
            phase = .finished

        case let .error(code, _):
            terminalError = code
            phase = .failed
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyRunStateTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 12 tests

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/VirtualCompanyRunState.swift codepetTests/VirtualCompanyRunStateTests.swift
git commit -m "feat(vc): pure reducer folding the run's events into renderable state"
```

---

### Task 6: Fan-out and handoff in CompanyStore

Not unit-tested: `CompanyStore` is `@MainActor`, and a test that deallocates it crashes the XCTest host under Xcode 26.2 (Global Constraints). Verified by a green build and a real run.

**Files:**
- Modify: `codepet/Models/CopilotMessage.swift`
- Modify: `codepet/Managers/CompanyStore.swift` (inside `sendMessage`, around line 551–615)

**Interfaces:**
- Consumes: `VirtualCompanyClient.run` (Task 3), `VirtualCompanyRunState` (Task 5), `FounderContextMapper.founder` (Task 2)
- Produces: `CopilotMessage.vcRun: VirtualCompanyRunState?`; `CompanyStore.publishRunProgress(_:placeholderId:cid:language:)` (Task 8 calls it to trigger the interview)

- [ ] **Step 1: Add the message payload field**

In `codepet/Models/CopilotMessage.swift`, add to `struct CopilotMessage` next to the other optional payloads (`draft`, `interview`, `execSteps`):

```swift
    /// A Virtual Company run rendered inside this message. Follows the existing
    /// fat-struct/if-chain pattern rather than an enum refactor, per
    /// docs/superpowers/specs/2026-07-31-coding-agent-in-copilot-design.md §2.
    var vcRun: VirtualCompanyRunState?
```

- [ ] **Step 2: Build to confirm the field compiles everywhere**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED. If a memberwise initialiser call now fails to compile, the field needs a default in `CopilotMessage`'s `init` — give it `vcRun: VirtualCompanyRunState? = nil`.

- [ ] **Step 3: Add the fan-out**

In `CompanyStore.sendMessage`, immediately after `let req = CompanyChatRequest(...)` is built and before the streaming `do { ... }` block, start the run in parallel:

```swift
        // Fan-out: the room is convened by the router's escape hatch, not by a
        // client-side heuristic. Both calls go out at once so ordinary chat keeps
        // its current latency — running intake first would put ~2s in front of
        // every message, including "hi".
        let vcRequest = VirtualCompanyRequest(
            request: text,
            language: language.rawValue,
            founder: FounderContextMapper.founder(from: company.brief),
            stressTest: false)
        let vcTask = Task { [weak self] () -> VirtualCompanyRunState? in
            var state = VirtualCompanyRunState()
            do {
                for try await event in VirtualCompanyClient.run(vcRequest) {
                    state.apply(event)
                    // The escape hatch fired: discard the run and let chat be.
                    // The founder never learns a routing decision happened.
                    if state.isEscapeHatch { return nil }
                    guard let self else { return nil }
                    await self.publishRunProgress(state, placeholderId: placeholderId, cid: cid, language: language)
                }
            } catch {
                // A failed run must never damage the chat (spec §7). 503 is the
                // kill switch and 429 the daily cap — both are silent by design.
                // 400 is a client bug and the only one worth a log line.
                if case let .http(status, body) = error as? VirtualCompanyRunError ?? .malformedResponse,
                   status == 400 {
                    print("virtualCompanyRun rejected the payload: \(body?.detail ?? "no detail")")
                }
                return nil
            }
            return state.handsOffToRoom ? state : nil
        }
```

Add the two supporting members to `CompanyStore`:

```swift
    /// Pushes run progress into the placeholder message. On the first handoff the
    /// message text is REPLACED with byte's one-liner rather than appended to:
    /// half an answer to a decision question is noise sitting above the room that
    /// is about to answer it properly (spec §3).
    private func publishRunProgress(_ state: VirtualCompanyRunState,
                                    placeholderId: String,
                                    cid: String,
                                    language: AppLanguage) async {
        guard companyId == cid, state.handsOffToRoom else { return }
        guard let i = chatMessages.firstIndex(where: { $0.id == placeholderId }) else { return }
        if chatMessages[i].vcRun == nil {
            chatMessages[i].text = language == .vi
                ? "Cái này cần cả phòng, để mình gọi product với finance vào."
                : "This one needs the whole room — let me bring in product and finance."
        }
        chatMessages[i].vcRun = state
    }
```

- [ ] **Step 4: Cancel the chat stream on handoff**

Inside the existing `for try await event in chatStreamer(req)` loop, in the `.delta` case, stop writing deltas once the room has taken over:

```swift
                case .delta(let chunk):
                    // The room took this turn: byte's partial answer is discarded
                    // rather than left above the cards.
                    if chatMessages.first(where: { $0.id == placeholderId })?.vcRun != nil { break }
                    if isCompanionTyping { isCompanionTyping = false }
                    streamedText += chunk
                    if let i = chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                        chatMessages[i].text = streamedText
                    }
```

And after the existing fallback block, suppress the offline copy when a run is rendering:

```swift
        // If the room answered, an unreachable companyChat is irrelevant — do not
        // overwrite the room with byte's offline line.
        let roomAnswered = chatMessages.first(where: { $0.id == placeholderId })?.vcRun != nil
        if (streamThrew || !receivedDone) && !roomAnswered {
```

(That `&& !roomAnswered` is added to the existing `if streamThrew || !receivedDone {` condition.)

Finally, await the run before returning so `isStreaming` stays true for its duration:

```swift
        _ = await vcTask.value
```

- [ ] **Step 5: Build and verify against the live endpoint**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

Then launch the app, sign in, and send both:

1. "Đặt tên tab thứ 4 là Insights hay Progress?" → expect an ordinary chat reply, no cards, and nothing in the UI hinting a run happened.
2. "Nên launch Codepet miễn phí kèm quảng cáo, hay bán một lần $9.99?" → expect byte's handoff line, then the run state populating.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/CopilotMessage.swift codepet/Managers/CompanyStore.swift
git commit -m "feat(vc): fan chat out to the company and hand off on multi_agent"
```

---

### Task 7: The cards, and locking a decision in

**Files:**
- Create: `codepet/Views/Copilot/VirtualCompanyCards.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`
- Modify: `codepet/Managers/CompanyStore.swift` (the Decisions action)
- Test: `codepetTests/VirtualCompanyDecisionTests.swift`

**Interfaces:**
- Consumes: `VirtualCompanyRunState` (Task 5), `MessageCard` and `AgentsWorkingRow` (existing), `Decisions.mergeDecisions` and `ExtractedDecision` (existing, `codepet/Models/Decisions.swift`)
- Produces: `VCRunCards(state:onLockIn:)`; `static VirtualCompanyDecision.extracted(from:runId:) -> ExtractedDecision?`

- [ ] **Step 1: Write the failing test for the Decisions mapping**

Create `codepetTests/VirtualCompanyDecisionTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyDecisionTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'VirtualCompanyDecision' in scope`

- [ ] **Step 3: Write the mapping**

Add to `codepet/Models/VirtualCompanyRunState.swift`:

```swift
/// Turns a finished run into a decision the founder can lock in.
///
/// Never automatic. The app's own pattern is approve-then-record —
/// `DecisionsClient.extract` takes an `ApprovedDeliverableDTO`, never a draft —
/// and the brief exists precisely to hand the founder a trade-off nobody else can
/// make. Recording it before they decide would put words in their mouth.
enum VirtualCompanyDecision {
    static func extracted(from state: VirtualCompanyRunState, runId: String) -> ExtractedDecision? {
        guard let brief = state.brief else { return nil }
        let topic = state.routing?.realQuestion.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !topic.isEmpty else { return nil }
        return ExtractedDecision(topic: topic,
                                 statement: brief.recommendation,
                                 source: "virtual-company/\(runId)")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyDecisionTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 3 tests

- [ ] **Step 5: Build the cards**

Create `codepet/Views/Copilot/VirtualCompanyCards.swift`:

```swift
// codepet/Views/Copilot/VirtualCompanyCards.swift
import SwiftUI

/// The room, rendered inside the chat. Stacked vertically because the dock is
/// 380pt wide — positions cannot sit in columns here, so they read as a sequence.
struct VCRunCards: View {
    let state: VirtualCompanyRunState
    let onLockIn: () -> Void

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routing = state.routing { routingCard(routing) }
            if !state.agents.isEmpty { AgentsWorkingRow(runs: agentRuns) }
            ForEach(state.agents, id: \.agentId) { meta in
                if let position = state.positions[meta.agentId] {
                    positionCard(meta, position)
                }
                if let error = state.agentErrors[meta.agentId] {
                    errorRow(meta, error)
                }
            }
            if !state.conflicts.isEmpty { conflictCard }
            ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
            if let verdict = state.verdict { verdictCard(verdict) }
            if let brief = state.brief { briefCard(brief) }
            if let stopped = state.stoppedReason { stoppedRow(stopped) }
        }
    }

    /// Bridges into the existing multi-agent row, which already knows how to show
    /// N concurrent agents with avatar, dept, status pill and elapsed time.
    private var agentRuns: [AgentRun] {
        state.agentStatuses.map { entry in
            let dept = DepartmentCatalog.all.first { $0.key == entry.meta.departmentKey }
            return AgentRun(id: entry.meta.agentId,
                            companionId: entry.meta.agentId,
                            deptName: dept?.name ?? (lang == .vi ? "Ban điều hành" : "Chief of staff"),
                            taskTitle: state.routing?.realQuestion ?? "",
                            steps: [],
                            status: entry.status,
                            startedAt: Date())
        }
    }

    // Spec §4.3: routing is CONTENT, not a loading state. It is the panel where
    // the founder sees their question decomposed.
    private func routingCard(_ routing: VCRouting) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "CÂU HỎI THẬT" : "THE REAL QUESTION")
                Text(routing.realQuestion)
                    .font(CodepetTheme.inter(15, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                ForEach(routing.agentMeta, id: \.agentId) { meta in
                    if let why = routing.reasonPerAgent[meta.agentId] {
                        Text("✓ \(displayName(meta)) — \(why)")
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                if !routing.missingInfo.isEmpty {
                    Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                         + routing.missingInfo.joined(separator: "; "))
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    private func positionCard(_ meta: VCAgentMeta, _ position: VCPosition) -> some View {
        MessageCard(hue: accent(meta)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(displayName(meta)).font(CodepetTheme.sectionName())
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(stanceLabel(position.stance))
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent(meta).opacity(0.12)))
                        .foregroundColor(accent(meta))
                    Spacer()
                    Text("\(position.confidence)/5")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                }
                Text(position.position).font(CodepetTheme.inter(14))
                    .foregroundColor(CodepetTheme.bodyText)
                Text((lang == .vi ? "Cái này khiến họ mất: " : "Costs their department: ")
                     + position.costToMyDept)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                if let blocker = position.hardBlocker {
                    Text("🔒 " + blocker)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
        }
    }

    // Spec §4.3: the highest-value view in the feature. Never collapsed.
    private var conflictCard: some View {
        MessageCard(hue: CodepetTheme.accentOrange) {
            VStack(alignment: .leading, spacing: 6) {
                label(lang == .vi ? "HỌ KHÔNG ĐỒNG Ý Ở ĐÂU" : "WHERE THEY DISAGREE")
                ForEach(state.conflicts, id: \.reason) { conflict in
                    Text("\(conflict.a) ↔ \(conflict.b) · \(conflict.kind)")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(conflict.reason).font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
        }
    }

    private func roundCard(_ round: VCNegotiationRound) -> some View {
        MessageCard(hue: CodepetTheme.hairline) {
            VStack(alignment: .leading, spacing: 6) {
                label((lang == .vi ? "VÒNG " : "ROUND ") + "\(round.round)")
                ForEach(round.turns, id: \.agent) { turn in
                    Text("\(turn.agent): \(turn.preciseDisagreement)")
                        .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.bodyText)
                    Text((lang == .vi ? "Đề xuất: " : "Proposes: ") + turn.proposal)
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    // No department colour: it is not a department (contract, §4.3).
    private func verdictCard(_ verdict: VCVerdict) -> some View {
        MessageCard(hue: CodepetTheme.primaryText) {
            VStack(alignment: .leading, spacing: 6) {
                label(lang == .vi ? "NGƯỜI PHẢN BIỆN" : "THE CHALLENGER")
                Text(verdict.loadBearingAssumption).font(CodepetTheme.inter(14, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(verdict.howItCouldBeFalse).font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                Text((lang == .vi ? "Cách kiểm rẻ nhất: " : "Cheapest test: ") + verdict.cheapestTest)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            }
        }
    }

    private func briefCard(_ brief: VCBrief) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "KHUYẾN NGHỊ" : "RECOMMENDATION")
                Text(brief.recommendation).font(CodepetTheme.inter(14))
                    .foregroundColor(CodepetTheme.bodyText)
                label(lang == .vi ? "ĐÁNH ĐỔI CHỈ BẠN QUYẾT ĐƯỢC" : "THE TRADE-OFF ONLY YOU CAN MAKE")
                Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                label(lang == .vi ? "DỪNG NẾU" : "STOP IF")
                ForEach(brief.killCriteria, id: \.self) { criterion in
                    Text("· " + criterion).font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.bodyText)
                }
                Text((lang == .vi ? "Việc tiếp theo (\(brief.nextAction.owner)): "
                                  : "Next action (\(brief.nextAction.owner)): ") + brief.nextAction.action)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                Text((lang == .vi ? "Vẫn chưa biết: " : "Still unknown: ") + brief.whatWeDontKnow)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                if let cost = state.telemetry?.costEstimateUsd {
                    // Spec §4.3: the founder has a right to know what the answer cost.
                    Text(String(format: "$%.3f", cost))
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                Button(action: onLockIn) {
                    Text(lang == .vi ? "Chốt quyết định này" : "Lock this decision in")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.accentPurple))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Written for the founder by the backend — shown verbatim (contract).
    private func stoppedRow(_ reason: String) -> some View {
        Text(reason).font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
    }

    private func errorRow(_ meta: VCAgentMeta, _ error: String) -> some View {
        Text("\(displayName(meta)): \(error)")
            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
            .foregroundColor(CodepetTheme.mutedText)
    }

    private func displayName(_ meta: VCAgentMeta) -> String {
        DepartmentCatalog.all.first { $0.key == meta.departmentKey }?.name ?? meta.agentId
    }

    private func accent(_ meta: VCAgentMeta) -> Color {
        DepartmentCatalog.all.first { $0.key == meta.departmentKey }?.accent
            ?? CodepetTheme.accentPurple
    }

    private func stanceLabel(_ stance: String) -> String {
        switch (stance, lang) {
        case ("proceed", .vi):                 return "nên làm"
        case ("proceed", _):                   return "proceed"
        case ("proceed_with_conditions", .vi): return "làm, có điều kiện"
        case ("proceed_with_conditions", _):   return "with conditions"
        case ("do_not_proceed", .vi):          return "không nên"
        default:                               return "do not proceed"
        }
    }
}
```

- [ ] **Step 6: Render the cards and wire the button**

In `CopilotChatView.swift`, inside the branch that renders a companion message's payloads (next to where `draft`, `interview` and `execSteps` are handled), add:

```swift
                    if let run = message.vcRun {
                        VCRunCards(state: run) {
                            Task { await companyStore.lockInVirtualCompanyDecision(run) }
                        }
                    }
```

And in `CompanyStore`:

```swift
    /// Records the brief as a decision the founder has locked in, which then
    /// grounds chat and run-task through ChatContext.
    func lockInVirtualCompanyDecision(_ state: VirtualCompanyRunState) async {
        guard let runId = state.runId,
              let extracted = VirtualCompanyDecision.extracted(from: state, runId: runId) else { return }
        let cid = companyId
        company.decisions = Decisions.mergeDecisions(existing: company.decisions,
                                                     extracted: [extracted],
                                                     now: Date().timeIntervalSince1970 * 1000)
        // Same persistence path the other mergeDecisions caller uses
        // (CompanyStore.swift:778) — an async saver closure, not a sync persist().
        _ = await decisionsSaver(cid, company.decisions)
    }
```

- [ ] **Step 7: Build and verify visually**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

Then send the pricing question in the app and confirm: routing renders immediately as content, both agents appear at once, positions land one at a time, the conflict is visible without expanding anything, the brief shows its cost, and "Chốt quyết định này" adds an entry visible in the Overview second-brain panel.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/VirtualCompanyCards.swift codepet/Views/Copilot/CopilotChatView.swift \
        codepet/Models/VirtualCompanyRunState.swift codepet/Managers/CompanyStore.swift \
        codepetTests/VirtualCompanyDecisionTests.swift
git commit -m "feat(vc): render the room in chat and let the founder lock the brief in"
```

---

### Task 8: Ask for runway and constraints after the first brief

**Files:**
- Modify: `codepet/Models/EnrichInterview.swift`
- Create: `codepet/Models/VirtualCompanyInterview.swift`
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/VirtualCompanyInterviewTests.swift`

**Interfaces:**
- Consumes: `VirtualCompanyRunState` (Task 5), `InterviewGap` and `EnrichInterview.question(for:language:)` (existing), `CompanyBrief.runway` / `.constraints` (Task 2)
- Produces: `InterviewGap.runway` and `InterviewGap.constraints` cases; `enum VirtualCompanyInterview { static func shouldAsk(state: VirtualCompanyRunState, brief: CompanyBrief, alreadyAsked: Bool) -> Bool; static let gaps: [InterviewGap] }`

**Why the enum, not a new type.** `InterviewGap` is a closed `String` enum (`goal, traction, problem`) and the chat card is driven by `CopilotMessage.interview: InterviewGap?`. Reusing the existing ask/answer path therefore means adding cases, not inventing a parallel type. `EnrichInterview.detectGaps` filters `gapOrder`, so leaving the two new cases out of `gapOrder` keeps the first-run onboarding interview exactly as it is — which the spec requires, since another engineer owns onboarding.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VirtualCompanyInterviewTests.swift`:

```swift
import XCTest
@testable import codepet

final class VirtualCompanyInterviewTests: XCTestCase {

    private func finishedRun() -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        let json: [String: Any] = ["decision": "multi_agent", "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        s.apply(.routing(try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))))
        s.apply(.brief(VCBrief(recommendation: "r", confidence: 3, confidenceReason: "c",
                               theRealDisagreement: "d", tradeoffFounderMustOwn: "t", killCriteria: ["k"],
                               nextAction: VCNextAction(action: "a", owner: "Founder"),
                               whatWeDontKnow: "u", unresolved: false)))
        s.apply(.done(runId: "r1", unresolved: false, skipped: nil))
        return s
    }

    func testAsksOnceAfterTheFirstBriefWithNoConstraints() {
        XCTAssertTrue(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: CompanyBrief(), alreadyAsked: false))
    }

    func testNeverAsksTwice() {
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: CompanyBrief(), alreadyAsked: true))
    }

    func testDoesNotAskWhenConstraintsAreAlreadyOnRecord() {
        var brief = CompanyBrief()
        brief.constraints = "Không thuê người quý này."
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: brief, alreadyAsked: false))
    }

    func testDoesNotAskUntilABriefActuallyArrived() {
        // Asking after a failed or escape-hatch run would interrogate the founder
        // for nothing.
        var s = VirtualCompanyRunState()
        s.apply(.error("upstream_failure", nil))
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: s, brief: CompanyBrief(), alreadyAsked: false))
    }

    func testAsksRunwayThenConstraints() {
        XCTAssertEqual(VirtualCompanyInterview.gaps, [.runway, .constraints])
    }

    func testBothNewGapsHaveCopyInBothLanguages() {
        for gap in VirtualCompanyInterview.gaps {
            for lang in [AppLanguage.vi, AppLanguage.en] {
                let q = EnrichInterview.question(for: gap, language: lang)
                XCTAssertFalse(q.ask.isEmpty, "\(gap) has no ask in \(lang)")
                XCTAssertFalse(q.why.isEmpty, "\(gap) has no why in \(lang)")
            }
        }
    }

    func testOnboardingInterviewIsUnchanged() {
        // The first-run interview filters gapOrder, so the two new cases must not
        // appear there — onboarding is owned by someone else.
        XCTAssertEqual(EnrichInterview.gapOrder, [.goal, .traction, .problem])
        XCTAssertFalse(EnrichInterview.detectGaps(nil).contains(.runway))
        XCTAssertFalse(EnrichInterview.detectGaps(nil).contains(.constraints))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyInterviewTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `type 'InterviewGap' has no member 'runway'`

- [ ] **Step 3: Add the two gap cases and their copy**

In `codepet/Models/EnrichInterview.swift`, extend the enum:

```swift
enum InterviewGap: String, CaseIterable, Equatable {
    case goal, traction, problem
    /// Asked by the Virtual Company, not by the first-run interview — deliberately
    /// absent from `gapOrder` so `detectGaps` never surfaces them in onboarding.
    case runway, constraints
}
```

Add the two branches to `value(_:_:)`:

```swift
        case .runway: return brief.runway
        case .constraints: return brief.constraints
```

And to `question(for:language:)`:

```swift
        case .runway:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Tiền hiện tại còn đủ cho bao lâu?",
                    why: "để phòng họp cân được chi phí với thời gian bạn còn")
                : InterviewQuestion(
                    ask: "How long does your current money last?",
                    why: "so the room can weigh cost against the time you actually have")
        case .constraints:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Có ràng buộc nào phòng họp không được đề xuất? (không thuê người, hạn ship, không nhận đầu tư…)",
                    why: "để không ai đề xuất thứ bạn đã loại từ đầu")
                : InterviewQuestion(
                    ask: "Any constraint the room must not propose? (no hiring, a ship date, no outside investment…)",
                    why: "so nobody recommends something you already ruled out")
```

- [ ] **Step 4: Write the gate**

Create `codepet/Models/VirtualCompanyInterview.swift`:

```swift
// codepet/Models/VirtualCompanyInterview.swift
import Foundation

/// The two questions that make the room concrete instead of generic.
///
/// It cannot run before the answer it improves. All five phases happen inside one
/// HTTP request, so there is no point at which the client can stop after intake,
/// ask, and resume — and aborting mid-stream would not help either, because the
/// function keeps working after a client disconnect and we would pay for a run we
/// threw away. So the first decision runs thin, the backend says so honestly in
/// `what_we_dont_know`, and this asks afterwards to sharpen every run after it.
enum VirtualCompanyInterview {

    /// Runway first: it is the number that changes a recommendation most.
    static let gaps: [InterviewGap] = [.runway, .constraints]

    static func shouldAsk(state: VirtualCompanyRunState,
                          brief: CompanyBrief,
                          alreadyAsked: Bool) -> Bool {
        guard !alreadyAsked else { return false }
        let onRecord = (brief.constraints ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard onRecord.isEmpty else { return false }
        // Only after a brief actually landed: no interrogation to pay for nothing.
        return state.brief != nil
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/VirtualCompanyInterviewTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS, 7 tests

Then confirm the onboarding interview really is untouched:

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/EnrichInterviewTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS. (If no such suite exists, run the whole `codepetTests` target and note which suites fail for the documented Xcode 26.2 reason rather than for this change.)

- [ ] **Step 6: Wire it into the store**

In `CompanyStore`, add the flag and the trigger, and call the trigger from `publishRunProgress` (Task 6) once `state.brief != nil`:

```swift
    /// Asked at most once. Not persisted: re-asking after a relaunch is harmless
    /// because `shouldAsk` also checks whether constraints are already on record.
    @Published var vcInterviewAsked: Bool = false

    private func maybeAskVirtualCompanyInterview(_ state: VirtualCompanyRunState,
                                                 language: AppLanguage) {
        guard VirtualCompanyInterview.shouldAsk(state: state,
                                                brief: company.brief,
                                                alreadyAsked: vcInterviewAsked) else { return }
        vcInterviewAsked = true
        // Reuses the existing queue: askInterviewGap owns the card, answerInterview
        // owns the reply path.
        let gaps = VirtualCompanyInterview.gaps
        interviewState = (gaps: gaps, idx: 0)
        askInterviewGap(gaps[0], language: language)
    }
```

In `answerInterview`, the existing code writes an answer into the brief field for the gap it just asked. Extend that mapping with the two new cases so `.runway` writes `company.brief.runway` and `.constraints` writes `company.brief.constraints`, then persist by whatever path the neighbouring brief writes already use in that function.

- [ ] **Step 7: Build and verify the once-only behaviour**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED

In the app: ask a decision question, wait for the brief, confirm the two questions appear after it. Answer them. Ask a second decision question and confirm the questions do **not** appear again, and that the new brief's positions now reference the constraint you gave.

- [ ] **Step 8: Commit**

```bash
git add codepet/Models/EnrichInterview.swift codepet/Models/VirtualCompanyInterview.swift \
        codepet/Managers/CompanyStore.swift codepetTests/VirtualCompanyInterviewTests.swift
git commit -m "feat(vc): ask for runway and constraints once, after the first brief"
```

---

## Verification before opening the PR

- [ ] `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED
- [ ] All six new suites pass: `VirtualCompanyRunDTOTests`, `FounderContextMapperTests`, `VirtualCompanyClientTests`, `VirtualCompanyDepartmentTests`, `VirtualCompanyRunStateTests`, `VirtualCompanyDecisionTests`, `VirtualCompanyInterviewTests`
- [ ] A one-dimensional question ("Đặt tên tab thứ 4 là Insights hay Progress?") produces an ordinary chat reply with no cards and no visible trace of a run
- [ ] A real trade-off ("Nên launch Codepet miễn phí kèm quảng cáo, hay bán một lần $9.99?") produces the handoff line, both agents at once, positions, the conflict, and a brief
- [ ] Turning the kill switch on (Firestore `config/virtual_company` → `{enabled: false}`) leaves chat working with no cards and no error text. **Set it back to `true` afterwards**
- [ ] "Chốt quyết định này" adds a decision visible in the Overview second-brain panel

## Out of scope, tracked in the spec

`detectConflicts` reporting a false `BLOCKER` when both departments block the same way; the 4-agent roster against nine UI departments; a real visual identity for the devil's advocate. All three are recorded in §10 of the spec.
