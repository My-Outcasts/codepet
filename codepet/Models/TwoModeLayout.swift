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

    /// The rail's DEFAULT width. Wide enough for workspace rows with a count badge,
    /// narrow enough that the conversation still owns the window.
    static let railWidth: CGFloat = 208

    /// Narrowest the rail may be dragged. Below this the mode switch's two segments
    /// cannot both hold their label — "DEVELOPER" at subheadline with tracking is
    /// ~70pt on its own — and a switch whose labels truncate is a switch you have to
    /// guess at.
    static let railMinWidth: CGFloat = 180

    /// Widest. Past this the rail stops being a rail and starts competing with the
    /// conversation for the window, which is the thing `railWidth`'s comment has
    /// always been about.
    static let railMaxWidth: CGFloat = 340

    /// The conversation's floor: whatever the rail does, the pane keeps enough width
    /// to hold the reading measure plus its margins.
    static let paneFloor: CGFloat = 520

    /// Clamped against BOTH the rail's own bounds and the window's, so a founder who
    /// drags hard on a narrow window cannot squeeze the conversation to nothing —
    /// same shape as `ShellLayout.clampDockWidth`.
    static func clampRailWidth(_ desired: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let ceiling = min(railMaxWidth, max(railMinWidth, windowWidth - paneFloor))
        return min(max(railMinWidth, desired), ceiling)
    }

    /// The divider's grab area. The visible line is 1pt; 16 is what makes it
    /// catchable — reused from the dock rather than re-picked, because two different
    /// hit widths for the same gesture is a difference nobody can learn.
    static var railResizeHitWidth: CGFloat { ShellLayout.dockResizeHitWidth }

    /// `cp_`-prefixed per the project's UserDefaults convention.
    static let railWidthKey = "cp_twoModeRailWidth"
    static let railCollapsedKey = "cp_twoModeRailCollapsed"

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

    /// Where this shell opens.
    ///
    /// `CompanyStore.view` starts at `.roadmap` and `AppView.home` is `.roadmap` — a
    /// founder call from 6 Aug, made for the TOP-NAV shell, where chat was a dock
    /// visible alongside whatever page you were on. Landing on Roadmap there cost
    /// nothing, because the conversation was still on screen.
    ///
    /// Here it is not: chat is the pane. Opening on Roadmap means opening a product
    /// whose thesis is "a chat with two destinations" into a destination, with the
    /// chat nowhere in sight. And because `onChange(of: mode)` redirects to `.chat`
    /// whenever the current view is not a conversation, the FIRST mode toggle
    /// silently moved you there anyway — so the real behaviour was "Roadmap until
    /// you touch the switch, then chat for the rest of the session", which is not a
    /// design, it is a leak.
    ///
    /// The wordmark still goes to `AppView.home`, so Roadmap keeps the thing the
    /// Aug 6 call actually gave it.
    static let launchDestination: AppView = .chat

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
