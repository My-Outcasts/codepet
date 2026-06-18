import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Expert
// ═══════════════════════════════════════════════════════════════════════════════

/// An industry expert who contributes case studies and mentor Q&A content.
struct Expert: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let role: String
    let bio: String
    let avatarColor: String   // hex color string, e.g. "#7B6BD8"
    let initials: String
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Case Study
// ═══════════════════════════════════════════════════════════════════════════════

/// A build-along case study authored by an expert, broken into chapters.
struct CaseStudy: Identifiable, Codable, Equatable {
    let id: String
    let expertId: String
    let title: String
    let icon: String          // SF Symbol name
    let color: String         // hex color string
    let tags: [String]
    let chapters: [Chapter]
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Chapter
// ═══════════════════════════════════════════════════════════════════════════════

/// A single chapter within a case study. Contains the narrative, a key takeaway,
/// and optional challenge/code snippet for hands-on learning.
struct Chapter: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let narrative: String        // multi-paragraph story text
    let keyLesson: String        // one-line takeaway
    let challenge: String?       // optional mini task for the user
    let codeSnippet: String?     // optional relevant code example
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Mentor Q&A
// ═══════════════════════════════════════════════════════════════════════════════

/// A mentor Q&A entry — a question posed to an expert with their full answer
/// and suggested follow-up questions for deeper exploration.
struct MentorQA: Identifiable, Codable, Equatable {
    let id: String
    let expertId: String
    let question: String
    let hint: String             // subtitle / teaser
    let iconName: String         // SF Symbol name
    let iconColor: String        // hex color string
    let answer: String           // expert's full answer
    let followUps: [String]      // suggested follow-up questions
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Learn Progress
// ═══════════════════════════════════════════════════════════════════════════════

/// Tracks the user's progress through Learn tab content — which chapters they've
/// completed and which Q&As they've read. Persists to UserDefaults with `cp_learn_` prefix.
class LearnProgress: ObservableObject {

    // MARK: - Published State

    @Published var completedChapterIds: Set<String> = []
    @Published var readQAIds: Set<String> = []

    // MARK: - UserDefaults Keys

    private enum Key {
        static let completedChapters = "cp_learn_completedChapters"
        static let readQAs = "cp_learn_readQAs"
        static let hasSavedBefore = "cp_learn_hasSavedBefore"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Progress Queries

    /// Number of chapters completed in a given case study.
    func completedCount(for caseStudy: CaseStudy) -> Int {
        caseStudy.chapters.filter { completedChapterIds.contains($0.id) }.count
    }

    /// Total number of chapters in a given case study.
    func totalCount(for caseStudy: CaseStudy) -> Int {
        caseStudy.chapters.count
    }

    /// Fraction of a case study completed (0.0 to 1.0).
    func progress(for caseStudy: CaseStudy) -> Double {
        let total = totalCount(for: caseStudy)
        guard total > 0 else { return 0 }
        return Double(completedCount(for: caseStudy)) / Double(total)
    }

    /// Whether every chapter in a case study has been completed.
    func isComplete(_ caseStudy: CaseStudy) -> Bool {
        completedCount(for: caseStudy) == totalCount(for: caseStudy)
    }

    // MARK: - Mutations

    func markChapterCompleted(_ chapterId: String) {
        completedChapterIds.insert(chapterId)
        save()
    }

    func markQARead(_ qaId: String) {
        readQAIds.insert(qaId)
        save()
    }

    // MARK: - Persistence

    func save() {
        defaults.set(true, forKey: Key.hasSavedBefore)
        defaults.set(Array(completedChapterIds), forKey: Key.completedChapters)
        defaults.set(Array(readQAIds), forKey: Key.readQAs)
        print("[LearnProgress] Saved — Chapters: \(completedChapterIds.count), QAs: \(readQAIds.count)")
    }

    /// Re-hydrate from the (account-swapped) UserDefaults. Clears in-memory
    /// first so a fresh account starts empty, then loads. Does NOT remove keys.
    func reload() {
        completedChapterIds = []
        readQAIds = []
        load()
    }

    func load() {
        guard defaults.bool(forKey: Key.hasSavedBefore) else {
            print("[LearnProgress] No saved data found — fresh start")
            return
        }

        let savedChapters = defaults.stringArray(forKey: Key.completedChapters) ?? []
        completedChapterIds = Set(savedChapters)

        let savedQAs = defaults.stringArray(forKey: Key.readQAs) ?? []
        readQAIds = Set(savedQAs)

        print("[LearnProgress] Loaded — Chapters: \(completedChapterIds.count), QAs: \(readQAIds.count)")
    }

    func resetAll() {
        completedChapterIds = []
        readQAIds = []

        defaults.removeObject(forKey: Key.completedChapters)
        defaults.removeObject(forKey: Key.readQAs)
        defaults.removeObject(forKey: Key.hasSavedBefore)

        print("[LearnProgress] All learn data cleared")
    }
}
