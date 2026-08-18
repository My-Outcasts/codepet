// codepet/Models/TwoModeLayout.swift
import CoreGraphics

/// Layout rules for the two-mode shell — `rail │ conversation │ inspector`.
///
/// Pure and unit-testable on purpose: the equivalent rules in the prototype are
/// the ones that produced two real clipping bugs, and both were found by
/// asserting geometry rather than by looking at it.
///
/// Spec: `docs/superpowers/specs/2026-08-17-codepet-two-mode-product-design.md` §3.2, §5.
enum TwoModeLayout {

    /// The rail. Wide enough for `WORKSPACE` rows with a count badge, narrow
    /// enough that the conversation still owns the window.
    static let railWidth: CGFloat = 208

    /// The inspector's share of the pane when open.
    static let inspectorFraction: CGFloat = 0.47

    /// Below this the inspector collapses — the SAME threshold the docked copilot
    /// already uses (`ShellLayout.dockExpandMinWidth`), deliberately not a second
    /// rule. Two thresholds for "the window is too narrow for a side panel" would
    /// drift, and the founder would learn neither.
    static var inspectorMinWindowWidth: CGFloat { ShellLayout.dockExpandMinWidth }

    static func inspectorCollapsed(forWidth width: CGFloat) -> Bool {
        width < inspectorMinWindowWidth
    }

    /// Inspector width for a given window, floored so it never squeezes the
    /// conversation below something readable.
    static func inspectorWidth(forWidth width: CGFloat) -> CGFloat {
        let pane = max(0, width - railWidth)
        return max(320, (pane * inspectorFraction).rounded())
    }

    /// Whether the pane shows the CONVERSATION or one of the five company pages.
    ///
    /// The rule the whole system map turns on: work always surfaces in chat;
    /// pages browse and manage state. So a destination replaces the conversation
    /// only while the founder is browsing one, and `.chat` returns them.
    static func showsConversation(for view: AppView) -> Bool {
        switch view {
        case .chat, .secondBrain: return true
        case .roadmap, .company, .tasks, .library, .environment: return false
        }
    }

    /// Where the rail's `+ New` sends you: a new conversation is only meaningful
    /// on the chat surface, so creating one also navigates there.
    static let newChatDestination: AppView = .chat

    /// Whether Developer has somewhere to work. **Either door counts.**
    ///
    /// The prototype has one flag, `repoLinked`, and two ways to set it: a folder
    /// on this Mac (Local, 0 credits) or a connected repo (Cloud). The shell tested
    /// only the cloud half, so linking a folder left Developer insisting it had
    /// nowhere to work while pointed straight at a repo — and the founder had just
    /// used the button that said it would fix that.
    ///
    /// Pure, and tested, because it is the gate the whole Developer flow hangs off:
    /// get it wrong in one direction and the dormant screen is unescapable, wrong
    /// in the other and an empty session claims a tree it cannot read.
    static func developerIsAwake(projectLink: Bool, cloudRun: Bool) -> Bool {
        projectLink || cloudRun
    }
}
