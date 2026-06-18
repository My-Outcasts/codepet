import SwiftUI
import Combine

class AppState: ObservableObject {
    // Onboarding
    @Published var onboardingComplete: Bool = false
    /// Whether the user has seen the one-time, character-narrated feature guide
    /// that auto-opens the first time they open the Profile tab after onboarding.
    /// Persisted directly to the `cp_hasSeenFeatureGuide` key — a `cp_` key, so
    /// AccountDataStore vaults it per account: a brand-new account sees the guide
    /// fresh, a returning account never gets re-nagged. Re-openable anytime from
    /// Profile → "Replay intro guide".
    @Published var hasSeenFeatureGuide: Bool = false {
        didSet {
            UserDefaults.standard.set(hasSeenFeatureGuide, forKey: "cp_hasSeenFeatureGuide")
        }
    }
    @Published var userAge: String = ""
    @Published var obWho: String = ""
    @Published var obDesire: String = ""
    @Published var obGoal: String = ""
    @Published var skillLevel: String = ""
    @Published var dailyGoalMinutes: Int = 0
    @Published var preferredLanguage: String = "javascript"
    @Published var languagePersona: LanguagePersona = .developer

    // User
    @Published var displayName: String = ""
    @Published var activeChar: String = "byte"
    @Published var userInterests: [String] = []

    // Progress
    @Published var totalXP: Int = 0
    @Published var userLevel: Int = 1
    @Published var currentTier: Int = 1
    @Published var charOutfit: Int = 1
    @Published var completedLessons: [String] = []
    @Published var completedChallenges: [String] = []

    /// Whether this account has real, user-earned progress in local storage.
    /// Used on sign-in to decide whether to pull the cloud backup: stray default
    /// keys written at launch must NOT count, or a returning user on a fresh
    /// device would skip their restore and then overwrite cloud with an empty
    /// state. Keep in sync with the fields CloudSyncService actually backs up.
    var hasMeaningfulProgress: Bool {
        totalXP > 0 || !completedLessons.isEmpty || !completedChallenges.isEmpty
    }

    // Streak
    @Published var streak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var lastVisit: Date? = nil
    @Published var weeklyStats: WeeklyStats = WeeklyStats()
    /// Set at load when a day was missed, so the game layer (which owns streak
    /// freezes) can decide whether to rescue the streak. Transient — not persisted.
    @Published var pendingStreakBreak: StreakBreak? = nil
    /// Full-screen recognition when a streak milestone is reached. Transient.
    @Published var streakMilestoneCelebration: StreakMilestoneCelebration? = nil

    // Difficulty
    @Published var difficultyLevel: String = "medium"
    @Published var performanceHistory: [PerformanceEntry] = []

    // Review / Spaced Repetition
    @Published var lessonReviewDates: [String: Date] = [:]  // skillId -> last review date
    @Published var lessonReviewCounts: [String: Int] = [:]  // skillId -> review count
    @Published var dailySnapshots: [DailySnapshot] = []

    // Daily Challenge
    @Published var dailyChallengeCompleted: Bool = false

    // UI State
    @Published var selectedTab: Tab = .reflection
    @Published var showWeeklyRecap: Bool = false
    /// Set by Skills tab to deep-link into a kingdom on the Home tab
    @Published var pendingKingdomId: Int? = nil
    /// Set by Tips tab to pre-fill a chat prompt on the Reflection tab.
    /// The Reflection chat view consumes and nils this after use.
    @Published var pendingChatPrompt: String? = nil
    /// When set, MainTabView presents the large practice-workspace modal.
    /// Exercises use this (a roomy modal) instead of the narrow companion panel.
    @Published var activeExercise: SkillChallenge? = nil
    /// When true, the Tips tab scrolls to the "Agentic coding skills" section on
    /// appear. Set by the Profile exercises card; TipsTabView consumes + resets it.
    @Published var pendingScrollToSkills: Bool = false
    /// Term id to deep-link into the Dictionary tab. Set when the user taps a
    /// highlighted glossary term in a narrative; DictionaryView opens + scrolls
    /// to it and nils this after use.
    @Published var pendingDictionaryTerm: String? = nil
    @Published var petEnergy: Int = 60
    @Published var petMood: String = "Idle"
    /// When true, Reflection tab shows the hardcoded "Sprout × Byte" demo
    /// instead of the live polling-driven UI. Toggled via Profile > Debug
    /// or launch arg `-demoMode YES`. Persists to UserDefaults key
    /// `cp_demo_mode`.
    @Published var demoModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(demoModeEnabled, forKey: "cp_demo_mode")
        }
    }

    /// UI display language. Controls demo content language and any other
    /// SwiftUI-rendered copy wired to `L10n`. Persists to UserDefaults key
    /// `cp_ui_language`. Default: Vietnamese (matches existing copy).
    @Published var uiLanguage: AppLanguage = .vi {
        didSet {
            UserDefaults.standard.set(uiLanguage.rawValue, forKey: "cp_ui_language")
        }
    }

    // Phase 5: Theme & Sound
    @Published var isDarkMode: Bool = false
    @Published var soundEnabled: Bool = false

    // Phase 5: Level-up tracking
    @Published var showLevelUp: Bool = false
    @Published var previousLevel: Int = 1

    // Tier unlock tracking
    @Published var showTierUnlock: Bool = false
    @Published var newTierNum: Int = 0

    // Skill "Leveled Up" celebration (set when a skill's exercises hit 100%).
    // Transient UI state — not persisted.
    @Published var skillCelebration: SkillCelebration? = nil

    // Per-exercise "Exercise complete!" celebration (full-screen, at root).
    @Published var exerciseCelebration: ExerciseCelebration? = nil

    // Auto-save cancellable
    private var saveCancellable: AnyCancellable?

    enum Tab: String, CaseIterable {
        case home = "Home"
        case skills = "Skills"
        case sessions = "Sessions"
        case insights = "Insights"
        case reflection = "Reflection"
        case tips = "Tips"
        case learn = "Learn"
        case dictionary = "Dictionary"
        case profile = "Profile"

        /// Localized display name for the sidebar nav label.
        func displayName(_ lang: AppLanguage) -> String {
            switch (self, lang) {
            case (.home,       .vi): return "Trang chủ"
            case (.home,       .en): return "Home"
            case (.skills,     .vi): return "Kỹ năng"
            case (.skills,     .en): return "Skills"
            case (.sessions,   .vi): return "Phiên"
            case (.sessions,   .en): return "Sessions"
            case (.insights,   .vi): return "Thống kê"
            case (.insights,   .en): return "Insights"
            case (.reflection, .vi): return "Thống kê"
            case (.reflection, .en): return "Insights"
            case (.tips,       .vi): return "Mẹo"
            case (.tips,       .en): return "Tips"
            case (.learn,      .vi): return "Học"
            case (.learn,      .en): return "Learn"
            case (.dictionary, .vi): return "Từ điển"
            case (.dictionary, .en): return "Dictionary"
            case (.profile,    .vi): return "Hồ sơ"
            case (.profile,    .en): return "Profile"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .skills: return "sparkles"
            case .sessions: return "doc.text.fill"
            case .insights: return "chart.bar.fill"
            case .reflection: return "quote.opening"
            case .tips: return "lightbulb.fill"
            case .learn: return "graduationcap.fill"
            case .dictionary: return "book.fill"
            case .profile: return "person.fill"
            }
        }
    }

    init() {
        // Load saved data
        PersistenceManager.shared.load(into: self)
        soundEnabled = false
        SoundManager.shared.isEnabled = false
        previousLevel = userLevel

        // Ensure tier progression matches completed lessons (fixes existing progress)
        syncTierToCompletedLessons()
        checkAndUpdateSnapshot()

        // Auto-save whenever any @Published property changes (debounced 2s)
        saveCancellable = objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                PersistenceManager.shared.save(self)
            }

        // DemoMode hydration: launch arg wins, else UserDefaults.
        // This runs after PersistenceManager.load so it always reflects the
        // most recent intent.
        if let demoIdx = CommandLine.arguments.firstIndex(of: "-demoMode"),
           demoIdx + 1 < CommandLine.arguments.count,
           CommandLine.arguments[demoIdx + 1].uppercased() == "YES" {
            self.demoModeEnabled = true
        } else {
            self.demoModeEnabled = UserDefaults.standard.bool(forKey: "cp_demo_mode")
        }

        // UI language hydration: read raw value from UserDefaults, fall
        // back to Vietnamese to match existing app copy.
        if let raw = UserDefaults.standard.string(forKey: "cp_ui_language"),
           let lang = AppLanguage(rawValue: raw) {
            self.uiLanguage = lang
        }

        // Feature-guide flag hydration (stored directly under cp_, not via
        // PersistenceManager). Defaults to false → guide shows for a new account.
        self.hasSeenFeatureGuide = UserDefaults.standard.bool(forKey: "cp_hasSeenFeatureGuide")
    }

    // MARK: - XP & Level Helpers

    /// Call this instead of manually setting totalXP — handles level-up detection + sound
    func addXP(_ amount: Int) {
        previousLevel = userLevel
        totalXP += amount
        userLevel = (totalXP / 100) + 1

        // Sound effect
        SoundManager.shared.playXPGain()

        // Detect level up
        if userLevel > previousLevel {
            SoundManager.shared.playLevelUp()
            showLevelUp = true
        }

        // Character outfit evolves with tier
        charOutfit = currentTier

        // Energy boost from activity
        petEnergy = min(100, petEnergy + 5)

        // Keep today's snapshot current
        checkAndUpdateSnapshot()
    }

    // MARK: - MCP Bridge Sync

    /// Merge real coding XP from the MCP server into the app.
    /// Uses a high-water mark to avoid double-counting.
    func syncFromMCP(_ bridge: MCPBridgeService) {
        guard bridge.isConnected else { return }

        let defaults = UserDefaults.standard
        let previouslyApplied = defaults.integer(forKey: "cp_mcpXPApplied")
        let currentMCPXP = bridge.totalSkillXP

        let delta = currentMCPXP - previouslyApplied
        guard delta > 0 else { return }

        // Scale MCP XP: 10 MCP XP = 1 app XP (to balance with lesson XP)
        let scaledXP = delta / 10
        if scaledXP > 0 {
            addXP(scaledXP)
        }

        // Update pet mood from daily summary
        if let summary = bridge.todaySummary, let _ = summary.petReaction {
            petMood = summary.totalCodingMinutes > 30 ? "Happy" :
                      summary.totalCodingMinutes > 0 ? "Content" : "Idle"
        }

        // Update energy from coding activity
        if let summary = bridge.todaySummary, summary.totalCodingMinutes > 30 {
            petEnergy = min(100, petEnergy + 10)
        }

        // Persist high-water mark
        defaults.set(currentMCPXP, forKey: "cp_mcpXPApplied")
        defaults.set(Date().timeIntervalSince1970, forKey: "cp_lastMCPSync")

        print("[MCP Sync] Applied \(scaledXP) XP (delta: \(delta) raw MCP XP)")
    }

    /// Silently sync currentTier to match completed lessons (called on init)
    private func syncTierToCompletedLessons() {
        for tier in GameData.skillTiers {
            let allCompleted = tier.skills.allSatisfy { completedLessons.contains($0.id) }
            if allCompleted && currentTier <= tier.id && tier.id < 4 {
                currentTier = tier.id + 1
                charOutfit = currentTier
            }
        }
    }

    /// Call after completing a lesson to check if a new tier should unlock
    func checkTierProgression() {
        let oldTier = currentTier
        for tier in GameData.skillTiers {
            let allCompleted = tier.skills.allSatisfy { completedLessons.contains($0.id) }
            if allCompleted && currentTier <= tier.id && tier.id < 4 {
                currentTier = tier.id + 1
            }
        }

        // Trigger tier unlock overlay
        if currentTier > oldTier {
            newTierNum = currentTier
            charOutfit = currentTier
            showTierUnlock = true
            SoundManager.shared.playLevelUp()
        }
    }

    // MARK: - Spaced Repetition

    /// Lessons ready for review (spaced repetition: 1d, 3d, 7d, 14d intervals)
    var lessonsReadyForReview: [String] {
        completedLessons.filter { skillId in
            guard let lastReview = lessonReviewDates[skillId] else {
                // Never reviewed — ready if completed more than 1 day ago
                return true
            }
            let reviewCount = lessonReviewCounts[skillId] ?? 0
            let interval: TimeInterval
            switch reviewCount {
            case 0: interval = 86400       // 1 day
            case 1: interval = 86400 * 3   // 3 days
            case 2: interval = 86400 * 7   // 7 days
            default: interval = 86400 * 14 // 14 days
            }
            return Date().timeIntervalSince(lastReview) >= interval
        }
    }

    /// Mark a lesson as reviewed
    func markReviewed(_ skillId: String) {
        lessonReviewDates[skillId] = Date()
        lessonReviewCounts[skillId] = (lessonReviewCounts[skillId] ?? 0) + 1
        incrementTodayReviews()
    }

    // MARK: - Daily Snapshots

    func checkAndUpdateSnapshot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let idx = dailySnapshots.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            // Update today's snapshot with current values
            dailySnapshots[idx].totalXP = totalXP
            dailySnapshots[idx].lessonsCompleted = completedLessons.count
            dailySnapshots[idx].challengesCompleted = completedChallenges.count
            dailySnapshots[idx].streak = streak
        } else {
            // Create new snapshot for today
            let snapshot = DailySnapshot(
                id: UUID(),
                date: today,
                totalXP: totalXP,
                lessonsCompleted: completedLessons.count,
                challengesCompleted: completedChallenges.count,
                streak: streak,
                reviewsDone: 0
            )
            dailySnapshots.append(snapshot)

            // Trim to 90 days
            if dailySnapshots.count > 90 {
                dailySnapshots = Array(dailySnapshots.suffix(90))
            }
        }
    }

    func incrementTodayReviews() {
        checkAndUpdateSnapshot()
        let calendar = Calendar.current
        if let idx = dailySnapshots.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: Date()) }) {
            dailySnapshots[idx].reviewsDone += 1
        }
    }

    /// Toggle dark mode with sound
    func toggleDarkMode() {
        isDarkMode.toggle()
        SoundManager.shared.playTap()
    }

    /// Toggle sound
    func toggleSound() {
        soundEnabled.toggle()
        SoundManager.shared.isEnabled = soundEnabled
        if soundEnabled {
            // Re-initialize engine when turning sound back on
            SoundManager.shared.initialize()
            SoundManager.shared.playTap()
        } else {
            SoundManager.shared.stopMusic()
        }
    }

    /// Complete daily challenge
    func completeDailyChallenge(xpReward: Int, challengeId: String) {
        guard !dailyChallengeCompleted else { return }
        dailyChallengeCompleted = true
        if !completedChallenges.contains(challengeId) {
            completedChallenges.append(challengeId)
        }
        addXP(xpReward)
        SoundManager.shared.playSuccess()
    }

    /// Force save (for manual save button in profile)
    func forceSave() {
        PersistenceManager.shared.save(self)
    }

    /// Reset all progress
    func resetProgress() {
        PersistenceManager.shared.resetAll()
        totalXP = 0
        userLevel = 1
        currentTier = 1
        streak = 0
        longestStreak = 0
        completedLessons = []
        completedChallenges = []
        dailyChallengeCompleted = false
        petEnergy = 60
        petMood = "Idle"
        weeklyStats = WeeklyStats()
        performanceHistory = []
        dailySnapshots = []
    }

    /// Reset every persisted field back to its launch default — IN MEMORY ONLY
    /// (does not touch UserDefaults). Used by `reloadFromPersistence()` so a
    /// fresh account doesn't inherit the previous account's in-memory values.
    /// UI/transient state and device prefs (dark mode, sound, language) are left
    /// alone.
    func resetInMemory() {
        onboardingComplete = false
        userAge = ""
        obWho = ""
        obDesire = ""
        obGoal = ""
        skillLevel = ""
        dailyGoalMinutes = 0
        preferredLanguage = "javascript"
        displayName = ""
        activeChar = "byte"
        userInterests = []
        totalXP = 0
        userLevel = 1
        currentTier = 1
        charOutfit = 1
        completedLessons = []
        completedChallenges = []
        streak = 0
        longestStreak = 0
        lastVisit = nil
        weeklyStats = WeeklyStats()
        difficultyLevel = "medium"
        performanceHistory = []
        lessonReviewDates = [:]
        lessonReviewCounts = [:]
        dailySnapshots = []
        dailyChallengeCompleted = false
        petEnergy = 60
        petMood = "Idle"
    }

    /// Re-hydrate from the (account-swapped) UserDefaults. Resets to defaults
    /// first so a fresh account starts clean, then loads any persisted keys.
    /// Called on account switch by ContentView after the vault swap.
    func reloadFromPersistence() {
        resetInMemory()
        PersistenceManager.shared.load(into: self)
        // Re-hydrate the per-account feature-guide flag from the swapped
        // UserDefaults (stored directly under cp_hasSeenFeatureGuide, not via
        // PersistenceManager) so a fresh account re-sees the guide and a
        // returning one doesn't.
        hasSeenFeatureGuide = UserDefaults.standard.bool(forKey: "cp_hasSeenFeatureGuide")
    }

    /// Reset onboarding only (for testing)
    func resetOnboarding() {
        onboardingComplete = false
        obWho = ""
        obDesire = ""
        obGoal = ""
        skillLevel = ""
        userAge = ""
        dailyGoalMinutes = 0
        userInterests = []
        activeChar = "byte"
        displayName = ""
        PersistenceManager.shared.save(self)
    }
}

struct WeeklyStats: Codable {
    var challengesDone: Int = 0
    var skillsLearned: Int = 0
    var xpEarned: Int = 0
}

struct PerformanceEntry: Codable {
    let score: Int
    let date: Date
    let skillId: String
}

struct DailySnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    var totalXP: Int
    var lessonsCompleted: Int
    var challengesCompleted: Int
    var streak: Int
    var reviewsDone: Int
}

/// A detected streak gap at load time. `missedDays == 1` is rescuable with a
/// single streak freeze (decided by the game layer).
struct StreakBreak: Equatable {
    let priorStreak: Int
    let missedDays: Int
}

/// Drives the full-screen streak-milestone recognition overlay.
struct StreakMilestoneCelebration: Identifiable, Equatable {
    let id = UUID()
    let day: Int
    let bonusCoins: Int
    let freezeReward: Int
    /// Display name of a cosmetic unlocked at this milestone, if any.
    let unlockedCosmetic: String?
}
