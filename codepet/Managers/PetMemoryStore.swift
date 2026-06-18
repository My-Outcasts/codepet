import Foundation
import Combine
import os

/// Lightweight cross-session memory that the pet uses to personalize narratives.
/// Stored locally in UserDefaults — keyed by project path so each project has
/// its own memory lane.
///
/// Memory is a compact struct designed to stay under ~500 chars when serialized
/// to a prompt payload, keeping token cost low while giving the LLM enough
/// context to sound like it actually knows the user.
@MainActor
final class PetMemoryStore: ObservableObject {

    static let shared = PetMemoryStore()

    private let logger = Logger(subsystem: "app.murror.codepet", category: "PetMemory")
    private let key = "cp_pet_memory_v1"

    /// All memories keyed by resolved project path.
    @Published private(set) var memories: [String: PetMemory] = [:]

    init() {
        load()
    }

    // MARK: - Public API

    /// Get memory for a project (or a fresh empty one).
    func memory(for projectPath: String?) -> PetMemory {
        guard let p = projectPath else { return PetMemory() }
        return memories[p] ?? PetMemory()
    }

    /// Record that a session just completed. Updates stats and rolling context.
    func recordSessionEnd(
        projectPath: String?,
        sessionDate: Date,
        durationMinutes: Int,
        summary: String?,
        lesson: String?,
        filesWorkedOn: [String]
    ) {
        guard let p = projectPath, !p.isEmpty else { return }
        var mem = memories[p] ?? PetMemory()

        mem.totalSessions += 1
        mem.totalMinutes += durationMinutes
        mem.lastSessionDate = sessionDate

        // Track time-of-day pattern
        let hour = Calendar.current.component(.hour, from: sessionDate)
        mem.sessionHours.append(hour)
        if mem.sessionHours.count > 20 { mem.sessionHours.removeFirst() }

        // Track streak
        let cal = Calendar.current
        let today = cal.startOfDay(for: sessionDate)
        if let lastDay = mem.lastActiveDay {
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            if cal.isDate(lastDay, inSameDayAs: yesterday) {
                mem.currentStreak += 1
            } else if !cal.isDate(lastDay, inSameDayAs: today) {
                mem.currentStreak = 1
            }
        } else {
            mem.currentStreak = 1
        }
        mem.lastActiveDay = today
        mem.longestStreak = max(mem.longestStreak, mem.currentStreak)

        // Track longest session
        mem.longestSessionMinutes = max(mem.longestSessionMinutes, durationMinutes)

        // Rolling recent summaries (keep last 3 for the prompt)
        if let s = summary, !s.isEmpty {
            mem.recentSummaries.append(s)
            if mem.recentSummaries.count > 3 { mem.recentSummaries.removeFirst() }
        }

        // Rolling lesson highlights
        if let l = lesson, !l.isEmpty, l != "" {
            mem.recentLessons.append(l)
            if mem.recentLessons.count > 3 { mem.recentLessons.removeFirst() }
        }

        // Track frequently edited files
        for file in filesWorkedOn {
            let short = shortenPath(file)
            mem.fileFrequency[short, default: 0] += 1
        }
        // Keep only top 10 files
        if mem.fileFrequency.count > 10 {
            let sorted = mem.fileFrequency.sorted { $0.value > $1.value }
            mem.fileFrequency = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(10)))
        }

        memories[p] = mem
        save()
        logger.info("Memory updated for \(p): \(mem.totalSessions) sessions, streak \(mem.currentStreak)")
    }

    /// Compact prompt-ready string for the Cloud Function (~300-500 chars).
    func promptPayload(for projectPath: String?) -> String? {
        guard let p = projectPath else { return nil }
        guard let mem = memories[p], mem.totalSessions > 0 else { return nil }
        return mem.toPromptString()
    }

    /// Aggregated prompt across all projects. Used by Tips guidance which
    /// isn't scoped to a single project.
    func allMemoryPrompt() -> String? {
        let active = memories.filter { $0.value.totalSessions > 0 }
        guard !active.isEmpty else { return nil }
        // Return the most-used project's memory (richest context).
        let best = active.max(by: { $0.value.totalSessions < $1.value.totalSessions })
        return best?.value.toPromptString()
    }

    // MARK: - Persistence

    /// Clear all per-project pet memories. Called on account switch.
    func resetAll() {
        memories = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Re-hydrate from the (account-swapped) UserDefaults key. Clears first so a
    /// fresh account starts empty, then loads. Does NOT remove the key.
    func reload() {
        memories = [:]
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: PetMemory].self, from: data) else {
            return
        }
        memories = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func shortenPath(_ path: String) -> String {
        // Keep just the filename or last 2 components
        let components = path.split(separator: "/")
        if components.count <= 2 { return path }
        return components.suffix(2).joined(separator: "/")
    }
}

// MARK: - PetMemory model

struct PetMemory: Codable, Equatable {
    var totalSessions: Int = 0
    var totalMinutes: Int = 0
    var lastSessionDate: Date?
    var lastActiveDay: Date?
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var longestSessionMinutes: Int = 0
    var sessionHours: [Int] = []           // last 20 session start hours
    var recentSummaries: [String] = []     // last 3 session summaries
    var recentLessons: [String] = []       // last 3 lessons
    var fileFrequency: [String: Int] = [:] // file → edit count

    /// Compact string for inclusion in the LLM prompt.
    func toPromptString() -> String {
        var lines: [String] = []

        lines.append("Sessions: \(totalSessions), total \(totalMinutes) min")

        if currentStreak > 1 {
            lines.append("Current streak: \(currentStreak) days (best: \(longestStreak))")
        }

        if longestSessionMinutes > 30 {
            lines.append("Longest session: \(longestSessionMinutes) min")
        }

        // Time-of-day pattern
        if sessionHours.count >= 3 {
            let avg = sessionHours.reduce(0, +) / sessionHours.count
            let period: String
            switch avg {
            case 0..<6: period = "late night"
            case 6..<12: period = "morning"
            case 12..<17: period = "afternoon"
            case 17..<21: period = "evening"
            default: period = "late night"
            }
            lines.append("Usually codes in the \(period)")
        }

        // Gap since last session
        if let last = lastSessionDate {
            let gap = Int(Date().timeIntervalSince(last) / 3600)
            if gap > 24 {
                lines.append("Last session: \(gap / 24) day(s) ago")
            }
        }

        // Top files
        let topFiles = fileFrequency.sorted { $0.value > $1.value }.prefix(5)
        if !topFiles.isEmpty {
            let fileStr = topFiles.map { "\($0.key)(\($0.value)x)" }.joined(separator: ", ")
            lines.append("Most-edited files: \(fileStr)")
        }

        // Recent context
        if let lastSummary = recentSummaries.last {
            // Truncate to ~150 chars
            let trimmed = String(lastSummary.prefix(150))
            lines.append("Last session: \(trimmed)")
        }

        return lines.joined(separator: "\n")
    }
}
