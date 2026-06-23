import SwiftUI

/// Pokédex-style collection gallery for discoverable code knowledge entries.
struct CompendiumView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme

    @State private var selectedCategory: CompendiumEntry.CompendiumCategory? = nil
    @State private var selectedEntry: CompendiumEntry? = nil
    @State private var showDetailSheet = false

    var filteredEntries: [CompendiumEntry] {
        let all = Compendium.all

        let filtered: [CompendiumEntry]
        if let category = selectedCategory {
            filtered = all.filter { $0.category == category }
        } else {
            filtered = all
        }

        return filtered.sorted { $0.name < $1.name }
    }

    var unlockedCount: Int {
        gameState.unlockedCompendiumEntries.count
    }

    var totalCount: Int {
        Compendium.all.count
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Text("Compendium")
                        .font(.pixelSystem(size: 28, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Text("\(unlockedCount)/\(totalCount) discovered")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                // Category filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // All button
                        Button(action: { selectedCategory = nil }) {
                            Text("All")
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(selectedCategory == nil ? .white : theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == nil ? Color(hex: "#7B6BD8") : theme.cardBackground)
                                .cornerRadius(6)
                        }

                        // Category buttons
                        ForEach(CompendiumEntry.CompendiumCategory.allCases, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                HStack(spacing: 4) {
                                    Text(category.emoji)
                                    Text(category.rawValue)
                                        .font(.pixelSystem(size: 12, weight: .semibold))
                                }
                                .foregroundColor(selectedCategory == category ? .white : theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color(hex: category.color) : theme.cardBackground)
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Grid of entries
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            CompendiumEntryCard(
                                entry: entry,
                                isUnlocked: gameState.unlockedCompendiumEntries.contains(entry.id),
                                action: {
                                    selectedEntry = entry
                                    showDetailSheet = true
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            if let entry = selectedEntry {
                CompendiumDetailSheet(
                    entry: entry,
                    isUnlocked: gameState.unlockedCompendiumEntries.contains(entry.id),
                    isPresented: $showDetailSheet
                )
                .environment(\.theme, theme)
            }
        }
    }
}

// MARK: - Entry Card Component

private struct CompendiumEntryCard: View {
    @Environment(\.theme) var theme

    let entry: CompendiumEntry
    let isUnlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Category color strip at top
                if isUnlocked {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: entry.category.color))
                        .frame(height: 3)
                }

                if isUnlocked {
                    // Unlocked entry
                    Text(entry.icon)
                        .font(.pixelSystem(size: 32))

                    Text(entry.name)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(entry.category.emoji)
                        .font(.pixelSystem(size: 11))
                } else {
                    // Locked entry
                    VStack(spacing: 8) {
                        Text("❓")
                            .font(.pixelSystem(size: 32))

                        Text("Undiscovered")
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(theme.textMuted)

                        Image(systemName: "lock.fill")
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(theme.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(isUnlocked ? theme.cardBackground : Color(hex: "#444444").opacity(0.3))
            .cornerRadius(8)
            .shadow(color: theme.shadow, radius: 4, y: 2)
        }
        .disabled(!isUnlocked)
    }
}

// MARK: - Detail Sheet

struct CompendiumDetailSheet: View {
    @Environment(\.theme) var theme

    let entry: CompendiumEntry
    let isUnlocked: Bool
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Entry Details")
                    .font(.pixelSystem(size: 18, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.pixelSystem(size: 18))
                        .foregroundColor(theme.textMuted)
                }
            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    // Icon and name
                    VStack(spacing: 12) {
                        Text(entry.icon)
                            .font(.pixelSystem(size: 48))

                        Text(entry.name)
                            .font(.pixelSystem(size: 20, weight: .bold))
                            .foregroundColor(theme.textPrimary)

                        // Category badge
                        HStack(spacing: 6) {
                            Text(entry.category.emoji)
                            Text(entry.category.rawValue)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: entry.category.color))
                        .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity)

                    // Description
                    Text(entry.description)
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(theme.cardBackground)
                        .cornerRadius(8)

                    // Code example (if available)
                    if let codeExample = entry.codeExample {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Code Example")
                                .font(.pixelSystem(size: 12, weight: .bold))
                                .foregroundColor(theme.textSecondary)

                            Text(codeExample)
                                .font(.pixelSystem(size: 11, design: .monospaced))
                                .foregroundColor(Color(hex: "#E0E0E0"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }
                    }

                    // Unlock info
                    VStack(spacing: 8) {
                        if isUnlocked {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(theme.accentGreen)
                                Text("Unlocked!")
                                    .font(.pixelSystem(size: 12, weight: .semibold))
                                    .foregroundColor(theme.accentGreen)
                            }
                        } else {
                            Text("Unlocked by completing:")
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(theme.textSecondary)

                            Text(entry.unlockedBy)
                                .font(.pixelSystem(size: 13, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(theme.cardBackground)
                                .cornerRadius(6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(isUnlocked ? theme.accentGreen.opacity(0.1) : Color(hex: "#666666").opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Spacer()

            // Close button
            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(.pixelSystem(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(hex: "#7B6BD8"))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .background(theme.background)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    CompendiumView()
        .environmentObject(AppState())
        .environmentObject(GameState())
        .environment(\.theme, ThemeManager.shared.light)
}
