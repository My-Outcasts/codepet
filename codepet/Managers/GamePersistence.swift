import Foundation

/// Saves and restores GameState to UserDefaults so all game progress survives app restarts.
/// Follows the same pattern as PersistenceManager with cp_game_ prefixed keys.
public class GamePersistence {

    public static let shared = GamePersistence()
    private let defaults = UserDefaults.standard

    // MARK: - Keys (all prefixed with cp_game_)

    private enum Key {
        static let petHunger = "cp_game_petHunger"
        static let petMoodState = "cp_game_petMoodState"
        static let lastFeedTime = "cp_game_lastFeedTime"
        static let showWelcomeBack = "cp_game_showWelcomeBack"

        static let idleXPEarned = "cp_game_idleXPEarned"
        static let idleTip = "cp_game_idleTip"

        static let hearts = "cp_game_hearts"
        static let lastHeartLoss = "cp_game_lastHeartLoss"

        static let coins = "cp_game_coins"

        static let equippedHat = "cp_game_equippedHat"
        static let equippedAccessory = "cp_game_equippedAccessory"
        static let equippedBackground = "cp_game_equippedBackground"
        static let equippedEffect = "cp_game_equippedEffect"
        static let ownedCosmetics = "cp_game_ownedCosmetics"

        static let unlockedCompendiumEntries = "cp_game_unlockedCompendiumEntries"
        static let streakFreezes = "cp_game_streakFreezes"
        static let frozenStreakDays = "cp_game_frozenStreakDays"
        static let awardedStreakMilestones = "cp_game_awardedStreakMilestones"

        static let hasSavedBefore = "cp_game_hasSavedBefore"
    }

    // MARK: - Save

    /// Save all GameState properties to UserDefaults
    public func save(_ state: GameState) {
        defaults.set(true, forKey: Key.hasSavedBefore)

        // Pet Care
        defaults.set(state.petHunger, forKey: Key.petHunger)
        defaults.set(state.petMoodState.rawValue, forKey: Key.petMoodState)
        if let lastFeed = state.lastFeedTime {
            defaults.set(lastFeed.timeIntervalSince1970, forKey: Key.lastFeedTime)
        }
        defaults.set(state.showWelcomeBack, forKey: Key.showWelcomeBack)

        // Idle System
        defaults.set(state.idleXPEarned, forKey: Key.idleXPEarned)
        defaults.set(state.idleTip, forKey: Key.idleTip)

        // Hearts System
        defaults.set(state.hearts, forKey: Key.hearts)
        if let lastLoss = state.lastHeartLoss {
            defaults.set(lastLoss.timeIntervalSince1970, forKey: Key.lastHeartLoss)
        }

        // Economy
        defaults.set(state.coins, forKey: Key.coins)

        // Cosmetics & Equipment
        defaults.set(state.equippedHat, forKey: Key.equippedHat)
        defaults.set(state.equippedAccessory, forKey: Key.equippedAccessory)
        defaults.set(state.equippedBackground, forKey: Key.equippedBackground)
        defaults.set(state.equippedEffect, forKey: Key.equippedEffect)
        defaults.set(state.ownedCosmetics, forKey: Key.ownedCosmetics)

        // Compendium & Unlocks
        defaults.set(state.unlockedCompendiumEntries, forKey: Key.unlockedCompendiumEntries)
        defaults.set(state.streakFreezes, forKey: Key.streakFreezes)
        defaults.set(state.frozenStreakDays.map { $0.timeIntervalSince1970 }, forKey: Key.frozenStreakDays)
        defaults.set(state.awardedStreakMilestones, forKey: Key.awardedStreakMilestones)

        print("[GamePersistence] Saved — Coins: \(state.coins), Hearts: \(state.hearts), Hunger: \(state.petHunger)")
    }

    // MARK: - Load

    /// Load all GameState properties from UserDefaults
    public func load(into state: GameState) {
        guard defaults.bool(forKey: Key.hasSavedBefore) else {
            print("[GamePersistence] No saved data found — fresh start")
            return
        }

        // Pet Care
        state.petHunger = defaults.integer(forKey: Key.petHunger)
        if state.petHunger == 0 { state.petHunger = 80 }

        if let moodString = defaults.string(forKey: Key.petMoodState),
           let mood = PetCare.Mood(rawValue: moodString) {
            state.petMoodState = mood
        } else {
            state.petMoodState = .content
        }

        let lastFeedInterval = defaults.double(forKey: Key.lastFeedTime)
        if lastFeedInterval > 0 {
            state.lastFeedTime = Date(timeIntervalSince1970: lastFeedInterval)
        }

        state.showWelcomeBack = defaults.bool(forKey: Key.showWelcomeBack)

        // Idle System
        state.idleXPEarned = defaults.integer(forKey: Key.idleXPEarned)
        state.idleTip = defaults.string(forKey: Key.idleTip) ?? IdleXPSystem.randomTip()

        // Hearts System
        state.hearts = defaults.integer(forKey: Key.hearts)
        if state.hearts == 0 { state.hearts = 5 }
        if state.hearts > HeartsSystem.maxHearts { state.hearts = HeartsSystem.maxHearts }

        let lastHeartLossInterval = defaults.double(forKey: Key.lastHeartLoss)
        if lastHeartLossInterval > 0 {
            state.lastHeartLoss = Date(timeIntervalSince1970: lastHeartLossInterval)
        }

        // Economy
        state.coins = defaults.integer(forKey: Key.coins)

        // Cosmetics & Equipment
        state.equippedHat = defaults.string(forKey: Key.equippedHat) ?? "hat_none"
        state.equippedAccessory = defaults.string(forKey: Key.equippedAccessory)
        state.equippedBackground = defaults.string(forKey: Key.equippedBackground) ?? "bg_default"
        state.equippedEffect = defaults.string(forKey: Key.equippedEffect)

        let savedCosmetics = defaults.stringArray(forKey: Key.ownedCosmetics) ?? ["hat_none", "bg_default"]
        state.ownedCosmetics = savedCosmetics

        // Compendium & Unlocks
        let savedCompendium = defaults.stringArray(forKey: Key.unlockedCompendiumEntries) ?? []
        state.unlockedCompendiumEntries = savedCompendium

        state.streakFreezes = defaults.integer(forKey: Key.streakFreezes)
        if let frozen = defaults.array(forKey: Key.frozenStreakDays) as? [Double] {
            state.frozenStreakDays = frozen.map { Date(timeIntervalSince1970: $0) }
        }
        state.awardedStreakMilestones = (defaults.array(forKey: Key.awardedStreakMilestones) as? [Int]) ?? []

        print("[GamePersistence] Loaded — Coins: \(state.coins), Hearts: \(state.hearts), Hunger: \(state.petHunger)")
    }

    // MARK: - Reset

    /// Clear all game state data from UserDefaults
    public func resetAll() {
        // Remove all cp_game_ keys individually
        let keysToRemove = [
            Key.petHunger,
            Key.petMoodState,
            Key.lastFeedTime,
            Key.showWelcomeBack,
            Key.idleXPEarned,
            Key.idleTip,
            Key.hearts,
            Key.lastHeartLoss,
            Key.coins,
            Key.equippedHat,
            Key.equippedAccessory,
            Key.equippedBackground,
            Key.equippedEffect,
            Key.ownedCosmetics,
            Key.unlockedCompendiumEntries,
            Key.streakFreezes,
            Key.frozenStreakDays,
            Key.awardedStreakMilestones,
            Key.hasSavedBefore
        ]

        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        print("[GamePersistence] All game data cleared")
    }
}
