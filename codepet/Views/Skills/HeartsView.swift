import SwiftUI

/// Small hearts display component for top bar / lesson header.
/// Shows heart icons (filled/empty) and timer until next heart regenerates.
struct HeartsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme

    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var showRefillSheet = false

    var currentHearts: Int {
        HeartsSystem.currentHearts(
            savedHearts: gameState.hearts,
            lastHeartLoss: gameState.lastHeartLoss
        )
    }

    var timeUntilNextHeart: TimeInterval? {
        HeartsSystem.timeUntilNextHeart(
            savedHearts: gameState.hearts,
            lastHeartLoss: gameState.lastHeartLoss
        )
    }

    var timeFormatted: String {
        let seconds = Int(timeRemaining)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Hearts row
            HStack(spacing: 6) {
                ForEach(0..<HeartsSystem.maxHearts, id: \.self) { index in
                    if index < currentHearts {
                        Text("❤️")
                            .font(.pixelSystem(size: 16))
                    } else {
                        Text("🤍")
                            .font(.pixelSystem(size: 16))
                    }
                }

                Spacer()

                // Timer if not full
                if timeUntilNextHeart != nil {
                    HStack(spacing: 4) {
                        Text("Next ❤️ in")
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(theme.textSecondary)
                        Text(timeFormatted)
                            .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.cardBackground)
                    .cornerRadius(6)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.cardBackground)
                    .shadow(color: theme.shadow, radius: 4, y: 2)
            )
            .onTapGesture {
                showRefillSheet = true
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .sheet(isPresented: $showRefillSheet) {
            HeartsRefillSheet(isPresented: $showRefillSheet)
                .environmentObject(appState)
                .environmentObject(gameState)
                .environment(\.theme, theme)
        }
    }

    private func startTimer() {
        stopTimer()
        timeRemaining = timeUntilNextHeart ?? 0

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // Heart regenerated, update state
                let newHearts = HeartsSystem.currentHearts(
                    savedHearts: gameState.hearts,
                    lastHeartLoss: gameState.lastHeartLoss
                )
                if newHearts > currentHearts {
                    gameState.hearts = newHearts
                    startTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Hearts Refill Sheet

struct HeartsRefillSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme
    @Binding var isPresented: Bool

    var currentHearts: Int {
        HeartsSystem.currentHearts(
            savedHearts: gameState.hearts,
            lastHeartLoss: gameState.lastHeartLoss
        )
    }

    var timeUntilNextHeart: TimeInterval? {
        HeartsSystem.timeUntilNextHeart(
            savedHearts: gameState.hearts,
            lastHeartLoss: gameState.lastHeartLoss
        )
    }

    var timeFormatted: String {
        guard let timeLeft = timeUntilNextHeart else { return "—" }
        let seconds = Int(timeLeft)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var canAffordRefill: Bool {
        gameState.coins >= GameEconomy.heartRefillCost
    }

    var currentCharacter: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Hearts")
                    .font(.pixelSystem(size: 20, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.pixelSystem(size: 20))
                        .foregroundColor(theme.textMuted)
                }
            }
            .padding(.bottom, 8)

            // Current hearts display (large)
            VStack(spacing: 12) {
                Text("❤️")
                    .font(.pixelSystem(size: 48))

                HStack(spacing: 8) {
                    ForEach(0..<HeartsSystem.maxHearts, id: \.self) { index in
                        if index < currentHearts {
                            Text("❤️")
                                .font(.pixelSystem(size: 24))
                        } else {
                            Text("🤍")
                                .font(.pixelSystem(size: 24))
                        }
                    }
                }

                Text("\(currentHearts) / \(HeartsSystem.maxHearts)")
                    .font(.pixelSystem(size: 16, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(20)
            .background(theme.cardBackground)
            .cornerRadius(12)

            // Refill button
            if currentHearts < HeartsSystem.maxHearts {
                Button(action: refillHearts) {
                    HStack(spacing: 8) {
                        Text("🪙")
                        Text("Refill all hearts")
                            .font(.pixelSystem(size: 14, weight: .semibold))
                        Text("(\(GameEconomy.heartRefillCost))")
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(canAffordRefill ? Color(hex: "#7B6BD8") : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(!canAffordRefill)

                // Or wait text
                VStack(spacing: 4) {
                    Text("Or wait")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(theme.textSecondary)
                    Text(timeFormatted)
                        .font(.pixelSystem(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textPrimary)
                    Text("for next heart")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(theme.cardBackground)
                .cornerRadius(8)
            } else {
                Text("Hearts at full capacity!")
                    .font(.pixelSystem(size: 14, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(theme.accentGreen.opacity(0.1))
                    .cornerRadius(8)
            }

            // Tip
            VStack(spacing: 8) {
                Text("💡 Tip")
                    .font(.pixelSystem(size: 12, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("Feeding \(currentCharacter.name) a meal can boost your hearts too!")
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .background(Color(hex: "#F5A623").opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
        .padding(20)
        .background(theme.background)
        .presentationDetents([.medium])
    }

    private func refillHearts() {
        if gameState.coins >= GameEconomy.heartRefillCost {
            gameState.coins -= GameEconomy.heartRefillCost
            gameState.hearts = HeartsSystem.maxHearts
            gameState.lastHeartLoss = nil
            isPresented = false
        }
    }
}

#Preview {
    HeartsView()
        .environmentObject(AppState())
        .environmentObject(GameState())
        .environment(\.theme, ThemeManager.shared.light)
        .padding()
}
