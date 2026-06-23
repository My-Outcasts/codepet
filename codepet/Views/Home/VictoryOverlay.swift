import SwiftUI

/// Full-screen victory celebration after completing a lesson/challenge.
/// Shows XP earned, particles, character celebration, and an optional badge.
struct VictoryOverlay: View {
    let xpEarned: Int
    let skillName: String
    let characterId: String
    let tierColor: Color
    let badge: String?
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showParticles = false
    @State private var showXP = false
    @State private var particleOffsets: [(x: CGFloat, y: CGFloat, rot: Double, scale: CGFloat)] = []

    private var character: PetCharacter? {
        PetCharacter.all[characterId]
    }

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(showContent ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Victory card
            VStack(spacing: 20) {
                // Celebration particles
                ZStack {
                    if showParticles {
                        ForEach(0..<12, id: \.self) { i in
                            VictoryParticle(
                                color: particleColor(for: i),
                                symbol: particleSymbol(for: i)
                            )
                            .offset(
                                x: particleOffsets.indices.contains(i) ? particleOffsets[i].x : 0,
                                y: particleOffsets.indices.contains(i) ? particleOffsets[i].y : 0
                            )
                            .rotationEffect(.degrees(particleOffsets.indices.contains(i) ? particleOffsets[i].rot : 0))
                            .scaleEffect(particleOffsets.indices.contains(i) ? particleOffsets[i].scale : 0)
                            .opacity(showParticles ? 0.8 : 0)
                        }
                    }

                    // Character celebration
                    if let char = character {
                        VStack(spacing: 6) {
                            CharacterImage(char.id, size: 80)
                                .charIdle(char.id)
                                .petBreathing()
                                .scaleEffect(showContent ? 1.0 : 0.3)

                            Text(char.name)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(char.color)
                        }
                    }
                }
                .frame(height: 120)

                // Title
                Text("Challenge Complete!")
                    .font(.pixelSystem(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))

                Text(skillName)
                    .font(.pixelSystem(size: 14))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))

                // XP reward
                if showXP {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color(hex: "#FFD700"))
                            .font(.pixelSystem(size: 18))
                        Text("+\(xpEarned) XP")
                            .font(.pixelSystem(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(tierColor)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tierColor.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(tierColor.opacity(0.3), lineWidth: 1.5)
                            )
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                // Badge (if earned)
                if let badge = badge {
                    VStack(spacing: 4) {
                        Text(badge)
                            .font(.pixelSystem(size: 32))
                        Text("Badge Earned!")
                            .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#D4960A"))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#FFF8E8"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "#D4960A").opacity(0.3), lineWidth: 1)
                            )
                    )
                }

                // Continue button
                Button(action: dismiss) {
                    Text("Continue")
                        .font(.pixelSystem(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(tierColor)
                                .shadow(color: tierColor.opacity(0.3), radius: 8, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            )
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0)
        }
        .onAppear {
            generateParticleOffsets()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                    showParticles = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showXP = true
                }
            }

            SoundManager.shared.playTap() // TODO: replace with victory sound
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }

    private func generateParticleOffsets() {
        particleOffsets = (0..<12).map { i in
            let angle = Double(i) * (360.0 / 12.0)
            let radius: CGFloat = CGFloat.random(in: 60...120)
            let x = radius * CGFloat(cos(angle * .pi / 180))
            let y = radius * CGFloat(sin(angle * .pi / 180))
            let rot = Double.random(in: -180...180)
            let scale = CGFloat.random(in: 0.6...1.2)
            return (x: x, y: y, rot: rot, scale: scale)
        }
    }

    private func particleColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "#FFD700"), Color(hex: "#FF6B6B"), Color(hex: "#6BCB77"),
            Color(hex: "#5BA8C8"), Color(hex: "#E8735A"), Color(hex: "#8B7BE8"),
            Color(hex: "#FFA500"), Color(hex: "#FF69B4"), Color(hex: "#00CED1"),
            Color(hex: "#FFD700"), Color(hex: "#FF6B6B"), Color(hex: "#6BCB77")
        ]
        return colors[index % colors.count]
    }

    private func particleSymbol(for index: Int) -> String {
        let symbols = ["✦", "★", "◆", "✧", "●", "◇", "✦", "★", "◆", "✧", "●", "◇"]
        return symbols[index % symbols.count]
    }
}

// MARK: - Victory Particle

struct VictoryParticle: View {
    let color: Color
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.pixelSystem(size: 14, weight: .bold))
            .foregroundColor(color)
    }
}
