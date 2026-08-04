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

    enum CodingKeys: String, CodingKey {
        case profile, stage, constraints
    }
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

    enum CodingKeys: String, CodingKey {
        case a, b, kind, reason
    }
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

    enum CodingKeys: String, CodingKey {
        case round, turns
    }
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

    enum CodingKeys: String, CodingKey {
        case action, owner
    }
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

struct VCTokenUsage: Codable, Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
    }
}

struct VCTelemetry: Codable, Equatable {
    /// Keyed by agent id. Always present — the backend initialises it to {}.
    let tokensPerAgent: [String: VCTokenUsage]
    /// Always present; the backend initialises it to 0. Non-optional on purpose:
    /// a missing value means a malformed payload, not a free run.
    let costEstimateUsd: Double
    let stoppedReason: String?

    enum CodingKeys: String, CodingKey {
        case tokensPerAgent = "tokens_per_agent"
        case costEstimateUsd = "cost_estimate_usd"
        case stoppedReason = "stopped_reason"
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
