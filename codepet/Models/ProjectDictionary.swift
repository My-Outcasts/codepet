import Foundation
import Combine

/// Where a stored term was seen in the user's code (client-tracked provenance,
/// rendered as the "seen in LoginView.swift · today" badge).
struct SeenRef: Codable, Equatable, Hashable {
    let file: String
    let date: Date
}

/// One generated, project-aware dictionary card plus the client-side metadata
/// the server does not own: where it was seen, its evolution stage, and when it
/// was first/last encountered. The card content fields mirror the
/// `generateDictionary` response 1:1.
struct DictionaryEntry: Codable, Equatable, Identifiable {
    // Card content (from the server)
    let term: String
    let title: String
    let topic: String
    let cardDefinition: String
    let whatItReallyMeans: String
    let analogy: String
    let codeExample: String
    let whenToUse: String
    let related: [String]
    var milestoneNote: String

    // Client-tracked provenance + progression
    var evolution: String          // "encountered" | "used" | "mastered"
    var seenIn: [SeenRef]          // most-recent first, de-duplicated by file
    var firstSeen: Date
    var lastSeen: Date
    var generatedAt: Date

    /// Spaced-retrieval state — *memory strength*, distinct from `evolution`
    /// (which tracks *usage*). Optional so entries persisted before this feature
    /// still decode; seeded on `upsert`. Drives the Due-for-review list and the
    /// recall card.
    var review: ReviewState? = nil

    /// Slug used as the stable id and the local-cache key. Mirrors the server's
    /// `termSlug` so the two never disagree about identity.
    var id: String { DictionaryEntry.slug(term) }

    static func slug(_ term: String) -> String {
        let lowered = term.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "term" : String(collapsed.prefix(60))
    }
}

/// Holds the user's generated project dictionary, keyed by term slug. Persists
/// locally via `DictionaryPersistence` (the server also caches each card in
/// `dictionary_cache`, so this store is the fast local mirror, not the source
/// of truth for cost).
@MainActor
final class ProjectDictionaryStore: ObservableObject {

    /// Generated entries keyed by `DictionaryEntry.slug(term)`.
    @Published var entries: [String: DictionaryEntry] = [:]

    /// The most recent term that leveled up *passively* — by recurring in real
    /// code rather than via a quiz. Drives the "✓ seen again in X.swift" toast.
    /// Set by `DictionaryEnricher`, cleared when the user dismisses it.
    @Published var lastPassiveRep: PassiveRep?

    struct PassiveRep: Equatable { let term: String; let file: String }

    /// Entries sorted for display: most recently seen first.
    var sortedEntries: [DictionaryEntry] {
        entries.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Entries grouped by their dynamic topic (frameworks / patterns / …).
    func entries(inTopic topic: String) -> [DictionaryEntry] {
        sortedEntries.filter { $0.topic == topic }
    }

    /// Merge or replace a generated entry, preserving the earliest firstSeen.
    func upsert(_ entry: DictionaryEntry) {
        var merged = entry
        if let existing = entries[entry.id] {
            merged.firstSeen = min(existing.firstSeen, entry.firstSeen)
            // Card regeneration must never reset spaced-retrieval progress.
            merged.review = merged.review ?? existing.review
        }
        // Seed a review schedule the first time a term enters the store.
        if merged.review == nil { merged.review = SpacedScheduler.initial() }
        entries[entry.id] = merged
    }

    // MARK: - Spaced retrieval

    /// Terms whose memory is due for an active recall card — soonest-due first,
    /// capped at the daily limit. Empty when nothing is due, so the surface
    /// hides itself.
    func dueReviewEntries(now: Date = Date()) -> [DictionaryEntry] {
        let states = entries.compactMapValues { $0.review }
        return SpacedScheduler.due(states, now: now).compactMap { entries[$0] }
    }

    /// Apply one self-graded recall rep and reschedule the term. Mutating
    /// `entries` triggers the debounced auto-save.
    func recordReview(slug: String, grade: RecallGrade, now: Date = Date()) {
        guard var entry = entries[slug], let state = entry.review else { return }
        entry.review = SpacedScheduler.advance(state, grade: grade, now: now)
        entries[slug] = entry
    }

    func resetAll() {
        entries = [:]
        lastPassiveRep = nil
    }

#if DEBUG
    /// Debug-only: make terms due *right now* so the spaced-review flow can be
    /// exercised before real schedules accrue. Seeds three sample terms if the
    /// store is empty, otherwise forces every existing term overdue.
    func debugSeedDueReviews() {
        if entries.isEmpty {
            for sample in Self.debugSamples() { entries[sample.id] = sample }
        } else {
            let past = Date().addingTimeInterval(-3600)
            for (key, var entry) in entries {
                var review = entry.review ?? SpacedScheduler.initial()
                review.dueAt = past
                entry.review = review
                entries[key] = entry
            }
        }
    }

    private static func debugSamples() -> [DictionaryEntry] {
        let now = Date()
        func make(_ term: String, _ def: String, _ file: String, box: Int) -> DictionaryEntry {
            DictionaryEntry(
                term: term, title: term, topic: "concepts",
                cardDefinition: def, whatItReallyMeans: def, analogy: "", codeExample: "",
                whenToUse: "", related: [], milestoneNote: "",
                evolution: "used",
                seenIn: [SeenRef(file: file, date: now)],
                firstSeen: now.addingTimeInterval(-6 * 86_400), lastSeen: now, generatedAt: now,
                review: ReviewState(box: box, dueAt: now.addingTimeInterval(-3600), lastReviewed: nil)
            )
        }
        return [
            make("closure", "A block of code you can pass around and run later — like handing someone instructions in an envelope.", "SplashView.swift", box: 1),
            make("optional", "A value that might be there or might be nothing — Swift makes you handle the \u{201C}nothing\u{201D} case on purpose.", "AppState.swift", box: 1),
            make("@EnvironmentObject", "Shared app state any screen can read, without passing it down by hand every time.", "CodePetApp.swift", box: 0),
        ]
    }
#endif
}
