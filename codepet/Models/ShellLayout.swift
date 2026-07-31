// codepet/Models/ShellLayout.swift
import CoreGraphics

/// Pure layout decisions for the app shell. Kept out of the views so the
/// dock-collapse rule is unit-testable.
enum ShellLayout {
    /// Minimum shell width that still fits the 380pt copilot dock beside a 520pt
    /// content floor. Below this the dock auto-collapses regardless of preference.
    static let dockExpandMinWidth: CGFloat = 900

    /// The dock is collapsed if the user collapsed it, or the window is too narrow.
    static func dockCollapsed(forWidth width: CGFloat, manual: Bool) -> Bool {
        manual || width < dockExpandMinWidth
    }
}
