import Foundation

/// What tapping a roadmap task does.
enum RoadmapAction: Equatable {
    case run              // Codepet can do it — output streams into chat
    case walkThrough      // needs the founder — the walkthrough streams into chat
    case approve          // needs approval — resolves in place
    case openDeliverable  // done — opens the deliverable sheet in place
    case none             // blocked — nothing to do yet
}

/// Pure routing rule for a roadmap task tap. Kept out of the view so the
/// "follow the action to chat" behaviour is testable on its own.
enum RoadmapDispatch {
    static func action(for status: TaskStatus) -> RoadmapAction {
        switch status {
        case .codepetCanDo:  return .run
        case .needsYou:      return .walkThrough
        case .needsApproval: return .approve
        case .done:          return .openDeliverable
        case .blocked:       return .none
        }
    }

    /// True when the action's result appears in chat, so the shell should select
    /// `.chat` after dispatching it.
    static func navigatesToChat(_ action: RoadmapAction) -> Bool {
        action == .run || action == .walkThrough
    }
}
