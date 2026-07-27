import Foundation

/// A capability quick-action: a localized title (also the message sent) + an
/// SF Symbol shown on the pill and in the composer's `+` menu.
struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}
