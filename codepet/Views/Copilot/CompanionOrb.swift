import SwiftUI

/// A luminous gradient sphere — the companion's identity in chat (hero focal
/// element, message avatar, thinking indicator). Pure SwiftUI, no assets.
struct CompanionOrb: View {
    var size: CGFloat = 78
    var glow: Bool = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Circle()
            .fill(AngularGradient(
                gradient: Gradient(colors: [
                    CodepetTheme.accentPurple, CodepetTheme.accentPink,
                    CodepetTheme.accentBlue, CodepetTheme.accentTeal,
                    CodepetTheme.accentPurple]),
                center: .center))
            .overlay(                     // glossy top-left highlight
                Circle().fill(RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.85), .clear]),
                    center: UnitPoint(x: 0.33, y: 0.28),
                    startRadius: 0, endRadius: size * 0.30)))
            .overlay(                     // bottom-right sphere shading for depth
                Circle().fill(RadialGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.35)]),
                    center: UnitPoint(x: 0.72, y: 0.78),
                    startRadius: size * 0.18, endRadius: size * 0.62)))
            .frame(width: size, height: size)
            .shadow(color: (glow && !reduceTransparency)
                    ? CodepetTheme.accentPurple.opacity(0.45) : .clear,
                    radius: size * 0.45)
    }
}

#if DEBUG
#Preview("CompanionOrb") {
    HStack(spacing: 24) {
        CompanionOrb(size: 78)
        CompanionOrb(size: 28, glow: false)
    }
    .padding(40)
    .background(Color.black)
}
#endif
