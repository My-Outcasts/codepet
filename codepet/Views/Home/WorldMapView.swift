import SwiftUI

// MARK: - World Map Section (for HomeView)

struct WorldMapSection: View {
    @EnvironmentObject var appState: AppState
    var onSelectKingdom: ((SkillTier) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("World Map")
                    .font(.pixelSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))

                Spacer()

                Text("Tier \(appState.currentTier)")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                    )
            }

            // Home Base
            HomeBaseCard()

            // 2x2 Kingdom Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(GameData.skillTiers) { tier in
                    KingdomMapCard(tier: tier, onTap: {
                        if tier.id <= appState.currentTier {
                            SoundManager.shared.playTap()
                            onSelectKingdom?(tier)
                        }
                    })
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Home Base Card

struct HomeBaseCard: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // Pixel art home scene
            Image("kingdom-home-base")
                .resizable()
                .interpolation(.none)
                .aspectRatio(1280.0 / 800.0, contentMode: .fill)
                .frame(height: 130)
                .clipped()

            // Bottom fade
            LinearGradient(
                colors: [.clear, Color(hex: "#2D2B26").opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 50)

            // HOME label
            Text("HOME")
                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.35))
                .cornerRadius(4)
                .padding(.bottom, 10)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Kingdom Map Card

struct KingdomMapCard: View {
    let tier: SkillTier
    var onTap: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    private var isLocked: Bool { tier.id > appState.currentTier }
    private var isMastered: Bool {
        tier.skills.allSatisfy { appState.completedLessons.contains($0.id) }
    }
    private var isActive: Bool { !isLocked && !isMastered && tier.id == appState.currentTier }
    private var completedCount: Int {
        tier.skills.filter { appState.completedLessons.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                KingdomScene(tierId: tier.id)
                    .frame(height: 100)

                if isLocked {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.15))
                        .frame(height: 100)
                    Image(systemName: "lock.fill")
                        .font(.pixelSystem(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(tier.kingdom)
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(isLocked ? Color(hex: "#2D2B26").opacity(0.3) : tier.kingdomColor)

            Text("\(tier.name) · Tier \(tier.id)")
                .font(.pixelSystem(size: 9))
                .foregroundColor(Color(hex: "#999999"))

            Text("\(completedCount)/\(tier.skills.count)")
                .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isMastered ? Color(hex: "#D4960A") : Color(hex: "#999999"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#FAFAF7"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isActive ? tier.kingdomColor.opacity(0.4) :
                                isMastered ? Color(hex: "#D4960A").opacity(0.4) : Color.clear,
                            lineWidth: isActive || isMastered ? 2 : 0
                        )
                )
        )
        .saturation(isLocked ? 0.3 : 1.0)
        .opacity(isLocked ? 0.6 : 1.0)
        .scaleEffect(isHovered && !isLocked ? 1.03 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Kingdom Scene Illustrations

struct KingdomScene: View {
    let tierId: Int

    var body: some View {
        switch tierId {
        case 1: KingdomImageScene(assetName: "kingdom-molten-forge")
        case 2: KingdomImageScene(assetName: "kingdom-frozen-spire")
        case 3: KingdomImageScene(assetName: "kingdom-eternal-garden")
        case 4: KingdomImageScene(assetName: "kingdom-mystic-grove")
        default: EmptyView()
        }
    }
}

// MARK: - Pixel Art Kingdom Image View

/// Displays a pre-rendered pixel art kingdom scene with nearest-neighbor scaling
struct KingdomImageScene: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fill)
    }
}

// Note: Kingdom scenes are rendered from pre-generated pixel art PNG assets
// (320×200 pixel grid, 4px/cell = 1280×800 output)
// Assets: kingdom-molten-forge, kingdom-frozen-spire, kingdom-eternal-garden, kingdom-mystic-grove

// MARK: - Achievements Section

struct AchievementsSection: View {
    @EnvironmentObject var appState: AppState

    private var achievements: [(icon: String, name: String, unlocked: Bool)] {
        [
            ("🏗️", "First Steps", appState.completedLessons.count >= 1),
            ("🌋", "Earth Walker", GameData.skillTiers[0].skills.allSatisfy { appState.completedLessons.contains($0.id) }),
            ("🔥", "On Fire", appState.streak >= 3),
            ("💧", "Water Sage", GameData.skillTiers.count > 1 && GameData.skillTiers[1].skills.allSatisfy { appState.completedLessons.contains($0.id) }),
            ("💎", "Flawless", appState.completedLessons.count >= 5),
            ("🦋", "Social Butterfly", false),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACHIEVEMENTS")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(0..<achievements.count, id: \.self) { i in
                    let a = achievements[i]
                    HStack(spacing: 6) {
                        Text(a.icon)
                            .font(.pixelSystem(size: 16))
                            .grayscale(a.unlocked ? 0 : 1)
                            .opacity(a.unlocked ? 1 : 0.4)
                        Text(a.name)
                            .font(.pixelSystem(size: 10, weight: .medium))
                            .foregroundColor(a.unlocked ? Color(hex: "#2D2B26") : Color(hex: "#A09B8E"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(a.unlocked ? Color(hex: "#F0FAF4") : Color(hex: "#F8F7F3"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(a.unlocked ? Color(hex: "#6BCB77").opacity(0.3) : Color(hex: "#E8E6E0"), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
        .padding(.horizontal, 20)
    }
}
