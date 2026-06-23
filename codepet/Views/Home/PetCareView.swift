import SwiftUI

/// Tamagotchi-style pet care card with feeding, mood display, and status bars.
/// Embedded in HomeView as a section (not a full-screen view).
struct PetCareView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme

    @State private var petScale: CGFloat = 1.0

    var currentCharacter: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var petMood: PetCare.Mood {
        let hoursSinceVisit = appState.lastVisit.map { Date().timeIntervalSince($0) / 3600 } ?? 0
        return PetCare.calculateMood(
            energy: appState.petEnergy,
            hunger: gameState.petHunger,
            streak: appState.streak,
            hoursSinceLastVisit: hoursSinceVisit,
            justFed: false
        )
    }

    var energyPercent: Double {
        Double(max(0, min(100, appState.petEnergy))) / 100.0
    }

    var hungerPercent: Double {
        Double(max(0, min(100, gameState.petHunger))) / 100.0
    }

    var body: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("PET CARE")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(petMood.emoji)
                        .font(.pixelSystem(size: 14))
                    Text(petMood.rawValue)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
            }

            // Mood + quote
            HStack(spacing: 12) {
                Text(petMood.emoji)
                    .font(.pixelSystem(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentCharacter.name)
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    Text(petMood.description)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(theme.textSecondary)
                }
                Spacer()
            }

            // Status bars
            VStack(spacing: 12) {
                StatusBar(label: "ENERGY", emoji: "⚡", value: appState.petEnergy, color: Color(hex: "#7B6BD8"), theme: theme)
                StatusBar(label: "HUNGER", emoji: "🍖", value: gameState.petHunger, color: Color(hex: "#F5A623"), theme: theme)
            }

            // Food row
            if petMood != .asleep {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PetFood.all) { food in
                            let canAfford = gameState.coins >= food.coinCost
                            Button(action: { if canAfford { feedPet(food) } }) {
                                VStack(spacing: 4) {
                                    Text(food.emoji)
                                        .font(.pixelSystem(size: 22))
                                    Text(food.name)
                                        .font(.pixelSystem(size: 9, weight: .semibold))
                                        .foregroundColor(theme.textPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 2) {
                                        Text("🪙\(food.coinCost)")
                                            .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(canAfford ? theme.textPrimary : theme.textMuted)
                                    }
                                }
                                .frame(width: 72)
                                .padding(8)
                                .background(theme.cardBackground)
                                .cornerRadius(10)
                                .opacity(canAfford ? 1.0 : 0.45)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAfford)
                        }
                    }
                }
            } else {
                // Asleep state
                Button(action: { gameState.wakeUpPet() }) {
                    HStack(spacing: 8) {
                        Text("💤")
                            .font(.pixelSystem(size: 20))
                        Text("Tap to wake up")
                            .font(.pixelSystem(size: 12, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: theme.shadow, radius: 8, y: 2)
        )
    }

    private func feedPet(_ food: PetFood) {
        gameState.feedPet(food: food, appState: appState)
        SoundManager.shared.playTap()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            petScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                petScale = 1.0
            }
        }
    }
}

// MARK: - Status Bar Component

private struct StatusBar: View {
    let label: String
    let emoji: String
    let value: Int
    let color: Color
    let theme: ThemeManager.ThemeColors

    var percent: Double {
        Double(max(0, min(100, value))) / 100.0
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(emoji) \(label)")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                Spacer()
                Text("\(value)/100")
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.energyBarTrack)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * percent)
                        .animation(.spring(response: 0.5), value: percent)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    PetCareView()
        .environmentObject(AppState())
        .environmentObject(GameState())
        .environment(\.theme, ThemeManager.shared.light)
        .frame(width: 400)
        .padding()
}
