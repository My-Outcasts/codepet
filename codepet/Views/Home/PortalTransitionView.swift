import SwiftUI

/// Full-screen portal transition when entering a kingdom.
/// Multi-phase: rings expand → flash → kingdom name → fade into interior.
struct PortalTransitionView: View {
    let tier: SkillTier
    let onComplete: () -> Void

    @State private var phase: Int = 0 // 0→1→2→3→done

    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            // Portal rings
            ForEach(0..<4, id: \.self) { ring in
                Circle()
                    .stroke(tier.kingdomColor, lineWidth: 3)
                    .frame(
                        width: phase >= ring ? CGFloat(200 + ring * 60) : 0,
                        height: phase >= ring ? CGFloat(200 + ring * 60) : 0
                    )
                    .opacity(phase >= ring ? 0.6 - Double(ring) * 0.12 : 0)
                    .rotationEffect(.degrees(phase >= ring ? Double(ring) * 45 : 0))
                    .animation(
                        .easeOut(duration: 0.5).delay(Double(ring) * 0.15),
                        value: phase
                    )
            }

            // Center glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tier.kingdomColor.opacity(0.5), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: phase >= 2 ? 300 : 5
                    )
                )
                .frame(width: 600, height: 600)
                .animation(.easeOut(duration: 0.6), value: phase)

            // Pixel particles
            if phase >= 1 {
                ForEach(0..<16, id: \.self) { i in
                    let angle = Double(i) * (360.0 / 16.0)
                    let radius: CGFloat = CGFloat(80 + phase * 40)
                    let x = radius * CGFloat(cos(angle * .pi / 180))
                    let y = radius * CGFloat(sin(angle * .pi / 180))

                    Rectangle()
                        .fill(tier.kingdomColor)
                        .frame(width: 4, height: 4)
                        .offset(x: x, y: y)
                        .opacity(phase >= 3 ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 0.4).delay(Double(i) * 0.03),
                            value: phase
                        )
                }
            }

            // Kingdom name & emoji (appears in phase 2)
            VStack(spacing: 12) {
                // Kingdom scene mini
                KingdomScene(tierId: tier.id)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(tier.kingdomColor.opacity(0.5), lineWidth: 2))

                Text(tier.kingdom)
                    .font(.pixelSystem(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: tier.kingdomColor.opacity(0.8), radius: 12)

                Text("Entering world...")
                    .font(.pixelSystem(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(phase >= 2 ? 1 : 0)
            .scaleEffect(phase >= 2 ? 1 : 0.5)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: phase)
        }
        .onAppear {
            // Phase sequence matching the prototype timing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                phase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                phase = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                phase = 3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }
}
