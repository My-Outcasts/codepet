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
