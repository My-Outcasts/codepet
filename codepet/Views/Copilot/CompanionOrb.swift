import SwiftUI

/// A luminous, companion-tinted sphere — the companion's identity in chat
/// (hero focal, message avatar, thinking indicator). Reads the active companion's
/// two hues from the store so switching companion re-tints every orb. Pure
/// SwiftUI, no assets. Only `isWorking` changes scale (a slow breathe); at rest
/// the internal colour drifts. Reduce Motion → one static frame.
struct CompanionOrb: View {
    var size: CGFloat = 78
    var glow: Bool = true
    var isWorking: Bool = false

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var character: PetCharacter? { PetCharacter.all[companyStore.company.companionId] }
    private var hue1: Color { character?.color ?? CodepetTheme.accentPurple }
    private var hue2: Color { character?.secondColor ?? CodepetTheme.accentPink }

    var body: some View {
        Group {
            if reduceMotion {
                orb(t: 0)
            } else {
                TimelineView(.animation) { tl in
                    orb(t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func breathe(_ t: Double) -> CGFloat {
        guard isWorking && !reduceMotion else { return 1.0 }
        // 3.6s period, scale 1.0 … 1.07
        return 1.0 + 0.035 * (1 + CGFloat(sin(t * (2 * .pi / 3.6))))
    }

    private func orb(t: Double) -> some View {
        ZStack {
            // 1. near-black luminous core — makes colour read as emitted light
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [CodepetTheme.chatOrbCore, .black]),
                center: .center, startRadius: 0, endRadius: size * 0.5))

            // 2. three internal colour bands, drifting on different periods, additive
            band(hue1, degPerSec: 30, t: t)
            band(hue2, degPerSec: 42, t: t)
            band(.white.opacity(0.5), degPerSec: 22, t: t)   // hue1 "lifted toward white"

            // 3. specular crescent
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [.white.opacity(0.9), .clear]),
                center: UnitPoint(x: 0.34 + 0.015 * sin(t * 0.6), y: 0.30),
                startRadius: 0, endRadius: size * 0.30))

            // 4. base shading for sphericality
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.40)]),
                center: UnitPoint(x: 0.70, y: 0.80),
                startRadius: size * 0.15, endRadius: size * 0.60))

            // 5. rim, brightest near the specular
            Circle().strokeBorder(
                AngularGradient(gradient: Gradient(colors: [
                    .white.opacity(0.55), .clear, .clear, .white.opacity(0.2), .white.opacity(0.55)]),
                    center: .center),
                lineWidth: max(1, size * 0.02))
        }
        .compositingGroup()
        .clipShape(Circle())
        .scaleEffect(breathe(t))
        .background(bloom)   // 6. outer bloom, behind and unclipped
    }

    private func band(_ color: Color, degPerSec: Double, t: Double) -> some View {
        AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.0), color.opacity(0.6), color.opacity(0.0)]),
            center: .center,
            angle: .degrees(reduceMotion ? 0 : t * degPerSec))
        .clipShape(Circle())
        .blendMode(.plusLighter)
    }

    private var bloom: some View {
        Circle()
            .fill(hue1.opacity((glow && !reduceTransparency) ? 0.45 : 0.0))
            .blur(radius: size * 0.45)
            .scaleEffect(1.12)
    }
}

#if DEBUG
#Preview("CompanionOrb") {
    HStack(spacing: 24) {
        CompanionOrb(size: 78, isWorking: true)
        CompanionOrb(size: 28, glow: false)
    }
    .padding(40)
    .background(Color.black)
    .environmentObject(CompanyStore())
}
#endif
