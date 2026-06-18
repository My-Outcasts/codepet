import Foundation
import Combine

/// Saves and restores TipsState to UserDefaults so skill progress, guidance
/// cache, and setup completion survive app restarts.
/// Follows the same pattern as GamePersistence with cp_tips_ prefixed keys.
final class TipsPersistence {

    static let shared = TipsPersistence()
    private let defaults = UserDefaults.standard

    // MARK: - Keys (all prefixed with cp_tips_)

    private enum Key {
        static let skillProgress = "cp_tips_skillProgress"
        static let currentGuidance = "cp_tips_currentGuidance"
        static let focusRepeatCount = "cp_tips_focusRepeatCount"
        static let completedSetupActions = "cp_tips_completedSetupActions"
        static let dismissedGuidanceDates = "cp_tips_dismissedGuidanceDates"
        static let plans = "cp_tips_plans"
        static let hasSavedBefore = "cp_tips_hasSavedBefore"
    }

    // MARK: - Save

    func save(_ state: TipsState) {
        defaults.set(true, forKey: Key.hasSavedBefore)

        // Skill progress — encode the whole dictionary as JSON Data
        if let data = try? JSONEncoder().encode(state.skillProgress) {
            defaults.set(data, forKey: Key.skillProgress)
        }

        // Current guidance — encode as JSON Data (nil-safe)
        if let guidance = state.currentGuidance,
           let data = try? JSONEncoder().encode(guidance) {
            defaults.set(data, forKey: Key.currentGuidance)
        } else {
            defaults.removeObject(forKey: Key.currentGuidance)
        }

        // Focus repeat count (rotation fallback)
        defaults.set(state.focusRepeatCount, forKey: Key.focusRepeatCount)

        // Completed setup actions — Set<String> stored as [String]
        defaults.set(Array(state.completedSetupActions), forKey: Key.completedSetupActions)

        // Dismissed guidance dates — Set<String> stored as [String]
        defaults.set(Array(state.dismissedGuidanceDates), forKey: Key.dismissedGuidanceDates)

        // Project Health plans — encode the whole dictionary as JSON Data
        if state.plansByKey.isEmpty {
            defaults.removeObject(forKey: Key.plans)
        } else if let data = try? JSONEncoder().encode(state.plansByKey) {
            defaults.set(data, forKey: Key.plans)
        }

        print("[TipsPersistence] Saved — \(state.skillProgress.count) skills, guidance: \(state.currentGuidance != nil)")
    }

    // MARK: - Load

    func load(into state: TipsState) {
        guard defaults.bool(forKey: Key.hasSavedBefore) else {
            print("[TipsPersistence] No saved data found — fresh start")
            return
        }

        // Skill progress
        if let data = defaults.data(forKey: Key.skillProgress),
           let decoded = try? JSONDecoder().decode([String: SkillProgress].self, from: data) {
            state.skillProgress = decoded
        }

        // Current guidance
        if let data = defaults.data(forKey: Key.currentGuidance),
           let decoded = try? JSONDecoder().decode(GuidanceResult.self, from: data) {
            state.currentGuidance = decoded
        }

        // Focus repeat count
        state.focusRepeatCount = defaults.integer(forKey: Key.focusRepeatCount)

        // Completed setup actions
        if let array = defaults.stringArray(forKey: Key.completedSetupActions) {
            state.completedSetupActions = Set(array)
        }

        // Dismissed guidance dates
        if let array = defaults.stringArray(forKey: Key.dismissedGuidanceDates) {
            state.dismissedGuidanceDates = Set(array)
        }

        // Project Health plans
        if let data = defaults.data(forKey: Key.plans),
           let decoded = try? JSONDecoder().decode([String: SectionPlan].self, from: data) {
            state.plansByKey = decoded
        }

        let mastered = state.skillProgress.values.filter { $0.isMastered }.count
        print("[TipsPersistence] Loaded — \(state.skillProgress.count) skills (\(mastered) mastered), guidance fresh: \(state.currentGuidance?.isFresh ?? false)")
    }

    // MARK: - Auto-save

    private var cancellable: AnyCancellable?

    /// Subscribe to TipsState changes and debounce-save after 1 second of
    /// inactivity. Call once at app startup after `load(into:)`.
    func startAutoSave(_ state: TipsState) {
        cancellable = state.objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save(state)
            }
    }

    // MARK: - Reset

    func resetAll() {
        let keysToRemove = [
            Key.skillProgress,
            Key.currentGuidance,
            Key.completedSetupActions,
            Key.dismissedGuidanceDates,
            Key.plans,
            Key.hasSavedBefore
        ]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        print("[TipsPersistence] All tips data cleared")
    }
}
