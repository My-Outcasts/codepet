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

    /// Whether "lock this decision in" has anything to record. Without a run id, a
    /// topic (`real_question`) and a non-blank recommendation the button would be a
    /// silent no-op, so it is not offered at all.
    var canLockIn: Bool {
        guard let runId else { return false }
        return VirtualCompanyDecision.extracted(from: self, runId: runId) != nil
    }

    /// The router judged this doesn't need the company. A correct, common outcome
    /// — not a failure.
    var isEscapeHatch: Bool {
        guard let decision = routing?.decision else { return false }
        return decision != "multi_agent"
    }

    /// One status pill per agent in the room.
    ///
    /// `.working` is only honest while the run is still going. A budget-stopped run
    /// (`run_stopped` then `done`) and a lost stream (the seal: `terminalError`,
    /// `.failed`) both end with departments that never filed a position, and reading
    /// those as "working" left their columns spinning forever — in the seal's case
    /// underneath a red error card saying the run had stopped. Once the run is over, an
    /// agent with neither a position nor an error has stalled, so it reads `.failed`:
    /// there is no outcome coming.
    var agentStatuses: [(meta: VCAgentMeta, status: AgentRunStatus)] {
        let runEnded = phase == .finished || phase == .failed
        return agents.map { meta in
            if agentErrors[meta.agentId] != nil { return (meta, .failed) }
            if positions[meta.agentId] != nil { return (meta, .done) }
            return (meta, runEnded ? .failed : .working)
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
        // A blank recommendation would record a decision that says nothing, and ground
        // every later chat turn on it.
        let statement = brief.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, !statement.isEmpty else { return nil }
        return ExtractedDecision(topic: topic,
                                 statement: statement,
                                 source: "virtual-company/\(runId)")
    }
}
