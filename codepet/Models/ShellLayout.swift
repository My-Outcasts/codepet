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

    /// Expanded copilot width: half the window, so chat and the main content split
    /// the shell 50/50. Floored at 360pt so the dock-adapted chat stays usable even
    /// at the `dockExpandMinWidth` boundary; the content area takes the remainder.
    static func dockWidth(forWidth width: CGFloat) -> CGFloat {
        clampDockWidth((width * 0.5).rounded(), windowWidth: width)
    }

    /// Minimum width the main content pane keeps when the dock is dragged wider.
    static let contentFloor: CGFloat = 420
    /// Minimum usable dock width (the chat is dock-adapted for ~360pt+).
    static let dockMinWidth: CGFloat = 360

    /// Clamp a desired (e.g. drag-set) dock width so BOTH panes stay usable: never
    /// below `dockMinWidth`, never so wide the content pane drops under `contentFloor`.
    static func clampDockWidth(_ desired: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let maxDock = max(dockMinWidth, windowWidth - contentFloor)
        return min(max(dockMinWidth, desired), maxDock)
    }
}
