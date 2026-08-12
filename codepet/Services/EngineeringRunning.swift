import Foundation

/// Everything a founder can send into a live engineering session.
///
/// These four shapes are exactly what `buildTurnEvents` in `engSendTurn.ts`
/// accepts, and there is no fifth. A case added here without a matching branch
/// there produces a 400 the founder cannot act on.
enum EngineeringTurn: Equatable {
    case text(String)
    case approve(toolUseId: String)
    /// A denial with a reason lets the agent try another way instead of
    /// stalling against a wall it cannot see the shape of.
    case deny(toolUseId: String, reason: String?)
    case interrupt

    /// The JSON body `engSendTurn` parses. Built here rather than in the client
    /// so the mock and the real conformer cannot drift on the wire shape.
    var body: [String: Any] {
        switch self {
        case .text(let text):
            return ["text": text]
        case .approve(let id):
            return ["approve": ["toolUseId": id, "allow": true]]
        case .deny(let id, let reason):
            var approve: [String: Any] = ["toolUseId": id, "allow": false]
            if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
                approve["reason"] = reason
            }
            return ["approve": approve]
        case .interrupt:
            return ["interrupt": true]
        }
    }
}

/// What the backend can refuse with, in the founder's terms.
///
/// One case per status the handlers actually return (see Plan 1 and Plan 2),
/// so the store maps a refusal once and every surface renders the same words.
/// `unknown` exists because a status nobody mapped must not silently read as
/// one that was.
enum EngineeringError: Error, Equatable {
    /// 409 — no repo linked. The client offers connect-or-create.
    case noRepoLinked
    /// 409 — GitHub itself is not connected. A different fix from the above.
    case gitHubNotConnected
    /// 402 — out of credits.
    case noCredits
    /// 500 — a deploy problem. Ours, never the founder's fault.
    case misconfigured
    /// 503 — retryable.
    case unavailable
    case unknown(Int)

    static func from(status: Int, code: String?) -> EngineeringError {
        switch (status, code) {
        case (402, _): return .noCredits
        case (409, "github_not_connected"): return .gitHubNotConnected
        case (409, _): return .noRepoLinked
        case (500, _): return .misconfigured
        case (503, _): return .unavailable
        default: return .unknown(status)
        }
    }
}

/// The seam over the engineering backend, so the whole flow is drivable
/// without a network, an Anthropic account, or credits.
///
/// Same shape as `CodeRunning` does for the local runner: one protocol, one
/// production conformer, one mock. The mock is not only a test fixture — with
/// the Anthropic account out of credits it is the only way to look at this UI
/// at all.
protocol EngineeringRunning {
    /// Start a run and stream its frames. Returns the runId as soon as the
    /// session exists; the closure keeps firing until the run reaches a
    /// terminal state or the caller cancels.
    func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String

    /// Re-attach to a run already in flight — a reconnect, or a founder
    /// returning to a run they left. The relay replays history, so the caller
    /// must tolerate frames it has already seen.
    func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws

    func send(runId: String, turn: EngineeringTurn) async throws

    func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary
}
