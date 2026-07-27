import SwiftUI

/// The chat surface's ambient purple radial wash — one shared, inert decoration
/// placed behind BOTH the empty hero and the active conversation so the two read
/// as one continuous surface. Suppressed under Reduce Transparency. Extracted from
/// `ChatEmptyState.brandWash` so the empty and active states share one definition.
struct ChatBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !reduceTransparency {
                RadialGradient(
                    gradient: Gradient(colors: [CodepetTheme.accentPurple.opacity(0.16), .clear]),
                    center: .center, startRadius: 0, endRadius: 420)
                .blur(radius: 60)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
