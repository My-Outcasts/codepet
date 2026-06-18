import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - GameState: ObservableObject
// ═══════════════════════════════════════════════════════════════════════════════

/// GameState extends AppState by holding all game system properties.
/// Since Swift doesn't allow stored properties in extensions, this is a separate
/// ObservableObject that works alongside AppState.
/// Views use: @EnvironmentObject var appState: AppState
///            @EnvironmentObject var gameState: GameState
public class GameState: ObservableObject {

    // MARK: - Pet Care Properties

    @Published public var petHunger: Int = 80
    @Published public var petMoodState: PetCare.Mood = .content
    @Published public var lastFeedTime: Date? = nil
    @Published public var showWelcomeBack: Bool = false

    // MARK: - Idle System Properties

    @Published public var idleXPEarned: Int = 0
    @Published public var idleTip: String = ""

    // MARK: - Hearts System Properties

    @Published public var hearts: Int = 5
    @Published public var lastHeartLoss: Date? = nil

    // MARK: - Economy Properties

    @Published public var coins: Int = 0

    // MARK: - Cosmetics & Equipment

    @Published public var equippedHat: String = "hat_none"
    @Published public var equippedAccessory: String? = nil
    @Published public var equippedBackground: String = "bg_default"
    @Published public var equippedEffect: String? = nil
    @Published public var ownedCosmetics: [String] = ["hat_none", "bg_default"]

    // MARK: - Compendium & Unlocks

    @Published public var unlockedCompendiumEntries: [String] = []
    @Published public var streakFreezes: Int = 0
    /// Days (startOfDay) whose missed activity was covered by a streak freeze.
    /// Surfaced as freeze markers on the streak calendar.
    @Published public var frozenStreakDays: [Date] = []
    /// Streak milestone day-counts already recognized, so each is awarded once.
    @Published public var awardedStreakMilestones: [Int] = []

    // MARK: - Auto-save cancellable

    private var saveCancellable: AnyCancellable?

    // MARK: - Reference to AppState (weak to avoid cycles)

    private weak var appState: AppState?

    // MARK: - Initialization

    init(appState: AppState? = nil) {
        self.appState = appState

        // Load game state from persistence
        GamePersistence.shared.load(into: self)

        // Auto-save whenever any @Published property changes (debounced 2s)
        saveCancellable = objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                GamePersistence.shared.save(self)
            }
    }

    /// Set the AppState reference (called after both are initialized)
    func setAppState(_ state: AppState) {
        self.appState = state
    }

    // MARK: - Pet Care Methods

    /// Feed the pet with food, costs coins, restores energy/hunger, updates mood
    @discardableResult
    func feedPet(food: PetFood, appState: AppState? = nil) -> Bool {
        guard coins >= food.coinCost else { return false }

        // Deduct coins
        coins -= food.coinCost

        // Restore hunger
        petHunger = min(100, petHunger + food.hungerRestore)

        // Restore energy on AppState
        if let appState = appState ?? self.appState {
            appState.petEnergy = min(100, appState.petEnergy + food.energyRestore)
        }

        // Update last feed time
        lastFeedTime = Date()

        // Update mood to reflect being fed
        updatePetMood(justFed: true)

        print("[GameState] Fed pet with \(food.name) (\(food.emoji)), restored hunger +\(food.hungerRestore), energy +\(food.energyRestore)")

        return true
    }

    /// Wake pet from asleep state (reset energy/hunger to baseline)
    func wakeUpPet() {
        guard let appState = appState else { return }
        appState.petEnergy = max(appState.petEnergy, 20)
        petHunger = max(petHunger, 20)
        updatePetMood()
        print("[GameState] Pet woken up")
    }

    /// Lose a heart (decrement, set lastHeartLoss)
    public func loseHeart() {
        if hearts > 0 {
            hearts -= 1
            lastHeartLoss = Date()
            print("[GameState] Lost a heart, now at \(hearts)/\(HeartsSystem.maxHearts)")
        }
    }

    /// Refill all hearts for coin cost
    public func refillHearts() -> Bool {
        guard coins >= GameEconomy.heartRefillCost else { return false }

        coins -= GameEconomy.heartRefillCost
        hearts = HeartsSystem.maxHearts
        lastHeartLoss = nil

        print("[GameState] Refilled hearts for \(GameEconomy.heartRefillCost) coins")
        return true
    }

    /// Buy a streak freeze to protect the streak
    public func buyStreakFreeze() -> Bool {
        guard coins >= GameEconomy.streakFreezeCost else { return false }

        coins -= GameEconomy.streakFreezeCost
        streakFreezes += 1

        print("[GameState] Bought streak freeze for \(GameEconomy.streakFreezeCost) coins")
        return true
    }

    // MARK: - Streak rescue + milestones

    /// If a single day was missed at load and a freeze is available, spend it to
    /// keep the streak alive (continuing it as if today resumed it), and record
    /// the frozen day for the calendar. Multi-day gaps aren't rescued by one
    /// freeze. Idempotent: consumes `appState.pendingStreakBreak`.
    public func resolveStreakRescue() {
        guard let appState = appState, let brk = appState.pendingStreakBreak else { return }
        appState.pendingStreakBreak = nil
        guard brk.missedDays == 1, streakFreezes > 0 else { return }

        streakFreezes -= 1
        appState.streak = brk.priorStreak + 1   // the frozen day bridged the gap
        if appState.streak > appState.longestStreak { appState.longestStreak = appState.streak }

        let cal = Calendar.current
        if let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) {
            let day = cal.startOfDay(for: yesterday)
            if !frozenStreakDays.contains(day) { frozenStreakDays.append(day) }
        }
        print("[GameState] Streak rescued with a freeze → \(appState.streak)")
    }

    /// Recognize any streak milestone newly reached: award its coins + bonus
    /// freezes and unlock matching `streak_<day>` cosmetics, once each. Returns
    /// the highest newly-reached milestone (for the celebration), or nil.
    @discardableResult
    public func checkStreakMilestones() -> StreakMilestone? {
        guard let appState = appState else { return nil }
        let streak = appState.streak
        let newlyReached = GameEconomy.streakMilestones
            .filter { $0.day <= streak && !awardedStreakMilestones.contains($0.day) }
            .sorted { $0.day < $1.day }
        guard !newlyReached.isEmpty else { return nil }

        var celebrate: StreakMilestone? = nil
        for m in newlyReached {
            awardedStreakMilestones.append(m.day)
            if m.bonusCoins > 0 { earnCoins(m.bonusCoins) }
            if m.freezeReward > 0 { streakFreezes += m.freezeReward }
            unlockStreakCosmetics(forStreakDay: m.day)
            celebrate = m   // the highest rung drives the celebration
        }
        return celebrate
    }

    /// Auto-unlock cosmetics gated by `unlockedBy: "streak_<day>"`.
    private func unlockStreakCosmetics(forStreakDay day: Int) {
        let key = "streak_\(day)"
        for item in CosmeticShop.all where item.unlockedBy == key && !ownedCosmetics.contains(item.id) {
            ownedCosmetics.append(item.id)
            print("[GameState] Unlocked cosmetic \(item.name) at streak \(day)")
        }
    }

    /// Display name of a cosmetic unlocked exactly at `day`, if any (for the
    /// celebration copy).
    public func cosmeticName(forStreakDay day: Int) -> String? {
        CosmeticShop.all.first { $0.unlockedBy == "streak_\(day)" }?.name
    }

    // MARK: - Cosmetics & Collection Methods

    /// Purchase a cosmetic item from the shop
    public func buyCosmeticItem(_ item: CosmeticItem) -> Bool {
        // Check if already owned
        if ownedCosmetics.contains(item.id) {
            print("[GameState] Already own \(item.name)")
            return true
        }

        // Check if it's purchasable
        guard let cost = item.coinCost else {
            print("[GameState] \(item.name) is not purchasable (achievement only)")
            return false
        }

        // Check if enough coins
        guard coins >= cost else {
            print("[GameState] Not enough coins for \(item.name) (\(cost) coins needed)")
            return false
        }

        // Purchase
        coins -= cost
        ownedCosmetics.append(item.id)

        print("[GameState] Purchased \(item.name) for \(cost) coins")
        return true
    }

    /// Equip a cosmetic item
    public func equipCosmetic(_ itemId: String) {
        // Verify owned
        guard ownedCosmetics.contains(itemId) else {
            print("[GameState] Don't own cosmetic \(itemId)")
            return
        }

        // Find the item to determine category
        guard let item = (CosmeticShop.all.first { $0.id == itemId }) else {
            print("[GameState] Unknown cosmetic \(itemId)")
            return
        }

        // Equip based on category
        switch item.category {
        case .hat:
            equippedHat = itemId
        case .accessory:
            equippedAccessory = itemId
        case .background:
            equippedBackground = itemId
        case .effect:
            equippedEffect = itemId
        }

        print("[GameState] Equipped \(item.name) (\(item.category.emoji))")
    }

    /// Unlock a compendium entry
    public func unlockCompendiumEntry(_ entryId: String) {
        guard !unlockedCompendiumEntries.contains(entryId) else {
            return // Already unlocked
        }

        unlockedCompendiumEntries.append(entryId)

        if let entry = Compendium.all.first(where: { $0.id == entryId }) {
            print("[GameState] Unlocked compendium entry: \(entry.name)")
        }
    }

    /// Check and unlock compendium entries based on lesson/challenge completion
    public func checkCompendiumUnlocks(forLesson lessonId: String) {
        let unlockedThisTime = Compendium.all.filter { entry in
            entry.unlockedBy == lessonId && !unlockedCompendiumEntries.contains(entry.id)
        }

        for entry in unlockedThisTime {
            unlockCompendiumEntry(entry.id)
        }
    }

    // MARK: - Economy Methods

    /// Earn coins from various sources
    public func earnCoins(_ amount: Int) {
        coins += amount
        print("[GameState] Earned \(amount) coins (now at \(coins) total)")
    }

    // MARK: - Mood Calculation

    /// Update pet mood based on current stats
    public func updatePetMood(justFed: Bool = false) {
        guard let appState = appState else { return }

        let hoursSinceLastVisit = appState.lastVisit.map { Date().timeIntervalSince($0) / 3600 } ?? 0

        petMoodState = PetCare.calculateMood(
            energy: appState.petEnergy,
            hunger: petHunger,
            streak: appState.streak,
            hoursSinceLastVisit: hoursSinceLastVisit,
            justFed: justFed
        )
    }

    // MARK: - Return from Idle

    /// Process everything that happens when user returns after being away
    /// - Decay energy and hunger
    /// - Regenerate hearts
    /// - Calculate idle XP
    /// - Update mood
    /// - Show welcome back screen
    public func processReturnFromIdle() {
        guard let appState = appState else { return }
        guard let lastVisit = appState.lastVisit else {
            // First visit, nothing to process
            idleXPEarned = 0
            idleTip = IdleXPSystem.randomTip()
            return
        }

        let hoursSinceLastVisit = Date().timeIntervalSince(lastVisit) / 3600

        // Decay energy
        appState.petEnergy = PetCare.decayEnergy(current: appState.petEnergy, hoursSinceLastVisit: hoursSinceLastVisit)

        // Decay hunger
        petHunger = PetCare.decayHunger(current: petHunger, hoursSinceLastVisit: hoursSinceLastVisit)

        // Regenerate hearts (calculate based on time elapsed)
        let currentHearts = HeartsSystem.currentHearts(savedHearts: hearts, lastHeartLoss: lastHeartLoss)
        hearts = currentHearts

        // Calculate idle XP
        idleXPEarned = IdleXPSystem.calculateIdleXP(hoursSinceLastVisit: hoursSinceLastVisit)
        if idleXPEarned > 0 {
            appState.addXP(idleXPEarned)
        }

        // Get a random tip
        idleTip = IdleXPSystem.randomTip()

        // Update mood
        updatePetMood(justFed: false)

        // Show welcome back only if away for 1+ hours
        showWelcomeBack = hoursSinceLastVisit >= 1.0

        print("[GameState] Processed return from idle: \(Int(hoursSinceLastVisit))h away, earned \(idleXPEarned) XP")
    }

    /// Force save to persistence
    public func forceSave() {
        GamePersistence.shared.save(self)
    }

    /// Reset in-memory game state to fresh-account defaults WITHOUT touching
    /// UserDefaults, then re-load from the (account-swapped) keys. Used on
    /// account switch so a new account doesn't inherit the previous coins/hearts.
    public func reloadFromPersistence() {
        petHunger = 80
        petMoodState = .content
        lastFeedTime = nil
        showWelcomeBack = false
        idleXPEarned = 0
        idleTip = ""
        hearts = 5
        lastHeartLoss = nil
        coins = 0
        equippedHat = "hat_none"
        equippedAccessory = nil
        equippedBackground = "bg_default"
        equippedEffect = nil
        ownedCosmetics = ["hat_none", "bg_default"]
        unlockedCompendiumEntries = []
        streakFreezes = 0
        GamePersistence.shared.load(into: self)
    }

    /// Reset all game state
    public func resetAll() {
        GamePersistence.shared.resetAll()
        petHunger = 80
        petMoodState = .content
        lastFeedTime = nil
        showWelcomeBack = false
        idleXPEarned = 0
        idleTip = ""
        hearts = 5
        lastHeartLoss = nil
        coins = 0
        equippedHat = "hat_none"
        equippedAccessory = nil
        equippedBackground = "bg_default"
        equippedEffect = nil
        ownedCosmetics = ["hat_none", "bg_default"]
        unlockedCompendiumEntries = []
        streakFreezes = 0
    }
}
