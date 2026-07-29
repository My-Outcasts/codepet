import Foundation

/// What tapping a roadmap task does.
enum RoadmapAction: Equatable {
    case run              // Codepet can do it (cloud) — output streams into chat
    case walkThrough      // needs the founder — the walkthrough streams into chat
    case approve          // needs approval — resolves in place
    case openDeliverable  // done — opens the deliverable sheet in place
    case editCode         // Engineering + a linked project — the local coding agent
    case none             // blocked — nothing to do yet
}

/// Pure routing rule for a roadmap task tap. Kept out of the view so the
/// "follow the action to chat" behaviour is testable on its own.
enum RoadmapDispatch {
    /// `isEngineering`/`projectLinked` default false so existing callers keep the
    /// original mapping; Engineering work runs LOCALLY (`.editCode`) only when a
    /// project is linked, otherwise it stays on the cloud run path (unchanged).
    static func action(for status: TaskStatus,
                       isEngineering: Bool = false,
                       projectLinked: Bool = false) -> RoadmapAction {
        switch status {
        case .codepetCanDo:  return (isEngineering && projectLinked) ? .editCode : .run
        case .needsYou:      return .walkThrough
        case .needsApproval: return .approve
        case .done:          return .openDeliverable
        case .blocked:       return .none
        }
    }

    /// True when the action's result appears in chat, so the shell should select
    /// `.chat` after dispatching it.
    static func navigatesToChat(_ action: RoadmapAction) -> Bool {
        action == .run || action == .walkThrough || action == .editCode
    }
}
