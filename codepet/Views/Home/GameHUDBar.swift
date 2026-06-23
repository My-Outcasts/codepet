import SwiftUI

/// Compact HUD bar showing hearts, coins, and streak.
/// Sits at the top of the main content area, game-style.
struct GameHUDBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    private var currentHearts: Int {
        HeartsSystem.currentHearts(
            savedHearts: gameState.hearts,
            lastHeartLoss: gameState.lastHeartLoss
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            // Hearts
            HStack(spacing: 4) {
                ForEach(0..<HeartsSystem.maxHearts, id: \.self) { index in
                    Image(systemName: index < currentHearts ? "heart.fill" : "heart")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(index < currentHearts ? Color(hex: "#FF4757") : Color(hex: "#DDD"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )

            // Coins
            HStack(spacing: 5) {
                Text("🪙")
                    .font(.pixelSystem(size: 12))
                Text("\(gameState.coins)")
                    .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )

            // Streak
            if appState.streak > 0 {
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.pixelSystem(size: 11))
                    Text("\(appState.streak)")
                        .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#FF6B6B"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                )
            }

            Spacer()

            // XP pill
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#FFD700"))
                Text("\(appState.totalXP) XP")
                    .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(character.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "#FBF9F1").opacity(0.95))
    }
}
