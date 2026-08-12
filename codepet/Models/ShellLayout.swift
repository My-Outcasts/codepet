// codepet/Models/ShellLayout.swift
import CoreGraphics

/// Pure layout decisions for the app shell. Kept out of the views so the
/// dock-collapse rule is unit-testable.
enum ShellLayout {
    /// Minimum shell width that still fits a usable half-width copilot dock beside
    /// the content. Below this the dock auto-collapses regardless of preference.
    static let dockExpandMinWidth: CGFloat = 900

    /// The dock is collapsed if the user collapsed it, or the window is too narrow.
    static func dockCollapsed(forWidth width: CGFloat, manual: Bool) -> Bool {
        manual || width < dockExpandMinWidth
    }

    /// The dock's width, full stop — it does NOT track the window.
    ///
    /// Chat is one column of text: it has an ideal measure and gains nothing past it, while
    /// the content pane — a roadmap whose header and board both want room — gains from every
    /// point. A share of the window gave chat width it could not use and made the reading
    /// column change size whenever the window did. Halving the window (with a 560pt cap) was
    /// the previous rule; going fullscreen still moved the dock 500 → 560 and re-wrapped every
    /// line of the transcript with it.
    ///
    /// 380pt is the width the founder settled on by dragging, and the value the chat's own
    /// `ChatColumn` was calibrated against. Founder call, Aug 5: resizing the window must not
    /// change the chat at all — the map takes every new point.
    ///
    /// Still a DEFAULT, not a ceiling: `AppShellView`'s drag handle overrides it for the
    /// session via `clampDockWidth`, which is also what keeps this honest on a small window
    /// (floored at `dockMinWidth`, and never so wide the content drops under `contentFloor`).
    static let dockDefaultWidth: CGFloat = 380

    static func dockWidth(forWidth width: CGFloat) -> CGFloat {
        clampDockWidth(dockDefaultWidth, windowWidth: width)
    }

    /// Minimum width the main content pane keeps when the dock is dragged wider.
    static let contentFloor: CGFloat = 420
    /// Minimum usable dock width (the chat is dock-adapted for ~360pt+).
    static let dockMinWidth: CGFloat = 360

    /// Grabbable width of the dock's resize divider. The divider itself paints 1pt; this
    /// is the invisible strip around it that takes the hover and the drag.
    ///
    /// It was 11pt (±5.5pt of aim). Measured off a screen recording on Aug 10, the pointer
    /// spent most of a resize OUTSIDE that strip, which is what made the divider stop
    /// showing the resize cursor. 16pt is ±8pt, in line with what a comparable divider on
    /// the web gives you. It buys aim only — it does NOT change the divider's layout width,
    /// which must stay fixed or the content pane shifts every time you hover.
    static let dockResizeHitWidth: CGFloat = 16

    /// Clamp a desired (e.g. drag-set) dock width so BOTH panes stay usable: never
    /// below `dockMinWidth`, never so wide the content pane drops under `contentFloor`.
    static func clampDockWidth(_ desired: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let maxDock = max(dockMinWidth, windowWidth - contentFloor)
        return min(max(dockMinWidth, desired), maxDock)
    }

    /// Whether the copilot belongs on this destination at all.
    ///
    /// Founder call (Aug 4): the copilot is an Overview surface. On Company, Tasks,
    /// Library and Environment it does not appear — neither the dock nor its collapsed
    /// button — and the content takes the full width. `.chat` and `.secondBrain` are not
    /// reachable destinations (both fall through to the Overview surface in
    /// `AppShellView.content`), so they count as Overview rather than as somewhere the
    /// copilot would vanish. Settings/Billing/Usage/Support are no longer in this list at
    /// all: they are modal sections over the current view, so whatever the copilot was
    /// doing behind the scrim it keeps doing.
    static func showsCopilot(in view: AppView) -> Bool {
        switch view {
        case .roadmap, .chat, .secondBrain: return true
        case .company, .tasks, .library, .environment: return false
        }
    }

    // MARK: - the engineering workspace

    /// What the content pane should show.
    ///
    /// `review` is NOT a nav destination and NOT a sheet. The design's §5.3 calls
    /// for "same thread, more room": Review takes over the content area beside the
    /// dock the founder is already reading, so the transcript stays where it is.
    enum ContentSurface: Equatable {
        /// The ordinary destination router — roadmap, company, tasks, and so on.
        case destination(AppView)
        /// The engineering Review pane, for this run.
        case engineeringReview(runId: String)
    }

    /// Which surface to render, given the current destination and whether a run is
    /// under review.
    ///
    /// The destination is passed through UNCHANGED while reviewing, which is the
    /// whole mechanism behind "leaving review restores where you were": nothing was
    /// ever navigated away from, so there is nothing to restore. A `view` case
    /// would have had to remember and put back the previous destination, and that
    /// is exactly the kind of state that goes wrong when a founder collapses the
    /// dock or switches threads mid-review.
    static func contentSurface(destination: AppView, reviewingRunId: String?) -> ContentSurface {
        // Review only exists beside the dock. On a destination with no copilot
        // there is no transcript to sit next to, so the pane would be a
        // full-window diff viewer nobody asked for — and a founder who navigated
        // to Library mid-run would find their map replaced by a diff.
        guard let runId = reviewingRunId, !runId.isEmpty, showsCopilot(in: destination) else {
            return .destination(destination)
        }
        return .engineeringReview(runId: runId)
    }

    /// Content-pane width below which a page header must abbreviate its controls —
    /// the "How to read this map" button drops to its bare "?" — so the title and the
    /// controls still share ONE row. Above it everything shows its full label.
    static let compactHeaderMaxWidth: CGFloat = 620

    /// Whether a page header at `width` must run its controls in compact form.
    /// `width == 0` means "not measured yet"; report roomy so the header doesn't
    /// flash abbreviated on first layout.
    static func compactPageHeader(forWidth width: CGFloat) -> Bool {
        width > 0 && width < compactHeaderMaxWidth
    }

    // MARK: - Settings modal

    /// Fixed width of the settings rail. It carries its own "Settings" title and never
    /// scrolls, so the founder can always see where they are.
    static let settingsRailWidth: CGFloat = 220

    /// Below this shell width the rail collapses to a section dropdown above the panel —
    /// the same responsive move the dock makes at `dockExpandMinWidth`.
    static let settingsRailMinWidth: CGFloat = 820

    static func settingsRailCollapsed(forWidth width: CGFloat) -> Bool {
        width < settingsRailMinWidth
    }

    /// The centered panel's size: inset 96pt from each window edge, capped at the ideal
    /// so a fullscreen window does not turn settings into a full-screen sheet, and
    /// floored so a tiny window still shows a usable form.
    static func settingsPanelSize(forWidth w: CGFloat, height h: CGFloat) -> CGSize {
        CGSize(width:  min(920, max(480, w - 96)),
               height: min(660, max(400, h - 96)))
    }
}
