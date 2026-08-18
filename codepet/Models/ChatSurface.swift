// codepet/Models/ChatSurface.swift
import SwiftUI

/// Which shell the chat is rendering inside.
///
/// `CopilotChatView` was written for the 380pt dock in `AppShellView`, and the
/// two-mode shell hands it the whole pane instead. Three pieces of its chrome are
/// only true in the dock — the collapse button (there is no dock to collapse), the
/// history icon (the rail's Recent list is the thread switcher), and the composer's
/// mode pill (`.plan`/`.build` retire; the mode is a place now) — so the surface,
/// not the view, decides whether they exist.
///
/// The default is `.dock`, which is what makes this additive: `AppShellView` reads
/// the default and renders exactly what it rendered before.
enum ChatSurface {
    /// The docked copilot column in `AppShellView` — main's shipping shell.
    case dock
    /// The full pane in `TwoModeShellView`, laid out to the prototype.
    case twoMode

    /// Only the dock has a dock to collapse and an icon row above the thread.
    var showsDockChrome: Bool { self == .dock }

    /// The mode pill dies with `ChatMode`. Ask and Developer are places in the rail.
    var showsModePill: Bool { self == .dock }

    /// The dock is 380pt wide and fits two chips + overflow; the pane fits the
    /// prototype's three.
    var visibleDeptChips: Int { self == .dock ? 2 : 3 }
}

private struct ChatSurfaceKey: EnvironmentKey {
    static let defaultValue: ChatSurface = .dock
}

extension EnvironmentValues {
    var chatSurface: ChatSurface {
        get { self[ChatSurfaceKey.self] }
        set { self[ChatSurfaceKey.self] = newValue }
    }
}
