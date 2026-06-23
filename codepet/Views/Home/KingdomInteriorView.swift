import SwiftUI

/// Kingdom Interior View — opens when tapping a kingdom on the World Map.
/// Shows a vertical challenge path with nodes, the player's character, and
/// kingdom-themed scenery. Keeps the existing card-based design language.
struct KingdomInteriorView: View {
    let tier: SkillTier
    let onClose: () -> Void
    let onStartLesson: (Skill) -> Void

    @EnvironmentObject var appState: AppState

    // Character position tracks which node index the character is at
    @State private var characterNodeIndex: Int = 0
    @State private var isCharacterWalking: Bool = false
    @State private var characterCelebrating: Bool = false
    @State private var previousCompletedCount: Int = 0

    private var completedCount: Int {
        tier.skills.filter { appState.completedLessons.contains($0.id) }.count
    }

    private var nextSkillIndex: Int? {
        tier.skills.firstIndex { !appState.completedLessons.contains($0.id) }
    }

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        ZStack {
            // Kingdom-themed background
            kingdomBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                // Scrollable challenge path
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Kingdom banner
                            kingdomBanner
                                .padding(.bottom, 24)

                            // Challenge path
                            challengePath

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }
                    .onAppear {
                        previousCompletedCount = completedCount
                        // Set character to current node
                        if let idx = nextSkillIndex {
                            characterNodeIndex = idx
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("node-\(idx)", anchor: .center)
                            }
                        } else {
                            characterNodeIndex = tier.skills.count - 1
                        }
                    }
                    // Detect lesson completion → celebrate then walk to next node
                    .onChange(of: completedCount) {
                        if completedCount > previousCompletedCount {
                            previousCompletedCount = completedCount

                            // 1. Celebrate at current position
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                                characterCelebrating = true
                            }

                            // 2. After celebration, walk to next node
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    characterCelebrating = false
                                    isCharacterWalking = true
                                }

                                if let idx = nextSkillIndex {
                                    withAnimation(.easeInOut(duration: 0.6)) {
                                        characterNodeIndex = idx
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            isCharacterWalking = false
                                            proxy.scrollTo("node-\(idx)", anchor: .center)
                                        }
                                    }
                                } else {
                                    // All done — stay at last node
                                    withAnimation(.easeInOut(duration: 0.6)) {
                                        characterNodeIndex = tier.skills.count - 1
                                        isCharacterWalking = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: {
                SoundManager.shared.playTap()
                onClose()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.pixelSystem(size: 14, weight: .bold))
                    Text("World Map")
                        .font(.pixelSystem(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Progress pill
            HStack(spacing: 6) {
                Text("\(completedCount)/\(tier.skills.count)")
                    .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Image(systemName: "star.fill")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#FFD700"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.25))
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Kingdom Banner

    private var kingdomBanner: some View {
        VStack(spacing: 0) {
            // Kingdom scene — full aspect ratio with bottom fade
            ZStack(alignment: .bottom) {
                KingdomScene(tierId: tier.id)
                    .aspectRatio(1280.0 / 800.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Bottom fade to blend into background
                LinearGradient(
                    colors: [.clear, .clear, kingdomFadeColor.opacity(0.6), kingdomFadeColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20
                    )
                )

                // Title overlay on the fade
                VStack(spacing: 4) {
                    Text(tier.kingdom)
                        .font(.pixelSystem(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                    Text("Tier \(tier.id) · \(tier.name)")
                        .font(.pixelSystem(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .padding(.bottom, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
    }

    /// Color used for the bottom fade on the kingdom banner
    private var kingdomFadeColor: Color {
        switch tier.id {
        case 1: return Color(hex: "#4A2020")
        case 2: return Color(hex: "#1A3A5C")
        case 3: return Color(hex: "#4A2050")
        case 4: return Color(hex: "#2A4020")
        default: return Color(hex: "#2D2B26")
        }
    }

    // MARK: - Challenge Path

    private var challengePath: some View {
        VStack(spacing: 0) {
            ForEach(Array(tier.skills.enumerated()), id: \.element.id) { index, skill in
                let isCompleted = appState.completedLessons.contains(skill.id)
                let isNext = index == nextSkillIndex
                let isLocked = !isCompleted && !isNext

                VStack(spacing: 0) {
                    // Connector line above (not for first node)
                    if index > 0 {
                        PathConnector(
                            isCompleted: appState.completedLessons.contains(tier.skills[index - 1].id),
                            tierColor: tier.kingdomColor
                        )
                    }

                    // The node
                    ZStack {
                        ChallengeNodeView(
                            skill: skill,
                            index: index + 1,
                            isCompleted: isCompleted,
                            isNext: isNext,
                            isLocked: isLocked,
                            tierColor: tier.kingdomColor,
                            teacher: LessonLibrary.all[skill.id]?.teacher,
                            onStart: { onStartLesson(skill) }
                        )

                        // Character at the active node — large, animated, interactive
                        if index == characterNodeIndex {
                            KingdomCharacterView(
                                characterId: character.id,
                                tierColor: tier.kingdomColor,
                                isCelebrating: characterCelebrating,
                                isWalking: isCharacterWalking,
                                side: index.isMultiple(of: 2) ? .left : .right
                            )
                        }
                    }
                    .id("node-\(index)")
                }
            }

            // Final gate / completion
            if completedCount == tier.skills.count {
                kingdomComplete
                    .padding(.top, 16)
            } else {
                // Teaser for what's ahead
                PathConnector(isCompleted: false, tierColor: tier.kingdomColor)
                lockedGate
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Kingdom Complete Badge

    private var kingdomComplete: some View {
        VStack(spacing: 8) {
            PathConnector(isCompleted: true, tierColor: tier.kingdomColor)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#FFD700"), Color(hex: "#FFA500")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(hex: "#FFD700").opacity(0.4), radius: 8, y: 2)

                Image(systemName: "crown.fill")
                    .font(.pixelSystem(size: 22))
                    .foregroundColor(.white)
            }

            Text("Kingdom Mastered!")
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(.white)

            Text("+50 XP Bonus")
                .font(.pixelSystem(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "#FFD700"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.2))
                )
        }
    }

    // MARK: - Locked Gate (next kingdom teaser)

    private var lockedGate: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                    )

                Image(systemName: "lock.fill")
                    .font(.pixelSystem(size: 16))
                    .foregroundColor(.white.opacity(0.4))
            }

            Text("Complete all challenges\nto master this kingdom")
                .font(.pixelSystem(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var kingdomBackground: some View {
        switch tier.id {
        case 1:
            LinearGradient(
                colors: [Color(hex: "#4A2020"), Color(hex: "#6A3830"), Color(hex: "#3D2020")],
                startPoint: .top, endPoint: .bottom
            )
        case 2:
            LinearGradient(
                colors: [Color(hex: "#1A3A5C"), Color(hex: "#2A5A7C"), Color(hex: "#1A3050")],
                startPoint: .top, endPoint: .bottom
            )
        case 3:
            LinearGradient(
                colors: [Color(hex: "#4A2050"), Color(hex: "#6A3870"), Color(hex: "#3D1845")],
                startPoint: .top, endPoint: .bottom
            )
        case 4:
            LinearGradient(
                colors: [Color(hex: "#2A4020"), Color(hex: "#3A5830"), Color(hex: "#1E3018")],
                startPoint: .top, endPoint: .bottom
            )
        default:
            Color(hex: "#2D2B26")
        }
    }
}

// MARK: - Kingdom Character View (large, animated, interactive)

struct KingdomCharacterView: View {
    let characterId: String
    let tierColor: Color
    let isCelebrating: Bool
    let isWalking: Bool
    let side: HorizontalAlignment

    enum HorizontalAlignment { case left, right }

    @State private var bouncePhase: Bool = false
    @State private var sparkleVisible: Bool = false

    private var xOffset: CGFloat { side == .left ? -110 : 110 }

    var body: some View {
        VStack(spacing: 0) {
            // Speech bubble (shows during celebration)
            if isCelebrating {
                Text(celebrationEmoji)
                    .font(.pixelSystem(size: 22))
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    )
                    .transition(.scale.combined(with: .opacity))
                    .offset(y: -4)
            }

            ZStack {
                // Glow platform under character
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [tierColor.opacity(0.4), tierColor.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 70, height: 20)
                    .offset(y: 28)
                    .scaleEffect(isCelebrating ? 1.3 : 1.0)

                // Celebration sparkles
                if isCelebrating {
                    ForEach(0..<6, id: \.self) { i in
                        let angle = Double(i) * 60.0
                        let rad = angle * .pi / 180
                        Circle()
                            .fill(i % 2 == 0 ? Color(hex: "#FFD700") : tierColor)
                            .frame(width: 5, height: 5)
                            .offset(
                                x: CGFloat(cos(rad)) * (sparkleVisible ? 28 : 8),
                                y: CGFloat(sin(rad)) * (sparkleVisible ? 28 : 8) - 10
                            )
                            .opacity(sparkleVisible ? 0 : 1)
                            .scaleEffect(sparkleVisible ? 0.3 : 1.0)
                    }
                }

                // Character (large!)
                CharacterImage(characterId, size: 64)
                    .charIdle(characterId)
                    .scaleEffect(x: side == .left ? 1 : -1, y: 1)
                    .scaleEffect(isCelebrating ? 1.15 : (isWalking ? 1.05 : 1.0))
                    .offset(y: isCelebrating ? -12 : (bouncePhase ? -2 : 0))
                    .rotationEffect(isWalking ? .degrees(side == .left ? -3 : 3) : .degrees(0))
            }
        }
        .offset(x: xOffset, y: -8)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isCelebrating)
        .animation(.easeInOut(duration: 0.5), value: isWalking)
        .onAppear {
            // Gentle idle bounce
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                bouncePhase = true
            }
        }
        .onChange(of: isCelebrating) {
            if isCelebrating {
                // Sparkle burst animation
                withAnimation(.easeOut(duration: 0.8)) {
                    sparkleVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    sparkleVisible = false
                }
            }
        }
    }

    private var celebrationEmoji: String {
        ["🎉", "⭐️", "🔥", "💪", "✨", "🏆"].randomElement()!
    }
}

// MARK: - Path Connector

struct PathConnector: View {
    let isCompleted: Bool
    let tierColor: Color

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(isCompleted ? tierColor : Color.white.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 28)
    }
}
