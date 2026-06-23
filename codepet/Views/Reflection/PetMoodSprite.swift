import SwiftUI

/// Pet mood enum — maps to Claude's `mood` field in the narrative.
enum NarrativeMood: String, CaseIterable {
    case idle
    case excited
    case thinking
    case proud
    case concerned
    case cheering

    init(raw: String) {
        self = NarrativeMood(rawValue: raw) ?? .idle
    }

    /// System image shown as a small badge/indicator near the sprite.
    var badgeIcon: String {
        switch self {
        case .idle:      return "sparkle"
        case .excited:   return "star.fill"
        case .thinking:  return "bubble.left.fill"
        case .proud:     return "trophy.fill"
        case .concerned: return "exclamationmark.triangle.fill"
        case .cheering:  return "heart.fill"
        }
    }

    /// Accent color for the mood badge — uses brand palette for consistency
    /// with ReflectionTheme.moodAccentColor(for:).
    var badgeColor: Color {
        switch self {
        case .idle:      return ReflectionTheme.brandPurple
        case .excited:   return ReflectionTheme.brandOrange
        case .thinking:  return ReflectionTheme.brandBlue
        case .proud:     return ReflectionTheme.brandGreen
        case .concerned: return ReflectionTheme.brandPink
        case .cheering:  return ReflectionTheme.brandYellow
        }
    }
}

/// Animated pet sprite that reacts to the narrative mood.
/// Displayed next to (or within) narrative cards.
struct PetMoodSprite: View {
    let characterId: String
    let mood: NarrativeMood
    let size: CGFloat

    // Animation state
    @State private var phase: CGFloat = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var glowOpacity: CGFloat = 0
    @State private var particlesVisible = false
    @State private var badgeScale: CGFloat = 0

    private var pet: PetCharacter? {
        PetCharacter.all[characterId]
    }

    private var petColor: Color {
        pet?.color ?? .purple
    }

    private var containerSize: CGFloat { size * 1.15 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Circle container — sprite + particles clipped inside.
            // compositingGroup() flattens animated transforms (offset, scale,
            // rotation) into a single render buffer BEFORE clipShape, so the
            // clip reliably catches geometry that escapes the frame.
            ZStack {
                Circle()
                    .fill(petColor.opacity(0.18))

                // Particle effects (clipped inside circle)
                if particlesVisible {
                    particleLayer
                }

                // Main sprite — nudged down slightly to visually center
                // within the circle (ears make the top heavy)
                spriteImage
                    .offset(y: 3 + bounceOffset)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: containerSize, height: containerSize)
            .compositingGroup()
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(petColor.opacity(0.35 + glowOpacity * 0.15), lineWidth: 2)
            )

            // Mood badge — bottom-right corner, overlapping the circle edge
            moodBadge
                .offset(x: containerSize * 0.04, y: containerSize * 0.04)
                .scaleEffect(badgeScale)
        }
        .frame(width: containerSize, height: containerSize)
        .onAppear { startMoodAnimation() }
        .onChange(of: mood) { _, _ in startMoodAnimation() }
    }

    // MARK: - Sprite Image

    /// Sprite at 70% of container — enough breathing room around the character
    /// so ears don't touch the circle edge and animations stay inside.
    private var spriteImage: some View {
        Group {
            if let pet = pet {
                Image(pet.imageName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: containerSize * 0.70, height: containerSize * 0.70)
            } else {
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: containerSize * 0.70, height: containerSize * 0.70)
            }
        }
    }

    // MARK: - Mood Badge

    /// Whether this mood's badge color is too light for white icon (yellow).
    private var badgeNeedsDarkIcon: Bool {
        mood == .cheering
    }

    private var moodBadge: some View {
        ZStack {
            Circle()
                .fill(mood.badgeColor)
                .frame(width: containerSize * 0.36, height: containerSize * 0.36)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: mood.badgeColor.opacity(0.5), radius: 4, y: 1)

            Image(systemName: mood.badgeIcon)
                .font(.system(size: containerSize * 0.16, weight: .bold))
                .foregroundColor(badgeNeedsDarkIcon ? Color(hex: "#412402") : .white)
        }
    }

    // MARK: - Particles

    @ViewBuilder
    private var particleLayer: some View {
        switch mood {
        case .excited:
            excitedParticles
        case .proud:
            proudParticles
        case .cheering:
            cheeringParticles
        case .concerned:
            concernedParticles
        case .thinking:
            thinkingParticles
        case .idle:
            EmptyView()
        }
    }

    private var excitedParticles: some View {
        let radius: Double = Double(containerSize * 0.35)
        let phaseD: Double = Double(phase)
        return ForEach(0..<5, id: \.self) { i in
            let angle: Double = Double(i) * .pi * 2.0 / 5.0 + phaseD * 2.0
            Text("✨")
                .font(.system(size: size * 0.15))
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                .opacity(1.0 - phaseD * 0.5)
                .scaleEffect(0.5 + phase * 0.5)
        }
    }

    private var proudParticles: some View {
        let colors: [Color] = [.yellow, .green, .purple, .orange, .pink, .blue]
        let dist: Double = Double(containerSize * 0.3 + phase * containerSize * 0.15)
        return ForEach(0..<6, id: \.self) { i in
            let angle: Double = Double(i) * .pi * 2.0 / 6.0
            Circle()
                .fill(colors[i % colors.count])
                .frame(width: 3, height: 3)
                .offset(x: cos(angle) * dist, y: sin(angle) * dist)
                .opacity(1.0 - Double(phase) * 0.7)
        }
    }

    private var cheeringParticles: some View {
        let offsets: [CGFloat] = [-8, 5, -4, 10]
        return ForEach(0..<4, id: \.self) { i in
            let yOff: CGFloat = -phase * containerSize * 0.3 - CGFloat(i * 4)
            Text("💕")
                .font(.system(size: size * 0.12))
                .offset(x: offsets[i], y: yOff)
                .opacity(1.0 - Double(phase) * 0.6)
        }
    }

    private var concernedParticles: some View {
        let yOff: CGFloat = -containerSize * 0.05 + phase * containerSize * 0.2
        let opacity: Double = Double(phase) < 0.7 ? 1.0 : max(0, 1.0 - (Double(phase) - 0.7) * 3.0)
        return Text("💧")
            .font(.system(size: size * 0.15))
            .offset(x: containerSize * 0.2, y: yOff)
            .opacity(opacity)
    }

    private var thinkingParticles: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let threshold: CGFloat = CGFloat(i) * 0.3
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .scaleEffect(phase > threshold ? 1.2 : 0.6)
            }
        }
        .offset(x: containerSize * 0.25, y: -containerSize * 0.15)
    }

    // MARK: - Animations

    private func startMoodAnimation() {
        // Reset
        phase = 0
        bounceOffset = 0
        rotation = 0
        scale = 1.0
        glowOpacity = 0
        particlesVisible = false
        badgeScale = 0

        // Badge entrance
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3)) {
            badgeScale = 1.0
        }

        switch mood {
        case .idle:
            // Gentle float
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                bounceOffset = -4
                glowOpacity = 0.5
            }

        case .excited:
            // Happy bounce + sparkles
            particlesVisible = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.4).repeatCount(3, autoreverses: true)) {
                bounceOffset = -6
                scale = 1.06
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                phase = 1.0
                glowOpacity = 0.8
            }

        case .thinking:
            // Slow head tilt + thought dots
            particlesVisible = true
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                rotation = 8
                bounceOffset = -2
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                phase = 1.0
            }

        case .proud:
            // Chest puff + confetti
            particlesVisible = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.08
                glowOpacity = 1.0
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                scale = 1.03
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }

        case .concerned:
            // Slight shrink + sweat
            particlesVisible = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scale = 0.92
                bounceOffset = 2
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = 1.0
            }

        case .cheering:
            // Jump + wave + hearts
            particlesVisible = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.35).repeatCount(4, autoreverses: true)) {
                bounceOffset = -6
                rotation = -3
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
                phase = 1.0
                glowOpacity = 0.6
            }
        }
    }
}
