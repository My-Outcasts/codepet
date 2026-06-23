import SwiftUI

/// Collection and dress-up shop for pet cosmetics (hats, accessories, backgrounds, effects).
struct CosmeticShopView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @Environment(\.theme) var theme

    @State private var selectedCategory: CosmeticItem.CosmeticCategory = .hat
    @State private var selectedItem: CosmeticItem? = nil
    @State private var showDetailSheet = false

    var currentCharacter: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var filteredItems: [CosmeticItem] {
        CosmeticShop.all.filter { $0.category == selectedCategory }
            .sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header with coin balance
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pet Shop")
                            .font(.pixelSystem(size: 28, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text("🪙")
                            .font(.pixelSystem(size: 20))
                        Text("\(gameState.coins)")
                            .font(.pixelSystem(size: 16, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.cardBackground)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)

                // Character preview area
                VStack(spacing: 12) {
                    Text("Your Pet")
                        .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textSecondary)

                    Image(currentCharacter.imageName)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(theme.cardBackground)
                .cornerRadius(12)
                .shadow(color: theme.shadow, radius: 4, y: 2)
                .padding(.horizontal, 20)

                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CosmeticItem.CosmeticCategory.allCases, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                HStack(spacing: 4) {
                                    Text(category.emoji)
                                    Text(category.rawValue)
                                        .font(.pixelSystem(size: 12, weight: .semibold))
                                }
                                .foregroundColor(selectedCategory == category ? .white : theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color(hex: "#7B6BD8") : theme.cardBackground)
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Grid of items
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredItems) { item in
                            CosmeticItemCard(
                                item: item,
                                isOwned: gameState.ownedCosmetics.contains(item.id),
                                isEquipped: isItemEquipped(item.id, forCategory: selectedCategory),
                                action: {
                                    selectedItem = item
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
            if let item = selectedItem {
                CosmeticDetailSheet(
                    item: item,
                    isOwned: gameState.ownedCosmetics.contains(item.id),
                    isEquipped: isItemEquipped(item.id, forCategory: selectedCategory),
                    buyAction: { buyItem(item) },
                    equipAction: { equipItem(item) },
                    isPresented: $showDetailSheet
                )
                .environment(\.theme, theme)
            }
        }
    }

    private func isItemEquipped(_ itemId: String, forCategory category: CosmeticItem.CosmeticCategory) -> Bool {
        switch category {
        case .hat: return gameState.equippedHat == itemId
        case .accessory: return gameState.equippedAccessory == itemId
        case .background: return gameState.equippedBackground == itemId
        case .effect: return gameState.equippedEffect == itemId
        }
    }

    private func buyItem(_ item: CosmeticItem) {
        if gameState.buyCosmeticItem(item) {
            gameState.equipCosmetic(item.id)
        }
    }

    private func equipItem(_ item: CosmeticItem) {
        gameState.equipCosmetic(item.id)
    }
}

// MARK: - Item Card Component

private struct CosmeticItemCard: View {
    @Environment(\.theme) var theme

    let item: CosmeticItem
    let isOwned: Bool
    let isEquipped: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    // Item emoji
                    Text(item.emoji)
                        .font(.pixelSystem(size: 40))

                    // Name
                    Text(item.name)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    // Rarity
                    Text(item.rarity.rawValue)
                        .font(.pixelSystem(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: item.rarity.color))
                        .cornerRadius(4)

                    Spacer()

                    // Status or cost
                    if isEquipped {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Equipped")
                        }
                        .font(.pixelSystem(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color(hex: "#7B6BD8"))
                        .cornerRadius(4)
                    } else if isOwned {
                        Text("Owned")
                            .font(.pixelSystem(size: 9, weight: .bold))
                            .foregroundColor(theme.textSecondary)
                    } else if let coinCost = item.coinCost {
                        HStack(spacing: 4) {
                            Text("🪙")
                            Text("\(coinCost)")
                        }
                        .font(.pixelSystem(size: 10, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    } else if item.unlockedBy != nil {
                        Image(systemName: "lock.fill")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(isOwned && !isEquipped ? theme.cardBackground : (isOwned ? Color(hex: "#7B6BD8").opacity(0.15) : Color(hex: "#444444").opacity(0.2)))
                .cornerRadius(8)
                .shadow(color: theme.shadow, radius: 4, y: 2)
                .border(
                    isEquipped ? Color(hex: "#7B6BD8") : Color.clear,
                    width: isEquipped ? 2 : 0
                )
                .cornerRadius(8)

                // Rarity dot in corner
                Circle()
                    .fill(Color(hex: item.rarity.color))
                    .frame(width: 8, height: 8)
                    .padding(8)
            }
        }
    }
}

// MARK: - Detail Sheet

struct CosmeticDetailSheet: View {
    @Environment(\.theme) var theme

    let item: CosmeticItem
    let isOwned: Bool
    let isEquipped: Bool
    let buyAction: () -> Void
    let equipAction: () -> Void
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Item Details")
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
                    // Large emoji and name
                    VStack(spacing: 12) {
                        Text(item.emoji)
                            .font(.pixelSystem(size: 64))

                        Text(item.name)
                            .font(.pixelSystem(size: 20, weight: .bold))
                            .foregroundColor(theme.textPrimary)

                        // Rarity badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: item.rarity.color))
                                .frame(width: 8, height: 8)

                            Text(item.rarity.rawValue)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: item.rarity.color))
                        .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity)

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.pixelSystem(size: 12, weight: .bold))
                            .foregroundColor(theme.textSecondary)

                        Text("A cosmetic item for your pet. Equip it to show off your collection!")
                            .font(.pixelSystem(size: 13))
                            .foregroundColor(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(theme.cardBackground)
                    .cornerRadius(8)

                    // Category
                    HStack(spacing: 8) {
                        Text("Category")
                            .font(.pixelSystem(size: 12, weight: .bold))
                            .foregroundColor(theme.textSecondary)
                        Text(item.category.emoji)
                        Text(item.category.rawValue)
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.cardBackground)
                    .cornerRadius(8)

                    // Status / Action section
                    if isEquipped {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.pixelSystem(size: 32))
                                .foregroundColor(theme.accentGreen)

                            Text("Currently Equipped")
                                .font(.pixelSystem(size: 14, weight: .semibold))
                                .foregroundColor(theme.accentGreen)

                            Text("This cosmetic is currently displayed on your pet.")
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(theme.accentGreen.opacity(0.1))
                        .cornerRadius(8)
                    } else if isOwned {
                        Button(action: equipAction) {
                            Text("Equip")
                                .font(.pixelSystem(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color(hex: "#7B6BD8"))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    } else if let coinCost = item.coinCost {
                        // Purchasable
                        Button(action: buyAction) {
                            HStack(spacing: 8) {
                                Text("🪙")
                                Text("Buy for \(coinCost) coins")
                                    .font(.pixelSystem(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(hex: "#7B6BD8"))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    } else if let unlockedBy = item.unlockedBy {
                        // Achievement-only
                        VStack(spacing: 8) {
                            Image(systemName: "lock.circle.fill")
                                .font(.pixelSystem(size: 32))
                                .foregroundColor(theme.textMuted)

                            Text("Achievement Only")
                                .font(.pixelSystem(size: 14, weight: .semibold))
                                .foregroundColor(theme.textPrimary)

                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(Color(hex: "#D4960A"))
                                Text("Earn: \(unlockedBy)")
                                    .font(.pixelSystem(size: 12))
                                    .foregroundColor(theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(theme.cardBackground)
                        .cornerRadius(8)
                    }
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
    CosmeticShopView()
        .environmentObject(AppState())
        .environmentObject(GameState())
        .environment(\.theme, ThemeManager.shared.light)
}
