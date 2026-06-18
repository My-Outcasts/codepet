import Foundation
import SwiftUI
import Combine

// MARK: - Skill progress tracking

/// Progress for a single agentic-coding skill tile.
/// Each skill has 5 practice slots (dots); filling all 5 marks it as mastered.
struct SkillProgress: Codable, Equatable {
    let skillId: String
    var practiceCount: Int          // 0–5
    var lastPracticedDate: Date?
    var isMastered: Bool { practiceCount >= 5 }

    /// Record one practice. Clamps at 5.
    mutating func recordPractice() {
        practiceCount = min(practiceCount + 1, 5)
        lastPracticedDate = Date()
    }
}

// MARK: - AI-generated guidance

/// Response from the generateGuidance Cloud Function.
/// Cached locally so we only call once per day.
struct GuidanceResult: Codable, Equatable {
    let headline: String
    /// Project this focus is anchored to (highlighted in the card). nil if the
    /// insight isn't tied to a specific project.
    let project: String?
    /// Section 1 — what the developer is doing well right now.
    let strength: String
    /// Section 1 — what's missing / to watch next (optional).
    let gap: String?
    /// Section 2 — the one improvement to make next.
    let move: String
    /// Focus-rotation status: "new", "continued", or "completed". Drives the
    /// small completion beat in the UI and the persisted repeat tracking.
    let status: String
    let mood: String               // NarrativeMood raw value
    let generatedAt: Date

    /// Whether this guidance is still fresh (generated today).
    var isFresh: Bool {
        Calendar.current.isDateInToday(generatedAt)
    }
}

// MARK: - Project Health action plan

/// A generated, per-section action plan (from the generatePlan Cloud Function).
/// Cached per (project + check + stage); unlike daily guidance it does not
/// expire daily — it's invalidated by a stage/brief change or manual regenerate.
struct SectionPlan: Codable, Equatable {
    struct Step: Codable, Equatable {
        let title: String
        /// The how-to. `nil` = locked (free tier; only step titles are shown).
        let detail: String?
        let doneWhen: String
    }
    let summary: String
    let steps: [Step]
    let pitfalls: [String]
    let estEffort: String
    let tier: String            // "preview" | "full"
    let lockedStepCount: Int
    let generatedAt: Date

    /// Stable cache key for a plan: project path + rule id + stage.
    static func key(projectPath: String, ruleId: String, stage: String) -> String {
        "\(projectPath)::\(ruleId)::\(stage)"
    }
}

// MARK: - Tips state

/// Central state for the Tips tab. Tracks skill progress, mastery count,
/// and the current AI-generated daily guidance.
///
/// Registered as an @EnvironmentObject in CodePetApp so all Tips views
/// can read and write progress.
///
/// Persistence: UserDefaults with `cp_tips_` prefix (Phase 5).
/// For MVP, state lives in memory and is saved/loaded via TipsPersistence.
final class TipsState: ObservableObject {

    // MARK: - Skill progress

    /// Keyed by a stable skill identifier: "{petId}_{skillIndex}" e.g. "nova_0".
    /// Each pet has 6 skills (from TipsContent.tipSkillsByPet), indexed 0–5.
    @Published var skillProgress: [String: SkillProgress] = [:]

    /// Total skills across all pets (7 pets x 6 skills = 42, but user only
    /// practices their active pet's skills). For the progress ring we count
    /// mastery within the active pet's discipline.
    var totalSkillsPerPet: Int { 6 }

    /// Count of mastered skills for the given pet.
    func masteredCount(for petId: String) -> Int {
        (0..<totalSkillsPerPet).count { index in
            let key = Self.skillKey(petId: petId, index: index)
            return skillProgress[key]?.isMastered == true
        }
    }

    /// Get or create progress for a specific skill.
    func progress(for petId: String, index: Int) -> SkillProgress {
        let key = Self.skillKey(petId: petId, index: index)
        return skillProgress[key] ?? SkillProgress(skillId: key, practiceCount: 0)
    }

    /// Record a practice for a skill and publish the change.
    func recordPractice(for petId: String, index: Int) {
        let key = Self.skillKey(petId: petId, index: index)
        var current = skillProgress[key] ?? SkillProgress(skillId: key, practiceCount: 0)
        current.recordPractice()
        skillProgress[key] = current
    }

    // MARK: - AI guidance

    /// The current daily guidance from the Cloud Function.
    /// nil means not yet fetched or not available.
    @Published var currentGuidance: GuidanceResult?

    /// How many times the current focus has been kept on the same project
    /// without the user acting on it. Used as a fallback so the coach rotates
    /// to another project instead of nagging forever. Persisted.
    @Published var focusRepeatCount: Int = 0

    /// Whether guidance is currently being fetched.
    @Published var isLoadingGuidance: Bool = false

    /// Last error from a failed guidance fetch, for UI display.
    @Published var guidanceError: String? = nil

    /// IDs of guidance the user has dismissed ("Not now").
    /// Keyed by the date string (yyyy-MM-dd) so dismissals reset daily.
    @Published var dismissedGuidanceDates: Set<String> = []

    // MARK: - Project Health plans

    /// Generated action plans, keyed by `SectionPlan.key(projectPath:ruleId:stage:)`.
    /// Cached so revisiting a section doesn't regenerate; persisted across launches.
    @Published var plansByKey: [String: SectionPlan] = [:]

    /// Whether today's guidance has been dismissed.
    var isGuidanceDismissed: Bool {
        dismissedGuidanceDates.contains(Self.todayKey)
    }

    /// Dismiss the current guidance for today.
    func dismissGuidance() {
        dismissedGuidanceDates.insert(Self.todayKey)
    }

    /// Whether we need to fetch fresh guidance (no cached result for today).
    var needsGuidanceFetch: Bool {
        guard let guidance = currentGuidance else { return true }
        return !guidance.isFresh
    }

    // MARK: - Setup section state

    /// Which setup actions the user has completed or dismissed.
    /// Keyed by "{petId}_{setupIndex}".
    @Published var completedSetupActions: Set<String> = []

    func isSetupCompleted(petId: String, index: Int) -> Bool {
        completedSetupActions.contains("\(petId)_\(index)")
    }

    func markSetupCompleted(petId: String, index: Int) {
        completedSetupActions.insert("\(petId)_\(index)")
    }

    // MARK: - Reset

    /// Clears all in-memory tips state. Used before re-populating demo data
    /// so repeated ⌥9 presses don't stack progress.
    func reset() {
        skillProgress = [:]
        currentGuidance = nil
        isLoadingGuidance = false
        guidanceError = nil
        dismissedGuidanceDates = []
        completedSetupActions = []
        plansByKey = [:]
    }

    // MARK: - Helpers

    static func skillKey(petId: String, index: Int) -> String {
        "\(petId)_\(index)"
    }

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
