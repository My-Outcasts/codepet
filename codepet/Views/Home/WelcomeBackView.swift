import SwiftUI

/// Full-screen overlay shown when user returns after 1+ hours away.
/// Celebrates idle progress with XP earned and pet status updates.
struct WelcomeBackView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme

    let idleXP: Int
    let previousEnergy: Int
    let previousHunger: Int
    let dismissAction: () -> Void

    @State private var sparkleScale: CGFloat = 0.5
    @State private var sparkleOpacity: Double = 0

    var currentCharacter: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        ZStack {
            // Translucent dark background
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            // Modal card
            VStack(spacing: 20) {
                // Character image at top
                Image(currentCharacter.imageName)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                // Welcome message
                VStack(spacing: 8) {
                    Text("Welcome back!")
                        .font(.pixelSystem(size: 24, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Text("While you were away, \(currentCharacter.name) studied on their own...")
                        .font(.pixelSystem(size: 14))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Idle XP earned with sparkle animation
                VStack(spacing: 12) {
                    ZStack {
                        Text("✨")
                            .font(.pixelSystem(size: 32))
                            .scaleEffect(sparkleScale)
                            .opacity(sparkleOpacity)

                        Text("+\(idleXP) XP")
                            .font(.pixelSystem(size: 28, weight: .bold))
                            .foregroundColor(Color(hex: "#7B6BD8"))
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        sparkleScale = 1.2
                        sparkleOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            sparkleOpacity = 0.5
                        }
                    }
                }

                // Tip from pet
                VStack(spacing: 0) {
                    Text(IdleXPSystem.randomTip())
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(theme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.cardBackground)
                        .shadow(color: theme.shadow, radius: 4, y: 2)
                )

                // Status changes
                VStack(spacing: 12) {
                    StatusChangeRow(
                        label: "Energy",
                        oldValue: previousEnergy,
                        newValue: appState.petEnergy,
                        emoji: "⚡",
                        isNegative: appState.petEnergy < previousEnergy
                    )

                    Divider()
                        .background(theme.divider)

                    StatusChangeRow(
                        label: "Hunger",
                        oldValue: previousHunger,
                        newValue: gameState.petHunger,
                        emoji: "🍖",
                        isNegative: gameState.petHunger < previousHunger
                    )
                }
                .padding(12)
                .background(theme.cardBackground)
                .cornerRadius(8)

                Spacer()

                // Let's go button
                Button(action: dismissAction) {
                    Text("Let's go!")
                        .font(.pixelSystem(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(hex: "#7B6BD8"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(theme.cardBackground)
            .cornerRadius(24)
            .shadow(color: theme.shadow, radius: 16, y: 8)
        }
    }
}

// MARK: - Status Change Row Component

private struct StatusChangeRow: View {
    @Environment(\.theme) var theme

    let label: String
    let oldValue: Int
    let newValue: Int
    let emoji: String
    let isNegative: Bool

    var changeText: String {
        let change = newValue - oldValue
        let prefix = change >= 0 ? "+" : ""
        return "\(prefix)\(change)"
    }

    var changeColor: Color {
        isNegative ? theme.accentRed : theme.accentGreen
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.pixelSystem(size: 16))

            Text(label)
                .font(.pixelSystem(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            Spacer()

            HStack(spacing: 8) {
                Text("\(oldValue)")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(theme.textSecondary)

                Text("→")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(theme.textMuted)

                Text("\(newValue)")
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                Text(changeText)
                    .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(changeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(changeColor.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }
}

#Preview {
    WelcomeBackView(
        idleXP: 24,
        previousEnergy: 60,
        previousHunger: 50,
        dismissAction: {}
    )
    .environmentObject(AppState())
    .environmentObject(GameState())
    .environment(\.theme, ThemeManager.shared.light)
}
