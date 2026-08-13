import Foundation

/// Where an engineering run is, from the founder's point of view.
///
/// The strings these map from are the backend's `RunStatus`
/// (`functions/src/engineering/engClient.ts`) plus the Managed Agents stop
/// reasons the relay forwards. Those two lists and this enum are one contract
/// in two languages: if a case is added there and not here, a run silently
/// reports `.failed`, so `EngineeringRunTests` pins every value the backend
/// can send.
enum EngineeringPhase: Equatable {
    /// The session exists and has not produced anything yet.
    case preparing
    case running
    /// Paused on a permission ask. The founder is the blocker, not the agent.
    case awaitingApproval
    /// Finished a turn. There is a diff to read.
    case reviewing
    /// Paused at its spend cap, which is why this is NOT `.failed`: the work
    /// is intact on the branch, and telling a founder their run failed when it
    /// is sitting there makes them start over and pay twice.
    ///
    /// Resumable in principle only. Raising a session's budget continues it in
    /// place on Anthropic's side, but Codepet exposes no endpoint that raises
    /// one — so there is nothing to hang a "Resume" control on today, and the
    /// copy says the work is safe rather than offering a button that lies.
    case budgetReached
    case failed(String)
}

extension EngineeringRun {
    /// The most credits one run can spend, mirroring `DEFAULT_RUN_CREDITS` in
    /// `functions/src/engineering/engBudget.ts` (40 credits = $2.00 at
    /// `CREDIT_CENTS = 5`).
    ///
    /// Duplicated across the wire rather than sent in the 402 body, because
    /// it is a product constant and not runtime state. Being honest about the
    /// cost: NO test can catch this drifting from the backend's value — they
    /// are in different languages and different test runners. If the cap
    /// changes there, it has to be changed here by hand.
    static let creditsPerRun = 40
}

/// Which base the Review pane's diff is taken against.
///
/// `commit` is in the design's selector and is deliberately absent here: it
/// needs a commit id the diff endpoint is not given, and `engDiff.parseScope`
/// maps it to the whole branch rather than pretending. Adding the case before
/// the endpoint can honour it would put a control in the UI that lies.
/// `Codable` because it round-trips as the `scope` field of a diff response;
/// the raw values are the `?scope=` query string `engDiff.parseScope` reads.
enum ReviewScope: String, CaseIterable, Equatable, Codable {
    case branch
    case turn
}

/// One file in a run's diff, as `engDiff` returns it.
struct EngFileDiff: Identifiable, Equatable, Codable {
    /// The file's current name. Stable across turns, and what any later fetch
    /// keys off — for a rename this is the NEW name.
    let file: String
    /// Display label. For a rename, `old → new`; otherwise equal to `file`.
    /// Never use this as an identity: it changes when a file is renamed, and a
    /// list keyed on it would animate the row as a delete plus an insert.
    let path: String
    let additions: Int
    let deletions: Int
    let status: String
    /// nil for a binary file — GitHub omits the patch. The row still belongs
    /// in the list: "we changed your logo" is information even when the bytes
    /// cannot be shown.
    let patch: String?

    var id: String { file }
    var isBinary: Bool { patch == nil }
}

/// A run's whole diff, plus the two honesty flags the pane must surface.
struct EngDiffSummary: Equatable, Codable {
    let files: [EngFileDiff]
    let additions: Int
    let deletions: Int
    /// GitHub caps a compare at 300 files. When true the list is INCOMPLETE,
    /// and showing it as if it were everything would be a lie of omission.
    let truncated: Bool
    let scope: ReviewScope
    /// The founder asked for one turn's changes and is looking at the whole
    /// branch, because the turn's base is not recorded yet. Surfacing this is
    /// the difference between a wider diff and a wrong one.
    let scopeFellBack: Bool

    static let empty = EngDiffSummary(
        files: [], additions: 0, deletions: 0,
        truncated: false, scope: .branch, scopeFellBack: false
    )
}

/// A tool the agent wants to run, waiting on the founder.
///
/// `id` is the Managed Agents `tool_use_id`, which is what `engSendTurn`
/// answers against — so two cards can never be confused, and answering one
/// twice is detectable.
struct EngApproval: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    /// The command, already rendered for display. A string rather than the raw
    /// JSON: the founder is being asked to approve something they can read.
    let input: String
}

enum EngineeringRun {
    /// A stop reason from the relay → the phase the card renders.
    ///
    /// Mirrors `statusFor` in `engWebhook.ts`, including its most important
    /// choice: an UNKNOWN reason is `.failed`, not `.reviewing`. If Anthropic
    /// adds a stop reason nobody has handled, the honest read is "we do not
    /// know this finished" — not a card inviting the founder to ship a diff
    /// nothing verified.
    static func phase(fromStopReason reason: String?) -> EngineeringPhase {
        switch reason {
        case "end_turn": return .reviewing
        case "budget_reached": return .budgetReached
        case "requires_action": return .awaitingApproval
        default: return .failed("unknown_stop_reason")
        }
    }

    /// A backend `RunStatus` string → the phase the card renders.
    ///
    /// Separate from `phase(fromStopReason:)` because they are different
    /// vocabularies for the same moment — the webhook writes a RunStatus to
    /// the run document, while the live stream carries a stop reason. Folding
    /// them into one function would invite passing the wrong one.
    static func phase(fromStatus status: String?) -> EngineeringPhase {
        switch status {
        case "starting": return .preparing
        case "running": return .running
        case "reviewing": return .reviewing
        case "budgetReached": return .budgetReached
        case "failed": return .failed("run_failed")
        default: return .failed("unknown_status")
        }
    }
}
