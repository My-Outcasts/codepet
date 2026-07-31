import Foundation

/// A capability quick-action: a localized title (also the message sent) + an
/// SF Symbol shown on the card/pill and in the composer's `+` menu, plus a
/// short localized helper description shown on the card. The detail is plain
/// display text — it is not separately selectable; the whole card is the tap target.
struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let detail: String
}
