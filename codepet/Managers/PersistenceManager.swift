import Foundation

/// Saves and restores AppState to UserDefaults so progress survives app restarts.
class PersistenceManager {

    static let shared = PersistenceManager()
    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let onboardingComplete = "cp_onboardingComplete"
        static let userAge = "cp_userAge"
        static let obWho = "cp_obWho"
        static let obDesire = "cp_obDesire"
        static let obGoal = "cp_obGoal"
        static let skillLevel = "cp_skillLevel"
        static let dailyGoalMinutes = "cp_dailyGoalMinutes"
        static let preferredLanguage = "cp_preferredLanguage"
        static let languagePersona = "cp_languagePersona"
        static let displayName = "cp_displayName"
        static let activeChar = "cp_activeChar"
        static let userInterests = "cp_userInterests"
        static let totalXP = "cp_totalXP"
        static let userLevel = "cp_userLevel"
        static let currentTier = "cp_currentTier"
        static let charOutfit = "cp_charOutfit"
        static let completedLessons = "cp_completedLessons"
        static let completedChallenges = "cp_completedChallenges"
        static let streak = "cp_streak"
        static let longestStreak = "cp_longestStreak"
        static let lastVisit = "cp_lastVisit"
        static let weeklyStats = "cp_weeklyStats"
        static let difficultyLevel = "cp_difficultyLevel"
        static let performanceHistory = "cp_performanceHistory"
        static let dailyChallengeCompleted = "cp_dailyChallengeCompleted"
        static let dailyChallengeDate = "cp_dailyChallengeDate"
        static let petEnergy = "cp_petEnergy"
        static let petMood = "cp_petMood"
        static let isDarkMode = "cp_isDarkMode"
        static let soundEnabled = "cp_soundEnabled"
        static let hasSavedBefore = "cp_hasSavedBefore"
        static let lessonReviewDates = "cp_lessonReviewDates"
        static let lessonReviewCounts = "cp_lessonReviewCounts"
        static let dailySnapshots = "cp_dailySnapshots"
        static let currentUserId = "cp_currentUserId"

        // MCP Bridge sync tracking
        static let mcpXPApplied = "cp_mcpXPApplied"
        static let mcpCoinsApplied = "cp_mcpCoinsApplied"
        static let lastMCPSync = "cp_lastMCPSync"
    }

    // MARK: - Current User Tracking

    var currentUserId: String? {
        get { defaults.string(forKey: Key.currentUserId) }
        set {
            if let uid = newValue {
                defaults.set(uid, forKey: Key.currentUserId)
            } else {
                defaults.removeObject(forKey: Key.currentUserId)
            }
        }
    }

    // MARK: - Save

    func save(_ state: AppState) {
        defaults.set(true, forKey: Key.hasSavedBefore)

        // Onboarding
        defaults.set(state.onboardingComplete, forKey: Key.onboardingComplete)
        defaults.set(state.userAge, forKey: Key.userAge)
        defaults.set(state.obWho, forKey: Key.obWho)
        defaults.set(state.obDesire, forKey: Key.obDesire)
        defaults.set(state.obGoal, forKey: Key.obGoal)
        defaults.set(state.skillLevel, forKey: Key.skillLevel)
        defaults.set(state.dailyGoalMinutes, forKey: Key.dailyGoalMinutes)
        defaults.set(state.preferredLanguage, forKey: Key.preferredLanguage)
        defaults.set(state.languagePersona.rawValue, forKey: Key.languagePersona)

        // User
        defaults.set(state.displayName, forKey: Key.displayName)
        defaults.set(state.activeChar, forKey: Key.activeChar)
        defaults.set(state.userInterests, forKey: Key.userInterests)

        // Progress
        defaults.set(state.totalXP, forKey: Key.totalXP)
        defaults.set(state.userLevel, forKey: Key.userLevel)
        defaults.set(state.currentTier, forKey: Key.currentTier)
        defaults.set(state.charOutfit, forKey: Key.charOutfit)
        defaults.set(state.completedLessons, forKey: Key.completedLessons)
        defaults.set(state.completedChallenges, forKey: Key.completedChallenges)

        // Streak
        defaults.set(state.streak, forKey: Key.streak)
        defaults.set(state.longestStreak, forKey: Key.longestStreak)
        if let lastVisit = state.lastVisit {
            defaults.set(lastVisit.timeIntervalSince1970, forKey: Key.lastVisit)
        }

        // Weekly stats (encode as JSON)
        if let data = try? JSONEncoder().encode(state.weeklyStats) {
            defaults.set(data, forKey: Key.weeklyStats)
        }

        // Difficulty
        defaults.set(state.difficultyLevel, forKey: Key.difficultyLevel)
        if let data = try? JSONEncoder().encode(state.performanceHistory) {
            defaults.set(data, forKey: Key.performanceHistory)
        }

        // Daily challenge — also track the date so we reset next day
        defaults.set(state.dailyChallengeCompleted, forKey: Key.dailyChallengeCompleted)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.dailyChallengeDate)

        // Pet
        defaults.set(state.petEnergy, forKey: Key.petEnergy)
        defaults.set(state.petMood, forKey: Key.petMood)

        // Review / Spaced Repetition
        let reviewDatesEncoded = state.lessonReviewDates.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(reviewDatesEncoded) {
            defaults.set(data, forKey: Key.lessonReviewDates)
        }
        if let data = try? JSONEncoder().encode(state.lessonReviewCounts) {
            defaults.set(data, forKey: Key.lessonReviewCounts)
        }

        // Daily Snapshots
        if let data = try? JSONEncoder().encode(state.dailySnapshots) {
            defaults.set(data, forKey: Key.dailySnapshots)
        }

        // Theme & Sound
        defaults.set(state.isDarkMode, forKey: Key.isDarkMode)
        defaults.set(state.soundEnabled, forKey: Key.soundEnabled)

        print("[Persistence] Saved — XP: \(state.totalXP), Level: \(state.userLevel), Streak: \(state.streak)")
    }

    // MARK: - Load

    func load(into state: AppState) {
        guard defaults.bool(forKey: Key.hasSavedBefore) else {
            print("[Persistence] No saved data found — fresh start")
            return
        }

        // Onboarding
        state.onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)

        // If onboarding isn't complete, start fresh — don't load stale answers
        if state.onboardingComplete {
            state.userAge = defaults.string(forKey: Key.userAge) ?? ""
            state.obWho = defaults.string(forKey: Key.obWho) ?? ""
            state.obDesire = defaults.string(forKey: Key.obDesire) ?? ""
            state.obGoal = defaults.string(forKey: Key.obGoal) ?? ""
            state.skillLevel = defaults.string(forKey: Key.skillLevel) ?? ""
            state.dailyGoalMinutes = defaults.integer(forKey: Key.dailyGoalMinutes)
        }
        state.preferredLanguage = defaults.string(forKey: Key.preferredLanguage) ?? "javascript"

        // Language persona — device pref, loads regardless of onboarding state
        if let raw = defaults.string(forKey: Key.languagePersona),
           let persona = LanguagePersona(rawValue: raw) {
            state.languagePersona = persona
        }

        // User
        state.displayName = defaults.string(forKey: Key.displayName) ?? ""
        state.activeChar = defaults.string(forKey: Key.activeChar) ?? "byte"
        state.userInterests = defaults.stringArray(forKey: Key.userInterests) ?? []

        // Progress
        state.totalXP = defaults.integer(forKey: Key.totalXP)
        state.userLevel = defaults.integer(forKey: Key.userLevel)
        if state.userLevel == 0 { state.userLevel = 1 }
        state.currentTier = defaults.integer(forKey: Key.currentTier)
        if state.currentTier == 0 { state.currentTier = 1 }
        state.charOutfit = defaults.integer(forKey: Key.charOutfit)
        if state.charOutfit == 0 { state.charOutfit = 1 }
        state.completedLessons = defaults.stringArray(forKey: Key.completedLessons) ?? []
        state.completedChallenges = defaults.stringArray(forKey: Key.completedChallenges) ?? []

        // Streak
        state.streak = defaults.integer(forKey: Key.streak)
        state.longestStreak = defaults.integer(forKey: Key.longestStreak)
        let lastVisitInterval = defaults.double(forKey: Key.lastVisit)
        if lastVisitInterval > 0 {
            state.lastVisit = Date(timeIntervalSince1970: lastVisitInterval)
        }

        // Weekly stats
        if let data = defaults.data(forKey: Key.weeklyStats),
           let stats = try? JSONDecoder().decode(WeeklyStats.self, from: data) {
            state.weeklyStats = stats
        }

        // Difficulty
        state.difficultyLevel = defaults.string(forKey: Key.difficultyLevel) ?? "medium"
        if let data = defaults.data(forKey: Key.performanceHistory),
           let history = try? JSONDecoder().decode([PerformanceEntry].self, from: data) {
            state.performanceHistory = history
        }

        // Daily challenge — reset if it's a new day
        let savedDate = defaults.double(forKey: Key.dailyChallengeDate)
        if savedDate > 0 {
            let saved = Date(timeIntervalSince1970: savedDate)
            if Calendar.current.isDateInToday(saved) {
                state.dailyChallengeCompleted = defaults.bool(forKey: Key.dailyChallengeCompleted)
            } else {
                state.dailyChallengeCompleted = false // new day — reset
            }
        }

        // Pet
        state.petEnergy = defaults.integer(forKey: Key.petEnergy)
        if state.petEnergy == 0 { state.petEnergy = 60 }
        state.petMood = defaults.string(forKey: Key.petMood) ?? "Idle"

        // Theme & Sound
        state.isDarkMode = defaults.bool(forKey: Key.isDarkMode)
        state.soundEnabled = defaults.object(forKey: Key.soundEnabled) == nil ? true : defaults.bool(forKey: Key.soundEnabled)

        // Review / Spaced Repetition
        if let data = defaults.data(forKey: Key.lessonReviewDates),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            state.lessonReviewDates = decoded.mapValues { Date(timeIntervalSince1970: $0) }
        }
        if let data = defaults.data(forKey: Key.lessonReviewCounts),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            state.lessonReviewCounts = decoded
        }

        // Daily Snapshots
        if let data = defaults.data(forKey: Key.dailySnapshots),
           let snapshots = try? JSONDecoder().decode([DailySnapshot].self, from: data) {
            state.dailySnapshots = snapshots
        }

        // Streak check — if more than 1 day since last visit, reset streak
        updateStreakOnLoad(state)

        print("[Persistence] Loaded — XP: \(state.totalXP), Level: \(state.userLevel), Streak: \(state.streak)")
    }

    // MARK: - Streak Logic

    private func updateStreakOnLoad(_ state: AppState) {
        guard let last = state.lastVisit else {
            // First ever visit
            state.streak = 1
            state.lastVisit = Date()
            return
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(last) {
            // Already visited today — no change
            return
        } else if calendar.isDateInYesterday(last) {
            // Consecutive day — increment streak
            state.streak += 1
            if state.streak > state.longestStreak {
                state.longestStreak = state.streak
            }
        } else {
            // Missed one or more days. Reset to a safe default now, but record
            // the break so the game layer (which owns streak freezes) can rescue
            // a single missed day on launch (GameState.resolveStreakRescue).
            let cal = calendar
            let daysSince = cal.dateComponents([.day],
                                               from: cal.startOfDay(for: last),
                                               to: cal.startOfDay(for: Date())).day ?? 99
            state.pendingStreakBreak = StreakBreak(priorStreak: state.streak, missedDays: max(0, daysSince - 1))
            state.streak = 1
        }
        state.lastVisit = Date()
    }

    // MARK: - Reset

    func resetAll() {
        let domain = Bundle.main.bundleIdentifier ?? "com.murror.codepet"
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        print("[Persistence] All data cleared")
    }

    /// Clears all user progress keys but preserves device-level prefs (dark mode, sound)
    /// and the stored current user ID.
    func clearProgress() {
        let keysToPreserve: Set<String> = [
            Key.isDarkMode, Key.soundEnabled, Key.currentUserId, Key.languagePersona
        ]
        let progressKeys = [
            Key.onboardingComplete, Key.userAge, Key.obWho, Key.obDesire, Key.obGoal,
            Key.skillLevel, Key.dailyGoalMinutes, Key.preferredLanguage,
            Key.displayName, Key.activeChar, Key.userInterests,
            Key.totalXP, Key.userLevel, Key.currentTier, Key.charOutfit,
            Key.completedLessons, Key.completedChallenges,
            Key.streak, Key.longestStreak, Key.lastVisit,
            Key.weeklyStats, Key.difficultyLevel, Key.performanceHistory,
            Key.dailyChallengeCompleted, Key.dailyChallengeDate,
            Key.petEnergy, Key.petMood, Key.hasSavedBefore
        ]
        for key in progressKeys where !keysToPreserve.contains(key) {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        print("[Persistence] Progress cleared (device prefs preserved)")
    }
}
